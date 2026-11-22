"""
tests/test_login.py —— email＋密碼登入（2026-11-22，auth.py）

  【1】雜湊：每次 salt 不同、對得上才 True、壞格式 False 不丟例外、原文不在雜湊裡
  【2】設定登入：email 轉小寫去空白、太短 422、格式錯 422、只能設一次、同一個 email 不能兩個帳號
  【3】登入換回原本的 user_id；大小寫不同的 email 也認得；沒這個 email 跟密碼錯回同一句
  【4】連錯 5 次鎖 15 分鐘：鎖著時連對的密碼也不放行；過期後放行；錯 4 次再對一次就清零
  【5】改密碼要舊密碼；錯的也算進連錯；改完舊的不能用、新的能用
  【6】雜湊不出後端：GET /users/{id}、GET /users/{id}/login、登入回應都沒有 password_hash
  【7】reset_password：發臨時密碼、清掉鎖、舊密碼失效；沒這個 email 回 None；不印 user_id
  【8】刪帳號連登入一起刪（CASCADE）；MariaDB 那邊 email 有唯一索引

⚠️ 全程使用暫存資料庫。執行：python tests/test_login.py
"""
import contextlib
import io
import json
import sys
import tempfile
from datetime import datetime, timedelta
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import db
TMP = Path(tempfile.mkdtemp()) / "test_login.db"
db.DB_PATH = TMP

import auth
import db_backend
import main
import reset_password
from fastapi.testclient import TestClient

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


def code(res):
    d = res.json().get("detail")
    return d.get("code") if isinstance(d, dict) else d


def new_user(name="Sleeper"):
    return client.post("/users", json={"display_name": name}).json()["user_id"]


PW = "moonlight42"

print("【1】雜湊")
h1, h2 = auth.hash_password(PW), auth.hash_password(PW)
ok("同一個密碼兩次雜湊不一樣（salt）", h1 != h2)
ok("對的密碼 True", auth.verify_password(PW, h1))
ok("錯的密碼 False", not auth.verify_password(PW + "x", h1))
ok("原文不在雜湊裡", PW not in h1)
ok("壞格式 False 不丟例外", not auth.verify_password(PW, "garbage") and not auth.verify_password(PW, None))

print("【2】設定登入")
me = new_user("Me")
check("還沒設：has_login false", client.get(f"/users/{me}/login").json(),
      {"has_login": False, "email": None})
r = client.post(f"/users/{me}/login", json={"email": "me@x.com", "password": "short"})
check("太短 422 bad_password", (r.status_code, code(r)), (422, "bad_password"))
r = client.post(f"/users/{me}/login", json={"email": "not an email", "password": PW})
check("格式錯 422 bad_email", (r.status_code, code(r)), (422, "bad_email"))
r = client.post(f"/users/{me}/login", json={"email": "  Me@Example.COM ", "password": PW})
check("設好 201、email 小寫去空白", (r.status_code, r.json()),
      (201, {"has_login": True, "email": "me@example.com"}))
r = client.post(f"/users/{me}/login", json={"email": "other@example.com", "password": PW})
check("只能設一次 409 already_set", (r.status_code, code(r)), (409, "already_set"))
other = new_user("Other")
r = client.post(f"/users/{other}/login", json={"email": "ME@example.com", "password": PW})
check("同一個 email（大小寫不同）409 email_taken", (r.status_code, code(r)), (409, "email_taken"))
r = client.post("/users/nobody/login", json={"email": "a@b.co", "password": PW})
check("沒這個帳號 404", r.status_code, 404)

print("【3】登入")
r = client.post("/login", json={"email": "me@example.com", "password": PW})
check("換回原本的 user_id", (r.status_code, r.json().get("user_id") == me), (200, True))
check("帶暱稱", r.json().get("display_name"), "Me")
check("帶目標就寢／起床（新手機不能拿預設值蓋掉）",
      (r.json().get("target_bedtime"), r.json().get("target_wake")), ("23:30", None))
r = client.post("/login", json={"email": " ME@EXAMPLE.com", "password": PW})
check("大小寫、空白不同也認得", r.json().get("user_id") == me, True)
wrong = client.post("/login", json={"email": "me@example.com", "password": "nope-nope"})
ghost = client.post("/login", json={"email": "ghost@example.com", "password": "nope-nope"})
check("密碼錯 401", wrong.status_code, 401)
check("沒這個 email 跟密碼錯回同一句", ghost.json(), wrong.json())
db.set_login_failures(me, 0, None)

print("【4】連錯 5 次鎖 15 分鐘")
for i in range(4):
    client.post("/login", json={"email": "me@example.com", "password": "bad"})
check("錯 4 次還沒鎖", db.get_login(me)["locked_until"], None)
r = client.post("/login", json={"email": "me@example.com", "password": PW})
check("錯 4 次再對一次 → 放行並清零", (r.status_code, db.get_login(me)["failed_attempts"]), (200, 0))
for i in range(4):
    client.post("/login", json={"email": "me@example.com", "password": "bad"})
r = client.post("/login", json={"email": "me@example.com", "password": "bad"})
check("第 5 次 423 locked、15 分鐘", (r.status_code, code(r), r.json()["detail"].get("minutes")),
      (423, "locked", 15))
r = client.post("/login", json={"email": "me@example.com", "password": PW})
check("鎖著時連對的密碼也 423", r.status_code, 423)
past = (datetime.now(db.TZ_TAIPEI) - timedelta(minutes=1)).isoformat(timespec="seconds")
db.set_login_failures(me, 5, past)
r = client.post("/login", json={"email": "me@example.com", "password": "bad"})
check("鎖過期後再錯一次不會馬上又鎖（重新數）", (r.status_code, db.get_login(me)["failed_attempts"]),
      (401, 1))
r = client.post("/login", json={"email": "me@example.com", "password": PW})
check("鎖過期後對的放行", r.status_code, 200)
now = datetime(2026, 11, 22, 12, 0, tzinfo=db.TZ_TAIPEI)
check("還剩 14 分 1 秒 → 寫 15 分",
      auth.locked_minutes_left({"locked_until": "2026-11-22T12:14:01+08:00"}, now), 15)
check("沒鎖 → 0", auth.locked_minutes_left({"locked_until": None}, now), 0)

print("【5】改密碼")
NEW = "sunrise-2026"
r = client.post(f"/users/{me}/password", json={"old_password": "bad", "new_password": NEW})
check("舊密碼錯 401", (r.status_code, code(r)), (401, "wrong"))
check("錯的也算進連錯", db.get_login(me)["failed_attempts"], 1)
r = client.post(f"/users/{me}/password", json={"old_password": PW, "new_password": "short"})
check("新密碼太短 422", (r.status_code, code(r)), (422, "bad_password"))
r = client.post(f"/users/{me}/password", json={"old_password": PW, "new_password": NEW})
check("改好 200、清零", (r.status_code, db.get_login(me)["failed_attempts"]), (200, 0))
check("舊的不能登入",
      client.post("/login", json={"email": "me@example.com", "password": PW}).status_code, 401)
check("新的可以",
      client.post("/login", json={"email": "me@example.com", "password": NEW}).status_code, 200)
r = client.post(f"/users/{other}/password", json={"old_password": PW, "new_password": NEW})
check("沒設登入的帳號 404 no_login", (r.status_code, code(r)), (404, "no_login"))

print("【6】雜湊不出後端")
stored = db.get_login(me)["password_hash"]
bodies = [client.get(f"/users/{me}").text, client.get(f"/users/{me}/login").text,
          client.post("/login", json={"email": "me@example.com", "password": NEW}).text,
          client.post(f"/users/{me}/password", json={"old_password": NEW, "new_password": NEW}).text]
ok("反向對照：雜湊真的存在資料庫裡", stored.startswith("scrypt$"))
ok("四個回應都沒有雜湊、沒有 password_hash 欄位",
   all(stored not in b and "password_hash" not in b and "failed_attempts" not in b for b in bodies))
check("GET /users/{id} 不多出登入欄位", "email" in client.get(f"/users/{me}").json(), False)

print("【7】reset_password")
for i in range(5):
    client.post("/login", json={"email": "me@example.com", "password": "bad"})
ok("先鎖住", db.get_login(me)["locked_until"] is not None)
temp, name = reset_password.reset("ME@example.com")
check("回暱稱", name, "Me")
check("臨時密碼長度", len(temp), auth.TEMP_PASSWORD_LENGTH)
ok("臨時密碼沒有看錯的字", not set(temp) & set("0O1lI"))
check("鎖清掉", db.get_login(me)["locked_until"], None)
check("臨時密碼登得進去",
      client.post("/login", json={"email": "me@example.com", "password": temp}).status_code, 200)
check("原本的不行",
      client.post("/login", json={"email": "me@example.com", "password": NEW}).status_code, 401)
check("沒這個 email 回 None", reset_password.reset("ghost@example.com"), (None, None))
out = io.StringIO()
sys.argv = ["reset_password.py", "me@example.com"]
with contextlib.redirect_stdout(out):
    rc = reset_password.main()
check("指令成功", rc, 0)
ok("輸出有臨時密碼、沒有 user_id", "Temporary password:" in out.getvalue() and me not in out.getvalue())

print("【8】刪帳號、唯一索引")
client.delete(f"/users/{me}")
check("刪帳號連登入一起刪", db.get_login_by_email("me@example.com"), None)
r = client.post(f"/users/{other}/login", json={"email": "me@example.com", "password": PW})
check("email 空出來之後別人可以用", r.status_code, 201)
ddl = "\n".join(db_backend.mysql_ddl(db.SCHEMA))
ok("MariaDB：email 有唯一索引", "CREATE UNIQUE INDEX `idx_user_logins_email`" in ddl)
ok("MariaDB：email 是 VARCHAR（能進索引）", "`email` VARCHAR(191)" in ddl)
ok("MariaDB：原本的一般索引還是一般索引", "CREATE INDEX `idx_block_events_user_date`" in ddl)

print()
if fails:
    print(f"✗ {len(fails)} 條沒過：{fails}")
    sys.exit(1)
print("✓ 全部通過")
