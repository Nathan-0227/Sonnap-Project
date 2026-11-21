"""
ai/chat_period.py —— 助理的問題問的是哪一晚、哪一週（2026-11-22 使用者 grill 定）。

純函式、只用標準庫：從問題裡抓時間詞，**不問 AI**（問 AI 每題多花一次額度）。

    最近一晚   last night、yesterday、tonight、this morning   → {"kind": "latest"}
    單晚       星期幾（全名／縮寫，可加 last、night）、11/18、Nov 18、November 18、18 Nov
               → {"kind": "night", "date": 起床那天}
    一段時間   this week（週一到今天）、last week（上週一到週日）、
               past week／last 7 days／past 7 days（今天往回 7 晚）
               → {"kind": "range", "start", "end"}（起床日）

⚠️ 一晚記在**起床那天**（同 behavior/adherence.night_date、早晨報告的標題）。使用者說
   「Tuesday」指的是星期二晚上睡的那一晚＝星期三那一晚；星期幾取**最近一個已經睡完的**
   （今天星期二早上問 Tuesday → 上週二晚上睡的那一晚）。
⚠️ 一題出現兩個時間詞只取第一個（比較兩晚這次不做）。
⚠️ 「the night before」這類相對說法不認，當作沒有時間詞。
"""
import re
from datetime import date, timedelta

# 能問多遠（含今天，日曆天）。超過就照實說沒資料，不偷換成最近一晚。
MAX_DAYS_BACK = 30

_WEEKDAYS = {
    "monday": 0, "mon": 0,
    "tuesday": 1, "tues": 1, "tue": 1,
    "wednesday": 2, "wed": 2,
    "thursday": 3, "thurs": 3, "thur": 3, "thu": 3,
    "friday": 4, "fri": 4,
    "saturday": 5, "sat": 5,
    "sunday": 6, "sun": 6,
}
_MONTHS = {
    "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3,
    "april": 4, "apr": 4, "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7,
    "august": 8, "aug": 8, "september": 9, "sept": 9, "sep": 9,
    "october": 10, "oct": 10, "november": 11, "nov": 11, "december": 12, "dec": 12,
}
_WD = "|".join(sorted(_WEEKDAYS, key=len, reverse=True))
_FULL_WD = "monday|tuesday|wednesday|thursday|friday|saturday|sunday"
_MO = "|".join(sorted(_MONTHS, key=len, reverse=True))

# 每一種說法一條規則；全部找出來之後取**在問題裡最先出現**的那一個。
_PATTERNS = [
    ("latest", re.compile(r"\b(last night|yesterday|tonight|this morning)\b", re.I)),
    ("this_week", re.compile(r"\bthis week\b", re.I)),
    ("last_week", re.compile(r"\blast week\b", re.I)),
    ("last7", re.compile(r"\b(past week|last 7 days|past 7 days|last seven days|past seven days)\b", re.I)),
    ("md", re.compile(r"\b(\d{1,2})/(\d{1,2})\b")),
    ("month_day", re.compile(rf"\b({_MO})\.?\s+(\d{{1,2}})(?:st|nd|rd|th)?\b", re.I)),
    ("day_month", re.compile(rf"\b(\d{{1,2}})(?:st|nd|rd|th)?\s+({_MO})\b", re.I)),
    # 全名哪裡都算；縮寫（sat、sun、wed 是常見字：「the sun woke me」）要前面有 on／last
    # 或後面接 night 才算
    ("weekday", re.compile(rf"\b({_FULL_WD})\b", re.I)),
    ("weekday", re.compile(rf"\b(?:on|last)\s+({_WD})\b\.?", re.I)),
    ("weekday", re.compile(rf"\b({_WD})\.?\s+night\b", re.I)),
]


def _bed_date_to_night(bed):
    return bed + timedelta(days=1)


def _from_month_day(month, day, today):
    """今年那一天晚上睡的那一晚；算出來是未來就當成去年。日期不存在回 None。"""
    for year in (today.year, today.year - 1):
        try:
            night = _bed_date_to_night(date(year, month, day))
        except ValueError:
            return None
        if night <= today:
            return night
    return None


def _match(kind, m, today):
    if kind == "latest":
        return {"kind": "latest"}
    if kind == "this_week":
        start = today - timedelta(days=today.weekday())
        return {"kind": "range", "start": start.isoformat(), "end": today.isoformat()}
    if kind == "last_week":
        start = today - timedelta(days=today.weekday() + 7)
        return {"kind": "range", "start": start.isoformat(), "end": (start + timedelta(days=6)).isoformat()}
    if kind == "last7":
        return {"kind": "range", "start": (today - timedelta(days=6)).isoformat(), "end": today.isoformat()}
    if kind == "weekday":
        wd = _WEEKDAYS[m.group(1).lower()]
        # 最近一個「睡完了」的：起床日（＝那天＋1）不能晚於今天
        bed = today - timedelta(days=1)
        while bed.weekday() != wd:
            bed -= timedelta(days=1)
        return {"kind": "night", "date": _bed_date_to_night(bed).isoformat()}
    if kind == "md":
        night = _from_month_day(int(m.group(1)), int(m.group(2)), today)
    elif kind == "month_day":
        night = _from_month_day(_MONTHS[m.group(1).lower()], int(m.group(2)), today)
    else:  # day_month
        night = _from_month_day(_MONTHS[m.group(2).lower()], int(m.group(1)), today)
    return {"kind": "night", "date": night.isoformat()} if night else None


def find_period(text, today):
    """一句話裡的時間詞；沒有回 None。today：伺服器當地的今天（date）。"""
    hits = []
    for kind, pattern in _PATTERNS:
        for m in pattern.finditer(text or ""):
            hits.append((m.start(), kind, m))
    for _, kind, m in sorted(hits, key=lambda h: h[0]):
        found = _match(kind, m, today)
        if found:
            return found
    return None


def resolve(question, earlier_questions, today):
    """
    這一題問的是哪一段。先看這一題；沒有時間詞就往**前面使用者自己問過的**找（新的先），
    都沒有就是最近一晚（{"kind": "latest"}）。
    """
    for text in [question, *reversed(list(earlier_questions))]:
        found = find_period(text, today)
        if found:
            return found
    return {"kind": "latest"}


def in_range(night_date, today):
    """這一晚在不在能問的範圍裡（今天往回 MAX_DAYS_BACK 天）。"""
    d = date.fromisoformat(night_date)
    return today - timedelta(days=MAX_DAYS_BACK - 1) <= d <= today


def nights_between(start, end):
    """start～end（含）每一晚的起床日。"""
    s, e = date.fromisoformat(start), date.fromisoformat(end)
    return [(s + timedelta(days=i)).isoformat() for i in range((e - s).days + 1)]
