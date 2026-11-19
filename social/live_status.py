"""
social/live_status.py —— 好友頁的即時狀態：現在誰睡了、誰還沒（2026-11-19 使用者 grill 後定）。純函式。

訊號只有一個：**按 Start Sleep 的當下**，App 送一次 POST /sleep-status（Out of bed／Cancel 也各送一次）。
手機不在背景偵測、手錶也不即時，所以「睡了」只代表「按了 Start Sleep」。

四種狀態（只陳述事實，不判斷好壞）：
| 狀態          | 條件                                                         |
|---------------|--------------------------------------------------------------|
| asleep        | 按了 Start Sleep、還沒結束，而且不到 14 小時                 |
| up            | 今天按了 Out of bed，而且現在還不到 18:00                    |
| past_bedtime  | 都不是，而且現在在「目標就寢 → 之後 6 小時」之間             |
| awake         | 其他                                                         |

⚠️ **past_bedtime 不等於熬夜。** 「不按也沒關係」那條規則還在——沒按的人可能早就睡了。
   所以畫面只寫「No Start Sleep yet · 40m past bedtime」，不寫 staying up。
⚠️ 14 小時＝睡覺畫面與鬧鐘的上限（忘了按 Out of bed 的那一列自己失效）。
⚠️ 18:00＝「18:00 以前算前一晚」那條切法（behavior/adherence.NIGHT_ROLLOVER_HOURS 的另一面）。
⚠️ 6 小時＝就寢守門守的「目標後 6 小時」（app/lib/services/bedtime_guard.dart）。三個都是設計決策、沒有文獻。
⚠️ 跨午夜只用 behavior/adherence.adherence_minutes 算，不另寫一份。
⚠️ 好友看不看得到由 social/sharing 的 `live_status` 那一項決定（預設關）；這裡不管分享。
"""
from datetime import datetime, timedelta

from behavior import adherence

STATES = ("asleep", "up", "past_bedtime", "awake")
MAX_ASLEEP_HOURS = 14
UP_UNTIL_HOUR = 18
PAST_BEDTIME_WINDOW_MINUTES = 6 * 60


def _wall(s):
    """ISO 字串 → 牆鐘 datetime（不換時區：按鈕存的是手機的牆鐘時間）。"""
    if not s:
        return None
    try:
        return datetime.fromisoformat(str(s)).replace(tzinfo=None)
    except ValueError:
        return None


def _iso(t):
    return t.replace(microsecond=0).isoformat() if t else None


def live_state(row, target_bedtime, now):
    """
    row：live_sleep_status 那一列（或 None）；target_bedtime："HH:MM"；now：牆鐘 datetime。
    → {"state", "since", "minutes_past_bedtime"}。since 是牆鐘 ISO；只有 past_bedtime 有分鐘數。
    """
    row = row or {}
    started = _wall(row.get("started_at"))
    ended = _wall(row.get("ended_at"))

    if started and ended is None and started <= now < started + timedelta(hours=MAX_ASLEEP_HOURS):
        return {"state": "asleep", "since": _iso(started), "minutes_past_bedtime": None}

    if ended and ended <= now and ended.date() == now.date() and now.hour < UP_UNTIL_HOUR:
        return {"state": "up", "since": _iso(ended), "minutes_past_bedtime": None}

    if target_bedtime:
        try:
            past = adherence.adherence_minutes(now, target_bedtime)
        except (ValueError, TypeError):
            past = None
        if past is not None and 0 < past <= PAST_BEDTIME_WINDOW_MINUTES:
            since = now - timedelta(minutes=past)
            return {"state": "past_bedtime", "since": _iso(since),
                    "minutes_past_bedtime": int(past)}

    return {"state": "awake", "since": None, "minutes_past_bedtime": None}


def recent_lights_out(rows, today, days=7):
    """
    最近 days 個晚上（以 today 為終點，舊的在前）每晚幾點放下手機 → [{"date", "time"}]。
    沒資料的晚上 time 是 None（不寫成 0）。好友卡右邊那排小長條用。
    ⚠️ 12:00–18:00 的放下手機不算那一晚的就寢（同早晨報告 phone_week_sheet 的規則）。
    """
    by_date = {str(r.get("date")): r.get("lights_out_at") for r in rows or []}
    out = []
    for i in range(days - 1, -1, -1):
        d = (today - timedelta(days=i)).isoformat()
        t = _wall(by_date.get(d))
        if t is not None and 12 <= t.hour < 18:
            t = None
        out.append({"date": d, "time": f"{t.hour:02d}:{t.minute:02d}" if t else None})
    return out
