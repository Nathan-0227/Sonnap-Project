"""
game/levels.py —— 累積 XP → 等級 → 寵物成長階段。純函式。

⚠️ 門檻是遊戲平衡不是計分（見 game/__init__.py）。取法：
   一晚最多 50 XP（行為 30 + 品質 20），只靠行為最多 30。
   第 2 級要 100 XP ≈ 準時 3–4 晚，D2 受測者的 4–5 晚內看得到第一次升級；
   之後每級的間距逐步拉大，讓「持續」比「偶爾一次」更有價值。
"""

# 第 N 級需要的**累積** XP（索引 0 = 第 1 級）。
LEVEL_THRESHOLDS = (0, 100, 250, 450, 700, 1000, 1400, 1900, 2500, 3200)
MAX_LEVEL = len(LEVEL_THRESHOLDS)

# (最低等級, 階段名)，由高到低排。
GROWTH_STAGES = ((6, "adult"), (3, "young"), (1, "baby"))


def level_for(total_xp):
    """
    累積 XP → 等級資訊。

    ⚠️ progress 是「這一級走了多少」，不是「總共走了多少」。
       畫面上的進度條要的是前者；用後者的話升級那一刻進度條不會歸零，
       使用者看不出來自己升級了。
    """
    total = max(0, int(total_xp or 0))
    level = 1
    for i, threshold in enumerate(LEVEL_THRESHOLDS):
        if total >= threshold:
            level = i + 1

    floor = LEVEL_THRESHOLDS[level - 1]
    if level >= MAX_LEVEL:
        return {
            "level": level,
            "xp_total": total,
            "xp_into_level": total - floor,
            "xp_for_next": None,
            "progress": 1.0,
            "max_level": True,
        }

    nxt = LEVEL_THRESHOLDS[level]
    return {
        "level": level,
        "xp_total": total,
        "xp_into_level": total - floor,
        "xp_for_next": nxt - total,
        "progress": round((total - floor) / (nxt - floor), 3),
        "max_level": False,
    }


def growth_stage(level):
    """等級 → 'baby' / 'young' / 'adult'。"""
    for min_level, stage in GROWTH_STAGES:
        if level >= min_level:
            return stage
    return "baby"
