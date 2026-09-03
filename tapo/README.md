# TAPO 攝影機影像模組

> 負責人：影像組（Elvira）
> 這份 README 由 AI/數據組於 2026-08-15 代寫，內容是**掃描程式碼與資料檔得出的
> 事實**，不是設計意圖。有寫錯的地方請影像組直接改。

用 Tapo IP 攝影機的 RTSP 串流偵測睡眠期間的翻身與聲音，輸出每晚的事件時間軸。

---

## 檔案

| 檔案 | 說明 |
|---|---|
| `tapo_detector.py` | **正式版偵測程式**。預設監測時段 **01:00–08:00**（`tapo_detector.py:22-23`） |
| `recalculate_scores_full.py` | V3 評分公式，寫好了但沒有套用到現有資料 |
| `rebuild_reports_from_videos.py` | 從既有的 `turn_*.mp4` 重跑偵測、重建報告並寫回 MySQL |
| `import_reports_to_mysql.py` | 把 `sleep_reports/` 底下的 JSON 匯進 MySQL |
| `analyze_from_mysql.py` | `SleepAnalyzer` 類別：從 MySQL 讀資料、產生圖表（需 pandas / matplotlib） |
| `sleep_anylzer.py` | 同類型的分析腳本，與上一支**不是同一份**（內容不同） |
| `check_db_connection.py` | 20 行的連線測試：連得上就印出資料表清單 |
| `check_backup_files.py` | 掃描 `sleep_reports/` 與 `backup_reports/`，列出有哪些 JSON |
| `sound_test.py` | 收音測試：錄 5 秒、算 RMS |
| `sleep_records.sql` | MySQL dump。**建表 SQL 就在這裡**（先前記的「沒有建表 SQL」已不成立） |
| `sleep_reports/` | 每晚的報告 JSON |
| `sleep_report.json` | 舊的單檔輸出（17:26 起、僅 29 秒的測試錄影） |
| `sleep_analysis_charts/` | 分析腳本產生的 PNG |
| `.env.example` | 設定範本，複製成 `.env` 填入攝影機網址 |

### ⚠️ 更正：先前寫「以下四個檔案是誤建的、可以直接刪除」——**那是錯的**

它們不是誤建，是**真實的程式碼被存成了錯誤的檔名**（存檔時把第一行 `import xxx`
當成檔名了）。實際內容是 20~456 行、各有各的用途，照原本的說法刪掉會丟掉約 1400 行。
已全部改名：

| 原檔名 | 改成 | 行數 |
|---|---|---|
| `import json.py` | `import_reports_to_mysql.py` | 110 |
| `import mysql.py` | `analyze_from_mysql.py` | 456 |
| `import os.py` | `check_backup_files.py` | 34 |
| `import mysql.connector`（連副檔名都沒有） | `check_db_connection.py` | 20 |
| `sleep rreport makong.py` | `rebuild_reports_from_videos.py` | 340 |
| `newsleep score count.py` | `recalculate_scores_full.py` | 451 |
| `sound test.py` | `sound_test.py` | — |

`recalculate_scores_full.py` 這個名字不是我取的——**它自己的 docstring 就寫著
「執行方式: python recalculate_scores_full.py」**，只是存檔時沒有照做。

改名不只是整齊：檔名帶空格、或叫 `import json.py` 的檔案**沒辦法被 import，
連跑 `python -m py_compile` 都得加引號**，等於這 1400 行程式碼沒有任何工具檢查得到。
改完之後 9 支全部通過語法檢查。

> 2026-08-15 已刪除四支舊版 `motion_detector.py`（1~4），保留 `tapo_detector.py`。
> 刪除前有五個版本、監測時段各不相同（15:13–15:14 / 22:00–23:00 / 00:30–08:00），
> 且沒有任何說明哪支是正式的。全部保留在 git 歷史裡，需要可取回。

---

## ✅ RTSP 帳密已改成環境變數

先前 `tapo/tapo_detector.py`、`tapo/sound test.py`、`tapo 2.0/tapo_detector.py`
都把 RTSP 帳密**明碼寫死**，而本 repo 是公開的。
現在全部改讀 `CAMERA_RTSP_URL`，**沒有預設值**——讀不到就中止並印出怎麼設定。

**設定方式**：`cp tapo/.env.example tapo/.env`，填入攝影機網址。

### ⚠️ 順手修掉一個讓「已經改成環境變數了」變成假話的 bug

`tapo 2.0/sleep_monitor.py` 早就寫了 `get_env_var('CAMERA_RTSP_URL', <寫死的網址>)`，
看起來已經處理好了。但它的 `.env` 載入寫的是 `Path('.env')`——
**相對於當下工作目錄**。從專案根目錄執行時找不到 `tapo 2.0/.env`，
於是安靜地退回第二個參數，也就是那組寫死的帳密。

修法是改成 `Path(__file__).parent / '.env'`（`ai/env_utils.py` 一直是這樣寫的），
並把兩處寫死的預設值拔掉。三種情境都實測過：

| 情境 | 結果 |
|---|---|
| 同目錄沒有 `.env` | ✅ 明確中止並印出設定說明，**不再沿用任何寫死值** |
| 同目錄有 `.env` | ✅ 讀到的值與檔案內容逐字相同（註解列會略過） |
| 從別的工作目錄執行（先前會退回寫死值的情境） | ✅ 仍讀得到 |

⚠️ 刪掉程式碼裡的帳密**不等於移除**——git 會永久保留歷史。
真正有效的動作是**修改攝影機密碼**（2026-08-28 已經換過一次，舊值已失效）。

⚠️ `.env` 不要用 GitHub 網頁「Add files via upload」上傳，那會**繞過本機 `.gitignore`**
——`tapo 2.0/.env` 就是這樣進版控的。一律用 `git commit`。

---

## 執行

```bash
pip install -r ../requirements.txt
python tapo/tapo_detector.py
```

程式會常駐等待，每天 `START_TIME` 到了自動開始監測、`END_TIME` 停止並存檔。

⚠️ 第一次跑之前要先 `cp tapo/.env.example tapo/.env` 填入攝影機網址，
否則程式會直接中止（這是刻意的，見上一節）。

⚠️ 需要一個 MySQL 資料庫（設定在 `tapo_detector.py` 的 `DB_CONFIG`）。
建表 SQL 在 `tapo/sleep_records.sql`。

---

## 目前的資料

`sleep_reports/<日期>/sleep_report_<時間>.json`，共 5 晚可用：

| 影片實際夜 | 時間範圍 | 事件數 | 大翻身 |
|---|---|---|---|
| 2026-08-02 | 01:25–07:38 | 1177 | 32 |
| 2026-08-03 | 01:41–06:50 | 6649 | 106 |
| 2026-08-04 | 01:07–10:11 | 2078 | 75 |
| 2026-08-05 | 02:18–10:29 | 5558 | 111 |
| 2026-08-06 | 01:33–10:26 | 7428 | 42 |

其中 **08-02 / 08-04 / 08-06 與 Garmin 資料重疊**，可做感測器交叉驗證。

### ⚠️ 三個資料陷阱（下游接資料時必須處理）

**1. `report_date` 不是那一夜的日期**

程式寫的是 `datetime.now()`（`tapo_detector.py:343`），也就是**產生報告的時間**。
實例：`sleep_reports/2026-08-04/sleep_report_003653.json` 的 `report_date` 是
`2026-08-04`，但內容是 08-03 那一夜（01:41–06:50，影片檔名全是 `20260803`）。
資料夾名稱同樣不可信（它等於 `report_date`）。

→ **日期要從 `video_clip` 檔名取**（格式 `turn_YYYYmmdd_HHMMSS_*.mp4`）。
已驗證 9 份報告每份的影片日期集合都唯一，可安全當日期鍵。

**2. 4 份 `_recovered` 檔是壞的**

時間戳全是 `00:00:00`~`00:00:04`，且 08-07 的三份內容完全相同。應排除。

**3. `sleep_quality_score` 全是 0**

5 份全部為 0（先前的版本是撞地板值 50）。評分邏輯需要檢查。

---

## ⚠️ 已知問題

### 音訊分類是死碼

`tapo_detector.py` 用 ffmpeg 從串流抽音訊算 RMS，**這是真的收音**
（先前版本的分貝值都是 `np.random` 模擬的）。但單位對不上：

```
db = 20 * log10(rms)      rms 來自 int16，最大 32767
→ 20 × log10(32767) = 90.3        db 的理論最大值是 90.3

AUDIO_SILENCE_THRESHOLD = 200     ← 永遠達不到
AUDIO_SNOOZE_THRESHOLD  = 1500    ← 更達不到
```

**結果 `sound_type` 永遠是 `"quiet"`**，打鼾偵測整段不會觸發。
那兩個門檻看起來是給 RMS 用的，變數從 RMS 改成 dB 時忘了改門檻。

### 這個 dB 不是聲壓級（SPL）

`20·log₁₀(RMS)` 測的是**數位訊號振幅**，會被麥克風靈敏度、前級增益、
攝影機的自動增益控制、擺放距離影響，而房間並沒有變吵。
真正的分貝以 20 μPa 為參考基準，**必須用分貝計校準**。

→ 未校準的值**不能跨使用者比較**，也**不能在報告裡寫成「環境音 35 分貝」**。
它只在「同一次錄影、設定不變」時能反映相對變化（偵測打鼾事件是合理用途）。

### RTSP 帳密明碼寫死

在 `tapo_detector.py:18`，且**本 repo 是公開的**。建議改讀環境變數。

⚠️ 注意：刪掉程式碼裡的帳密**不等於移除**——git 會永久保留歷史。
真正有效的動作是**修改攝影機密碼**。

### 錄影是排程啟動，不是偵測到人進房

`START_TIME = "00:30:00"` 寫死。所以「第一個動作事件」只是
「00:30 之後的第一次動」，**不能當成上床時間**。

這件事有代價：**「入睡潛伏期」與「真實睡眠效率」兩個文獻指標解鎖不了**，
而那是 TAPO 對本專案最大的潛在價值（Garmin 只知道「入睡時間」，
不知道「上床時間」，兩者相減才是潛伏期）。

→ 要解鎖需要：傍晚就開始錄 + 床鋪區域（ROI）偵測「人躺下並持續停留」。

### 其他

- `cv2.imshow` 讓它無法在無桌面環境（伺服器、排程）執行
- `sleep_records` 資料表沒有建表 SQL

---

## 下游怎麼用這份資料

`build_app_payload.py` 的 `load_tapo_report()` 會讀取，但**有有效性門檻**——
過不了就只用 Garmin 資料，不會報錯：

| 檢查 | 擋掉什麼 |
|---|---|
| 錄影時段全在白天（6–20 時） | 測試錄影 |
| 每小時大翻身 > 30 次 | 動作偵測捕捉到整個畫面變化而非人體 |

`decibel` 與 `snore_count` **一律不採用**，無論其他檢查過不過（見上方說明）。

目前 `sleep_reports/` 底下的每夜資料**尚未接入** payload，只有舊的單檔路徑有接。
接入計劃見 `../PROJECT_STATUS.md` 第七節。
