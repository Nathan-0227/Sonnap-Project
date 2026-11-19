"""
驗收：Insights 改版（2026-11-19）的 Week／Month／Year 要的三樣東西都由 /insights 帶出來。

守的是壞掉時不會報錯的地方：

1. 等級切點（quality_bands）照抄評分器的 GRADE_THRESHOLDS——App 把「這段期間的中位分數」
   換成星星與等級用，Dart 不寫任何一個數字。兩份漂移時不會有錯誤訊息
2. 沒量到 REM 的晚上 rem_minutes 與 light_minutes 都是 null，不是 0
   （畫成 0 會被讀成整晚沒有 REM；減出來的淺睡會把 REM 吃進去）
3. daily 帶出步數等白天資料，而且是輕量版（不帶 awake_hr、move_iq——一年份太慢）
4. 那些格子只讀不寫：/insights 不會改到任何一晚的分數
6. 一年份的 daily 只有 Garmin 原始檔的主人才讀那份檔（_owns_garmin_file）——
   別的帳號（示範帳號）的壓力不能是本人的

用臨時的 SQLite 資料庫跑。不需要 pytest：

    python tests/test_insights_periods.py
"""

import os
import sys
import tempfile
from datetime import date, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
os.environ.pop("SONNAP_DB_URL", None)

import db  # noqa: E402

TMP = Path(tempfile.mkdtemp()) / "test_insights_periods.db"
db.DB_PATH = TMP

import main  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

sys.path.insert(0, str(ROOT / "garmin"))
import apply_recovery_modifier  # noqa: E402
import evaluate_sleep_quality  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

client = TestClient(main.app, raise_server_exceptions=False)
FAILURES = []


def check(label, got, expected):
    ok = got == expected
    print(f"  {'✓' if ok else '✗'} {label}" + ("" if ok else f"　得到 {got!r}，預期 {expected!r}"))
    if not ok:
        FAILURES.append(label)


db.init_db(TMP)
uid = client.post("/users", json={"display_name": "Periods", "target_bedtime": "23:30"}).json()["user_id"]

today = date.today()
d1 = (today - timedelta(days=2)).isoformat()
d2 = (today - timedelta(days=1)).isoformat()
base = {"duration_min": 420.0, "deep_min": 60.0, "efficiency": 95.0, "waso_min": 10.0,
        "final_score": 82.0, "final_quality": "Good", "base_score": 80.0, "base_quality": "Good"}
db.upsert_wearable_nightly(uid, d1, "garmin", {**base, "rem_min": 90.0, "rem_measured": 1}, db_path=TMP)
db.upsert_wearable_nightly(uid, d2, "garmin", {**base, "rem_min": 0.0, "rem_measured": 0}, db_path=TMP)
db.upsert_garmin_daily(uid, d1, {"steps": 8123, "step_goal": 9000, "active_kcal": 400,
                                 "active_sec": 1800, "highly_active_sec": 600}, db_path=TMP)

r = client.get("/insights", params={"user_id": uid, "days": 365})
check("/insights 200", r.status_code, 200)
body = r.json()
w = body["wearable"]

print("【1】等級切點照抄評分器")
check("與 apply_recovery_modifier 相同",
      [(b["min"], b["quality"]) for b in w["quality_bands"]],
      [tuple(x) for x in apply_recovery_modifier.GRADE_THRESHOLDS])
check("與 evaluate_sleep_quality 相同（兩支評分器本來就要一致）",
      [(b["min"], b["quality"]) for b in w["quality_bands"]],
      [tuple(x) for x in evaluate_sleep_quality.GRADE_THRESHOLDS])

print("【2】REM／淺睡")
by = {h["date"]: h for h in w["history"]}
check("量到 REM：rem 90", by[d1]["rem_minutes"], 90.0)
check("量到 REM：淺睡＝總 − 深 − REM", by[d1]["light_minutes"], 270.0)
check("沒量到 REM：rem 是 null 不是 0", by[d2]["rem_minutes"], None)
check("沒量到 REM：淺睡也是 null", by[d2]["light_minutes"], None)

print("【3】daily")
daily = {x["date"]: x for x in body["daily"]}
check("有那一天", d1 in daily, True)
check("步數照抄", daily[d1]["steps"], 8123)
check("活動分鐘＝(active+highly)/60", daily[d1]["active_minutes"], 40)
check("輕量版不帶 awake_hr", "awake_hr" in daily[d1], False)
check("輕量版不帶 move_iq", "move_iq" in daily[d1], False)
check("沒資料的日子不放", d2 in daily, False)

print("【4】只讀")
again = client.get("/insights", params={"user_id": uid, "days": 365}).json()
check("讀兩次分數不變",
      [h["final_score"] for h in again["wearable"]["history"]],
      [h["final_score"] for h in w["history"]])

print("【5】/home 的 yesterday.history 照舊（完整版，14 天）")
h = client.get("/home", params={"user_id": uid, "date": d2}).json()
hist = ((h.get("yesterday") or {}).get("history")) or []
if hist:
    check("完整版有 awake_hr 鍵", "awake_hr" in hist[-1], True)
else:
    print("  - 那天沒有白天資料，跳過")

print("【6】原始檔只給它的主人")
_orig = main.sleep_heart_rate.stress_day_averages
main.sleep_heart_rate.stress_day_averages = lambda records: {d1: 77.0}
try:
    other = client.post("/users", json={"display_name": "Other", "target_bedtime": "23:30"}).json()["user_id"]
    db.upsert_wearable_nightly(other, d1, "health_connect", dict(base), db_path=TMP)
    db.upsert_garmin_daily(other, d1, {"steps": 5000, "step_goal": 9000}, db_path=TMP)
    mine = {x["date"]: x for x in client.get("/insights", params={"user_id": uid, "days": 365}).json()["daily"]}
    theirs = {x["date"]: x for x in client.get("/insights", params={"user_id": other, "days": 365}).json()["daily"]}
    check("主人讀得到原始檔的壓力（反向對照）", mine[d1].get("stress_avg"), 77.0)
    check("別的帳號讀不到本人的壓力", theirs[d1].get("stress_avg") == 77.0, False)
finally:
    main.sleep_heart_rate.stress_day_averages = _orig

if FAILURES:
    print(f"\n✗ {len(FAILURES)} 項失敗")
    sys.exit(1)
print("\n✓ 全部通過")
