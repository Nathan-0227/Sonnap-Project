"""
好友小鎮（social/town.py ＋ GET /friends/town、POST /friends/{handle}/visit）。2026-11-17 新增。

守的事：
【1】發光＝昨晚準時放下手機且有分享 On time；判準同 night_achieved（自己照亮）
【2】沒發光的三種情況（晚了、沒資料、沒分享）回應**一模一樣**——不給原因
【3】拜訪：一天一次（換一句話也不行）、不認得的動作 422、不是朋友／自己 404
【4】對方看到的那一句（照他自己的寵物寫 dog／cat）；送的人看得到「送過了」
【5】不給 XP、不影響分數
【6】存 14 天：寫入時順手刪舊的；解除好友、刪帳號時一起刪
【7】回應裡沒有任何 user_id；/friends/town 不會被當成邀請碼

⚠️ 全程使用暫存資料庫。執行：python tests/test_friend_town.py
"""
import os
import sys
import tempfile
from datetime import date, datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.stdout.reconfigure(encoding="utf-8")

from social import town  # noqa: E402

failures = []


def check(name, got, want):
    ok = got == want
    print(f"  {'✓' if ok else '✗'} {name:<60} {got!r}" + ("" if ok else f"  期望 {want!r}"))
    if not ok:
        failures.append(name)


print("【0】純函式")
check("晚上 22:00 送的算隔天（起床日）", town.visit_day(datetime(2026, 11, 17, 22, 0)), "2026-11-18")
check("早上 10:00 送的算今天", town.visit_day(datetime(2026, 11, 17, 10, 0)), "2026-11-17")
check("貓的主人看到 cat", town.message("pet", "Leo", "cat"), "Leo pet your cat 🐾")
check("不認得的種類當 dog", town.message("pet", "Leo", None), "Leo pet your dog 🐾")
check("一句話", town.message("sleep_well", "Mia", "dog"), "Mia: Sleep well 💤")
check("示範帳號的名字不重複寫 (demo)", town.display_name("Mia (demo)"), "Mia")
rows = [{"date": "2026-11-17", "adherence_minutes": 0}]
check("準時＋分享 → 亮", town.glows(rows, "2026-11-17", True), True)
check("準時但沒分享 → 不亮", town.glows(rows, "2026-11-17", False), False)
check("晚了 → 不亮", town.glows([{"date": "2026-11-17", "adherence_minutes": 200}], "2026-11-17", True), False)
check("沒測到（None）→ 不亮", town.glows([{"date": "2026-11-17", "adherence_minutes": None}], "2026-11-17", True), False)
check("別晚準時不算昨晚", town.glows([{"date": "2026-11-16", "adherence_minutes": 0}], "2026-11-17", True), False)

print("\n【API】")
os.environ.pop("SONNAP_DB_URL", None)
import db  # noqa: E402
db.DB_PATH = Path(tempfile.mkdtemp()) / "town.db"
db.init_db()
import main  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

client = TestClient(main.app)
today = date.today().isoformat()
me = db.create_user("Me")
early = db.create_user("Early")     # 準時、有分享 → 亮
late = db.create_user("Late")       # 晚了
blank = db.create_user("Blank")     # 沒資料
shy = db.create_user("Shy")         # 準時但沒分享
stranger = db.create_user("Stranger")
for i, u in enumerate((early, late, blank, shy)):
    db.add_friendship(me, u)
    c = db.connect()  # 同一秒加的好友 created_at 會一樣，順序就不固定 → 給遞增的時間
    c.execute("UPDATE friendships SET created_at = ? WHERE friend_id = ? OR user_id = ?",
              (f"2026-01-0{i + 1}T00:00:00", u, u))
    c.commit()
    c.close()
for u in (me, early, late, blank, shy):
    db.set_friend_sharing(u, items={"on_time": u != shy})
db.set_friend_sharing(me, items={"on_time": False})  # 我自己沒分享，自己看自己照亮
db.set_friend_sharing(early, pet_species="cat")
for u, mins in ((me, 0), (early, 0), (late, 180), (shy, 0)):
    db.upsert_nightly_behavior(u, today, "23:00", f"{today}T23:00:00", mins, mins > 30)

r = client.get("/friends/town", params={"user_id": me})
check("200", r.status_code, 200)
j = r.json()
by = {p["display_name"]: p for p in j["people"]}
check("我排第一個、標 mine", (j["people"][0]["display_name"], j["people"][0]["mine"]), ("Me", True))
check("朋友照加好友的先後", [p["display_name"] for p in j["people"][1:]], ["Early", "Late", "Blank", "Shy"])
check("【1】準時＋分享的亮", by["Early"]["glow"], True)
check("【1】我自己沒分享也照亮", by["Me"]["glow"], True)


def same_shape(p):
    """小鎮畫面用到的欄位。pet_mood 與 card 只出現在點開的小卡上，而且是他自己選擇分享的
    （心情、昨晚的卡）——那不是小鎮的樣子，所以不比。"""
    return {k: v for k, v in p.items() if k not in ("handle", "display_name", "pet_mood", "card")}


check("【2】晚了／沒資料／沒分享：三個人的回應一模一樣（除了名字）",
      same_shape(by["Late"]) == same_shape(by["Blank"]) == same_shape(by["Shy"]), True)
check("【2】小鎮畫面只用這幾個欄位（多了新欄位要回來看會不會洩漏原因）",
      sorted(same_shape(by["Late"])), ["demo", "glow", "mine", "pet_species", "sent"])
check("【2】而且都是 glow: false", [by[n]["glow"] for n in ("Late", "Blank", "Shy")], [False] * 3)
check("【2】反向對照：亮的那個跟他們不一樣", same_shape(by["Early"]) == same_shape(by["Shy"]), False)
check("按鈕四種，照順序", [k["key"] for k in j["kinds"]], ["pet", "good_night", "sleep_well", "proud"])

print("\n【3】拜訪")
h = {p["display_name"]: p["handle"] for p in j["people"]}


def visit(handle, kind, who=me):
    return client.post(f"/friends/{handle}/visit", json={"user_id": who, "kind": kind})


check("送出 201", visit(h["Early"], "pet").status_code, 201)
check("同一天第二次 409（換一句話也不行）", visit(h["Early"], "sleep_well").status_code, 409)
check("另一個朋友照樣可以送", visit(h["Late"], "good_night").status_code, 201)
check("不認得的動作 422", visit(h["Blank"], "hug").status_code, 422)
check("不是朋友 404", visit(db.ensure_invite_code(stranger), "pet").status_code, 404)
check("自己 404", visit(h["Me"], "pet").status_code, 404)

j = client.get("/friends/town", params={"user_id": me}).json()
by = {p["display_name"]: p for p in j["people"]}
check("【4】送的人看得到送過了什麼", (by["Early"]["sent"], by["Late"]["sent"], by["Blank"]["sent"]),
      ("pet", "good_night", None))
check("【4】我自己沒有 sent", by["Me"]["sent"], None)
je = client.get("/friends/town", params={"user_id": early}).json()
check("【4】對方看到的那一句照他自己的寵物（貓）", [v["message"] for v in je["visits"]], ["Me pet your cat 🐾"])
jl = client.get("/friends/town", params={"user_id": late}).json()
check("【4】另一個朋友看到的", [v["message"] for v in jl["visits"]], ["Me: Good night 🌙"])
check("【4】回送：Early 也能送我", visit(h["Me"], "proud", who=early).status_code, 201)
check("【4】我收到", [v["message"] for v in client.get("/friends/town", params={"user_id": me}).json()["visits"]],
      ["Early: Proud of you ⭐"])

print("\n【5】不給 XP、不影響分數")
before = client.get("/game", params={"user_id": shy}).json()
visit(h["Shy"], "sleep_well")
after = client.get("/game", params={"user_id": shy}).json()
check("被拜訪前後 /game 一模一樣", before == after, True)

print("\n【6】存多久、什麼時候刪")
conn = db.connect()
conn.execute("INSERT INTO friend_visits (sender_id, receiver_id, day, kind, created_at) VALUES (?,?,?,?,?)",
             (late, me, (date.today() - timedelta(days=20)).isoformat(), "pet", "x"))
conn.commit()
conn.close()
visit(h["Blank"], "pet")  # 任何一次寫入都會順手清舊的


def count(sql, *a):
    c = db.connect()
    try:
        return c.execute(sql, a).fetchone()[0]
    finally:
        c.close()


check("20 天前的拜訪被清掉", count("SELECT COUNT(*) FROM friend_visits WHERE sender_id = ?", late), 0)
n_before = count("SELECT COUNT(*) FROM friend_visits WHERE (sender_id=? AND receiver_id=?) OR (sender_id=? AND receiver_id=?)",
                 me, early, early, me)
check("（對照）解除好友前 Me↔Early 有 2 筆", n_before, 2)
client.delete(f"/friends/{h['Early']}", params={"user_id": me})
check("解除好友：兩個方向的拜訪一起刪",
      count("SELECT COUNT(*) FROM friend_visits WHERE (sender_id=? AND receiver_id=?) OR (sender_id=? AND receiver_id=?)",
            me, early, early, me), 0)
check("（對照）別人的拜訪還在", count("SELECT COUNT(*) FROM friend_visits WHERE receiver_id = ?", blank), 1)
db.delete_user(blank)
check("刪帳號：收到的拜訪一起刪（CASCADE）", count("SELECT COUNT(*) FROM friend_visits WHERE receiver_id = ?", blank), 0)

print("\n【7】隱私與路徑")
texts = [client.get("/friends/town", params={"user_id": u}).text for u in (me, late, shy)]
check("回應裡沒有任何 user_id", any(u in t for t in texts for u in (me, early, late, blank, shy)), False)
check("/friends/town 不會被當成邀請碼（不是 404）",
      client.get("/friends/town", params={"user_id": me}).status_code, 200)

print()
if failures:
    print(f"✗ {len(failures)} 條沒過：{failures}")
    sys.exit(1)
print("全部通過")
