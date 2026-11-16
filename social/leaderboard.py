"""
好友排行榜（第二批，2026-11-16 共識摘要第 3 節）。**純函式**：資料由 main.py 撈好傳進來。

規則（使用者定）：
- 只是好玩，不代表誰睡得好；第一名的稱號刻意俏皮（Sleepyhead）。
- 只有**公開那一項的人**才上榜（自己沒公開也一樣不上，釘在底下的卡會說要打開哪一項）。
- **月、年用平均，不用加總**（少戴幾天錶的人不會永遠追不上）。
- 上榜門檻跟著時段：晚／日 1、週 3、月 10、年 60；不到的列在最下面「N nights so far」，沒有名次。
- 沒資料的晚上不算準時、也不算進平均。同分並列同一個名次（1, 1, 3）。
- Score 只算有按 Start Sleep 的晚上（不然大家會為了上榜故意不按，見 CLAUDE.md 三段式計分）。
- 名次變化跟上一個同長度的時段比，箭頭只代表方向（上升紅、下降綠，App 照首頁的規矩）。
- 🔴 紅線 4：這裡只讀，不寫回任何分數。

⚠️ 「準時」的判準只有一處：behavior.challenges.night_achieved（同 Streak、挑戰）。
⚠️ 作息收斂只有一處：behavior.adherence.bedtime_spread_minutes（同挑戰 Steady bedtime）。
"""
from datetime import date as _date, timedelta

from behavior.adherence import bedtime_spread_minutes
from behavior.challenges import night_achieved

# 名次表的時段
PERIOD_LABELS = {
    "now": "Now", "night": "Night", "day": "Day",
    "week": "Week", "month": "Month", "year": "Year",
}
THRESHOLD = {"now": 1, "night": 1, "day": 1, "week": 3, "month": 10, "year": 60}

# key → 分享項目、能選的時段、排序方向、第一名稱號、顯示名
METRICS = {
    "on_time": {"share": "on_time", "periods": ("week", "month", "year"),
                "higher": True, "title": "Phone-down champ", "label": "On time"},
    "streak": {"share": "streak", "periods": ("now",),
               "higher": True, "title": "On fire", "label": "Streak"},
    "steady": {"share": "phone_down_time", "periods": ("week", "month"),
               "higher": False, "title": "Clockwork", "label": "Steady"},
    "steps": {"share": "steps", "periods": ("day", "week", "month", "year"),
              "higher": True, "title": "Trailblazer", "label": "Steps"},
    "sleep": {"share": "sleep_duration", "periods": ("night", "week", "month", "year"),
              "higher": True, "title": "Sleepyhead", "label": "Sleep"},
    "score": {"share": "score", "periods": ("night", "week", "month", "year"),
              "higher": True, "title": "Top score", "label": "Score"},
}
METRIC_ORDER = ("on_time", "streak", "steady", "steps", "sleep", "score")


def window(period, today, back=0):
    """時段 → (起, 迄)（含兩端，ISO 日期字串）。back=1 是上一個同長度的時段（算箭頭用）。
    晚＝今天起床的那一晚；日＝昨天（白天資料早上才匯入）；週從週一開始；月、年是日曆的。"""
    if period == "now":  # Streak：目前連續幾晚，不分時段
        return today.isoformat(), today.isoformat()
    if period == "night":
        d = today - timedelta(days=back)
        return d.isoformat(), d.isoformat()
    if period == "day":
        d = today - timedelta(days=1 + back)
        return d.isoformat(), d.isoformat()
    if period == "week":
        start = today - timedelta(days=today.weekday()) - timedelta(weeks=back)
        end = today if back == 0 else start + timedelta(days=6)
        return start.isoformat(), end.isoformat()
    if period == "month":
        start = today.replace(day=1)
        for _ in range(back):
            start = (start - timedelta(days=1)).replace(day=1)
        if back == 0:
            return start.isoformat(), today.isoformat()
        nxt = (start + timedelta(days=32)).replace(day=1)
        return start.isoformat(), (nxt - timedelta(days=1)).isoformat()
    if period == "year":
        y = today.year - back
        return _date(y, 1, 1).isoformat(), (today if back == 0 else _date(y, 12, 31)).isoformat()
    raise ValueError(period)


def _in(rows, lo, hi):
    return [r for r in rows if lo <= str(r.get("date", "")) <= hi]


def _fmt_minutes(m):
    m = int(round(m))
    return f"{m // 60}h {m % 60}m" if m >= 60 else f"{m}m"


def measure(metric, person, lo, hi):
    """
    一個人在一段時間的成績 → (排序用的值 or None, 顯示的字, 有資料的晚／天數)。
    person：{"behavior": [...], "wearable": [...], "daily": [...], "streak": (目前, 最長)}。
    """
    if metric == "streak":
        cur, best = person.get("streak") or (None, None)
        # 0 晚不排名次（一群人並列最後一名很怪），列在最下面
        if not cur:
            return None, None, 0
        return cur, f"{cur} {'night' if cur == 1 else 'nights'} · best {best}", 1
    if metric == "on_time":
        marks = [night_achieved(r) for r in _in(person["behavior"], lo, hi)]
        marks = [m for m in marks if m is not None]  # 沒資料的晚上不算準時、也不算分母
        if not marks:
            return None, None, 0
        k = sum(1 for m in marks if m)
        # 月、年用平均＝準時的比例；同比例時準時晚數多的在前（排序鍵的第二位）
        return (k / len(marks), k), f"{k} / {len(marks)} nights", len(marks)
    if metric == "steady":
        rows = [r for r in _in(person["behavior"], lo, hi) if r.get("lights_out_at")]
        spread, n = bedtime_spread_minutes(rows)
        if spread is None:
            return None, None, n
        return spread, f"±{round(spread)}m", n
    if metric == "steps":
        # 0 步＝沒戴錶（Garmin 的慣例），不算進平均
        vals = [r["steps"] for r in _in(person["daily"], lo, hi)
                if isinstance(r.get("steps"), (int, float)) and r["steps"] > 0]
        if not vals:
            return None, None, 0
        avg = sum(vals) / len(vals)
        return avg, f"{round(avg):,} / day", len(vals)
    if metric == "sleep":
        vals = [r["duration_min"] for r in _in(person["wearable"], lo, hi)
                if isinstance(r.get("duration_min"), (int, float)) and r["duration_min"] > 0]
        if not vals:
            return None, None, 0
        avg = sum(vals) / len(vals)
        return avg, _fmt_minutes(avg), len(vals)
    if metric == "score":
        pressed = {r["date"] for r in person["behavior"] if r.get("bed_start_at")}
        vals = [r["final_score"] for r in _in(person["wearable"], lo, hi)
                if r.get("date") in pressed and isinstance(r.get("final_score"), (int, float))]
        if not vals:
            return None, None, 0
        avg = sum(vals) / len(vals)
        return avg, f"{round(avg)}", len(vals)
    raise ValueError(metric)


def rank(people, metric, period, lo, hi):
    """
    people：[{"key": 內部用的識別, "shares": bool, ...資料}]
    → (上榜的 [(key, 名次, 值, 顯示, n)], 不到門檻的 [(key, n)], 沒公開的 {key})。
    同分並列：1, 1, 3。
    """
    spec = METRICS[metric]
    need = THRESHOLD[period]
    ranked, below, hidden = [], [], set()
    for p in people:
        if not p["shares"]:
            hidden.add(p["key"])
            continue
        value, shown, n = measure(metric, p, lo, hi)
        if value is None or n < need:
            below.append((p["key"], n))
        else:
            ranked.append((p["key"], value, shown, n))
    ranked.sort(key=lambda t: t[1], reverse=spec["higher"])
    out, prev_value, prev_rank = [], object(), 0
    for i, (key, value, shown, n) in enumerate(ranked):
        r = prev_rank if value == prev_value else i + 1
        out.append((key, r, value, shown, n))
        prev_value, prev_rank = value, r
    below.sort(key=lambda t: -t[1])
    return out, below, hidden


def board(people, metric, period, today):
    """整張表（含跟上一個時段比的名次變化）。people 同 rank()，另帶 display 用的欄位。"""
    lo, hi = window(period, today)
    ranked, below, hidden = rank(people, metric, period, lo, hi)
    prev = {}
    if period != "now":
        plo, phi = window(period, today, back=1)
        prev = {key: r for key, r, *_ in rank(people, metric, period, plo, phi)[0]}
    return {"window": (lo, hi), "ranked": ranked, "below": below, "hidden": hidden, "prev": prev,
            "need": THRESHOLD[period]}
