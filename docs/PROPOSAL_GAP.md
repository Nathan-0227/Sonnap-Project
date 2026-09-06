# Sonnap：計畫書 × 現況對照

> 建立日期：2026-08-18｜**最後逐條重驗：2026-09-06**｜撰寫者：陳泰銘（AI 與數據處理）
>
> ⚠️ **2026-09-06 全文重驗過一次。** 08-18 到 09-06 之間合併了 PR #26~#34，
> 本文原本有十餘條「現況」已經不成立（App 呼叫後端 0 個端點、release 版沒有
> INTERNET、只有一個 Lottie、report 頁整頁寫死、就寢時間兩頁不同步……）。
> 那些欄位**已直接改掉，沒有保留舊敘述**——同一份文件裡兩種說法，
> 讀的人無從判斷哪個是新的。過程記錄在 [DEVLOG.md](DEVLOG.md)。
>
> **這份文件的用途**：拿原始《Sonnap 專案計畫書》逐項對照 repo 裡**實際存在的程式碼**，
> 讓團隊與指導老師一眼看出哪些做完了、哪些沒開始、哪些卡在別的地方。
>
> **舉證原則**（沿用 [PROJECT_STATUS.md](PROJECT_STATUS.md) 的既有做法）：
> 每一條現況主張都附**檔案與行號**，可以獨立重跑查證。
> 描述功能缺口時對事不對人——開發中的專案本來就會有半成品。
>
> ⚠️ **不採信任何文件的自述，包含我們自己的**。本文所有「現況」欄位都來自
> 實際 grep 與讀碼，不是來自 README 或設計文件。這條紀律的由來見
> `PROJECT_STATUS.md` 8.2。

---

## 摘要：一句話

**方向沒有跑掉，是「量測」這條軸挖到了計畫書沒要求的深度，
而計畫書真正要驗證的「介入 → 行為改變」那條軸還沒開工。**

計畫書的論證是三段式：

```
報復性熬夜是問題（Kroese 2014）
        ↓
用情感連結 ＋ 遊戲化 ＋ 社交監督去介入
        ↓
使用者實測，驗證行為有沒有改變（D2 / D3）
```

第一段有完整文獻（`Research-Background/`）。

第二段**做了一半**：行為介入迴圈已於 2026-09-01（PR #30）端到端接通——
手機偵測就寢時刻 → `POST /nightly` → 達成度 → 挑戰進度。
但**遊戲化（經驗值／等級／貨幣／成長）與社交仍是零**。

第三段**不再有結構性阻礙**（第二節那三個都解掉了），材料已備齊
（[D2_STUDY/](D2_STUDY/)），但**尚未招募、尚未收到任何受測者資料**。

而計畫書對「量測」的全部要求只有一句話：

> 「將使用者的客觀睡眠數據**即時轉換為遊戲內的經驗值與寵物健康指標**」

前半句做到了超規格。後半句：「寵物健康指標」有了（四態心情，由 `final_quality`
決定），**「經驗值」仍然一行程式碼都沒有**。

---

## 一、計畫書 × 現況逐項對照

### 1.1 計畫書「二、專案目標」的三個子目標

| # | 計畫書寫的 | 現況 | 證據 |
|---|---|---|---|
| 1 | 開發具備 **AI 對話能力**的虛擬寵物，給予差異化且具同理心的情感回饋 | 🟡 **半成品**。有真實 LLM，但只用於**單向的夢境日記**，不是對話。App 端的問答是**查表路由器**：把問題分到 12 個主題，每個主題從 payload 取既有欄位組句 | 真 LLM：`ai/llm_client.py`（打 `api.anthropic.com`）。查表：`app/lib/services/assistant_answers.dart` 的 `_topicKeywords`。⚠️ 08-18 原記「App 端無 `http` 套件，結構上不可能呼叫 LLM」——**那條已不成立**：資料層用 `dart:io` 的 `HttpClient`（`sleep_repository.dart:89`），要接 LLM 只差後端一個 `POST /chat` |
| 2 | 建構**睡眠行為與遊戲獎懲的映射模型**，轉換為經驗值與寵物健康指標 | 🟡 **獎懲有了，數值化沒有**。「分數 → 寵物心情」四態可用；挑戰引擎（**4 個**行為挑戰）在後端跑著。但沒有經驗值、沒有貨幣、沒有成長 | 有的部分：`build_app_payload.py` `QUALITY_TO_MOOD`；`behavior/challenges.py`（463 行）＋ `GET /challenges`。沒有的部分：`xp`／`experience`／`coin`／`currency`／`achievement` 在 `app/lib/` **仍是零命中**（`level` 只命中 Garmin 的 `levelMean`／`levelMax`）。⚠️ **挑戰進度後端算好了，App 一個畫面都沒有**——`challenge` 在 `app/lib/` 唯一命中是 `user_identity.dart:9` 的一行註解 |
| 3 | 評估系統成效，透過使用者實驗探討改善睡眠拖延的實際成效 | 🔴 **尚未開始，但架構已經做得到了** | 第二節那三個結構性阻礙**已全部解除**（多使用者後端 PR #11、release 版 INTERNET ＋ HTTP 資料層 PR #28）。材料備齊於 [D2_STUDY/](D2_STUDY/)（同意書／隱私政策／招募文／前後測問卷／操作手冊）。**尚未招募、零筆受測者資料** |

### 1.2 計畫書「三、研究方法」的三個步驟

| # | 計畫書寫的 | 現況 | 證據 |
|---|---|---|---|
| 1 | **使用者需求分析**：行為調查問卷、深度訪談、App Store 負評文本分析 | 🔴 **零產出** | 全 repo（不限 `.md`）搜尋 `問卷`／`訪談`／`需求分析`／`競品`／`負評`／`questionnaire`／`interview`／`competitor` — **全部零命中**。`git ls-files` 確認 `Research-Background/` 只有 7 個檔（09-06 多了 `攝影機分數.md`），沒有被刪除的痕跡。**這是全計畫書唯一至今零產出的項目**，第四節有問卷草案可用 |
| 2 | **視覺化介面設計**：把睡眠數據轉成寵物狀態（黑眼圈深淺、精神狀態動畫、環境整潔度） | 🟡 **精神狀態動畫做完了**，黑眼圈與環境整潔度沒有 | 邏輯：`build_app_payload.py:187-212` `map_pet_mood()`，四種心情且附 `mood_reason` 可稽核。視覺：`app/assets/animations/` **四個檔都在了**（`happy`／`bored`／`tired`／`anxious`，PR #23），依心情切換，點歷史可換寵物。⚠️ 三個是從 `happy_dog.json` 腳本衍生的暫時版，等 UI/UX 給真資產直接覆蓋、程式不用改。**仍無**黑眼圈分級、無環境整潔度 |
| 3 | **使用者評估**：多名大學生安裝實測、事後訪談 | 🔴 **未開始** | 見第二節 |

### 1.3 計畫書「七、預期結果」的四個頁面

計畫書圖三～圖五描述了四個介面區塊。逐項對照：

#### 主頁面與寵物互動（圖三）

| 計畫書元素 | 現況 | 證據 |
|---|---|---|
| 頂端顯示當下時間 | ✅ 有 | `app/lib/widgets/header_card.dart:119-129` |
| 就寢倒數 | ✅ **真的在跑**，跨日邏輯正確 | `header_card.dart:81-98` `_getTimeLeftDuration()`；`:50-54` `Timer.periodic(30s)` |
| 目標就寢時間可設定 | 🟡 **能選、兩頁同步了，但仍不存檔** | 兩頁共用同一份 state：`main.dart:52` 是唯一擁有者（PR #28）。⚠️ 但那一行自己標明「**目前只存在記憶體裡，App 關掉就回到預設值**」。持久化的位置就是那裡，`KeyValueStore`（`sonnap/store`）現成可用 |
| **接近就寢時間，時間字體轉紅色** | 🔴 **仍然沒有** | 09-06 重驗：`header_card.dart` 全檔 `Colors.red`／依剩餘時間的顏色分支**零命中**。所有顏色都是編譯期常數 |
| **發出通知** | 🔴 **仍然沒有** | `app/pubspec.yaml` 相依仍只有 4 個，**無任何通知套件**。AndroidManifest 現在有 2 個 `uses-permission`（`INTERNET`、`PACKAGE_USAGE_STATS`）但**沒有 `POST_NOTIFICATIONS`**。鈴鐺開關只切換 icon 與文字。⚠️ 別裝 `flutter_local_notifications`——它會動到 linux/macos/windows 的 generated plugin 檔，本專案不出那三個平台（同 `shared_preferences` 的既定取捨）。走 MethodChannel 比照 `sonnap/store` |
| 睡眠計量條，隨最近幾天熬夜程度變動 | 🟡 **後端算好了，畫面還沒接** | streak 仍是「連續有睡眠**記錄**的夜數」，衡量的其實是配戴率（`compute_streak()` docstring 自己標明）。但真正的熬夜比率**後端已經在回了**：`adherence.late_night_ratio()`，`main.py:488`（`/home`）與 `:604`（`/insights`）都有 `late_night_ratio`／`late_nights`。**App 沒有任何地方顯示它** |
| 寵物依作息呈現疲憊／黑眼圈／生病／開心 | 🟡 **四種心情都有視覺了**，但沒有黑眼圈分級 | 同 1.2 第 2 列。四個 Lottie 齊備，`history` 30 晚實測含 happy 16／bored 6／anxious 4／tired 4 |
| 寵物透過對話框分享見聞 | 🟡 **靜態標語，非對話** | `app/lib/widgets/pet_card.dart:31-51` 有對話泡泡，但可能字串只有 4 組，寫死在 `build_app_payload.py:122-147`（Poor 與 Bad 還共用同一句） |

#### 遊戲化獎勵機制（圖三上方選單）

| 計畫書元素 | 現況 | 證據 |
|---|---|---|
| 達成睡眠目標解鎖服飾與禮物 | 🔴 **未開始** | 無任何解鎖邏輯、無獎勵資料模型 |
| 上方選單更換眼鏡／帽子／配件（Closet） | 🔴 **空殼** | `home_screen.dart:251-258` `FeatureCard` → `onTap: () => _showComingSoon("Closet")`，該函式（`:45-49`）只彈一個 SnackBar |
| Rewards | 🔴 **空殼** | `home_screen.dart:260-267`，同上 |
| 經驗值 / 等級 / 貨幣 | 🔴 **完全沒有檔案** | `xp`／`experience`／`level`／`coin`／`currency`／`point` 在 `app/lib/` 零命中（唯一的 `level` 命中是 `models/metrics.dart:62` 的 `levelMean`，那是 Garmin 加速度強度，與遊戲等級無關） |
| 成就徽章 | 🔴 **完全沒有檔案** | `achievement`／`badge` 在 `app/lib/` 零命中 |

#### 社交互動頁面（圖四）

| 計畫書元素 | 現況 | 證據 |
|---|---|---|
| 好友列表、寵物種類與當下心情 | 🔴 **四筆寫死的假資料** | `app/lib/screens/friends_screen.dart:17-74` 四筆 `const FriendPet`，連 emoji 與顏色都手填 |
| 顯示「好友睡了沒」 | 🔴 假的 | `friends_screen.dart:110-113` 唯一的「運算」是對那 4 筆假資料數數 |
| 點擊詳細查看好友寵物穿搭 | 🔴 空殼 | `friends_screen.dart:100-106` `_visitFriend()` 只彈 SnackBar |
| 後端好友支援 | 🔴 **仍是零，但基礎建設已經有了** | ⚠️ 08-18 原記「`main.py` 全 77 行只有 2 個端點、無資料庫、無 `user_id`」——**那條已完全不成立**：現在 799 行、**11 個端點**、SQLite 8 張表、暱稱制 `user_id`，CORS 是 `["GET","POST","PATCH","DELETE","OPTIONS"]`（`main.py:75`）。**但沒有任何 friends 端點、沒有 friends 表** |

⚠️ 附帶發現：`friends_screen.dart:68` 的假好友心情是 `"Sick"`，
但後端定義的合法心情只有 `happy`／`tired`／`bored`／`anxious`
（`app/lib/models/status.dart:8`）。**前端假資料與 data contract 已經對不上。**

#### 數據統計與知識頁面（圖五）

| 計畫書元素 | 現況 | 證據 |
|---|---|---|
| 過去 30 天睡眠數據視覺化 | ✅ **接了真資料** | ⚠️ 08-18 原記「整頁寫死、`StatelessWidget`」——**已不成立**（PR #16／#20）。現在是 `StatefulWidget` 吃 `SleepRepository`（`report_screen.dart:13-25`），趨勢圖、週分數、週心情都來自 payload，並在頁面上誠實標示資料來源是 `Live from backend` 還是 `Bundled with the app` |
| **熬夜比率（圖五那個 40%）** | 🟡 **後端有，畫面沒有** | `behavior/adherence.py` 的 `late_night_ratio()`；`/home` 與 `/insights` 都在回。App 端零命中——**接上去就有，是目前最便宜的補洞之一** |
| **熬夜時最常使用的前三項 App 及佔比** | 🟡 **假資料換成誠實的日彙總**，但還不是「睡前」 | 假的四筆已經拿掉（PR #28）。現在讀真的 `UsageStats`，並在卡片上寫明 `Daily totals. Not yet narrowed to the hour before bed.`（`report_screen.dart:1144`）——**不把日彙總說成睡前使用**，有測試守著。要做睡前切段，材料已經在 `queryEvents` 那條路上 |
| **強制阻斷機制**（就寢前半小時關閉特定 App） | 🔴 **仍是零程式碼** | 09-06 重驗：版控內的檔案無 accessibility service、無 `SYSTEM_ALERT_WINDOW`、無 `DevicePolicyManager`。⚠️ 查的時候要用 `git ls-files` 限定範圍——直接 `grep -r app/` 會命中 `app/build/` 的建置產物（4 個），那是 Android SDK 自己的字串，**不是我們的程式碼** |
| 睡眠知識影片或文章 | 🔴 未開始 | — |

✅ **08-18 記的那個「會誤導使用者的顯示」已經修掉了。** 當時 `report_screen.dart`
硬寫三個資料來源並全部標成綠勾「已連線」（Garmin `Last synced 22:45`、
Camera Assist `Active`、Phone Activity `Last updated 22:50`），而實際 payload 的
`data_sources` 只有 `["garmin"]`。09-06 重驗：那三行字串已不存在，改成依實際
來源顯示 `Live from backend` / `Bundled with the app`。

### 1.4 ✅ 那個「會被 demo 抓包的 bug」已修（PR #28）

08-18 記的是：`HeaderCard` 與 `SettingsScreen` 各自持有獨立的 `targetBedtime`
state，在 Settings 改完切回首頁倒數完全沒變，**同一個設定在兩個畫面顯示互相
矛盾的值，而且沒有任何錯誤訊息**。

現在 `main.dart:52` 是那兩個值的**唯一擁有者**，兩個 widget 本來就寫成受控元件
（`initial*` 參數 ＋ `onChanged` ＋ `didUpdateWidget`），所以修正**沒有動它們
內部一行**。`app/test/bedtime_sync_test.dart` 守著這件事。

⚠️ **但持久化仍然沒做**——`main.dart:50` 自己標明「目前只存在記憶體裡，
App 關掉就回到預設值」。要接儲存就接在那裡，不要在 widget 裡各自存，
那會把剛修好的問題再造一次。

### 1.5 已經超出計畫書要求的部分（誠實對照的另一面）

| 項目 | 計畫書要求 | 實際做到 |
|---|---|---|
| 睡眠評分 | 「客觀睡眠數據」（無方法要求） | Tier1/2 文獻加權（每項都有 DOI）＋ Tier3 個人化修正 ＋ SRI，**57 晚**實測（2026-05-29 ~ 09-01）。`Research-Background/Garmin手錶分數.md` 383 行 A–M 節論述。⚠️ 那 57 晚**跨 3 名配戴者**，報告寫法見 [REPORT_CAVEATS.md](REPORT_CAVEATS.md) |
| LLM 串接（C1） | 「LLM API 串接與 Prompt 測試」 | **57 晚全數由 LLM 生成、0 晚 fallback** ＋ **四道確定性驗證層**（夢境不得出現數字、建議的數字須逐字存在於事實區塊、醫療宣稱禁詞、「無記錄」意象只准用於真的沒測到的夜晚）。`PROMPT_VERSION` 已到 **v4** |
| 資料誠實性 | 未提及 | 三個欄位刻意留 `null` 而非硬湊（`motion_count`／`ambient_noise_db`／`current_activity`），並在 payload 內附 `notes` 說明原因 |
| 攝影機的文獻基礎 | 未提及 | `Research-Background/攝影機分數.md`（09-06 新增）逐節論證四個構念**目前都還不能計分**，並寫明缺什麼才能過關 |
| 回歸測試守「壞掉不會報錯」的機制 | 未提及 | 6 支 Python ＋ 12 支 Flutter 測試檔，其中多條是用「把 bug 重新引入、確認測試會紅」驗證過的 |

**C1（LLM API 串接，原訂 2026/09/24）實質上已於 2026-08-12 完成，提前約六週。**

---

## 二、D2「使用者實測」：三個結構性阻礙

計畫書 D2（原訂 2026/11/01，權重 10%）要求
**「讓多名使用者在真實生活中安裝並使用此 App」**，事後逐一訪談。

團隊已於 2026-08-18 確認：**要真的找同學裝 APK 用一到兩週**。

> ✅ **2026-09-06 更新：下面三個阻礙已全部解除。**
> 阻礙 1（單一使用者）由 PR #11 ＋ #30 解掉，阻礙 2（資料凍結）由 PR #28 解掉，
> 阻礙 3（受測者沒有裝置）由 Tier A／Tier B 分層解掉。
> **本節保留原文作為當初的分析記錄**，每一項後面加上現況。
> 現在真正卡住 D2 的只剩「還沒招募」，材料備齊於 [D2_STUDY/](D2_STUDY/)。

當時的分析，三個原因：

### 阻礙 1：整個系統假設世界上只有一個使用者　✅ 已解除

| 位置 | 08-18 當時 | 現況（09-06 重驗） |
|---|---|---|
| `app/assets/data/app_payload.json` | **一份**檔案，屬於誰不明 | 仍是一份，但只當**離線退路**；線上走 `/get-sleep-data?user_id=` |
| `/get-sleep-data` | **不接受任何參數**，永遠回同一份 | ✅ 另外 10 個端點都吃 `user_id`；資料存 SQLite 逐人分開 |
| `settings_screen.dart` 使用者名稱寫死 | 寫死 | ✅ 改吃帳號暱稱，沒有就用 `kFallbackDisplayName`（`"Sleeper"`） |
| `home_screen.dart` `username: "Jeremy"` 寫死 | 寫死隊友的名字 | ✅ 同上。⚠️ 這個 bug 是**做完帳號才看得出來**的：用「Nathan」註冊完，首頁還是說 "Good morning Jeremy" |
| `friends_screen.dart:17-74` | 四個好友寫死 | 🔴 **仍然寫死**（friends 後端沒做） |
| `friend_pet.dart` 沒有 `fromJson` | 結構上無法從 API 反序列化 | 🔴 **仍然沒有**（同上） |

→ 當時：**把 APK 發給 10 個同學，他們看到的全部是同一個人（研究者）的資料。**

✅ **現況（09-06 重驗）**：`AccountService` 走首次開啟 `POST /users` ＋ 存本機，
一支 APK 給所有人；`/get-sleep-data` 之外的 10 個端點都吃 `user_id`；
`settings_screen`／`home_screen` 的名字改由帳號提供，沒有就用 `kFallbackDisplayName`。
⚠️ **仍未解的只有 `friend_pet.dart` 沒有 `fromJson`**——因為 friends 後端根本還沒做。

### 阻礙 2：資料凍結在 build 當下　✅ 已解除

當時：`AssetSleepRepository` 走 `rootBundle` 讀打包進去的檔，使用者裝了 App
之後**看到的數字永遠不會變**；而且 release 版的 AndroidManifest 連 `INTERNET`
權限都沒有，就算改成打 API 也連不出去。

✅ **現況（09-06 重驗）**：`ApiSleepRepository`（`sleep_repository.dart:89`）已實作，
`FallbackSleepRepository` 在打不到後端時退回 asset 並**在 Insights 頁誠實標示來源**。
release 版的 `AndroidManifest.xml:9` 有 `INTERNET`，檔案裡還寫明了
「debug/profile 有而 release 沒有」是一個只在正式建置才出現的故障。

⚠️ **但 D2 有一個新的、更難發現的資料遺失風險**，見 [D2_STUDY/README.md](D2_STUDY/README.md)
開頭：就寢時刻的查詢視窗是**往回 24 小時的滑動視窗**（`lights_out.dart:180`），
而上傳是一次性的、失敗不留任何東西（`nightly_uploader.dart` 無 store／queue／retry）。
受測者早上開 App 時連不到後端，**那一晚就永久消失，隔天再開也救不回來**。
→ 發 APK 之前要先做離線上傳佇列。

### 阻礙 3：受測者沒有量測裝置　✅ 已解除（靠分層，不是靠買裝置）

計畫書經費（第四節）只編列 **1 支手環、1 台攝影機**。
當時所有睡眠資料都來自 Garmin，等於**受測者沒有任何資料可看**。

✅ **現況**：Tier A（手機自己產生的行為資料）已端到端接通並實機驗證過，
**不需要任何穿戴裝置**。受測者拿得到就寢時刻、達成度、熬夜比率、挑戰進度、
寵物心情。Tier B（生理層）維持可選。

### 解法：資料來源分兩層

```
Tier A —— 每個人都有，手機自己產生 ──── 驅動遊戲化與行為介入
    target_bedtime          使用者設定
    lights_out_at           手機最後互動時間（Android UsageStats）
    adherence_minutes       lights_out_at − target_bedtime，正值＝拖延
    prebed_app_usage        睡前 60 分鐘各 App 前景時間
    block_events            阻斷觸發／使用者強制略過

Tier B —— 有穿戴裝置的人才有 ────────── 客觀睡眠層，唯讀
    duration / efficiency / WASO / deep / rem / heart_rate
        ├─ 自備裝置的同學：Health Connect  → Tier1/2 基礎分數（0–100）
        └─ 研究者：Garmin                  → Tier1/2 ＋ Tier3 ＋ SRI
```

**關鍵：計畫書的核心機制本來就不需要穿戴裝置。**
主頁面那些東西（目標就寢時間、倒數、熬夜比率、寵物狀態）手機自己就能產生。
Kroese (2014) 對睡眠拖延的定義是
「**在沒有外在因素阻礙下，未能在預定時間上床**」——
**這個定義裡沒有睡眠品質，它是純粹的行為**，正是手機測得最準的東西。
手錶測的是拖延造成的**後果**，屬於另一個構念。

Garmin 因此從「地基」降級成「可選的客觀驗證層」。

⚠️ **這同時消掉了一個先前列為最高優先的難題**。
`PROJECT_STATUS.md` 第七節把「每個使用者都要交出 Garmin 帳密，這是隱私問題」
列為最高優先、需要全隊拍板。**那件事不存在了**——受測者不用 Garmin，
Garmin 永遠只綁研究者一人。

### 受測者也要有深睡／REM／心率／分數 → Health Connect

不用買 N 支手環，也不用外借。Android 的健康資料標準層 **Health Connect**
會把受測者**自備**裝置的資料寫進同一個介面：

| 裝置 | 寫入 Health Connect |
|---|---|
| Garmin／Samsung／Fitbit／小米（Mi Fitness）／Amazfit | ✅ |
| **Apple Watch** | ❌ 蘋果生態封閉 |

`SleepSessionRecord` 帶完整分期 **AWAKE / LIGHT / DEEP / REM** ＋ 心率。
**Tier1/2 那 100 分的五項全部拿得到 → 現有評分邏輯原封不動套用，不用重寫**：

| 指標 | 權重 | Health Connect |
|---|---|---|
| 睡眠時長 | 30 | ✅ session 總長 |
| 睡眠效率 | 25 | ✅ |
| WASO 夜間清醒 | 25 | ✅ AWAKE 分期加總 |
| 深層睡眠比例 | 10 | ✅ DEEP |
| REM 比例 | 10 | ✅ REM |

**Tier3（±12）與 SRI 拿不到，兩個原因都不是 bug：**

1. **壓力分數（±4）拿不到**——Garmin 的 Body Battery／Stress／Intensity Minutes
   是 Garmin 專有指標，**不寫進 Health Connect**
2. **一到兩週的研究，Tier3 全部處於冷啟動**（需 14–28 晚個人 baseline）；
   **SRI 也算不出來**（需 28 天窗格 ≥10 組相鄰配對——研究者自己 57 晚
   也只有一部分算得出來）

→ 這正是 `garmin/apply_recovery_modifier.py` 已經處理好的情況
（各訊號**獨立**冷啟動、非全有全無）。**不需要為此改任何評分程式碼。**

### ⚠️ 方法學紅線：跨品牌的生理指標不可互相比較

**不同品牌的睡眠分期演算法不互通**——Garmin 的 REM 20% 與 Fitbit 的 REM 20%
不是同一個東西。

這與本專案已記錄的 Czeisler (2026) SRI 問題**完全同型**
（`PROJECT_STATUS.md` 6.5：「光是計算方法不同，就足以改變死亡率、糖尿病、
心房顫動模型的結果與詮釋」），當初正是因此決定 SRI 不計分。同樣的邏輯：

- **個人內比較成立**（你這週比上週深睡多）
- **跨使用者排名不成立**（你的深睡比小明多）

⚠️ 這直接影響 `Research-Background/社交功能設計.md` 功能三
「好友平均睡眠比較」（Liu & Niederdeppe 2024）。
**拿跨品牌深睡比例排名 = `PROJECT_STATUS.md` 8.3 紅線 2 的變體。**

**安全切法：**

| | 裝置相依性 | 可否跨使用者比較 |
|---|---|---|
| **Tier A**（就寢達成率、熬夜比率） | 裝置無關 | ✅ **社交功能只能建在這上面** |
| **Tier B**（深睡／REM／心率／分數） | 裝置相依 | ❌ 只做個人內趨勢 |

### 受測者分三層

| 層 | 條件 | 拿得到 |
|---|---|---|
| L0 | 只有 Android 手機 | Tier A 行為資料 |
| L1 | 自備 Health Connect 相容裝置 | Tier A **＋ Tier1/2 完整 0–100 評分** |
| L2 | 研究者本人 | 全部 ＋ Tier3 ＋ SRI ＋ 攝影機 |

### 為什麼不用「輪流出借手錶」當主力

**關鍵事實：借手錶不會比 Health Connect 多拿到任何資料。**
Tier3 每一項都需要 14–28 晚個人 baseline，SRI 需要 28 天窗格 ≥10 組相鄰配對。
**兩週就是兩週，換誰的錶都一樣**——兩者拿到的都只有 Tier1/2 基礎分數。
要讓 Tier3 真的啟動，每人得配戴 4 週以上。

排程算術（今天 2026-08-18，學期底約 11/30 共 15 週；行為層目前是 0，
開發樂觀估 5 週；每次交接含清潔設定約 1 週）：

| 每人配戴 | 實際能測幾人 |
|---|---|
| 2 週 | **3–4 人** |
| 4 週（Tier3 才會啟動） | **2 人** |

三個實驗設計問題：

1. **時間軸不可比**：第 1 位用 9 月版 App、第 4 位用 11 月版，中間一定會改東西
   → **他們用的不是同一個產品**，資料不能合併分析。
   要避免就得凍結版本十週不改，那等於浪費十週開發時間
2. **學期效應混淆**：開學／期中考／期末週的熬夜模式差異巨大，
   而每個時期只有一個人 → 分不清「人不同」還是「時期不同」，**事後無法校正**
3. **N=3–4 能支持質性結論**（Nielsen 的經驗法則：5 人可找出約 85% 可用性問題），
   **但撐不住計畫書寫的「改善睡眠拖延行為的實際成效」**——那個 claim 需要量化

### ⚠️ 攝影機不外借（倫理問題，不是技術問題）

- 要架在同學臥室、對準床，需要他的 WiFi 設定
- **若受測者與人合住，室友也會被拍進去，而室友沒有簽同意書**
- `tapo/tapo_detector.py` 的 `cv2.imshow` 使它無法在無桌面環境執行
  （`PROJECT_STATUS.md` 3.5）→ 還要借一台整晚開著的電腦
- RTSP 帳號密碼明碼寫死在程式裡（同 3.5）

### 建議：混合設計（不是二選一）

| 角色 | 誰 | 拿到 | 支持的結論 |
|---|---|---|---|
| **主力** | 有 Health Connect 裝置的同學，同版本同時期跑滿兩週 | Tier A ＋ Tier1/2 | 量化：行為改變 |
| **深度個案** | 輪流出借研究者手錶，2–3 位 | 同上 ＋ 深度訪談 | 質性：為什麼有效／無效 |
| **縱貫基準** | 研究者本人 | **57 晚** ＋ 攝影機 ＋ Tier3 ＋ SRI | 不可替代。⚠️ 那 57 晚**跨 3 名配戴者**，可確認同一人的最長連續區段是 41 晚 |

⚠️ **Tier3 與 SRI 需四週以上才長得出來，受測者無論如何都不會有。
研究者那 57 晚本來就是全隊唯一一份縱貫資料，不需要靠外借去複製它。**

**決策規則（現在不用決定，招募問卷會告訴你）：**

- **≥6 人有 Health Connect 相容裝置** → 走主力路線，手錶用於深度個案
- **幾乎沒人有** → 輪流出借變主力，N=3–4，**研究定位改成質性**
  （可用性與接受度），並在報告中誠實說明為何無法量化

---

## 三、需要團隊拍板的事

比 `PROJECT_STATUS.md` 第七節列的少很多——因為「D2 要找同學裝 APK」
這一個決定，已經連帶解掉了多使用者與 Garmin 帳密兩個問題。

### 3.1 研究倫理與知情同意（**最高優先**）

D2 會收集同學的**手機 App 使用資料**與**睡眠生理資料**，兩者都是敏感個資。
需要：

- 知情同意書（收集什麼、存多久、誰看得到、如何退出並刪除）
- 資料保留與銷毀政策
- 確認系上／校方是否需要 IRB 或等同審查

⚠️ 這件事必須在**招募之前**完成，不能事後補。

### 3.2 平台限定 Android

兩個獨立原因，任一個都足以排除 iOS：

- 強制阻斷需要 Android Accessibility Service，**iOS 沒有等價 API**
- Apple Watch 不寫 Health Connect

→ **受測者招募必須限定 Android 使用者**，且需在招募說明寫清楚：
Health Connect 在 **Android 14+ 內建**，Android 9–13 要另外從 Play 商店安裝。

### 3.3 ⚠️ Google Play 上架政策（現在不寫下來，之後會撞牆）

Google Play 政策規定 **Accessibility API 只能用於協助身心障礙者**。
強制阻斷類 App 使用該 API **上架會被駁回**。

D2 走側載 APK 沒有這個問題。但如果專案目標包含「上架」，
就必須改用其他機制（例如 `UsageStatsManager` ＋ 提醒式覆蓋層，
不做真正的阻斷），或接受無法上架。**需要現在決定，因為它影響架構。**

### 3.4 隱私政策 URL

Health Connect 權限申請要求 App 提供對外可存取的隱私政策網址。
需要決定放在哪（GitHub Pages 即可）。

### 3.5 社交比較只能用行為指標

見第二節的方法學紅線。這會改變 `Research-Background/社交功能設計.md`
功能三的設計——**不能比深睡比例，只能比就寢達成率與熬夜比率**。

### 3.6 帳號方案建議：暱稱制免註冊

App 首次啟動產生 UUID ＋ 使用者填暱稱。**不收 email、不收密碼。**

理由：對 D2 最友善（受測者不用註冊就能開始用），隱私面最乾淨
（沒有可識別個人的欄位），也不需要做密碼儲存與重設流程。

### 3.7 兩個經費核銷面的偏離（請 PM 確認）

| 計畫書編列 | 實際使用 |
|---|---|
| ChatGPT Plus 訂閱 NT$3,200 | 實際用的是 **Claude API**（`ai/llm_client.py:47`） |
| 小米手環 9 Active NT$579 | 57 晚資料實際來自 **Garmin Vivoactive 3**（研究者自有） |

⚠️ **附帶一個要確認的事實**：小米手環 9 Active 若已購入，
它透過 Mi Fitness **支援 Health Connect** —— 那就是**第二支可用的裝置**，
會改變第二節「輪流出借」的算術（兩支可以同時借給兩位受測者）。
**請確認這支手環是否已購入、目前在誰手上。**

---

## 四、招募問卷草案（同時補掉逾期的 A1 查核點）

計畫書 A1（2026/04/01，權重 5%，「文獻探討與**競品功能分析**」）
與研究方法第 1 步（需求分析問卷／訪談／負評分析）**至今零產出**（見 1.2）。

**同一份招募問卷可以同時做兩件事**：做受測者分層，順便補上 A1 要的需求資料。

### A. 篩選與分層（決定 L0／L1）

1. 你的手機是 Android 還是 iPhone？（**iPhone 者無法參與**，需說明原因）
2. Android 版本？（14 以上／9–13／不知道）
3. 你有沒有智慧手錶或手環？型號是？
   （Garmin／Samsung Galaxy Watch／Fitbit／小米手環／Amazfit／Apple Watch／沒有）
4. 你戴著睡覺嗎？一週大約幾天？

### B. 報復性熬夜（對應 Kroese 2014，`Research-Background/Home_Page_Design.md` 第 1 節）

5. 你有沒有「明明想睡了，卻捨不得放下手機」的經驗？頻率？
6. 平常打算幾點睡？實際大約幾點真的放下手機？
7. 熬夜的主要原因？（複選：追劇／社群／遊戲／課業／聊天／說不上來）

### C. 睡前手機使用（對應計畫書「熬夜時最常使用的前三項 App」）

8. 睡前一小時最常用的三個 App？
9. 你會不會希望有東西在就寢時間提醒或擋住你？
   **溫和提醒** vs **強制阻斷** 你偏好哪一種？
   （⚠️ 計畫書第二節明說使用者對強制阻斷「容易引發反感與抵抗心理」——
   這題正是要驗證那個前提）

### D. 競品與需求（對應 A1）

10. 你用過哪些睡眠 App？為什麼停用？
11. 對「養虛擬寵物來改善作息」這件事的接受度？
12. 願不願意讓好友看到你的睡眠狀態？（對應社交功能的可行性）

### E. 參與意願

13. 是否願意參與為期兩週的實測？
14. 是否願意接受事後訪談（約 30 分鐘）？

⚠️ **第 12 題很關鍵**：`Research-Background/社交功能設計.md` 的四個功能
全部建立在「使用者願意公開睡眠狀態」這個**從未驗證過的假設**上。
如果多數人不願意，那一整塊設計要重新考慮。

---

## 五、計畫書查核點對照

> 團隊已確認這是課程專題，日期為參考而非硬期限。此表用於掌握全局，不是進度考核。

| 查核點 | 原訂日期 | 權重 | 現況 |
|---|---|---|---|
| A1 文獻探討與競品功能分析 | 2026/04/01 | 5% | 🟡 **睡眠文獻極完整**（`Garmin手錶分數.md` 383 行逐項 DOI，09-06 再加 `攝影機分數.md`），**但競品分析與需求調查仍是零產出**（見 1.2）。第四節那份問卷可補。**這是全計畫書唯一至今零產出的項目** |
| A2 UI/UX 介面設計與原型製作 | 2026/05/16 | 10% | ✅ 五個頁面切版完成 |
| B1 前端 APP 介面切版與邏輯 | 2026/07/01 | 15% | 🟡 切版完成；**五頁中四頁接了真資料**（Home／Insights／Assistant／Settings），只剩 `friends_screen` 全寫死。⚠️ 08-18 記的「只有 Home」已不成立 |
| B2 後端資料庫與睡眠監測實作 | 2026/09/01 | 20% | ✅ **完成**。⚠️ 08-18 記的「`main.py` 是一支唯讀的靜態檔案伺服器、無 DB driver」**已完全不成立**：799 行、11 個端點、SQLite 8 張表（標準庫 `sqlite3`）、欄位遷移機制、暱稱制多使用者。睡眠監測仍是超額完成 |
| C1 LLM API 串接與 Prompt 測試 | 2026/09/24 | 15% | ✅ **提前約六週完成**（2026-08-12），含四道確定性驗證；57 晚全數 LLM 生成、0 晚 fallback。⚠️ 計畫書目標一要的是**對話**，這一項交付的是單向生成，見 1.1 第 1 列 |
| C2 遊戲化數值與社交功能開發 | 2026/10/16 | 15% | 🟡 **行為挑戰做完了，遊戲化數值與社交仍是零**。有的：`behavior/`（5 個檔 1114 行）**4 個**行為挑戰 ＋ 達成度 ＋ 行為版睡眠效率 ＋ 寵物狀態，端到端接通並實機驗證。沒有的：經驗值／等級／貨幣／成長／Closet／Rewards／成就／好友後端 |
| D1 系統整合測試與除錯 | 2026/10/01 | 5% | 🟡 **回歸測試有了，整合測試沒有**。6 支 Python ＋ 12 支 Flutter 測試檔，多條用「把 bug 重新引入、確認測試會紅」驗證過。但沒有跨模組的端到端自動化測試 |
| D2 使用者實測與數據收集 | 2026/11/01 | 10% | 🟡 **架構就緒、材料備齊、尚未招募**。三個結構性阻礙已全部解除（見第二節）。同意書／隱私政策／招募文／前後測問卷／操作手冊在 [D2_STUDY/](D2_STUDY/)。**零筆受測者資料** |
| D3 數據分析與結案報告撰寫 | 2026/11/30 | 5% | 🔴 未開始 |

⚠️ 附帶一提，計畫書甘特圖本身有一處順序矛盾：
**D1（系統整合測試，10/01）排在 C2（遊戲化與社交開發，10/16）之前**——
要測的模組那時還沒寫完。若日後需要重排時程，這一點可以順便修正。

---

## 六、08-18 那一輪做完了什麼（歷史記錄）

分支 `feature/behavior-loop`，三項**全部完成並合併**（PR #11）：
本文件、後端多使用者 ＋ 持久化（SQLite、`user_id`、Health Connect adapter）、
行為介入迴圈（就寢達成度、挑戰引擎、Tier A 驅動的寵物狀態）。

當時列為「不在本輪範圍」的四項，後續進度：

| 當時排除的 | 現況 |
|---|---|
| Android platform channel — UsageStats | ✅ 完成（PR #30）。`UsageStatsService.kt` ＋ `sonnap/usage` |
| Android platform channel — 通知／Accessibility | 🔴 仍未開始 |
| Health Connect 的 Flutter 串接 | 🔴 仍未開始（Python 端的 adapter 早就好了） |
| 任何 `app/` 的改動 | ✅ 已解除限制（PR #16／#20／#23／#28／#30） |
| 部署 | 🔴 仍未開始，且 D2 走區網不走公網（API 沒有認證） |

⚠️ 架構紅線（`PROJECT_STATUS.md` 8.7）在新架構下**從「靠紀律守住」變成
「結構上不可能違反」**：行為層完全建立在 Tier A 上，
`garmin/evaluate_sleep_quality.py` 與 `garmin/apply_recovery_modifier.py`
根本不在那條路徑上。

⚠️ **本文原本寫的驗收指令是錯的**，會永遠誤報。
`grep -r "evaluate_sleep_quality\|apply_recovery_modifier" behavior/` 現在有 7 個命中，
但那**全部是說明這條規則本身的註解**（`behavior/__init__.py`、`adherence.py` 的檔頭）
加上兩個 `.pyc`。**一個會固定誤報的驗收，等於沒有驗收**——看到的人只會學會忽略它。

正確的指令只看 import 行，記在 `behavior/__init__.py:18`：

```bash
grep -rnE "^[[:space:]]*(import|from)[[:space:]]+.*(evaluate_sleep_quality|apply_recovery_modifier|garmin)" behavior/
```

2026-09-06 實測：**0 結果，紅線守住**。
