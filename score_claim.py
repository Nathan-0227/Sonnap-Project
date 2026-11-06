"""
score_claim.py — 這個分數宣稱自己是什麼，以及哪幾項的門檻效度存疑。

═══════════════════════════════════════════════════════════════════
為什麼要單獨一個模組
═══════════════════════════════════════════════════════════════════

「分數由哪幾項組成」這件事有**兩個消費端**，而它們拿不到同一份資料：

    main.py（API）          讀資料庫的原始度量 → 推論哪幾項有算
    build_app_payload.py    讀 pipeline 的分項得分 → 直接知道哪幾項有算

兩邊都要輸出同一組**文字與形狀**（警語怎麼寫、欄位叫什麼）。
⚠️ 而 build_app_payload **不能 import main.py**——main.py 反過來 import 了它
   （`resolve_mood` 用 `map_pet_mood`），會循環。

→ 所以文字放這裡，兩邊都 import。複製兩份的話，改了一邊而沒改另一邊，
  使用者會在 App 與 API 看到**不同的警語**，而且不會有任何錯誤訊息。

⚠️ 「哪幾項有算」這個**判準**刻意留在各自那邊（一個推論、一個直讀），
   由 tests/test_score_composition.py 拿真實資料逐夜比對。
   這與 has_measured_sleep / is_valid_night 是同一個模式：
   刻意寫兩份，用測試守住不漂移，而不是用耦合。

═══════════════════════════════════════════════════════════════════
這個分數宣稱自己是什麼（2026-10-01 使用者決定）
═══════════════════════════════════════════════════════════════════

舊的宣稱是「多維度合成的睡眠品質分數」。逐項查證後改成
**以睡眠時長為主、其他維度為輔**——四個計分項裡，只有睡眠時長的
裝置量測誤差明確小於它的判讀級距：

    分項      級距寬度（換算成分鐘）   已知裝置偏差        偏差÷級距
    duration  120 分（7–9 小時）      −16.9 分           14%      ✅
    waso       15 分                  +13.3~24.1 分      89–161%  🔴
    deep       42 分（13–23% of 7h）  高估，量級不明      算不出來 ⚠️
    rem        21 分（20–25% of 7h）  低估，量級不明      算不出來 ⚠️

**關鍵是級距寬度差了 8 倍**：同樣約 17 分鐘的誤差對 duration 無關痛癢，
對 WASO 足以翻掉一整級。完整分析見 Research-Background/Garmin手錶分數.md
的 I-0 與 E-3～E-6。

⚠️ 這是「改宣稱」不是「改結構」：分項、配分、程式邏輯一個都沒動。
"""

# 各分項的配分。⚠️ 與 evaluate_sleep_quality.WEIGHTS 必須一致，
# 但刻意不 import 那支（garmin/ 五支是各自獨立的行程、不是 package）。
# tests/test_score_composition.py 守著。
SCORE_COMPONENT_WEIGHTS = {"duration": 30, "efficiency": 25, "waso": 25, "deep": 10, "rem": 10}

# 這個分數以哪一項為主。做成欄位而不只是散文，前端才分得出
# 「四項一樣可信」與「以時長為主」的差別。
PRIMARY_SCORE_COMPONENT = "duration"

NOT_MEASURED_REASON = "not measured on this night"

# ── 睡眠效率：2026-11-07 恢復計分，三段式（behavior/sleep_efficiency.scoring_efficiency）──
# 每晚用的是哪一種寫在 efficiency_basis，這裡依它挑**那一晚的**警語。
# ⚠️ 三種都掛警語，理由各不相同——不是「沒問題的那一種不用講」：
#    ① 構念對了，但兩端是自述的、分子有已知的裝置低估
#    ② 終點是手錶給的、沒有常模
#    ③ 構念錯配（10-01 停止計分的原因），幾乎每晚拿滿
# ⚠️ basis 字串照抄 behavior/sleep_efficiency.py 的常數（刻意不 import：
#    score_claim 要保持零相依，main.py 與 build_app_payload 都 import 它）。
#    tests/test_score_composition.py 守著兩邊一致。
EFFICIENCY_CAVEATS = {
    "watch_tst__phone_tats": (
        "scored from your Start sleep and Out of bed taps: the sleep your watch "
        "measured, divided by the time you marked as trying to sleep - the "
        "definition the >=85% threshold was written for. Both taps are "
        "self-reported, and wrist devices tend to under-count total sleep by "
        "about 17 minutes, which pulls this figure down."
    ),
    "phone_bed_start__watch_wake": (
        "scored from your Start sleep tap to the time your watch says you woke "
        "up, because Out of bed was missing or could not be used. No published "
        "norm exists for this definition: the >=85% threshold is borrowed, and "
        "the watch's wake time is earlier than leaving bed, so this reads high."
    ),
    "watch_tst__watch_onset_to_wake": (
        "no sleep buttons were tapped this night, so the watch's own figure is "
        "used. It divides by (wake - sleep onset) and leaves out time awake "
        "before falling asleep, so it reads high - almost every such night gets "
        "the full points - and the >=85% threshold was not written for it."
    ),
}

# 有計分、但門檻效度存疑的分項。
#
# ⚠️ 這**不是**「沒測到」（那個走 unscored），是「測到了、也照門檻算了，
#    但那個門檻能不能套在這支錶的量測上，證據不足」。
# ⚠️ duration 刻意不在這裡：它的偏差（−16.9 分）只佔級距（120 分）的 14%，
#    是唯一誤差明確小於級距的分項。**每一項都掛警語的話，警語就沒有意義。**
# ⚠️ waso 也刻意不在這裡（2026-10-22 使用者決定）：WASO 以手錶原始值計分、
#    不校正裝置偏差，App 上不再掛警語。**這不代表問題解決了**——手錶多算
#    清醒時間（+13~24 分）與 15 分鐘的級距一樣大，約一成夜晚可能被低估一級。
#    這個限制改由報告交代（docs/REPORT_CAVEATS.md），不在產品畫面上講。
SCORED_COMPONENT_CAVEATS = {
    "deep": (
        "consumer wrist devices are 60-75% accurate at four-class sleep "
        "staging and are known to over-report deep sleep; no pooled bias in "
        "minutes is available, so the size of the error is unquantified."
    ),
    "rem": (
        "consumer wrist devices are 60-75% accurate at four-class sleep "
        "staging and are known to under-report REM - this watch reports zero "
        "REM on some nights, which are excluded rather than scored as poor."
    ),
}

COMPOSITION_NOTE = (
    "The score is renormalised to 100 over the components that were "
    "measurable on this night, so a night scored on fewer components is "
    "not directly comparable with one scored on more. Which components "
    "are available depends on the devices the user has. This is a "
    "duration-primary score, not an equally-weighted composite: sleep "
    "duration is the only component whose device measurement error is "
    "clearly smaller than the band it is graded on. See 'caveats'."
)


def compose(scored, efficiency_basis=None):
    """
    把「哪幾項有算」組成 API／payload 要回的那個 dict。

    efficiency_basis：效率有算時，這晚用的是哪一種（三種 basis 之一）。
                      決定 caveats 裡效率那一條寫什麼；沒算效率時忽略。
    scored：有算分的分項名稱（可迭代）。呼叫端自己決定怎麼判斷——
            main.py 從資料庫的原始度量推論，build_app_payload 直接讀
            pipeline 算出來的分項得分。**判準兩邊各一份，形狀與文字共用這份。**

    ⚠️ 順序照 SCORE_COMPONENT_WEIGHTS 走，不照傳進來的順序——
       同一晚在 App 與 API 的清單順序不一致會讓人以為是不同的東西。
    """
    scored_set = set(scored)
    ordered = [k for k in SCORE_COMPONENT_WEIGHTS if k in scored_set]
    unscored = [
        {"component": k, "reason": NOT_MEASURED_REASON}
        for k in SCORE_COMPONENT_WEIGHTS if k not in scored_set
    ]
    caveat_text = dict(SCORED_COMPONENT_CAVEATS)
    if efficiency_basis in EFFICIENCY_CAVEATS:
        caveat_text["efficiency"] = EFFICIENCY_CAVEATS[efficiency_basis]
    return {
        "scored": ordered,
        "unscored": unscored,
        "scored_weight": sum(SCORE_COMPONENT_WEIGHTS[k] for k in ordered),
        "primary_component": PRIMARY_SCORE_COMPONENT,
        "efficiency_basis": efficiency_basis if "efficiency" in scored_set else None,
        "caveats": [
            {"component": k, "caveat": caveat_text[k]}
            for k in ordered if k in caveat_text
        ],
        "note": COMPOSITION_NOTE,
    }
