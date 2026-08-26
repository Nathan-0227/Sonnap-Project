"""
apply_recovery_modifier.py

讀取 evaluate_sleep_quality.py 產生的 garmin_sleep_quality.csv（Tier 1/2 基礎分數），
以及 garmin_sleep_summary.csv 的心率／壓力／步數原始資料，套用 Tier 3「生理修正訊號」，
輸出：
- garmin_sleep_quality_final.csv
- garmin_sleep_quality_final.json

═══════════════════════════════════════════════════════════════════
架構依據：Research-Background/Garmin手錶分數.md「權重設定原則」
═══════════════════════════════════════════════════════════════════
Tier 1/2（睡眠時長/效率/WASO/深睡/REM）為「基礎分數」，已由 evaluate_sleep_quality.py
完整計算，本檔案不重算、不打散原始配分，只在它算好的分數上「疊加」修正值。

Tier 3 生理／作息修正訊號是「疊加在基礎分數上的有界調整值」，不佔用基礎分數配額：
  靜止心率（resting_heart_rate）偏離個人 baseline：±2
  睡眠期間平均心率（avg_heart_rate）偏離個人 baseline：±2
    （與靜止心率合計仍是 ±4，兩者拆半而非各自獨立滿額，理由見下方 2026-07-30 記錄）
  HRV／壓力偏離個人 baseline：±4（Vivoactive 3 無 HRV，以 Garmin 壓力分數替代，見 G 節）
  活動量相對 baseline：0 ～ +2（僅加分，不扣分，見 H 節設計）
  睡眠片段化（醒來次數 ±1 ＋ 睡眠段數 ±1）：±2（見下方 2026-08-10 記錄，M 節）
  修正值總上限：±12；最終分數 = clamp(基礎分數 + 修正值, 0, 100)

另外計算但「不計分」的呈現用指標：
  睡眠規律指數（Sleep Regularity Index，SRI）：照常計算並輸出數值與有效配對數，
    供報告／App 呈現數值與趨勢，但不參與修正值加總。原因是 Czeisler 2026 證實
    SRI 分數會因計算方法不同而顯著改變，本專案的近似實作無法對照外部常模計分。
    完整理由見下方 SRI 常數區塊與 2026-08-10 記錄第 5 點。

文獻依據：
  Quer et al. 2020（為何用個人化 baseline；構念對應「靜止心率」）、
  Cosgrave et al. 2021（睡眠期間平均心率與主觀睡眠品質相關；構念對應「睡眠期間平均心率」，
    原文：自評睡眠品質較差者「在幾乎所有睡眠階段的平均心率皆顯著高於良好睡眠者」）、
  Kerkering et al. 2022（訊號可靠測量）——心率修正值依據，三篇對應到不同子構念，不可互換引用。
  Van Reeth 2000、Yap 2020、Correia 2023、Chalmers 2022——壓力修正值依據。
  Kredlow 2015、Wang & Zhong 2026——活動量修正值依據。
  Phillips 2017（SRI 原始提出）、Windred 2024（SRI 預測全因死亡率優於睡眠時長，
    支持「值得呈現給使用者」）、Czeisler 2026（RIRI；證實 SRI 跨計算方法不可比，
    是本專案決定「只呈現不計分」的直接依據）、Kalkanis 2025——睡眠規律性依據。
    注意：這些文獻談的是「數週的作息規律程度」與長期健康結果的關聯，不是逐夜關聯，
    SRI 因此設計成 28 日滾動窗格的慢速訊號，詳見 2026-08-10 記錄與 compute_sri() 說明。
  片段化（M 節）沿用 WASO 相關文獻脈絡，但操作上窄化為「醒來次數＋睡眠段數」兩項新訊號，
    不含 WASO 本身（WASO 已計入 Tier1，避免同一原始數值被重複計分，詳見下方記錄）。
  完整論述見 Research-Background/Garmin手錶分數.md 的 F、G、H、J、M 節。

═══════════════════════════════════════════════════════════════════
Cold start（冷啟動）處理
═══════════════════════════════════════════════════════════════════
每項指標各自要求至少 MIN_BASELINE_NIGHTS（14）晚「有效歷史資料」才會啟用該項修正值，
不足則該項修正值為 0（不是整晚都不修正，是缺資料的那一項不修正），避免用統計上
還不具意義的雜訊資料誤導分數。baseline 只採用「當晚之前」的歷史資料（不含當晚本身），
避免當晚資料影響自己的比較基準。

═══════════════════════════════════════════════════════════════════
⚠️ 已知限制與設計變更記錄（誠實揭露）
═══════════════════════════════════════════════════════════════════
1. 【2026-07-31 擴充】原本只用 resting_heart_rate（靜止心率）算心率修正值，
   avg_heart_rate（睡眠期間平均心率）未使用。經檢查發現 F 節其實已有對應的
   文獻依據——Cosgrave et al. (2021) 講的正是「睡眠期間平均心率」（原文比較
   自評好/壞睡眠者「在幾乎所有睡眠階段的平均心率」），只是先前沒有把它接進
   程式碼。已補上 avg_heart_rate 修正值，並把原本 RHR 獨用的 ±4 額度拆成
   RHR ±2、avg_heart_rate ±2，而非兩者各自獨立滿額——因為兩者是高度相關的
   同一生理面向（心血管自律神經狀態），各給滿額會造成同一件事被重複計分，
   這跟「淺層睡眠不獨立計分，因深睡+REM+淺層=1」是同一個道理。
   Quer (2020) 對應 RHR 這個子構念、Cosgrave (2021) 對應平均心率這個子構念，
   兩篇文獻分工明確，不可互換引用（同 K 節 Troxel/MSLT 事件的教訓）。

2. 「活動量」修正值目前只用 steps_total（每日步數），未納入中強度活動分鐘數
   （需另外呼叫 get_intensity_minutes API，尚未實作，見 H 節）。
   【2026-08-10 補充】更根本的問題是資料有效性：本專案使用者起床後會取下手錶、
   傍晚才戴回，導致 steps_total 記錄到的是「傍晚在家的活動量」而非「一天的活動量」
   （步數中位數僅 185 步；心率讀數分布佐證：12:00 僅 45 筆、17:00 回到 734 筆）。
   已加入 ACTIVITY_MIN_BASELINE_STEPS 門檻自動偵測並停用此項，詳見該常數說明。
   對於整天配戴的使用者，此項仍正常運作。
   ⚠️【2026-08-24 修正】原本讀「同一列」的 steps_total，但那是**睡醒之後**才發生的
   活動量——summary 的每一列混了兩個時段：睡眠歸「起床日」（對齊 Garmin
   calendarDate），而步數的時間戳寫在該日 15:00、照自己的日曆日歸類。
   H 節文獻要的是相反方向（「日間活動對夜間睡眠的促進效果」，Kredlow 2015 的
   統合分析是前瞻設計），所以改讀「前一個日曆日」的步數（見 prev_day_steps()）。
   對現有 46 晚的**數值零影響**（此項已被上述門檻停用），僅 2026-06-11 那一晚的
   modifier_note 由「資料無效」改為「冷啟動」——序列位移一天，滿 14 筆的時間點
   也晚一晚，那是正確的結果而非副作用。此項若日後啟用才會有數值差異。

3. 【2026-07-30 修正】心率與壓力的偏離換算，原本用「相對 baseline 的百分比」，
   但實測發現壓力分數（avg_stress_score）在 baseline 很小（例如 3-7 分）的夜晚，
   稍微一點絕對變化就會被百分比公式放大到爆表（例：baseline=7、今晚=15，
   (7-15)/7=-114%，直接打滿上限；但 baseline=50、今晚=58，同樣差 8 分卻只有
   -16%）。這是「除以小分母」造成的統計不穩定，不是設計邏輯錯誤，但換算方式
   不合理。已改成「絕對差距」換算（心率：每差 1 bpm 給 X 分；壓力：每差 1 分
   Garmin 壓力分數給 X 分），不再受 baseline 大小影響。活動量（步數）因 baseline
   數值本身較大（幾百到幾千步），沒有這個小分母問題，維持用百分比換算。

4. 分數與 baseline 之間的換算比例（每 1 單位偏離對應幾分）是本專案的操作性設計，
   非文獻直接給出的公式——文獻只支持「該用個人化 baseline」與「訊號與睡眠品質有關聯」
   這兩個方向，具體換算比例是工程實作決策，正式報告中應如實區分兩者。

5. 【2026-08-10 擴充】新增 M（睡眠片段化）修正值，並新增 SRI（睡眠規律指數）作為
   「只呈現不計分」的指標。兩者原本在 Garmin手錶分數.md 被列為「Tier4，未來可能擴充」。
   M 併入 Tier3 修正值池（同一套「個人化 baseline」邏輯）而非另開一層，總上限由
   ±10 調整為 ±12。設計過程記錄如下：
   (a) 【SRI 最終不計分】規律性的文獻（Kalkanis 2025、Czeisler 2026、Windred 2024）
       談的是「連續數週的作息規律程度」與長期健康結果的關聯，並非逐夜關聯。設計過程
       依序排除了三種計分方式，記錄下來避免日後重蹈：
         · 排除「今晚 vs 個人 baseline」：會把測量的東西從「你有多不規律」偷換成
           「你最近有沒有比以前更不規律」。長年作息都亂的人會永遠拿 0 分（因為他沒有
           變得更亂），但文獻說的正是這種人屬於風險族群——構念不符。且實測發現此法
           會懲罰作息改善：2026-07-11 該使用者 22:42 上床（平常凌晨 1–3 點），對長期
           作息是明顯改善，卻因「偏離自身常態」而扣分，且會在整個調整期持續扣分。
           另有統計問題：SRI 本身已是 28 天滾動統計量，相鄰兩天的窗格有 27 天資料重疊
           （96% 相同），比較不具統計獨立性。
         · 排除「就寢時間標準差 + 自訂切點」：查證後沒有任何一篇文獻能乾淨支持此指標
           的門檻。Wong 2022 年齡吻合但論文自己沒標明數字是否為標準差且為日記自陳；
           Price 2023（Sci Rep 13:22114）年齡分層且為加速規實測，但報的是「睡眠中點」
           標準差而非就寢標準差（中點的兩端變異會互相抵消，數值天生較小），構念不符；
           UK Biobank 的就寢標準差構念正確但受試者平均 62 歲、且僅為研討會摘要。
           此法另有技術缺陷：用「距中午幾分鐘」換算時，橫跨中午前後的起床時間會被
           錨點切開，實測算出 507 分鐘的假變異度（實際僅約 1 小時）。
         · 排除「SRI 對照同齡常模計分」（一度已實作）：Czeisler 2026（n>73,000）證實
           同一批資料用兩個廣泛使用的開源套件計算，SRI 分數在絕對值與相對值上都有顯著
           差異，且「光是計算方法的不同就足以實質改變結果與詮釋」。佐證數字：NHANES
           （54.5 歲）SRI 平均 63.0 vs UK Biobank（62.8 歲）中位數 81.0，年齡僅差 8 歲
           卻差 18 分，顯非年齡效應而是方法學差異。本專案的近似實作與外部常模的落差
           極可能超過整個修正額度，該比較不具意義。
       最終決定：SRI 照常計算並輸出（供報告／App 呈現數值與趨勢），但不參與計分。
       Windred 2024 能支持的是「規律性是重要健康指標、值得呈現」（其預測全因死亡率
       的能力優於睡眠時長），它支持不了「今晚的 SRI 該換算成幾分」。
       未來若 RIRI 標準普及或本專案能自建同齡常模，可再啟用計分——計算邏輯已保留。
   (b) M 節文獻原文以 WASO、醒來次數、睡眠段數三者共同定義「片段化」概念，但 WASO
       已於 Tier1 核心分數（25 分）獨立評分。若 Tier3 修正值再次計入 WASO，會讓
       同一原始測量值在複合總分中被重複計權（同一行為事實影響分數兩次）。因此
       操作上窄化為僅用「醒來次數」與「睡眠段數」兩項訊號，WASO 角色保留在 Tier1；
       這是避免重複計分的操作性決定，不代表文獻本身主張 WASO 不重要。
       兩項高度相關（醒一次通常也會多一段），比照 RHR/avg_HR 的處理拆半：
       醒來次數 ±1、睡眠段數 ±1，合計仍是 M 的 ±2。

6. 【2026-08-10 已知限制】本專案的 SRI 是「近似值」，與文獻標準算法有三處差異。
   雖然 SRI 已不參與計分，但既然仍會呈現給使用者，正式報告中仍必須誠實標註，
   不可宣稱等同於文獻的 SRI：
   (a) 文獻的 SRI 用連續加速規資料（含小睡、含白天所有睡/醒狀態轉換）計算；本專案只用
       Garmin 判定的「主睡眠區間」建構睡/醒時間軸，白天小睡不會被計入，會讓 SRI 略微高估。
   (b) 文獻用 30 秒 epoch，本專案用 1 分鐘 epoch（對結果影響極小，但仍是差異）。
   (c) 最需要注意的偏誤：沒戴錶的夜晚會被整組排除（沿用 GGIR 慣例，該日配對有效比例
       低於 0.66 即排除）。若使用者剛好傾向在作息特別混亂的夜晚不戴錶，SRI 會被系統性
       高估（看起來比實際更規律）。這個偏誤方向是可預期的，實測資料 45 天中有 11 天缺失，
       有效日配對僅 24/43 組。
   → 因此本專案的 SRI 只適合用來看「同一個人自己的變化趨勢」（同一套實作前後一致），
     不適合跟其他研究或其他系統的 SRI 數值直接比大小。
"""

# argparse：讓這支腳本可以用命令列參數指定輸入/輸出檔名（例如測試用不同資料夾）
import argparse
# csv：讀寫 garmin_sleep_quality.csv / garmin_sleep_summary.csv 這種表格檔
import csv
# json：輸出 .json 版本，給前端或除錯時方便閱讀巢狀結構
import json
# datetime/timedelta：SRI 計算要把「入睡→起床」展開成逐分鐘的睡/醒時間軸，
# 需要對時間做加減與跨日推進（見 build_sleep_timeline）
from datetime import datetime, timedelta
# Path：用來定位 data/ 資料夾（相對於本檔案位置，不受工作目錄影響）
from pathlib import Path


# ═══════════════════════════════════════════════════════════════════
# 預設檔名（可被 --quality / --summary / --output / --output-json 覆寫）
# ═══════════════════════════════════════════════════════════════════
# 【2026-08-11】生成的資料檔集中放在 garmin/data/，用 Path(__file__).parent 定位，
# 不管從哪個工作目錄執行都能正確找到（見 garmin/README.md）。
DATA_DIR = Path(__file__).parent / "data"

DEFAULT_QUALITY_CSV = DATA_DIR / "garmin_sleep_quality.csv"   # Tier1/2 基礎分數（evaluate_sleep_quality.py 的輸出）
DEFAULT_SUMMARY_CSV = DATA_DIR / "garmin_sleep_summary.csv"   # 每晚原始心率/壓力/步數（analyze_garmin_sleep.py 的輸出）
DEFAULT_OUTPUT_CSV = DATA_DIR / "garmin_sleep_quality_final.csv"
DEFAULT_OUTPUT_JSON = DATA_DIR / "garmin_sleep_quality_final.json"

# 冷啟動保護：baseline 至少要有幾晚有效歷史資料，這項修正值才會啟動。
# 14 這個數字對應 Kerkering/Quer 等文獻常用的「至少兩週」個人化基準門檻。
MIN_BASELINE_NIGHTS = 14
# baseline 最多往回看幾晚——避免一個月前的資料還一直影響「現在」的比較基準，
# 讓 baseline 能跟著使用者近期的生活型態緩慢漂移，而不是永遠固定不變。
MAX_BASELINE_NIGHTS = 28

# ═══════════════════════════════════════════════════════════════════
# 各修正項的分數上限（見 Garmin手錶分數.md 權重設定原則，Tier3 = ±10）
# RHR ±2 + avg_HR ±2 + 壓力 ±4 + 活動量 0~+2 → 最大加總 +10、最小加總 -8，
# 天然落在 ±10 以內，但 compute_modifiers() 仍會再做一次 clamp 保底，
# 避免未來調參數時意外超界。
# ═══════════════════════════════════════════════════════════════════
# 【2026-07-31】心率原本是單一 HR_CAP=4，現拆成 RHR 與睡眠期間平均心率各半，
# 避免同一個生理面向（心血管自律神經狀態）被兩個高度相關的訊號重複計分，
# 詳見檔頭 2026-07-31 修正記錄。
RHR_CAP = 2.0
AVG_HR_CAP = 2.0
STRESS_CAP = 4.0
ACTIVITY_CAP = 2.0
# 【2026-08-10 新增】M（片段化）併入 Tier3 修正值池，上限由 ±10 調整為 ±12。
# 註：J（睡眠規律性 / SRI）原本也規劃納入計分（曾暫定 J_CAP = 2.0，總上限 ±14），
# 後因 Czeisler 2026 證實 SRI 跨計算方法不可比而撤除計分，改為只呈現數值不計分，
# 故無 J_CAP，總上限為 ±12（見 SRI 常數區塊與檔頭 2026-08-10 記錄第 5 點）。
M_AWAKE_CAP = 1.0
M_SEGMENT_CAP = 1.0
TOTAL_MODIFIER_CAP = 12.0

# 【2026-07-30 改版】心率／壓力改用「絕對差距」換算，不再用百分比：
# RHR_POINTS_PER_BPM：靜止心率每偏離 baseline 1 bpm，給/扣多少分。
#   0.4 分/bpm → 偏離 5 bpm 就打滿 ±2（RHR_CAP 從 4 降為 2 後同步調整比例，
#   維持「偏離 5 bpm 打滿」這個生理上合理的敏感度）。
RHR_POINTS_PER_BPM = 0.4
# AVG_HR_POINTS_PER_BPM：睡眠期間平均心率每偏離 baseline 1 bpm，給/扣多少分。
#   跟 RHR 用同一套比例邏輯（偏離 5 bpm 打滿 ±2），因為兩者同屬心率訊號、
#   沒有理由用不同敏感度。
AVG_HR_POINTS_PER_BPM = 0.4
# STRESS_POINTS_PER_UNIT：Garmin 壓力分數每偏離 baseline 1 分，給/扣多少分。
#   0.4 分/單位 → 偏離 10 分（Garmin 壓力分數尺度）打滿 ±4。
#   （原本用百分比會被小 baseline 放大，見檔頭修正記錄第 3 點）
STRESS_POINTS_PER_UNIT = 0.4
# ACTIVITY_SCALE：步數用「相對 baseline 的百分比」換算。
# 0.2 分/百分比 → 高於 baseline 10% 就打滿 +2。
# ⚠️ 這個換算只在「baseline 夠大」時才成立，見下方 ACTIVITY_MIN_BASELINE_STEPS。
ACTIVITY_SCALE = 0.2
# ═══════════════════════════════════════════════════════════════════
# 【2026-08-10 新增】活動量資料有效性門檻
# ═══════════════════════════════════════════════════════════════════
# 背景：本檔案原本註解寫著「步數 baseline 通常是幾百到幾千，數值夠大，不會有
# 小分母不穩定的問題」——這句話被實測資料證明是錯的，記錄下來避免重蹈覆轍。
#
# 實測發現：本專案使用者的步數中位數僅 185 步/日。追查後確認原因是配戴習慣——
# 使用者起床後會把手錶取下，傍晚才戴回（心率讀數分布佐證：12:00 僅 45 筆、
# 17:00 回到 734 筆、19:00 後回到 1100 筆/小時）。也就是說 steps_total 記錄到的
# 是「傍晚在家的活動量」而非「一天的活動量」，白天外出/通勤那段完全沒被計入。
#
# 這造成兩個問題：
#   (1) 統計上：baseline=185 時，+10% 只是 19 步，就足以打滿 +2 分——19 步是雜訊
#       不是訊號。這其實跟壓力分數當初的「小分母」問題是同一個毛病（見檔頭第 3 點），
#       只是當時誤以為步數不會遇到。
#   (2) 構念上：H 節文獻（Wang & Zhong 2026、Kredlow 2015）研究的都是每日數千步的
#       族群，「活動量高於個人常態有助睡眠」這個結論從未在 185 步的量級上被驗證過。
#
# 因此：baseline 低於此門檻時，直接判定「這筆資料無法反映真實活動量」，
# 該項修正值設為 0（不是給 0 分，是停用），並在 modifier_note 誠實說明。
# 1000 步是操作性門檻——即使極度靜態的成人只要整天配戴，通常仍有 1500-2500 步，
# 低於 1000 幾乎可以確定是配戴不完整而非真實活動量。此數字非文獻給出，
# 是依據「全日配戴下的合理下限」所做的工程判斷。
ACTIVITY_MIN_BASELINE_STEPS = 1000.0

# ═══════════════════════════════════════════════════════════════════
# 【2026-08-10 新增】J（睡眠規律性，SRI）計算與換算參數
# ═══════════════════════════════════════════════════════════════════
# J 跟其他修正項的計分邏輯本質不同，這裡要特別說明：
#   其他項目（心率/壓力/步數）是「今晚的值 vs 個人 baseline」——今晚偏離平常多少。
#   但「規律性」本身沒有「今晚的單一數值」可比：規律性 = 這段期間的作息有多一致，
#   它本身就已經是一個跨多晚的統計量。所以 J 不跟個人 baseline 比（那會把測量的東西
#   從「你有多不規律」偷換成「你最近有沒有比以前更不規律」，構念不符，
#   見檔頭 2026-08-10 記錄第 5(a) 點），而是直接把 SRI 對照「同齡人口常模」給分。
#
# SRI_EPOCH_MINUTES：把一天切成幾分鐘一格來比對睡/醒狀態。
#   文獻標準是 30 秒，這裡用 1 分鐘——Garmin 只給到分鐘級的入睡/起床時間，
#   用比資料本身更細的 epoch 沒有意義。
SRI_EPOCH_MINUTES = 1
# 一天有幾個 epoch（24 小時 × 60 分鐘 ÷ epoch 長度）
SRI_EPOCHS_PER_DAY = 24 * 60 // SRI_EPOCH_MINUTES
# SRI_WINDOW_DAYS：滾動窗格長度，用「日曆天」而非「有資料的晚數」。
#   因為 SRI 的計算單位是「相鄰兩天的配對」，中間缺一天就會斷掉一組配對，
#   用日曆天才能正確反映「這 28 天內的作息一致性」。
SRI_WINDOW_DAYS = 28
# SRI_MIN_PAIR_VALIDITY：單一組日配對至少要有多少比例的 epoch「兩天都有資料」，
#   才把這組配對納入計算。0.66 沿用 GGIR / sleepreg 套件的預設慣例。
SRI_MIN_PAIR_VALIDITY = 0.66
# SRI_MIN_VALID_PAIRS：整個窗格至少要湊到幾組有效配對，J 修正值才啟用。
#   這是 J 專用的冷啟動門檻——其他項目用 MIN_BASELINE_NIGHTS=14「晚」，
#   但 J 的計算單位不是「晚」而是「相鄰日配對」，所以要用不同的門檻。
SRI_MIN_VALID_PAIRS = 10
# ───────────────────────────────────────────────────────────────────
# ⚠️【2026-08-10 重要設計決定】SRI 只呈現數值與趨勢，不換算成分數
# ───────────────────────────────────────────────────────────────────
# 原本的設計是把 SRI 對照 Wong et al. (2022) 的大一新生常模（74.1 ± 8.7），
# 以 ±1 個標準差為滿分/滿扣門檻換算成 ±2 分。此設計已撤除，理由如下：
#
# Czeisler ME, Leota J, Le F, et al. Comparison of Sleep Regularity Index scores
# calculated by open-source packages and implications for outcomes research:
# rationale and design of the RIRI statement. Sleep. 2026;49(4):zsaf299.
# doi:10.1093/sleep/zsaf299
#   → 該研究以超過 73,000 名成人的資料證實：同一批資料用兩個廣泛使用的開源套件
#     （sleepreg 與 GGIR）計算，SRI 分數「在絕對值與相對值上都有顯著差異」，
#     且「光是計算方法的不同，就足以實質改變死亡率、第二型糖尿病、心房顫動
#     模型的結果與詮釋」。作者因此制定 RIRI 檢核表來規範 SRI 的報告方式。
#
# 佐證此問題的實際數字（不同世代研究之間的落差遠大於年齡效應）：
#   Wong 2022（大學生 18.7 歲，睡眠日記）      SRI = 74.1 ± 8.7
#   NHANES（n=5,589，54.5 歲，加速規）          SRI 平均 63.0
#   Windred 2024（UK Biobank n=60,997，62.8 歲）SRI 中位數 81.0
#   → NHANES 與 UK Biobank 年齡僅差 8 歲，SRI 卻差 18 分，顯非年齡效應而是方法學差異。
#
# 推論到本專案：連兩個成熟標準套件都對不起來，本專案這個「只用主睡眠區間、
# 1 分鐘 epoch、自製實作」的近似版本去跟外部常模比較，誤差極可能超過整個 ±2 的
# 額度——這不是「不完全可比」的程度，而是「該比較本身不具意義」。
#
# 因此改為：SRI 照常計算並輸出（數值 + 有效配對數），供報告／App 呈現數值與趨勢，
# 但不參與 total_modifier 的加總。Windred 2024 能支持的是「規律性是重要的健康指標、
# 值得呈現給使用者」（其預測全因死亡率的能力優於睡眠時長），它支持不了
# 「今晚的 SRI 該換算成幾分」。
#
# 為何不改採「跟使用者自己的歷史 SRI 比」：(1) SRI 本身已是 28 天滾動統計量，
# 相鄰兩天的窗格有 27 天資料重疊（96% 相同），比較不具統計獨立性；(2) 更關鍵的是
# 會懲罰作息改善——實測 2026-07-11 該使用者 22:42 上床（平常凌晨 1–3 點），
# 對長期作息而言是明顯改善，但「偏離自身常態」的算法反而會扣分，且在整個
# 作息調整期間持續扣分，直到新作息成為新常態為止。
#
# 未來若 RIRI 標準普及、或本專案累積足夠的同齡使用者資料可自建常模，
# 可再啟用計分——SRI 的計算、跨午夜處理、冷啟動判定皆已保留，屆時只需恢復換算即可。

# M（片段化）兩個子項的換算比例。用「絕對差距」而非百分比，理由同心率/壓力：
# 醒來次數的 baseline 常常只有 2-3 次，用百分比會被小分母放大（醒 3 次變醒 6 次
# 是 +100%，但實際只多醒 3 次）。
# M_AWAKE_POINTS_PER_COUNT：每比 baseline 多醒 1 次，扣多少分。
#   0.34 分/次 → 多醒約 3 次就打滿 -1。實測 awake_count 中位數 3、範圍 1-9，
#   多醒 3 次（= 中位數的兩倍）已是明顯偏離常態。
M_AWAKE_POINTS_PER_COUNT = 0.34
# M_SEGMENT_POINTS_PER_COUNT：每比 baseline 多 1 個睡眠段，扣多少分。
#   0.1 分/段 → 多 10 段打滿 -1。實測 sleep_segment_count 中位數 21、範圍 9-36，
#   多 10 段約等於比平常多切了一半，是合理的滿分門檻。
M_SEGMENT_POINTS_PER_COUNT = 0.1

# 沿用 evaluate_sleep_quality.py 的分級門檻，確保 base/final 分級判定邏輯一致，
# 不會出現「基礎分數用一套標準分級、最終分數用另一套」這種不一致。
GRADE_THRESHOLDS = [
    (80, "Good"),
    (65, "Normal"),
    (50, "Poor"),
    (0, "Bad"),
]


def parse_args():
    """定義命令列參數；全部有預設值，直接 `python apply_recovery_modifier.py` 就能跑。"""
    parser = argparse.ArgumentParser(
        description="Apply Tier 3 physiological modifiers (heart rate / stress / activity) and emit final scores."
    )
    parser.add_argument("--quality", default=DEFAULT_QUALITY_CSV, help="Tier1/2 base score CSV.")
    parser.add_argument("--summary", default=DEFAULT_SUMMARY_CSV, help="Per-night heart rate / stress / steps CSV.")
    parser.add_argument("--output", default=DEFAULT_OUTPUT_CSV, help="Output final score CSV.")
    parser.add_argument("--output-json", default=DEFAULT_OUTPUT_JSON, help="Output final score JSON.")
    return parser.parse_args()


def to_float(value):
    """
    安全轉浮點數。CSV 讀進來的欄位一律是字串，且可能是空字串（代表那晚沒量到），
    這裡統一處理成「轉得動就轉，轉不動或是空的就回傳 None」，讓後面的邏輯
    可以直接用 `if x is None` 判斷「這筆資料有沒有」，不用到處寫 try/except。
    """
    try:
        if value is None or str(value).strip() == "":
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def grade_for(score):
    """
    依總分對照 GRADE_THRESHOLDS 給出 Good/Normal/Poor/Bad 標籤。
    由上而下比對，第一個「分數 >= 門檻」的級距就是答案（門檻由高到低排列）。
    """
    for threshold, label in GRADE_THRESHOLDS:
        if score >= threshold:
            return label
    return "Bad"


def load_summary(path):
    """
    讀 garmin_sleep_summary.csv，回傳依日期由舊到新排序的 list[dict]。
    一定要排序，因為 compute_modifiers() 是「逐晚往前滾動」計算 baseline，
    如果順序是亂的，baseline 會混進未來的資料，變成用「還沒發生的晚上」
    去影響「現在」的分數，這是時間序列分析最忌諱的資料洩漏（data leakage）。
    """
    with open(path, "r", encoding="utf-8-sig", newline="") as f:
        rows = list(csv.DictReader(f))
    rows.sort(key=lambda r: r.get("date", ""))
    return rows


def rolling_baseline(history_values):
    """
    以「當晚之前」最多 MAX_BASELINE_NIGHTS 筆有效數值算中位數，當作個人化 baseline。

    為什麼用中位數不用平均數：平均數容易被單一天的極端值拉走
    （例如某晚壓力飆到 46 分，用平均會把整個 baseline 往上拖），
    中位數對這種偶發極端值比較不敏感，更能代表「平常大概是這樣」。

    有效歷史筆數不足 MIN_BASELINE_NIGHTS 時回傳 None，
    呼叫端看到 None 就知道「這項還不能修正，資料還不夠」。
    """
    # 只保留有量到的值（None 是那晚沒資料，不該算進 baseline），
    # 再取最後 MAX_BASELINE_NIGHTS 筆，捨棄太久以前的資料
    valid = [v for v in history_values if v is not None][-MAX_BASELINE_NIGHTS:]
    if len(valid) < MIN_BASELINE_NIGHTS:
        return None

    valid_sorted = sorted(valid)
    mid = len(valid_sorted) // 2
    # 奇數筆：正中間那個就是中位數
    if len(valid_sorted) % 2 == 1:
        return valid_sorted[mid]
    # 偶數筆：取中間兩個的平均
    return (valid_sorted[mid - 1] + valid_sorted[mid]) / 2.0


def score_lower_is_better(current, baseline, cap, points_per_unit):
    """
    數值越低越好（心率、壓力）時的修正分數計算。

    今晚比 baseline 低 → 正分（恢復比平常好）；今晚比 baseline 高 → 負分（比平常差）。
    用「絕對差距 × 每單位分數」而不是百分比，理由見檔頭第 3 點修正記錄：
    百分比在 baseline 很小時會被異常放大，絕對差距不會有這個問題。

    cap：這一項的正負分上限（HR_CAP 或 STRESS_CAP）。
    points_per_unit：每差 1 個單位（1 bpm 或 1 分壓力分數）給幾分。
    """
    if current is None or baseline is None:
        return None
    # (baseline - current)：今晚比 baseline 低就是正值，直覺對應「表現比平常好」
    diff = baseline - current
    raw_score = diff * points_per_unit
    # 用 max/min 夾住範圍，確保不管差距多大，這一項最多只會影響 ±cap 分
    return max(-cap, min(cap, raw_score))


def score_higher_is_better_bonus_only(current, baseline, cap, scale):
    """
    數值越高越好、但只加分不扣分（活動量）。

    設計理由（見 Garmin手錶分數.md H 節）：文獻認為活動量與睡眠品質的關係
    是「規律活動有正向幫助」，而不是「活動不足就該扣分」——今天活動量低
    可能只是休息日、生病、天氣不好，不該被當成睡眠風險扣分，
    所以低於 baseline 一律回傳 0（沒有負分），只有高於 baseline 才給獎勵分。

    這裡用百分比（而非絕對差距）換算，前提是 baseline 夠大；若 baseline 過小，
    百分比會像壓力分數那樣被小分母放大到不合理，因此呼叫端必須先用
    ACTIVITY_MIN_BASELINE_STEPS 擋掉那種情況（見該常數上方的完整說明）。
    """
    if current is None or baseline is None or baseline == 0:
        return None
    # 資料有效性把關：baseline 過低代表手錶沒有整天配戴，記錄到的步數
    # 無法反映真實活動量，此時回傳 None（= 該項停用），而不是硬算出一個分數。
    if baseline < ACTIVITY_MIN_BASELINE_STEPS:
        return None
    dev_pct = (current - baseline) / baseline * 100.0
    if dev_pct <= 0:
        # 低於或等於 baseline：不扣分，直接回傳 0（這是刻意的設計，不是漏寫上限）
        return 0.0
    return min(cap, dev_pct * scale)


def build_sleep_timeline(summary_rows):
    """
    把每晚的「入睡時間 → 起床時間」轉換成逐分鐘的睡/醒狀態時間軸，供 SRI 計算使用。

    回傳 (asleep_epochs, recorded_days)：
      asleep_epochs：set of (date, epoch_index)，代表「這一天的這一分鐘是睡著的」。
        用 set 而非二維陣列，是因為睡著的分鐘只佔一天的三分之一左右，
        用 set 記錄「哪些格子是 1」比開一個全是 0 的大陣列更省記憶體也更好讀。
      recorded_days：set of date，代表「這一天有量到資料」。
        這個很重要：沒被記錄到的日子要視為「缺資料」而不是「整天都醒著」，
        否則沒戴錶的日子會被當成「一整天沒睡」，把 SRI 嚴重低估。

    ⚠️ 一晚的睡眠常常跨午夜（例如 23:41 睡、08:57 起），所以同一段睡眠會同時
    在「入睡那天」與「起床那天」留下睡著的分鐘。這裡逐分鐘往前推進、
    用每個時間點自己的日期去標記，跨午夜自然被拆到正確的兩天，
    不需要額外處理跨日邏輯。
    """
    asleep_epochs = set()
    recorded_days = set()

    for row in summary_rows:
        start_raw = row.get("sleep_start_time", "")
        wake_raw = row.get("wake_time", "")
        # 三種要排除的情況：沒入睡時間、沒起床時間、兩者相同
        # （相同代表那天 Garmin 沒抓到睡眠、程式 fallback 成同一個時間點，
        #   例如 2026-06-02 的 00:00:00 → 00:00:00，是已知的異常資料）
        if not start_raw or not wake_raw or start_raw == wake_raw:
            continue
        try:
            start_dt = datetime.fromisoformat(start_raw)
            wake_dt = datetime.fromisoformat(wake_raw)
        except (TypeError, ValueError):
            continue
        # 防禦性檢查：起床時間必須晚於入睡時間，否則資料有問題，跳過
        if wake_dt <= start_dt:
            continue

        # 這一晚「有資料」的日子：從入睡日到起床日都算（跨午夜就是兩天）
        day = start_dt.date()
        while day <= wake_dt.date():
            recorded_days.add(day)
            day += timedelta(days=1)

        # 逐分鐘標記睡著的格子。用 while 而非 range，因為要跨日期推進，
        # 直接對 datetime 加 timedelta 最不容易寫錯。
        cursor = start_dt
        while cursor < wake_dt:
            epoch_index = (cursor.hour * 60 + cursor.minute) // SRI_EPOCH_MINUTES
            asleep_epochs.add((cursor.date(), epoch_index))
            cursor += timedelta(minutes=SRI_EPOCH_MINUTES)

    return asleep_epochs, recorded_days


def compute_sri(window_days, asleep_epochs, recorded_days):
    """
    計算一段期間的 Sleep Regularity Index（SRI）。

    SRI 的定義（Phillips et al. 2017）：相隔 24 小時的兩個時間點，睡/醒狀態相同的機率，
    換算成 -100 ～ +100 的分數：
        SRI = -100 + 200 × (狀態相同的配對數 ÷ 總配對數)
    直覺理解：
      - 每一天的作息都跟前一天一模一樣 → 全部配對都相同 → SRI = +100
      - 睡覺時間完全隨機 → 大約一半配對相同 → SRI = 0
      - 每天都跟前一天完全顛倒（日夜反轉）→ 沒有配對相同 → SRI = -100

    為什麼 SRI 不需要處理跨午夜問題：它比較的是「同一個時鐘時間，今天與昨天」，
    根本沒有「一天從幾點開始算」這個問題，不像「就寢時間標準差」那樣需要挑一個
    時間錨點（挑錯就會像先前那樣算出 507 分鐘的假變異度，見檔頭 2026-08-10 記錄）。

    window_days：要計算的日期清單（連續的日曆日，含缺資料的日子）。
    回傳 (sri, valid_pair_count)；有效配對數不足時 sri 為 None。
    """
    matched_epochs = 0   # 兩天狀態相同的 epoch 總數
    compared_epochs = 0  # 兩天都有資料、實際比較過的 epoch 總數
    valid_pairs = 0      # 通過有效性檢查的「相鄰日配對」組數

    for i in range(len(window_days) - 1):
        day1 = window_days[i]
        day2 = window_days[i + 1]
        # 只比較「真正相鄰」的兩天。window_days 理論上是連續的，
        # 但加這個檢查可以避免呼叫端傳進不連續清單時算出錯誤結果。
        if (day2 - day1).days != 1:
            continue
        # 缺資料的日子直接跳過整組配對——這是關鍵：
        # 若把沒戴錶的日子當成「整天醒著」，會跟有睡眠的日子大量不匹配，
        # 讓 SRI 被嚴重低估（看起來像作息很亂，其實只是沒戴錶）。
        if day1 not in recorded_days or day2 not in recorded_days:
            continue

        pair_matched = 0
        for epoch in range(SRI_EPOCHS_PER_DAY):
            state1 = (day1, epoch) in asleep_epochs
            state2 = (day2, epoch) in asleep_epochs
            if state1 == state2:
                pair_matched += 1

        # 這組配對兩天都有資料，所以整天的 epoch 都算有效。
        # 保留這個比例檢查是為了對齊 GGIR/sleepreg 的慣例，
        # 未來若改成「部分時段才有資料」的資料來源，這裡就會發揮作用。
        pair_validity = 1.0
        if pair_validity < SRI_MIN_PAIR_VALIDITY:
            continue

        valid_pairs += 1
        matched_epochs += pair_matched
        compared_epochs += SRI_EPOCHS_PER_DAY

    # 有效配對太少時不給分：資料量不足算出來的 SRI 沒有統計意義，
    # 這是 J 的冷啟動保護（對應其他項目的「未滿 14 晚不修正」）
    if valid_pairs < SRI_MIN_VALID_PAIRS or compared_epochs == 0:
        return None, valid_pairs

    return -100.0 + 200.0 * (matched_epochs / compared_epochs), valid_pairs


def build_modifier_note(rhr_available, avg_hr_available, stress_available,
                        activity_available, sri_available,
                        awake_available, segment_available,
                        activity_data_invalid=False, stress_window_missing=False):
    """
    組出一句人看得懂的提示文字，說明「這一晚哪些修正項沒有生效、以及為什麼」。
    目的是讓 App／報告端可以誠實顯示「這個分數還沒有加上哪些修正」，
    而不是讓使用者以為系統忽略了他們的心率/壓力資料。

    三種「沒生效」的原因要分開講，因為使用者該採取的行動完全不同：
      1. 冷啟動（資料還不夠多）→ 繼續戴就會好，看 MIN_BASELINE_NIGHTS。
      2. SRI 資料不足（相鄰夜配對不夠）→ 需要「連續」幾晚都有資料，
         跟第 1 種的「累積幾晚」不是同一回事，所以分開寫。
         注意：SRI 不參與計分（見 SRI 常數區塊的設計決定），所以這裡的措辭是
         「無法計算」而非「暫不修正」——它本來就不會修正分數。
      3. 活動量資料無效（手錶沒整天戴）→ 再戴幾晚也不會改善，
         必須改變配戴習慣才行，講成「累積中」會誤導使用者。
      4.【2026-08-25 新增】壓力缺「入睡前清醒時段」→ 前一晚沒戴錶，
         所以量不到那一段。這跟第 1 種同樣不是使用者做錯什麼，但原因不同：
         冷啟動是「總量還不夠」，這個是「這一晚剛好缺前一晚」，
         下一晚只要前後都有戴就會恢復。
    """
    missing = []
    if not rhr_available:
        missing.append("resting heart rate")
    if not avg_hr_available:
        missing.append("sleep-period average heart rate")
    # 壓力跟活動量同理：只有在「不是因為缺窗格」時，才歸類為冷啟動
    if not stress_available and not stress_window_missing:
        missing.append("stress")
    # 活動量只有在「不是因為資料無效」時，才歸類為冷啟動
    if not activity_available and not activity_data_invalid:
        missing.append("activity")
    if not awake_available:
        missing.append("night-time awakenings")
    if not segment_available:
        missing.append("sleep segments")

    notes = []
    if missing:
        notes.append(
            f"Building personal baseline ({'/'.join(missing)} below {MIN_BASELINE_NIGHTS} nights of history); this modifier is paused."
        )
    if not sri_available:
        notes.append(
            f"Sleep Regularity Index (SRI) not computable: needs at least "
            f"{SRI_MIN_VALID_PAIRS} adjacent-night pairs within {SRI_WINDOW_DAYS} days."
        )
    if activity_data_invalid:
        notes.append(
            f"Activity modifier disabled: daily step baseline is below {ACTIVITY_MIN_BASELINE_STEPS:.0f} steps, "
            "indicating the watch was not worn consistently during the day, so this figure cannot reflect real activity."
        )
    if stress_window_missing:
        notes.append(
            "Stress modifier not applied: this night has no pre-sleep wake-window data "
            "(the previous night was not recorded, so the start of that window cannot be determined)."
        )
    return " ".join(notes)


def prev_day_steps(row_date, steps_by_date):
    """
    取「上床前那個白天」的步數——也就是 row_date 的前一個日曆日。

    見 compute_modifiers() 迴圈內的完整說明。回傳 None 的情況有兩種，
    兩種都代表「這一晚沒有可用的睡前活動量」，交給下游的 None 處理邏輯：
      1. 前一天沒戴錶（那一列根本不存在）
      2. 前一天有列但 steps_total 是空的

    ⚠️ 不要「往前找到最近一個有資料的日子」來補洞。那會把三天前的活動量
       當成昨天的用，而 H 節文獻講的是「當日活動 → 當晚睡眠」的鄰接關係，
       隔了幾天就不是同一回事了。寧可誠實地回 None。
    """
    try:
        prev = datetime.fromisoformat(row_date).date() - timedelta(days=1)
    except (TypeError, ValueError):
        return None
    return steps_by_date.get(prev.isoformat())


def compute_modifiers(summary_rows):
    """
    對每一晚計算 Tier 3 修正值，回傳 {date: {...}} 的字典。

    核心邏輯是「逐晚往前滾動」：處理第 N 晚時，只用第 1 到第 N-1 晚的歷史資料
    算 baseline，算完第 N 晚的修正值之後，才把第 N 晚的原始數值加進歷史清單，
    留給第 N+1 晚使用。這樣可以保證 baseline 永遠只包含「過去」，不會用到
    「未來」的資料去評價「現在」這一晚——這在真實系統裡也是對的，因為使用者
    在第 N 晚睡覺當下，系統本來就不可能知道第 N+1 晚會發生什麼事。
    """
    # 六條獨立的歷史清單，逐晚累積；用 list 而非 dict 是因為只需要「依時間順序的數值」
    rhr_history = []
    avg_hr_history = []
    stress_history = []
    steps_history = []
    awake_count_history = []
    segment_count_history = []

    # SRI 需要「整段期間的睡/醒時間軸」，不像其他項目只需要單一數值，
    # 所以在進迴圈前先把時間軸建好一次，迴圈裡只取用不同的日期窗格。
    asleep_epochs, recorded_days = build_sleep_timeline(summary_rows)

    # ═══════════════════════════════════════════════════════════════
    # 【2026-08-24 修正】活動量要用「上床前那個白天」的步數
    # ═══════════════════════════════════════════════════════════════
    # 這張查表是為了讓迴圈能取到「前一個日曆日」那一列的步數。詳細理由見
    # 迴圈內 steps 那一行的說明，這裡只講為什麼需要一張額外的表：
    # summary_rows 是逐列處理的，而我們要的值在「上一列」——但不能直接用
    # 上一列，因為中間可能有沒戴錶的日子而使日期不連續。必須用日期查。
    steps_by_date = {
        r.get("date", ""): to_float(r.get("steps_total"))
        for r in summary_rows
    }

    modifiers_by_date = {}

    for row in summary_rows:
        row_date = row.get("date", "")
        # 讀出「今晚」的原始數值（可能是 None，代表那晚沒量到）
        rhr = to_float(row.get("resting_heart_rate"))
        avg_hr = to_float(row.get("avg_heart_rate"))
        # ⚠️【2026-08-25 修正】壓力改讀 presleep_stress_score（上一次起床 → 這次入睡
        #    的整個清醒時段），不再用 avg_stress_score。
        #
        #    原因：avg_stress_score 的 11,439 筆讀數裡只有 8.6% 落在睡眠期間，
        #    91.4% 是白天——而那個「白天」主體是**起床之後**那一天。
        #    G 節引的 Yap (2020) 講的是「當日壓力 → 當夜睡眠」，方向相反。
        #
        #    實例（2026-07-12，入睡 02:39、起床 15:29）：
        #      舊值 25.8（基準 5.5）→ 扣滿 −4.0，但那 25.8 整段發生在起床之後
        #      新值  3.3（基準 5.4）→ 入睡前那個清醒時段其實低於個人常態
        #    同一批原始讀數，只因時窗不同而差了將近 8 倍。
        #
        #    ⚠️ avg_stress_score 欄位仍然保留在 summary 裡（未刪除），
        #       但**不再參與任何計分**。要看歷史對照時才用它。
        stress = to_float(row.get("presleep_stress_score"))
        # ⚠️【2026-08-24 修正】活動量讀「前一個日曆日」的步數，不是這一列自己的。
        #
        # 原因是 summary 的每一列混了兩個不同時段的資料：
        #   列 D 的「睡眠」＝ D-1 晚上上床、D 早上起床（歸起床日，對齊 Garmin calendarDate）
        #   列 D 的「步數」＝ D 白天（garmin_connect_fetch.py 把時間戳寫在 D 的 15:00，
        #                            不落在睡眠區間內，所以照自己的日曆日歸類）
        # → 也就是說，列 D 的步數發生在列 D 那一覺**睡完之後**。
        #
        # 但 H 節文獻要的是相反的方向。Garmin手錶分數.md 第 122 行寫的是
        # 「白天身體活動量……用以反映**日間活動對夜間睡眠**的潛在促進效果」，
        # 第 126 行「將白天活動量視為對**夜間**睡眠的漸進式加分來源」，
        # 引用的 Kredlow (2015) 統合分析也是「運動 → 之後的睡眠」這個前瞻方向。
        # 用睡醒之後才發生的步數去加分給睡前那一覺，因果方向是反的。
        #
        # 所以列 D 這一覺（上床於 D-1 晚上）該配的是 **D-1 白天**的步數。
        #
        # ⚠️ 為什麼要用日期查而不是直接取前一列：46 晚裡有 28 個日曆日沒戴錶，
        #    列與列之間的日期不連續，「上一列」很可能是好幾天前。
        #
        # ⚠️ 本次修改對現有 46 晚的分數**沒有任何影響**，因為
        #    ACTIVITY_MIN_BASELINE_STEPS 已把整項停用（步數中位數僅 185）。
        #    這正好是這次修改的回歸測試：分數若有變動，就代表理解有誤。
        steps = prev_day_steps(row_date, steps_by_date)
        awake_count = to_float(row.get("awake_count"))
        segment_count = to_float(row.get("sleep_segment_count"))

        # 用「今晚之前」累積的歷史（此時還沒把今晚加進去）算各項 baseline
        rhr_baseline = rolling_baseline(rhr_history)
        avg_hr_baseline = rolling_baseline(avg_hr_history)
        stress_baseline = rolling_baseline(stress_history)
        steps_baseline = rolling_baseline(steps_history)
        awake_baseline = rolling_baseline(awake_count_history)
        segment_baseline = rolling_baseline(segment_count_history)

        # 靜止心率、睡眠期間平均心率、壓力：數值越低越好，用絕對差距換算
        # （見檔頭修正記錄第 3 點）；心率拆成 RHR 與 avg_HR 兩個子項各佔一半額度
        # （見檔頭 2026-07-31 修正記錄，避免同一生理面向重複計分）
        rhr_score = score_lower_is_better(rhr, rhr_baseline, RHR_CAP, RHR_POINTS_PER_BPM)
        avg_hr_score = score_lower_is_better(avg_hr, avg_hr_baseline, AVG_HR_CAP, AVG_HR_POINTS_PER_BPM)
        stress_score = score_lower_is_better(stress, stress_baseline, STRESS_CAP, STRESS_POINTS_PER_UNIT)
        # 活動量：數值越高越好、只加分不扣分，用百分比換算。
        # 若 baseline 低於 ACTIVITY_MIN_BASELINE_STEPS，score_higher_is_better_bonus_only()
        # 會回傳 None（判定為「手錶沒整天戴，資料無法反映活動量」而停用該項）。
        activity_score = score_higher_is_better_bonus_only(steps, steps_baseline, ACTIVITY_CAP, ACTIVITY_SCALE)
        # 分辨「活動量沒生效」的兩種原因：baseline 還沒累積夠（冷啟動，繼續戴就會好）
        # vs baseline 夠了但數值太低（配戴習慣問題，再戴幾晚也不會改善）。
        # 兩者給使用者的提示訊息完全不同，不能混為一談。
        activity_data_invalid = (
            steps_baseline is not None and steps_baseline < ACTIVITY_MIN_BASELINE_STEPS
        )

        # ── M（睡眠片段化）：醒來次數與睡眠段數，都是越少越好 ──
        # 兩者高度相關（醒一次通常也會多切一段），所以各佔 M 額度的一半（±1），
        # 而不是各給 ±2 讓同一件事被計分兩次（見檔頭 2026-08-10 記錄第 5(b) 點）。
        # ⚠️ 刻意「不」把 WASO（清醒總分鐘數）納入這裡：WASO 已在 Tier1 佔 25 分，
        # 再算一次會讓同一個原始測量值在總分裡影響兩次。這兩個新訊號補的是
        # WASO 看不出來的資訊——同樣清醒 40 分鐘，是「醒一次躺很久」還是
        # 「醒八次每次五分鐘」，只有次數/段數分得出來。
        awake_score = score_lower_is_better(
            awake_count, awake_baseline, M_AWAKE_CAP, M_AWAKE_POINTS_PER_COUNT
        )
        segment_score = score_lower_is_better(
            segment_count, segment_baseline, M_SEGMENT_CAP, M_SEGMENT_POINTS_PER_COUNT
        )

        # ── J（睡眠規律性）：SRI，只計算不計分 ──
        # ⚠️ SRI 刻意「不」參與 total_modifier 的加總，理由見 SRI 常數區塊的
        #    完整說明（Czeisler 2026 證實 SRI 跨計算方法不可比，本專案的近似
        #    實作無法對照外部常模）。這裡照常算出數值，供報告／App 呈現趨勢。
        #
        # 窗格是「以今晚為結尾、往回推 SRI_WINDOW_DAYS 個日曆天」。
        # 為什麼可以包含今晚（跟其他項目「只用過去」的規則不同）：
        #   其他項目是拿「今晚的值」去跟「過去的基準」比，若基準含今晚就是自己比自己。
        #   但 SRI 沒有「今晚的單一值」——它本身就是整個窗格的統計量，今晚只是窗格裡的
        #   一天。而且使用者早上看到結果時，系統本來就已經知道昨晚幾點睡、幾點起，
        #   用這筆資料不算偷看未來。真正的資料洩漏是用「明晚」的資料，這裡沒有。
        #   實務上這也讓 SRI 能反映「今晚作息突然偏移」（實測 07-11 提早上床，
        #   SRI 由 79.2 降到 69.5，正確捕捉到偏移）。
        sri_value = None
        valid_pairs = 0
        try:
            current_day = datetime.fromisoformat(row_date).date()
        except (TypeError, ValueError):
            current_day = None
        if current_day is not None:
            # 產生連續的日曆天清單（含中間沒資料的日子，compute_sri 會自行跳過）
            window_days = [
                current_day - timedelta(days=offset)
                for offset in range(SRI_WINDOW_DAYS - 1, -1, -1)
            ]
            sri_value, valid_pairs = compute_sri(window_days, asleep_epochs, recorded_days)

        # 加總各修正項，None（該項未生效）不計入。
        # ⚠️ 注意 sri_value 不在這個清單裡——SRI 只呈現不計分。
        total = sum(
            v for v in (
                rhr_score, avg_hr_score, stress_score, activity_score,
                awake_score, segment_score,
            )
            if v is not None
        )
        # 保底再夾一次總範圍，防止未來調整個別上限時，總和意外超出 ±12
        total = max(-TOTAL_MODIFIER_CAP, min(TOTAL_MODIFIER_CAP, total))

        modifiers_by_date[row_date] = {
            # None 代表這項因冷啟動未生效；有值的話四捨五入到小數點後兩位方便閱讀
            "rhr_modifier": None if rhr_score is None else round(rhr_score, 2),
            "avg_hr_modifier": None if avg_hr_score is None else round(avg_hr_score, 2),
            "stress_modifier": None if stress_score is None else round(stress_score, 2),
            "activity_modifier": None if activity_score is None else round(activity_score, 2),
            "awake_modifier": None if awake_score is None else round(awake_score, 2),
            "segment_modifier": None if segment_score is None else round(segment_score, 2),
            # SRI 是「呈現用」欄位，不影響 total_modifier；一併輸出有效配對數，
            # 讓報告端能判斷這個數值是用多少資料算出來的（配對數越少越不穩定）
            "sri": None if sri_value is None else round(sri_value, 1),
            "sri_valid_pairs": valid_pairs,
            "total_modifier": round(total, 2),
            "modifier_note": build_modifier_note(
                rhr_baseline is not None, avg_hr_baseline is not None,
                stress_baseline is not None, activity_score is not None,
                sri_value is not None,
                awake_baseline is not None, segment_baseline is not None,
                activity_data_invalid,
                # 這一晚有沒有「入睡前清醒時段」可用（前一晚有戴錶才有）。
                # 與冷啟動分開，兩者要採取的行動不同——見 build_modifier_note。
                stress is None,
            ),
        }

        # 算完「今晚」的修正值之後，才把今晚的原始值併入歷史清單，
        # 這一行的順序很重要：一定要放在算完 baseline/modifier 之後，
        # 否則今晚就會把自己算進自己的 baseline 裡，變成用自己評價自己。
        # （J 不在這裡累積，因為它用的是 build_sleep_timeline 建好的完整時間軸，
        #   由窗格範圍控制「看到哪些天」，不需要逐晚 append。）
        rhr_history.append(rhr)
        avg_hr_history.append(avg_hr)
        stress_history.append(stress)
        # ⚠️ 這裡 append 的是「已經位移過」的 steps（前一天的值）。這是對的，
        #    不是漏改：baseline 必須跟被比較的值取自同一個序列，否則就變成
        #    拿「睡前活動量」去比「全部白天活動量」的基準，兩者定義不同。
        steps_history.append(steps)
        awake_count_history.append(awake_count)
        segment_count_history.append(segment_count)

    return modifiers_by_date


def main():
    args = parse_args()

    # 讀 Tier1/2 基礎分數（一定要先跑過 evaluate_sleep_quality.py 才會有這個檔）
    with open(args.quality, "r", encoding="utf-8-sig", newline="") as f:
        quality_rows = list(csv.DictReader(f))
    if not quality_rows:
        raise SystemExit(f"{args.quality} has no rows. Run evaluate_sleep_quality.py first.")

    # 讀原始心率/壓力/步數資料，並依日期算出每晚的 Tier3 修正值
    summary_rows = load_summary(args.summary)
    modifiers_by_date = compute_modifiers(summary_rows)

    results = []
    for row in quality_rows:
        date = row.get("date", "")
        # 基礎分數若讀不到（理論上不會發生，防禦性寫法）就當 0 分處理
        base_score = to_float(row.get("score")) or 0.0
        # 用 .get(date, {...}) 給一組全 None/0 的預設值，
        # 避免 quality.csv 裡有某天但 summary.csv 剛好沒有對應資料時程式直接掛掉
        mod = modifiers_by_date.get(date, {
            "rhr_modifier": None, "avg_hr_modifier": None, "stress_modifier": None,
            "activity_modifier": None,
            "awake_modifier": None, "segment_modifier": None,
            "sri": None, "sri_valid_pairs": 0,
            "total_modifier": 0.0, "modifier_note": "",
        })

        # 最終分數 = 基礎分數 + 修正值，再夾在 [0, 100] 之間防止超界
        final_score = max(0.0, min(100.0, base_score + mod["total_modifier"]))
        final_score = round(final_score, 1)

        results.append({
            "date": date,
            "base_score": base_score,
            "base_quality": row.get("quality", ""),
            "rhr_modifier": mod["rhr_modifier"],
            "avg_hr_modifier": mod["avg_hr_modifier"],
            "stress_modifier": mod["stress_modifier"],
            "activity_modifier": mod["activity_modifier"],
            "awake_modifier": mod["awake_modifier"],
            "segment_modifier": mod["segment_modifier"],
            # ⚠️ sri 是「呈現用」欄位，不影響 final_score（見檔頭 2026-08-10 記錄第 5(a) 點）。
            # 一併輸出有效配對數，讓報告端能判斷該數值是用多少資料算出來的。
            "sri": mod["sri"],
            "sri_valid_pairs": mod["sri_valid_pairs"],
            "total_modifier": mod["total_modifier"],
            "modifier_note": mod["modifier_note"],
            "final_score": final_score,
            "final_quality": grade_for(final_score),
            # 建議文字沿用 Tier1/2 算出來的版本，Tier3 目前不額外產生建議文字
            "recommendation": row.get("recommendation", ""),
        })

    # 輸出 JSON（給前端/除錯用，巢狀結構好讀）
    with open(args.output_json, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)

    # 輸出 CSV（給 Excel/報告用）；用第一筆的 keys 當欄位順序，所有列結構一致所以安全
    with open(args.output, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=results[0].keys())
        writer.writeheader()
        writer.writerows(results)

    # 執行完印出摘要統計，方便一眼看出這次跑出來的結果合不合理
    nights_with_modifier = sum(1 for r in results if r["total_modifier"] != 0.0)
    changed_grade = sum(1 for r in results if r["base_quality"] != r["final_quality"])
    avg_modifier = round(sum(r["total_modifier"] for r in results) / len(results), 2)

    # SRI 另外印一組統計。它不參與計分，所以不能混在「修正值」的統計裡看，
    # 分開顯示才能一眼確認它有沒有正常算出來、以及變化範圍是否合理。
    sri_values = [r["sri"] for r in results if r["sri"] is not None]

    print("Recovery modifier (Tier 3) applied.")
    print(f"- Input: {args.quality} ({len(quality_rows)} nights of base scores) + {args.summary}")
    print(f"- Output: {args.output} / {args.output_json}")
    print(f"- Nights with a non-zero modifier: {nights_with_modifier} / {len(results)}")
    print(f"- Mean modifier: {avg_modifier}")
    print(f"- Nights whose grade changed due to the modifier: {changed_grade}")
    if sri_values:
        print(
            f"- SRI (display only, not scored): computable for {len(sri_values)} / {len(results)} nights, "
            f"range {min(sri_values):.1f}–{max(sri_values):.1f}"
        )
    else:
        print(
            f"- SRI (display only, not scored): not yet computable"
            f" (needs {SRI_MIN_VALID_PAIRS} adjacent-night pairs within {SRI_WINDOW_DAYS} days)"
        )


if __name__ == "__main__":
    main()
