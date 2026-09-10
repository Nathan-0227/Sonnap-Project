"""
tests/test_friends.py —— 好友（B5）的兩條紅線 + 四個端點

  【方法學】好友只看得到 Tier A 行為指標
     - 摘要欄位剛好是白名單
     - 回應裡找不到任何穿戴資料的值（分數、深睡、心率）
     - 心情是行為版，social/ 不 import 任何讀穿戴或評分的模組

  【安全】別人的 user_id 永遠不出後端
     - 整個回應掃過一遍，找不到任何一個朋友的 user_id
     - 邀請碼不是從 user_id 推出來的

  【紅線 5】連續紀錄缺資料就中斷（只在表現好的日子開 App 累積不了）

⚠️ 全程使用暫存資料庫。執行：python tests/test_friends.py
"""
import ast
import sqlite3
import sys
import tempfile
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import db
TMP = Path(tempfile.mkdtemp()) / "test_friends.db"
db.DB_PATH = TMP

import main
from fastapi.testclient import TestClient
from social import friends

# ⚠️ raise_server_exceptions=False：端點出錯時回 500 而不是讓整支測試崩掉。
#    崩掉會把後面所有檢查一起遮住——變異測試第一次跑時，「自己的碼也收」
#    與「少了 CASCADE」都是這樣：抓到了，但抓法是整支中斷。
client = TestClient(main.app, raise_server_exceptions=False)
fails = []


def check(label, got, want):
    good = got == want
    print(f"  {'✓' if good else '✗'} {label:<50} {got!r}" + ("" if good else f"  期望 {want!r}"))
    if not good:
        fails.append(label)


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label:<50} {extra}")
    if not cond:
        fails.append(label)


def section(title):
    print()
    print("=" * 78)
    print(title)
    print("=" * 78)


# ═══════════════════════════════════════════════════════════════════
section("【1】連續紀錄：沿日曆日走，缺資料就中斷")
# ═══════════════════════════════════════════════════════════════════
def row(d, minutes):
    return {"date": d, "adherence_minutes": minutes}

rows = [row("2026-09-01", -5), row("2026-09-02", -5),
        # 09-03 沒有資料
        row("2026-09-04", -5), row("2026-09-05", -5), row("2026-09-06", -5)]
check("中間缺一晚 → 最長是 3，不是 5", friends.best_streak(rows), 3)
check("熬夜那一晚也中斷", friends.best_streak([row("2026-09-01", -5), row("2026-09-02", 120),
                                               row("2026-09-03", -5)]), 1)
check("沒資料 = 0", friends.best_streak([]), 0)

# ═══════════════════════════════════════════════════════════════════
section("【2】social/ 不碰穿戴資料與評分")
# ═══════════════════════════════════════════════════════════════════
FORBIDDEN = ("garmin", "build_app_payload", "wearable", "evaluate_sleep_quality",
             "apply_recovery_modifier", "map_pet_mood", "resolve_mood", "game")
bad = []
for f in sorted((ROOT / "social").glob("*.py")):
    for node in ast.walk(ast.parse(f.read_text(encoding="utf-8"))):
        names = []
        if isinstance(node, ast.Import):
            names = [a.name for a in node.names]
        elif isinstance(node, ast.ImportFrom):
            names = [node.module or ""] + [a.name for a in node.names]
        bad += [f"{f.name}: {n}" for n in names if any(t in n for t in FORBIDDEN)]
check("social/ 沒有任何讀穿戴或評分的 import", bad, [])

# ═══════════════════════════════════════════════════════════════════
section("【3】端點：三個人，其中一個有手錶資料")
# ═══════════════════════════════════════════════════════════════════
db.init_db(TMP)
db.seed_challenges(TMP)


def make_user(name, times):
    uid = client.post("/users", json={"display_name": name, "target_bedtime": "23:30"}).json()["user_id"]
    dates = []
    for t in times:
        r = client.post("/nightly", json={"user_id": uid, "lights_out_at": t})
        assert r.status_code == 201, r.text
        dates.append(r.json()["date"])
    return uid, dates


alice, _ = make_user("Alice", ["2026-09-01T23:10:00+08:00", "2026-09-02T23:05:00+08:00"])
bob, bob_dates = make_user("Bob", ["2026-09-01T23:00:00+08:00", "2026-09-02T23:00:00+08:00",
                                   "2026-09-03T23:00:00+08:00"])
carol, _ = make_user("Carol", ["2026-09-02T02:30:00+08:00"])

# Bob 有手錶資料，而且值很好認——等一下要確認這些值一個都沒外洩
for d in bob_dates:
    db.upsert_wearable_nightly(bob, d, "garmin", {
        "final_score": 42.75, "final_quality": "Poor", "deep_min": 111.5,
        "rem_min": 77.25, "avg_hr": 63.5,
    }, db_path=TMP)

me = client.get(f"/friends?user_id={alice}").json()
code_a = me["my_invite_code"]
code_b = client.get(f"/friends?user_id={bob}").json()["my_invite_code"]
code_c = client.get(f"/friends?user_id={carol}").json()["my_invite_code"]
check("邀請碼 6 碼", len(code_a), 6)
check("同一個人永遠同一個碼", client.get(f"/friends?user_id={alice}").json()["my_invite_code"], code_a)
ok("邀請碼跟 user_id 無關", code_a not in alice and code_a.lower() not in alice.lower())
check("還沒有朋友", me["friends"], [])

# ═══════════════════════════════════════════════════════════════════
section("【4】加好友：404 / 422 / 409 分得開，而且是雙向的")
# ═══════════════════════════════════════════════════════════════════
check("沒有這個碼 → 404", client.post("/friends", json={"user_id": alice, "invite_code": "ZZZZZZ"}).status_code, 404)
check("自己的碼 → 422", client.post("/friends", json={"user_id": alice, "invite_code": code_a}).status_code, 422)
check("小寫也認得 → 201", client.post("/friends", json={"user_id": alice, "invite_code": code_b.lower()}).status_code, 201)
check("已經是朋友 → 409", client.post("/friends", json={"user_id": alice, "invite_code": code_b}).status_code, 409)
check("Bob 那邊也看得到 Alice", [f["display_name"] for f in client.get(f"/friends?user_id={bob}").json()["friends"]], ["Alice"])
client.post("/friends", json={"user_id": alice, "invite_code": code_c})

# ═══════════════════════════════════════════════════════════════════
section("【5】方法學紅線：只看得到行為")
# ═══════════════════════════════════════════════════════════════════
resp = client.get(f"/friends?user_id={alice}")
data = resp.json()
bob_summary = next(f for f in data["friends"] if f["display_name"] == "Bob")
check("摘要欄位剛好是白名單", tuple(bob_summary), friends.FRIEND_FIELDS)
for leaked in ("42.75", "111.5", "77.25", "63.5", "Poor"):
    ok(f"Bob 的手錶值 {leaked} 沒有出現在回應裡", leaked not in resp.text)
check("心情是行為版（Bob 準時 → happy，不管手錶說 Poor）", bob_summary["pet_mood"], "happy")

# ═══════════════════════════════════════════════════════════════════
section("【6】安全：別人的 user_id 一個都不出現")
# ═══════════════════════════════════════════════════════════════════
for name, uid in (("Bob", bob), ("Carol", carol)):
    ok(f"{name} 的 user_id 不在 /friends 回應裡", uid not in resp.text)
r_one = client.get(f"/friends/{code_b}?user_id={alice}")
check("GET /friends/{邀請碼} → 200", r_one.status_code, 200)
ok("單一朋友的回應裡也沒有 user_id", bob not in r_one.text)
added = client.post("/friends", json={"user_id": carol, "invite_code": code_b})
ok("加好友的回應裡也沒有 user_id", bob not in added.text, f"{added.status_code}")

# ═══════════════════════════════════════════════════════════════════
section("【7】排行：依目前連續達成，只排行為")
# ═══════════════════════════════════════════════════════════════════
board = client.get(f"/friends?user_id={alice}").json()["leaderboard"]
check("Bob（3 晚）排在 Carol（熬夜）前面", [e["display_name"] for e in board], ["Bob", "Carol"])
check("排行只有行為欄位", set(board[0]), {"rank", "handle", "display_name", "current_streak", "best_streak"})

# ═══════════════════════════════════════════════════════════════════
section("【8】不是朋友就看不到；解除好友兩邊一起消失")
# ═══════════════════════════════════════════════════════════════════
check("朋友之間互相看得到（Bob 看 Alice）→ 200", client.get(f"/friends/{code_a}?user_id={bob}").status_code, 200)
dave, _ = make_user("Dave", ["2026-09-01T23:00:00+08:00"])
check("不是朋友 → 404", client.get(f"/friends/{code_b}?user_id={dave}").status_code, 404)
check("解除好友 → 200", client.delete(f"/friends/{code_b}?user_id={alice}").status_code, 200)
check("Alice 那邊沒有 Bob 了", [f["display_name"] for f in client.get(f"/friends?user_id={alice}").json()["friends"]], ["Carol"])
check("Bob 那邊也沒有 Alice 了", "Alice" in [f["display_name"] for f in client.get(f"/friends?user_id={bob}").json()["friends"]], False)

# ═══════════════════════════════════════════════════════════════════
section("【9】退出即刪除：好友關係與邀請碼跟著清掉")
# ═══════════════════════════════════════════════════════════════════
del_status = client.delete(f"/users/{carol}").status_code
ok("退出（刪除帳號）成功——朋友那邊的關係不能擋住它", del_status in (200, 204), f"{del_status}")
conn = sqlite3.connect(TMP)
left = {
    "friendships(自己那邊)": conn.execute("SELECT COUNT(*) FROM friendships WHERE user_id = ?", (carol,)).fetchone()[0],
    "friendships(朋友那邊)": conn.execute("SELECT COUNT(*) FROM friendships WHERE friend_id = ?", (carol,)).fetchone()[0],
    "invite_codes": conn.execute("SELECT COUNT(*) FROM invite_codes WHERE user_id = ?", (carol,)).fetchone()[0],
}
conn.close()
check("三處都沒有殘留", left, {k: 0 for k in left})
check("Alice 的朋友清單不再有 Carol", [f["display_name"] for f in client.get(f"/friends?user_id={alice}").json()["friends"]], [])

print()
if fails:
    print(f"✗ {len(fails)} 條沒過：")
    for f in fails:
        print(f"    - {f}")
    sys.exit(1)
print("✓ 全部通過")
