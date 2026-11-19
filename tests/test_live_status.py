"""
tests/test_live_status.py —— 好友頁的即時狀態（2026-11-19）

  【1】四種狀態的判斷（純函式）：14 小時失效、Up 到 18:00、跨午夜的 past_bedtime、6 小時後回 awake
  【2】最近 7 晚放下手機：沒資料是 None 不是 0；12:00–18:00 的不算
  【3】分享設定預設關：好友一個即時欄位都看不到
  【4】打開之後：Start → asleep、Out of bed → up、Cancel → 整列刪掉
  【5】只寫準時與否：狀態照給、時刻與分鐘數拿掉
  【6】不碰 nightly_behavior、回應不帶任何人的 user_id、刪帳號一起刪、格式錯回 422

⚠️ 全程使用暫存資料庫。執行：python tests/test_live_status.py
"""
import json
import sys
import tempfile
from datetime import date, datetime
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import db
TMP = Path(tempfile.mkdtemp()) / "test_live_status.db"
db.DB_PATH = TMP

import main
from fastapi.testclient import TestClient
from social import friends, live_status

client = TestClient(main.app, raise_server_exceptions=False)
fails = []


def check(label, got, want):
    good = got == want
    print(f"  {'✓' if good else '✗'} {label:<58} {got!r}" + ("" if good else f"  期望 {want!r}"))
    if not good:
        fails.append(label)


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label:<58} {extra}")
    if not cond:
        fails.append(label)


def section(title):
    print()
    print("=" * 78)
    print(title)
    print("=" * 78)


T = datetime.fromisoformat
st = live_status.live_state

# ═══════════════════════════════════════════════════════════════════
section("【1】四種狀態")
# ═══════════════════════════════════════════════════════════════════
start = {"started_at": "2026-11-19T23:40:00", "ended_at": None}
check("按了 Start Sleep → asleep", st(start, "23:30", T("2026-11-20T01:00"))["state"], "asleep")
check("asleep 的 since 是按下的時刻", st(start, "23:30", T("2026-11-20T01:00"))["since"],
      "2026-11-19T23:40:00")
check("14 小時後失效（忘了按 Out of bed）", st(start, "23:30", T("2026-11-20T13:41"))["state"],
      "awake")
check("13 小時 59 分還算 asleep", st(start, "23:30", T("2026-11-20T13:39"))["state"], "asleep")
check("Start 在未來（手機時鐘亂掉）不算 asleep",
      st(start, "23:30", T("2026-11-19T23:00"))["state"], "awake")

ended = {"started_at": "2026-11-19T23:40:00", "ended_at": "2026-11-20T07:30:00"}
check("今天按了 Out of bed → up", st(ended, "23:30", T("2026-11-20T09:00"))["state"], "up")
check("17:59 還是 up", st(ended, "23:30", T("2026-11-20T17:59"))["state"], "up")
check("18:00 換回 awake", st(ended, "23:30", T("2026-11-20T18:00"))["state"], "awake")
check("隔天半夜過了目標 → past_bedtime（不是 up）",
      st(ended, "23:30", T("2026-11-21T00:10"))["state"], "past_bedtime")

r = st(None, "23:30", T("2026-11-20T00:10"))
check("跨午夜：目標 23:30、現在 00:10 → 過了 40 分", (r["state"], r["minutes_past_bedtime"]),
      ("past_bedtime", 40))
check("past_bedtime 的 since 是目標時刻", r["since"], "2026-11-19T23:30:00")
check("目標前 → awake", st(None, "23:30", T("2026-11-19T23:00"))["state"], "awake")
check("剛好在目標 → awake（還沒過）", st(None, "23:30", T("2026-11-19T23:30"))["state"], "awake")
check("目標後 6 小時整 → 還是 past_bedtime", st(None, "23:30", T("2026-11-20T05:30"))["state"],
      "past_bedtime")
check("目標後 6 小時多一分 → awake", st(None, "23:30", T("2026-11-20T05:31"))["state"], "awake")
check("目標 03:00、現在 02:00 → awake（不會算成過了 23 小時）",
      st(None, "03:00", T("2026-11-20T02:00"))["state"], "awake")
check("只有 past_bedtime 有分鐘數", st(start, "23:30", T("2026-11-20T01:00"))["minutes_past_bedtime"],
      None)

# ═══════════════════════════════════════════════════════════════════
section("【2】最近 7 晚放下手機")
# ═══════════════════════════════════════════════════════════════════
rows = [{"date": "2026-11-18", "lights_out_at": "2026-11-18T01:23:00+08:00"},
        {"date": "2026-11-19", "lights_out_at": "2026-11-19T14:07:00"}]
rl = live_status.recent_lights_out(rows, date(2026, 11, 19))
check("七格", len(rl), 7)
check("舊的在前、最後一格是今天", (rl[0]["date"], rl[-1]["date"]), ("2026-11-13", "2026-11-19"))
check("牆鐘時刻（不換 UTC）", rl[-2]["time"], "01:23")
check("下午的放下手機不算就寢 → None", rl[-1]["time"], None)
check("沒資料的晚上 → None 不是 0", rl[0]["time"], None)

# ═══════════════════════════════════════════════════════════════════
section("【3】–【6】端點")
# ═══════════════════════════════════════════════════════════════════
db.init_db(TMP)
db.seed_challenges(TMP)


def make_user(name):
    return client.post("/users", json={"display_name": name, "target_bedtime": "23:30"}).json()["user_id"]


alice, bob = make_user("Alice"), make_user("Bob")
code_b = client.get(f"/friends?user_id={bob}").json()["my_invite_code"]
assert client.post("/friends", json={"user_id": alice, "invite_code": code_b}).status_code == 201


def bob_as_seen():
    body = client.get(f"/friends?user_id={alice}").json()
    return next(f for f in body["friends"] if f["handle"] == code_b), body


LIVE = ("live_state", "live_since", "minutes_past_bedtime")
now = datetime.now().replace(microsecond=0)

r = client.post("/sleep-status", json={"user_id": bob, "event": "start", "at": now.isoformat()})
check("POST /sleep-status start", r.status_code, 200)
ok("回應不帶 user_id", bob not in r.text)
seen, _ = bob_as_seen()
check("【3】預設關：三個即時欄位都是 None", [seen[k] for k in LIVE], [None, None, None])
ok("【3】分享設定裡有這一項、預設關",
   any(i["key"] == "live_status" and i["enabled"] is False and i["default"] is False
       for g in client.get(f"/sharing?user_id={bob}").json()["groups"] for i in g["items"]))

client.patch("/sharing", json={"user_id": bob, "items": {"live_status": True}})
seen, body = bob_as_seen()
check("【4】打開之後 → asleep", seen["live_state"], "asleep")
check("【4】since＝按下的時刻", seen["live_since"], now.isoformat())
ok("【6】整個回應找不到 Bob 的 user_id", bob not in json.dumps(body))
ok("【4】摘要欄位剛好是白名單", tuple(seen) == friends.FRIEND_FIELDS)

client.post("/sleep-status", json={"user_id": bob, "event": "end", "at": now.isoformat()})
seen, _ = bob_as_seen()
want = "up" if now.hour < live_status.UP_UNTIL_HOUR else seen["live_state"]
check("【4】Out of bed → up（18:00 前）", seen["live_state"], want)
ok("【4】Out of bed 之後不再是 asleep", seen["live_state"] != "asleep")
check("【4】Out of bed 不清掉開始時刻",
      db.get_live_sleep_status(bob)["started_at"], now.isoformat())

client.post("/sleep-status", json={"user_id": bob, "event": "start", "at": now.isoformat()})
client.post("/sleep-status", json={"user_id": bob, "event": "cancel"})
check("【4】Cancel → 整列刪掉", db.get_live_sleep_status(bob), None)
seen, _ = bob_as_seen()
ok("【4】Cancel 之後不是 asleep", seen["live_state"] in ("awake", "past_bedtime"), seen["live_state"])

client.post("/sleep-status", json={"user_id": bob, "event": "start", "at": now.isoformat()})
client.patch("/sharing", json={"user_id": bob, "time_precision": "on_time_only"})
seen, _ = bob_as_seen()
check("【5】只寫準時與否：狀態照給", seen["live_state"], "asleep")
check("【5】時刻、分鐘數、7 晚時刻拿掉",
      (seen["live_since"], seen["minutes_past_bedtime"], seen["recent_lights_out"]), (None, None, None))

check("【6】沒有寫進 nightly_behavior", db.get_nightly_behavior(bob, days=30), [])
check("【6】event 亂寫 → 422",
      client.post("/sleep-status", json={"user_id": bob, "event": "nap", "at": now.isoformat()}).status_code,
      422)
check("【6】start 沒給時刻 → 422",
      client.post("/sleep-status", json={"user_id": bob, "event": "start"}).status_code, 422)
check("【6】不認識的人 → 404",
      client.post("/sleep-status", json={"user_id": "nobody", "event": "cancel"}).status_code, 404)
client.delete(f"/users/{bob}")
check("【6】刪帳號一起刪", db.get_live_sleep_status(bob), None)

print()
if fails:
    print(f"✗ {len(fails)} 條沒過：{fails}")
    sys.exit(1)
print("✓ 全部通過")
