"""
social/friends.py —— 把一個朋友的行為資料組成可以分享的摘要。純函式。

⚠️ 可以分享的欄位是一份**白名單**（FRIEND_FIELDS），不是「全部減掉敏感的」。
   黑名單的寫法會在某天有人加了一個新欄位時安靜地把它分享出去；白名單的話，
   新欄位要被分享得有人刻意加進這裡。
⚠️ 這個檔案只 import 行為層（behavior/），不 import 任何讀穿戴資料或評分的模組。
"""
from datetime import timedelta

from behavior import adherence, pet_state
from behavior.challenges import _as_date, current_streak, night_achieved

FRIEND_FIELDS = (
    "handle",               # 邀請碼。好友之間的名牌，不是 user_id
    "display_name",
    "pet_mood",             # 行為版心情：happy / bored / tired / None
    "last_night_date",      # 最近一筆記錄是哪一晚（起床日）
    "last_lights_out_at",   # 那一晚幾點放下手機
    "last_night_late",      # 那一晚算不算熬夜（後端 adherence 的判斷）
    "current_streak",
    "best_streak",
    "late_night_ratio",
    "late_nights",
    "recorded_nights",
    "pet_species",          # 狗／貓（畫他的寵物用；2026-11-15）
    "streak_week",          # 這一週（週一→週日）每天：on_time / late / none / future
    # 即時狀態（2026-11-19，social/live_status.py）。分享設定的 live_status 預設關 → 三個都是 None
    "live_state",           # asleep / up / past_bedtime / awake
    "live_since",           # 那個狀態從幾點開始（牆鐘）；awake 是 None
    "minutes_past_bedtime", # 只有 past_bedtime 有；後端算好，目標時刻本身不分享
    "recent_lights_out",    # 最近 7 晚每晚幾點放下手機 [{date, time}]，好友卡右邊的小長條
)


def best_streak(rows):
    """
    有史以來最長的連續達成夜數。

    ⚠️ 與 `challenges.current_streak()` 同一條規則：**沿日曆日走，缺資料就中斷**。
       只走 rows 的順序的話，「只在表現好的日子開 App」的人會累積出假的連續紀錄
       ——獎勵就變成跟「有沒有資料」耦合（紅線 5）。
    """
    by_date = {}
    for r in rows or []:
        d = _as_date(r.get("date"))
        if d is not None:
            by_date[d] = r
    if not by_date:
        return 0

    best = run = 0
    cursor, last = min(by_date), max(by_date)
    while cursor <= last:
        row = by_date.get(cursor)
        if row is not None and night_achieved(row) is True:
            run += 1
            best = max(best, run)
        else:
            run = 0
        cursor += timedelta(days=1)
    return best


def build_friend_summary(user, handle, behavior_rows, pet_species="dog", today=None,
                         live_row=None, now=None):
    """
    一個朋友可以分享的摘要。user 是 db.get_user() 的那一列，
    handle 是他的邀請碼，behavior_rows 是他的 nightly_behavior（由舊到新）。

    ⚠️ 回傳的 key 一定剛好是 FRIEND_FIELDS。
    """
    rows = behavior_rows or []
    latest = rows[-1] if rows else None
    mood, _ = pet_state.mood_for_adherence(latest.get("adherence_minutes") if latest else None)
    ratio, late, recorded = adherence.late_night_ratio(rows)
    streak, _ = current_streak(rows)
    from datetime import date as _date
    from social.sharing import streak_week
    from datetime import datetime as _dt
    from social import live_status
    week = streak_week(rows, today or _date.today(), night_achieved)
    now = now or _dt.now()
    live = live_status.live_state(live_row, user.get("target_bedtime"), now)

    summary = {
        "handle": handle,
        "display_name": user["display_name"],
        "pet_mood": mood,
        "last_night_date": latest["date"] if latest else None,
        "last_lights_out_at": latest.get("lights_out_at") if latest else None,
        "last_night_late": (
            bool(latest["is_late"]) if latest and latest.get("is_late") is not None else None
        ),
        "current_streak": streak,
        "best_streak": best_streak(rows),
        "late_night_ratio": ratio,
        "late_nights": late,
        "recorded_nights": recorded,
        "pet_species": pet_species,
        "streak_week": week,
        "live_state": live["state"],
        "live_since": live["since"],
        "minutes_past_bedtime": live["minutes_past_bedtime"],
        "recent_lights_out": live_status.recent_lights_out(rows, today or now.date()),
    }
    assert tuple(summary) == FRIEND_FIELDS, "摘要欄位必須剛好是白名單"
    return summary


def apply_sharing(summary, settings):
    """
    照這個人的分享設定遮掉摘要裡沒公開的（2026-11-15）。遮掉＝None，**不是 0**。
    ⚠️ 欄位照舊剛好是 FRIEND_FIELDS（App 認得的形狀不變），只是值變 None。
    """
    items = settings["items"]
    out = dict(summary)
    if not items.get("phone_down_time") or settings["time_precision"] == "on_time_only":
        out["last_lights_out_at"] = None
        out["recent_lights_out"] = None
    # 即時狀態預設關（2026-11-19 使用者定）：它等於讓好友知道你此刻在不在睡
    if not items.get("live_status"):
        out["live_state"] = None
        out["live_since"] = None
        out["minutes_past_bedtime"] = None
    elif settings["time_precision"] == "on_time_only":
        # 只寫準時與否的人：狀態照給，時刻與分鐘數拿掉
        out["live_since"] = None
        out["minutes_past_bedtime"] = None
    if not items.get("on_time"):
        out["last_night_late"] = None
        out["late_night_ratio"] = None
        out["late_nights"] = None
        out["streak_week"] = None
    if not items.get("streak"):
        out["current_streak"] = None
        out["best_streak"] = None
    if not items.get("pet_mood"):
        out["pet_mood"] = None
    if not items.get("outfit"):
        out["pet_species"] = None
    assert tuple(out) == FRIEND_FIELDS
    return out


def leaderboard(summaries):
    """
    依「目前連續達成」排名，同分再比「最長連續」，再比名字。

    ⚠️ 只排行為指標。不排分數、不排深睡——那些跨裝置不能比（見 social/__init__.py）。
    """
    # 沒公開連續天數的人不上榜（遮掉的是 None）
    summaries = [s for s in summaries if s.get("current_streak") is not None]
    ordered = sorted(
        summaries,
        key=lambda s: (-s["current_streak"], -s["best_streak"], s["display_name"]),
    )
    return [
        {
            "rank": i + 1,
            "handle": s["handle"],
            "display_name": s["display_name"],
            "current_streak": s["current_streak"],
            "best_streak": s["best_streak"],
        }
        for i, s in enumerate(ordered)
    ]
