# Sonnap 專案背景（給 Claude Code）

## 專案是什麼

Sonnap 是結合「睡眠監測」與「AI 寵物陪伴」的 App。攝影機/穿戴裝置偵測使用者睡眠狀態，
轉換成虛擬寵物的心情與活動，並用 AI（Gemini）生成「夢境日記」。詳見 [README.md](README.md)。

團隊分工：PM/系統整合、UI/UX（Figma）、App 前端、影像工程（OpenCV）、AI/數據處理，共 5 人。

---

## 🔖 交接區：目前狀態與下一步（2026-08-25 更新．新對話請先讀這段）

> **最新一輪的成果與待辦在「📌 2026-08-25 這一輪」那一節**，本節底下的
> git 狀態已更新，但「下一步」那張表講的是 2026-08-12 完成的 Part A–E，
> 屬於歷史記錄。目前真正的路線圖是
> `C:\Users\user\.claude\plans\abundant-nibbling-sutton.md`
> （D2 使用者實測 → 多使用者架構 → 行為介入迴圈）。

這段是「現在在哪、接下來做什麼」。底下的其他章節是**累積的歷史記錄**，
裡面有些標題（例如「Next Development Goal」）寫的是當時的下一步，**現在已經過期**，
不要照著做。以這段為準。

### 工作位置（重要）

**唯一該用的位置：`C:\Users\user\Projects\Sonnap-Project`**（真正的 git clone）

桌面上那份 `OneDrive\桌面\Sonnap-Project-main\Sonnap-舊工作副本_勿用\` 是最初下載的 zip，
**沒有版控、已停用**。它裡面只剩三樣東西沒被搬過來，都是刻意的：`garmin/.env`（帳密）、
除錯 log、`garmin/data/_backup_20260811/`（重抓資料前的保險）。

> 為什麼不放 OneDrive：OneDrive 同步 `.git` 資料夾會弄壞 repo。

### git 狀態（2026-08-25 更新）

**目前在 `feature/behavior-loop` 分支上**（從 `main` 的 `ab7e1e7` 切出）。

> ⚠️ 前一版這裡寫的「4 個 commit 直接打在 main 上、尚未 push」**已經過期**——
> 那四個 commit 後來已推上去，`main` 與 `origin/main` 同步中。不必再補救。

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

**但它也不完整、不該直接撿來用**：`tapo_detector.py:200` 寫入的欄位與它逐欄相同，
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

### 下一步（完整計劃在 `C:\Users\user\.claude\plans\encapsulated-squishing-rivest.md`）

計劃檔存在全域 `~/.claude/plans/`，**換工作目錄後仍讀得到**，細節請直接讀它。摘要：

| | 內容 | 狀態 |
|---|---|---|
| Part 0 | 推上 GitHub | ✅ 已完成（PR #9 已合併） |
| Part A | 基礎建設：`requirements.txt`、修 `.gitignore`、`.env.example` | ✅ 已完成（2026-08-12） |
| Part B | **AI 睡眠顧問**，獨立 `ai/` 資料夾 | ✅ 已完成（2026-08-12，含真實 API 呼叫） |
| Part C | `PROJECT_STATUS.md` 現況報告（給團隊/教授） | ✅ 已完成（2026-08-12） |
| Part D | **資料交接層**：`build_app_payload.py` + `main.py` 接真資料 | ✅ 已完成（2026-08-12） |
| Part E | **Flutter 資料層**：4 個 model + `services/` + HomeScreen | ✅ 已完成（2026-08-12） |

⚠️ **要動評分邏輯或新增遊戲化功能（挑戰／獎勵／寵物成長／貨幣）之前，
先讀下一節「🚧 設計紅線與待補迴圈」**——那五條紅線是拿外部同類專案對照後定的，
其中第 4、5 條防的是我們還沒踩但下一步最可能踩的坑。

> 完整計劃在 `C:\Users\user\.claude\plans\plan-app-graceful-pie.md`。
> **那份檔案已於 2026-08-15 整個改寫成「產品化路線圖」**，不再是 TAPO 接入計劃——
> 因為使用者確認了目標是「別人能實際裝來用的產品，時間一學期以上」，
> 在那個標準下重新盤點的結論是：**技術難的部分幾乎都做完了，缺的是產品的部分**。
> 兩個最根本的缺口：**整個系統假設世界上只有一個使用者**、**資料不會自己更新**。

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

### 📋 方法論：評估外部專案先讀碼，不要採信 README

對方 README 寫「整合加速度計、陀螺儀、Fitbit、Apple Watch」，
但 `grep -ri "accelerom\|sensor\|fitbit\|health" lib/` **零結果**、
`pubspec.yaml` 沒有任何感測套件、「睡眠資料」頁的時數是寫死字串。
**它的睡眠量測整個是假的**，README 描述的是路線圖不是現況。

→ 日後評估任何外部專案／函式庫，**先看相依套件清單與實際呼叫路徑，再看 README**。
（我們自己也犯過同型的錯：`ADVICE_LANG` 曾經寫在文件上卻沒有實作，後來把
`.env.example` 改成誠實說明。）

---

## 📌 2026-08-25 這一輪（量測時窗修正 + 產品化地基）

分支 `feature/behavior-loop`，4 個 commit。完整計劃在
`C:\Users\user\.claude\plans\abundant-nibbling-sutton.md`。

### ⚠️ 壓力與活動量的量測時窗**都差了一天**（重要，已修）

根因是同一件事：**`garmin_sleep_summary.csv` 的每一列混了兩個時段的資料。**

```
列 D 的「睡眠」＝ D-1 晚上上床、D 早上起床   （歸起床日，對齊 Garmin calendarDate）
列 D 的「步數/壓力」＝ D 白天               （時間戳不在睡眠區間內，照自己的日曆日歸類）
                                            ↑ 發生在那一覺「之後」
```

分流的那一行是 `analyze_garmin_sleep.py:185`：
`date = session_date_for(ts_dt, sessions) or get_date(timestamp)`。

**壓力（±4，Tier3 額度最大的一項）**——實測 11439 筆讀數裡**只有 8.6% 落在
睡眠期間，91.4% 是白天**，而 G 節寫的構念是「睡眠期間的生理壓力負荷」。
更麻煩的是本資料集平均就寢 02:34，所以列 D 的傍晚讀數（19:00–23:00，配戴高峰）
其實屬於**下一晚**的睡前時段——單一欄位橫跨了兩個不同夜晚。

已新增 `presleep_stress_score`（`build_awake_windows()`），定義是
**「上一次起床 → 這一次入睡」的整個清醒時段**。⚠️ **窗格兩端都由資料自己界定，
不含任何人為選定的時間長度**——這是刻意的：本專案每個門檻都要有依據，
而最好的做法是根本不需要門檻。（一度考慮過「睡前 3 小時」，但那個 3 需要引文，
而且量到的其實是 pre-sleep arousal 這個**中介變項**，不是 G 節要的「當日壓力」。）

**活動量**——改讀前一個日曆日的 `steps_total`。H 節引的 Kredlow (2015) 檢驗的是
「日間活動 → 其後睡眠」的前瞻方向。此項已因 baseline < 1000 步而停用，
**數值零影響**，只有 06-11 的 `modifier_note` 由「資料無效」改成「冷啟動」
（序列位移一天，滿 14 筆的時間點也晚一晚，是正確結果不是副作用）。

**實測影響（46 晚）：**

| | 修正前 | 修正後 |
|---|---|---|
| 壓力修正生效 | 34/46 晚 | **14/46 晚** |
| 飽和率 | 24% | **14%** |
| 改變分級 | — | 3 晚 |
| **Tier1/2 基礎分數** | — | **46 晚完全未變** |

生效夜數下降是因為需要**連續兩晚都有記錄**——與 SRI 受同一結構限制，
兩者可用夜數同為 28。這不是永久限制：**配戴率改善它就自己補起來**，
而舊定義的構念錯誤再收集 200 晚也還是錯的。

單晚差異可達整個 ±4：**2026-07-12**（02:39 入睡、15:29 起床）舊值 25.8
（基準 5.5）扣滿 −4.0，但那 25.8 **整段發生在起床之後**；新值 3.3（基準 5.4），
入睡前的清醒時段其實**低於**個人常態。同一批原始讀數，差了 7.8 倍。

⚠️ **`avg_stress_score` 保留未刪**，但不再參與計分。理由不是「歷史對照」
（那是錯的說法），是 **`itegration/if_integrate.py:250` 仍在讀它**。

### ⚠️ 順手抓到：06-02 那筆異常列會汙染 baseline

第一次跑出來壓力生效 15/46 而不是預測的 14/46。差一晚查下去是 **2026-06-02**
（`sleep_start == wake == 00:00:00`，本檔案早已記錄的異常列）。

**關鍵：`extract_sleep_features.py` 會濾掉它，但 `apply_recovery_modifier`
讀的是 `summary` 而不是過濾後的 features**，所以假值會直接進 `stress_history`
汙染 baseline，讓它提早一晚湊滿 14 筆。已在 `build_awake_windows` 自己擋掉
退化區間（兩端都檢查），**不倚賴下游過濾**。

→ 教訓：`summary` 與 `features` 的有效性標準不同，任何讀 `summary` 的新程式
都得自己做有效性檢查。

### ⚠️ 評分路徑盤點：**我在這一輪連續寫錯兩次**，過程比結論更值得記

- 第一版：「兩套」——漏了 `if_integrate.py`
- 第二版：「第三套是 `calculate_garmin_score_from_features`，用 `stress > 20`」
  ——**那是死碼**
- 第三版：「`camera_score` 會從原始計數重算，取代 TAPO 自己的分數」
  ——**也是死碼**，SQL 早就寫了 `sleep_quality_score as camera_score`

**兩次錯誤同一個原因**：看到 `df['x'] = self.calculate_x(df)` 就假設它會執行，
沒往上看那個 `if 'x' in df.columns` 是否已經成立。**這正是 8.2 的紀律
（先讀實際呼叫路徑再下結論），而我對自己的專案連續兩次沒做到。**

正確答案（兩套 + 一個組合 + 兩段死碼）：

| 分數 | 狀態 |
|---|---|
| `final_score`（`garmin/`） | ✅ 文獻加權 |
| `sleep_quality_score`（`tapo/tapo_detector.py:326`） | ✅ 扣分制 |
| `integrated_score`（`if_integrate.py:214`） | ✅ `0.6×garmin + 0.4×tapo`，**權重無依據** |
| `calculate_camera_score()` / `calculate_garmin_score_from_features()` | ❌ 都是死碼 |

⚠️ **`itegration/if_integrate.py` 與 `tapo/if_integrate.py` 是逐位元組相同的
重複檔**（各 518 行）。`tapo/` 五支 detector 那個問題的重演，要決定留哪一份。

**「把 Garmin 和 TAPO 合起來」不需要從頭做——它已經寫好了。但
`PROJECT_STATUS.md` 3.10 主張根本不該做加權平均**：攝影機的價值是提供
手錶量不到的「上床時刻」（→ 臥床時間 → 解掉 6.3 的效率限制 + 解鎖入睡潛伏期），
那條路**一個新參數都不用訂**；而加權平均要 justify 60/40，還是拿有引文的分數
去平均沒引文的分數。整合路徑的五個問題見 3.8，臥床時間見 3.9。

### 產品化地基（`db.py` + `behavior/`）

D2 確認要「找同學裝 APK 實際用一到兩週」之後，**多使用者不再是待決策事項**。
`db.py` 用標準庫 `sqlite3`（`requirements.txt` 不多任何一行），七張表，
暱稱制免註冊。`behavior/` 是 Tier A 行為層。

⚠️ **架構紅線（8.7）在新架構下是結構上成立的，不需要靠紀律守住**：
遊戲化建立在 Tier A（手機行為）上，與評分器不在同一條路徑。驗收指令見
`behavior/__init__.py`——**要比對 import 行，不能單純搜關鍵字**，
否則會抓到規則自己的說明文字（實際踩過）。

### ⚠️ 兩個「安靜失效」的坑（都已修，都有實測）

1. **`.gitignore` 寫 `data/` 會遞迴匹配 `garmin/data/` 與 `ai/data/`**
   （那裡有 11 個檔已進版控）。已追蹤的檔案不受影響，所以不會立刻壞掉，
   但**新增的檔案會被靜默擋掉、沒有任何錯誤訊息**。要寫 `/data/`。
   已用 `git check-ignore -v` 實測確認。
2. **`db.py` 的 `update_user` 檢查順序反了**——當**所有**欄位都打錯時，
   `updates` 是空的而提早 `return False`，未知欄位的檢查永遠走不到。
   先擋未知、再處理空更新。

### `garmin_sleep_summary.csv` 的現行欄位（取代 2026-07-12 那份清單）

`date`、`sleep_start_time`、`wake_time`、`total_sleep_minutes`、
`deep/light/rem/awake_minutes`、**`movement_sample_minutes`**（原 `movement_count`）、
`movement_level_mean/max`、`movement_active_minutes`、`steps_total`、
`avg/min/max_heart_rate`、`avg_stress_score`（不再計分）、
**`presleep_stress_score`**（Tier3 用這個）、`resting_heart_rate`、
`awake_count`、`sleep_segment_count`。

---

## 📌 2026-08-15 這一輪（階段 0：不依賴任何人的清理）

路線圖的「階段 0」共四項，**全部完成**，四個 commit 見上方 git 狀態。

### ⚠️ `movement_count` 其實是取樣分鐘數，不是動作量（重要，已修）

使用者問「Garmin 的 movement 是動作幅度嗎」，查下去發現**原始資料是，但我們的
pipeline 把幅度丟掉了**。`analyze_garmin_sleep.py:191` 對每筆 `sleepMovement`
只做 `+= 1`，完全沒讀 `activityLevel` 的值。

**四條獨立證據（任一條不成立結論就垮，日後有人質疑可以直接重跑）：**

| # | 證據 | 結果 |
|---|---|---|
| 1 | 程式碼路徑 | fetch 把 `activityLevel` 存進 `value`，analyze 卻只 `+= 1`，從未讀取 |
| 2 | 取樣間隔 | 28444/28449 個相鄰間隔**正好 60 秒**（99.98%）→ 固定頻率取樣器 |
| 3 | 相關性 | 與睡眠時長 **r = +0.929**、與夜間清醒 WASO **r = −0.138** |
| 4 | 被丟掉的 value | 28497 筆連續值、17962 種相異值、範圍 0.00–7.64 → **那才是動作幅度** |

證據 3 是最強的反證：若真是翻身次數，該與清醒相關而非與時長相關。

**08-09 那晚示範了不修的後果**：舊 `movement_count` 是 489，四晚裡**最低**，
看起來像「動最少」。但真訊號說反話——平均幅度 1.64（其他三晚的兩倍）、
活躍分鐘佔 **72%**（其他約 22%）。那正是評級 Bad、`pet_mood: anxious` 的夜。
**舊指標不只是沒用，會給出相反的結論。**

已改名 `movement_sample_minutes` 並新增 `movement_level_mean/max`、
`movement_active_minutes`。⚠️ **這幾項永不進評分**——`MOVEMENT_ACTIVE_THRESHOLD = 1.0`
是看資料分布訂的、沒有文獻依據，本專案每一項計分都有引文，不破例。
回歸測試：`garmin_sleep_quality_final.csv` 修改前後**逐位元組相同**。

### ⚠️ 順手修掉一段會誤導人的過期註解

`extract_sleep_features.py` 原本寫著心率／壓力／步數是「V2 預留（目前未計分）」。
那寫於 Tier3 上線（2026-07-31）之前，**已經不正確**。要分兩層講：

- **features.csv 裡那幾欄**確實沒人讀（evaluate 只用 Tier1/2 的五項）
- **同樣的數值有進計分**，走的是 `summary.csv` → `apply_recovery_modifier.py`

讀的人會直接得出「心率不計分」的錯誤結論。已改寫。
（這是使用者自己抓到的，不是我發現的。）

### AI 夢境重複率 70% → 17%（`PROMPT_VERSION` 升到 v3）

原本 46 晚裡 32 晚不是「圖書館」就是「海床」。**根因不是模型偷懶**——
調色盤每個條件只給一組意象，又要求「只能用當晚事實支持的意象」，
事實相似的夜晚必然寫出幾乎一樣的夢。

修法三層：調色盤每類擴充成 3–6 組（並改用身體感受寫而非形容詞）、
新增 `recent_motifs()` 把最近 7 晚用過的意象寫進 prompt 要求避開、
數值一律阿拉伯數字。

⚠️ `recent_motifs()` 的呼叫**必須放在主迴圈內**重算，不能提到迴圈外先算好——
`entries` 每跑完一晚就更新，放裡面第 2 晚才看得到第 1 晚用掉的意象。
放外面的話一次補 46 晚時等於這個功能沒作用。

⚠️ **國字數字規則收窄過一次，這是第三次踩到同一類錯誤。**
第一版寫成「國字＋單位就擋」，結果「十分安穩」被誤判（那是「非常安穩」
不是「十分鐘」），「再試一次」「提早一小時」同理。回頭想真正的缺陷是什麼：
出問題的 4 晚**全是小數**（十點三、九十八點四），整數國字量詞從來不是問題。
收窄成「必須有『點』」之後誤判消失。
**教訓（已經第三次）：規則寫寬很省事，但誤判的代價是整晚退回規則式文字。**
前兩次分別是「沒看清」與 `SIMPLIFIED_CHARS` 的于／后／里。

### 這一輪的量測結果（46 晚實測）

| 指標 | 修正前 | 修正後 |
|---|---|---|
| 「圖書館 or 海床」 | 32 晚（70%） | **8 晚（17%）** |
| 用到的意象家族 | 5 種 | **16 種** |
| 國字數字 | 4 晚 | **0 晚** |
| 夢境出現數字 | 0 | 0 |
| fallback | — | **0 晚**（46/46 全 LLM） |
| Garmin 分數 | — | **與基準逐位元組相同** |

### ⚠️ 已知未解，留給下一輪（診斷已完成，修法很小）

**集中點搬家了**：「棉被與雪」現在佔 17 晚（37%）。文字彼此有差異
（各有不同的感官細節），但 06-01 與 06-06 仍然接近。

**根因是 `MOTIF_FAMILIES` 的粒度與調色盤不對稱：**

```
深睡類 6 個選項 → 只對應 2 個家族（海床沉降 / 棉被與雪）
REM 類 6 個選項 → 對應 5 個家族  ← 所以它沒有這個問題（圖書館只剩 8 晚）
```

深睡類兩個家族都用過後，`recent_motifs` 就沒有「沒用過的」可推薦，
而這個資料集 Good 夜晚有 31 晚，深睡充足的夜特別多。

**修法**：把 `MOTIF_FAMILIES` 拆成與調色盤選項一對一（約 6 行），再重跑 46 晚。

**Part B 已於 2026-08-12 完成真實呼叫**：`ai/.env` 的 `ANTHROPIC_API_KEY` 已填
（該檔已被 gitignore 擋住，`git check-ignore` 驗證過），模型設為 `claude-sonnet-5`。

⚠️ **第一次真實呼叫就抓到兩個 prompt 層的 bug，兩個都已修好（`PROMPT_VERSION` 升到 v2）。
這兩個都不是「模型偶爾出錯」，是 prompt 結構本身有問題，記在這裡避免改回去：**

1. **「日記中間幾頁是空白的」意象被誤用在 REM 有測到的夜晚。**
   這個意象不是修辭，是把「手錶沒測到 REM」誠實寫進敘事的機制——用在有資料的夜晚，
   等於對使用者謊稱這段沒有記錄，跟 payload 那三個誠實 null 是同一件事。
   實例：2026-08-09 的 REM = 29 分鐘（9.0%），模型仍寫了空白頁。
   **根因是 few-shot 把兩個獨立條件綁在一起**——範例二同時是「評級 Bad」又是「REM 未測得」，
   模型在 Bad 的夜晚就整段照抄。
   修法（三層，缺一不可）：
   - 調色盤那一行改成**只有 `rem_unmeasured` 為真時才放進 system prompt**
     （`build_system_prompt()`）
   - REM 有測到時**明確禁止**，不只是不提供（`PALETTE_REM_MEASURED`）
   - few-shot 拆成兩版依當晚條件挑（`build_few_shot()`）
   - `validate()` 加 `MISSING_RECORD_MOTIFS` 關鍵字擋，通不過就重試
   **第四層真的救到了**：修好前三層之後重跑，模型第 1 次仍寫出「沒看清」被驗證擋下，
   重試才過。光把選項拿掉不夠，模型自己的先驗會把它帶回來。

2. **簡體字混進 zh-TW 輸出**：`claude-sonnet-5` 寫出「門边」（門正體、边簡體，同一個詞裡兩種字形）。
   已加 `SIMPLIFIED_CHARS` 檢查 + FORMAT_RULES 明寫「一律臺灣正體中文」。
   該集合**刻意不含 于／后／里**——那些字正體中文本來就會用（皇后、公里），
   誤判的代價是整晚退回規則式文字。

3. **我自己的驗證規則太寬，反而害 3 晚退回規則式**（全量跑完才發現）：
   第一版把「沒看清」列為無條件禁詞，但 `PALETTE_REM_MEASURED` 才剛叫模型
   「REM 比例低要寫夢很淡、很快就過去」——而「來不及看清楚就散掉」正是那個意思，
   是在形容夢很模糊，**不是**在宣稱資料不存在。prompt 跟驗證規則互相打架。
   已收窄成兩組：`MISSING_RECORD_MOTIFS`（空白/留白/沒有記錄/沒看見等無條件擋）
   與「`SECTION_WORDS` + `VAGUE_VERBS` 同時出現才擋」（「中間…沒看清」擋、
   「來不及看清楚」放行）。收窄後回歸測試：原始錯誤文字仍被擋、正常說法放行、
   既有 43 晚零誤判。

**最終結果：46 晚全部由 LLM 生成（0 晚 fallback），全數重新驗證通過。**
`app/assets/data/app_payload.json` 的 `ai_content.is_ai_generated` 已是 `true`。

⚠️ **另修掉 `run_pipeline.py` 的跨終端機 bug**：它第一行就印中文標題，在 Windows
Git Bash（cp1252）下**跑任何步驟之前就 UnicodeEncodeError 崩掉**，PowerShell 則沒事——
同一台機器兩種結果。已加 `sys.stdout.reconfigure` + 對子行程設 `PYTHONIOENCODING=utf-8`
（設環境變數而非逐支腳本改，這樣新增步驟時不會忘記）。

`ADVICE_LANG` 這個設定**沒有實作**（輸出固定正體中文，prompt 本身就是中文寫的）。
`.env.example` 已改成誠實說明，不要以為改那個變數就能換語言。

Part A 那個已驗證的坑（`.gitignore` 的 `.env.*` 會連 `.env.example` 一起擋掉）
已用 `!.env.example` 修好並實測確認。同時新增了 `turn_*.mp4`——
兩支 TAPO 程式都會產生**臥室錄影片段**，原本沒有任何規則擋住它們。

Part B 的已定案決策（不要重新討論）：
- **模型用 Claude API**（Anthropic），用標準庫 `urllib.request` 打，**不裝 SDK**
  （理由：這功能不會讓 `requirements.txt` 多任何一行）
- AI 程式**獨立成 `ai/` 資料夾**，不要塞進 `garmin/`
- AI 要**整合 Garmin + TAPO** 給建議；TAPO 目前無真實資料 → 介面設計成有資料才自動啟用
- AI 的真正價值在**跨夜趨勢**（規則式 `recommendation` 46 晚只產生 8 種字串），
  數值判斷仍留在 Python 規則層，模型只負責敘事

### 前端整合的現況（2026-08-12 更新）

三個阻塞點都已解除：4 個 0 bytes 的 model 已填好、新增了 `app/lib/services/`、
`main.py` 已改成回傳真實資料。

**資料通道走 bundled asset，不走 HTTP**（已定案）：

```
garmin/data/*.json → build_app_payload.py → app/assets/data/app_payload.json
                                                    ├─→ Flutter rootBundle 讀
                                                    └─→ main.py 對外服務同一個檔
```

只產一份檔的理由：兩份就會有「App 顯示的跟 API 回傳的對不上」這種最難查的 bug。
`rootBundle` 與 `dart:convert` 都是內建的，所以**這條路徑沒有讓 `pubspec.yaml`
多任何一個套件**。之後要接 HTTP 只要實作 `sleep_repository.dart` 裡預留的
`ApiSleepRepository`（那時才需要加 `http` 套件）。

**還沒接的**：`report_screen.dart`（Insights 頁，34 KB，資料寫死在 `CustomPainter`
內部）與 `assistant_screen.dart` 的問答。`payload` 裡已經帶了 `history`（最近 30 晚），
要接 Insights 時不用改後端。

⚠️ **動 `app/` 之前先問 Jeremy**——那是他負責的部分。這一輪只碰了
「0 bytes 的空檔 + 全新檔案 + `home_screen.dart`」，刻意避開 `report_screen.dart`
以降低衝突面。

### 安全規範（一直有效）

`garmin/.env` 有**真實 Garmin 帳號密碼**。絕不提交、絕不在回覆中印出或引用其內容。

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

## 現有程式碼結構

- `main.py` — FastAPI 後端，目前 `/get-sleep-data` 只回傳寫死的 mock_data，**尚未接上任何真實資料來源**。
- `tapo/motion_detector.py` — OpenCV 讀 Tapo 攝影機 RTSP 串流，偵測翻身動作，寫入 MySQL（`sonnap` DB）。
  ⚠️ RTSP 帳密目前明碼寫死在檔案第 10 行，之後要改成環境變數。
- `garmin/` — Garmin 手錶資料匯入（目前我正在做這部分，見下方詳細狀態）。
- `Research-Background/` — 首頁設計的文獻依據（行為科學/遊戲化理論）。
- `app/` — Flutter 前端（隊友負責，PR #8 合併進來，156 個檔）。狀態見上方交接區。
- `docs` — 43 bytes 的佔位**檔案**（不是資料夾，所以無法在裡面放東西），待團隊決定怎麼處理。

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

### ✅ 已完成的舊規劃：Sleep Feature Extraction + Quality Evaluation

> ⚠️ 這節原標題是「Next Development Goal（下一步）」，**已於 2026-07 全部完成**，
> 保留下來只是歷史記錄。真正的下一步請看檔案開頭的「🔖 交接區」。

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

   > ⚠️ **上表是 2026-08-10 的歷史記錄。壓力與活動量兩列已於 2026-08-25 改動**
   > （量測時窗差了一天），最新狀態見本檔案「📌 2026-08-25 這一輪」。

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
