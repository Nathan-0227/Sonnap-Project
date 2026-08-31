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
（影像組負責，尚未改成環境變數）。`tapo 2.0/` 的兩支也各有 2–4 處命中。
同樣不要複製進回覆或 commit。

### ⚠️ GitHub 網頁「Add files via upload」會繞過本機 `.gitignore`

`.gitignore:8` 早就有 `.env` 規則，但那條規則**只在 `git add` 時生效**。
從網頁上傳檔案不經過本機 git，所以擋不住——`tapo 2.0/.env` 就是這樣進版控的
（commit `b5d166a`，08-27）。這是目前**唯一已知能繞過既有防護的路徑**。

→ 一律用 `git commit` 推檔案，不要用網頁上傳。
→ 收到隊友「Add files via upload」的 commit 時，先跑
  `git show --stat <commit>` 看有沒有 `.env`、金鑰、憑證。

---

## 🔖 交接區：現在在哪、下一步做什麼（2026-08-28 更新．新對話先讀這段）

> ⚠️ **這一輪是兩個 Claude Code session 同時在同一份 working copy 上工作**
> （使用者開了不只一個視窗）。過程中發生過一次真的 race：一個 session
> 正在存檔 `CLAUDE.md`，另一個同時 `git add -A` 把那次存檔也掃進了自己的
> commit（`9646f2c`）——這次結果無害（內容本身正確），但下次可能不會這麼幸運。
> **多開視窗同時改同一個 repo 時，commit 前先看 `git status` 裡有沒有
> 自己沒改過的檔案**，那多半是另一個 session 剛寫的。

### ✅ `tapo 2.0/.env` 的密碼已換（2026-08-28）

08-27 影像組用 GitHub 網頁「Add files via upload」誤傳了 `tapo 2.0/.env`
（含 RTSP 攝影機帳密），公開 repo 曝露約 12+ 小時。已在分支
`fix/untrack-tapo-env`（1 個 commit `6b41901`）把它從版控移除、
換成只留鍵名的 `.env.example`，並在檔案裡寫明「網頁上傳會繞過本機
`.gitignore`」這個根因。**已由 PR #18 合併**。

⚠️ **08-28 深夜又發生一次獨立的意外**：`feature/pet-mood-animation` 的
`8c52874`（寵物動畫）commit message 完全沒提到 `tapo 2.0/.env`，卻把它
一起帶進了 commit——多 session 同時改同一份 working copy、`git add -A`
把別人沒 commit 的修改也掃了進去。裡面的 `CAMERA_RTSP_URL` 因此帶了一組
**先前從未在 `origin/main` 上出現過**的新值，隨這條分支一起 push 上了公開 repo，
幾分鐘後才發現。已用 `c7c410d` 把三個受影響的檔案復原成 `origin/main` 版本，
現在 GitHub 上看到的檔案內容不含那組新值。

**兩次外洩用的都不是同一組值，但使用者已去 Tapo App 把攝影機的 RTSP
密碼換掉**——不管 git 歷史裡（`b5d166a`、`8c52874`）留著哪一組舊值，
兩組都已失效，曝露已解除。

✅ **治本的修法已合併**（PR #18，`origin/main` = `5e41e0f`）。
`tapo 2.0/.env` **已不在版控中**，只剩 `.env.example`（實測：
`git ls-tree origin/main "tapo 2.0/"` 只有 `.env.example`、
`sleep_monitor.py`、`tapo_detector.py`）。

→ 那條「`git add -A` 掃到別人沒 commit 的 `.env`」的路徑**已經堵住**：
檔案不再被追蹤，`.gitignore:8` 的規則從此對它生效。
⚠️ 但**網頁「Add files via upload」仍然繞得過去**（那是 08-27 那次的根因），
所以規則不變：一律用 `git commit` 推檔案，不要用網頁上傳。

### ✅ 2026-08-28 凌晨那一輪（另一個 session，9 個 commit，全在 `feature/pet-mood-animation`）

✅ **全部已經合進 `main`**（PR #17 + #18）。下面那張表留著是為了記錄每一項的
實測結果，不是進度追蹤——要知道 main 現在有什麼，問 git 不要問這裡（方法論第 2 點）。

| # | 做了什麼 | 實測 |
|---|---|---|
| 1 | `tapo 2.0/.env` 停止追蹤 + `.env.example`（分支 `fix/untrack-tapo-env`，**獨立**） | — |
| 2 | `wearable_nightly` 補 `sleep_start_time` / `wake_time` | 51 晚有值，與 asset 路徑 30/30 逐字相同 |
| 3 | baseline 窗格改日曆天（`MAX_BASELINE_DAYS`） | 17 晚位移，最大 1.60，**0 晚換等級** |
| 4 | `MOTIF_FAMILIES` 一對一 + 關鍵字擋得住改寫 | 對不到家族 **10/51 → 1/51** |
| 5 | 沒量到睡眠的夜晚不得進 baseline | 27 晚位移，最大 1.30，2 晚換等級 |
| 6 | **新增 `tests/test_scoring_guards.py`** | 4 條，全部驗證過「bug 重現時會紅」 |
| 7 | `PROJECT_STATUS.md` 對齊現況（51 晚、三名配戴者） | 見六、0 |
| 8 | 3.9 攝影機上床時刻：樣本 3 晚 → 9 晚 | 成功 4 晚、兩種失敗各有解 |
| 9 | **新增 `inspect_tapo_dump.py`** | 讓 3.9/3.10 的數字可重跑 |

⚠️ **第 2 項的教訓**：文件寫「要補是三處」，實際是**五處**。多的兩處是
`db.py` 的欄位白名單（會拋錯）與 `healthconnect_adapter.to_wearable_row`
（**不會報錯**）。以後在 `wearable_nightly` 加欄位請照五處盤點。

### ⏭️ 這一輪之後，還沒做的

| 事情 | 卡在誰 |
|---|---|
| **換 RTSP／MySQL 密碼**（見上方 🔴） | 影像組。**移除檔案不等於止血** |
| ~~TAPO timeline 時間戳壞掉~~ | ✅ **我方已繞過**：時刻在 `video_clip` 檔名裡，見 `tapo_index.py`。來源端的修法在 **Issue #19** |
| **TAPO 的 8 個問題**（門檻沒記錄、`video_events` 被丟棄、連續翻身不進 timeline、`MOTION_MICRO` 太靈敏…） | 影像組。清單與偵測層規格見 **[TAPO_HANDOFF.md](TAPO_HANDOFF.md)**，每一條都可用 `python inspect_tapo_score.py` 重現 |
| `SLEEP_START=01:00` 太晚，14% 的夜晚結構上錄不到 | 使用者已決定改成「App 點『開始睡眠』才開攝影機」→ 需要影像組 × Jeremy 對接介面（`.env` 是靜態值，App 觸發要有訊號通道） |
| id 117（08-19）`total_events=73` 但 `timeline=[]` | 影像組，含在 Issue #19；細節見 TAPO_HANDOFF #8(b) |
| `report_screen.dart` / `assistant_screen.dart` 接資料 | Jeremy（`app/` 動之前先問他） |
| push / 開 PR | 使用者（公開 repo 的對外動作） |
| 要不要跑 `--ai` 重生 51 晚 | 使用者（會花 API 額度；**目前沒必要**，51 晚全是 llm） |

✅ 已經不卡了：`report_screen.dart`（PR #16 就接好了）、`assistant_screen.dart`
（PR #20 接上真實 payload）、push／開 PR（08-28 四個 PR 全部合完）。

### ✅ demo 相關這一輪的四個進展

1. **APK 已能自己建，且已裝進實體手機測過**（分支 `merge/jeremy-report-screen`，
   已合併進 `main`，見下方「已完成」）。Flutter/Android 環境已從零建起，
   細節與踩過的坑見 `DEVLOG.md` 2026-08-27 那則。
   ✅ 手機上那份已重建重裝（08-28 實測：拉出手機裡的 APK、解出內嵌的
   `app_payload.json`，`pet_mood: happy`、`82.2 Good`，與 repo 逐位元組相同）。
2. **寵物動畫不再永遠播開心的狗**——跟著 `pet_mood` 走，四態各一個資產路徑，
   資產還沒到位前退到濾鏡版的 `happy_dog.json`（PR #17）。
3. **Tier3／SRI 不再跨戴錶者計算（`9646f2c`）**——這支手錶 2026-05-28~08-27
   經手三個人，之前被當成同一個人處理，導致 08-02 之後 10 晚裡 9 晚被誤判
   `anxious`（含兩個 90 分以上的 Good 夜晚）。已用 `WEARER_SEGMENTS` 分段，
   細節見下方 ①。
4. **睡眠助理不再是假回覆，且時區 bug 已修（PR #20）**——
   `assistant_screen.dart` 改讀真實 payload。它是**路由器不是生成器**：
   只把後端算好的欄位取出來組句子，**不自己產生任何建議**
   （產生建議＝第二套沒有文獻依據的評分層，違反紅線 4）。
   ⚠️ 順手抓到一個**已經在 `main` 上、使用者看得到**的 bug：
   `DateTime.tryParse("...+08:00")` 回傳的是 UTC，`.hour` 因此**早 8 小時**
   （22:32 顯示成 14:32）。Jeremy 的 Insights 圖表也中招
   （`report_screen.dart` 的 `_timeToMinutes`）。
   → 修法是新檔 `app/lib/models/wall_clock.dart` 的 `parseWallClock()`：
   **不要用 `.toLocal()`**——那會跟著手機時區跑，而這些是已經記錄下來的事實，
   要的是字串裡那個 `+08:00` 的牆鐘時間。**Flutter 端解析 payload 時間一律走它。**

✅ **那個發現已修**（2026-08-28，commit 見下）。而且實際規模比當初記的大得多：
不是 07-13~07-15 三筆，是 **89 列 summary 裡有 38 列沒量到睡眠**，
其中大部分都帶著 `avg_heart_rate` 值。

關鍵在語意——那一欄的定義是「**睡眠期間**平均心率」。
`total_sleep_minutes = 0` 時手錶根本沒偵測到睡眠，那個數字量的是清醒時段。
數值本身就說明了：`wearer_a` 真正睡眠夜的 avgHR 是 52–58，
這些無效列上是 **85 / 88 / 90 / 95**。

`compute_modifiers()` 現在有自己的 `has_measured_sleep()`，
並且**分辨構念層級而不是整列丟掉**：

| 欄位 | 無效夜晚 | 理由 |
|---|---|---|
| `avg_heart_rate`、`awake_count`、`sleep_segment_count`、`presleep_stress_score` | ❌ 排除 | 全由睡眠期推導，沒有睡眠期就沒有這些量 |
| `resting_heart_rate`（每日單一數字）、`steps_total`（白天的量） | ✅ 保留 | 不是從睡眠期算出來的 |

**實測**：27 晚分數改變（26 晚是 `avg_hr_modifier`，正是預測的機制），
最大位移 **1.30**、平均 0.165，品質等級改變 **2 晚**
（06-18 Normal→Good、07-09 Normal→Poor）。
方向：**下降 24 晚、上升 3 晚**——與假設一致（baseline 原本被白天心率推高，
正常夜晚因此拿到不該有的加分）。同樣是單向的：0 項變寬鬆、2 項變停用。

⚠️ `build_sleep_timeline()`（SRI）**本來就有**自己的檢查，不受影響。

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

> ✅ **Jeremy 那個卡點已於 2026-08-26 修好**（分支 `feature/history-sleep-times`）。
> `build_app_payload.py` 的 `history` 每晚現在帶 `sleep_start_time` 與 `wake_time`，
> 與 `metrics` 同一個來源（features），最新一晚兩邊逐字相同。
> 30/30 晚都有值，分數欄位逐欄未變。
>
> ✅ **`GET /insights` 的 `history` 也補上了**（2026-08-28，commit `4aff730`）。
> `/home` 的 `metrics` 一併補齊。51 晚全部有值，與 `app_payload.json` 的
> history 30/30 逐字相同，分數欄位逐列未變。**Jeremy 現在接新 API 不會再卡。**
>
> ⚠️ **當時文件寫「要補是三處」，實際是五處。** 多出來的兩處是
> `db.py` 的 `upsert_wearable_nightly` 欄位白名單、以及
> `wearable/healthconnect_adapter.py` 的 `to_wearable_row`。
> 前者會拋 `ValueError`，跑一次就發現；**後者不會報錯**——不補的話
> 只有 Health Connect 來源的使用者缺值、Garmin 來源有值，
> 那種「只在一種來源下缺資料」的 bug 最難查。
> → 以後在 `wearable_nightly` 加欄位，請照**五處**盤點。
>
> ⚠️ **不要拿 `sleep_start_time` 當 `lights_out_at`**——前者是手錶偵測到你
> 「睡著」（生理），後者是「放下手機」（行為），後者一定較早。
> （理由已寫在 `migrate_garmin_to_db.py:24-27`。）


**① Tier3 的 baseline 跨了不同的戴錶者 —— 已修（2026-08-28）**

那支手錶在 2026-05-28 ~ 08-27 之間**經手三個人**，專題負責人本人 08-28 才開始戴。
在此之前 51 晚被當成同一個人處理。Tier3 的每一項都是「今晚的你 vs 過去的你」，
SRI 也是個人內比較——**跨人比較沒有意義**。

實作在 `garmin/apply_recovery_modifier.py` 的 `WEARER_SEGMENTS`：

| 區段 | 期間 | 可信 |
|---|---|---|
| `wearer_a` | 2026-05-28 ~ 07-27 | ✅ |
| `unverified` | 2026-07-28 ~ 08-27 | ❌ 已知多人戴過，訊號分不出是一人還兩人 |
| `wearer_c` | 2026-08-28 起（專題負責人本人） | ✅ |

換段時 baseline 歸零、SRI 窗格夾在本段起日之後；`trusted=False` 的區段
把 Tier3 與 SRI 全部關掉，改輸出 `UNVERIFIED_SEGMENT_NOTE`
（措辭刻意與「冷啟動」不同：冷啟動是「再戴幾晚就會好」，這個是「這段不該做個人化比較」）。

分界是用生理訊號本身找的（使用者不記得交接日期）：對每個候選分界算
「左右中位數差 / MAD」，真正的換人會在多個獨立訊號上同時跳躍。
A→B 分界處靜止心率跳 5.73~6.74、睡眠期間平均心率跳 4.13；
前 41 晚內部三個訊號的最大跳躍都 ≤ 1.03（確定同一人）。

**實測影響**（51 晚重跑，2026-08-28）：

| | |
|---|---|
| 分數改變 | **10 晚**，全部落在 `unverified` 區段 |
| 修正值 | −2.37 ~ −9.75 → **0.0**，平均取消掉 **5.61 分** |
| 品質等級改變 | **6 晚**（08-07 / 08-22 / 08-23 Normal→Good；08-09 / 08-21 Bad→Poor；08-17 Poor→Normal） |
| 最新一晚心情 | `anxious` → `happy` ——那是一個 **82.2 分的 Good 夜晚卻顯示焦慮寵物** |

⚠️ **報告不能寫「51 晚單一使用者實測」**——那是三個人。誠實的寫法是
「跨 3 名配戴者、51 晚」。**Tier1/2 的基礎分數完全不受影響**
（文獻加權、不依賴個人 baseline），所以每一晚的分數本身仍然站得住。

⚠️ **負責人本人的 baseline 從 2026-08-28 起算**，`MIN_BASELINE_NIGHTS = 14`，
所以**前 14 晚 Tier3 是冷啟動、不產生修正值**（09-09 之前湊不滿）。

✅ **那個殘留問題已修**（2026-08-28，commit `925e2b1`）。
常數改名 `MAX_BASELINE_DAYS`，`rolling_baseline()` 改吃 `(日期, 值)` 並依
日曆天夾窗，與 `SRI_WINDOW_DAYS` 一致。

實測 51 晚：17 晚分數位移（最大 **1.60**、平均 0.129）、**0 晚品質等級改變**、
最新一晚不變。**0 個項目「原本沒 baseline、改完才有」**——這一改只會更嚴不會更鬆。
3 晚的 `stress_modifier` 改為停用（`presleep_stress_score` 要求前一晚也戴錶，
是最稀疏的訊號，日曆天窗格最先咬到它）。

⚠️ 兩個門檻管的是不同的事，不要混為一談：
`MAX_BASELINE_DAYS`（28）管「多舊的資料還算數」（日曆天），
`MIN_BASELINE_NIGHTS`（14）管「要有幾晚才夠穩」（有效晚數）。
配戴稀疏時兩者會同時咬到，那是正確行為——「最近 28 天只戴 9 晚」
本來就不足以代表「現在的你」。

**② AI 夢境 —— 這一條已經沒事了（2026-08-28 核對）**

「新 5 晚沒有 AI 夢境」這句**早就過期**：`ai/data/ai_advice.json` 的 51 晚
全部 `source=llm`，`app_payload.json` 最新那晚 `is_ai_generated=true`
（model `claude-sonnet-5`）。不需要再跑 `--ai`。

✅ 那個擋路的「`MOTIF_FAMILIES` 不是一對一」也已修（commit `d79cf97`），
而且一併抓到**第二個更嚴重的缺陷**：

| | 修正前 | 修正後 |
|---|---|---|
| 家族數 | 21 | 27（與調色盤選項一對一） |
| **對不到任何家族的夜晚** | **10 / 51** | **1 / 51** |
| 實際用到的家族 | 13 | 19 |
| 最集中的家族 | 19.6% | **11.8%** |

第二個缺陷是：**關鍵字抄了調色盤的逐字片語，但 prompt 明寫
"You may rephrase and extend"**。模型照做，關鍵字就對不上，
10 晚的去重完全失效。最直接的證據是 08-18 與 08-22 兩晚的夢幾乎逐句相同
（"a sky that could not decide / settle on a season"），卻因為關鍵字寫的是
`changing season` 而雙雙沒被擋下。

→ 新增調色盤選項時，這裡要**同步新增一個家族**，而且關鍵字要取
「該選項獨有、改寫後仍會留下」的字（`season` / `lake` / `cold morning`），
不是那一整句。

⚠️ **`PROMPT_VERSION` 沒有動**（仍是 v4）。升版會把 51 晚全部標記為 stale
要求重生，那會實際呼叫 Claude API 花掉額度；既有夢境的內容不因這次修改
而失效，改善的是**往後**生成時的去重精細度。

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

### git 狀態（2026-08-28 更新）

✅ `origin/main` 現在是 `18aa8ed`。08-28 這一輪的四個 PR 全部合完：

| PR | 內容 |
|---|---|
| #17 | 寵物動畫四態化 + 戴錶者分段（`WEARER_SEGMENTS`）+ baseline 日曆天窗格 |
| #18 | `tapo 2.0/.env` 停止追蹤，改附 `.env.example` |
| #20 | 睡眠助理接真實 payload + 修掉時區解析錯 8 小時 |
| #21 | 本檔的 `.env` 狀態更新 |

更早的 PR #11（多使用者後端）、#12~15（文件與英文化）、#16（Jeremy 的
Insights 頁）也都在裡面。

**本地與遠端都只剩 `main` 一條自己的分支**，已合併的分支都刪了。
遠端另有三條別人的：`flutter`、`second-flutter-integration`（都已併入、可刪）
與 `feature/opencv-motion-garmin`（影像組，整條不能合，見下）。

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

**Flutter/Android 這一輪（08-27）也從零裝起**：Flutter 3.44.9（`C:\Users\user\flutter`）
+ Android SDK + Temurin JDK 17。踩過的坑（`compileSdk` 版本不對、機器上一度有
兩份 Flutter SDK 互相污染、`local.properties` 反斜線跳脫、VS Code Gradle 外掛搶鎖）
全部記在 `DEVLOG.md` 2026-08-27 那則，這裡不重複。**現在 `flutter build apk`
與 `adb install` 都能跑**，已裝進實體 Android 手機驗證過。

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

分支盤點（2026-08-28 晚間用 `git ls-remote --heads origin` 實測，4 條遠端分支）：

| 遠端分支 | 作者 | 狀態 |
|---|---|---|
| `main` | — | `18aa8ed`（PR #21 合併點） |
| `second-flutter-integration` | Jeremy | ✅ **內容已於 PR #16 併入 main**（走的是新分支 `merge/jeremy-report-screen`，不是直接合這條）。這條本身沒人刪，**可以刪了** |
| `flutter` | Jeremy | 已全數合併，可刪 |
| `feature/opencv-motion-garmin` | 影像組 | 12 個 commit 從沒合併，整條不能合，見下方 |

✅ 自己開過的分支全部合完並刪除（遠端與本地都只剩 `main`）。
剩下那兩條 Jeremy 的沒動——**別人的分支不代刪**。

### Jeremy 的 `second-flutter-integration` —— ✅ 已於 PR #16 併入，這節可歸檔

沒有走「直接合他那條分支」的路（原本規劃的順序，21 個落後 commit、
1 個生成檔衝突）。實際做法是另開分支 `merge/jeremy-report-screen`
（從當時的 `main` 分出去）手動合併他的內容，衝突檔取 main 版本重新產生，
2026-08-27 併入 main（PR #16）。`second-flutter-integration` 本身還留在遠端，
內容已經沒用了，可以刪。

⚠️ **`feature/opencv-motion-garmin` 有 12 個 commit 從沒合併，但整條不能合。**
另外 11 個 commit 會刪掉 `app`、`backend`、`docs`，還會把 2026-08-11 刪掉的
`garmin_importer.py` 救回來。唯一有價值的是 `sleep_records.sql`——那正是
`PROJECT_STATUS.md` 3.5 說「不存在」的 TAPO 建表 SQL。

⚠️ **那條分支上的 `sleep_records.sql`（根目錄）已經被取代，不要再引用它。**
現行版本是 `tapo/sleep_records.sql`（commit `00c08b1`，244KB），有 `created_at`，
所以先前記的「建表後 `sleep_anylzer.py` 會 `Unknown column`」在現行版**不存在**。

⚠️ **舊 dump 那三項「可直接引用進報告」的觀察，有兩項在新資料裡已經不成立。**
2026-08-28 重新清點現行檔（實測，不是推論）：

| 舊記錄（來自舊 dump） | 現行檔實際情形 |
|---|---|
| 5 筆紀錄 | **15 筆** |
| 4 筆分數全是 50 → 印證紅線 3「人為地板」 | `sleep_quality_score` 有 **14 個不同的值（11~97）**，**地板症狀不存在** |
| `report_date` 全是 dump 產生當天 | 日期是分散的，但**可信度分三層**，見下 |

用 `created_at` 對照 `report_date` 分層（這是判斷日期可不可信的唯一內部證據）：

| 分層 | 筆數 | 判準 |
|---|---|---|
| 現場擷取（可信） | 9 | `created_at` 與 `report_date` 同日或差 ±1 天（跨午夜） |
| 事後批次補的 | 5 | `created_at` **全部是 `2026-08-12 13:21:29`**，同一秒 → 日期是人工填的 |
| 幾乎確定是錯的 | 1 | id 48 宣稱 `2026-06-11`，卻在 **08-18** 才建立（差 68 天） |

與 Garmin 51 晚的重疊：**最寬鬆 10 晚、只算現場擷取的 5 晚**（08-17/18/21/22/23）。

⚠️ 那筆 06-11 是**唯一**讓 TAPO 與 Garmin 六月資料產生重疊的紀錄。
不做這個分層就直接 `merge`，會憑空多出一個橫跨兩個月的「共同樣本」。
✅ 已處理：`tapo_index.sleep_recording_problem()` 會擋掉它（29 秒的白天錄影），
三個呼叫端共用同一個判準。實測 `if_integrate.py` 的重疊因此從 10 晚變成 9 晚，
日期範圍從「2026-06-12 ~ 08-23」收斂成「2026-08-02 ~ 08-23」。

⚠️ **「`motion_intensity` 恆為 2073600」這個說法已被實測推翻（2026-08-30）。**
24949 筆事件裡有 20105 個相異值，整畫面值只有 **238 筆（0.95%）**，
且全部集中在 `large_turn`（1017 筆中的 23.4%），micro_motion 一筆都沒有。
整畫面誤判是真的、值得修，但**不是攝影機分數歸零的原因**——
歸零的原因是事件量（micro_motion 佔全部事件的 93%）。
重跑：`python inspect_tapo_score.py`。

已合併的歷史：PR #9（Garmin 評分）、PR #10（資料交接層 + AI + Flutter 資料層）、
PR #11（多使用者後端）、PR #12~15（文件與英文化）、PR #16（Jeremy 的 Insights 頁）。
`main` 也含隊友的 Flutter app（`app/`）與 TAPO（`tapo/`）。

✅ `gh` CLI 已登入（帳號 `Nathan-0227`），可以直接用它開 PR、看 PR 列表。

### 已完成

- Garmin pipeline 5 步驟全通，`python garmin/run_pipeline.py` 約 6 秒跑完
- 51 晚實測資料（2026-05-28 ~ 08-25），每晚 0–100 分 + Good/Normal/Poor/Bad，
  **跨 3 名戴錶者**（見上方 ①，報告不能寫成單一使用者）
- Tier1/2 基礎分數（文獻加權）+ Tier3 個人化修正值（±12，戴錶者分段後）
  + SRI（呈現不計分）
- 完整文獻依據：`Research-Background/Garmin手錶分數.md`
- 後端多使用者 API、行為介入迴圈、Health Connect adapter（PR #11）
- Flutter App 已能自己建置 APK 並裝進實體 Android 手機執行（見上方 ✅）

---

## 🚧 設計紅線與待補迴圈（2026-08-17 定．動評分或遊戲化之前必讀）

來源：拿 GitHub 上同類型開源專案 **NightBloom**（`shev0k/sleep_tracker`）逐行對照的結論。
4 stars／34 commits／**最後一次 push 是 2024-11-02**，停更約 21 個月
（2026-08-28 用 GitHub API 複查，仍是最新版本；為什麼要複查見方法論第 2 點）。
⚠️ **授權不明**：README 宣稱 MIT，但 repo 裡沒有 LICENSE 檔（見方法論第 1 點）。
**完整證據與行號在 [PROJECT_STATUS.md](PROJECT_STATUS.md) 第八節**，這裡只留規則。

分寸先講清楚：對方是小型學生專案，**「它有問題」不能反過來證明我們是對的**。
留這一節是因為它的每個問題剛好對應到我們刻意做過的取捨，可以當成回歸測試用的反例。

### ❌ 五條紅線（要動評分或加遊戲化功能時逐條檢查）

| # | 紅線 | 對方踩到的實例 |
|---|---|---|
| 1 | **同一個訊號不得以多個名義重複計分** | 它的 `movementScore` / `remSleepScore` / `lightSleepScore` 全是加速度 magnitude 的不同切法 → **70% 的分數只反映單一訊號** |
| 2 | **每一項計分都必須有文獻門檻**（見下方展開） | 它的 `1.5 / 2.5 / 60 / 20 / 50` 五個門檻零引用，且未扣重力（靜止時 magnitude 本來就是 1.0 g） |
| 3 | **分數不得有人為地板** | 它所有子分數只有 100/75/50 三檔，總分被壓在 [50,100]，糟糕的夜晚彼此無法區分 |
| 4 | **⚠️ 遊戲化層只讀，不得回寫評分層** | 見下方展開 |
| 5 | **獎勵必須與「品質」耦合，不能只與「有資料」耦合** | 見下方展開 |

**紅線 2 展開（2026-08-31 使用者重申，適用於所有新的計分項）**：
**要計分，先有文獻證明並記錄下來**——文件寫好之前不寫公式，也不調既有係數。
格式比照 `Research-Background/Garmin手錶分數.md`：
「構念 → 文獻怎麼說 → 本專案採用的操作性門檻 → 為什麼這樣取捨 → 完整書目」，
每一條引用都要**核對第一作者**（方法論第 6 點，已誤植過兩次）。

→ 攝影機是現在唯一卡在這一關的模組：要讓 TAPO 參與計分，
  必須先寫 **`Research-Background/攝影機分數.md`**。TAPO 那四代公式
  （`2.0/0.1/0.4`、`10/5/2`、`95/85/70/50/30`）之所以全部失敗，
  正是因為四代都跳過了這一步，沒有一個數字說得出出處。
  已查證可用的種子文獻兩條，寫在 `inspect_tapo_score.py` 的常數區：
  Montini 2024（video-PSG，動作率中位數 11 次/小時，IQR 8–15）與
  De Koninck 1992（18–24 歲體位改變 3.6 次/小時）。
  ⚠️ **常模不等於門檻**：文獻數的是人工判讀的動作，我們數的是像素面積過門檻的幀，
  中間還缺一次效標驗證。

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
| `avg_stress_score` | 不是睡眠期間的壓力 | 該**日曆日白天**的平均（11439 筆讀數中僅 8.6% 落在睡眠期間）。**已不計分**，保留只因 `itegration/if_integrate.py` 的相關性分析還在讀 |
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
| `sleep_quality_score` | `tapo/tapo_detector.py:486`（V1，另有 V2/V2.5/V3 三代） | ⚠️ 扣分制，影像組的。**量的是 timeline 長度不是睡眠**——同一晚跨來源差 80 分。再往下一層：timeline 長度取決於**當晚的偵測門檻**，而門檻逐晚變過至少四組且沒記在任何欄位裡 → **跨夜比較在原理上不成立，不是調係數能修的**。見 [TAPO_HANDOFF.md](TAPO_HANDOFF.md) |
| `integrated_score` | `itegration/if_integrate.py` | ⚠️ `0.6×garmin + 0.4×tapo`，**權重無依據**，輸出已標成 PROVISIONAL |
| ~~`calculate_camera_score()`~~ | — | ✅ **已刪除**（2026-08-30） |
| ~~`calculate_garmin_score_from_features()`~~ | — | ✅ **已刪除**（2026-08-30） |

⚠️ **`PROJECT_STATUS.md` 3.10 主張根本不該做加權平均**：攝影機的價值是提供
手錶量不到的「上床時刻」（→ 臥床時間 → 解掉效率限制 + 解鎖入睡潛伏期），
那條路一個新參數都不用訂；而加權平均要 justify 60/40，還是拿有引文的分數
去平均沒引文的分數。

> 那兩段死碼在 2026-08-30 刪掉了。刪的理由不只是「跑不到」——**它們跑到也會壞**：
> 裡面寫 `if eff < 85:` 而 `eff` 是一個 pandas Series，對 Series 取真值會拋
> `ValueError: The truth value of a Series is ambiguous`。
> 留著只會讓讀的人以為「沒有 Garmin 分數時系統會自己算」，那是假的。
> （我曾連續兩次把它們當成現況寫進文件——見末尾「方法論」第 4 點。）

---

## 🤖 兩個模組的既定決策（不要改回去）

### 🌐 輸出語言：**英文**（2026-08-26 使用者決定）

全系統的**輸出字串**一律英文——payload 欄位、API 訊息、評分建議、挑戰文案、
AI 夢境、console 輸出。**程式碼註解與 docstring 維持中文**：那是給團隊讀的
說明不是輸出，翻掉會讓專案最有價值的決策記錄變難讀。

⚠️ **換語言時最危險的不是翻譯，是驗證層會安靜地失效。**
`ai/generate_advice.py` 有四個機制與語言綁死，換掉任何一個而不改對應物，
**不會報錯，只會不再擋任何東西**：

| 機制 | 中文版 | 英文版 | 不改的後果 |
|---|---|---|---|
| 語言洩漏 | `SIMPLIFIED_CHARS` | `CJK_LEAK_PATTERN` | 模型漂回中文不會被擋 |
| 拼字數值 | `CHINESE_NUMERAL_PATTERN` | `SPELLED_NUMERAL_PATTERN` | "ten point three hours" 混進 App |
| 意象去重 | `MOTIF_FAMILIES` 中文關鍵字 | 照英文調色盤重挑 **+ 比對前 `.lower()`** | 去重完全失效 |
| 長度上下限 | 20–150／30–250／5–100 | **×3** → 60–450／90–750／15–300 | **整批被長度檢查擋掉** |

長度倍率的依據是實測：舊中文 46 晚的字元中位數是 48／85／31，
英文寫同樣內容是 131／280／80，約 **2.7–3.3 倍**。

⚠️ 意象去重的關鍵字**不能逐詞翻譯**——「闔上」翻成 `closed` 會誤判到
"I closed my eyes"。要照著英文調色盤實際會寫出的措辭重挑。

### AI 夢境（`ai/`，`PROMPT_VERSION` = v4）

| 決策 | 理由 |
|---|---|
| 用 Claude API + 標準庫 `urllib.request`，**不裝 SDK** | 這功能不讓 `requirements.txt` 多任何一行 |
| 「日記中間幾頁空白」意象**只在 `rem_unmeasured` 為真時**才放進 system prompt | 那不是修辭，是把「手錶沒測到 REM」誠實寫進敘事的機制。用在有資料的夜晚等於對使用者謊稱 |
| few-shot 依當晚條件拆兩版 | 原本範例二同時是「Bad」又是「REM 未測得」，模型在 Bad 的夜晚就整段照抄 |
| `validate()` 保留 `MISSING_RECORD_MOTIFS` 關鍵字擋 | **這層真的救到了**：前三層修好後模型第 1 次仍寫出「沒看清」，重試才過 |
| 拼字數值規則**必須有 `point` 才擋** | 沿用中文版「必須有『點』」的收窄判準。英文更容易誤判（number words 是常用字），"give it one more try"／"half an hour earlier" 都必須放行 |
| `BANNED_WORDS` 用**完整單詞**比對（`\b...\b`） | 英文才需要這層：`treat` 會命中 `retreat`、`ill` 命中 `still`。中文沒有這個問題 |
| `recent_motifs()` 的呼叫**必須放在主迴圈內** | `entries` 每跑完一晚才更新，放外面等於這個功能沒作用 |
| `ADVICE_LANG` **仍然沒有實作** | 輸出固定英文（prompt 本身就是英文寫的）。改那個變數不會換語言 |

> ⚠️ **驗證規則寫寬很省事，但誤判的代價是整晚退回規則式文字。**
> 這類錯誤已經踩過三次（「沒看清」無條件擋、`SIMPLIFIED_CHARS` 的于／后／里、
> 國字數字）。加新規則前先問：**它會不會誤傷正常說法？**

> 📊 **v4 全量實測（51 晚，2026-08-26）**：51/51 由 LLM 生成、**0 晚 fallback**，
> 中文洩漏 0 晚、夢境含數字 0 晚，意象最集中的家族 **19.6%**。
> ⚠️ 中文版留下的未解問題「棉被與雪佔 37%」在英文版沒有重現，但**根因沒有修**——
> `MOTIF_FAMILIES` 與調色盤選項仍然不是一對一（深睡類 6 個選項只對應 2–3 個家族）。

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
- **`tapo_index.py`（2026-08-30 新增）— 攝影機資料的單一事實來源。**
  同時讀 `tapo/sleep_records.sql` 與 `tapo/sleep_reports/*/*.json`，
  **依 `video_clip` 檔名定日期與時刻**（`report_date` 會錯、`time` 欄位會壞，
  兩者都已有實例）。依 6 小時間隔切夜、去重、每個欄位附 `provenance()` 標籤。
  ⚠️ 呼叫端有三個（`ai/night_profile.py`、`build_app_payload.py`、
  `itegration/if_integrate.py`），**有效性判準只有一份**
  （`sleep_recording_problem()`），不要各自再寫。
- `inspect_tapo_score.py`（2026-08-30 新增，08-31 擴充）— 攝影機分數的根因分析，
  只清點不評分。六張表：扣分拆解、跨來源落差、decibel 分世代、整畫面誤判、
  **門檻漂移**、**事件節奏 vs 文獻常模**。
  影像組送新 dump 之後直接重跑，不要照抄舊數字。
- **`TAPO_HANDOFF.md`（2026-08-31 新增，09-01 擴充）— 給影像組的交接文件。**
  上半部是 8 項問題（每條附 `檔案:行號` 與可重現的數字），
  下半部是**偵測層規格**：為什麼 `countNonZero` 救不回來、
  建議的管線（降取樣→照明否決→背景相減→開運算→ROI→連通域）、
  ROI 三種定法、「一次動作 = 一段 episode 不是一幀」、起始參數與驗收條件。
  ⚠️ 裡面有一條觀念要記住：**偵測門檻 ≠ 計分門檻**——前者拿影片人工標註校準，
  不受紅線 2 約束；後者才必須有文獻。

**模組**

| 目錄 | 內容 |
|---|---|
| `garmin/` | 5 步 pipeline（見下節）。⚠️ 只留程式碼，生成物全在 `garmin/data/` |
| `behavior/` | Tier A 行為層：`challenges.py`、`pet_state.py`、`adherence.py` |
| `wearable/` | `healthconnect_adapter.py`：Health Connect → **既有評分器**（一個門檻都沒改） |
| `ai/` | 夢境日記（Claude API）。⚠️ `ai/.env` 有金鑰，已被 gitignore |
| `tapo/` | 影像組負責。⚠️ 檔名是 `tapo_detector.py`（不是 `motion_detector.py`） |
| `itegration/` | `if_integrate.py`（Garmin×TAPO 整合）。⚠️ `itegration` 是拼字錯誤，刻意不改名。2026-08-30 從 MySQL 改讀 `tapo_index`，**第一次真的跑得起來**（先前那個 `sonnap` 資料庫不在這台機器上）。需要 `pip install -r requirements.txt` |
| `tests/` | `test_api.py`、`test_healthconnect_adapter.py`，**獨立腳本不需 pytest** |
| `app/` | Flutter（Jeremy 負責）。⚠️ **動之前先問他** |
| `Research-Background/` | 文獻依據，正式來源是 `Garmin手錶分數.md` |
| `docs` | 43 bytes 的佔位**檔案**（不是資料夾），待團隊決定 |

**環境**：`.venv` 已裝 `fastapi`、`uvicorn`、`httpx`、`garminconnect`、
`mysql-connector-python`。**未裝** `pandas`、`matplotlib`、`seaborn`、`opencv-python`、
`numpy`——只有 `itegration/` 與 `tapo/` 需要，要用時再 `pip install -r requirements.txt`。
⚠️ `garminconnect` 只有 `--fetch` 那一步需要，pipeline 後四步不受影響。

**驗收指令**

Python 四支，都是獨立腳本、不需要 pytest：

```bash
python tests/test_api.py                 # 端點與行為層（用暫存 DB，不碰 data/sonnap.db）
python tests/test_healthconnect_adapter.py
python tests/test_scoring_guards.py      # 2026-08-28 新增
python tests/test_tapo_index.py          # 2026-08-30 新增
```

Flutter（在 `app/` 底下跑，**34 條全過**）：

```bash
flutter test        # widget_test 4 + pet_mood_animation 5 + assistant_answers 17 + wall_clock 8
flutter analyze     # 0 error（15 個既有的 warning／info 不是這一輪帶進來的）
```

⚠️ `test_tapo_index.py` 守的是 TAPO 資料那五個**壞掉時不會報錯**的機制
（日期取自檔名而非 `report_date`、壞掉的時間戳要能還原、橫跨兩夜的紀錄要切開、
重複檔要去重、每個欄位都要有 provenance 標籤）。五條都用
「把 bug 重新引入、確認測試會紅」驗證過。

⚠️ `test_scoring_guards.py` 守的是**四個壞掉時不會報錯的機制**，
每一條都用「把 bug 重新引入、確認測試會紅」驗證過：

1. `has_measured_sleep()` 與 `extract_sleep_features.is_valid_night()` 的判準
   不得漂移（兩支刻意不互相 import，所以漂移沒有任何錯誤訊息）
2. 沒量到睡眠的夜晚，睡眠衍生的量不得進 baseline
   （含反向對照，確認那些欄位真的有被讀，否則第 2 條會假性通過）
3. baseline 窗格是日曆天不是筆數
4. `MOTIF_FAMILIES` 與夢境調色盤選項一對一，且沒有兩個家族共用關鍵字

**資料通道走 bundled asset，不走 HTTP**（已定案）：

```
garmin/data/*.json → build_app_payload.py → app/assets/data/app_payload.json
                                              ├─→ Flutter rootBundle 讀
                                              └─→ main.py 對外服務同一個檔
```

只產一份檔的理由：兩份就會有「App 顯示的跟 API 回傳的對不上」這種最難查的 bug。
之後要接 HTTP 只要實作 `sleep_repository.dart` 裡預留的 `ApiSleepRepository`。

✅ **四個畫面都接上真實資料了**：`home_screen` / `report_screen`（PR #16）/
`assistant_screen`（PR #20）/ `friends_screen` 仍是假資料（社交功能還沒做後端）。

⚠️ `assistant_screen` 的答案由 `app/lib/services/assistant_answers.dart` 產生，
它是**查表路由器不是生成器**：`_topicKeywords` 把問題分到 12 個主題，
每個主題只從 payload 取既有欄位組句。**不要在這裡加「算出來」的建議**——
那會變成第二套沒有文獻依據的評分層（紅線 4）。
問不出來的題目要老實說「我沒有這項資料」並列出真的做得到的事，
不要寫「等後端接上就有了」。

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
   ⚠️ **同一份 README 還錯第二次**（2026-08-28 複查發現）：它寫「本專案採 MIT 授權，
   詳見 LICENSE 檔」，但 repo 根目錄**沒有那個檔案**，GitHub API 的 `license` 因此是
   `null`。→ 授權看 LICENSE 檔本身，不看 README。
   **同一份文件錯兩次，就不是筆誤，是整份不能當事實來源。**
2. **遠端狀態問 git，不要問文件**——連問這份檔案都不行。
   動手前先跑 `git ls-remote --heads origin` 與
   `git fetch && git log --oneline origin/main -1`。
   ⚠️ **查外部 repo 有沒有停更，只看 `pushed_at`，不要看 `updated_at`。**
   後者被 star、被 watch、改個描述都會動。NightBloom 的 `updated_at` 是
   **2026-04-29**、`pushed_at` 是 **2024-11-02**——差 18 個月，
   中間一行程式碼都沒進來。挑錯欄位就會得出「它最近有更新」的相反結論。
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
