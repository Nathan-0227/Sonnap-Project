"""
tests/test_sleep_heart_rate.py —— 睡著期間的心率曲線（2026-11-13，早晨報告的 Heart rate 卡）

守的東西：
   【1】只取入睡 → 起床那一段；每 5 分鐘一個點、取平均
   【2】⚠️ 平均／最低／最高從那一段的原始讀數算（不是從 5 分鐘平均、也不是 avg_hr 欄位）
   【3】點太少、時刻壞掉、沒有讀數 → None（App 整張卡不畫，不畫平線）
   【4】0、負數、布林值不算讀數
   【5】/home 的 metrics.heart_rate_curve：Garmin 來源才有；Health Connect 是 null
   【6】回傳裡沒有任何判斷字眼（紅線 2）

執行：python tests/test_sleep_heart_rate.py
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
sys.path.insert(0, str(ROOT / "garmin"))

import sleep_heart_rate as hr  # noqa: E402

fails = []


def check(label, got, want):
    good = got == want
    print(f"  {'✓' if good else '✗'} {label:<60} {got!r}" + ("" if good else f"  期望 {want!r}"))
    if not good:
        fails.append(label)


def recs(start, values, every_min=2):
    t0 = datetime.fromisoformat(start)
    return [{"timestamp": (t0 + timedelta(minutes=every_min * i)).isoformat(),
             "metric": "heart_rate", "value": v, "unit": "bpm"} for i, v in enumerate(values)]


START, WAKE = "2026-11-12T01:00:00+08:00", "2026-11-12T02:00:00+08:00"

print("\n【1】只取睡著那一段、每 5 分鐘一點")
# 00:50 起每 2 分鐘一筆，到 02:10：前後各有一段清醒的讀數（90）
values = [90] * 5 + [60] * 31 + [90] * 5
c = hr.heart_rate_curve(recs("2026-11-12T00:50:00+08:00", values), START, WAKE)
check("清醒的 90 不算進去", c["max"], 60)
check("第一點從入睡那一刻起算", c["points"][0]["t"], START)
check("每 5 分鐘一點（60 分鐘 → 12～13 點）", len(c["points"]) in (12, 13), True)

print("\n【2】平均／最低／最高從原始讀數算")
values = [50, 70] * 20  # 每 2 分鐘交替
c = hr.heart_rate_curve(recs(START, values), START, WAKE)
check("最低是原始讀數的 50，不是 5 分鐘平均", c["min"], 50)
check("最高是原始讀數的 70", c["max"], 70)
check("平均", c["avg"], 60)

print("\n【3】資料不夠 → None")
check("只有 10 分鐘的讀數", hr.heart_rate_curve(recs(START, [60] * 5), START, WAKE), None)
check("沒有讀數", hr.heart_rate_curve([], START, WAKE), None)
check("起床早於入睡", hr.heart_rate_curve(recs(START, [60] * 30), WAKE, START), None)
check("時刻壞掉", hr.heart_rate_curve(recs(START, [60] * 30), "nope", WAKE), None)

print("\n【4】不合理的值不算")
bad = recs(START, [60] * 30)
bad[3]["value"] = 0
bad[4]["value"] = -1
bad[5]["value"] = True
check("0、負數、布林值跳過", hr.heart_rate_curve(bad, START, WAKE)["min"], 60)

print("\n【4b】手錶動作曲線")
mv = [{"timestamp": r["timestamp"], "metric": "movement", "value": v, "unit": "arb"}
      for r, v in zip(recs(START, [0] * 60, every_min=1),
                      [0.0, 0.5, 1.2, 3.9] * 15)]
c = hr.movement_curve(mv, START, WAKE)
check("點的欄位叫 value（App 照這個讀）", sorted(c["points"][0]), ["t", "value"])
check("⚠️ 動作 0 是「沒動」，是真的值、要算進去", c["min"], 0.0)
check("留兩位小數", c["max"], 3.9)
check("心率的點也叫 value",
      sorted(hr.heart_rate_curve(recs(START, [60] * 30), START, WAKE)["points"][0]), ["t", "value"])

print("\n【5】/home")
import db  # noqa: E402

TMP = Path(tempfile.mkdtemp()) / "test_sleep_heart_rate.db"
db.DB_PATH = TMP
import main  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

db.init_db(TMP)
client = TestClient(main.app, raise_server_exceptions=False)
uid = client.post("/users", json={"display_name": "HR", "target_bedtime": "23:30"}).json()["user_id"]
records = recs(START, [55 + (i % 7) for i in range(31)]) + mv
main._garmin_records = lambda: records  # 不讀真的 Garmin 原始檔
metrics = {"duration_min": 60, "efficiency": 95, "waso_min": 0, "deep_min": 10, "rem_min": 10,
           "avg_hr": 80, "resting_hr": 50, "sleep_start_time": START, "wake_time": WAKE}
db.upsert_wearable_nightly(uid, "2026-11-12", source="garmin", metrics=metrics)
m = client.get("/home", params={"user_id": uid, "date": "2026-11-12"}).json()["metrics"]
curve = m["heart_rate_curve"]
check("Garmin 來源有曲線", curve is not None and len(curve["points"]) >= hr.MIN_POINTS, True)
check("⚠️ 平均從曲線那段算，不是 avg_hr 欄位的 80", curve["avg"] != 80 and 55 <= curve["avg"] <= 61, True)

uid2 = client.post("/users", json={"display_name": "HC", "target_bedtime": "23:30"}).json()["user_id"]
db.upsert_wearable_nightly(uid2, "2026-11-12", source="health_connect", metrics=metrics)
m2 = client.get("/home", params={"user_id": uid2, "date": "2026-11-12"}).json()["metrics"]
check("Health Connect 來源沒有曲線", m2["heart_rate_curve"], None)
check("Garmin 來源也有動作曲線", m["movement_curve"] is not None, True)
check("Health Connect 沒有動作曲線", m2["movement_curve"], None)

print("\n【6】不判斷")
text = json.dumps(curve).lower()
check("沒有 normal／high／low／good 字眼",
      any(w in text for w in ("normal", "high", "good", "poor", "elevated")), False)

print()
if fails:
    print(f"✗ {len(fails)} 項失敗：")
    for f in fails:
        print(f"   - {f}")
    sys.exit(1)
print("✓ 全部通過")
