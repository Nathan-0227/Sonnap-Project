"""
寵物 notes 的建議清單（2026-11-12 起，2026-11-17 擴充）。

**「去做什麼」只能來自這份清單。** 2026-11-17 起 AI 從**後端今晚推薦的那幾條**（11-18 收緊，原本是整份清單）挑 0–3 條、換成寵物口吻
（ai/night_summary.py），但不能加清單外的行動；AI 寫不出來、或手錶資料還沒到時，
畫面顯示 applicable_tips() 挑的原句。
每一句的出處、適用時機與措辭取捨在 Research-Background/起床小建議與自評.md，
**改措辭要先改那份文件**（T1–T12 使用者 2026-11-12 審過，P1–P8 2026-11-18 審過）。

⚠️ 這裡只挑句子，**不碰任何分數、XP、寵物心情**（紅線 4）。
   tests/test_api.py 的紅線 4 那條會掃 behavior/ 不得 import 評分層——
   所以生理狀況的判讀（`judged`）由呼叫端算好傳進來，這裡只看字串。

⚠️ 適用條件只用三種東西：使用者自己勾的標籤（起床自評）、後端算好的
   adherence_minutes、後端算好的生理判讀（評分器的級距、心率比平常高或低）。
"""

# 起床自評可以勾的標籤（App 送 id，畫面顯示 label）。順序就是畫面上的順序。
TAGS = {
    "late_caffeine": "Late caffeine",
    "alcohol": "Alcohol",
    "exercise": "Exercise",
    "stress": "Stress",
    "napped": "Napped",
    "woken_by_someone": "Woken up by someone",
    "unwell": "Feeling unwell",
    "travel": "Travel",
    "noise": "Noise",
    "temperature": "Too hot / cold",
}

# 自評的五個選項：照抄 Consensus Sleep Diary-M 第 10 題（Carney 2012，論文附錄 Figure 2）。
RESTED_LABELS = {
    1: "Not at all rested",
    2: "Slightly rested",
    3: "Somewhat rested",
    4: "Well-rested",
    5: "Very well-rested",
}

# id → (種類, 句子)。種類 "tip" 教下次可以怎麼做；"note" 只解釋這一晚。
TIPS = {
    "T1": ("tip", "Try leaving your phone outside the bed for the last 30 minutes before sleep."),
    "T2": ("tip", "A steady bedtime is linked with a steadier body clock."),
    "T3": ("tip", "Caffeine even 6 hours before bed can shorten sleep — try keeping it earlier in the day."),
    "T4": ("tip", "Alcohol can help you fall asleep faster, but it tends to break up sleep later in the night."),
    "T5": ("tip", "If you nap, keeping it to about 10–20 minutes is less likely to leave you groggy."),
    "T6": ("tip", "A cool, comfortable bedroom helps — heat tends to cause more waking at night."),
    "T7": ("tip", "Regular physical activity is linked with better sleep quality."),
    "T8": ("tip", "Jotting down tomorrow's to-do list before bed helped people fall asleep faster in one sleep-lab study."),
    "T9": ("note", "When you're unwell, your body often needs more sleep — rest is part of recovering."),
    "T10": ("note", "If you crossed time zones, your body clock can take a few days to a week to catch up."),
    "T11": ("note", "Being woken up by someone else is out of your control — tonight is a fresh start."),
    "T12": ("tip", "Noise at night can disturb sleep even when you don't fully wake — a quieter bedroom helps."),
    # ── 生理狀況（2026-11-18 使用者審過；出處見研究文件「生理狀況」一節）──
    "P1": ("tip", "Most adults are recommended 7–9 hours of sleep — tonight, try giving yourself enough time in bed."),
    "P2": ("tip", "Hard workouts that end close to bedtime are linked with shorter sleep — try finishing at least 4 hours before."),
    "P3": ("tip", "Reading on a bright screen before bed cut REM sleep in one lab study — try dimming it or switching to paper."),
    "P4": ("note", "Most REM sleep comes late in the night, so a short night usually means less REM."),
    "P5": ("note", "Deep sleep follows how much sleep you need to catch up on — after a full night, less is normal."),
    "P6": ("tip", "A long or late-afternoon nap can lower deep sleep that night — keeping naps short and early helps."),
    "P7": ("tip", "Alcohol is linked with a higher heart rate in the first hours of sleep — the more you drink, the bigger the rise."),
    "P8": ("note", "Heart rate often runs higher during sleep when you have a fever — rest is part of recovering."),
}

# 什麼時候適用（交給 AI 的說明，英文）。與研究文件表格的「什麼時候適用」同義。
WHEN = {
    "T1": "phone put down 30–59 minutes after the user's target",
    "T2": "phone put down 60 or more minutes after the user's target",
    "T3": "user noted late caffeine; may also explain short sleep, more time awake, or less deep sleep",
    "T4": "user noted alcohol; may also explain more time awake later in the night or less REM",
    "T5": "user noted a nap",
    "T6": "user noted too hot / cold; may also explain short sleep, more time awake, less deep sleep or less REM",
    "T7": "user noted exercise and nothing else went wrong; a long-term statement, never a reason for one night",
    "T8": "user noted stress; only about falling asleep faster",
    "T9": "user noted feeling unwell",
    "T10": "user noted travel",
    "T11": "user noted being woken up by someone",
    "T12": "user noted noise; may also explain more time awake, less deep sleep, less REM or a higher heart rate",
    "P1": "time asleep below the recommended range",
    "P2": "user noted exercise and time asleep was short, REM was low, or sleeping heart rate was higher than usual",
    "P3": "REM was low and the phone went down after the target",
    "P4": "REM was low and time asleep was also short",
    "P5": "deep sleep was low but the previous night's time asleep was within or above the recommended range",
    "P6": "deep sleep was low and the user noted a nap",
    "P7": "sleeping heart rate higher than usual and the user noted alcohol",
    "P8": "sleeping heart rate higher than usual and the user noted feeling unwell",
}

# AI 把句子換成寵物口吻時，必須留下的重點字（任一個出現即可）。
# 這是「沒有換掉建議本身」的最低檢查：挑了 T3 卻沒提到咖啡，就是在講別的事。
KEYWORDS = {
    "T1": r"phone", "T2": r"bedtime|same time|steady|regular",
    "T3": r"caffeine|coffee", "T4": r"alcohol|drink", "T5": r"nap",
    "T6": r"cool|temperature|heat|hot|cold", "T7": r"activity|exercise|active",
    "T8": r"to-?do|list", "T9": r"unwell|sick|rest", "T10": r"time zone|travel|body clock",
    "T11": r"woken|woke", "T12": r"nois|quiet",
    "P1": r"7.9 hours|enough time in bed", "P2": r"4 hours", "P3": r"screen",
    "P4": r"late in the night|REM", "P5": r"catch up|full night", "P6": r"nap",
    "P7": r"alcohol|drink", "P8": r"fever",
}

# 標籤 → 句子
TAG_TIPS = {
    "unwell": "T9",
    "travel": "T10",
    "woken_by_someone": "T11",
    "late_caffeine": "T3",
    "alcohol": "T4",
    "stress": "T8",
    "napped": "T5",
    "noise": "T12",
    "temperature": "T6",
    "exercise": "T7",
}

# 優先順序（T 系列使用者 11-12 審過）：最能解釋這一晚的優先，使用者勾的優先於量到的。
# P 系列插在同類的 T 後面（同樣是使用者勾的標籤＋生理判讀者排前面，只靠生理判讀者排後面）。
# 只用在 AI 寫不出來／手錶資料還沒到時挑原句；AI 寫得出來時由 AI 自己挑。
PRIORITY = ["T9", "P8", "T10", "T11", "T3", "T4", "P7", "T8", "T5", "P6", "T12", "T6",
            "P2", "T1", "P3", "T2", "P1", "P4", "P5", "T7"]

# 原句最多給幾條（AI 那邊同一個上限）。紅線 5：差的晚上不能收到一長串「該改」。
MAX_TIPS = 3

# 生理判讀的字串（由 ai/night_summary.judge_night 產生，這裡只比對）
BELOW, WITHIN, ABOVE = "below the recommended range", "within the recommended range", "above the recommended range"
HR_HIGHER = "higher than your usual"

# 放下手機比目標晚幾分鐘。⚠️ T1 與 T2 **不重疊**：原本 T2 是「≥ 60」、T1 是「≥ 30」，
# T1 排在前面，所以 T2 永遠輪不到（2026-11-12 寫程式時發現）。改成 30–59 給 T1、
# ≥ 60 給 T2——晚一小時以上講的是作息，不是最後半小時的手機。
# 30 與「三個 30 分鐘」一致；60 與挑戰「作息收斂 ±60 分鐘」一致（behavior/challenges.py）。
PHONE_LATE_MINUTES = 30
BEDTIME_LATE_MINUTES = 60


def triggered(tags=(), adherence_minutes=None, judged=None):
    """
    這一晚適用哪些句子（未排序）。

    judged：後端算好的生理判讀，鍵為 time_asleep / previous_time_asleep / deep_sleep /
    rem_sleep / sleeping_heart_rate，值是上面那幾個常數字串；沒有手錶資料就給 None
    （那時只看標籤與放下手機）。
    """
    tags = set(tags)
    hits = {TAG_TIPS[t] for t in tags if t in TAG_TIPS}
    if adherence_minutes is not None:
        if adherence_minutes >= BEDTIME_LATE_MINUTES:
            hits.add("T2")
        elif adherence_minutes >= PHONE_LATE_MINUTES:
            hits.add("T1")
    j = judged or {}
    short = j.get("time_asleep") == BELOW
    rem_low = j.get("rem_sleep") == BELOW
    deep_low = j.get("deep_sleep") == BELOW
    hr_high = j.get("sleeping_heart_rate") == HR_HIGHER
    if short:
        hits.add("P1")
    if "exercise" in tags and (short or rem_low or hr_high):
        hits.add("P2")
    if rem_low and adherence_minutes is not None and adherence_minutes > 0:
        hits.add("P3")
    if rem_low and short:
        hits.add("P4")
    if deep_low and j.get("previous_time_asleep") in (WITHIN, ABOVE):
        hits.add("P5")
    if deep_low and "napped" in tags:
        hits.add("P6")
    if hr_high and "alcohol" in tags:
        hits.add("P7")
    if hr_high and "unwell" in tags:
        hits.add("P8")
    # T7（運動）是唯一正向的一句：只在沒有任何其他觸發時才用，避免差的晚上被誇（紅線 5）
    if "T7" in hits and len(hits) > 1:
        hits.discard("T7")
    return hits


def tip_dict(tip_id):
    kind, text = TIPS[tip_id]
    return {"id": tip_id, "kind": kind, "text": text}


def applicable_tips(tags=(), adherence_minutes=None, judged=None, limit=MAX_TIPS):
    """
    依優先順序挑最多 limit 句原句。回傳 [{"id", "kind", "text"}]，沒有就是空清單
    （不硬塞建議）。用在 AI 寫不出來、或手錶資料還沒到的時候。
    """
    hits = triggered(tags, adherence_minutes, judged)
    return [tip_dict(t) for t in PRIORITY if t in hits][:limit]


def pick_tip(tags=(), adherence_minutes=None, judged=None):
    """挑最優先的一句；沒有就回 None。"""
    picked = applicable_tips(tags, adherence_minutes, judged, limit=1)
    return picked[0] if picked else None
