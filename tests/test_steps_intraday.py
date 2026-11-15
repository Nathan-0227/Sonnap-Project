"""
每個鐘頭走幾步（garmin/steps_intraday.py，2026-11-15 使用者定）。

   【1】🔴 GMT → 當地時間（+8）：不差 8 小時；只留那個當地日曆日的格子
   【2】每小時：沒戴錶（none）的鐘頭是 None、有戴走 0 步是 0；整天沒資料是 None
   【3】合併只增不減；補抓只補沒資料的日子、有上限
   【4】⚠️ 429 立刻停，已經抓到的照樣存
   【5】資料庫：另一欄、存白天資料時不會被蓋掉；匯入只收本人、只寫手機帳號
   【6】/home 的 yesterday 帶 steps_hourly；history 帶每天的目標
   【7】⚠️ 不進版控：.gitignore 有它、打包檔（進版控）不帶它

執行：python tests/test_steps_intraday.py
"""
import json
import os
import sys
import tempfile
from argparse import Namespace
from datetime import date
from pathlib import Path

os.environ["ANTHROPIC_API_KEY"] = ""
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "garmin"))

import db  # noqa: E402

TMP = Path(tempfile.mkdtemp()) / "test_steps_intraday.db"
db.DB_PATH = TMP

import daily_activity as daily  # noqa: E402
import garmin_connect_fetch as fetch  # noqa: E402
import main  # noqa: E402
import migrate_garmin_to_db as migrate  # noqa: E402
import steps_intraday as si  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

client = TestClient(main.app, raise_server_exceptions=False)
fails = []


def check(label, got, want):
    good = got == want
    print(f"  {'✓' if good else '✗'} {label:<64} {got!r}" + ("" if good else f"  期望 {want!r}"))
    if not good:
        fails.append(label)


def chart(day_gmt_start="2026-11-12T16:00:00.0"):
    """get_steps_data 的形狀：當地 11-13 00:00 = GMT 11-12 16:00，96 格。"""
    from datetime import datetime, timedelta
    t0 = datetime.fromisoformat(day_gmt_start)
    out = []
    for i in range(-4, 100):  # 前後各多一點，模擬跨到別天
        st = t0 + timedelta(minutes=15 * i)
        local_h = (st + timedelta(hours=8)).hour
        if local_h < 7:
            level, steps = "sleeping", 0
        elif local_h == 9:
            level, steps = "none", 0          # 沒戴錶
        elif local_h == 14:
            level, steps = "active", 300
        else:
            level, steps = "sedentary", 10
        out.append({"startGMT": st.isoformat() + ".0",
                    "endGMT": (st + timedelta(minutes=15)).isoformat() + ".0",
                    "steps": steps, "pushes": 0, "primaryActivityLevel": level})
    return out


print("\n【1】GMT → 當地時間")
slots = si.parse_steps_chart(chart(), "2026-11-13", 8.0)
check("只留當地 11-13 的 96 格", len(slots), 96)
check("第一格是當地 00:00（GMT 16:00 + 8）", slots[0]["start"], "00:00")
check("最後一格是 23:45", slots[-1]["start"], "23:45")
check("🔴 14 點那格在當地 14:00（不是 06:00 或 22:00）",
      [s["steps"] for s in slots if s["start"] == "14:00"], [300])
check("沒抓到 → None", si.parse_steps_chart(None, "2026-11-13"), None)
check("抓到但空的 → []", si.parse_steps_chart([], "2026-11-13"), [])

print("\n【2】每小時")
h = si.hourly(slots)
check("24 格", len(h), 24)
check("14 點：4 格 × 300", h[14], 1200)
check("有戴、走 0 步（睡著）→ 0", h[3], 0)
check("⚠️ 沒戴錶（none）→ None，不是 0", h[9], None)
check("一般的鐘頭 4 × 10", h[20], 40)
check("整天沒資料 → None", si.hourly([{"start": "10:00", "steps": 0, "level": "none"}]), None)
check("沒抓到 → None", si.hourly(None), None)

print("\n【2b】每 15 分鐘的活動程度（Active time 的時間軸）")
q = si.quarters(slots)
check("96 格", len(q), 96)
check("14:00 那格＝[active, 300]", q[14 * 4], ["active", 300])
check("睡著＝sleep、久坐＝still", (q[3 * 4][0], q[20 * 4][0]), ("sleep", "still"))
check("⚠️ 沒戴錶（none）→ None，不畫成任何一種", q[9 * 4], None)
check("generic 照實標 other（不硬塞進活動或久坐）",
      si.quarters([{"start": "10:15", "steps": 50, "level": "generic"}])[41], ["other", 50])
check("highlyActive → high", si.quarters([{"start": "08:45", "steps": 852, "level": "highlyActive"}])[35],
      ["high", 852])
check("整天沒資料 → None", si.quarters([{"start": "10:00", "steps": 0, "level": "none"}]), None)

print("\n【3】合併與補抓")
m = si.merge_days({"2026-11-01": slots}, {"2026-11-01": [], "2026-11-02": None, "2026-11-13": slots})
check("空的、沒抓到的留舊的、不刪", sorted(m), ["2026-11-01", "2026-11-13"])
back = si.days_to_backfill({"2026-08-29": slots}, date(2026, 8, 28), date(2026, 9, 5),
                           already=[date(2026, 8, 30)], limit=3)
check("只補沒資料的、最舊的先、有上限", back, [date(2026, 8, 28), date(2026, 8, 31), date(2026, 9, 1)])


class FakeClient:
    def __init__(self, block_on=None):
        self.block_on, self.calls = block_on, []

    def get_steps_data(self, ds):
        self.calls.append(ds)
        if ds == self.block_on:
            raise RuntimeError("429 Too Many Requests")
        return chart()


print("\n【4】429 立刻停")
fc = FakeClient(block_on="2026-11-12")
got, stopped = fetch.fetch_steps_intraday(fc, [date(2026, 11, 13), date(2026, 11, 12), date(2026, 11, 14)],
                                          pause=0, tz_hours=8.0, sleep=lambda s: None)
check("停在被擋的那天", stopped, "2026-11-12")
check("擋下之後不再發請求", fc.calls, ["2026-11-13", "2026-11-12"])
f = Path(tempfile.mkdtemp()) / "garmin_steps_intraday.json"
fetch.run_steps_intraday(FakeClient(), [date(2026, 11, 13)],
                         Namespace(daily_since="", daily_limit=5, daily_pause=0, tz="+08:00"),
                         path=f, sleep=lambda s: None)
check("存檔、讀得回來", si.hourly(si.load(f)["2026-11-13"])[14], 1200)

print("\n【5】資料庫與匯入")
db.init_db(TMP)
phone = client.post("/users", json={"display_name": "Phone", "target_bedtime": "23:30"}).json()["user_id"]
d = Path(tempfile.mkdtemp())
daily.save({"2026-07-01": daily.parse_day({"totalSteps": 5, "activeSeconds": 5}),
            "2026-11-13": daily.parse_day({"totalSteps": 5347, "dailyStepGoal": 9540,
                                           "activeSeconds": 300})}, d / "garmin_daily_activity.json")
si.save({"2026-07-01": slots, "2026-11-13": slots}, d / "garmin_steps_intraday.json")
migrate.import_daily_activity(phone, path=d / "garmin_daily_activity.json")
r = db.get_garmin_daily(phone, "2026-11-13")
check("本人那天：每小時讀出來是 list", r["steps_hourly"][14], 1200)
check("本人那天：每 15 分鐘的程度也寫進去", r["activity_quarters"][14 * 4], ["active", 300])
check("別人戴的那天沒進來", db.get_garmin_daily(phone, "2026-07-01"), None)
db.upsert_garmin_daily(phone, "2026-11-13", daily.parse_day({"totalSteps": 6000, "activeSeconds": 300}))
r = db.get_garmin_daily(phone, "2026-11-13")
check("⚠️ 再存一次白天資料，每小時不會被蓋成 null", (r["steps"], r["steps_hourly"][14]), (6000, 1200))
check("⚠️ 每 15 分鐘的程度也不會被蓋掉", r["activity_quarters"][14 * 4], ["active", 300])
check("那天沒有白天資料那一列 → 不寫", db.set_garmin_steps_hourly(phone, "2026-01-01", [0] * 24), False)

print("\n【6】/home 的 yesterday")
y = client.get("/home", params={"user_id": phone, "date": "2026-11-14"}).json()["yesterday"]
check("steps_hourly 24 格、沒戴錶的鐘頭是 null", (len(y["steps_hourly"]), y["steps_hourly"][9]), (24, None))
check("activity_quarters 96 格、沒戴錶是 null", (len(y["activity_quarters"]), y["activity_quarters"][36]),
      (96, None))

print("\n【7】不進版控")
check(".gitignore 有它", "garmin/data/garmin_steps_intraday.json" in (ROOT / ".gitignore").read_text(encoding="utf-8"), True)
src = (ROOT / "build_app_payload.py").read_text(encoding="utf-8")
check("⚠️ 打包檔（進版控）不帶 steps_hourly", '"steps_hourly":' in src, False)
check("⚠️ 打包檔也不帶 activity_quarters", '"activity_quarters":' in src, False)
blob = json.dumps(y)
check("不寫判斷字眼", any(w in blob.lower() for w in ("reached", "achieved", "good", "poor")), False)

print()
if fails:
    print(f"✗ {len(fails)} 條沒過：", fails)
    sys.exit(1)
print("✓ 全部通過")
