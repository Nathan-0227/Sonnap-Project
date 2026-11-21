"""
一個慢的請求不能把整個後端卡住（2026-11-21）。

實機：App 一打開同時送出 /home、/game、/friends/feed…，/game、/home 等 3 秒就放棄。
量出來單獨打都在 0.4 秒內，但一起打時連 /health 都要 3.7 秒——
/friends/feed 要幫自己和每個朋友每晚各組一次 /home（3.2 秒），而它寫成 `async def`、
裡面卻全是同步的資料庫查詢，那 3 秒整個事件迴圈被它佔住，其他請求全部排隊。

修法：沒有真的在 await 的端點一律寫成 `def`，FastAPI 會把它丟到執行緒池，不擋別人。

守兩件事（壞掉時都不會報錯，只會讓 App 偶爾「連不上」）：
  【1】一個卡 1.5 秒的請求進行中，/health 照樣馬上回來
  【2】所有端點裡只有真的在 await 的才准是 async（新端點寫成 async 就會紅）
  【3】快取一次整份換掉：多個請求同時讀原始檔，拿到的心率索引前後一致
"""
import inspect
import socket
import sys
import urllib.request
import tempfile
import threading
import time
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import db  # noqa: E402
TMP = Path(tempfile.mkdtemp()) / "test_no_blocking.db"
db.DB_PATH = TMP

import main  # noqa: E402
from fastapi.routing import APIRoute  # noqa: E402
import uvicorn  # noqa: E402

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
    print(f"\n{'=' * 78}\n{title}")


db.init_db(TMP)
uid = db.create_user("Blocker", db_path=TMP)

# ═══════════════════════════════════════════════════════════════════
section("【1】一個慢的請求進行中，/health 照樣馬上回來")
SLOW = 1.5
real = db.list_friend_ids


def slow_list_friend_ids(*a, **kw):      # 模擬動態牆那 3 秒的同步工作
    time.sleep(SLOW)
    return real(*a, **kw)


# ⚠️ 要開一個真的 uvicorn、用真的 HTTP 打：TestClient 每個執行緒各開一個事件迴圈，
#    「async 端點卡住別人」在 TestClient 裡根本不會發生，這一段會永遠綠（寫這支測試時踩到）。
sock = socket.socket()
sock.bind(("127.0.0.1", 0))
PORT = sock.getsockname()[1]
sock.close()
server = uvicorn.Server(uvicorn.Config(main.app, host="127.0.0.1", port=PORT, log_level="warning"))
threading.Thread(target=server.run, daemon=True).start()
for _ in range(100):
    if server.started:
        break
    time.sleep(0.05)
BASE = f"http://127.0.0.1:{PORT}"


def http_status(path):
    with urllib.request.urlopen(BASE + path, timeout=10) as resp:
        return resp.status


db.list_friend_ids = slow_list_friend_ids
result = {}
t = threading.Thread(target=lambda: result.setdefault("feed", http_status(f"/friends/feed?user_id={uid}")))
t.start()
time.sleep(0.2)                           # 讓動態牆先開始跑
start = time.monotonic()
health = http_status("/health")
waited = time.monotonic() - start
t.join()
db.list_friend_ids = real
server.should_exit = True
check("動態牆照常回 200", result.get("feed"), 200)
check("/health 回 200", health, 200)
ok(f"⚠️ /health 沒有排在動態牆後面（< 0.5 秒，動態牆卡 {SLOW} 秒）", waited < 0.5,
   f"{waited:.2f}s")

# ═══════════════════════════════════════════════════════════════════
section("【2】只有真的在 await 的端點才准是 async")
# 加一支到這裡之前先確認它真的在等（await 網路、執行緒池…），不然它會擋住整個後端
ALLOWED_ASYNC = {"post_sleep_status"}
async_routes = sorted({r.endpoint.__name__ for r in main.app.routes
                       if isinstance(r, APIRoute) and inspect.iscoroutinefunction(r.endpoint)})
check("async 端點只有白名單裡的", async_routes, sorted(ALLOWED_ASYNC))
for name in ALLOWED_ASYNC:
    src = inspect.getsource(getattr(main, name))
    ok(f"白名單裡的 {name} 真的有 await", "await " in src)

# ═══════════════════════════════════════════════════════════════════
section("【3】快取一次整份換掉：同時讀拿到的前後一致")
ok("原始檔快取是一份 (mtime, records)", isinstance(main._STANDARD_CACHE.get("snap"), tuple))
ok("心率索引是一份 (key, times, recs)", isinstance(main._HR_INDEX.get("snap"), tuple)
   and len(main._HR_INDEX["snap"]) == 3)
src = inspect.getsource(main._hr_records_near)
ok("⚠️ 讀索引時從同一份 snap 拿 times 與 recs（不分兩次讀全域）",
   '_HR_INDEX["times"]' not in src and '_HR_INDEX["recs"]' not in src)

# ═══════════════════════════════════════════════════════════════════
print(f"\n{'=' * 78}")
if fails:
    print(f"結果：{len(fails)} 項失敗")
    for f in fails:
        print(f"  ✗ {f}")
    sys.exit(1)
print("結果：全部通過")
print("=" * 78)
