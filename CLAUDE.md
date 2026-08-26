# Sonnap 專案背景（給 Claude Code）

## 📖 這份檔案怎麼讀

| 這裡有什麼 | 這裡沒有什麼 |
|---|---|
| **現行的規則、語意、下一步** | 逐輪的過程記錄 → [DEVLOG.md](DEVLOG.md) |
| 動評分／遊戲化之前必讀的紅線 | 「當初為什麼這樣決定」的完整推理 → [DEVLOG.md](DEVLOG.md) |

> ⚠️ **這份檔案只寫現在為真的事。** 發現哪一段過期了，請**改掉或刪掉**，
> 不要在旁邊加一句「這段已過期」——同一份檔案裡的兩種說法，讀的人無從判斷哪個新，
> 而警語只在讀者剛好讀到警語時有效。過程記錄要留就留進 [DEVLOG.md](DEVLOG.md)。
>
> （2026-08-26 拆分。拆分前這裡有 1016 行，其中「`main.py` 仍回傳寫死 mock_data」
> 這種**早已完成卻還寫著「尚未完成」**的段落至少兩處。）

## 專案是什麼

Sonnap 是結合「睡眠監測」與「AI 寵物陪伴」的 App。攝影機/穿戴裝置偵測使用者睡眠狀態，
轉換成虛擬寵物的心情與活動，並用 AI（**Claude API**，見 `ai/llm_client.py`）生成「夢境日記」。詳見 [README.md](README.md)。

團隊分工：PM/系統整合、UI/UX（Figma）、App 前端、影像工程（OpenCV）、AI/數據處理，共 5 人。

---

## 🔴 安全規範（永遠有效）

`garmin/.env` 有**真實 Garmin 帳號密碼**。絕不提交、絕不在回覆中印出或引用其內容。

⚠️ `tapo/tapo_detector.py:29` 與 `tapo/sound test.py:7` 的 RTSP 帳密仍是**明碼寫死**
（影像組負責，尚未改成環境變數）。同樣不要複製進回覆或 commit。

---

## 🔖 交接區：現在在哪、下一步做什麼（2026-08-26 更新．新對話先讀這段）

現行路線圖：`C:\Users\user\.claude\plans\abundant-nibbling-sutton.md`
（D2 使用者實測 → 多使用者架構 → 行為介入迴圈）。

✅ **那份路線圖的後端部分已於 2026-08-26 全部完成並合併進 `main`**
（PR #11：多使用者持久化、Health Connect adapter、行為介入迴圈、51 晚遷移、驗收測試）。
**剩下的全部在手機端**：Android 的 UsageStats（取得 `lights_out_at` 與睡前 App 分布）、
Accessibility 阻斷、Health Connect 串接。後端的端點與資料表都已就緒且有測試，
手機端接上去就能跑 D2。

⚠️ **要動評分邏輯或新增遊戲化功能（挑戰／獎勵／寵物成長／貨幣）之前，
先讀「🚧 設計紅線」那一節**——那五條紅線是拿外部同類專案對照後定的，
其中第 4、5 條防的是我們還沒踩但下一步最可能踩的坑。

### ⏭️ 下次接手的三件事（2026-08-26 留．按這個順序）

**① Tier3 的 baseline 會過期 —— 等使用者決定，程式一行都沒改**

`MAX_BASELINE_NIGHTS = 28`（`garmin/apply_recovery_modifier.py:181`）
**數的是「晚」不是「天」**。配戴稀疏時 28 晚會橫跨兩三個月：

| 訊號 | 算 2026-08-17 時，baseline 實際往回跨了 |
|---|---|
| 靜止心率 | **60 天**（9 週） |
| 睡眠期間平均心率 | 32 天 |
| 入睡前壓力 | **79 天**（11 週） |

程式第 396 行的註解寫「捨棄太久以前的資料」，但它**按筆數捨棄不按時間**。
對照：`SRI_WINDOW_DAYS`（:265）明寫「用日曆天而非有資料的晚數」——
這個區別程式裡別處有處理，Tier3 的 baseline 沒有。

後果：新 5 晚（08-17~08-23）的 `total_modifier` 平均 **−7.09**，
而舊 46 晚是 **−0.33**，三個訊號幾乎全部打滿負值。
基於個人 baseline 的修正值長期本來就該趨近於零，
所以那**不是「這幾晚睡得特別差」**，是 baseline 不能代表現在的自己。

⚠️ 但**訊號本身也真的位移了，而且從 08-02 就開始**（不是重抓造成的）：
靜止心率 07-11~07-27 穩定在 50–56、08-02 起跳到 62–77；
步數中位數 150 → 3624（**手錶開始整天配戴**）；入睡前壓力 4.9 → 32.8。

三個選項的實測影響（已算好，不必重算）：

| 選項 | 影響 |
|---|---|
| **(a) 不改，只在 `modifier_note` 標註 baseline 跨了幾天** | 分數一律不變。⚠️ 配戴率已大幅改善（新時期 6/9 天步數 >1000），再四週這個問題會自己消失 |
| (b) 加「28 個日曆天」上限 | 讓程式做到它註解說的事。代價：靜止心率 38→**28** 晚、壓力 35→**16** 晚會回到冷啟動 |
| (c) 什麼都不動 | 只寫進文件 |

**② 新 5 晚沒有 AI 夢境**

`python garmin/run_pipeline.py --ai` —— ⚠️ **會真的打 Claude API**（`ai/.env` 已有金鑰）。
目前 `app_payload.json` 最新那晚 `is_ai_generated=false`，退回規則式文字。
⚠️ 跑之前先看 8/15 記錄的「深睡類調色盤只對應 2 個家族」那個未解問題
（`MOTIF_FAMILIES` 拆成一對一，約 6 行），否則新 5 晚很可能又寫出「棉被與雪」。

**③ TAPO 的 `sonnap` 資料庫不在這台機器上**

已實測確認：本機 MySQL 9.5 有在跑（port 3306），但**資料目錄裡只有系統內建的
五個資料庫，沒有 `sonnap`**，也沒有任何 `sleep_records` 檔案；
17 個 binlog 全是 198–221 bytes（只有啟動/關閉事件）→ **這個 server 從沒被寫過東西**。
→ 資料在影像組的電腦上，只能跟他們要。不必再花時間找。

✅ 但那條「請影像組跑 `SHOW CREATE TABLE sleep_records`」的待辦**可以劃掉了**——
他們 08-26 推上來的 `tapo/sleep_records.sql` 第 38 行有 `created_at`，
先前記錄的「建表後 `sleep_anylzer.py` 會 `Unknown column`」在新檔裡不存在。

### 工作位置（重要）

**唯一該用的位置：`C:\Users\user\Projects\Sonnap-Project`**（真正的 git clone）

桌面上那份 `OneDrive\桌面\Sonnap-Project-main\Sonnap-舊工作副本_勿用\` 是最初下載的 zip，
**沒有版控、已停用**。它裡面只剩三樣東西沒被搬過來，都是刻意的：`garmin/.env`（帳密）、
除錯 log、`garmin/data/_backup_20260811/`（重抓資料前的保險）。

> 為什麼不放 OneDrive：OneDrive 同步 `.git` 資料夾會弄壞 repo。

### git 狀態（2026-08-26 更新）

✅ **這一輪的工作已經全部進 `main`** —— PR #11 於 2026-08-26 由使用者合併
（`origin/main` = `e382b83`）。`db.py`、`main.py`、`behavior/`、`wearable/`、
`tests/`、`migrate_garmin_to_db.py`、`PROPOSAL_GAP.md`、51 晚的資料全都在裡面。

`origin/main` 也兩次合併進本分支：08-25 那次是影像組 8/17 的工作，
08-26 那次是他們當天推的三個 commit（只動 `tapo/`，零衝突）。

⚠️ **遠端有兩個分支該清掉，但先問過再刪**：

| 分支 | 狀態 |
|---|---|
| `feature/behavior-loop-feat(backend)-多使用者-API、…` | PR #11 用的那個。名字裡有 commit message，**已完全合併進 main** |
| `feature/behavior-loop` | 合併後被刪過，又被我的第二次推送建回來 |

> ### ⚠️ 遠端狀態要問 git，不要問文件（這一輪踩了兩次）
>
> 1. 文件上寫「尚未 push」，但這個分支 08-25 就推過一次（停在 `796b8c1`），
>    我照文件講，對使用者講錯了。
> 2. 我寫「PR 尚未開」的**同時**，使用者正在網頁上合併 PR #11——
>    那份筆記一 commit 就是過期的。
>
> → 動手前先跑 **`git ls-remote --heads origin`** 與
>   **`git fetch && git log --oneline origin/main -1`**，不要相信任何文件上的敘述
>   （包括這一段）。
>
> ⚠️ 更早的一版還寫過「4 個 commit 直接打在 main 上、尚未 push」，那也早就過期了。

### ⚠️ 環境（2026-08-26 補記）

專案有 `.venv`，但**相依套件從來沒有裝過**——所以在此之前
`main.py` 其實跑不起來（`ModuleNotFoundError: fastapi`）。

已裝：`fastapi`、`uvicorn`、`httpx`（測試用）、`garminconnect`（`--fetch` 需要）、
`mysql-connector-python`（查 TAPO 時裝的）。
仍未裝：`pandas`、`matplotlib`、`seaborn`、`opencv-python`、`numpy`
——只有 `itegration/` 與 `tapo/` 那幾支需要，要用時再
`pip install -r requirements.txt`。

⚠️ **`garminconnect` 沒裝不影響 pipeline 的後四步**——只有 `--fetch`（重抓資料）
那一步需要它，其餘四步讀既有的 `garmin_standard_data.json`。

### ⚠️ 重抓資料是**覆寫**不是增量（2026-08-26 補記）

`garmin_connect_fetch.py:778` 用 `open(args.output, "w")`，
所以 **`--days N` 會把整個 `garmin_standard_data.json` 換掉**，只留最近 N 天。
`--days 7` 這種用法會**弄丟前面所有歷史**，而且不會有任何警告。

正確用法是給完整區間：

```bash
python garmin/garmin_connect_fetch.py --start-date 2026-05-28 --end-date <今天>
python garmin/run_pipeline.py          # 再跑後四步
```

抓之前先備份 `garmin_standard_data.json` 與 `garmin_sleep_quality_final.csv`，
抓完**一定要比對歷史夜晚的分數有沒有被改寫**（2026-08-26 那次比對過，
46 晚逐欄未變，只是往後長了 5 晚——那是正確結果）。

分支盤點（2026-08-25 實測）：

| 遠端分支 | 作者 | 領先 main | 最後更新 | 狀態 |
|---|---|---|---|---|
| `origin/flutter` | Jeremy | **0** | 2026-07-10 | 已全數合併，可刪 |
| `origin/feature/garmin-sleep-scoring` | 我 | **0** | 2026-08-11 | 已合併，可刪 |
| `origin/feature/project-setup` | 我 | **0** | 2026-08-12 | 已合併，可刪 |
| `origin/feature/opencv-motion-garmin` | 影像組 | **12** | 2026-06-11 | ⚠️ 見下方 |

⚠️ **`feature/opencv-motion-garmin` 有 12 個 commit 從沒合併，但整條不能合。**
另外 11 個 commit 會刪掉 `app`、`backend`、`docs`，還會把 2026-08-11 刪掉的
`garmin_importer.py` 救回來。唯一有價值的是 `sleep_records.sql`——那正是
`PROJECT_STATUS.md` 3.5 說「不存在」的 TAPO 建表 SQL。

**但它也不完整、不該直接撿來用**：`tapo_detector.py:499` 寫入的欄位與它逐欄相同，
但 `sleep_anylzer.py:50` 與 `import mysql.py:57` 都 SELECT 了 `created_at`，
而那份 `CREATE TABLE` **沒有這一欄**。拿它建表，寫得進去但分析程式會
`Unknown column`。→ 應請影像組跑一次 `SHOW CREATE TABLE sleep_records` 給出現行結構。

那份 dump 順帶用**我們自己的資料**驗證了三件已知的事（可直接引用進報告）：
5 筆紀錄的 `report_date` 全是 dump 產生當天（證實 3.4「report_date 不可信」）；
其中 4 筆分數**全是 50**，但事件數從 183 到 1225、翻身從 8 到 344——
**四個完全不同的夜晚彼此無法區分**，正是 8.3 紅線 3「分數不得有人為地板」；
timeline 第一筆是 16:48，且 `motion_intensity: 2073600` = 1920×1080，整畫面誤判。

已合併的歷史：PR #9（Garmin 評分）、PR #10（資料交接層 + AI + Flutter 資料層）。
`main` 也含隊友的 Flutter app（`app/`）與 TAPO（`tapo/`）。

> 💡 `gh` CLI 已於 2026-08-25 安裝（v2.98.0），但**尚未 `gh auth login`**，
> 所以還看不到 PR 列表。要用的話請先在終端機登入一次。

### 已完成

- Garmin pipeline 5 步驟全通，`python garmin/run_pipeline.py` 約 3 秒跑完
- 46 晚實測資料（2026-05-28 ~ 08-10），每晚 0–100 分 + Good/Normal/Poor/Bad
- Tier1/2 基礎分數（文獻加權）+ Tier3 個人化修正值（±12）+ SRI（呈現不計分）
- 完整文獻依據：`Research-Background/Garmin手錶分數.md`

---

## 🚧 設計紅線與待補迴圈（2026-08-17 定．動評分或遊戲化之前必讀）

來源：拿 GitHub 上同類型開源專案 **NightBloom**（`shev0k/sleep_tracker`，MIT，
4 stars／34 commits／停更於 2024-11）逐行對照的結論。
**完整證據與行號在 [PROJECT_STATUS.md](PROJECT_STATUS.md) 第八節**，這裡只留規則。

分寸先講清楚：對方是小型學生專案，**「它有問題」不能反過來證明我們是對的**。
留這一節是因為它的每個問題剛好對應到我們刻意做過的取捨，可以當成回歸測試用的反例。

### ❌ 五條紅線（要動評分或加遊戲化功能時逐條檢查）

| # | 紅線 | 對方踩到的實例 |
|---|---|---|
| 1 | **同一個訊號不得以多個名義重複計分** | 它的 `movementScore` / `remSleepScore` / `lightSleepScore` 全是加速度 magnitude 的不同切法 → **70% 的分數只反映單一訊號** |
| 2 | **每一項計分都必須有文獻門檻** | 它的 `1.5 / 2.5 / 60 / 20 / 50` 五個門檻零引用，且未扣重力（靜止時 magnitude 本來就是 1.0 g） |
| 3 | **分數不得有人為地板** | 它所有子分數只有 100/75/50 三檔，總分被壓在 [50,100]，糟糕的夜晚彼此無法區分 |
| 4 | **⚠️ 遊戲化層只讀，不得回寫評分層** | 見下方展開 |
| 5 | **獎勵必須與「品質」耦合，不能只與「有資料」耦合** | 見下方展開 |

**紅線 4 展開**：挑戰、獎勵、寵物成長、貨幣等模組**只能讀**
`final_score` / `final_quality` / `sri`，**不得參與**
`garmin/evaluate_sleep_quality.py` 與 `garmin/apply_recovery_modifier.py` 的任何計算。
最容易破功的說法是「為了讓挑戰有感，完成挑戰的夜晚加 5 分」——**那一步就毀了
「每項計分都有引文」這個本專案最難複製的資產**。要獎勵就在遊戲層獎勵。

**紅線 5 展開（我們還沒踩，但下一步最可能踩）**：
對方的遊戲貨幣是把所有夜晚的分數無條件累加，配合地板 50 →
**睡得再差也照領 50 點**，成長速度只跟「有沒有睡」有關。它的遊戲化在激勵層面是失效的。
我們目前沒問題（`pet_mood` 直接由 `final_quality` 決定，Bad 的夜晚真的會顯示
`tired`/`anxious`）。但 `PROJECT_STATUS.md` 第五節列的「任務系統／寵物成長／
Closet／Rewards」全在這個風險區——**加任何獎勵機制時，第一個要驗的就是
「差的夜晚拿到的回饋明顯少於好的夜晚」**。

### ✅ 該補的：行為介入迴圈（我們缺一整層）

兩邊的缺口剛好互補：**它是「假量測 + 真迴圈」，我們是「真量測 + 無迴圈」。**
目前使用者看完分數與夢境日記就結束了，**沒有可以「做」的事**。

要補的話，**標的用 SRI**。這不是抄它，是從我們自己的資料長出來的：

- SRI 已經在 `apply_recovery_modifier.py` 算好並輸出，但**刻意不計分、只呈現**
  → 目前實質上是一筆沒人使用的死資料
- 挑戰標的必須是**行為**（幾點上床），不能是**生理結果**（深睡幾分鐘）。
  使用者控制得了前者，控制不了後者
- ⚠️ **拿 SRI 當挑戰目標不違反「不計分」的決定**——當初不計分的理由是
  「不同計算方法算出的 SRI 差異大到不能對照外部常模」（Czeisler 2026），
  而「這 7 天你的上床時間有沒有收斂」是**個人內比較**，不受該問題影響。
  但**它仍然不准進 `total_modifier`**，兩件事不要混淆
- 有 46 晚實測資料，可先驗證挑戰難度再上線

建議形式：「連續 7 天上床時間落在 ±30 分鐘內」→ 寵物解鎖某個狀態。

## ⚠️ 資料語意：最容易誤讀的欄位（動 Garmin 資料前必讀）

### `garmin_sleep_summary.csv` 現行欄位

`date`、`sleep_start_time`、`wake_time`、`total_sleep_minutes`、
`deep/light/rem/awake_minutes`、**`movement_sample_minutes`**（原 `movement_count`）、
`movement_level_mean/max`、`movement_active_minutes`、`steps_total`、
`avg/min/max_heart_rate`、`avg_stress_score`（**不再計分**）、
**`presleep_stress_score`**（Tier3 用這個）、`resting_heart_rate`、
`awake_count`、`sleep_segment_count`。

### 四個名字會騙人的欄位

| 欄位 | 它**不是**什麼 | 它**是**什麼 |
|---|---|---|
| `movement_sample_minutes` | 不是動作量／翻身次數 | 取樣分鐘數（每分鐘一筆，99.98% 間隔正好 60 秒）。與睡眠時長 r=+0.929、與 WASO r=−0.138 |
| `avg_stress_score` | 不是睡眠期間的壓力 | 該**日曆日白天**的平均（11439 筆讀數中僅 8.6% 落在睡眠期間）。**已不計分**，保留只因 `itegration/if_integrate.py:250` 還在讀 |
| `presleep_stress_score` | — | 「上一次起床 → 這一次入睡」整段清醒時段。Tier3 壓力修正值用這個 |
| `sleep_efficiency` | 不是臨床睡眠效率 | 分母是（起床 − 入睡），**不含入睡潛伏期**。報告中須誠實標註 |

### 三條計分紀律

1. **`movement_level_mean/max`、`movement_active_minutes` 永不進評分。**
   `MOVEMENT_ACTIVE_THRESHOLD = 1.0` 是看資料分布訂的、沒有文獻依據，
   而本專案每一項計分都有引文，不破例。
2. **SRI 照算照輸出，但不進 `total_modifier`。**
   理由是 Czeisler 2026 證實不同計算方法算出的 SRI 差異大到不能對照外部常模。
   ⚠️ 但**拿 SRI 當挑戰目標不違反這個決定**——那是個人內比較，不受該問題影響。
3. **`clinical_efficiency`（Health Connect 算得出）只供報告，不計分。**
   Garmin 的效率分母是「起床 − 入睡」，臨床定義是「起床 − 上床」，後者一定較低。
   兩種數字餵進同一組門檻（`EFFICIENCY_GOOD = 85`），有穿戴裝置的同學會被
   **系統性地扣分**，而那個差異來自裝置不是來自睡眠。

### 兩個 pipeline 層級的坑

**① 重抓資料是覆寫不是增量。**
`garmin_connect_fetch.py:778` 用 `open(args.output, "w")`，
所以 `--days N` 會把整個 `garmin_standard_data.json` 換掉、只留最近 N 天，
**弄丟前面所有歷史且沒有任何警告**。正確用法是給完整區間：

```bash
python garmin/garmin_connect_fetch.py --start-date 2026-05-28 --end-date <今天>
python garmin/run_pipeline.py          # 再跑後四步
```

抓之前先備份 `garmin_standard_data.json` 與 `garmin_sleep_quality_final.csv`，
抓完**一定要比對歷史夜晚的分數有沒有被改寫**。

**② `summary` 與 `features` 的有效性標準不同。**
`extract_sleep_features.py` 會濾掉 06-02 那筆異常列（`sleep_start == wake == 00:00:00`），
但 `apply_recovery_modifier.py` 讀的是 `summary` **而不是**過濾後的 features，
假值會直接汙染 baseline。→ **任何讀 `summary` 的新程式都得自己做有效性檢查**，
不要倚賴下游過濾。

---

## 🗺️ 評分路徑盤點（有幾個「分數」、哪個是活的）

| 分數 | 位置 | 狀態 |
|---|---|---|
| `final_score` | `garmin/apply_recovery_modifier.py` | ✅ 文獻加權，主線 |
| `sleep_quality_score` | `tapo/tapo_detector.py:487` | ✅ 扣分制，影像組的 |
| `integrated_score` | `itegration/if_integrate.py:214` | ✅ `0.6×garmin + 0.4×tapo`，**權重無依據** |
| `calculate_camera_score()` | `itegration/if_integrate.py` | ❌ **死碼**（SQL 早就寫了 `sleep_quality_score as camera_score`） |
| `calculate_garmin_score_from_features()` | 同上 | ❌ **死碼** |

⚠️ **`PROJECT_STATUS.md` 3.10 主張根本不該做加權平均**：攝影機的價值是提供
手錶量不到的「上床時刻」（→ 臥床時間 → 解掉效率限制 + 解鎖入睡潛伏期），
那條路一個新參數都不用訂；而加權平均要 justify 60/40，還是拿有引文的分數
去平均沒引文的分數。

> ⚠️ 那兩段死碼我連續兩次寫錯、兩次同一個原因——見末尾「方法論」第 4 點。
> （實際行號：`if_integrate.py:199-211`，`camera_score` 在 `:130` 的 SQL 就已經有值。）

---

## 🤖 兩個模組的既定決策（不要改回去）

### AI 夢境（`ai/`，`PROMPT_VERSION` = v3）

| 決策 | 理由 |
|---|---|
| 用 Claude API + 標準庫 `urllib.request`，**不裝 SDK** | 這功能不讓 `requirements.txt` 多任何一行 |
| 「日記中間幾頁空白」意象**只在 `rem_unmeasured` 為真時**才放進 system prompt | 那不是修辭，是把「手錶沒測到 REM」誠實寫進敘事的機制。用在有資料的夜晚等於對使用者謊稱 |
| few-shot 依當晚條件拆兩版 | 原本範例二同時是「Bad」又是「REM 未測得」，模型在 Bad 的夜晚就整段照抄 |
| `validate()` 保留 `MISSING_RECORD_MOTIFS` 關鍵字擋 | **這層真的救到了**：前三層修好後模型第 1 次仍寫出「沒看清」，重試才過 |
| `SIMPLIFIED_CHARS` **刻意不含 于／后／里** | 正體中文本來就會用（皇后、公里），誤判的代價是整晚退回規則式文字 |
| 國字數字規則**必須有「點」才擋** | 「十分安穩」是「非常安穩」不是「十分鐘」。出問題的 4 晚全是小數 |
| `recent_motifs()` 的呼叫**必須放在主迴圈內** | `entries` 每跑完一晚才更新，放外面等於這個功能沒作用 |
| `ADVICE_LANG` **沒有實作** | 輸出固定正體中文（prompt 本身就是中文寫的）。改那個變數不會換語言 |

> ⚠️ **驗證規則寫寬很省事，但誤判的代價是整晚退回規則式文字。**
> 這類錯誤已經踩過三次（「沒看清」無條件擋、`SIMPLIFIED_CHARS` 的于／后／里、
> 國字數字）。加新規則前先問：**它會不會誤傷正常說法？**

### 行為層 × 評分層怎麼合併（`main.py` 的 `resolve_mood()`）

**有行為資料時行為優先，生理只做 `anxious` 覆寫。**
理由同「挑戰標的必須是行為不是生理結果」——使用者準時放下手機卻因感冒睡不好
而看到難過的寵物，就是**因為自己控制不了的事被懲罰**，回饋迴圈一斷機制就失效。

⚠️ **沒有行為資料時完全走舊路徑**（直接 import `build_app_payload.map_pet_mood`，
不重寫）。已實測：研究者那 46 晚走新 API 與走舊 asset 給出**逐字相同**的心情與理由。

⚠️ **挑戰門檻是 n=1 校準出來的暫定值**：`作息收斂` ±60 分鐘（±30 的達成率是 0/36）、
`連續 3 晚`（校準時要先把「缺資料就中斷」的斷點拿掉，那是手錶配戴率造成的假象，
Tier A 沒有這個問題）。`target_bedtime` **不能給所有人同一個預設值**——
同一批資料 23:30 → 2%、02:30 → 43%、03:00 → 59%。

---

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

## 現有程式碼結構（2026-08-26 核對過）

**後端（根目錄）**

- `main.py` — FastAPI。12 個端點：`POST /users /nightly /wearable`、
  `PATCH`+`DELETE /users/{id}`、`GET /home /insights /challenges /get-sleep-data /health`。
  ⚠️ `/get-sleep-data` **已接真實資料**（讀打包的 asset 檔），檔案不存在時回 **503
  而不 fallback 回假資料**——這是刻意的，見該函式的 docstring。
- `db.py` — SQLite（標準庫 `sqlite3`），七張表，暱稱制免註冊。
  ⚠️ 有 `COLUMN_MIGRATIONS` 欄位遷移機制：`CREATE TABLE IF NOT EXISTS` 對**已存在**
  的表什麼都不做、連新加的欄位也不補，只改 SCHEMA 會讓已跑過 `--init` 的開發機
  `no such column`。加欄位時兩邊都要改。
- `build_app_payload.py` — `garmin/data/*.json` → `app/assets/data/app_payload.json`
- `migrate_garmin_to_db.py` — 46 晚 → `wearable_nightly`，可重複執行

**模組**

| 目錄 | 內容 |
|---|---|
| `garmin/` | 5 步 pipeline（見下節）。⚠️ 只留程式碼，生成物全在 `garmin/data/` |
| `behavior/` | Tier A 行為層：`challenges.py`、`pet_state.py`、`adherence.py` |
| `wearable/` | `healthconnect_adapter.py`：Health Connect → **既有評分器**（一個門檻都沒改） |
| `ai/` | 夢境日記（Claude API）。⚠️ `ai/.env` 有金鑰，已被 gitignore |
| `tapo/` | 影像組負責。⚠️ 檔名是 `tapo_detector.py`（不是 `motion_detector.py`） |
| `itegration/` | `if_integrate.py`（Garmin×TAPO 整合）。⚠️ `itegration` 是拼字錯誤，刻意不改名 |
| `tests/` | `test_api.py`、`test_healthconnect_adapter.py`，**獨立腳本不需 pytest** |
| `app/` | Flutter（Jeremy 負責）。⚠️ **動之前先問他** |
| `Research-Background/` | 文獻依據，正式來源是 `Garmin手錶分數.md` |
| `docs` | 43 bytes 的佔位**檔案**（不是資料夾），待團隊決定 |

**環境**：`.venv` 已裝 `fastapi`、`uvicorn`、`httpx`、`garminconnect`、
`mysql-connector-python`。**未裝** `pandas`、`matplotlib`、`seaborn`、`opencv-python`、
`numpy`——只有 `itegration/` 與 `tapo/` 需要，要用時再 `pip install -r requirements.txt`。
⚠️ `garminconnect` 只有 `--fetch` 那一步需要，pipeline 後四步不受影響。

**驗收指令**：`python tests/test_api.py`、`python tests/test_healthconnect_adapter.py`
（`test_api.py` 全程用暫存資料庫，不碰 `data/sonnap.db`）。

**資料通道走 bundled asset，不走 HTTP**（已定案）：

```
garmin/data/*.json → build_app_payload.py → app/assets/data/app_payload.json
                                              ├─→ Flutter rootBundle 讀
                                              └─→ main.py 對外服務同一個檔
```

只產一份檔的理由：兩份就會有「App 顯示的跟 API 回傳的對不上」這種最難查的 bug。
之後要接 HTTP 只要實作 `sleep_repository.dart` 裡預留的 `ApiSleepRepository`。

**還沒接的**：`report_screen.dart`（Insights 頁，資料寫死在 `CustomPainter` 內部）
與 `assistant_screen.dart` 的問答。`payload` 已帶 `history`（最近 30 晚），
接 Insights 時不用改後端。

---

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

### 尚未解決的問題（2026-08-26 核對過）

1. **缺少排程與增量抓取。**
   每次要手動執行、指定區間，沒有排程機制（Windows 工作排程器/cron），
   也沒有記錄「上次抓到哪裡」，容易重複抓或漏抓。
   屬社群套件 PoC，Garmin 介面異動時可能失效。

2. **`ambient_noise_db` Garmin 手錶沒有這個數據。**
   需要跟 TAPO 那邊確認這欄位由誰負責提供，並在 data contract 文件上寫清楚。
   ⚠️ TAPO 現在的「分貝數」是 `np.random` 產生的**假資料**，不是真的收音。
   音訊門檻 bug（`PROJECT_STATUS.md` 3.7）**已交給影像組修**——
   根因是單位錯亂不是靈敏度，`db` 天花板是 90.3，驗收要跑真的有聲音的錄音。

3. **中強度活動分鐘數**（需接 `get_intensity_minutes`）——
   但在配戴習慣改變前，接了也一樣拿不到有效的白天資料，優先度低。

4. **TAPO 的 `sonnap` 資料庫不在這台機器上。**
   已實測：本機 MySQL 9.5 有在跑，但資料目錄只有系統內建的五個資料庫，
   17 個 binlog 全是 198–221 bytes（只有啟動/關閉事件）→ **這個 server 從沒被寫過東西**。
   資料在影像組的電腦上，只能跟他們要。**不必再花時間找。**

### 已修正的歷史問題（保留紀錄，避免重複踩）

- ✅ 跨午夜夜晚被切成兩列 → 改用「起床日」分組（對齊 Garmin 的 `calendarDate`）
- ✅ 睡眠階段誤用「段數」→ 改用 `*_duration_sec` 的分鐘數，與 App 一致
- ✅ 步數多算 → 改用官方 `get_daily_steps`，不再加總 96 個 15 分鐘區間
- ✅ `_parse_sleep_data` 縮排錯誤造成 `UnboundLocalError`（沒睡眠資料的日子會觸發）
- ✅ 06-02 異常列（入睡=起床=00:00:00）→ `extract_sleep_features.py` 會濾掉
- ✅ `build_project_payload()` 沒按「一晚」分組（把 13 天算成一晚）
  → 2026-08-11 已連同 `garmin_importer.py` 一併刪除（該函式的產出從來沒有任何程式讀取）

---

## 開發規範

- 請勿直接 push 到 main，從 main 切新分支：`git checkout -b feature/功能名稱`。
- Commit message 保持簡潔（如：`feat: 新增睡眠數據欄位`）。
- Bug 或功能討論請開 GitHub Issue，避免資訊散落在通訊軟體。
- Python 3.13，輸出檔案一律 UTF-8，時間格式一律 ISO8601（+08:00）。
- 優先用標準庫，非必要不用 pandas。
- 保持現有專案結構，不要破壞現有 Garmin parser。

⚠️ **在 Windows Git Bash（cp1252）下，Python 印中文會 `UnicodeEncodeError`**，
PowerShell 則沒事——同一台機器兩種結果。新腳本要印中文請加
`sys.stdout.reconfigure(encoding='utf-8')`，跑子行程時設 `PYTHONIOENCODING=utf-8`
（設環境變數而非逐支腳本改，這樣新增步驟時不會忘記）。

⚠️ **`.gitignore` 寫 `data/` 會遞迴匹配 `garmin/data/` 與 `ai/data/`**。
已追蹤的檔案不受影響，所以不會立刻壞掉，但**新增的檔案會被靜默擋掉、
沒有任何錯誤訊息**。要寫 `/data/`。改完用 `git check-ignore -v <路徑>` 實測確認。

## 📋 方法論（踩過才寫下來的）

1. **評估外部專案／函式庫，先看相依套件清單與實際呼叫路徑，再看 README。**
   NightBloom 的 README 寫「整合加速度計、陀螺儀、Fitbit、Apple Watch」，
   但 `grep -ri "accelerom\|sensor\|fitbit\|health" lib/` **零結果**、
   `pubspec.yaml` 沒有任何感測套件、「睡眠資料」頁的時數是寫死字串。
   **它的睡眠量測整個是假的**，README 描述的是路線圖不是現況。
   → 我們自己也犯過同型的錯：`ADVICE_LANG` 曾經寫在文件上卻沒有實作。
2. **遠端狀態問 git，不要問文件**——連問這份檔案都不行。
   動手前先跑 `git ls-remote --heads origin` 與
   `git fetch && git log --oneline origin/main -1`。
3. **宣稱「跑過了」之前，先確認每一步都真的跑了。**
   一律用 `python garmin/run_pipeline.py`，不要手動一步一步跑——
   漏跑中間步驟**不會報錯**，後面的步驟會安靜地用上次留下的舊檔案算出結果。
4. **判斷「這段程式會不會執行」要往上看呼叫路徑**，不能看到
   `df['x'] = self.calculate_x(df)` 就假設它會跑，要往上確認那個
   `if 'x' in df.columns` 是否已經成立。（連續兩次把死碼當成現況寫進文件。）
5. **驗證規則寫寬很省事，但誤判的代價往往比漏判大。**
   加新規則前先問「它會不會誤傷正常說法」——AI 夢境那三次全是這個原因。
6. **引用文獻一律核對第一作者。**已經誤植過兩次（K 節 Troxel/Iskander、
   RIRI 論文的 Czeisler ME 被寫成 Mason et al.）。
