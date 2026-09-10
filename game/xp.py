"""
game/xp.py —— 每一晚值多少 XP。純函式，不碰資料庫。

一晚的 XP = 行為 XP + 睡眠品質加成：

    行為（每個人都有，使用者控制得了）
        準時或提早           30
        晚了但在容許範圍內   15    （容許範圍 = adherence.LATE_THRESHOLD_MINUTES）
        熬夜                  0

    睡眠品質加成（只有戴錶的人有，是生理結果）
        Good 20 / Normal 10 / Poor 0 / Bad 0

⚠️ **熬夜又睡不好 = 0 XP。** 這是紅線 5 的核心：只是「有資料」不值任何東西。
⚠️ **行為的上限（30）大於品質加成的上限（20）**，所以沒戴錶的 D2 受測者
   只靠行為也能穩定升級，而戴錶的人不會因為一晚感冒就被拉開很遠。
⚠️ 行為分級**直接用 `adherence.LATE_THRESHOLD_MINUTES`**，不在這裡另訂一個
   「幾分鐘算晚」——那會變成第二個定義處，兩份漂移時寵物心情說「還好」、
   XP 卻說「熬夜」，而且不會有任何錯誤訊息。
"""
from behavior.adherence import LATE_THRESHOLD_MINUTES

BEHAVIOUR_XP = {
    "on_time": 30,
    "tolerance": 15,
    "late": 0,
}

# ⚠️ Poor 與 Bad 都是 0，不是負數。扣 XP 等於懲罰使用者控制不了的生理結果。
QUALITY_BONUS_XP = {
    "Good": 20,
    "Normal": 10,
    "Poor": 0,
    "Bad": 0,
}


def behaviour_tier(adherence_minutes):
    """
    'on_time' / 'tolerance' / 'late'，沒資料回 None。

    ⚠️ None 不是 'late'。「那一晚沒量到」與「那一晚熬夜」是兩件事，
       前者不該在任何畫面上被說成熬夜。
    """
    if adherence_minutes is None:
        return None
    if adherence_minutes <= 0:
        return "on_time"
    if adherence_minutes <= LATE_THRESHOLD_MINUTES:
        return "tolerance"
    return "late"


def night_xp(behavior_row=None, wearable_row=None):
    """
    一晚的 XP 拆解。兩個參數都可以是 None（那一層那晚沒資料）。

    回傳的 dict 把兩個來源分開列，讓畫面能講出「這 30 點是因為你準時」，
    而不是只給一個總數——跟評分系統一路以來「數字要能講出理由」是同一個要求。
    """
    minutes = behavior_row.get("adherence_minutes") if behavior_row else None
    tier = behaviour_tier(minutes)
    b_xp = BEHAVIOUR_XP[tier] if tier else 0

    quality = wearable_row.get("final_quality") if wearable_row else None
    q_xp = QUALITY_BONUS_XP.get(quality, 0) if quality else 0

    date = (behavior_row or {}).get("date") or (wearable_row or {}).get("date")
    return {
        "date": date,
        "behaviour_tier": tier,
        "behaviour_xp": b_xp,
        "final_quality": quality,
        "quality_xp": q_xp,
        "total": b_xp + q_xp,
    }


def nights_xp(behavior_rows, wearable_rows):
    """
    把兩層的資料依日期對齊，逐晚算 XP，**由舊到新**。

    ⚠️ 用日期對齊而不是用索引對齊。兩層的夜晚集合不同（有人只有手機、
       有人某幾晚沒戴錶），用索引的話第 3 列的行為會配到第 3 列的手錶，
       而那可能是不同的兩晚——算出來的 XP 看起來完全正常。
    """
    by_date = {}
    for r in behavior_rows or []:
        by_date.setdefault(r["date"], [None, None])[0] = r
    for r in wearable_rows or []:
        by_date.setdefault(r["date"], [None, None])[1] = r
    return [night_xp(b, w) for _, (b, w) in sorted(by_date.items())]
