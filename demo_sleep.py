"""
demo_sleep.py —— 示範帳號（demo_accounts.py）每一晚的睡眠階段。純函式、只用標準庫。

🔴 **這是假資料。** 只給 study_cohort = db.DEMO_COHORT 的示範帳號用，手錶資料的 source 一律是
   "demo"（不是 garmin／health_connect），任何「真的手錶資料」的查詢都不會撈到它。

做法（2026-11-16 使用者定「示範帳號全部資料都要生成」）：
1. 先決定那一晚的深睡／淺睡／REM／清醒各幾分鐘
2. night_segments() 把它排成一整晚的階梯（固定種子：同樣的輸入每次都排出一模一樣的段）
3. demo_accounts 把這些段當成 Health Connect 的 session，交給**既有的評分器**算分數
   （wearable/healthconnect_adapter.to_wearable_row）——分數不是手寫的
4. API 要畫階梯圖時（main.night_stages），用存下來的分鐘數再排一次，得到同一份段

⚠️ 所以 night_segments 必須是**決定性**的：只看參數、不看時間或全域亂數。
   tests/test_demo_accounts.py 守著「再排一次跟評分時那一份相同」。
"""
import random
from datetime import datetime, timedelta

CYCLES = 5
# 深睡集中在前半夜、REM 集中在後半夜（睡眠週期的一般樣子，只是讓圖看起來像一晚）
_DEEP_W = (0.36, 0.30, 0.20, 0.10, 0.04)
_REM_W = (0.08, 0.15, 0.22, 0.25, 0.30)


def _split(total, weights):
    """total 分鐘照權重切成整數，加總剛好等於 total（最大餘數法）。"""
    total = int(total)
    raw = [total * w / sum(weights) for w in weights]
    out = [int(x) for x in raw]
    rest = total - sum(out)
    for i in sorted(range(len(raw)), key=lambda i: raw[i] - out[i], reverse=True)[:rest]:
        out[i] += 1
    return out


def night_segments(onset, deep, light, rem, awake, seed):
    """
    onset：睡著的時刻（datetime 或 ISO 字串）；deep／light／rem／awake：整數分鐘；seed：字串。
    回傳 [{"start", "end", "stage"}]（ISO，帶時區就照帶），第一段從 onset 開始、最後一段是睡著的
    （清醒只出現在中間，所以 WASO＝awake 分鐘數）。
    """
    if isinstance(onset, str):
        onset = datetime.fromisoformat(onset)
    rng = random.Random(f"sonnap-demo:{seed}")
    deeps = _split(deep, _DEEP_W)
    rems = _split(rem, _REM_W)
    lights = _split(light, [1] * CYCLES)
    awake = int(awake)
    bouts = 0 if awake <= 0 else min(awake, rng.choice((1, 2, 2, 3)))
    bout_mins = _split(awake, [1] * bouts) if bouts else []
    after = sorted(rng.sample(range(1, CYCLES), bouts)) if bouts else []

    plan = []
    for i in range(CYCLES):
        a = lights[i] // 2
        plan += [("light", a), ("deep", deeps[i]), ("light", lights[i] - a), ("rem", rems[i])]
        if i + 1 in after:
            plan.append(("awake", bout_mins[after.index(i + 1)]))
    # 清醒不能是最後一段（那就變成起床了）
    while plan and plan[-1][0] == "awake":
        plan.insert(-2 if len(plan) > 2 else 0, plan.pop())

    out = []
    t = onset
    for stage, mins in plan:
        if mins <= 0:
            continue
        end = t + timedelta(minutes=mins)
        if out and out[-1]["stage"] == stage:
            out[-1]["end"] = end.isoformat()
        else:
            out.append({"start": t.isoformat(), "end": end.isoformat(), "stage": stage})
        t = end
    return out


def night_seed(w_row):
    """同一個人同一晚 → 同一個種子（評分時與畫圖時要一樣）。"""
    return f"{w_row.get('user_id')}:{w_row.get('date')}"


def awake_count(segments):
    return sum(1 for s in segments if s["stage"] == "awake")


def stages_block(w_row):
    """
    API 用：示範帳號那一晚的階梯圖，形狀同 main.night_stages（Garmin 來源）。
    用存下來的分鐘數重排一次——跟評分時是同一份段。資料不夠 → None。
    """
    if not w_row or w_row.get("source") != "demo":
        return None
    need = ("sleep_start_time", "duration_min", "deep_min", "rem_min", "waso_min")
    if any(w_row.get(k) is None for k in need):
        return None
    deep, rem = int(round(w_row["deep_min"])), int(round(w_row["rem_min"]))
    light = int(round(w_row["duration_min"])) - deep - rem
    awake = int(round(w_row["waso_min"]))
    segs = night_segments(w_row["sleep_start_time"], deep, light, rem, awake, night_seed(w_row))
    return {
        "segments": segs,
        "minutes": {"awake": awake, "rem": rem, "light": light, "deep": deep},
        "rem_measured": True,
    }
