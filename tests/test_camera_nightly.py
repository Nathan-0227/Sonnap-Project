"""
tests/test_camera_nightly.py — 攝影機資料進 DB 與 /insights 的驗收

⚠️ 全程使用**暫存資料庫**，不會碰到 data/sonnap.db（裡面是受測者個資）。

這支守的是四個**壞掉時不會報錯**的地方：

1. **低於偵測下限時必須是 null，不是 0。** 報 0 會被讀成「躺下就睡著」，
   而真值可能是 5 分鐘。這是整條路上最容易安靜地說謊的地方。
2. **camera 區塊裡不得出現任何分數欄位。** 攝影機現行可計分項目是 0 項
   （攝影機分數.md），加一個 score 就是第五代沒有引文的公式（設計紅線 2）。
3. **沒有資料時要回 None 而不是空陣列**——畫面要能說「沒有攝影機資料」，
   而不是畫出一排 0。
4. **provenance 一定要跟著每一列走。** 臥床是自述、入睡是偵測，
   少了標籤，讀的人會把自述當成攝影機量到的。

執行：python tests/test_camera_nightly.py
"""
import sys
import tempfile
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

# ⚠️ 一定要在 import main 之前換掉 DB_PATH，否則端點會寫到真的資料庫
import db
TMP = Path(tempfile.mkdtemp()) / "camera.db"
db.DB_PATH = TMP

import main
from fastapi.testclient import TestClient

client = TestClient(main.app)
fails = []


def check(label, got, want):
    ok_ = got == want
    print(f"  {'✓' if ok_ else '✗'} {label:<52} {got!r}" + ("" if ok_ else f"  期望 {want!r}"))
    if not ok_:
        fails.append(label)


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label:<52} {extra}")
    if not cond:
        fails.append(label)


db.init_db(TMP)
db.seed_challenges(TMP) if hasattr(db, "seed_challenges") else None

uid = client.post("/users", json={"display_name": "攝影機", "study_cohort": "L2"}).json()["user_id"]
other = client.post("/users", json={"display_name": "沒攝影機", "study_cohort": "L0"}).json()["user_id"]

# analyse() 的回傳格式（欄名與 tapo_sleep_onset.analyse 一致）。
ABOVE_FLOOR = {
    "csv": "20260903_020631.csv",
    "roi": None,
    "motion_threshold_pct_of_frame": 0.75,
    "bed_start_at": "2026-09-03T02:06:33",
    "bed_end_at": "2026-09-03T09:01:01",
    "time_in_bed_minutes": 414.5,
    "bed_times_provenance": "SELF_REPORTED_recording_start_stop",
    "sleep_onset_at": "2026-09-03T02:18:03",
    "sleep_onset_latency_minutes": 11.5,
    "sleep_onset_below_floor": False,
    "sleep_onset_floor_minutes": 10,
    "sleep_onset_provenance": "DETECTED_motion_density__n2_unvalidated",
    "events_total": 135,
    "events_per_hour": 19.5,
}
BELOW_FLOOR = {
    "csv": "20260908_015338.csv",
    "roi": [34, 129, 288, 231],
    "motion_threshold_pct_of_roi": 0.75,
    "bed_start_at": "2026-09-08T01:53:41",
    "bed_end_at": "2026-09-08T08:27:02",
    "time_in_bed_minutes": 393.4,
    "bed_times_provenance": "SELF_REPORTED_recording_start_stop",
    # ⚠️ 低於下限：這兩個就是 None，analyse() 刻意不給數字
    "sleep_onset_at": None,
    "sleep_onset_latency_minutes": None,
    "sleep_onset_below_floor": True,
    "sleep_onset_floor_minutes": 10,
    "sleep_onset_provenance": "DETECTED_motion_density__n2_unvalidated",
    "events_total": 102,
    "events_per_hour": 15.6,
}

print("=" * 78)
print("【1】寫入與冪等")
print("=" * 78)
db.upsert_camera_nightly(uid, "2026-09-03", ABOVE_FLOOR, db_path=TMP)
db.upsert_camera_nightly(uid, "2026-09-08", BELOW_FLOOR, db_path=TMP)
db.upsert_camera_nightly(uid, "2026-09-08", BELOW_FLOOR, db_path=TMP)   # 再跑一次
rows = db.get_camera_nightly(uid, days=30, db_path=TMP)
check("重複執行不會變成三列", len(rows), 2)
check("由舊到新排序", [r["date"] for r in rows], ["2026-09-03", "2026-09-08"])
check("ROI 存成字串", rows[1]["roi"], "34,129,288,231")
check("沒有 ROI 的那晚分母是整個畫面", rows[0]["motion_threshold_basis"], "frame")
check("有 ROI 的那晚分母是 ROI", rows[1]["motion_threshold_basis"], "roi")

print()
print("=" * 78)
print("【2】⚠️ 低於偵測下限 → null，不是 0")
print("=" * 78)
ins = client.get(f"/insights?user_id={uid}").json()
cam = ins["camera"]
hist = {h["date"]: h for h in cam["history"]}
b = hist["2026-09-08"]
check("sleep_onset_latency_minutes 是 None", b["sleep_onset_latency_minutes"], None)
check("⚠️ 絕對不能是 0（那會被讀成躺下就睡著）", b["sleep_onset_latency_minutes"] == 0, False)
check("sleep_onset_at 也是 None", b["sleep_onset_at"], None)
check("below_floor 是 True", b["sleep_onset_below_floor"], True)
check("floor 要跟著回去（畫面才寫得出「≤ N 分」）", b["sleep_onset_floor_minutes"], 10.0)
a = hist["2026-09-03"]
check("高於下限的那晚照實給數字", a["sleep_onset_latency_minutes"], 11.5)
check("而它的 below_floor 是 False（反向對照）", a["sleep_onset_below_floor"], False)
ok("回應有說明「低於下限不是 0」", "NOT zero" in cam["floor_note"], cam["floor_note"][:60])

print()
print("=" * 78)
print("【3】⚠️ camera 區塊不得有任何分數欄位")
print("=" * 78)
banned = [k for k in list(cam.keys()) + list(a.keys())
          if "score" in k.lower() or "quality" in k.lower()]
ok("沒有任何 score / quality 欄位", not banned, banned or "(無)")
ok("note 明寫不進任何分數", "never enter any score" in cam["note"])
ok("note 明寫臥床時間是自述", "SELF-REPORTED" in cam["note"])

print()
print("=" * 78)
print("【4】provenance 與「沒有資料」的表達")
print("=" * 78)
ok("每一列都帶臥床的 provenance",
   all(h["bed_times_provenance"] for h in cam["history"]))
ok("每一列都帶入睡的 provenance",
   all(h["sleep_onset_provenance"] for h in cam["history"]))
ok("臥床標成自述、入睡標成偵測（兩者分得開）",
   a["bed_times_provenance"].startswith("SELF_REPORTED")
   and a["sleep_onset_provenance"].startswith("DETECTED"))
ok("每一列都記得是哪一份錄影算的", all(h["csv_name"] for h in cam["history"]))

ins2 = client.get(f"/insights?user_id={other}").json()
check("⚠️ 沒有攝影機資料的使用者 → camera 是 None（不是空陣列）", ins2["camera"], None)

print()
print("=" * 78)
print(f"結果：{'全部通過' if not fails else f'{len(fails)} 項失敗 → {fails}'}")
print("=" * 78)
sys.exit(1 if fails else 0)
