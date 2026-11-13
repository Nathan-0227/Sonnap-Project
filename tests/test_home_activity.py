"""
tests/test_home_activity.py —— 首頁 Activity 卡的打包檔區塊（2026-11-13）

守的東西（都是壞掉時不會報錯的）：
   【1】那一晚（起床日）→ **前一個日曆日**的白天資料，形狀跟報告的 /home yesterday 一樣
   【2】那一天沒有白天資料 → None（首頁整張不畫，不回 0）
   【3】VO2 max 取 90 天內最近一次；超過就 None
   【4】history 只放有資料的日子、活動分鐘＝高強度＋活動
   【5】整天心率：只取那個日曆日、最低最高從原始讀數、靜止心率取那一天的；資料不夠 None
   【6】不判斷：回傳裡沒有 Normal／High／reached

執行：python tests/test_home_activity.py
"""
import json
import sys
import tempfile
from datetime import datetime, timedelta
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "garmin"))

import build_app_payload as payload  # noqa: E402
import daily_activity as daily  # noqa: E402
import sleep_heart_rate as shr  # noqa: E402

fails = []


def check(label, got, want):
    good = got == want
    print(f"  {'✓' if good else '✗'} {label:<60} {got!r}" + ("" if good else f"  期望 {want!r}"))
    if not good:
        fails.append(label)


STATS = {"totalSteps": 9955, "dailyStepGoal": 9430, "totalDistanceMeters": 6720,
         "activeKilocalories": 377, "highlyActiveSeconds": 1800, "activeSeconds": 9600,
         "sedentarySeconds": 62000, "floorsAscended": 9.4}


def hr_records(day, n=700, base=55):
    t0 = datetime.fromisoformat(f"{day}T00:00:00+08:00")
    out = [{"timestamp": (t0 + timedelta(minutes=2 * i)).isoformat(), "metric": "heart_rate",
            "value": base + (i % 30), "unit": "bpm"} for i in range(n)]
    out.append({"timestamp": f"{day}T04:00:00+08:00", "metric": "resting_heart_rate",
                "value": 59, "unit": "bpm"})
    return out


tmp = Path(tempfile.mkdtemp())
payload.GARMIN_DATA = tmp
days = {
    "2026-08-01": daily.parse_day(STATS, [{"generic": {"vo2MaxPreciseValue": 44.0}}]),  # 太舊
    "2026-10-09": daily.parse_day(STATS, [{"generic": {"vo2MaxPreciseValue": 45.7}}]),
    "2026-11-10": daily.parse_day(STATS),
    "2026-11-12": daily.parse_day(STATS, events=[]),
}
daily.save(days, tmp / "garmin_daily_activity.json")
records = hr_records("2026-11-11", 100) + hr_records("2026-11-12") + hr_records("2026-11-13", 100, base=90)
(tmp / "garmin_standard_data.json").write_text(json.dumps({"records": records}), encoding="utf-8")

print("\n【1】前一個日曆日")
a = payload.activity_block("2026-11-13")
check("那一晚 11-13 → 11-12 的白天資料", a and a["date"], "2026-11-12")
check("步數與目標照實給", (a["steps"], a["step_goal"]), (9955, 9430))
check("形狀跟報告的 yesterday 一樣（activity 分組）",
      a["activity"], {"highly_active_sec": 1800, "active_sec": 9600, "sedentary_sec": 62000})

print("\n【2】沒有白天資料 → None")
check("11-11 那天沒有白天資料", payload.activity_block("2026-11-12"), None)
check("日期壞掉", payload.activity_block("nope"), None)

print("\n【3】VO2 max 90 天內最近一次")
check("取 10-09 的 45.7", a["vo2max"], {"value": 45.7, "measured_on": "2026-10-09"})
days2 = {"2026-08-01": days["2026-08-01"], "2026-11-12": days["2026-11-12"]}
daily.save(days2, tmp / "garmin_daily_activity.json")
check("只有 08-01（超過 90 天）→ None", payload.activity_block("2026-11-13")["vo2max"], None)
daily.save(days, tmp / "garmin_daily_activity.json")

print("\n【4】history")
h = payload.activity_block("2026-11-13")["history"]
check("只放有資料的日子（14 天窗格內）", [x["date"] for x in h], ["2026-11-10", "2026-11-12"])
check("活動分鐘＝高強度＋活動", h[-1]["active_minutes"], round((1800 + 9600) / 60))

print("\n【5】整天心率")
hr = a["heart_rate"]
check("只取 11-12 那個日曆日（11-13 的 90+ 不算進來）", hr["max"] < 90, True)
check("最低最高從原始讀數", (hr["min"], hr["max"]), (55, 84))
check("靜止心率取那一天的", hr["resting"], 59)
check("每 10 分鐘一點", len(hr["points"]) <= 144 and len(hr["points"]) > 100, True)
check("點也叫 value、帶時區標記", sorted(hr["points"][0]), ["t", "value"])
check("資料不夠 → None", shr.day_heart_rate(hr_records("2026-11-12", 3), "2026-11-12"), None)

print("\n【6】不判斷")
text = json.dumps(a).lower()
check("沒有 normal／high／reached", any(w in text for w in ("normal", "\"high\"", "reached", "achieved")), False)

print()
if fails:
    print(f"✗ {len(fails)} 項失敗：")
    for f in fails:
        print(f"   - {f}")
    sys.exit(1)
print("✓ 全部通過")
