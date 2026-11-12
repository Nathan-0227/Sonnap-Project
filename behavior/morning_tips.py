"""
早晨報告的小建議（2026-11-12）。

一晚最多挑一句，**逐字**來自這份清單；AI 不寫建議（它寫的那段文字與建議分開顯示）。
每一句的出處、觸發條件與措辭取捨在 Research-Background/起床小建議與自評.md，
**改措辭要先改那份文件**（措辭由使用者 2026-11-12 審過）。

⚠️ 這裡只挑句子，**不碰任何分數、XP、寵物心情**（紅線 4）。
   tests/test_api.py 的紅線 4 那條會掃 behavior/ 不得 import 評分層。

⚠️ 觸發只用兩種東西：使用者自己勾的標籤（起床自評），以及後端算好的
   adherence_minutes（放下手機比目標晚幾分鐘）。量不到的事一律不觸發。
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
    "T10": ("note", "If you crossed time zones, your body clock can take a few days to catch up."),
    "T11": ("note", "Being woken up by someone else is out of your control — tonight is a fresh start."),
    "T12": ("tip", "Noise at night can disturb sleep even when you don't fully wake — a quieter bedroom helps."),
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

# 優先順序（使用者審過）：最能解釋這一晚的優先，使用者勾的優先於量到的。
PRIORITY = ["T9", "T10", "T11", "T3", "T4", "T8", "T5", "T12", "T6", "T1", "T2", "T7"]

# 放下手機比目標晚幾分鐘。⚠️ T1 與 T2 **不重疊**：原本 T2 是「≥ 60」、T1 是「≥ 30」，
# T1 排在前面，所以 T2 永遠輪不到（2026-11-12 寫程式時發現）。改成 30–59 給 T1、
# ≥ 60 給 T2——晚一小時以上講的是作息，不是最後半小時的手機。
# 30 與「三個 30 分鐘」一致；60 與挑戰「作息收斂 ±60 分鐘」一致（behavior/challenges.py）。
PHONE_LATE_MINUTES = 30
BEDTIME_LATE_MINUTES = 60


def triggered(tags=(), adherence_minutes=None):
    """這一晚觸發了哪些句子（未排序）。"""
    hits = {TAG_TIPS[t] for t in tags if t in TAG_TIPS}
    if adherence_minutes is not None:
        if adherence_minutes >= BEDTIME_LATE_MINUTES:
            hits.add("T2")
        elif adherence_minutes >= PHONE_LATE_MINUTES:
            hits.add("T1")
    # T7（運動）是唯一正向的一句：只在沒有任何其他觸發時才用，避免差的晚上被誇（紅線 5）
    if "T7" in hits and len(hits) > 1:
        hits.discard("T7")
    return hits


def pick_tip(tags=(), adherence_minutes=None):
    """
    挑一句。回傳 {"id", "kind", "text"}；這一晚沒有任何觸發就回 None
    （那晚只提醒使用者自己設的目標，不硬塞建議）。
    """
    hits = triggered(tags, adherence_minutes)
    for tip_id in PRIORITY:
        if tip_id in hits:
            kind, text = TIPS[tip_id]
            return {"id": tip_id, "kind": kind, "text": text}
    return None
