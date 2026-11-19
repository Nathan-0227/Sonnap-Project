"""
behavior/wake.py — 準時起床（睡眠計畫 M3，2026-11-19）

═══════════════════════════════════════════════════════════════════
這是什麼
═══════════════════════════════════════════════════════════════════
睡眠計畫的核心是「每天差不多時間睡、差不多時間起」。就寢那一端已經有
`adherence.py`（放下手機 vs 目標就寢）；這支補上起床那一端：
**實際起床 vs 目標起床，差在 ±60 分鐘內算準時。**

依據與取捨全在 `Research-Background/睡眠計畫.md` 主題 1 與「使用者決定」：
- 固定起床出自 Bootzin & Perlis 2011（刺激控制法擴充的第 5 條），
  ⚠️ **不是 Bootzin 1972**——原文四條指示沒有一條講起床時刻。
- ±60：Bootzin & Perlis 2011「休假日與上班日差 < 1 小時」與 Windred 2024
  的 1 小時窗格。兩個都是**臨床慣例／觀察描述，不是切點研究**。
- 七天都算（不分平日週末）：同上，Bootzin & Perlis 2011「all 7 days」。

═══════════════════════════════════════════════════════════════════
起床時刻從哪來（使用者 2026-11-19 定）
═══════════════════════════════════════════════════════════════════
    ① Out of bed 按鈕（nightly_behavior.bed_end_at；當下按、事後補都算，
       同效率的規則）
    ② 手錶認定的起床（wearable_nightly.wake_time）
    ③ 都沒有 → None（「沒量到」，不是「沒做到」）

不做「手機早上第一次解鎖」：要另寫一套偵測，而且賴床滑手機會被當成起床。

⚠️ 這兩個不是同一個量：按鈕是「離開床」，手錶是「醒來」（通常比較早）。
   所以每一晚都帶 `wake_source`，畫面上可以分開標。

⚠️ 手錶的起床是**時刻**（幾點醒），不是生理結果（深睡幾分鐘）。挑戰的標的
   仍然是使用者控制得了的行為——鬧鐘訂幾點、幾點下床。

═══════════════════════════════════════════════════════════════════
⚠️ 時間一律當牆鐘讀
═══════════════════════════════════════════════════════════════════
`bed_end_at` 不帶時區、`wake_time` 帶 `+08:00`。拿掉時區、**不做換算**，
理由同 `sleep_efficiency._wall()`（換算 UTC 會差 8 小時）。
"""

from datetime import datetime

from .adherence import adherence_minutes, parse_bedtime

# 起床在目標前後幾分鐘內算準時。出處見檔頭（臨床慣例，不是切點）。
# ⚠️ 跟挑戰「Steady bedtime ±60」同一個數字，但那是就寢端的離散度，這是起床端
#    跟目標的距離——兩件事，改一個不必改另一個。
WAKE_TOLERANCE_MINUTES = 60.0

WAKE_SOURCE_BUTTON = "button"
WAKE_SOURCE_WATCH = "watch"


def _wall(value):
    """字串或 datetime → 不帶時區的牆鐘 datetime；None 原樣回傳。"""
    if value is None:
        return None
    if isinstance(value, str):
        value = datetime.fromisoformat(value)
    return value.replace(tzinfo=None) if value.tzinfo is not None else value


def wake_moment(bed_end_at, watch_wake_time):
    """
    這一晚的起床時刻與來源。按鈕優先，沒有才用手錶。

    回傳 (datetime, "button"|"watch")，都沒有回 (None, None)。
    """
    if bed_end_at:
        return _wall(bed_end_at), WAKE_SOURCE_BUTTON
    if watch_wake_time:
        return _wall(watch_wake_time), WAKE_SOURCE_WATCH
    return None, None


def wake_adherence_minutes(wake_at, target_wake):
    """
    起床偏離目標幾分鐘。正值＝晚起，負值＝早起。

    跨午夜的正規化直接用 `adherence.adherence_minutes()`——只有一份。
    （目標 00:30、09:00 起床這種極端設定也照樣取較短的那一段。）
    """
    if wake_at is None or not target_wake:
        return None
    return round(adherence_minutes(wake_at, parse_bedtime(target_wake)), 1)


def up_on_time(minutes, tolerance=WAKE_TOLERANCE_MINUTES):
    """
    準時起床：True／False／**None（沒量到或沒有目標）**。

    早起太多也不算準時：要的是「每天同一時刻」，不是「越早越好」。
    """
    if minutes is None:
        return None
    return abs(minutes) <= tolerance


def evaluate_wake(bed_end_at, watch_wake_time, target_wake):
    """
    一晚的起床判定，回傳可以直接併進行為列的欄位。

        wake_at                 "YYYY-MM-DDTHH:MM:SS"（牆鐘）或 None
        wake_source             "button" / "watch" / None
        wake_adherence_minutes  float 或 None
        up_on_time              True / False / None
    """
    wake_at, source = wake_moment(bed_end_at, watch_wake_time)
    minutes = wake_adherence_minutes(wake_at, target_wake)
    return {
        "wake_at": wake_at.isoformat() if wake_at else None,
        "wake_source": source,
        "wake_adherence_minutes": minutes,
        "up_on_time": up_on_time(minutes),
    }


def annotate_rows(behavior_rows, watch_wake_by_date):
    """
    把起床判定併進每一列行為資料（回傳新的 list，不改傳進來的）。

    watch_wake_by_date：{"YYYY-MM-DD": wake_time 字串}，來自 wearable_nightly。
    ⚠️ 讀取時才算、不存資料庫：手錶資料常常比手機晚到（早上匯入），
       寫入時算的話手錶晚到的夜晚會永遠是 None。同 measured_efficiency。
    """
    out = []
    for r in behavior_rows:
        extra = evaluate_wake(
            r.get("bed_end_at"),
            watch_wake_by_date.get(r.get("date")),
            r.get("target_wake"),
        )
        out.append({**r, **extra})
    return out
