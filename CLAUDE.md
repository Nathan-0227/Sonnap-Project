# Sonnap 專案背景（給 Claude Code）

## 專案是什麼

Sonnap 是結合「睡眠監測」與「AI 寵物陪伴」的 App。攝影機/穿戴裝置偵測使用者睡眠狀態，
轉換成虛擬寵物的心情與活動，並用 AI（Gemini）生成「夢境日記」。詳見 [README.md](README.md)。

團隊分工：PM/系統整合、UI/UX（Figma）、App 前端、影像工程（OpenCV）、AI/數據處理，共 5 人。

## 資料契約（Data Contract）

所有模組最終都要組成這個格式給後端 API：

```json
{
  "session_id": "20260512_001",
  "status": { "pet_mood": "happy", "current_activity": "dreaming", "energy_level": 85 },
  "metrics": {
    "motion_count": 12,
    "sleep_duration_minutes": 240,
    "ambient_noise_db": 35,
    "sleep_start_time": "...",
    "wake_time": "..."
  },
  "ai_content": { "dream_summary": "...", "advice": "..." },
  "timestamp": "2026-05-12T22:00:00Z"
}
```

## 現有程式碼結構

- `main.py` — FastAPI 後端，目前 `/get-sleep-data` 只回傳寫死的 mock_data，**尚未接上任何真實資料來源**。
- `tapo/motion_detector.py` — OpenCV 讀 Tapo 攝影機 RTSP 串流，偵測翻身動作，寫入 MySQL（`sonnap` DB）。
  ⚠️ RTSP 帳密目前明碼寫死在檔案第 10 行，之後要改成環境變數。
- `garmin/` — Garmin 手錶資料匯入（目前我正在做這部分，見下方詳細狀態）。
- `Research-Background/` — 首頁設計的文獻依據（行為科學/遊戲化理論）。
- `docs`、`app` 目前只是空的佔位檔案。

## Garmin 資料 Pipeline（已完成，見 `garmin/README.md`）

### 架構（2026-08-11 整理後）

5 個步驟，每一步吃前一步的輸出。**所有生成的資料檔集中在 `garmin/data/`**，
`garmin/` 目錄下只留程式碼。腳本用 `Path(__file__).parent / "data"` 定位，
從任何工作目錄執行都可以。

```
garmin_connect_fetch.py    ① 連 Garmin API 抓資料 → data/garmin_standard_data.json
analyze_garmin_sleep.py    ② 按「一晚」分組整理   → data/garmin_sleep_summary.csv
extract_sleep_features.py  ③ 濾有效夜晚、算特徵   → data/garmin_sleep_features.csv
evaluate_sleep_quality.py  ④ Tier1/2 基礎分數     → data/garmin_sleep_quality.csv
apply_recovery_modifier.py ⑤ Tier3 修正值 + SRI   → data/garmin_sleep_quality_final.csv
```

**執行一律用 `python garmin/run_pipeline.py`**（加 `--fetch` 才會重抓資料）。

⚠️ **不要手動一步一步跑**——漏跑中間步驟不會報錯，後面的步驟會安靜地用上次留下的
舊檔案算出結果。2026-08-10 真的發生過（改完 ② 之後只跑 ②→④，漏掉 ③，
evaluate 讀到三週前的 features 檔，完全沒有錯誤訊息）。

### 尚未解決的問題

1. **Garmin 資料還沒接進 API。**
   `main.py` 的 `/get-sleep-data` 仍回傳寫死的 `mock_data`。
   要接的話應該接 `data/garmin_sleep_quality_final.json`（有分數、修正值、SRI），
   資訊比舊的 payload 格式豐富得多。**這是整條 pipeline 唯一還沒打通的最後一段。**

2. **缺少排程與增量抓取。**
   每次要手動執行、指定 `--days`，沒有排程機制（Windows 工作排程器/cron），
   也沒有記錄「上次抓到哪裡」，容易重複抓或漏抓。
   屬社群套件 PoC，Garmin 介面異動時可能失效。

3. **`ambient_noise_db` Garmin 手錶沒有這個數據。**
   需要跟 TAPO 那邊確認這欄位由誰負責提供，並在 data contract 文件上寫清楚。
   （注意：TAPO 現在的「分貝數」是 `np.random` 產生的假資料，不是真的收音。）

### 已修正的歷史問題（保留紀錄，避免重複踩）

- ✅ 跨午夜夜晚被切成兩列 → 改用「起床日」分組（對齊 Garmin 的 `calendarDate`）
- ✅ 睡眠階段誤用「段數」→ 改用 `*_duration_sec` 的分鐘數，與 App 一致
- ✅ 步數多算 → 改用官方 `get_daily_steps`，不再加總 96 個 15 分鐘區間
- ✅ `_parse_sleep_data` 縮排錯誤造成 `UnboundLocalError`（沒睡眠資料的日子會觸發）
- ✅ 06-02 異常列（入睡=起床=00:00:00）→ `extract_sleep_features.py` 會濾掉
- ✅ `build_project_payload()` 沒按「一晚」分組（把 13 天算成一晚）
  → 2026-08-11 已連同 `garmin_importer.py` 一併刪除（該函式的產出從來沒有任何程式讀取）

### Next Development Goal（下一步：Sleep Feature Extraction + Quality Evaluation）

延續現有 pipeline，新增兩支腳本（此規劃已跟另一個 AI 助手的建議比對過，方向正確，
但補上了資料完整性前置修正，避免建立在有瑕疵的資料上）：

**動手前，先處理資料完整性（順序很重要）：**
1. ✅ 已完成（2026-07-11）：重跑 `garmin_connect_fetch.py`，抓 2026-05-29~07-11 共 44 天、53489 筆，
   `garmin_standard_data.json` 已補回（7.5MB）。過程中修掉了 `_parse_sleep_data` 的 UnboundLocalError
   （sleepLevels 那段縮排錯誤，見問題原 #7 相關；沒睡眠資料的日子會觸發）。
2. ✅ 已完成（2026-07-12）：修好 `analyze_garmin_sleep.py`，兩項重大修正：
   (a) 分組改用「起床日」(session date = wake date)。已用 Garmin 原始 `calendarDate` 欄位驗證：
       7/10 22:42 上床、7/11 07:51 起床的那晚，Garmin 自己標記為 calendarDate=2026-07-11。
       修正後 07-10 正確變空、該晚移到 07-11，與 Garmin App 一致。跨午夜夜晚不再被切開。
   (b) 睡眠階段輸出改成「分鐘」(deep/light/rem/awake_minutes + total_sleep_minutes)，
       取代原本的「段數 count」。分鐘值直接來自 Garmin dailySleepDTO 的 *SleepSeconds，
       已驗證與 Garmin App 完全一致（例：06-11 深48/淺329/REM98 分；07-09 總541分=9h01m）。
   ⚠️ 資料語意澄清（之前混淆點）：
       - 睡眠階段 → Garmin 顯示「分鐘」，不是段數。正確資料在 *_duration_sec，已改用。
       - resting_heart_rate → 單一每日數字（Garmin 圖示旁的數字），正確。
       - movement_count → 我們自訂的翻動取樣筆數，非 Garmin 顯示值，勿直接對照。
       - steps → 見下方步數決策。
   ⚠️ 裝置限制：Vivoactive 3 沒有 Garmin 睡眠分數（sleepScores 欄位不存在），無法用官方分數驗證評分。
       且部分夜晚 REM=0（Garmin 也顯示無 REM），是舊錶偵測限制非 bug。
3. ⏭️ 待做：在 `extract_sleep_features.py` 加資料有效性檢查。實測需要濾掉的列：
   - 無睡眠記錄的日子（手錶沒戴睡）：05-28, 06-16, 06-19, 06-20, 06-23, 06-25, 06-29,
     07-03, 07-04, 07-05, 07-08, 07-10（sleep 欄位空、total_sleep_minutes=0）。
   - 06-02 異常：sleep_start == wake == 00:00:00（睡眠時長=0）。
   - 資料極少的日子（連 avg_heart_rate 都是 null）。

**步數決策：✅ 已完成（2026-07-12）改用官方 `get_daily_steps`。**
- fetch 新增 `_parse_daily_steps()`，主迴圈改呼叫 `get_daily_steps(day, day)`，輸出 `daily_steps`
  與 `step_goal` metric（時間戳設在該日 15:00 避開睡眠區間）。
- analyze 改讀 `daily_steps`（直接設定非加總）。已重抓驗證：06-11 = 195 步（= Garmin App）。
- 現在整條 pipeline（fetch → standard_data → analyze → summary）數字全部與 Garmin App 一致。
- summary 欄位：date, sleep_start_time, wake_time, total_sleep_minutes,
  deep/light/rem/awake_minutes, movement_count, steps_total,
  avg/min/max_heart_rate, avg_stress_score, resting_heart_rate。

**接著實作 `extract_sleep_features.py`：**
- 輸入：`garmin_sleep_summary.csv`
- 輸出：`garmin_sleep_features.csv`
- 每天產生：Sleep Duration (hours)、Deep/REM/Awake Ratio、Average Heart Rate、Resting Heart Rate、
  Average Stress、Movement Count、Total Steps、Sleep Efficiency (optional)。

**再實作 `evaluate_sleep_quality.py`（rule-based scoring，總分 100）：**

⚠️ 評分權重已於 2026-07-15 依文獻改版。原本的 30/20/15/15/20（時長/深睡/REM/清醒/HR+壓力+翻動）
**已作廢**，改採 `Research-Background/Garmin手錶分數.md` 的 PSQI 式「核心高權重、輔助低權重」原則。

**V1 權重（只用現有資料算得出、且有文獻門檻的指標）：**
| 指標 | 權重 | 文獻 | 門檻 |
|---|---|---|---|
| 睡眠時長（核心）| 30 | Hirshkowitz 2015 | 分齡，成人 7–9h |
| 睡眠效率（核心）| 25 | Hertenstein 2018 | ≥85 佳／80–84 尚可／<80 低 |
| WASO 夜間清醒（核心）| 25 | Ohayon 2004、Harrison 2021 | 分齡，年輕成人 0–15min 佳 |
| 深層睡眠比例（輔助）| 10 | Boulos 2019、Hertenstein 2018 | 13–23% 參考區間 |
| REM 比例（輔助）| 10 | Ohayon 2004 | 分齡，年輕成人 20–25% |

- 分級：80-100 Good／65-79 Normal／50-64 Poor／<50 Bad。
- 輸出 `garmin_sleep_quality.csv` / `garmin_sleep_quality.json`。
- Recommendation 先用 rule-based 文字，之後可替換成 Gemini AI 生成。

**V2 待加（各有前置條件）：**
- 心率／壓力：文獻要求「個人 baseline（近 14–28 晚）+ 趨勢」，非固定 bpm。
- 活動量：文獻要求「相對個人 baseline + 中強度分鐘數」，需另抓 `get_intensity_minutes`。
- 睡眠規律性（就寢/起床變異、平假日差）：用現有 summary 即可算，尚未實作。
- 入睡潛伏期 + 真實睡眠效率：**需等 TAPO 攝影機提供「上床時間」**（見下方）。
- 睡眠片段化：需把 `standard_data` 的 sleep_segment 數與醒來次數帶進 summary。

**已決議的設計決策（2026-07-15）：**
1. **年齡**：由使用者註冊時輸入。V1 先做成可設定參數，預設「年輕成人 18–25」。
   文獻的時長／REM／WASO 門檻都要分齡，不能用單一標準。
2. **權重**：採文獻的 PSQI 式核心/輔助架構（見上表），不用原本的固定 30/20/15/15/20。
3. **範圍**：先做 V1，其餘進 V2。

**⚠️ 資料語意重要澄清：**
- **HRV ≠ 心率**。心率是「一分鐘跳幾下」；HRV 是「每兩下心跳間隔時間的變化量（ms）」。
  我們抓的 `heart_rate` 是每分鐘平均值，**無法反推 HRV**（需 beat-to-beat RR interval）。
  但 Garmin 的「壓力分數」本身即由 HRV 推算，等於已間接取得 HRV 資訊。
  Garmin HRV Status 為 2022 後新錶功能，Vivoactive 3 很可能不支援（尚未實測 `get_hrv_data`）。
- **目前的 `sleep_efficiency` 不是臨床真效率**。因缺「上床時間」，分母用的是
  （起床 − 入睡），實為「睡眠期間效率」，不含入睡潛伏期。報告中須誠實標註。

**TAPO 攝影機整合（規劃中，會解鎖兩個文獻指標）：**
- 目標：由攝影機偵測「上床時間」（人進入床鋪區域並躺下），Garmin 已提供「入睡時間」，兩者互補。
- 解鎖：入睡潛伏期 = Garmin 入睡 − 攝影機上床；真實睡眠效率 = 總睡眠 ÷（起床 − 攝影機上床）。
- 三個必須解決的前置問題：
  1. **時間同步**（最關鍵）：攝影機與 Garmin 時鐘須對準同時區且準確，否則潛伏期無意義。
  2. 夜視環境：紅外線雜訊大，建議用「床鋪 ROI + 動作趨於穩定」規則，非純畫面差分。
  3. 「上床」定義：建議為「當晚第一次進入床鋪區域並持續停留」；需處理半夜起身、在床滑手機等情況。
- 隱私：臥室攝影機需在報告中說明資料處理與知情同意。

**架構決策（需要跟團隊對齊，不要自己悶著做）：**
- 這個新流程（summary → features → quality）跟原本 README 定義的 data contract
（`pet_mood`/`energy_level`/`dream_summary`，透過 `main.py` 的 FastAPI 提供給 Flutter）是兩條不同路徑。
  需要決定：quality score 要怎麼映射回 `pet_mood`/`energy_level`？最終是 Flutter 直接讀 JSON 檔，
  還是透過 FastAPI API？做決定前先跟 PM/前端對一次，避免兩條資料流各自為政。
- ✅ 已處理（2026-08-11）：`garmin_importer.py` 與其 `build_project_payload()` 已刪除，
  組員不會再誤用那個有 bug 的舊路徑。

**Coding 規範（沿用團隊既有規範 + 新腳本要求）：**
- 保持現有專案結構，不要破壞現有 Garmin parser。
- Python 3.13，輸出檔案一律 UTF-8，時間格式一律 ISO8601（+08:00）。
- 優先用標準庫，非必要不用 pandas。
- 程式碼要模組化、可重用，關鍵邏輯加註解。

### 進度更新（2026-07-20，此輪由 Claude 完成）

1. ⚠️→✅ **文獻查證與後續逐項核對，最終合併成單一文件**——正式且唯一的成果是
   [`Research-Background/Garmin手錶分數.md`](Research-Background/Garmin手錶分數.md)
   （A–M 共 13 節完整學術論述 + 附錄「文獻門檻 × 程式碼對照表」+ 修訂記錄 + Sonnap 章節樹狀架構）。
   演變過程：`_Perplexity_文獻查證交接.md` 是查證草稿、不是待辦事項；Claude 一度誤判成
   「還沒查證」而用 WebSearch 重查一次，另存成 `睡眠品質評分文獻依據.md`；後來逐項核對兩份文件，
   發現並修正了 B/F/G/I 節共 4 處真實的邏輯缺口（B 節自相矛盾、F/G 節引用內容支撐不了設計邏輯、
   I 節內部兩段話互相矛盾且跟 V1 程式碼對不上）；2026-07-30 使用者要求把兩份文件合併成一份，
   避免文件太多——`睡眠品質評分文獻依據.md` 的對照表與修正記錄已整併進 `Garmin手錶分數.md`
   附錄，原檔已刪除。獨立查證的結論可信：程式引用的文獻皆為真實存在、DOI 正確的論文。
   **後續有新文件要交接給別的 Claude/VS Code 前，先開口問對方現有進度，不要預設「沒做過」。**

2. ✅ **修掉 `evaluate_sleep_quality.py` 的建議文字矛盾 bug**：`build_recommendation()`
   原本只要「失分比例 > 15%」就會加一句改進建議，沒考慮整晚等級已經是 Good，
   導致像 2026-05-31（總分 93.8）出現「請維持目前的作息」後面又接「睡眠時間不足，
   建議提早就寢」的自相矛盾。已修成 Good 等級不再附加改進建議。重跑後掃過全部
   33 晚輸出，確認無殘留矛盾。平均分數 85.4（Good 25 / Normal 6 / Poor 1 / Bad 1，
   8 晚 REM 未測得排除計分）。

### 進度更新（2026-07-31，此輪由 Claude 完成）

1. ✅ **新增 `garmin/apply_recovery_modifier.py`，V2/Tier3「生理修正訊號」正式實作上線。**
   讀 `garmin_sleep_quality.csv`（Tier1/2 基礎分數）+ `garmin_sleep_summary.csv`（心率/壓力/步數），
   輸出 `garmin_sleep_quality_final.csv/json`（`final_score = clamp(基礎分數 + 修正值, 0, 100)`）。
   四項修正訊號、各自獨立冷啟動（累積 <14 晚有效歷史資料則該項修正值=0，非全有全無）：
   - 靜止心率 ±2（`RHR_CAP`，Quer 2020）
   - 睡眠期間平均心率 ±2（`AVG_HR_CAP`，Cosgrave 2021）
   - 壓力分數 ±4（`STRESS_CAP`，Vivoactive 3 無 HRV，以 Garmin 壓力分數替代）
   - 活動量（步數）0～+2（`ACTIVITY_CAP`，僅加分不扣分）
   總上限 ±10。baseline 採最近 14–28 晚中位數，只用「當晚之前」的歷史資料，避免時間序列資料洩漏。
   全檔逐行加了說明注釋（使用者要求）。已用 33 晚真實資料驗證：21 晚套用非零修正值、
   平均修正值 0.35、2 晚因修正值改變分級。

2. ✅ **修掉壓力/心率修正值的統計不穩定 bug（2026-07-30 記錄）**：原本用「相對 baseline 的
   百分比」換算，但壓力分數 baseline 偏小（例如平常僅 3–7 分）的夜晚，些微絕對變化會被
   百分比公式放大到不合理程度（同樣差 8 分，baseline=7 時是 -114%、baseline=50 時只有 -16%），
   屬「除以小分母」的統計不穩定，非設計邏輯錯誤。已改為「絕對差距」換算（每差 1 bpm / 1 分
   壓力分數給固定分數），不再受 baseline 大小影響；步數因 baseline 數值本身較大，維持用百分比。

3. ✅ **心率修正值拆成靜止心率／睡眠期間平均心率兩個子項（2026-07-31 記錄）**：原本只用
   `resting_heart_rate` 算心率修正值，後來發現 `Garmin手錶分數.md` F 節已有的 Cosgrave (2021)
   引用其實對應的是「睡眠期間平均心率」（`avg_heart_rate`）這個獨立子構念，先前沒接進程式碼。
   已補上 `avg_heart_rate` 修正值，並把原本合計 ±4 的心率額度拆半（RHR ±2、avg_HR ±2），
   而非兩者各自獨立滿額——理由是二者高度相關、同屬心血管自律神經訊號，各給滿額會造成
   同一件事被重複計分，跟「淺層睡眠不獨立計分，因深睡+REM+淺層=1」是同一道理。

4. ✅ **`Garmin手錶分數.md` 同步更新**：F/G/H 節各補上「實作更新」段落，I 節 Tier3 狀態由
   「V2 規劃中」改為「V2 已實作」並更新分項額度，附錄對照表 F 列拆成靜止心率／平均心率兩列，
   修訂記錄補上 2026-07-30（百分比→絕對差距）與 2026-07-31（心率拆分項）兩筆記錄。

### 進度更新（2026-08-10，此輪由 Claude 完成）

1. ✅ **M（睡眠片段化）由 Tier4 併入 Tier3，Tier3 上限 ±10 → ±12；J（睡眠規律性/SRI）
   已實作計算但「刻意不計分」，只呈現數值與趨勢。**
   M 併入而非另立一層的理由：本專案區分 Tier1/2 與 Tier3 的判準一直是「文獻給絕對參考範圍
   vs 相對個人 baseline 的偏離量」，不是「生理 vs 作息」這種題材分類。M 的文獻明說沒有
   跨族群通用門檻，性質跟心率/壓力一致。
   - `analyze_garmin_sleep.py` 新增 `awake_count`、`sleep_segment_count` 兩欄
     （沒戴錶的日子輸出 None 而非 0，避免被誤判成「醒來 0 次、超規律」）。
   - `apply_recovery_modifier.py` 新增 M（醒來次數 ±1 + 睡眠段數 ±1）與 SRI（不計分）。

2. ⚠️ **J/SRI 最終「不計分」的完整推理（重要，這段是整輪最有價值的產出）：**
   依序排除了三種做法，每一種都是實際做過或查證過才排除的：
   - ❌「今晚 vs 個人 baseline」逐夜比較：會把測的東西從「你有多不規律」偷換成
     「你最近有沒有比以前更不規律」。長年作息都亂的人永遠拿 0 分（沒變得更亂），
     但文獻說這種人正是風險族群 → 構念不符，跟 K 節 Troxel/MSLT 是同型錯誤。
     且會**懲罰作息改善**：07-11 那晚 22:42 上床（平常凌晨 1-3 點）明明是變好，
     卻因「偏離常態」被扣分，而且整個調整期都會被持續扣。
     統計上也不乾淨：SRI 本身是 28 天滾動值，相鄰兩天窗格有 27 天資料重疊（96%）。
   - ❌「就寢時間標準差 + 自訂切點」：查證後三篇候選文獻各有致命傷（Wong 2022 年齡吻合
     但沒標明數字是否為標準差、Price 2023 測的是「睡眠中點」標準差構念不符、UK Biobank
     構念對但平均 62 歲且只是研討會摘要）。且技術上有 bug：用「距中午幾分鐘」換算時，
     橫跨中午的起床時間會被錨點切開，算出 507 分鐘的假變異度（實際只差 1 小時）。
   - ❌「SRI 對照同齡常模計分」（一度已經寫完並跑過）：**Czeisler 2026 證實
     同一批資料用 sleepreg 跟 GGIR 兩套件算，SRI 差異顯著，且「光是計算方法不同
     就足以改變死亡率、糖尿病、心房顫動模型的結果與詮釋」**。佐證：NHANES（54.5 歲）
     SRI 平均 63.0 vs UK Biobank（62.8 歲）中位數 81.0——差 8 歲卻差 18 分，
     顯然是方法學差異不是年齡效應。我們這個近似實作跟外部常模的誤差極可能超過
     整個 ±2 額度，那個比較本身就沒有意義。
   - ✅ **最終：SRI 照算照輸出（供 App 顯示數值與趨勢），但不進 total_modifier。**
     分寸是：Windred 2024 能支持「規律性重要、值得呈現」（預測死亡率優於睡眠時長），
     但支持不了「今晚 SRI 該換算成幾分」。之後若 RIRI 標準普及或能自建同齡常模，
     計算邏輯都保留著，恢復計分只需改幾行。
   - 實測：28 日滾動 SRI 範圍 69.5–80.4，07-11 因提早上床正確地由 79.2 掉到 69.5。

   ⚠️ **順帶抓到第二起作者誤植**：文件原本寫「Mason et al.」的那篇 RIRI 論文，
   第一作者其實是 **Czeisler ME**，且缺卷期。已更正為 Sleep. 2026;49(4):zsaf299。
   這是繼 K 節 Troxel/Iskander 之後第二次，**日後引用文獻一律要核對第一作者**。

3. ✅ **M 刻意排除 WASO**：M 節文獻用「WASO+醒來次數+睡眠段數」定義片段化概念，但 WASO
   已在 Tier1 佔 25 分，再算一次會讓同一數值影響總分兩次。窄化為只用醒來次數+睡眠段數，
   這兩者補的正是 WASO 看不出的資訊（同樣清醒 40 分鐘，「醒一次躺很久」vs「醒八次各五分鐘」
   完全不同）。已在文件誠實標註此窄化。

4. ⚠️ **發現並修掉 `activity_modifier` 的資料有效性問題（重要）：**
   實測步數中位數只有 **185 步**。查證後確認原因是**起床後會取下手錶、傍晚才戴回**
   （心率讀數佐證：12:00 只有 45 筆/小時、17:00 回到 734 筆、19:00 後回到 1100 筆）。
   所以 `steps_total` 測到的是「傍晚在家的活動量」，不是全日活動量。
   - 統計問題：baseline=185 時，多走 19 步（+10%）就打滿 +2 分——19 步是雜訊。
     這就是壓力分數當初那個「小分母」bug 的重現，而程式碼註解原本還寫著
     「步數 baseline 通常夠大，不會有這問題」，該假設已被自己的資料推翻。
   - 構念問題：H 節文獻研究的都是每日數千步的族群，「活動量高於常態有助睡眠」
     這個結論從沒在 185 步的量級上被檢驗過。
   - 已加 `ACTIVITY_MIN_BASELINE_STEPS = 1000` 門檻自動停用，且 `modifier_note` 會
     明確區分「資料無效（要改配戴習慣）」與「冷啟動（繼續戴就好）」——後者講法會誤導。
   - 修掉後平均修正值由 0.89 降到 0.04，更合理（基於個人 baseline 的修正值長期本來就該
     趨近於零，先前的 0.89 是被灌水的活動量加分撐起來的）。

5. **目前 Tier3 全貌**（33 晚實測，飽和率健康、1 晚改變分級且是相鄰級距）：
   | 訊號 | 額度 | 飽和率 | 啟用條件 |
   |---|---|---|---|
   | 靜止心率 | ±2 | 10% | 累積 14 晚 |
   | 睡眠期間平均心率 | ±2 | 10% | 累積 14 晚 |
   | 壓力 | ±4 | 14% | 累積 14 晚 |
   | 活動量 | 0~+2 | — | 累積 14 晚 **＋ baseline ≥1000 步**（本專案停用中）|
   | 醒來次數 | ±1 | 15% | 累積 14 晚 |
   | 睡眠段數 | ±1 | 15% | 累積 14 晚 |
   | **SRI（不計分）** | **—** | — | 28 日內 ≥10 組相鄰日配對；只輸出數值供呈現 |

   總上限 ±12。輸出欄位：`rhr_modifier`、`avg_hr_modifier`、`stress_modifier`、
   `activity_modifier`、`awake_modifier`、`segment_modifier`、`total_modifier`、
   `sri`（呈現用）、`sri_valid_pairs`、`modifier_note`、`final_score`、`final_quality`。

6. 待辦（尚未動工）：
   - 中強度活動分鐘數（需接 `get_intensity_minutes`）——但在配戴習慣改變前，
     接了也一樣拿不到有效的白天資料，優先度低。
   - TAPO 側（`tapo/motion_detector.py`）有一套獨立的 `sleep_quality_score`，與本檔案輸出的
     `final_score` 邏輯、格式皆不同，需與隊友/PM 對齊要顯示哪一個或如何合併，尚未處理。
   - `main.py` 仍回傳寫死 mock_data，未接上 `garmin_sleep_quality_final.json`。

### 進度更新（2026-08-11，此輪由 Claude 完成）

✅ **garmin/ 資料夾整理**（原本 19 個檔案裡有 11 個是生成物，平鋪在同一層）

1. **生成物集中到 `garmin/data/`**，`garmin/` 只留 6 支程式 + README。
   五支腳本的路徑改用 `Path(__file__).parent / "data"`，不再是相對路徑字串——
   從專案根目錄或 `garmin/` 執行都能正確定位（已實測兩種都可）。

2. **新增 `garmin/run_pipeline.py`**：依序執行 4 步（加 `--fetch` 才含抓取），
   任一步失敗立即中止並回傳非零 exit code。解決「漏跑中間步驟不會報錯」的隱患。

3. **刪除 `garmin_importer.py`**（讀手動匯出 CSV 的替代入口）。查證後確認
   `garmin_export/` 資料夾從未存在，這條路徑從來沒被使用過。但它不能直接刪——
   `garmin_connect_fetch.py` 有 `from garmin_importer import ...` 借用兩個函式：
   - `build_standard_payload()` → 已搬進 `garmin_connect_fetch.py`，
     並順手修掉 `source` 標籤寫死的問題（API 抓的資料原本會被標成「手動匯出」）
   - `build_project_payload()` → 直接移除。它有已知 bug（沒按「一晚」分組，
     把 13 天算成一晚），而且它的產出 `garmin_project_payload.json` **全專案沒有
     任何程式讀取**——等於每次抓資料都產生一個沒人要的錯誤檔案

4. **`GARMIN_IMPORT_GUIDE.md` → `garmin/README.md`**：舊文件內容全是已刪除的
   importer 用法。新 README 有 pipeline 流程圖、各步驟輸入輸出、已知限制表、
   資料語意注意事項。專案根目錄 `README.md` 的 Garmin 段落也一併更新。

5. 驗證：整理前後 `garmin_sleep_quality_final.csv` 完全一致（`diff` 確認）。

⚠️ **這輪也發現我自己前一次的疏漏**：宣稱「全流程重跑無誤」時實際漏跑了
`extract_sleep_features.py`。那次剛好沒造成錯誤（改動只是新增下游沒用到的欄位），
但這正是 `run_pipeline.py` 要防的問題。**日後宣稱「跑過了」之前，先確認每一步都真的跑了。**

### 開發規範

- 請勿直接 push 到 main，從 main 切新分支：`git checkout -b feature/功能名稱`。
- Commit message 保持簡潔（如：`feat: 新增睡眠數據欄位`）。
- Bug 或功能討論請開 GitHub Issue，避免資訊散落在通訊軟體。
