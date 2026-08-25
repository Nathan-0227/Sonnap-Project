"""
behavior/pet_state.py — 由行為驅動的寵物狀態（Tier A）

═══════════════════════════════════════════════════════════════════
這個模組要解的問題
═══════════════════════════════════════════════════════════════════

目前寵物心情**只有一條產生路徑**：build_app_payload.py 的
QUALITY_TO_MOOD，吃的是 Garmin 的 final_quality。

    → **沒有手錶的人拿不到任何心情。**

而 D2 的受測者絕大多數沒有手錶（經費只有一支手環，且攝影機不外借）。
如果心情只能由生理資料產生，那計畫書的核心機制（情感連結驅動行為改變）
對他們就完全不存在——App 打開來是空的。

本模組補上另一條路徑：**由行為（幾點放下手機）決定心情**。
這條路徑每個人都有，因為它只需要手機。

═══════════════════════════════════════════════════════════════════
⚠️ Tier A **不產生 anxious**，這是刻意的
═══════════════════════════════════════════════════════════════════
README 的合法值有四個：happy / tired / bored / anxious。
本模組只產生前三個。

anxious 在現行系統裡的語意是**自律神經明顯偏離個人 baseline**
（build_app_payload.py 用 stress_modifier 與心率修正值判定，
兩者都是睡眠期間量到的生理訊號）。手機測不到那個東西。

拿「熬夜很多天」去生成 anxious 會讓同一個標籤有兩種來源、兩種意思，
而使用者無從分辨自己看到的是哪一種。那就是編造。
→ **anxious 保留給 Tier B。沒有穿戴裝置的人不會看到它。**

這跟本專案對 ambient_noise_db、motion_count、current_activity 一律
留 null 而不硬塞值是同一個標準。

═══════════════════════════════════════════════════════════════════
⚠️ Tier A **不產生 energy_level**
═══════════════════════════════════════════════════════════════════
energy_level 在 data contract 裡的定義是睡眠分數（build_app_payload.py
寫的是 round(final_score)）。Tier A 沒有分數。

把 adherence_minutes 換算成一個 0–100 的數字塞進去，會製造出**第二個
看起來像睡眠分數、但沒有任何文獻依據的數字**，而且它一定會被拿去跟
真的 final_score 比較。那正是本專案最不想要的東西（見紅線 2）。

→ L0 使用者的 energy_level 是 null。他們的主頁改為顯示行為指標：
  達成與否、遲了幾分鐘、連續紀錄、熬夜比率、挑戰進度。
  那些全是真的量測值，而且**正是計畫書圖五要的東西**。

═══════════════════════════════════════════════════════════════════
⚠️ 本模組絕不 import 評分層
═══════════════════════════════════════════════════════════════════
見 behavior/__init__.py。兩層要合併時（研究者本人同時有 Tier A 與
Tier B）由 API 層負責，不在這裡——那樣這個模組就會依賴評分路徑，
紅線 8.7 的結構保證就破了。
"""

from .adherence import LATE_THRESHOLD_MINUTES

# ═══════════════════════════════════════════════════════════════════
# 心情分段
# ═══════════════════════════════════════════════════════════════════
#
# ⚠️ 這裡**沒有新的門檻**，兩個切點都是既有的：
#
#     0 分鐘                    ← 挑戰的達成判準
#                                 （behavior/challenges.py 的
#                                   ACHIEVED_MAX_ADHERENCE_MINUTES）
#     LATE_THRESHOLD_MINUTES    ← 熬夜的判準（behavior/adherence.py）
#
# 沿用而不另訂，是為了讓使用者看到的三件事互相對得上：
# 「挑戰達成了」「今天沒算熬夜」「寵物是開心的」不會各講各的。
# 若這裡自己訂一組切點，就會出現「挑戰說我達成了但寵物還是累的」。
#
# 分段（adherence_minutes = 實際放下手機 − 目標就寢時間，正值＝拖延）：
#
#     <= 0                            happy   準時或提早
#     0 < x <= LATE_THRESHOLD (30)    bored   略遲，還在容忍範圍內
#     > LATE_THRESHOLD                tired   熬夜
#
# ⚠️ 紅線 5 的驗收就在這條分段上：遲三小時的夜晚必須明顯比準時的夜晚
#    拿到更差的回饋。上面的分段保證了這件事（tired vs happy），
#    而且 mood_reason 會把實際分鐘數帶出來，不是只給一個標籤。

MOOD_HAPPY = "happy"
MOOD_BORED = "bored"
MOOD_TIRED = "tired"

# 各心情對應的 UI 字串。
#
# ⚠️ 用英文是配合 App 現有介面（"Great job!"、"Sweet dreams..."），
#    沿用 build_app_payload.py 的 DISPLAY_STRINGS 既有決定，
#    不要在英文介面裡蹦出中文。i18n 方案待團隊決定。
#
# ⚠️ score_message 在 Tier A 不存在（沒有分數），所以這裡沒有那個鍵。
#    刻意不放一個空字串進去——空字串會讓 UI 以為「有這個欄位只是沒內容」，
#    缺鍵才講得清楚「這條路徑沒有這個概念」。
MOOD_STRINGS = {
    MOOD_HAPPY: {
        "mood_description": "Your buddy slept right on time!",
        "header_message": "Let's keep this rhythm going!",
        "pet_message": "You kept\nyour promise!\nThank you 🌙",
    },
    MOOD_BORED: {
        "mood_description": "Your buddy waited up a little.",
        "header_message": "So close — let's aim for on time tonight.",
        "pet_message": "I waited up\na little\nfor you...",
    },
    MOOD_TIRED: {
        "mood_description": "Your buddy stayed up waiting for you.",
        "header_message": "Let's put the phone down earlier tonight.",
        "pet_message": "I waited up\nall night...\nlet's rest.",
    },
}

# 心情對應的顏色，沿用 build_app_payload.py 的 QUALITY_TO_COLOR 色票，
# 讓兩條路徑產生的畫面在視覺上是同一套語彙。
MOOD_COLOR = {
    MOOD_HAPPY: "#9AD36A",   # 同 Good
    MOOD_BORED: "#FFC83D",   # 同 Normal
    MOOD_TIRED: "#FF9518",   # 同 Poor
}


def mood_for_adherence(adherence_minutes):
    """
    由 adherence_minutes 決定寵物心情。回傳 (mood, reason)。

    **adherence_minutes 為 None（那一晚沒測到）時回傳 (None, 原因)**，
    不回一個預設心情。理由跟整個專案一致：沒測到不是一種狀態，
    給它一個心情等於對使用者謊稱我們知道他昨晚幾點睡。
    UI 該顯示的是「昨晚沒有記錄」而不是一隻開心的狗。

    reason 會一路帶到 payload 裡，讓畫面上的心情**可以追溯到是哪一條
    規則、哪一個數字造成的**——這跟評分系統一路以來「數字要能講出理由」
    是同一個要求。
    """
    if adherence_minutes is None:
        return None, "no_data: 昨晚沒有行為記錄"

    if adherence_minutes <= 0:
        return MOOD_HAPPY, (
            f"adherence_minutes={adherence_minutes:.0f} ≤ 0（準時或提早）"
        )

    if adherence_minutes <= LATE_THRESHOLD_MINUTES:
        return MOOD_BORED, (
            f"adherence_minutes={adherence_minutes:.0f}，"
            f"在 0–{LATE_THRESHOLD_MINUTES} 分鐘的容忍範圍內"
        )

    return MOOD_TIRED, (
        f"adherence_minutes={adherence_minutes:.0f} > "
        f"{LATE_THRESHOLD_MINUTES}（判定為熬夜）"
    )


def build_pet_state(night_row):
    """
    把一晚的行為資料組成 App 要的寵物狀態區塊。

    night_row 是 db.get_nightly_behavior() 回的其中一列
    （或 behavior.adherence.evaluate_night() 的輸出，兩者欄位相同）。
    傳 None 代表完全沒有記錄。

    回傳的結構刻意與 build_app_payload.py 的 status 區塊對齊
    （pet_mood / current_activity / energy_level / mood_reason），
    這樣 App 端不需要為兩種使用者寫兩套解析。
    """
    minutes = night_row.get("adherence_minutes") if night_row else None
    mood, reason = mood_for_adherence(minutes)

    return {
        "pet_mood": mood,
        # current_activity 需要「此刻」的狀態。Tier A 只有「昨晚幾點放下手機」，
        # 給不出來，理由與 build_app_payload.py 完全相同（那邊是批次產出）。
        # 硬填一個值就是編造，留 null 讓 App fallback 到 idle 動畫。
        "current_activity": None,
        # ⚠️ 一律 null。理由見本檔案開頭——Tier A 沒有分數，
        #    換算一個出來會製造第二個沒有文獻依據的「分數」。
        "energy_level": None,
        "mood_reason": reason,
        # ── 以下是 Tier A 專屬、拿來取代 energy_level 的真實量測值 ──
        "adherence_minutes": minutes,
        "is_late": bool(night_row["is_late"]) if night_row and night_row.get("is_late") is not None else None,
        "source": "behavior",
    }


def build_display(mood):
    """
    心情對應的 UI 字串與顏色。

    mood 為 None（沒有記錄）時回一組明確說明沒資料的文案，
    **不要沿用任何一種心情的文案**——那會讓「沒測到」在畫面上
    看起來跟某一種真實狀態一模一樣。
    """
    if mood is None:
        return {
            "lang": "en",
            "score_color": "#B0B0B0",
            "mood_description": "No record for last night.",
            "header_message": "Set your bedtime and we'll start tracking.",
            "pet_message": "I didn't see\nyou last night.",
        }

    return {
        "lang": "en",
        "score_color": MOOD_COLOR.get(mood, "#FFC83D"),
        **MOOD_STRINGS[mood],
    }
