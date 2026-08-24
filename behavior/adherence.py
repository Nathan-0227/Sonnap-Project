"""
behavior/adherence.py — 就寢達成度（Tier A）

═══════════════════════════════════════════════════════════════════
這一層在整個架構的哪裡
═══════════════════════════════════════════════════════════════════

    Tier A ← 就在這裡。每個使用者都有，手機自己產生，**裝置無關**
        target_bedtime      使用者設定的目標
        lights_out_at       手機最後一次互動的時間
        adherence_minutes   兩者相減，正值＝拖延
        ↓
        驅動挑戰、寵物狀態、熬夜比率

    Tier B    穿戴裝置的生理資料（睡眠分數）——**本模組完全不碰**

═══════════════════════════════════════════════════════════════════
⚠️ 架構紅線：本套件（behavior/）絕不 import 評分層
═══════════════════════════════════════════════════════════════════
`PROJECT_STATUS.md` 8.7：「遊戲化層只讀，不得回寫評分層」。

以前這條紅線只能靠紀律守住；在新架構下它是**結構上成立**的——
behavior/ 底下不會出現 garmin/evaluate_sleep_quality.py 或
apply_recovery_modifier.py 的任何引用。機械化驗收見 behavior/__init__.py
（要比對 import 行，不能單純搜關鍵字——否則會抓到說明文字本身）。

（Health Connect 的資料要算分數，那是 wearable/ 的事，不在這裡。）

═══════════════════════════════════════════════════════════════════
⚠️ lights_out_at 是替代測量（proxy），不是入睡時間
═══════════════════════════════════════════════════════════════════
手機測得到的是「最後一次操作手機」，不是「睡著」。有人放下手機後
還會躺半小時。報告中必須誠實標註成 proxy，比照本專案對
`sleep_efficiency`（非臨床真效率，因缺上床時間）與
`movement_count`（其實是取樣分鐘數）的既有處理標準。

但**對計畫書的研究問題而言，這個 proxy 正好對題**：
Kroese et al. (2014) 對睡眠拖延的定義是「在沒有外在因素阻礙的情況下，
未能在**預定時間**上床」——那是一個純粹的行為，定義裡沒有睡眠品質。
"""

from datetime import datetime, time, timedelta

# ═══════════════════════════════════════════════════════════════════
# 常數
# ═══════════════════════════════════════════════════════════════════

# 超過目標就寢時間幾分鐘算「熬夜」。
#
# ⚠️ **這是產品決定，不是文獻門檻。** 必須講清楚，因為本專案每一項
#    「計分」都有引文（見 Research-Background/Garmin手錶分數.md），
#    而這個數字沒有。之所以還是可以用，是因為它**不進任何分數**——
#    它只影響遊戲化層的挑戰達成與寵物狀態，那一層本來就與評分層隔離。
#    同理於 MOVEMENT_ACTIVE_THRESHOLD：算得出來，但刻意不納入評分。
LATE_THRESHOLD_MINUTES = 30

# 「一晚」歸屬到哪一天。
#
# 沿用 garmin/analyze_garmin_sleep.py 的「起床日」約定——2026-08-11 已用
# Garmin 原始的 calendarDate 欄位驗證過：7/10 22:42 上床、7/11 07:51 起床
# 的那一晚，Garmin 自己標記為 calendarDate=2026-07-11。
#
# 實作方式是把時間往後推 6 小時再取日期，等於「18:00 之後就算隔天那一晚」：
#     08-17 23:00 + 6h = 08-18 05:00 → 08-18  ✓
#     08-18 02:15 + 6h = 08-18 08:15 → 08-18  ✓
#     08-18 05:09 + 6h = 08-18 11:09 → 08-18  ✓
# Tier A 與 Tier B 用同一個約定，兩邊的資料才對得起來。
NIGHT_ROLLOVER_HOURS = 6

MINUTES_PER_DAY = 24 * 60


# ═══════════════════════════════════════════════════════════════════
# 時間處理
# ═══════════════════════════════════════════════════════════════════

def parse_bedtime(value):
    """把 "23:30" 轉成 time。已經是 time 就原樣回傳。"""
    if isinstance(value, time):
        return value
    hh, mm = str(value).strip().split(":")[:2]
    return time(int(hh), int(mm))


def night_date(lights_out_at):
    """
    這個時間點屬於哪一晚（回傳「起床日」的 date）。

    見 NIGHT_ROLLOVER_HOURS 的說明。
    """
    return (lights_out_at + timedelta(hours=NIGHT_ROLLOVER_HOURS)).date()


def adherence_minutes(lights_out_at, target_bedtime):
    """
    算出偏離目標就寢時間幾分鐘。**正值＝拖延，負值＝提早。**

    ⚠️ 跨午夜是這個函式唯一的難處，而且不處理的話錯得很離譜。
       目標 23:30、實際隔天 02:15，直覺相減會得到 −21 小時 15 分
       （看起來像「提早了 21 小時」），實際上是**遲了 165 分鐘**。

    解法是把差距正規化到 (−12h, +12h] 這個區間——也就是把「時鐘」
    當成環狀來看，取兩點之間較短的那一段，並保留方向。
    這比「用距中午幾分鐘換算」穩健：後者在跨越錨點時會被切開，
    本專案在評估「就寢時間標準差」那個方案時就踩過那個坑
    （橫跨中午的起床時間被算出 507 分鐘的假變異度，
    見 PROJECT_STATUS.md 6.5 排除的第二種做法）。

    回傳 float（分鐘）。
    """
    target = parse_bedtime(target_bedtime)
    target_dt = lights_out_at.replace(
        hour=target.hour, minute=target.minute, second=0, microsecond=0
    )
    diff = (lights_out_at - target_dt).total_seconds() / 60.0

    # 正規化到 (−720, 720]
    diff = (diff + MINUTES_PER_DAY / 2) % MINUTES_PER_DAY - MINUTES_PER_DAY / 2
    return float(diff)


def is_late(minutes, threshold=LATE_THRESHOLD_MINUTES):
    """超過門檻算熬夜。見 LATE_THRESHOLD_MINUTES 的說明（產品決定，非文獻）。"""
    return minutes is not None and minutes > threshold


# ═══════════════════════════════════════════════════════════════════
# 對外主函式
# ═══════════════════════════════════════════════════════════════════

def evaluate_night(lights_out_at, target_bedtime, source="phone"):
    """
    把一晚的原始行為資料算成可以存進 nightly_behavior 的欄位。

    lights_out_at 可以是 datetime 或 ISO8601 字串；**允許為 None**
    （那一晚沒測到——例如手機關機、或使用者沒授權使用情況存取）。
    None 時 adherence 與 is_late 都是 None，不是 0：
    「沒測到」與「準時」是完全不同的兩件事，混在一起就再也分不開了。
    這跟 payload 裡那三個誠實的 null 是同一個原則。

    回傳可直接展開給 db.upsert_nightly_behavior() 的 dict。
    """
    if isinstance(lights_out_at, str):
        lights_out_at = datetime.fromisoformat(lights_out_at)

    if lights_out_at is None:
        return {
            "date": None,
            "target_bedtime": _fmt(target_bedtime),
            "lights_out_at": None,
            "adherence_minutes": None,
            "is_late": None,
            "source": source,
        }

    minutes = adherence_minutes(lights_out_at, target_bedtime)
    return {
        "date": night_date(lights_out_at).isoformat(),
        "target_bedtime": _fmt(target_bedtime),
        "lights_out_at": lights_out_at.isoformat(),
        "adherence_minutes": round(minutes, 1),
        "is_late": is_late(minutes),
        "source": source,
    }


def late_night_ratio(rows):
    """
    熬夜比率——計畫書圖五統計頁那個「過去 30 天熬夜比率 40%」。

    分母刻意是「**有測到資料**的夜數」而不是「日曆天數」。
    理由跟 compute_streak() 的 docstring 是同一件事：
    把沒資料的日子當成「沒熬夜」會讓數字好看但沒有意義，
    而把它當成「熬夜」則是憑空捏造。只算測得到的，並把
    recorded_nights 一起回傳讓呼叫端知道樣本有多大。

    回傳 (ratio_or_None, late_nights, recorded_nights)。
    """
    recorded = [r for r in rows if r.get("is_late") is not None]
    if not recorded:
        return None, 0, 0
    late = sum(1 for r in recorded if r["is_late"])
    return round(late / len(recorded), 3), late, len(recorded)


def bedtime_spread_minutes(rows):
    """
    最近幾晚的就寢時間有多分散（分鐘）——挑戰 `consistency` 的標的。

    ⚠️ 這是對 PROJECT_STATUS.md 8.6 的必要修正。8.6 寫「挑戰標的用 SRI」，
       但那是在「單使用者、有手錶」的前提下寫的——**SRI 需要 Garmin 的
       睡眠時間軸，而 D2 的受測者沒有錶**。這裡改用 lights_out_at 的收斂
       程度：同一個構念（作息規律性）、同樣是**個人內比較**，因此同樣繞開
       6.5 的顧慮（不同計算方法算出的 SRI 不能對照外部常模）；
       但資料來源換成每個人都有的手機。

    ⚠️ 環狀平均：就寢時間跨午夜，直接對「小時數」取平均會出事——
       23:50 與 00:10 的算術平均是 12:00（正中午），實際上只差 20 分鐘。
       所以先挑一個參考點，把每一晚換算成「相對參考點幾分鐘」
       （用同一套 (−12h, +12h] 正規化），再算離散度。

    回傳 (最大偏離量, 樣本數)；不足兩晚回傳 (None, n)。
    """
    times = [
        datetime.fromisoformat(r["lights_out_at"])
        for r in rows
        if r.get("lights_out_at")
    ]
    if len(times) < 2:
        return None, len(times)

    # 以第一晚當參考點，其餘換算成相對偏移
    ref = times[0]
    offsets = []
    for t in times:
        aligned = t.replace(year=ref.year, month=ref.month, day=ref.day)
        d = (aligned - ref).total_seconds() / 60.0
        d = (d + MINUTES_PER_DAY / 2) % MINUTES_PER_DAY - MINUTES_PER_DAY / 2
        offsets.append(d)

    # 再以這些偏移的平均為中心，回報最大偏離
    center = sum(offsets) / len(offsets)
    spread = max(abs(o - center) for o in offsets)
    return round(spread, 1), len(times)


def _fmt(target_bedtime):
    """把 time 或 "23:30" 統一成 "HH:MM" 字串存進資料庫。"""
    t = parse_bedtime(target_bedtime)
    return f"{t.hour:02d}:{t.minute:02d}"
