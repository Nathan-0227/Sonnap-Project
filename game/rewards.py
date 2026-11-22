"""
game/rewards.py —— 挑戰獎勵的領取規則。純函式。（徽章在 game/badges.py）

═══════════════════════════════════════════════════════════════════
挑戰獎勵：每個挑戰「每一個窗格」可以領一次
═══════════════════════════════════════════════════════════════════

挑戰的達成與否**一律由 `behavior/challenges.py` 判定**，這裡只決定
「領過了沒」。在這裡重新判斷一次挑戰有沒有達成，就是第二個定義處。

領取的單位是窗格：`on_time_tonight`（1 天）每晚可以領一次、
`bedtime_consistency_7d` 每 7 天一次、`streak_nights`（14 天）每 14 天一次。
⚠️ 不做成「每個挑戰一輩子領一次」——那樣第一週之後就沒有東西可以領了。
⚠️ 也不做成「只要是完成狀態就每天都能領」——連續 20 晚的人會每天重複領
   同一個 streak 的獎勵，而那 20 晚的行為 XP 早就在 xp.py 給過了。

═══════════════════════════════════════════════════════════════════
⚠️ 徽章只看行為與睡眠品質，不看「有沒有資料」
═══════════════════════════════════════════════════════════════════

「第一次記錄」「記錄滿 7 晚」這種徽章看起來無害，但它們獎勵的正是
紅線 5 禁止的東西——只跟「有資料」耦合。徽章（game/badges.py）的每一個系列都要做到某件事；
那裡也記了使用者知情的三個例外（拜訪、習慣、助理）。
"""
from datetime import date as date_cls

# 領一次挑戰獎勵給多少 XP。
# ⚠️ 'time'（今晚準時）只給 10：那一晚的準時已經在 xp.py 給過 30 了，
#    這裡只是「你記得來領」的小獎勵，不能讓同一件事拿兩份大獎。
# 一晚的挑戰 10、多晚的 40。
# 2026-11-19 補上 phone_in_bed 與 wake_time（使用者定）：原本 phone_in_bed 沒列在表上，
# 完成了領到 0 XP——那是漏掉，不是設計。⚠️ 新增挑戰型別時這張表也要加，
# 不然 .get(kind, 0) 會安靜地給 0（tests/test_game_rewards.py 有一條守著）。
CLAIM_XP = {"time": 10, "phone_in_bed": 10, "wake_time": 10,
            "streak": 40, "consistency": 40}

# 徽章在 game/badges.py（2026-11-22 改成 13 個系列 × 5 級），這裡不再判。


def claim_period(window_days, as_of):
    """某個日期落在第幾個窗格。as_of 是 'YYYY-MM-DD'。"""
    return date_cls.fromisoformat(as_of).toordinal() // max(1, int(window_days))


def achievement_id(challenge, as_of):
    return f"challenge:{challenge['challenge_id']}:{claim_period(challenge['window_days'], as_of)}"


def claimable(evaluated, as_of, claimed_ids):
    """
    現在可以領哪些挑戰獎勵。

    evaluated 是 `challenge_engine.evaluate_all()` 的輸出（**後端判定的**
    達成狀態）；as_of 是最新一晚的日期；claimed_ids 是已經領過的成就 id。
    沒有任何一晚的資料時 as_of 是 None，一律回空清單。
    """
    if as_of is None:
        return []
    claimed = set(claimed_ids or ())
    out = []
    for ch in evaluated:
        if ch.get("status") != "completed":
            continue
        aid = achievement_id(ch, as_of)
        if aid in claimed:
            continue
        out.append({
            "challenge_id": ch["challenge_id"],
            "title": ch["title"],
            "achievement_id": aid,
            "xp": CLAIM_XP.get(ch["kind"], 0),
        })
    return out
