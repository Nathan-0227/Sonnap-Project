"""
守睡眠計畫的 Journey（2026-11-19，behavior/journey.py）。

═══════════════════════════════════════════════════════════════════════
守什麼（每一條壞掉都不會報錯）
═══════════════════════════════════════════════════════════════════════
【1】一站一站：第 1 站＝起點 − 30；最後一站不滿 30 只走剩下的、停在終點；跨午夜
【2】終點不比起點早（往後移）→ 不建立（API 422）
【3】連續 3 天準時才前進：沒準時從 0 重數、沒量到不打斷、永遠不退站
【4】睡眠長度由使用者自己定（不設 7 小時下限）
【5】從哪一晚開始算：白天按＝今晚、半夜按＝這一晚
【6】建議起點：最近 7 晚中間值、取到 5 分；不到 3 晚是 None
【7】整條流程走 API：前進之後 users 的目標＝下一站；**以前每晚的快照不變**；
     最後一站也 3 天準時 → done、目標留在終點
【8】舊版 App 用 PATCH 改掉目標 → 下一次同步拉回這一站（這一站就是目標）
【9】Stop：停在這一站、目標不還原；終點比起點晚 422
【10】不給 XP：game/ 不讀 Journey；刪帳號連 Journey 一起刪

    python tests/test_journey.py
"""
import os
import sys
import tempfile
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
os.environ.pop("SONNAP_DB_URL", None)

import db  # noqa: E402

TMP = Path(tempfile.mkdtemp()) / "test.db"
db.DB_PATH = TMP

import main  # noqa: E402
from behavior import journey as J  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

client = TestClient(main.app)
fails = []


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label}" + (f"  ({extra})" if extra else ""))
    if not cond:
        fails.append(label)


print("【1】一站一站")
ok("11:00 → 09:50：10:30、10:00、09:50", J.stops("11:00", "09:50") == ["10:30", "10:00", "09:50"],
   str(J.stops("11:00", "09:50")))
ok("剛好整除：11:00 → 10:00 是兩站", J.stops("11:00", "10:00") == ["10:30", "10:00"])
ok("跨午夜：00:20 → 23:40", J.stops("00:20", "23:40") == ["23:50", "23:40"],
   str(J.stops("00:20", "23:40")))
ok("就寢＝起床 − 睡眠長度（跨午夜）", J.bedtime_for("07:00", 480) == "23:00")

print("【2】往後移不建立")
ok("06:00 → 08:00 是往後 → None", J.advance_minutes("06:00", "08:00") is None)
ok("一樣 → None", J.advance_minutes("09:00", "09:00") is None)
ok("沒有站", J.stops("06:00", "08:00") == [])


def night(d, ok_):
    return {"date": d, "up_on_time": ok_}


print("【3】連續 3 天")
rows = [night("2026-10-01", True), night("2026-10-02", True), night("2026-10-03", True)]
ok("3 天準時 → 第 2 站、重新數", J.progress(rows, "2026-10-01", 3) == (1, 0, False))
rows = [night("2026-10-01", True), night("2026-10-02", False), night("2026-10-03", True),
        night("2026-10-04", True)]
ok("中間沒準時 → 從 0 重數（還在第 1 站、連 2 天）", J.progress(rows, "2026-10-01", 3) == (0, 2, False))
rows = [night("2026-10-01", True), night("2026-10-02", None), night("2026-10-03", True),
        night("2026-10-04", True)]
ok("沒量到不打斷", J.progress(rows, "2026-10-01", 3) == (1, 0, False))
rows = [night("2026-10-01", True)] * 1 + [night(f"2026-10-0{i}", True) for i in range(2, 4)] \
    + [night(f"2026-10-0{i}", False) for i in range(4, 10)]
ok("前進之後一直沒準時也不退站", J.progress(rows, "2026-10-01", 3)[0] == 1)
rows = [night("2026-09-29", True), night("2026-09-30", True), night("2026-10-01", True)]
ok("開始之前的夜晚不算", J.progress(rows, "2026-10-01", 3) == (0, 1, False))
rows = [night(f"2026-10-{i:02d}", True) for i in range(1, 7)]
ok("兩站 × 3 天 → 走完", J.progress(rows, "2026-10-01", 2) == (1, 0, True))

print("【4】睡眠長度自己定")
ok("沒有 clamp_sleep（不擋 7 小時以下）", not hasattr(J, "clamp_sleep"))

print("【5】從哪一晚開始算")
ok("白天 10:00 按 → 明天那一晚", J.first_night_for(datetime(2026, 11, 19, 10, 0)) == "2026-11-20")
ok("晚上 21:00 按 → 明天那一晚", J.first_night_for(datetime(2026, 11, 19, 21, 0)) == "2026-11-20")
ok("半夜 02:00 按 → 今天這一晚", J.first_night_for(datetime(2026, 11, 20, 2, 0)) == "2026-11-20")

print("【6】建議起點")
wake_rows = [{"date": f"2026-10-{i:02d}", "wake_at": f"2026-10-{i:02d}T{t}:00"}
             for i, t in enumerate(["10:58", "11:12", "11:03", "10:40", "11:30"], start=1)]
ok("中間值 11:03 → 11:05", J.suggested_start(wake_rows) == "11:05", str(J.suggested_start(wake_rows)))
ok("只有 2 晚 → None", J.suggested_start(wake_rows[:2]) is None)
ok("沒起床時刻的夜晚不算", J.suggested_start(wake_rows[:2] + [{"date": "2026-10-09", "wake_at": None}]) is None)

print("【7】整條流程走 API")
db.init_db(TMP)
db.seed_challenges(TMP)
uid = client.post("/users", json={"display_name": "旅人", "target_bedtime": "04:00"}).json()["user_id"]
client.patch(f"/users/{uid}", json={"target_wake": "11:00"})

res = client.post("/journey", json={"user_id": uid, "start_wake": "11:00",
                                    "end_wake": "09:50", "sleep_minutes": 420})
ok("開始 → 201", res.status_code == 201, res.text)
j = res.json()["journey"]
ok("睡眠長度照送來的存", j["sleep_minutes"] == 420)
ok("第 1 站 10:30／03:30", j["current"] == {"wake": "10:30", "bedtime": "03:30"}, str(j["current"]))
u = db.get_user(uid)
ok("目標立刻換成第 1 站", (u["target_wake"], u["target_bedtime"]) == ("10:30", "03:30"))

# 測試要能控制日期：把開始那一晚改成固定的過去日期
conn = db.connect(TMP)
conn.execute("UPDATE journeys SET first_night = '2026-10-01' WHERE user_id = ?", (uid,))
conn.commit()
conn.close()


def upload(day, wake_hhmm):
    """day 那一晚：凌晨 3 點睡；wake_hhmm 是按 Out of bed 的時刻，None＝沒按（也沒手錶）。"""
    d = datetime(2026, 10, 1) + timedelta(days=day - 1)
    body = {"user_id": uid, "lights_out_at": d.replace(hour=3).isoformat(timespec="seconds"),
            "bed_start_at": d.replace(hour=2, minute=50).isoformat(timespec="seconds")}
    if wake_hhmm:
        h, m = map(int, wake_hhmm.split(":"))
        body["bed_end_at"] = d.replace(hour=h, minute=m).isoformat(timespec="seconds")
    r = client.post("/nightly", json=body)
    assert r.status_code == 201, r.text


def state():
    return client.get(f"/journey?user_id={uid}").json()["journey"]


upload(1, "10:35")
upload(2, "10:20")
upload(3, None)            # 沒量到
upload(4, "12:00")         # 晚 90 分 → 重數
upload(5, "10:30")
upload(6, "10:40")
s = state()
ok("連 2 天 → 還在第 1 站", s["stop_index"] == 0 and s["on_time_streak"] == 2, str(s))
upload(7, "10:25")
s = state()
ok("第 3 天準時 → 第 2 站", s["stop_index"] == 1 and s["current"]["wake"] == "10:00", str(s))
u = db.get_user(uid)
ok("users 的目標＝第 2 站", (u["target_wake"], u["target_bedtime"]) == ("10:00", "03:00"),
   str((u["target_wake"], u["target_bedtime"])))
hist = {r["date"]: r for r in db.get_nightly_behavior(uid, days=3650)}
ok("那一晚的快照還是第 1 站（不改歷史）", hist["2026-10-07"]["target_wake"] == "10:30",
   str(hist["2026-10-07"]["target_wake"]))
ok("那一晚的就寢快照也還是第 1 站", hist["2026-10-07"]["target_bedtime"] == "03:30",
   str(hist["2026-10-07"]["target_bedtime"]))

upload(8, "10:05")
ok("下一晚的快照是新的一站", {r["date"]: r for r in db.get_nightly_behavior(uid, days=3650)}
   ["2026-10-08"]["target_wake"] == "10:00")
upload(9, "09:55")
upload(10, "10:10")
s = state()
ok("最後一站 09:50（只走 10 分鐘）", s["stop_index"] == 2 and s["current"]["wake"] == "09:50", str(s))
upload(11, "09:50")
upload(12, "09:40")
upload(13, "10:00")
s = state()
ok("最後一站也 3 天準時 → done", s["status"] == "done", str(s))
u = db.get_user(uid)
ok("走完目標留在終點", u["target_wake"] == "09:50" and u["target_bedtime"] == "02:50")

print("【8】這一站就是目標")
uid2 = client.post("/users", json={"display_name": "舊版", "target_bedtime": "03:00"}).json()["user_id"]
client.post("/journey", json={"user_id": uid2, "start_wake": "10:00", "end_wake": "09:00",
                              "sleep_minutes": 480})
client.patch(f"/users/{uid2}", json={"target_wake": "12:00", "target_bedtime": "05:00"})
client.get(f"/journey?user_id={uid2}")
u = db.get_user(uid2)
ok("PATCH 掉之後同步拉回第 1 站", (u["target_wake"], u["target_bedtime"]) == ("09:30", "01:30"),
   str((u["target_wake"], u["target_bedtime"])))

print("【9】Stop 與往後移")
res = client.post("/journey/stop", json={"user_id": uid2})
ok("Stop → stopped", res.status_code == 200 and res.json()["journey"]["status"] == "stopped", res.text)
client.patch(f"/users/{uid2}", json={"target_wake": "08:45"})
client.get(f"/journey?user_id={uid2}")
ok("停了之後不再拉回（可以自己改了）", db.get_user(uid2)["target_wake"] == "08:45")
res = client.post("/journey", json={"user_id": uid2, "start_wake": "06:00",
                                    "end_wake": "08:00", "sleep_minutes": 480})
res6 = client.post("/journey", json={"user_id": uid2, "start_wake": "10:00",
                                     "end_wake": "09:00", "sleep_minutes": 360})
ok("睡 6 小時也照 6 小時排（不拉到 7）", res6.status_code == 201
   and res6.json()["journey"]["sleep_minutes"] == 360
   and res6.json()["journey"]["current"]["bedtime"] == "03:30", res6.text)
client.post("/journey/stop", json={"user_id": uid2})
ok("往後移 → 422 already_there", res.status_code == 422 and "already_there" in res.text, res.text)
ok("沒有 Journey 的人 Stop → 404",
   client.post("/journey/stop", json={"user_id": client.post(
       "/users", json={"display_name": "無"}).json()["user_id"]}).status_code == 404)
res = client.get(f"/journey?user_id={uid2}").json()
ok("GET 帶建議起點與兩個常數", "suggested_start" in res and res["recommended_sleep_minutes"] == 420
   and res["step_minutes"] == 30, str(res))

print("【10】不給 XP、刪帳號一起刪")
game_src = "".join(p.read_text(encoding="utf-8") for p in (ROOT / "game").glob("*.py"))
ok("game/ 不讀 Journey", "journey" not in game_src.lower())
client.delete(f"/users/{uid}")
ok("刪帳號 → Journey 一起刪", db.get_journey(uid) is None)

print()
if fails:
    print(f"❌ {len(fails)} 條失敗：{fails}")
    sys.exit(1)
print("✅ 全部通過")
