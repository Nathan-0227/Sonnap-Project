"""
tests/test_garmin_daily.py —— Garmin 白天資料（2026-11-13，早晨報告的「Yesterday」那一塊）

守的東西（都是壞掉時不會報錯的）：
   【1】解析：一天的四個回應 → 欄位；沒戴錶的那天是「沒有資料」不是「走了 0 步」；
        Garmin 的負數＝沒有值；Move IQ 的時長單位是分鐘、照時間排序
   【2】合併只增不減：這次沒抓到的欄位留舊的、整天沒抓到留舊的、從不刪一天
   【3】補抓：只補沒有資料的日子、最舊的先、有上限
   【4】⚠️ 429 立刻停，已經抓到的照樣存；別的錯誤只讓那一項變 None
   【5】檔案欄位與資料庫欄位一致（兩份定義，漂移不會報錯）
   【6】資料庫：存讀、Move IQ 是 list、VO2 max 找 90 天內最近一次、刪帳號一起刪
   【7】⚠️ 匯入只收本人（wearer_c）那段、只寫手機帳號；找不到手機帳號就不寫
   【8】/home 的 yesterday：前一個日曆日；沒資料整塊 null（不回 0）；VO2 max 太舊不給
   【9】⚠️ 只呈現、不計分：評分層、遊戲層、挑戰、好友都不讀；好友端點不回這些欄位
  【10】早晨匯入有帶補抓起點，起點跟戴錶者分段的本人起日一致

執行：python tests/test_garmin_daily.py
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

TMP = Path(tempfile.mkdtemp()) / "test_garmin_daily.db"
db.DB_PATH = TMP

import daily_activity as daily  # noqa: E402
import garmin_connect_fetch as fetch  # noqa: E402
import main  # noqa: E402
import migrate_garmin_to_db as migrate  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

client = TestClient(main.app, raise_server_exceptions=False)
fails = []


def check(label, got, want):
    good = got == want
    print(f"  {'✓' if good else '✗'} {label:<64} {got!r}" + ("" if good else f"  期望 {want!r}"))
    if not good:
        fails.append(label)


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label:<64} {extra}")
    if not cond:
        fails.append(label)


# 2026-11-12 實際抓到的數字（只留用得到的鍵，識別碼全拿掉）
STATS = {
    "totalSteps": 9955, "dailyStepGoal": 9430, "totalDistanceMeters": 6720,
    "activeKilocalories": 377.0, "highlyActiveSeconds": 1747, "activeSeconds": 9691,
    "sedentarySeconds": 62062, "floorsAscended": 9.42651,
    "restStressDuration": 27660, "lowStressDuration": 11340,
    "mediumStressDuration": 14880, "highStressDuration": 2100,
}
# 2026-10-09 實際抓到的形狀
MAX_METRICS = [{"generic": {"vo2MaxPreciseValue": 45.7, "vo2MaxValue": 46.0, "fitnessAge": 20}}]
EVENTS = [
    {"activityType": "walking", "duration": 18, "startTimestampLocal": "2026-10-09T17:35:00.0"},
    {"activityType": "walking", "duration": 11, "startTimestampLocal": "2026-10-09T09:54:00.0"},
    {"activityType": "cycling", "duration": 31, "startTimestampLocal": "2026-10-09T20:55:00.0"},
]
BODY_BATTERY = [{"charged": 48, "drained": 61}]

print("\n【1】解析")
row = daily.parse_day(STATS, MAX_METRICS, EVENTS, BODY_BATTERY)
check("步數", row["steps"], 9955)
check("步數目標照抄", row["step_goal"], 9430)
check("活動卡路里取整數", row["active_kcal"], 377)
check("爬樓留一位小數", row["floors_up"], 9.4)
check("高壓力秒數", row["stress_high_sec"], 2100)
check("VO2 max 取精確值", row["vo2max"], 45.7)
check("Body Battery", (row["body_battery_charged"], row["body_battery_drained"]), (48, 61))
check("Move IQ 照時間排、時長是分鐘",
      row["move_iq"],
      [{"type": "walking", "start": "09:54", "minutes": 11},
       {"type": "walking", "start": "17:35", "minutes": 18},
       {"type": "cycling", "start": "20:55", "minutes": 31}])
not_worn = daily.parse_day({"totalSteps": 0, "activeSeconds": 0, "sedentarySeconds": 0,
                            "lowStressDuration": -1})
check("⚠️ 一整天沒戴錶 → 步數是 None，不是 0", not_worn["steps"], None)
check("沒戴錶那天什麼都沒有", daily.has_any(not_worn), False)
check("Garmin 的負數＝沒有值", daily.parse_day({"totalSteps": 10, "highStressDuration": -2})
      ["stress_high_sec"], None)
check("沒抓到（None）的回應 → 那幾欄 None", daily.parse_day(STATS)["vo2max"], None)
check("Move IQ 沒抓到是 None，沒有事件是 []",
      (daily.parse_day(STATS)["move_iq"], daily.parse_day(STATS, events=[])["move_iq"]),
      (None, []))

print("\n【2】合併只增不減")
old = {"2026-11-10": daily.parse_day(STATS, MAX_METRICS),
       "2026-11-11": daily.parse_day(STATS)}
partial = daily.parse_day({**STATS, "totalSteps": 12000})  # 這次 VO2 max 沒抓到
merged, rep = daily.merge_days(old, {"2026-11-10": partial,
                                     "2026-11-11": daily.parse_day(),  # 整天沒抓到
                                     "2026-11-12": daily.parse_day(STATS)})
check("這次抓到的值蓋掉舊的", merged["2026-11-10"]["steps"], 12000)
check("⚠️ 這次沒抓到的欄位留舊的", merged["2026-11-10"]["vo2max"], 45.7)
check("⚠️ 整天沒抓到 → 留舊的那天", merged["2026-11-11"]["steps"], 9955)
check("新的日子加進來", "2026-11-12" in merged, True)
check("報告", (rep["new"], rep["updated"], rep["kept"]),
      (["2026-11-12"], ["2026-11-10"], ["2026-11-11"]))
merged2, _ = daily.merge_days(merged, {})
check("從不刪一天", sorted(merged2), sorted(merged))

print("\n【3】補抓")
have = {"2026-08-28": daily.parse_day(STATS), "2026-08-30": daily.parse_day()}
todo = daily.days_to_backfill(have, date(2026, 8, 28), date(2026, 9, 2), limit=3)
check("只補沒有資料的、最舊的先、有上限",
      [d.isoformat() for d in todo], ["2026-08-29", "2026-08-30", "2026-08-31"])
todo = daily.days_to_backfill(have, date(2026, 8, 28), date(2026, 8, 31),
                              already=[date(2026, 8, 29)])
check("這次本來就要抓的日子不重複", [d.isoformat() for d in todo], ["2026-08-30", "2026-08-31"])


class TooManyRequests(Exception):
    pass


class FakeClient:
    def __init__(self, block_on=None, broken=()):
        self.calls = []
        self.block_on = block_on
        self.broken = set(broken)

    def _call(self, name, ds):
        self.calls.append((name, ds))
        if ds == self.block_on:
            raise TooManyRequests("Mobile login returned 429")
        if name in self.broken:
            raise RuntimeError("boom")

    def get_stats(self, ds):
        self._call("stats", ds)
        return STATS

    def get_max_metrics(self, ds):
        self._call("max", ds)
        return MAX_METRICS

    def get_all_day_events(self, ds):
        self._call("events", ds)
        return EVENTS

    def get_body_battery(self, a, b):
        self._call("bb", a)
        return BODY_BATTERY


print("\n【4】429 立刻停")
days = [date(2026, 11, 10), date(2026, 11, 11), date(2026, 11, 12)]
fc = FakeClient(block_on="2026-11-11")
got, stopped = fetch.fetch_daily_activity(fc, days, pause=0, sleep=lambda s: None)
check("停在被擋的那天", stopped, "2026-11-11")
check("擋下之前抓到的照樣回傳", sorted(got), ["2026-11-10"])
check("⚠️ 擋下之後一個請求都不再發", any(ds == "2026-11-12" for _, ds in fc.calls), False)
got, stopped = fetch.fetch_daily_activity(FakeClient(broken={"max"}), days[:1], pause=0,
                                          sleep=lambda s: None)
check("別的錯誤：只有那一項變 None", (got["2026-11-10"]["vo2max"], got["2026-11-10"]["steps"]),
      (None, 9955))
check("別的錯誤不算被擋", stopped, None)

tmp_file = Path(tempfile.mkdtemp()) / "garmin_daily_activity.json"
daily.save({"2026-08-28": daily.parse_day(STATS)}, tmp_file)
args = Namespace(daily_since="2026-08-28", daily_limit=5, daily_pause=0)
fc = FakeClient(block_on="2026-08-30")
fetch.run_daily_activity(fc, [date(2026, 11, 12)], args, path=tmp_file,
                         today=date(2026, 11, 12), sleep=lambda s: None)
saved = daily.load(tmp_file)
check("被擋了也照樣存：舊的那天還在", "2026-08-28" in saved, True)
check("被擋之前補到的那天存了", "2026-08-29" in saved, True)
check("這次的日子（11-12）先抓、有存到", "2026-11-12" in saved, True)
check("被擋之後的沒有", "2026-08-31" in saved, False)

print("\n【5】檔案欄位＝資料庫欄位")
check("daily_activity.FIELDS == db.GARMIN_DAILY_FIELDS",
      tuple(daily.FIELDS), tuple(db.GARMIN_DAILY_FIELDS))

print("\n【6】資料庫")
db.init_db(TMP)
uid = client.post("/users", json={"display_name": "Daily", "target_bedtime": "23:30"}).json()["user_id"]
db.upsert_garmin_daily(uid, "2026-11-12", daily.parse_day(STATS, events=EVENTS))
r = db.get_garmin_daily(uid, "2026-11-12")
check("存讀：步數", r["steps"], 9955)
check("Move IQ 讀出來是 list", isinstance(r["move_iq"], list) and len(r["move_iq"]), 3)
db.upsert_garmin_daily(uid, "2026-10-09", daily.parse_day(STATS, MAX_METRICS))
db.upsert_garmin_daily(uid, "2026-06-01", daily.parse_day(STATS, [{"generic": {"vo2MaxPreciseValue": 40.0}}]))
check("VO2 max：90 天內最近一次",
      db.latest_vo2max(uid, "2026-11-12", "2026-08-15"), (45.7, "2026-10-09"))
check("VO2 max：窗格外的不算", db.latest_vo2max(uid, "2026-09-30", "2026-07-03"), None)

print("\n【7】匯入只收本人、只寫手機帳號")
daily_file = Path(tempfile.mkdtemp()) / "d.json"
daily.save({"2026-07-01": daily.parse_day(STATS),     # wearer_a
            "2026-08-10": daily.parse_day(STATS),     # unverified
            "2026-09-01": daily.parse_day(STATS),     # wearer_c（本人）
            "2026-09-02": daily.parse_day()}, daily_file)
phone = client.post("/users", json={"display_name": "Phone", "target_bedtime": "23:30"}).json()["user_id"]
written, skipped = migrate.import_daily_activity(phone, path=daily_file)
check("只寫本人那段有資料的日子", (written, skipped), (1, 3))
check("別人戴的那天沒進手機帳號", db.get_garmin_daily(phone, "2026-07-01"), None)
check("本人那天進來了", db.get_garmin_daily(phone, "2026-09-01")["steps"], 9955)
check("⚠️ 找不到手機帳號 → 一天都不寫", migrate.import_daily_activity(None, path=daily_file)[0], 0)

print("\n【8】/home 的 yesterday")
h = client.get("/home", params={"user_id": uid, "date": "2026-11-13"}).json()
y = h.get("yesterday")
check("前一個日曆日", y and y["date"], "2026-11-12")
check("步數與目標照實給（不判斷達標）", (y["steps"], y["step_goal"]), (9955, 9430))
check("壓力只給秒數", y["stress"], {"rest_sec": 27660, "low_sec": 11340,
                                     "medium_sec": 14880, "high_sec": 2100})
check("VO2 max：最近一次＋量到的日期", y["vo2max"], {"value": 45.7, "measured_on": "2026-10-09"})
check("Move IQ 三段", len(y["move_iq"]), 3)
check("history：最近幾天（到那一天為止），照日期排；活動分鐘＝高強度＋活動",
      [(x["date"], x["steps"]) for x in y["history"]][-1], ("2026-11-12", 9955))
check("history 不含那一天之後的", all(x["date"] <= "2026-11-12" for x in y["history"]), True)
check("history 跟打包檔同一個形狀", sorted(y["history"][-1]),
      ["active_kcal", "active_minutes", "date", "steps"])
ok("整天心率欄位在（沒有原始讀數時是 null，不回 0）", "heart_rate" in y)
ok("不給任何判斷字眼", not any(w in json.dumps(y).lower()
                               for w in ("good", "normal", "poor", "reached", "achieved")))
check("⚠️ 前一天沒資料 → 整塊 null（不回 0）",
      client.get("/home", params={"user_id": uid, "date": "2026-11-20"}).json().get("yesterday"),
      None)
db.upsert_garmin_daily(uid, "2026-11-19", daily.parse_day(STATS))
y2 = client.get("/home", params={"user_id": uid, "date": "2026-11-20"}).json()["yesterday"]
check("VO2 max 在 90 天內 → 還在", y2["vo2max"]["measured_on"], "2026-10-09")
db.upsert_garmin_daily(uid, "2027-02-01", daily.parse_day(STATS))
y3 = client.get("/home", params={"user_id": uid, "date": "2027-02-02"}).json()["yesterday"]
check("VO2 max 超過 90 天 → null", y3["vo2max"], None)

print("\n【9】只呈現、不計分")
for rel in ("garmin/evaluate_sleep_quality.py", "garmin/apply_recovery_modifier.py",
            "behavior/challenges.py", "behavior/pet_state.py", "social/friends.py"):
    text = (ROOT / rel).read_text(encoding="utf-8")
    ok(f"{rel} 不讀白天資料", "garmin_daily" not in text and "daily_activity" not in text)
for p in (ROOT / "game").glob("*.py"):
    text = p.read_text(encoding="utf-8")
    ok(f"game/{p.name} 不讀白天資料", "garmin_daily" not in text and "daily_activity" not in text)
from social import friends  # noqa: E402
ok("好友白名單沒有任何白天資料欄位",
   not set(friends.FRIEND_FIELDS) & (set(db.GARMIN_DAILY_FIELDS) | {"yesterday"}))
db.delete_user(uid)
check("刪帳號一起刪", db.get_garmin_daily(uid, "2026-11-12"), None)

print("\n【10】早晨匯入的補抓起點")
import morning_import  # noqa: E402
from apply_recovery_modifier import WEARER_SEGMENTS  # noqa: E402
check("起點＝本人那段的起日", morning_import.OWN_DATA_SINCE,
      [s for s in WEARER_SEGMENTS if s[2] == "wearer_c"][0][0])
src = (ROOT / "morning_import.py").read_text(encoding="utf-8")
ok("呼叫 fetch 時有帶 --daily-since", '"--daily-since", OWN_DATA_SINCE' in src)

print()
if fails:
    print(f"✗ {len(fails)} 項失敗：")
    for f in fails:
        print(f"   - {f}")
    sys.exit(1)
print("✓ 全部通過")
