"""
behavior/sleep_efficiency.py — 睡眠效率（行為版，Tier A）

═══════════════════════════════════════════════════════════════════
這個數字是什麼
═══════════════════════════════════════════════════════════════════

    [按「開始睡覺」]        [lights_out：放下手機]        [按「結束睡覺」]
         │                          │                          │
         ├──── 上床後滑手機 ────────┤                          │
         └──────────────── 臥床時間 TIB ──────────────────────┘

    假定睡眠時間 = 結束 − lights_out          ← 分子
    臥床時間     = 結束 − 開始                ← 分母
    睡眠效率     = 分子 ÷ 分母 × 100%

⚠️ **分子是「假定」的，不是量到的。** 它假設兩件事：
   ① 放下手機的當下就睡著了（實際上可能又躺了半小時）
   ② 整夜沒有醒來（WASO = 0）

═══════════════════════════════════════════════════════════════════
🔴 這個數字會在什麼情況下把判讀方向搞反（一定要讀完再用）
═══════════════════════════════════════════════════════════════════
把上面的式子展開：

    TIB − 假定睡眠 = lights_out − 開始 = 上床後滑手機的時間

    ⇒ 睡眠效率 = 1 − (上床後滑手機的時間 ÷ 臥床時間)

**它在代數上等於「臥床時間裡沒在滑手機的比例」。** 唯一能讓它變動的
變數是手機使用時間；睡眠本身完全不影響它。以 8 小時臥床為例：

| 上床後滑手機 | 這個數字 | 若拿 Ohayon 2017 的共識切點判讀 |
|---|---|---|
| 5 分鐘 | 99.0% | 「良好」 |
| 30 分鐘 | 93.8% | 「良好」 |
| 72 分鐘 | 85.0% | ← 良好／尚可的分界 |
| 120 分鐘 | 75.0% | ← 不良的分界 |

因此會出現兩種**方向相反**的誤判：

  · 真的睡很差的人（半夜醒著兩小時但沒碰手機）→ 99%，判讀「良好」
  · 睡得很好但睡前滑了兩小時的人            → 75%，判讀「不良」

**使用者（專題負責人）2026-09-06 知悉以上限制後，仍決定沿用「睡眠效率」
這個名稱。** 這個決定記在這裡，不是為了翻案，而是因為警語只在讀者剛好
讀到警語時有效（CLAUDE.md 開頭那條規則）——所以它必須跟著程式碼走，
而不是只寫在某一份文件裡。

═══════════════════════════════════════════════════════════════════
⚠️ 與另外兩個「效率」的關係：三個都不一樣，不可互相取代
═══════════════════════════════════════════════════════════════════

| 欄位 | 分子 | 分母 | 有文獻嗎 | 進 final_score 嗎 |
|---|---|---|---|---|
| `wearable_nightly.efficiency`（Garmin） | 手錶量的總睡眠 | 起床 − **入睡** | 🔴 門檻套錯量 | ❌ **2026-10-01 起停止計分** |
| `wearable_nightly.clinical_efficiency`（Health Connect） | 手錶量的總睡眠 | 起床 − **上床** | ✅ | ❌ 只供呈現 |
| **本模組**（手機／行為） | **假定**睡眠 | 結束 − 開始（自述） | ❌ | ❌ **絕不** |

→ 所以本模組的輸出**一定**帶著 `efficiency_basis` 一起走。
  只傳數字不傳 basis，下游就分不出它是哪一種——而三者在同一個
  API 回應裡並存，混淆的代價是使用者看到互相矛盾的兩個百分比。

═══════════════════════════════════════════════════════════════════
⚠️ 架構紅線：本套件（behavior/）絕不 import 評分層
═══════════════════════════════════════════════════════════════════
見 behavior/__init__.py。這個數字**不進任何分數**，只供呈現與行為迴圈。
"""

from datetime import datetime

# 這個數字的計算基礎。**必須與數字一起傳遞。**
# 值本身就說得出它的兩個假設，這樣即使只看到 API 回應也不會誤讀。
EFFICIENCY_BASIS = "phone_lights_out__waso_assumed_zero"

# WASO 目前恆為 0（沒有任何來源給得出它）。寫成常數而不是直接寫 0，
# 是為了讓「哪一天有 WASO 來源了」這件事有一個明確的改動點。
# ⚠️ 有來源之後不要只改這裡：分子要改成 (結束 − lights_out − WASO)，
#    而且 EFFICIENCY_BASIS 要跟著換值，否則舊資料與新資料會混在一起。
WASO_MINUTES_ASSUMED = 0

# 臥床時間短於這個就不算。低於一小時的「一晚」多半是誤觸按鈕，
# 而分母很小的時候，滑手機幾分鐘就會讓百分比劇烈跳動。
MIN_TIME_IN_BED_MINUTES = 60


def _parse(value):
    """允許 datetime 或 ISO8601 字串；None 原樣回傳。"""
    if value is None or isinstance(value, datetime):
        return value
    return datetime.fromisoformat(value)


def _blank(source, reason, bed_start=None, bed_end=None):
    """
    算不出效率的時候回這個。

    ⚠️ 每個**推導出來的**數值欄位都是 None **不是 0**：「沒測到」與
       「效率 0%」是完全不同的兩件事，混在一起就再也分不開了。
       與 adherence.evaluate_night() 同一個原則。

    ⚠️ **但使用者按過的時刻要原樣留著。** 2026-09-07 實機測到的：使用者
       按了「開始睡覺」卻忘了按「下床」，結果連 bed_start_at 都沒存進去——
       而「幾點上床」本身就是有用的資料（拿它跟攝影機的開錄時刻對照，
       就是目前唯一量得到「手機代理值偏多少」的方法）。
       算不出效率 ≠ 沒有資料。
    """
    return {
        "bed_start_at": bed_start.isoformat() if bed_start else None,
        "bed_end_at": bed_end.isoformat() if bed_end else None,
        "time_in_bed_minutes": None,
        "phone_in_bed_minutes": None,
        "assumed_sleep_minutes": None,
        "sleep_efficiency": None,
        "efficiency_basis": EFFICIENCY_BASIS,
        "efficiency_note": reason,
        "source": source,
    }


def evaluate_efficiency(bed_start_at, lights_out_at, bed_end_at, source="phone"):
    """
    算出一晚的行為版睡眠效率。

    bed_start_at / bed_end_at：使用者在畫面上按「開始／結束睡覺」的時刻。
    lights_out_at            ：手機最後一次互動（behavior/adherence.py 那個）。

    三個都允許是 datetime、ISO8601 字串或 None。任何一個缺就算不出來，
    回傳的每個數值欄位都是 None（不是 0），並在 efficiency_note 說明原因。

    回傳的 dict 可直接展開存進 nightly_behavior。
    """
    bed_start = _parse(bed_start_at)
    lights_out = _parse(lights_out_at)
    bed_end = _parse(bed_end_at)

    if bed_start is None or bed_end is None:
        return _blank(source, "no bed_start/bed_end: the user did not mark "
                              "getting into or out of bed",
                      bed_start, bed_end)
    if lights_out is None:
        return _blank(source, "no lights_out_at: last phone interaction unknown",
                      bed_start, bed_end)

    tib = (bed_end - bed_start).total_seconds() / 60
    if tib < MIN_TIME_IN_BED_MINUTES:
        return _blank(source, f"time in bed {tib:.0f} min is under the "
                              f"{MIN_TIME_IN_BED_MINUTES} min floor",
                      bed_start, bed_end)

    # 放下手機的時刻晚於起床時刻 —— 這是資料錯誤，不是一個 0% 的夜晚。
    if lights_out > bed_end:
        return _blank(source, "lights_out_at is after bed_end_at",
                      bed_start, bed_end)

    # 放下手機**早於**上床：代表上床之後就沒再碰手機。
    # 這是合理的一晚，不是錯誤 —— 滑手機時間記 0。
    phone_in_bed = max((lights_out - bed_start).total_seconds() / 60, 0.0)

    assumed_sleep = tib - phone_in_bed - WASO_MINUTES_ASSUMED
    efficiency = assumed_sleep / tib * 100

    return {
        # 原樣存回去。⚠️ 這兩個是**自述**的上床／下床時刻，不是量到的
        #    入睡／醒來 —— 欄位名刻意用 bed_ 而不是 sleep_。
        "bed_start_at": bed_start.isoformat(),
        "bed_end_at": bed_end.isoformat(),
        "time_in_bed_minutes": round(tib, 1),
        "phone_in_bed_minutes": round(phone_in_bed, 1),
        "assumed_sleep_minutes": round(assumed_sleep, 1),
        "sleep_efficiency": round(efficiency, 1),
        "efficiency_basis": EFFICIENCY_BASIS,
        # ⚠️ 這句話會被送到前端。它不是裝飾——它是這個數字唯一隨身
        #    攜帶的限制說明。改字可以，不要拿掉。
        "efficiency_note": (
            "Assumes sleep begins when the phone is put down and that there "
            "are no awakenings. Not comparable with clinical sleep efficiency."
        ),
        "source": source,
    }


# ═══════════════════════════════════════════════════════════════════
# 第二個數字：分子改用**手錶量到的**睡眠（2026-09-30 新增）
# ═══════════════════════════════════════════════════════════════════
#
# 上面那個 evaluate_efficiency() 的分子是「假定」睡眠，所以它量的其實是
# 「臥床時間裡沒在滑手機的比例」。這裡把分子換成手錶實測的總睡眠時間，
# 分母沿用同一個自述臥床區間，得到的才是真正的睡眠效率。
#
# 📖 文獻依據（Research-Background/Garmin手錶分數.md B-1、B-5 情境①）：
#    ANSI/CTA/NSF-2110 並列接受兩種分母——TIB（臥床時間）與
#    **TATS（Time Attempting to Sleep，嘗試入睡的時間）**。
#    手機「開始睡覺／結束睡覺」按鈕記錄的正是使用者宣告「我要睡了」到
#    「我起來了」的區間，在構念上**直接對應 TATS**，不是 TIB 的粗略代理。
#    因此 Ohayon 2017 的 ≥85% 切點對這個數字是適用的。
#
# 🔴 **但它仍然不進 final_score。** 兩個阻礙（見 B-5、B-6）：
#    ① 樣本：同時有手錶睡眠與按鈕區間的夜晚極少，無法驗證門檻
#    ② 公平性：不是每晚都有人按按鈕。有按的夜晚分母較大、數字較低，
#       與沒按的夜晚餵進同一組 EFFICIENCY_GOOD=85，會**系統性扣按按鈕者的分**，
#       而差異來自「有沒有按」不是睡眠本身。
#    → 照 SRI 的先例：照算、照顯示、標 basis、不進 total_modifier。

MEASURED_EFFICIENCY_BASIS = "watch_tst__phone_tats"

# 手錶睡眠允許超出自述臥床區間多少分鐘。
#
# 超過就是矛盾——不可能睡得比「嘗試入睡的時間」還久。成因通常是按鈕按錯
# （例如忘了按「開始睡覺」、隔天才補按），不是睡眠本身的性質。
# ⚠️ **不夾平成 100%。** 那正是 2026-06-27 那個 bug 的形狀：靜默夾平會讓
#    一列矛盾的資料看起來完全正常（見 extract_sleep_features 的同名常數）。
#    這裡一律回 None 並在 note 說明，「算不出來」與「效率 100%」必須分得開。
MAX_SLEEP_OVER_TATS_MINUTES = 1.0


def _hm(minutes):
    """
    分鐘 → 給人讀的「8 h 40 m」。

    ⚠️ 只用在**要給使用者看的句子**裡。畫面上寫「520 min」沒有錯，但沒有人
       會在腦中把它換算成八個多小時——而這幾句話存在的目的正是讓人一眼看出
       「手錶量到的」與「你自己標的」差多少。
    """
    total = int(round(minutes))
    h, m = divmod(total, 60)
    return f"{h} h {m} m" if h else f"{m} m"


def measured_efficiency(total_sleep_minutes, time_in_bed_minutes):
    """
    手錶實測睡眠 ÷ 自述臥床（TATS）。回傳 dict；算不出來時每個數值欄位是 None。

    total_sleep_minutes：手錶量到的總睡眠（`wearable_nightly.total_sleep_minutes`）
    time_in_bed_minutes：evaluate_efficiency() 算好的臥床分鐘數（結束 − 開始）

    ⚠️ **純函式，不讀資料庫、不 import 評分層。** 兩份資料分別來自
       nightly_behavior 與 wearable_nightly，而它們的寫入時機不固定
       （手機早上自己上傳、手錶要有人跑 morning_import），所以**由呼叫端
       在讀取時 join**，不在寫入時算、也不存進資料庫——存了就會有
       「手錶晚到那晚永遠是 null」的問題。
    """
    def blank(reason):
        return {
            "measured_efficiency": None,
            "measured_efficiency_basis": MEASURED_EFFICIENCY_BASIS,
            "measured_efficiency_note": reason,
        }

    # ⚠️ 下面每一句**都會原封不動出現在手機畫面上**（Insights 頁那張
    #    「Sleep Efficiency (measured)」卡片直接顯示 note，不改寫一個字——
    #    改寫就會有第二份說法，而兩份漂移時不會有任何錯誤訊息）。
    #    所以這些句子要用**對使用者說話**的寫法：
    #      ① 第二人稱（your / you），不要寫 "the user"
    #      ② 不要出現欄位名（`bed_start` 之類）——那是給 API 讀的，
    #         畫面上出現就變成一行 log
    #      ③ 做得到的事要講出來，而且**照抄 App 上按鈕的字**
    #         （`Start sleep` / `Out of bed`，與 challenges.py 同一組字）
    #    `tests/test_sleep_efficiency.py`【6】有幾條在守這三點。
    if total_sleep_minutes is None:
        return blank(
            "No sleep data from your watch for this night yet, so there is "
            "nothing to compare your bed marks with."
        )
    if not time_in_bed_minutes:
        return blank(
            "You didn't mark this night. Tap Start sleep when you get into "
            "bed and Out of bed when you get up, and this can be worked out "
            "for you."
        )

    tst = float(total_sleep_minutes)
    tats = float(time_in_bed_minutes)
    if tst <= 0:
        return blank(
            "Your watch recorded no sleep at all for this night, so there is "
            "nothing to divide."
        )

    if tst - tats > MAX_SLEEP_OVER_TATS_MINUTES:
        # ⚠️ 兩個時長都要講出來，使用者才看得出是哪一邊不對勁。
        #    **不要只說「資料有誤」**——那等於要人家自己去猜。
        return blank(
            f"Your watch recorded {_hm(tst)} of sleep, but the window you "
            f"marked is only {_hm(tats)} long. One of the two bed marks is "
            f"probably off, so no figure is shown for this night."
        )

    return {
        "measured_efficiency": round(min(tst / tats * 100, 100.0), 1),
        "measured_efficiency_basis": MEASURED_EFFICIENCY_BASIS,
        # ⚠️ 這句會送到前端。它說明分子分母各自從哪來——前端同時拿得到
        #    三、四個叫「效率」的數字，只有 basis 與這句話分得開它們。
        # ⚠️ 「不進分數」那半句不能省：這個數字看起來就像一般的睡眠效率，
        #    少了那半句，使用者會以為它影響了分數。
        "measured_efficiency_note": (
            "The sleep your watch measured, as a share of the time you said "
            "you were trying to sleep - from when you tapped Start sleep to "
            "when you tapped Out of bed. Shown for information only; it never "
            "affects your sleep score."
        ),
    }


def phone_in_bed_share(row):
    """
    「上床後滑手機」佔臥床時間的比例（%）。

    這是同一份資料的另一種寫法：`100 − sleep_efficiency`。之所以另外
    給一個函式，是因為**這個方向才是這份資料真正量到的東西**，
    行為迴圈（挑戰、寵物狀態）應該讀它而不是讀效率——使用者控制得了
    「躺下後少滑 20 分鐘」，控制不了「今晚別醒來」。
    """
    tib = row.get("time_in_bed_minutes")
    phone = row.get("phone_in_bed_minutes")
    if not tib or phone is None:
        return None
    return round(phone / tib * 100, 1)
