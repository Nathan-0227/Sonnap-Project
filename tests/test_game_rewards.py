"""
tests/test_game_rewards.py —— 遊戲化層的兩條紅線 + 四個端點

守的東西（每一條都是「壞掉不會報錯」的那種）：

  【紅線 5】獎勵要跟品質綁在一起，不能只跟「有資料」綁在一起
     - 熬夜又睡不好的一晚 = 0 XP
     - Bad 夜晚明顯少於 Good，而且 XP 不是常數
     - XP 的大宗來自行為（使用者控制得了），不是生理結果

  【紅線 4】遊戲層只讀，不得回寫評分層
     - game/ 不 import 評分模組
     - 打過所有遊戲端點之後，評分表與行為表逐欄沒變

⚠️ 全程使用**暫存資料庫**，不會碰到 data/sonnap.db。

執行：python tests/test_game_rewards.py
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

# ⚠️ 一定要在 import main 之前換掉 DB_PATH，否則端點會寫到真的資料庫
import db
TMP = Path(tempfile.mkdtemp()) / "test_game.db"
db.DB_PATH = TMP

import main
from behavior.adherence import LATE_THRESHOLD_MINUTES
from fastapi.testclient import TestClient
from game import inventory, levels, rewards, xp

client = TestClient(main.app)
fails = []


def check(label, got, want):
    good = got == want
    print(f"  {'✓' if good else '✗'} {label:<52} {got!r}" + ("" if good else f"  期望 {want!r}"))
    if not good:
        fails.append(label)


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label:<52} {extra}")
    if not cond:
        fails.append(label)


def section(title):
    print()
    print("=" * 78)
    print(title)
    print("=" * 78)


def night(minutes, quality):
    b = None if minutes is None else {"date": "2026-09-01", "adherence_minutes": minutes}
    w = None if quality is None else {"date": "2026-09-01", "final_quality": quality}
    return xp.night_xp(b, w)["total"]


# ═══════════════════════════════════════════════════════════════════
section("【1】紅線 5：只是「有資料」拿不到任何東西")
# ═══════════════════════════════════════════════════════════════════
good_on_time = night(-10, "Good")
bad_late = night(120, "Bad")
check("熬夜又睡不好 = 0 XP", bad_late, 0)
ok("Bad＋熬夜 明顯少於 Good＋準時", bad_late < good_on_time, f"{bad_late} vs {good_on_time}")
check("完全沒資料 = 0 XP（不是參加獎）", night(None, None), 0)

# ═══════════════════════════════════════════════════════════════════
section("【2】紅線 5：XP 跟品質走，不是常數")
# ═══════════════════════════════════════════════════════════════════
by_quality = [night(-10, q) for q in ("Good", "Normal", "Poor", "Bad")]
ok("同樣準時，Good > Normal > Poor", by_quality[0] > by_quality[1] > by_quality[2], f"{by_quality}")
ok("四種品質不是同一個數", len(set(by_quality)) > 1, f"{set(by_quality)}")
by_behaviour = [night(m, "Normal") for m in (-10, LATE_THRESHOLD_MINUTES, LATE_THRESHOLD_MINUTES + 1)]
ok("同樣品質，準時 > 容許範圍內 > 熬夜", by_behaviour[0] > by_behaviour[1] > by_behaviour[2], f"{by_behaviour}")
check("Poor 與 Bad 都是 0，不扣成負數", (xp.QUALITY_BONUS_XP["Poor"], xp.QUALITY_BONUS_XP["Bad"]), (0, 0))

# ═══════════════════════════════════════════════════════════════════
section("【3】XP 的大宗來自行為（使用者控制得了）")
# ═══════════════════════════════════════════════════════════════════
ok("行為上限 > 品質加成上限",
   max(xp.BEHAVIOUR_XP.values()) > max(xp.QUALITY_BONUS_XP.values()),
   f"{max(xp.BEHAVIOUR_XP.values())} vs {max(xp.QUALITY_BONUS_XP.values())}")
ok("沒戴錶的人只靠準時也拿得到 XP", night(-10, None) > 0, f"{night(-10, None)}")
ok("準時但睡不好 > 熬夜但睡得好（行為優先）",
   night(-10, "Bad") > night(120, "Good"), f"{night(-10, 'Bad')} vs {night(120, 'Good')}")

# ═══════════════════════════════════════════════════════════════════
section("【4】判準只有一個定義處")
# ═══════════════════════════════════════════════════════════════════
check("剛好等於 LATE_THRESHOLD → 容許範圍內", xp.behaviour_tier(LATE_THRESHOLD_MINUTES), "tolerance")
check("多 1 分鐘 → 熬夜", xp.behaviour_tier(LATE_THRESHOLD_MINUTES + 1), "late")
check("沒資料不是熬夜", xp.behaviour_tier(None), None)

# ═══════════════════════════════════════════════════════════════════
section("【5】兩層依日期對齊，不是依索引")
# ═══════════════════════════════════════════════════════════════════
nights = xp.nights_xp(
    [{"date": "2026-09-01", "adherence_minutes": -5}],
    [{"date": "2026-09-02", "final_quality": "Good"}],
)
check("兩個不同的夜晚", [n["date"] for n in nights], ["2026-09-01", "2026-09-02"])
# ⚠️ 用 .get 而不是直接索引：對齊寫錯時清單會變短，直接索引會在這裡崩掉，
#    把後面所有檢查一起遮住——那比「這一條沒過」更難看出哪裡壞了。
by_date = {n["date"]: n for n in nights}
n1, n2 = by_date.get("2026-09-01", {}), by_date.get("2026-09-02", {})
check("09-01 只有行為 XP", (n1.get("behaviour_xp"), n1.get("quality_xp")), (30, 0))
check("09-02 只有品質加成", (n2.get("behaviour_xp"), n2.get("quality_xp")), (0, 20))

# ═══════════════════════════════════════════════════════════════════
section("【6】等級：進度條是「這一級」的，升級時歸零")
# ═══════════════════════════════════════════════════════════════════
ok("門檻嚴格遞增", all(a < b for a, b in zip(levels.LEVEL_THRESHOLDS, levels.LEVEL_THRESHOLDS[1:])))
check("0 XP = 第 1 級", levels.level_for(0)["level"], 1)
check("剛好 100 XP = 第 2 級、進度 0", (levels.level_for(100)["level"], levels.level_for(100)["progress"]), (2, 0.0))
check("最高級沒有下一級", levels.level_for(10 ** 6)["xp_for_next"], None)
check("成長階段隨等級改變", [levels.growth_stage(n) for n in (1, 3, 6)], ["baby", "young", "adult"])

# ═══════════════════════════════════════════════════════════════════
section("【7】紅線 4：game/ 不 import 評分模組")
# ═══════════════════════════════════════════════════════════════════
FORBIDDEN = ("garmin", "evaluate_sleep_quality", "apply_recovery_modifier", "build_app_payload")
bad_imports = []
for f in sorted((ROOT / "game").glob("*.py")):
    tree = ast.parse(f.read_text(encoding="utf-8"))
    for node in ast.walk(tree):
        names = []
        if isinstance(node, ast.Import):
            names = [a.name for a in node.names]
        elif isinstance(node, ast.ImportFrom) and node.module:
            names = [node.module]
        for n in names:
            if any(tok in n for tok in FORBIDDEN):
                bad_imports.append(f"{f.name}: {n}")
check("game/ 沒有任何評分模組的 import", bad_imports, [])

# ═══════════════════════════════════════════════════════════════════
section("【8】端點：三個使用者，行為相同但品質／準時不同")
# ═══════════════════════════════════════════════════════════════════
db.init_db(TMP)
db.seed_challenges(TMP)


def make_user(name, lights_out_times, qualities):
    uid = client.post("/users", json={"display_name": name, "target_bedtime": "23:30"}).json()["user_id"]
    for t, q in zip(lights_out_times, qualities):
        r = client.post("/nightly", json={"user_id": uid, "lights_out_at": t})
        assert r.status_code == 201, r.text
        if q is not None:
            db.upsert_wearable_nightly(uid, r.json()["date"], "garmin",
                                       {"final_quality": q, "final_score": 80.0}, db_path=TMP)
    return uid


ON_TIME = ["2026-09-01T23:10:00+08:00", "2026-09-02T23:05:00+08:00", "2026-09-03T23:15:00+08:00"]
LATE = ["2026-09-02T02:30:00+08:00", "2026-09-03T02:40:00+08:00", "2026-09-04T02:20:00+08:00"]
good = make_user("GoodSleeper", ON_TIME, ["Good"] * 3)
bad = make_user("LateSleeper", LATE, ["Bad"] * 3)
nowatch = make_user("NoWatch", ON_TIME, [None] * 3)

g_good = client.get(f"/game?user_id={good}").json()
g_bad = client.get(f"/game?user_id={bad}").json()
g_nowatch = client.get(f"/game?user_id={nowatch}").json()
check("熬夜又睡不好的三晚：0 XP", g_bad["xp_total"], 0)
check("準時又睡得好的三晚：150 XP", g_good["xp_total"], 150)
check("沒戴錶但準時的三晚：90 XP", g_nowatch["xp_total"], 90)
ok("XP 來源拆得開", g_good["xp_sources"] == {"behaviour": 90, "sleep_quality": 60, "challenge_rewards": 0},
   f"{g_good['xp_sources']}")
check("150 XP = 第 2 級", g_good["level"], 2)
check("熬夜的人沒有徽章", [b["badge_id"] for b in g_bad["badges"] if b["earned"]], [])

# ═══════════════════════════════════════════════════════════════════
section("【9】領獎：404 / 422 / 409 分得開，而且真的加到 XP")
# ═══════════════════════════════════════════════════════════════════
snapshot_before = (db.get_nightly_behavior(good, db_path=TMP), db.get_wearable_nightly(good, db_path=TMP))

claimable = {c["challenge_id"] for c in g_good["claimable"]}
ok("連續 3 晚準時 → 連續挑戰可領", "streak_nights" in claimable, f"{sorted(claimable)}")
r = client.post("/game/claim", json={"user_id": good, "challenge_id": "streak_nights"})
check("領獎 201", r.status_code, 201)
check("XP 加上去了", client.get(f"/game?user_id={good}").json()["xp_total"],
      150 + rewards.CLAIM_XP["streak"])
check("同一個窗格再領 → 409", client.post("/game/claim", json={"user_id": good, "challenge_id": "streak_nights"}).status_code, 409)
check("還沒完成的挑戰 → 422", client.post("/game/claim", json={"user_id": good, "challenge_id": "bedtime_consistency_7d"}).status_code, 422)
check("沒有這個挑戰 → 404", client.post("/game/claim", json={"user_id": good, "challenge_id": "nope"}).status_code, 404)
check("熬夜的人什麼都領不到", client.post("/game/claim", json={"user_id": bad, "challenge_id": "streak_nights"}).status_code, 422)

# ═══════════════════════════════════════════════════════════════════
section("【10】衣櫃：沒解鎖不能穿、穿了會記得、可以脫")
# ═══════════════════════════════════════════════════════════════════
closet = client.get(f"/closet?user_id={good}").json()
check("六件衣服", len(closet["items"]), len(inventory.CATALOG))
check("穿第 8 級的皇冠 → 403", client.post("/closet/equip", json={"user_id": good, "item_id": "crown"}).status_code, 403)
check("穿不存在的衣服 → 404", client.post("/closet/equip", json={"user_id": good, "item_id": "cape"}).status_code, 404)
check("穿第 2 級的圍巾 → 200", client.post("/closet/equip", json={"user_id": good, "item_id": "scarf"}).status_code, 200)
check("衣櫃記得穿著圍巾", client.get(f"/closet?user_id={good}").json()["equipped_item_id"], "scarf")
check("熬夜的人穿不了圍巾", client.post("/closet/equip", json={"user_id": bad, "item_id": "scarf"}).status_code, 403)
check("脫掉 → 200", client.post("/closet/equip", json={"user_id": good, "item_id": None}).status_code, 200)
check("脫掉之後什麼都沒穿", client.get(f"/closet?user_id={good}").json()["equipped_item_id"], None)
ok("穿過的圍巾留在衣櫃裡（不收回）", "scarf" in db.get_inventory(good, db_path=TMP))
# ⚠️ 只驗「資料庫有記」不夠：要驗等級掉下來之後**真的還能穿**。
#    XP 規則日後調整、等級下降時，已經穿過的衣服不能被收回。
ok("等級掉回 1，穿過的皇冠照樣能穿", inventory.is_unlocked("crown", 1, ["crown"]))
ok("反向對照：沒穿過的皇冠在第 1 級不能穿", not inventory.is_unlocked("crown", 1, []))

# ═══════════════════════════════════════════════════════════════════
section("【11】紅線 4：打完所有遊戲端點，評分表與行為表逐欄沒變")
# ═══════════════════════════════════════════════════════════════════
snapshot_after = (db.get_nightly_behavior(good, db_path=TMP), db.get_wearable_nightly(good, db_path=TMP))
check("nightly_behavior 逐欄相同", snapshot_after[0], snapshot_before[0])
check("wearable_nightly 逐欄相同（final_score 沒被動）", snapshot_after[1], snapshot_before[1])

# ═══════════════════════════════════════════════════════════════════
section("【12】退出即刪除：遊戲表跟著清掉")
# ═══════════════════════════════════════════════════════════════════
client.delete(f"/users/{good}")
conn = sqlite3.connect(TMP)
left = {t: conn.execute(f"SELECT COUNT(*) FROM {t} WHERE user_id = ?", (good,)).fetchone()[0]
        for t in ("user_game_state", "user_inventory", "achievements")}
conn.close()
check("三張遊戲表都沒有殘留", left, {"user_game_state": 0, "user_inventory": 0, "achievements": 0})

print()
if fails:
    print(f"✗ {len(fails)} 條沒過：")
    for f in fails:
        print(f"    - {f}")
    sys.exit(1)
print("✓ 全部通過")
