"""
game/state.py —— 把一個使用者的資料組成 `GET /game` 的回應。純函式。

抽出來而不是寫在 main.py 裡，是為了讓測試不必起 API 就能驗
「Bad 夜晚拿到的比 Good 少」這種紅線——端點只負責從資料庫撈資料、
把結果交給這裡。
"""
from . import levels, rewards, xp

# 畫面上列最近幾晚的 XP 拆解。
RECENT_NIGHTS = 7


def build_game_state(behavior_rows, wearable_rows, achievement_rows, evaluated_challenges):
    """
    behavior_rows / wearable_rows：db 取回的每晚資料（由舊到新）
    achievement_rows：db.get_achievements() 的輸出（已領過的挑戰獎勵）
    evaluated_challenges：challenge_engine.evaluate_all() 的輸出

    ⚠️ 總 XP 是**每次即時算**的（每晚的 XP + 已領的獎勵），不存一個累加值。
       理由同挑戰進度：事實來源是 nightly_behavior，受測者事後補填某一晚時
       XP 會自動更正；存成累加值的話，補填那一晚就永遠少算或多算。
    """
    nights = xp.nights_xp(behavior_rows, wearable_rows)
    behaviour_total = sum(n["behaviour_xp"] for n in nights)
    quality_total = sum(n["quality_xp"] for n in nights)
    claims_total = sum(int(a.get("xp_awarded") or 0) for a in achievement_rows or [])
    total = behaviour_total + quality_total + claims_total

    lvl = levels.level_for(total)
    dates = [r["date"] for r in behavior_rows or [] if r.get("date")]
    as_of = max(dates) if dates else None
    claimed_ids = [a["achievement_id"] for a in achievement_rows or []]

    return {
        **lvl,
        "growth_stage": levels.growth_stage(lvl["level"]),
        "xp_sources": {
            "behaviour": behaviour_total,
            "sleep_quality": quality_total,
            "challenge_rewards": claims_total,
        },
        "recent_nights": nights[-RECENT_NIGHTS:],
        "claimable": rewards.claimable(evaluated_challenges, as_of, claimed_ids),
        "badges": rewards.badges(nights),
        "as_of": as_of,
    }
