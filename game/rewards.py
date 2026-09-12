"""
game/rewards.py —— 挑戰獎勵的領取規則、成就徽章。純函式。

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
紅線 5 禁止的東西——只跟「有資料」耦合。這裡每一個徽章都要做到某件事。
"""
from datetime import date as date_cls

# 領一次挑戰獎勵給多少 XP。
# ⚠️ 'time'（今晚準時）只給 10：那一晚的準時已經在 xp.py 給過 30 了，
#    這裡只是「你記得來領」的小獎勵，不能讓同一件事拿兩份大獎。
CLAIM_XP = {"time": 10, "streak": 40, "consistency": 40}

BADGES = (
    {
        "badge_id": "first_on_time",
        "title": "First on-time night",
        "description": "Put your phone down before your target bedtime.",
    },
    {
        "badge_id": "on_time_x5",
        "title": "Five on-time nights",
        "description": "Five nights on time, not necessarily in a row.",
    },
    {
        "badge_id": "good_sleep",
        "title": "A good night",
        "description": "Your watch rated a night as Good.",
    },
)


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


def badges(nights):
    """
    nights 是 xp.nights_xp() 的輸出。回傳每個徽章與是否已經拿到。

    ⚠️ 徽章是**即時算**的，不存資料庫——事實來源是每晚的資料，
       存起來的話就會有「資料改了、徽章沒跟著改」的第二份真相。
    """
    on_time = sum(1 for n in nights if n["behaviour_tier"] == "on_time")
    good = any(n["final_quality"] == "Good" for n in nights)
    earned = {
        "first_on_time": on_time >= 1,
        "on_time_x5": on_time >= 5,
        "good_sleep": good,
    }
    return [{**b, "earned": earned[b["badge_id"]]} for b in BADGES]
