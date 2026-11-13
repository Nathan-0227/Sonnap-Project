"""
tests/test_camera_curve.py —— 攝影機的動作曲線（2026-11-13，Sleep Stages 卡點 Camera 疊上去）

守的東西（都是壞掉時不會報錯的）：
   【1】每 5 分鐘一點＝可用的幀有幾成在動；不可用的幀不算進分母；整格沒有可用的幀就不出點
   【2】⚠️ 門檻呼叫時才讀 MOTION_THRESHOLD（不抄一份——校準改了這裡要跟著動）
   【3】⚠️ 沒有床鋪 ROI 的夜晚 → None（分母是整個畫面，同一個門檻差一個數量級）
   【4】資料庫存讀；/home 只留手錶入睡 → 起床那段；時間當牆鐘比
   【5】frame 基準的那一列、沒有手錶那一晚 → null
   【6】不進分數：評分層與遊戲層不讀

執行：python tests/test_camera_curve.py
"""
import json
import os
import sys
import tempfile
from datetime import datetime, timedelta
from pathlib import Path

os.environ["ANTHROPIC_API_KEY"] = ""
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import tapo_sleep_onset as onset  # noqa: E402

fails = []


def check(label, got, want):
    good = got == want
    print(f"  {'✓' if good else '✗'} {label:<60} {got!r}" + ("" if good else f"  期望 {want!r}"))
    if not good:
        fails.append(label)


T0 = datetime(2026, 11, 12, 1, 0, 0)
ROI = (34, 129, 288, 231)


def samples(minutes, moving_at=(), unusable_at=()):
    """每秒一幀。moving_at／unusable_at 是「第幾分鐘」的集合。"""
    out = []
    for s in range(minutes * 60):
        m = s // 60
        t = T0 + timedelta(seconds=s)
        if m in unusable_at:
            out.append((t, 0.0, False))
        else:
            out.append((t, 0.02 if m in moving_at else 0.0, True))
    return out


print("\n【1】每 5 分鐘有幾成在動")
c = onset.motion_curve(samples(60, moving_at={0, 1}), ROI, T0)
check("第一格：5 分鐘裡 2 分鐘在動 → 0.4", c["points"][0]["value"], 0.4)
check("第二格沒動 → 0", c["points"][1]["value"], 0.0)
check("一小時 12 點", len(c["points"]), 12)
check("時間是牆鐘、沒有時區標記", c["points"][0]["t"], "2026-11-12T01:00:00")
c = onset.motion_curve(samples(60, moving_at={0}, unusable_at={1, 2, 3, 4}), ROI, T0)
check("不可用的幀不算進分母：可用的 1 分鐘全在動 → 1.0", c["points"][0]["value"], 1.0)
c = onset.motion_curve(samples(60, unusable_at={0, 1, 2, 3, 4}), ROI, T0)
check("整格沒有可用的幀 → 不出點（不是 0）", c["points"][0]["t"], "2026-11-12T01:05:00")

print("\n【2】門檻呼叫時才讀")
saved = onset.MOTION_THRESHOLD
try:
    onset.MOTION_THRESHOLD = 0.05   # 0.02 不再算在動
    c = onset.motion_curve(samples(60, moving_at={0, 1}), ROI, T0)
    check("改了門檻，結果跟著變", c["points"][0]["value"], 0.0)
finally:
    onset.MOTION_THRESHOLD = saved

print("\n【3】沒有 ROI → None")
check("沒有 ROI", onset.motion_curve(samples(60, moving_at={0}), None, T0), None)
check("太短（不到 6 點）", onset.motion_curve(samples(20), ROI, T0), None)

print("\n【4】資料庫與 /home")
import db  # noqa: E402

TMP = Path(tempfile.mkdtemp()) / "test_camera_curve.db"
db.DB_PATH = TMP
import main  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

db.init_db(TMP)
client = TestClient(main.app, raise_server_exceptions=False)
uid = client.post("/users", json={"display_name": "Cam", "target_bedtime": "23:30"}).json()["user_id"]
curve = onset.motion_curve(samples(240, moving_at={30, 31, 120}), ROI, T0)  # 01:00–05:00
result = {"roi": list(ROI), "motion_threshold_pct_of_roi": 0.75,
          "bed_start_at": T0.isoformat(), "bed_end_at": (T0 + timedelta(hours=4)).isoformat(),
          "time_in_bed_minutes": 240, "events_total": 3, "events_per_hour": 0.8,
          "csv": "x.csv", "motion_curve": curve}
db.upsert_camera_nightly(uid, "2026-11-12", result)
row = db.get_camera_nightly(uid, days=5)[0]
check("存進去的是 JSON", json.loads(row["motion_curve"])["points"][0]["value"], 0.0)

main._garmin_records = lambda: []
metrics = {"duration_min": 120, "efficiency": 95, "waso_min": 0, "deep_min": 10, "rem_min": 10,
           "avg_hr": 60, "resting_hr": 50,
           # 手錶：02:00 睡著、04:00 醒來（帶時區）
           "sleep_start_time": "2026-11-12T02:00:00+08:00",
           "wake_time": "2026-11-12T04:00:00+08:00"}
db.upsert_wearable_nightly(uid, "2026-11-12", source="garmin", metrics=metrics)
cam = client.get("/home", params={"user_id": uid, "date": "2026-11-12"}).json()["metrics"]["camera_curve"]
check("只留 02:00–04:00（25 點）", len(cam["points"]), 25)
check("第一點是入睡那一刻（牆鐘比，不換 UTC）", cam["points"][0]["t"], "2026-11-12T02:00:00")
check("03:00 那格有動（第 120 分鐘）",
      [p["value"] for p in cam["points"] if p["t"] == "2026-11-12T03:00:00"], [0.2])

print("\n【5】frame 基準、沒有手錶 → null")
db.upsert_camera_nightly(uid, "2026-11-11", {**result, "roi": None, "motion_threshold_pct_of_frame": 0.75})
db.upsert_wearable_nightly(uid, "2026-11-11", source="garmin", metrics=metrics)
check("frame 基準（09-01／09-03 那種）",
      client.get("/home", params={"user_id": uid, "date": "2026-11-11"}).json()["metrics"]["camera_curve"],
      None)
uid2 = client.post("/users", json={"display_name": "NoWatch", "target_bedtime": "23:30"}).json()["user_id"]
db.upsert_camera_nightly(uid2, "2026-11-12", result)
check("沒有手錶那一晚（沒有階梯可以疊）",
      client.get("/home", params={"user_id": uid2, "date": "2026-11-12"}).json().get("metrics"), None)

print("\n【5b】回填只補曲線、不動別的欄位")
db.upsert_camera_nightly(uid, "2026-11-10", {**result, "motion_curve": None, "events_total": 99})
check("回填前沒有曲線", db.get_camera_nightly(uid, days=10)[0]["motion_curve"] is None
      if db.get_camera_nightly(uid, days=10)[0]["date"] == "2026-11-10" else
      [r for r in db.get_camera_nightly(uid, days=10) if r["date"] == "2026-11-10"][0]["motion_curve"] is None,
      True)
n = db.set_camera_motion_curve(uid, "2026-11-10", curve)
row = [r for r in db.get_camera_nightly(uid, days=10) if r["date"] == "2026-11-10"][0]
check("補上了", n == 1 and json.loads(row["motion_curve"])["bucket_minutes"] == 5, True)
check("⚠️ 其他欄位一個都沒動（事件數還是 99）", row["events_total"], 99)
check("那一晚不存在 → 0 列、不新增", db.set_camera_motion_curve(uid, "2020-01-01", curve), 0)
check("真的沒新增", any(r["date"] == "2020-01-01" for r in db.get_camera_nightly(uid, days=100)), False)

print("\n【6】不進分數")
for rel in ("garmin/evaluate_sleep_quality.py", "garmin/apply_recovery_modifier.py",
            "behavior/challenges.py", "behavior/pet_state.py"):
    text = (ROOT / rel).read_text(encoding="utf-8")
    check(f"{rel} 不讀攝影機曲線", "motion_curve" in text or "camera_curve" in text, False)

print()
if fails:
    print(f"✗ {len(fails)} 項失敗：")
    for f in fails:
        print(f"   - {f}")
    sys.exit(1)
print("✓ 全部通過")
