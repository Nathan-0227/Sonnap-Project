"""
behavior/journey.py — 睡眠計畫的 Journey：把起床一站一站往前移（2026-11-19）

═══════════════════════════════════════════════════════════════════
規則（全部在 Research-Background/睡眠計畫.md「使用者決定」與「Journey」兩節）
═══════════════════════════════════════════════════════════════════
- 一站提早 STEP_MINUTES（30）分鐘                         ← 文獻：Gradisar 2011、Lack 2007
- 先移起床，就寢＝起床 − 睡眠長度                          ← 文獻：Sharkey 2011、Burgess 2006
- 睡眠長度**由使用者自己定、不設下限**（11-19 使用者改：每個人需要的不一樣）；
  畫面上只照抄 RECOMMENDED_SLEEP_MINUTES（7 小時，Hirshkowitz 2015）當參考
- 第 1 站＝起點 − 30，開始那晚就生效
- 最後一站不滿 30 分鐘就只走剩下的，剛好停在終點
- 連續 ON_TIME_IN_A_ROW（3）天準時起床才前進               ← 🔴 設計決策，沒有文獻
  沒準時 → 從 0 重數；沒量到 → 不算也不打斷；永遠不退站
- 在最後一站也連續 3 天準時 → 走完（done）
- 終點不比起點早（想往後移）→ 不建立                       ← 查到的文獻全是往前移
- 起點建議：最近 7 晚實際起床的中間值，取到 5 分鐘；量到的不到 3 晚就不給
                                                         ← 🔴 設計決策，沒有文獻

「準時」照抄 behavior/wake.py 併進每一列的 `up_on_time`（每晚用當晚的目標快照判），
這裡不另外判——判準只有一份。

⚠️ 進度是**每次從頭重算**的（同挑戰引擎）：手錶資料晚到、使用者事後補按鈕，
   重算一次就對了。存在資料庫的 stop_index 只用來知道「剛剛前進了沒」。
⚠️ 不進評分、不給 XP、不改寵物心情（紅線 4、5）。
"""

from datetime import datetime, timedelta
from statistics import median

STEP_MINUTES = 30
ON_TIME_IN_A_ROW = 3          # 🔴 設計決策；取 3 與挑戰「Three nights in a row」一致
RECOMMENDED_SLEEP_MINUTES = 7 * 60  # Hirshkowitz 2015（P1 的 7–9 小時的下限）；只給畫面當參考，不擋
SUGGEST_NIGHTS = 7            # 🔴 設計決策
SUGGEST_MIN_MEASURED = 3      # 🔴 設計決策
SUGGEST_ROUND_MINUTES = 5
DAY = 24 * 60

STATUS_ACTIVE = "active"
STATUS_DONE = "done"
STATUS_STOPPED = "stopped"


def to_minutes(hhmm):
    h, m = hhmm.split(":")
    return int(h) * 60 + int(m)


def to_hhmm(minutes):
    minutes %= DAY
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


def advance_minutes(start_wake, end_wake):
    """
    起點到終點要提早幾分鐘（跨午夜取「往前」那一段）。

    終點不比起點早（一樣，或往前要超過 12 小時＝其實是往後移）→ None。
    """
    delta = (to_minutes(start_wake) - to_minutes(end_wake)) % DAY
    if delta == 0 or delta > DAY // 2:
        return None
    return delta


def stops(start_wake, end_wake):
    """每一站的起床時間（"HH:MM"），第 1 站＝起點 − 30，最後一站＝終點。"""
    delta = advance_minutes(start_wake, end_wake)
    if delta is None:
        return []
    start = to_minutes(start_wake)
    out, moved = [], 0
    while moved < delta:
        moved = min(moved + STEP_MINUTES, delta)
        out.append(to_hhmm(start - moved))
    return out


def bedtime_for(wake_hhmm, sleep_minutes):
    return to_hhmm(to_minutes(wake_hhmm) - sleep_minutes)




def first_night_for(moment):
    """
    在 moment 按下開始，從哪一晚開始算（跟 nightly_behavior.date 同一個約定：
    時刻＋6 小時落在哪一天）。

    白天（06:00–18:00）按的：今天早上已經起床了，算的是**今晚**＝明天那個日期。
    晚上或半夜按的：還沒睡，就是這一晚。
    """
    if 6 <= moment.hour < 18:
        return (moment.date() + timedelta(days=1)).isoformat()
    return (moment + timedelta(hours=6)).date().isoformat()


def progress(rows, first_night, n_stops):
    """
    從每晚的準時起床重算進度。

    rows：behavior/wake.annotate_rows() 之後的行為列（要有 date、up_on_time）。
    回傳 (stop_index, streak, done)。
    """
    idx, streak, done = 0, 0, False
    for r in sorted(rows, key=lambda r: r["date"]):
        if r["date"] < first_night:
            continue
        ok = r.get("up_on_time")
        if ok is None:          # 沒量到：不算、也不打斷
            continue
        if not ok:              # 沒準時：從 0 重數（不退站）
            streak = 0
            continue
        streak += 1
        if streak >= ON_TIME_IN_A_ROW:
            if idx >= n_stops - 1:
                done, streak = True, 0
                break
            idx += 1
            streak = 0
    return idx, streak, done


def suggested_start(rows):
    """
    最近 SUGGEST_NIGHTS 晚實際起床（按鈕，沒有就手錶）的中間值，取到 5 分鐘。
    量到的不到 SUGGEST_MIN_MEASURED 晚 → None（App 退回轉盤上的起床時間）。
    """
    measured = [r for r in sorted(rows, key=lambda r: r["date"]) if r.get("wake_at")]
    recent = measured[-SUGGEST_NIGHTS:]
    if len(recent) < SUGGEST_MIN_MEASURED:
        return None
    minutes = [datetime.fromisoformat(r["wake_at"]).hour * 60
               + datetime.fromisoformat(r["wake_at"]).minute for r in recent]
    m = median(minutes)
    return to_hhmm(int(round(m / SUGGEST_ROUND_MINUTES)) * SUGGEST_ROUND_MINUTES)


def describe(journey, idx, streak, done):
    """API 回應：一站一站的時間、現在第幾站、連續幾天。"""
    sleep = journey["sleep_minutes"]
    wakes = stops(journey["start_wake"], journey["end_wake"])
    idx = min(idx, max(len(wakes) - 1, 0))
    return {
        "status": journey["status"],
        "start_wake": journey["start_wake"],
        "end_wake": journey["end_wake"],
        "sleep_minutes": sleep,
        "first_night": journey["first_night"],
        "stops": [{"wake": w, "bedtime": bedtime_for(w, sleep)} for w in wakes],
        "stop_index": idx,
        "on_time_streak": 0 if done else streak,
        "on_time_needed": ON_TIME_IN_A_ROW,
        "current": ({"wake": wakes[idx], "bedtime": bedtime_for(wakes[idx], sleep)}
                    if wakes else None),
    }
