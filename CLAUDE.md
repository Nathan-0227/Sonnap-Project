# Sonnap 專案背景（給 Claude Code）

## 📖 這份檔案怎麼讀

| 這裡有什麼 | 這裡沒有什麼 |
|---|---|
| **現行的規則、語意、下一步** | 逐輪的過程記錄 → [DEVLOG.md](docs/DEVLOG.md) |
| 動評分／遊戲化之前必讀的紅線 | 「當初為什麼這樣決定」的完整推理 → [DEVLOG.md](docs/DEVLOG.md) |

> ⚠️ **這份檔案只寫現在為真的事。** 發現哪一段過期了，請**改掉或刪掉**，
> 不要在旁邊加一句「這段已過期」——同一份檔案裡的兩種說法，讀的人無從判斷哪個新，
> 而警語只在讀者剛好讀到警語時有效。過程記錄要留就留進 [DEVLOG.md](docs/DEVLOG.md)。
>
> （2026-08-26 拆分。拆分前這裡有 1016 行，其中「`main.py` 仍回傳寫死 mock_data」
> 這種**早已完成卻還寫著「尚未完成」**的段落至少兩處。）

## 專案是什麼

Sonnap 是結合「睡眠監測」與「AI 寵物陪伴」的 App。攝影機/穿戴裝置偵測使用者睡眠狀態，
轉換成虛擬寵物的心情與活動，並用 AI（**Claude API**，見 `ai/llm_client.py`）寫「寵物 notes」（每晚的總結＋從有出處的清單挑的建議；2026-11-17 起取代夢境日記）。詳見 [README.md](README.md)。

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

## 🔖 交接區：現在在哪、下一步做什麼（2026-10-03 更新．新對話先讀這段）

### 現在在哪：Tier A 行為迴圈已經通了

```
手機事件流 → lights_out_at → POST /nightly → nightly_behavior
                                                 ↓
                                   挑戰進度、熬夜比率、寵物狀態
```

`nightly_behavior` 從 08-26（PR #11）就有端點、有測試、有挑戰邏輯，
但**一直沒有任何東西寫進去**。2026-09-03 接上了來源，實機實測：

```
LightsOut[unlock] ok at=2026-09-02 02:39:18 quiet=329m
NightlyUpload: ok date=2026-09-02 adherence=189m late=true
→ GET /challenges："Lights out on time" recorded_nights 1
→ bedtime_spread_minutes 36.0（「作息收斂」挑戰第一次有真實資料）
```

（這一段由 PR #30 帶進來。過程記錄——包含三個只有實機看得到的錯——見
[DEVLOG.md](docs/DEVLOG.md) 2026-09-02~03 那則。）

### ⚠️ 就寢時刻偵測的四條規則（`app/lib/services/lights_out.dart`）

這四條都是**實機才看得到**的——單元測試全綠、畫面顯示「偵測不到就寢時刻」
看起來完全正常，其實是錯的。改那個檔案之前逐條確認。（規則 4 的測試在 `app/test/lights_out_brief_unlock_test.dart`，三種破壞方式都驗證過會紅）

| 規則 | 不遵守的後果 |
|---|---|
| **解鎖（`keyguard_hidden`）才算互動，螢幕亮不算** | 通知整夜點亮螢幕，把安靜期切成碎片。實測那一夜 `KEYGUARD_HIDDEN` 是 0 次但 `SCREEN_INTERACTIVE` 14 次，最長安靜期從 249 分鐘掉到 148 分鐘 |
| **`keyguard_shown` 沒配對也算，`screen_off` 沒配對不算** | 就寢時刻常常正好是事件流的**第一筆**（前面沒有解鎖可配對），一律丟掉就會丟掉唯一正確的答案 |
| **只認兩段使用之間的空隙，頭尾都不算** | 視窗結尾是「現在」，那段安靜還沒結束卻幾乎一定最長，會蓋掉真的那一段 |
| **（2026-11-15 加）找不到 ≥3 小時的安靜期時，可以跨過半夜 < 30 秒的短解鎖**——只在原本的規則失敗時才用；相隔 < 10 秒的紀錄先併成一次使用（一次解鎖＝screen_off＋0.7 秒後 keyguard_shown）；可跨任意次、跨完仍要 ≥3 小時；有好幾段時挑**跨最少次**的、同次數挑最長；只用在 unlock 模式；跨了幾次存在 `nightly_behavior.bridged_unlocks`（NULL＝舊資料，只供分析不顯示）。⚠️ **30 秒是設計決策、沒有文獻**（同 3 小時） | 半夜解鎖 4 秒看時間就讓整晚偵測不到。實例 11-12：05:43 放下、07:20 看 4 秒、09:28 起床 → 97＋128 分鐘，兩段都不到 3 小時。挑最長而不是跨最少次的話，睡前 5 秒看鬧鐘也會被跨過去、就寢時刻往前移 |

### ⚠️ 第 5 條：**手機挑錯的時候由後端用手錶改正**（2026-11-16 使用者定）

前四條都在手機裡，而手機挑的是**最長**的那一段安靜期——半夜起來用幾分鐘手機
就會把一晚切成兩段，後面那段通常比較長。11-16 實例：00:49 放下（手錶 00:56 入睡）、
02:18 醒來用 5 分 3 秒、02:23 再睡 → 兩段是 88.4 與 218.8 分鐘 → 挑到 02:23，
記成**熬夜 98.6 分鐘**（實際晚 4.9 分鐘）。清點：44 個同時有兩種訊號的夜晚裡
**17 晚**的 `lights_out_at` 晚於手錶入睡，8 晚晚超過 30 分鐘，**全部被記成熬夜**。

**放下手機不可能發生在睡著之後**，但裁判（手錶的入睡時刻）只有後端拿得到。
所以手機把**所有** >=60 分鐘的安靜期一起送上來（`quiet_candidates`，最多 10 段），
後端在**早晨匯入寫完手錶之後**重挑（`resolve_lights_out.py`，判準在
`behavior/lights_out_resolve.py`）。

| 規則 | 不遵守的後果 |
|---|---|
| **手機端的挑選規則一個字都不改**，候選是額外附上的材料 | 手機身上沒有裁判，在那裡加判斷就是第二套沒有依據的規則 |
| 刷掉「起點晚於手錶入睡 + **30 分鐘**」的候選，剩下的挑**最晚**那一段 | 就寢時刻是「睡前最後一次使用」；挑最早的話，睡前 5 秒看鬧鐘也會被當成就寢（同規則 4 挑「跨最少次」的理由） |
| ⚠️ **30 分鐘是設計決策、沒有文獻**（同 3 小時、30 秒，屬偵測層）。取 30 是**刻意放過「滑手機滑到睡著」**那個不同的現象（09-11 +12、11-08 +9.1） | 那個現象使用者 10-22 已決定改用 `USER_INTERACTION` 解。一條規則同時修兩個現象，兩個都查不清楚 |
| **沒有手錶、沒有候選（舊版 App）、挑中的落在別的 `night_date`** → 三種都原樣不動 | 沒有證據就不要動；夜晚日期由 `lights_out_at` 決定，換了日期連上床按鈕都配錯 |
| 有手錶但**一段都沒過關** → `adherence_minutes` 與 `is_late` 存 **NULL**，`lights_out_at` 留著 | 繼續顯示「熬夜 461 分鐘」是假話。時刻本身仍是「最後一次碰手機」這個量測事實 |
| **可以重複執行**：每次都從候選重挑，不是在改過的值上再改 | App 重送同一晚會把時刻覆寫回手機挑的那個，隔天早上要能再挑一次 |

⚠️ **救不回來的夜晚**：Android 只保留約 24 小時的事件，所以 11-16 以外那幾晚的
候選早就沒了，只能標成「不知道」。11-16 的原始事件存在
`sonnap-data/lights-out-evidence/`，也是 `app/test/fixtures/` 那份測資的來源。

⚠️ **事件量比想像大：實機 24 小時 4057 筆**（三星 One UI）。原生端的 `limit`
訂太小會把視窗砍掉一半，而且丟的是**舊的**那半——正好是昨晚睡覺那段。

⚠️ **不需要背景服務，也不能在半夜跑。** `queryEvents()` 讀的是 Android 自己的
歷史（實測保留 **≥5 天**），早上開 App 就回推得到昨晚；而演算法要求那段安靜
**已經結束**，半夜跑的時候人還在睡，結構上得不到答案。

### ⚠️ 達成度只在後端算

`adherence_minutes` / `is_late` 一律來自 `POST /nightly` 的回應，畫面上標著
"from backend"。跨午夜正規化寫在 `behavior/adherence.py`——目標 23:30、
實際 02:39，直覺相減會得到「提早 20 小時 51 分」而不是「晚了 189 分鐘」。
**在 Dart 重算就有第二個定義處，兩份漂移時不會有任何錯誤訊息**，
與「不要在 Dart 從 `final_quality` 推 `pet_mood`」是同一條紀律。

`app/test/usage_stats_test.dart` 有兩條互為反面的測試守著：沒有後端回應時
不得出現任何達成度措辭；有回應時必須照抄它的數字。

### ⚠️ App 的身分有兩條路，建置參數優先

| 實作 | 身分從哪來 | 一支 APK |
|---|---|---|
| `BuildTimeUserIdentity` | `--dart-define=SONNAP_USER_ID` | = 一個人。demo 用，**本人那支手機也是走這條**（手機上沒存帳號，見下方「IP 每次都不一樣」那節） |
| `AccountService` | 首次開啟 `POST /users`，存本機 | 給所有人。D2 用 |

測試用的 id 由 `migrate_garmin_to_db.py` 的 `RESEARCHER_USER_ID` 產生。

⚠️ **`user_id` 本身就是憑證**（免註冊、無密碼）。不要印進 logcat（裝了 adb
就讀得到）、不要放進會外流的檔案。註冊畫面**不得出現「安全」「加密」字眼**
（有測試守著）——那會讓畫面與同意書自相矛盾。上架前要補認證。

⚠️ **建不了帳號絕對不能擋住 App。** 後端沒開是 demo 的常態。跳過**不寫進儲存**：
最常見的原因是暫時連不到後端，記成永久決定的話之後永遠不會被問第二次。

⚠️ 本機儲存走 `sonnap/store` MethodChannel 包 Android SharedPreferences，
**刻意不裝 `shared_preferences`**——那會連帶動到 linux/macos/windows 三個平台的
generated plugin 檔，而這個專案不出那三個平台。同一個取捨見
`ApiSleepRepository` 用 `dart:io` 而不裝 `package:http`。

### ⚠️ 不要拿任何人的名字當佔位符

`home` / `settings` / `assistant` 三個畫面原本各自寫死 `"Jeremy"`（隊友的名字）。
帳號做完之後才看得出來：用「Nathan」註冊完，首頁還是說「Good morning Jeremy」。
現在有帳號就用帳號的暱稱，沒有就用 `kFallbackDisplayName`（`"Sleeper"`）。

### ✅ 手機連後端：CORS / 綁定 / 防火牆都就緒

| 項目 | 狀態 |
|---|---|
| CORS | ✅ 已經是 `["GET", "POST", "PATCH", "DELETE", "OPTIONS"]` |
| 綁 `0.0.0.0` | ✅ `uvicorn main:app --host 0.0.0.0 --port 8000` 實測可用 |
| Windows 防火牆 | ✅ 手機連得到（2026-09-13 從手機實測）。⚠️ 但**不是靠** `Sonnap venv python (demo)` 那條規則，見下 |

### 🔴 IP 每次都不一樣，而且它是**編譯期**參數

三輪實測分別是 `192.168.1.75`、`192.168.1.104`、`10.91.117.92`（最後那次是
電腦連手機熱點）。`SONNAP_API_BASE` 用 `--dart-define` 帶入，**IP 一變就要重建 APK**：

```bash
flutter build apk --debug \
  --dart-define=SONNAP_API_BASE=http://<當下的IP>:8000 \
  --dart-define=SONNAP_USER_ID=<手機帳號的 id>   # 🔴 裝到本人手機一定要帶，見下
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

🔴 **裝到本人那支手機的 APK 一定要帶 `SONNAP_USER_ID`。** 那支手機上**沒有存帳號**
（`sonnap_store.xml` 裡沒有 `user_id` 鍵，2026-11-20 實測），一直是靠建置參數認人的。
漏帶的話 App 不會報錯：助理每一題都說
「cannot be reached right now」、上傳與衣櫃全部對不到帳號——看起來像後端壞了，其實是 App 不知道你是誰
（2026-11-20 連續幾支 APK 都漏帶，踩到）。⚠️ 這時 App 若跳出要填暱稱，**不要填**：那會建一個全新的空帳號，跟原本的資料分開。

id 不要手打、也不要印出來（它就是憑證）：從資料庫找手機帳號、只寫進暫存檔，建置時用 `$(cat 檔案)` 帶進去：

```bash
SONNAP_DB_URL=mysql://root@localhost/sonnap python -c "import db; uid, info = db.resolve_phone_account(); open('<暫存資料夾>/phone_uid.txt','w').write(uid); print(info['reason'], info['nights'])"
flutter build apk --debug --dart-define=SONNAP_API_BASE=http://<當下的IP>:8000 \
  --dart-define=SONNAP_USER_ID=$(cat <暫存資料夾>/phone_uid.txt)
```

驗收：設定頁「Data」寫「Last night sent」（上傳要帶 id 才會成功）；logcat 有 `NightlyUpload: ok`。
⚠️ **不要拿首頁的「Hi, Sleeper!」判斷漏帶 id。** 2026-11-21 前建置參數那條路**從來不拿暱稱**，帶了 id 也一律是 Sleeper；
現在改成打開時向後端 `GET /users/{id}` 要一次、記在手機上（`AccountService.refreshBuildTimeName`），
所以後端連不到、又從沒連到過的時候**仍然是 Sleeper**——那代表沒連到後端，不代表沒帶 id。

→ **demo 當天要當場查 IP、當場重建。** 連不上不會壞——會退回打包的資料
並在 Insights 頁如實標示「Bundled with the app / Backend unreachable」。

⚠️ **不要用 `192.168.56.1`**，那是 VirtualBox 的 host-only 介面，手機連不到。

⚠️ **防火牆認的是「實際開著 8000 埠的那支程式」，而那支不是 venv 的 python.exe。**
（2026-09-13 實測）Windows 上 `.venv\Scripts\python.exe` 只是轉介程式，
它會再叫出**系統 Python** 來跑，真正開埠的是後者：

| | 路徑 |
|---|---|
| 開著 8000 埠的程式 | `...\AppData\Local\Programs\Python\Python313\python.exe` |
| 它的上一層（轉介） | `Sonnap-Project\.venv\Scripts\python.exe` |
| `Sonnap venv python (demo)` 放行的 | `Sonnap-Project\.venv\Scripts\python.exe` ← **對不上** |

實測：把 `Sonnap venv python (demo)` **停用之後，手機照樣連得到**
（`adb shell curl http://<IP>:8000/health` 回 `status: ok`），測完已恢復啟用。
所以舊版這裡寫的兩句都不成立：「換了 venv 規則就失效」、
「原本擋住的是系統 Python 規則與 venv 路徑對不上」。

真正放行系統 Python 的是四條名叫 `python.exe` 的規則（Private／Public × TCP／UDP，
不限埠）。內部名稱開頭是 `TCP Query User`／`UDP Query User`——那是**某次 Python
第一次開埠時，Windows 跳出「允許存取」視窗、有人按了允許**才產生的，不是專案加的。
熱點連線被 Windows 當成 **Public** 網路（同日實測），所以要有 Public 的規則才連得進來。

⚠️ **沒驗到的一點**：反向實驗「停用系統 Python 的規則後，手機就連不到」**沒有做**
（停用那條規則的動作被 Claude Code 的安全機制擋下）。機器上另有 10 條不限程式的
放行規則（Teams、Game Bar、Microsoft Store 等 App 的），推測只管各自的 App，但沒有驗證。
要驗的話：系統管理員 PowerShell 停用那條 Public TCP 的 `python.exe` 規則 → 從手機測 → 再啟用。

→ **手機連不上、懷疑是防火牆時**，查的是「開埠那支程式」有沒有規則，不是查 venv 那條：

```powershell
$exe = (Get-NetTCPConnection -LocalPort 8000 -State Listen |
  ForEach-Object { Get-CimInstance Win32_Process -Filter "ProcessId=$($_.OwningProcess)" }).ExecutablePath
Get-NetFirewallApplicationFilter | Where-Object { $_.Program -eq $exe } |
  Get-NetFirewallRule | Select-Object DisplayName, Enabled, Action, Profile
```

demo 結束後：

```powershell
Remove-NetFirewallRule -DisplayName "Sonnap venv python (demo)"   # 對連線沒有作用，留著只是雜訊
```

⚠️ **拿掉上面那條並不會把門關上。** 系統 Python 那四條放行的是
**這台電腦上任何 Python 程式、任何埠，連公用網路也算**。要真的收起來得處理那四條，
但它們不是專案加的、可能有別的用途，**刪不刪由使用者決定**，不要代刪。

⚠️ **驗證只能從手機做**。「本機用區網 IP 打得開」不等於手機打得開——
同一台機器發往自己區網 IP 的封包**不經過防火牆**，09-01 那次就是這樣
差點誤判成「已經通了」。以後任何一次「手機連得到嗎」都要從手機開網址
（或 `adb shell curl`），不要用電腦上的 `curl` 代替。

⚠️ **在家裡通不代表在現場通**：不少學校/公共 Wi-Fi 開了 client isolation，
會直接擋掉手機↔筆電，與防火牆無關、這邊也修不了。
**09-09 的進度查核前務必在現場再測一次。**
（09-03 那次是把電腦連上手機熱點才通的——那也是現場可用的備案。）

⚠️ 這個 API **沒有認證**（`user_id` 本身就是憑證），而放行它的規則
（系統 Python 那四條）掛在 Public 設定檔上，代表在外面的網路也生效。D2 側載那個情境可接受，但不要長期開著。

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

### ⚠️ 在 `wearable_nightly` 加欄位請照**五處**盤點

文件曾經寫「要補是三處」，實際是五處。多出來的兩處是 `db.py` 的
`upsert_wearable_nightly` 欄位白名單（會拋 `ValueError`，跑一次就發現）
與 `wearable/healthconnect_adapter.py` 的 `to_wearable_row`
（**不會報錯**——不補的話只有 Health Connect 來源的使用者缺值、
Garmin 來源有值，那種「只在一種來源下缺資料」的 bug 最難查）。

（08-28 那一輪九個 commit 的逐項實測數字見 [DEVLOG.md](docs/DEVLOG.md)。）

### ⚠️ 同一晚兩個來源：**Garmin 優先**（2026-09-13 使用者決定）

`wearable_nightly` 的主鍵是（帳號, 日期），一晚只能留一列。實機上 Garmin 與
Health Connect 常是**同一支錶**（Garmin Connect 會同步進 Health Connect），
不定規則的話分數會跟著「誰最後送」跳動（09-11：Garmin 69.8、Health Connect 75.9），
而且沒有任何錯誤訊息。

| 寫入路徑 | 那一晚已經是 | 做什麼 |
|---|---|---|
| `POST /wearable`（Health Connect） | `garmin` | **不寫，回 409**；App 記成送過、不重送 |
| `POST /wearable` | `health_connect` 或沒有 | 照常寫（手錶補完整的一段要能更新） |
| `migrate_garmin_to_db.py` | `health_connect` | **蓋掉**，並印出蓋了哪幾晚 |

留 Garmin 的理由：它有戴錶者分段與 Tier3 個人化修正；Health Connect 來源的 Tier3 一律是 0。
⚠️ 規則寫在**兩個**寫入路徑裡（`main.py` 與匯入腳本），改一邊要改另一邊——
`test_api.py` 與 `test_migrate_accounts.py` 各守一邊。

### ⏭️ 這一輪之後，還沒做的

| 事情 | 卡在誰 |
|---|---|
| **換 RTSP／MySQL 密碼**（見上方 🔴） | 影像組。**移除檔案不等於止血** |
| **TAPO 的 8 個問題**（門檻沒記錄、`video_events` 被丟棄、連續翻身不進 timeline、`MOTION_MICRO` 太靈敏…） | 影像組。清單與偵測層規格見 **[TAPO_HANDOFF.md](docs/TAPO_HANDOFF.md)**，每一條都可用 `python inspect_tapo_score.py` 重現。⚠️ **調 `.env` 救不回歷史資料**：實測 99.3% 的 micro_motion 強度低於現行 `MOTION_MICRO`，那批資料是用另一組沒記錄的門檻寫的 |
| ~~`SLEEP_START=01:00` 太晚~~ | ✅ **已改成 `22:00`**（2026-09-04）。57 晚實測：01:00 錄不到 7 晚（12%），22:00 涵蓋 57/57、只多錄 3 小時，再往前沒有額外好處。改了 `.env`／`.env.example`／程式預設三處。長期仍朝「App 點開始睡眠」走（那對 D2 受測者才通用） |
| id 117（08-19）`total_events=73` 但 `timeline=[]` | ⚠️ **2026-09-04 追過：不是程式 bug。** 解析、截斷、兩條寫入路徑全部排除，且所有存檔點都有 `if sleep_timeline:` 保護。`updated_at` 晚 5.5 小時而計數保留 → 最可能是有人在 phpMyAdmin 手動清掉。我方已加 `count_mismatch` 防護（測試【6】） |
| ⚠️ **睡眠效率 11-07 恢復計分（三段式）**——09-17 發現門檻套錯量、10-01 停止計分、11-07 使用者決定恢復 | 我方。有按按鈕的夜晚用按鈕算，沒按的退回手錶效率（幾乎都拿滿）。**沒按的夜晚平均比兩個都按的高 8.5 分**，使用者看過數字後接受。詳見下方「睡眠效率：2026-11-07 起三段式計分」與 `Garmin手錶分數.md` B-7。回到「只靠量測」要等攝影機人形偵測（`TAPO_HANDOFF.md`） |
| 🔴 **每晚要按「開始／結束睡覺」** | 使用者。**這不是為了現在計分**（現在不計分），是為了**驗證攝影機的上床偵測**——按鈕時刻是那個偵測器唯一的 ground truth 標籤。驗收需要 ≥10 個有按鈕的夜晚，不按就永遠驗不了 |
| ✅ **WASO：以手錶原始值計分，不校正**（10-22 使用者決定） | 使用者決定：**照手錶的值計分、App 分數卡不掛 WASO 警語、報告留一句**（`REPORT_CAVEATS.md` 第 11 節）。試算：+13.3 分鐘的偏差會讓約 **10 / 89 晚低一個等級**，方向只會偏低。PSG 對照不追，「哪天有人剛好要做睡眠檢查再順便戴錶」。⚠️ `score_claim.SCORED_COMPONENT_CAVEATS` 刻意沒有 waso，**不是漏掉**。以下是 10-01 的查證內容，仍然成立： | 我方。年齡趨勢**有兩份獨立文獻互證**（Ohayon 2004 +10 分/十年、Boulos 2019 +9.7 分/十年）→ 分齡設計站得住。但 Lee 2025 匯總裝置偏差 **+13.3 分**（非 Fitbit +24.1，CI 15.7–32.5）**整段跨過一整級**（級距寬 15 分）；而改成個人內比較也不行——**個人內 MAD 只有 2–5 分，比裝置誤差小 3~10 倍**。⚠️ 但 WASO 與效率是**不同性質**：效率是構念錯配（修不好），WASO 是量測誤差（驗證得出來），且實測仍有鑑別力（三級都用到、標準差 6.6）。**處置：維持現狀計分 + 誠實標註**，詳見 `Garmin手錶分數.md` E-3～E-6 |
| ✅ ~~要不要縮減 Tier1 的維度~~ → **改宣稱不改結構**（10-01 決定） | 使用者決定：**分數誠實宣稱「以睡眠時長為主」**，不是多維度等權合成。依據是四項裡只有 duration 的裝置誤差明確小於級距（**14%** vs WASO 的 89–161%，deep/rem 量級查不到）——**關鍵是級距寬度差了 8 倍**（120 / 15 / 42 / 21 分）。WASO **保留計分**（唯一代表睡眠連續性的項目、實測有鑑別力、缺陷是可驗證的量測誤差而非構念錯配）。WASO 的警語 10-22 起拿掉（見上一列），深睡／REM 的保留。結構、配分、程式一個都沒動，詳見 `Garmin手錶分數.md` I-0 |
| 🔴 **需要一次效標驗證** | 我方／影像組。本專案的 **Vivoactive 3 對照 PSG 或第二參考標準**，量出「WASO 的偏差與每夜隨機誤差各幾分鐘」。那是解開 WASO 門檻的唯一鑰匙（條件寫在 E-6）。⚠️ 我們的機型**不在** Lee 2025 的樣本裡（那是 Vivosmart 3/4、Fenix 5S），所以不能直接引用它的數字當自己的 |

**刻意不做**：

| 事情 | 理由 |
|---|---|
| 背景排程（WorkManager）每天自動上傳 | 事件保留 ≥5 天，「忘記開 App」有很大容錯；而三星會殺背景、各家 ROM 不同 |
| D2 實測 | 見路線圖 |

（睡前 60 分鐘的 App 歸因、遊戲化、Accessibility 阻斷、Health Connect、好友社交
都已經做了，見下方「產品迴圈」。）

### ⚠️ Flutter 端解析 payload 的時間一律走 `parseWallClock()`

`app/lib/models/wall_clock.dart`。理由：`DateTime.tryParse("...+08:00")`
回傳的是 **UTC**，`.hour` 因此早 8 小時（22:32 顯示成 14:32）。
這個 bug 曾經在 `main` 上、使用者看得到，首頁與 Insights 圖表都中招。

⚠️ **不要用 `.toLocal()`**——那會跟著手機時區跑，而這些是已經記錄下來的事實，
要的是字串裡那個 `+08:00` 的牆鐘時間。

### ⚠️ 沒量到睡眠的夜晚不得進 baseline

`total_sleep_minutes = 0` 時手錶根本沒偵測到睡眠，但那一列**照樣帶著
`avg_heart_rate`**——量的是清醒時段。`wearer_a` 真正睡眠夜的 avgHR 是 52–58，
這些無效列上是 85 / 88 / 90 / 95。89 列 summary 裡有 **38 列**是這種。

`compute_modifiers()` 的 `has_measured_sleep()` **分辨構念層級而不是整列丟掉**：

| 欄位 | 無效夜晚 | 理由 |
|---|---|---|
| `avg_heart_rate`、`awake_count`、`sleep_segment_count`、`presleep_stress_score` | ❌ 排除 | 全由睡眠期推導，沒有睡眠期就沒有這些量 |
| `resting_heart_rate`（每日單一數字）、`steps_total`（白天的量） | ✅ 保留 | 不是從睡眠期算出來的 |

⚠️ `has_measured_sleep()` 與 `extract_sleep_features.is_valid_night()`
**刻意不互相 import**，所以判準漂移時沒有任何錯誤訊息——
`tests/test_scoring_guards.py` 第 1 條就是在守這件事。
**兩支各有一份判準，改一邊就要改另一邊**（實測只改一邊，第 1 條會紅）。

⚠️ **判準第四條：階段時長不得超出睡眠視窗**（`MAX_SLEEP_OVER_PERIOD_MINUTES = 1.0`，
2026-09-30 新增）。Garmin 偶爾會回傳自相矛盾的一列——實測 2026-06-27 階段秒數
合計 688 分鐘，但它自己給的入睡→起床視窗只有 447.9 分鐘。**這是上游資料問題，
不是解析錯誤**（原始回傳即為 deep 17400s + light 23880s + REM 0）。

在加這條之前，效率算出 153.62% 後被 `min(…, 100.0)` **靜默夾平成 100%**，
於是一列完全不可信的資料（REM=0、深睡佔 42%）照樣拿滿睡眠效率那 25 分。
容差 1 分鐘有依據：Garmin 階段時長量化到整分鐘（實測 276 筆 `*_duration_sec`
全為 60 的倍數），視窗由秒級時刻相減，故 1 分鐘內的落差屬量化誤差。
⚠️ **不可調得更嚴**：實測有 16 晚總睡眠正好等於視窗（真實的 100.00%，
Garmin 回報那幾晚睡眠期間內零清醒），那些不是壞資料，不能誤殺。

⚠️ `build_sleep_timeline()`（SRI）**本來就有**自己的檢查，不受影響。

現行路線圖：`C:\Users\user\.claude\plans\abundant-nibbling-sutton.md`
（D2 使用者實測 → 多使用者架構 → 行為介入迴圈）。

✅ **後端部分 2026-08-26 完成**（PR #11：多使用者持久化、Health Connect adapter、
行為介入迴圈、資料遷移、驗收測試）。
✅ **手機端的 UsageStats 與 `lights_out_at` 2026-09-03 完成**（PR #30），
連同暱稱制帳號——**D2 需要的最小組合已經齊了**。

✅ **睡前 App 分布**已接上（`app/lib/services/pre_bed_apps.dart`；2026-11-19 起在 Phone down 詳細頁最底下，只有最近一次放下手機那一晚）。

### ✅ 產品迴圈（PR #51，2026-09-12 合併）

六個功能一起進來。**最後三個的實機狀況（2026-11-19 用手機上的紀錄重新查證）**：

| 功能 | 實機 | 依據 |
|---|---|---|
| Health Connect | ✅ **整條通了**（2026-11-17） | 手機送出 3 段、後端寫成 `source=health_connect`，再被 Garmin 依優先權蓋掉。詳見 [HEALTH_CONNECT.md](docs/HEALTH_CONNECT.md) |
| 就寢守門 | ⚠️ **只有 Reminder 模式驗過**（2026-09-13 兩次） | 手機 `shared_prefs/sonnap_guard.xml` 的 `reminded:` 鍵（只在 reminder 模式寫）。**Send-home 模式沒有紀錄、不留痕跡**，而現在設定就是它。詳見 [BEDTIME_GUARD.md](docs/BEDTIME_GUARD.md) |
| 就寢提醒 | 🔴 **沒有驗過** | 只驗了編得過、Dart 測試全過 |

🔴 **報告與 PPT 只能照這張表寫**：就寢提醒不能寫成「手機上已經可以用」，
守門要寫就只能寫提醒模式。
🔴 **重裝 APK 會把無障礙服務關掉、App 不會說**——換了 APK 又要示範守門的話必檢。

| 功能 | 在哪 | 不能破的規則 |
|---|---|---|
| 遊戲化（XP／等級／衣櫃／成就） | `game/`、`GET /game`、`POST /game/claim`、`GET /closet`、`POST /closet/equip` | 紅線 4、5。一晚 XP = 行為（準時 30／容許內 15／熬夜 0）＋品質（Good 20／Normal 10／Poor・Bad 0）→ 熬夜又睡不好 = 0。行為上限大於品質上限，沒戴錶的人也升得了級。**XP 不存**，每次從 `nightly_behavior`／`wearable_nightly` 即時算；表只存使用者動作（領取、穿戴） |
| 好友 | `social/friends.py`、`social/sharing.py`、`/friends`、`/friends/feed`、`/friends/{handle}`、`/sharing`、`/sharing/preview` | **別人的 `user_id` 永遠不出後端**，好友之間用邀請碼（handle）當名牌。**2026-11-15 起每個人自己選讓好友看到什麼**（使用者定，grill）：能分享的仍是**白名單**（`sharing.ITEMS`，每一項一個 picker 從那一晚的 `/home` 挑值——跟本人報告同一份）；**預設開 10 項**（以 `sharing.defaults()` 為準）：放下手機、準時、連續、寵物心情、**分數、睡多久、攝影機每小時動幾次**（動態卡那三個大數字，2026-11-16 使用者定「預設分享、可關」）、用了哪些裝置、衣服與徽章、挑戰；其他（心率、壓力、步數、起床自評…）預設關、自己打開；即時狀態 `live_status` 也預設關；**三項永遠不給**、連選項都沒有：攝影機片段、Move IQ 每段時刻、睡前用了哪些 App（PATCH 送進來 422；`items` 用 StrictBool，"yes" 不會被轉成 true）。對所有好友同一組設定；時刻可選「只寫準時與否」。沒公開的值是 null、App 不畫（不寫 0）。好友頁最上面是自己的 **Streak 大卡**（他選的狗／貓＋火：0 晚沒有、1–2 小、3+ 大，減少動態效果不動；週一→週日一排，晚了空心圈不打叉不用紅）＋底下分 **Feed（動態牆，預設）／Friends（邀請碼、名單、排行）** 兩個分頁。**動態卡（2026-11-16 使用者定）**：整張卡是他自己選的場景（`friend_sharing.scene`，`sharing.SCENES` 四張使用者生成的圖；像大頭貼，**不依心情或好壞換**），寵物站在圖裡的地上、不放圓框；前三個有公開的項目寫成大數字，連續 3 晚以上在他最近那一晚的卡上出現一條只寫事實的橫幅，公開了 Sleep Stages 就畫那一晚的階梯（每一段只給「第幾分鐘」不給 ISO 時刻，選「只寫準時與否」的人兩端只寫 Fell asleep／Woke up）。寵物狗／貓由 App 送到 `friend_sharing.pet_species`。心情用純行為版。⚠️ 夢境不能分享（後端沒有每個人一份的夢）；手機使用只給睡前 60 分鐘加總。排行榜（七個標籤＋晚／日·週·月·年）是**第二批**、還沒做 |
| 睡眠助理 | `ai/chat.py`、`POST /chat` | 見下方「程式碼結構」最後一段（2026-11-19 起是對話，帶前文） |
| 就寢提醒 | `bedtime_reminder.dart`、`sonnap/notify`（AlarmManager） | 提前 30 分鐘，**留在 Dart**。關掉開關要 cancel（不是只是不排新的）。⚠️ 手機重開機後鬧鐘會消失，要等下次開 App 才重排 |
| 就寢守門（Accessibility） | `bedtime_guard.dart`、`sonnap/guard` | 守「目標前 30 分 → 目標後 6 小時」，判斷全在 Dart，Kotlin 只照做。`canRetrieveWindowContent="false"`（不讀畫面內容，設定頁的承諾靠它）。⚠️ **Google Play 不會讓它上架**；Android 13+ 側載要先「允許受限設定」。實機清單見 [BEDTIME_GUARD.md](docs/BEDTIME_GUARD.md) |
| Health Connect | `health_connect.dart`、`sonnap/health` → `POST /wearable` | 只要 `READ_SLEEP`。**每個起床日只送最長的一段**（午覺照順序送會蓋掉那一晚，後端照樣回 201）。**那一晚已有 Garmin 就回 409、不蓋**（見「同一晚兩個來源」）。`minSdk` 因此 24 → 26。實機清單見 [HEALTH_CONNECT.md](docs/HEALTH_CONNECT.md) |

⚠️ 三個「30 分鐘」必須一致：就寢提醒 `kReminderLead`、守門 `kGuardLeadIn`、
首頁倒數變紅 `kImminentThreshold`。不一致時通知說「還有 30 分」、倒數還是綠的、
App 卻已經被擋了——`bedtime_guard_test.dart` 有一條在守。

⚠️ **要動評分邏輯或新增遊戲化功能（挑戰／獎勵／寵物成長／貨幣）之前，
先讀「🚧 設計紅線」那一節**——那五條紅線是拿外部同類專案對照後定的，
其中第 4、5 條防的是我們還沒踩但下一步最可能踩的坑。

### ✅ Insights 改版（2026-11-19，`feature/insights-tabs`）

頂端 **Day／Week／Month／Year**＋「‹ 期間 ›」（`screens/insights_screen.dart`）。示意圖與決定記錄見記憶 `insights-dwmy-redesign`。

| 規則 | 不遵守的後果 |
|---|---|
| **Day＝早晨報告本體**（`MorningReportScreen.fromLoader(embedded: true)`，跟起床後看到的同一個元件）；不畫經驗條、關閉鈕、底部兩顆按鈕 | 兩份「這一晚」遲早各說各的 |
| 組一晚報告的程式**只有一份**：`services/report_loader.dart`（首頁與 Insights 共用） | 一邊多接一個詳細頁的資料，另一邊點了沒反應 |
| 🔴 Insights 的 notes **一律 generate=false**（`ReportLoader.notesLoader(allowGenerate: false)`） | 打開 Insights 就花 AI 額度、而且寫出來的不含自評 |
| 期間：週一起的日曆週、日曆月、日曆年；右到本期、左到帳號第一筆資料 | — |
| W/M/Y：上面心情（Week 7 顆狗頭、Month 月曆、Year 365 格熱圖，照抄每晚 `pet_mood`）＋中位分數＋星星；下面**鏡像格子**（跟 Day 同一項同一位置）。加總在 `services/insights_periods.dart`（純函式） | — |
| 大字是**中位數**；Year 每欄是那個月的中位數；沒資料是「—」不是 0；**0 步＝沒戴錶** | 平均會被一兩晚拉走；0 會被讀成走了 0 步 |
| 跟上一期比**只代表方向**：上升紅、下降綠，**分數也一樣**；Sleeping HR、Sleep phases、卡路里、活動、壓力不比 | 在 Dart 判斷好壞 |
| **效率所有種類合在一起**算中位數與比較（使用者 11-19 定、知情：按按鈕多的週看起來會比較低） | — |
| 熬夜「N of M nights late」**照抄後端每晚 `is_late`**；12:00–18:00 的放下手機不算 | 跨午夜只在 adherence.py 算 |
| 攝影機 W/M/Y 畫「一小時動幾次」，**不畫文獻常模**、寫 not part of your score | 事件率跨夜不穩 3.1 倍 |
| 星星＝後端 `wearable.quality_bands`（照抄 `GRADE_THRESHOLDS`）換算；**舊版後端沒有就不畫星星**，Dart 不寫切點 | 第二份切點 |
| 資料：App 一次要 `/insights?days=365`（`_insightsYear`，等 8 秒）；連不到後端時 Week 用打包檔、**Month／Year 照實寫 Needs the backend** | 拿 30 晚冒充一年 |
| **分數組成與警語不在 App 上**（使用者 11-19 定，只留書面報告） | — |
| 舊卡去處：挑戰＝Day 與 W/M/Y 最底下一行（`widgets/challenges_sheet.dart`）；睡前 App＝Phone down 詳細頁最底下、**只有最近一次放下手機那一晚**；資料即時與否／昨晚送到沒／來源＝設定頁「Data」；Sleep basics＝助理頁（預設收合） | — |
| 🔴 **偵測就寢＋上傳＋問挑戰在 App 層的 `services/nightly_sync.dart`**：開 App（帳號解析完之後）與每次回到前景都跑，**跟停在哪一頁無關**。原本藏在舊 Insights 頁的 initState。✅ **2026-11-20 實機驗證過**（設定頁 Data 寫「Last night sent」）；`nightly_trigger_test.dart` 守著三條：打開跑一次、回到前景再跑、帳號沒解析完不跑（拿掉任一處觸發都會紅）。測試靠 `SonnapApp(nightly:)` 注入 | 漏跑不會報錯，只是昨晚沒上傳、熬夜與挑戰少一晚 |
| 手機使用權限沒開時**首頁**寵物下方一條提示（`usage-access-banner`），點了去系統設定、回來開了就消失 | 原本按鈕在舊 Insights 卡裡，新使用者找不到 |
| **W/M/Y 的格子與心情卡點了開詳細頁**（`widgets/period_detail_sheet.dart`，PR 3）：開在**同一個期間**，頁裡也有 D/W/M/Y 與「‹ 期間 ›」；切到 Day 停在那段期間**最後一個有資料的晚上**、跟上一個有資料的晚上比；Year 一欄＝那個月的中位數；時刻（Phone down）畫點、上早下晚；點長條寫那一天。規矩同格子（中位數、「—」、只代表方向、不放常模、分數頁不呈現組成）。每一項怎麼取值、怎麼寫只在 `kPeriodMetrics` 一份。**Day 分頁的格子點開的是報告原本的詳細頁**（這一晚＋這一週），那些頁刻意不加 Month／Year（11-19 使用者定）——要看月、年從頂端切到 Month 再點 | — |

### ✅ 首頁改版（2026-11-12，`feature/home-day-night`）

一頁全放（**不分早晚版**，使用者先定早晚兩版、後改回一頁）：問候 → 時鐘卡 → 寵物站在山頂 →
「不按也沒關係」那句 → 分數卡 → 兩欄 → Sleep Stages → 一週心情列。**Start Sleep 在導覽列中間**（見下一列），按了進全螢幕睡覺畫面。

| 規則 | 不遵守的後果 |
|---|---|
| 頂端只有小字「Hi, 暱稱!」＋大字「Welcome to Sonnap」（2026-11-13 使用者定），**不分早午晚、不放後端的 `header_message`**；暱稱一律來自帳號，沒有帳號是 `Hi, Sleeper!` | 不得拿任何人的名字當佔位符（見上方） |
| 一週心情列、圖例、寵物旁的心情標籤畫**狗頭表情**（`assets/moods/dog_*.png`，使用者生成），**不用起床自評那五顆圓臉**；不認得的心情退回 bored | 圓臉是「你覺得怎樣」、狗頭是「寵物的心情」，共用一套臉同一個早上會看到兩個意思 |
| **寵物 notes**（2026-11-17 取代夢境日記）：**首頁與早晨報告都是草地上一本攤開的日記**（`widgets/notes_book.dart`，圖 `assets/moods/dream_book.png` 使用者生成）。首頁放在小狗右下、貼著草地；報告放右下草地。點開是 AI 的總結＋從清單挑的建議（`widgets/pet_notes_sheet.dart`，標題 **Your buddy's notes**——寵物沒有名字，小狗、貓都適用；標題下寫那一晚的日期）。**還沒看過這個 version 就抖＋右上角紅點**，看過就靜止（`services/pet_notes.dart` 的 `NotesReadStore` 存**看過的 version**，首頁與報告共用；內容換了紅點再亮），減少動態效果時不抖、紅點照樣在。**沒有內容（沒總結、沒建議）就不出現**——但**首頁在手錶資料到了的晚上照樣放一本空的**（11-21 使用者定：點了才能叫 AI 寫），空的不亮紅點、不抖，AI 也沒寫出來時頁面寫 Nothing to add for this night.；手錶還沒到又沒內容仍不出現。**首頁問今天日曆日那一晚，沒內容就退回前一晚、只往回 1 晚**（11-19 使用者定：凌晨才睡，過了午夜「今天」那晚還沒開始，原本日記本會消失到起床；`homeNotesDates()`）。🔴 **首頁打開一律 `generate=false`**（打開不觸發 AI）；**點日記本才叫 AI 寫**（11-21 使用者定）：AI 已寫好或手錶還沒到就直接開；只有原句時，那一晚**還沒自評就先跳自評卡**（Skip 也照樣寫），再 `generate=true` 要一次——頁面先開、底下一行 Writing your notes…，寫好換上去並記成看過，寫不出來留原句。報告流程照舊（自評之後生成），報告關掉後首頁重新拿一次。沒有分數時報告與等待畫面也帶 `generate=false`（`NotesLoader`）。讀不到日記本圖時退回程式畫的書本圖示 | 使用者定。AI 那段要讀自評，首頁一打開就生成會不含自評、還多花一次額度（`pet_notes_test.dart` 守著：打開不生成、點書先問自評、寫好的不重叫）|
| 首頁右上**沒有 notes 圖示**（11-15 使用者定：草地上那本日記就是入口），只剩衣櫃、獎勵、設定 | — |
| **導覽列**（2026-11-13 使用者定，照參考圖）：只有圖示、沒有文字；Home · Friends ｜ **中間一顆凸出的紫色圓鈕＝開始睡覺**（畫睡著的狗頭 `dog_tired.png`，缺圖退回月亮）：**先滑出 Sleep schedule**（同時鐘卡那個轉盤，按鈕字換成 Start Sleep），按了才開始；把面板關掉＝不開始、不記上床。面板背景是使用者生成的夜晚窗景 `assets/backgrounds/schedule_night.jpg`（三個入口共用；讀不到退回深藍）｜ Insights · Assistant。**Settings 搬到首頁右上角的人像**，按返回回首頁。選中的分頁紫色＋底下小點，圖示保留朗讀名稱（`widgets/moon_nav_bar.dart`） | 中間那顆只送一個請求（`StartSleepRequests`），**開始睡覺的流程只在首頁一份**；在別的分頁按會先切回 Home，起床報告才接得下去。⚠️ Settings 刻意留在 IndexedStack（不另開一頁）：首頁與設定頁共用就寢時間，要即時同步（`bedtime_sync_test`）。⚠️ 頁面延伸到導覽列後面（extendBody），但內容只排到導覽列上緣：高度用 body 的 `padding.bottom`，**不能用 `viewPadding`**（Scaffold 已經拿掉系統那段，實機量過，首頁最底那列會被蓋住） |
| **等級徽章在寵物正上方**，不在標題旁（2026-11-13 使用者定）；沒有後端不畫。**11-21 起底下一條細進度條＋「430 XP to Lv 8」**；有接後端時背景、山頂、寵物與底下全部**往下推 `kHomeLevelExtra`（30）**，寵物照樣站在山頂、上面空出來的補 `kHomeBackgroundTop`。⚠️ 看「有沒有接後端」不看「/game 拿到了沒」，不然資料晚到時整頁往下跳；不往下推的話等級條只能往上長、實機壓到時鐘卡（`game_test` 量**整張**時鐘卡 `countdown-border`，原本量的倒數字在卡片內距裡、抓不到）（`widgets/level_progress.dart`，**睡眠計畫頁寵物頭上也是同一個**，點了都開獎勵頁）：條填多少照抄 `/game` 的 `progress`、還差幾 XP 照抄 `xp_for_next`，**不從 xp_total 自己算**；最高級條滿、寫 Max level | `game_test.dart` 量位置守著；`level_progress_test.dart` 守照抄、最高級、計畫頁也有 |
| **寵物用隊友的 2D 分層寵物**（`lib/pet2d/`，2026-11-15 換成 v4.6.45：**小狗四種心情都有圖、多一隻灰色虎斑貓**，經 `widgets/home_pet.dart` 這個插槽）。**設定頁「Pet」選小狗或貓**（`services/pet_choice.dart`，**只存在手機上**、預設小狗、不認得的值當小狗）。**缺圖的心情畫 bored，絕不畫 happy**（`PetDefinition.resolve()`，隊友原版退回 happy）。⚠️ 起床／等報告／睡覺的 GIF 與睡姿圖**只有小狗版**：選貓時走各自的程式版退路（寵物是 `HomePet`，所以是貓；睡覺畫面是 tired 的貓）；**一週心情列與導覽列的狗頭圖示還沒有貓的版本**（待辦：請隊友補貓頭） | 焦慮的夜晚畫成開心的寵物＝紅線 5。`pet2d_test.dart` 用一隻故意缺圖的假寵物守退路、守兩隻四種心情都畫自己的圖；`pet_choice_test.dart` 守選貓時三個畫面都不出現小狗 GIF（拿掉判斷三條都會紅） |
| **「跟上一晚比」只代表方向：上升紅、下降綠**（台灣股市慣例，使用者定） | 改成「變好綠、變差紅」就是在 Dart 判斷好壞——睡得多不一定好，攝影機動作更已驗證與任何結果無關 |
| 比的是**上一個有資料的晚上**；那一項沒逐夜資料時**不畫比較** | 編出比較數字。效率、深睡的逐夜資料來自後端 PR（`feat/history-eff-deep`） |
| **首頁分數卡、效率、深睡、Movement 點開＝早晨報告同一份詳細頁**（2026-11-21，`widgets/night_sheets.dart` 的 `NightSheets`；報告點分數圓弧也開分數頁；Movement 開報告那頁攝影機頁，**跟分數無關、那晚有錄影就開**；首頁舊的通用長條圖頁 `_showMetricSheet` 已刪）。分數頁：大數字＋等級＋星星＋圓環、這一晚五個量（睡多久、效率、醒著、深睡、REM）**只寫數字不寫得分**、有詳細頁的可點（點了先收掉分數頁再開）、REM 沒量到寫 **N/A**、沒資料寫「—」；一週照每晚等級上色，顏色照抄後端 `/insights` 的 `score_color`（**Dart 沒有等級顏色表**）。深睡頁：幾分鐘＋佔總睡眠幾成＋幾段、時間軸只亮深睡、各階段平均心率（`stageHeartRates`，不寫正常範圍）、一週不畫常模線。Usually＝中間值、跟前一週比只代表方向。**App 上一處警語都不放**（11-19 定） | 同一個量兩頁的話兩邊遲早說的不一樣；`night_sheets_test.dart` 守顏色照抄、N/A 與「—」分開、不出現得分、列點了不疊兩層 |
| **兩張主卡**（2026-11-13 使用者定，參考 Otter Life）：**Sleep**（昨晚：原本四張＋睡著期間的心率）與 **Activity**（**前一個日曆日**：步數、活動卡路里、活動時間、整天心率）。資料來自打包檔的 `activity`（`build_app_payload.activity_block()`，讀白天資料檔＋原始檔的整天心率，不碰資料庫） | 白天資料早上才匯入，沒有「今天到目前」，所以標 Yesterday |
| **左右兩欄**（2026-11-13 使用者定，照 Otter Life 原圖）：**左邊一格一格的小卡**（Sleep、效率、深睡、攝影機動作）往下疊，**右邊一張 Activity 卡**（步數、活動卡路里、活動時間、整天心率，項目之間細線分隔、**平均分配卡片高度、每項在兩條線正中間**（列的 Column 要 `mainAxisSize.min` 才置中得起來），底下不留一大塊空白；整天心率標題只寫 Heart rate、小字寫 `all day · resting N`）。兩欄上下緣對齊（IntrinsicHeight，左邊每格平均撐開）；**左右各項不逐列對齊**（使用者試過逐列對齊後決定回到原圖）。睡著心率與 VO2 max 使用者拿掉了（睡著心率在 Sleep Stages 疊線看）；**Move IQ 也不放首頁**（11-14 使用者定，早晨報告的 Yesterday 格子還有）。⚠️ 大字一律 `softWrap: false`——FittedBox 裡的字量高度時會被當成會折行、量得過高。**沒有白天資料時 Sleep 退回整寬 2x2**（只剩半欄會空一半） | `home_activity_test.dart` 量位置守著 |
| Activity 只寫事實：步數只寫 goal、不畫獎盃／打勾、**沒有「跟前一天比」的箭頭**；**點了開早晨報告 Yesterday 同一份詳細頁**（2026-11-21，`night_sheets.dart` 的 `DaySheets`：步數、Calories、Active time；心率有醒著的心率開 Awake HR、沒有才退回那天 0–24 點的線）。那一天的資料用後端 `/home` 的 `yesterday`（有每小時步數、每 15 分鐘程度、醒著心率），拿不到才用打包檔那一份（那幾塊照實少掉） | 上升紅的規矩套在步數上會很怪；達標是判斷；同一個量兩頁的話兩邊遲早說的不一樣 |
| ⚠️ **兩個心率不混**：Sleep 卡是睡著期間的平均（同 Sleep Stages 的心率線），Activity 卡是那一整天的範圍（含走路）。都不寫 Normal／High。**這支錶沒有 HRV 與呼吸**——整天的心率也算不出 HRV（手錶只存 2 分鐘平均，沒有每一下心跳的間隔） | 使用者問過「心率跟 HRV 是不是一樣」 |
| **效率小卡顯示進分數的那一個**（2026-11-13 使用者定，同早晨報告）：按了兩個按鈕是臥床版、只按 Start 是到手錶醒來、沒按是手錶版；下面一行小字寫是哪一種（`score_claim.EFFICIENCY_BASIS_LABELS`，App 照抄）。打包檔每晚帶 `scored_efficiency`／`_basis`／`_label`，直讀評分器的 `efficiency_used`／`efficiency_basis` | 手錶版的分母從入睡算起，幾乎每晚 100%（使用者問「為什麼都是 100%」）。⚠️ 「跟上一晚比」與長條圖**只放同一種**：臥床版 88 跟手錶版 100 不是同一個量，混著比會畫出假的下降箭頭 |
| **Sleep Stages 是圓角階梯，不是平滑波浪** | 平滑曲線會畫過那一刻沒發生的階段 |
| 沒量到 REM 的晚上不畫 REM 那一層，圖例寫 `N/A`（11-21 使用者定，原本 `not measured` 太長）；**淺睡照寫手錶自己的總數**（`main._stage_legend_light`，＝總睡眠 − 深睡，跟圖上畫的淺睡同一段）。比例條與 Insights 的 `light_minutes` 仍是 null | 畫成 0 會被讀成整晚沒有 REM；比例條上淺睡吃掉 REM 會像整晚沒有 REM |
| **凌晨兩點（過目標 60 分以上）不顯示倒數** | 倒數會算成「距離明天還有 21 小時」 |
| 倒數光條**剩 30 分鐘內變紅**，與提醒、守門同一個 30 分鐘 | 三個 30 分鐘不一致時，通知說還有 30 分、倒數卻還是綠的 |
| 背景兩張圖（山丘、湖面）是使用者以 prompt 生成的原創圖，左右翻轉過；**只鋪到內容結束**（Positioned） | 不用 Positioned 的話頁面被圖撐長，底下多一大段空白 |
| 星星與流星是程式畫的；系統開「減少動態效果」時靜止 | — |

### ✅ 衣櫃改版（2026-11-19，PR #148，`feature/closet-redesign`）

照使用者給的遊戲換裝參考圖（`screens/closet_screen.dart`）：上半是使用者生成的更衣室 `assets/backgrounds/closet_room.jpg`，寵物站在地毯上；最上面大字是**暱稱**（寵物沒有名字）＋「Lv. N」；左上 ‹＝**不存離開**、右上 ✓＝存起來（取代底部 Confirm 長鈕，有改才亮）；分類是一排菱形鈕（All · 頭 · 臉 · 脖子）；格子選中金框＋勾、身上那件底下小點、沒解鎖變暗＋鎖＋Lv。**一次只穿一件**（後端只存一件）。

| 規則 | 不遵守的後果 |
|---|---|
| 禮帽、皇冠是使用者生成的圖（`assets/accessories/head/star_top_hat.png`、`moon_crown.png`），粗黑外框已改細、改同色系＋底下淡影子（`shadowAt`）；後端 item_id 經 `home_pet.dart` 的 `kLayeredAccessoryFor` 對到圖 | 外框粗、沒接觸點時像貼紙浮在頭上（使用者連說兩次「突兀」） |
| **這兩頂每種姿勢各有一組戴法**：`AccessoryDefinition.poseFits`，鍵是「寵物 id.心情」（`dog01.happy`…），值是 `AccessoryFit(fit, drop, dx, rotationDeg)`；**8 格（小狗／貓 × 4 種心情）都是使用者逐格看圖挑的**，改之前先出預覽給使用者看 | 只調一個共用值會把別的姿勢弄歪——各姿勢的頭位置、耳朵開合差很多 |
| 🔴 **漏一格會悄悄退回預設大小**（`fitFor()` 找不到鍵就用 `fit`／`drop`），不報錯；新增寵物或心情時要為這兩頂補齊。`game_test.dart` 守著：兩頂對 dog01／cat01 × 每個 `PetMood` 都要有 | 某個心情的帽子突然變大、浮起來，只有剛好那晚是那個心情才看得到 |
| 其他衣服（睡帽、眼鏡、圍巾、蝴蝶結、貝雷帽、墨鏡）**不用 poseFits**，`fit` 1、`drop` 0，照隊友的錨點；測試守著只有那兩頂 `fit` < 1 | 錨點是隊友逐姿勢對過的，再疊一層調整就有兩個定義處 |
| **貝雷帽（Lv7）、紅蝴蝶結（Lv4 的 bow）用自己的定位點**：寵物的 `accessoryAnchors[圖檔 id][心情]`（隊友 v4.6.48，2026-11-20 照抄），沒列到的衣服用插槽錨點；墨鏡（Lv9）用 face 插槽。粉紅蝴蝶結 11-20 拿掉（使用者定） | 漏一格同樣悄悄退回插槽錨點；`game_test.dart` 守 8 格齊全、也守「`game/inventory.py` 每件都有圖、有分類」 |
| 位置以錨點框為單位（`fit` 以底邊中點縮放、`drop`／`dx` 是框邊長的比例），跟著寵物大小走 | 寫像素的話首頁與衣櫃的寵物大小不同，會一邊對一邊歪 |

### ✅ 好友頁的即時狀態（2026-11-19，`feature/friends-live-status`，疊在 `feature/friends-sharing` 上）

最上面的大分頁：**Town · Feed · Friends · Ranks**（2026-11-19 第二輪，排行榜自成一頁；四個放不下時整排等比縮小）。
Friends 分頁＝「加朋友＋看朋友現在的狀態」：**You 卡**（好友看到的你；沒分享寫「Friends can't see your live status」＋Share）
→ **All · Asleep · Still up**（人數寫在膠囊上）→ 依狀態排好的卡片（睡著的在前、睡最久的先 → 過了就寢 → 醒著 → 起床了 → 沒分享）。
卡片＝頭像（睡著畫 tired）＋大字（睡著寫睡了多久、其他寫昨晚放下手機）＋狀態一行＋7 晚放下手機小長條（越晚越高、一個顏色）。
邀請碼在標題右邊的**圓的「人＋」**面板裡（我的碼＋Copy、輸入朋友的碼）；小鎮的 ＋ Invite 也開這個面板。
Sleep Circle 卡拿掉（它講昨晚）；右上只放**狀態圖示**，不放獎盃、火焰（那些屬於 Ranks）。
點卡片＝`widgets/friend_live_sheet.dart`：現在的狀態 → 7 晚放下手機（星期＋時刻，沒資料寫「—」）→ 最近那張動態卡 → Remove friend。
沒有朋友：睡覺的小狗＋「Add a friend to see who's asleep」＋大的 Add friend。

| 規則 | 理由 |
|---|---|
| 訊號只有**按鈕當下**：Start Sleep／Out of bed（含 I already got up）／Cancel 各送一次 `POST /sleep-status`（表 `live_sleep_status`），**只試一次、不補送、不擋睡覺** | 沒有背景服務、手錶不即時；半夜補送「我在睡」沒有意義 |
| 四種狀態**只在後端判**（`social/live_status.py`）：asleep（14 小時失效）／up（到當天 18:00）／past_bedtime（目標後 6 小時內，跨午夜用 `adherence_minutes`）／awake。14／18／6 是**設計決策**，各自沿用睡覺畫面、18:00 切夜、守門的值 | Dart 判就是第二個定義處 |
| past_bedtime **只寫「No Start Sleep yet · 40m past bedtime」，不寫 staying up**；Still up 不含 up、不含沒分享的人 | 「不按也沒關係」——沒按的人可能早就睡了 |
| 分享設定 `live_status` **預設關**；只寫準時與否時狀態照給、時刻與分鐘數拿掉；目標時刻本身不分享（後端只送分鐘數） | 即時狀態等於讓好友知道你此刻在不在睡 |
| 卡片**不放手錶睡眠時長**（參考圖的 8h 12m 不照做） | 生理資料不在好友白名單 |
| 第一次**切到 Friends 分頁**才問一次要不要分享；**不在 initState 問**；連不到後端／舊版後端／點旁邊關掉都不記成問過（`friends_live_test.dart` 守著） | 好友頁在 IndexedStack 裡，App 一打開就建好了，會在首頁上跳出來 |
| 卡片頭像 `HomePet(animate: false)` | 一排寵物同時動太吵；`pumpAndSettle` 也會逾時 |

### ✅ 小鎮送禮（2026-11-22 grill Q1–Q15，`feature/friend-gifts`，照 Finch 的送禮頁）

點小鎮裡的朋友 → 資料卡最下面 **Send something** → 送禮頁（`widgets/visit_gift_sheet.dart`）：你的寵物＋朋友的寵物、泡泡一句、**3×3 九種**，**先選再按 Send**。兩隻寵物（與地圖上的寵物）穿各自的衣服：朋友的要他有分享 Pet outfit，後端給 `equipped_item_id` 才畫。背景 `assets/backgrounds/visit_gift.jpg`（使用者生成：夜晚客廳、地毯上兩個坐墊），**你的寵物站左邊坐墊、朋友的站右邊**；坐墊位置用原圖比例寫在 `kVisitSeatMine／kVisitSeatFriend`，**換圖要重量**。讀不到退回漸層。
收的一方：小鎮右下**愛心＋還沒看過的數量**（`services/visits_seen.dart`，打開就算看過、只存手機）→ Stopped by today（寵物頭＋那句＋**Send back**）；地圖上今天送過你的朋友頭頂冒那一種的小圖示（只是裝飾）。

| 規則 | 不遵守的後果 |
|---|---|
| 九種的三句（按鈕、對方看到的、泡泡）**只在 `social/town.KINDS`**，App 只把 `{friend}` 換成名字；原本 4 種的 key 不改 | 第二個定義處；舊紀錄讀不到 |
| **一句都不准評判或催促**（`test_friend_town.py`【9】掃字） | 同「不按也沒關係」 |
| **不鎖格子、不扣能量、不給 XP、不推播**；一個朋友一天一次照舊 | 等級反映睡眠品質，睡不好的人能送的關心不該比較少（紅線 5 的反面） |
| 預設選中那格只看**自己手機的時間**（晚上 good_night、早上 good_morning），不看朋友的即時狀態 | 即時狀態預設不分享 |
| 圖示 `assets/visits/<key>.png`（使用者生成的 3×3 圖示表切的），讀不到退回按鈕字裡的 emoji | — |
| 減少動態效果：圖示不飛、寵物不跳，只換字 | — |
| 小鎮資料先畫、「看過哪幾則」晚一點補 | 讀手機儲存慢時會拖住整個小鎮（測試裡 channel 不回應時整頁空白，寫的時候踩到） |
| 成果展：`demo_accounts.py --live` 讓 Mia／Leo／Yuki **今天**各送你一則（先刪再寫，可重跑） | 拜訪只看今天，`--create` 那天寫的到展示當天看不到 |

### ✅ 按 Start Sleep 自動開攝影機（2026-11-21 grill Q1–Q17，`feature/camera-auto-start`）

手機按 Start Sleep → `POST /sleep-status`（start）→ `camera_auto.py` 另外開一個獨立的 `tapo_metric_logger.py`；
Out of bed／Cancel → 放停止旗標 `tapo_metrics/STOP`，錄影程式自己收尾。睡覺畫面在副標底下多一行 `Camera recording`
（沒插電加 `· laptop on battery`）。設定在 `tapo_metrics/camera_auto.json`（沒有就用預設：框 34,129,288,231、影片 840 分、最多 14 小時）。
**每晚睡前／起床照 [BEDTIME_CHECKLIST.md](docs/BEDTIME_CHECKLIST.md) 做**（插電、同一個網路、攝影機 IP、開後端、Camera recording、`--status`）。

| 規則 | 不遵守的後果 |
|---|---|
| **只認手機帳號（`resolve_phone_account`）＋私有網段／本機**（`camera_auto.decide()`、`is_local_network()`；Tailscale 100.64/10 不算） | API 沒密碼、user_id 就是鑰匙：拿到 id 的人能從外面讓臥室攝影機開錄 |
| **停錄只放旗標檔，不從外面砍** | Windows 的 terminate 是硬砍，熱區圖、影片檔尾不會寫，影片壞掉 |
| 「有沒有在錄」看錄影程式自己寫的 `tapo_metrics/logger.lock`（pid＋phase）；**手動開的也算**，Out of bed 一樣停它；程式死了或超過 15 小時當作沒在錄；`--selftest` 不寫鎖檔 | 鎖檔沒清掉就永遠開不了錄；自測會擋住當晚的 Start Sleep |
| 已在錄不開第二個；最多錄 14 小時由**錄影程式自己的 `--max-hours`** 守 | 兩個程式搶串流；後端半夜重開的話後端計時就沒了 |
| Cancel：收尾（鎖檔消失）之後把那一晚的檔案**搬到 `tapo_metrics/cancelled/`，不刪**；錄影程式不結束就不搬 | 誤按 Cancel 刪了救不回；正在寫的檔案搬了會壞。早上匯入只看第一層，不會挑到 |
| 錄影期間 `--keep-awake`（SetThreadExecutionState）；⚠️ **擋得住閒置待機，擋不住闔上螢幕** | 09-20 用電池 4 分鐘就待機、錄影斷掉 |
| 手機只在**確定在錄**（recording／already_recording）時寫那一行；沒回應、還在接、沒開成一律不寫（`cameraStatusLine`）。回應放進 `cameraStatusBoard`，**按 Start Sleep 先清掉** | 手機分不出後端沒開還是網路慢；寫 Camera off 可能是錯的；不清會顯示上一晚的 |
| `/sleep-status` 裡攝影機的任何錯誤都吞掉（好友狀態照記）；開錄等接上最多約 8 秒，在執行緒裡跑；手機 start 的逾時 12 秒 | 攝影機只是附加的，不能讓好友狀態跟著壞 |
| **攝影機有沒有移動**（`camera_alignment.py`）：錄影程式在第 15／30／60／90／120 分鐘各存一張 `_frame_NNN.png`、第 60 分鐘多存一張畫上框的 `_snapshot.png`；**只比框上方那一條**（牆、層架）、**多張取中間值**，> **30 像素**（設計決策，沒有文獻）判「可能移動」 | grill 原本定「開錄 90 秒拍一張、比整張」：10 晚實測人常常正對鏡頭、被子每晚不同，攝影機沒動也 2～259 像素亂跳。改了之後 9/10 晚 1～4 像素，11-09 真的擺歪那晚 32 |
| 早上匯入偵測到移動：**手錶照常、那一晚攝影機不匯入**；`--camera-ok` 硬匯；沒有畫面或沒有基準不擋 | 框歪了那晚的動作數字全錯，但跟手錶無關 |
| 抓不到「床移動、攝影機沒動」——那種情況靠 `_snapshot.png` 給人看 | — |
| 基準在 `tapo_metrics/reference/`（frame.png＋roi.json），第一次：`python camera_alignment.py --make-reference tapo_metrics/20260903_020631.mp4 --roi 34,129,288,231`（當初推出框的第 3 晚，第 30 分鐘那格） | — |
| **錄影程式在背景跑、沒有視窗**（`CREATE_NO_WINDOW`，⚠️ 不要加回 `DETACHED_PROCESS`）；要看有沒有在錄：`python camera_auto.py --status`（錄影中／連線中／收尾中、從幾點、影片多大；超過 60 秒沒寫入、沒插電會提醒） | 11-21 實機：舊旗標讓錄影程式自己開一個黑色終端機視窗，關掉就斷錄；拿掉之後使用者看不到在錄、以為沒錄就按了 Cancel |
| 攝影機與筆電都連手機熱點時，**熱點會換攝影機的 IP**；`tapo 2.0/.env` 的 IP 對不上就連不上（`auto_logger.log` 寫「連不上」）→ 去 Tapo App 看 IP，只改 IP 那段 | 11-21 實機第一次就是這樣 |
| 重新框：`python camera_reframe.py`——熱區推一個框畫在照片上，**人按 Enter 才存**（或 D 自己拖）；存時**同時換基準**，舊的框與基準備份到 `reference/backup-<時間>/`；**下一晚**開始用；0.75% 門檻沒在新框底下重新驗證 | 自動推框有室友那晚選錯過；基準不換的話之後每晚都判移動 |

### ✅ 睡眠計畫（2026-11-19，`feature/sleep-plan`）

首頁「不按也沒關係」底下的 **Today's plan** 小卡 → Plan 頁：作息（就寢、起床，同轉盤）→ This week（連續準時、作息收斂）→ **Measured** 三列（準時放下手機、上床少滑手機、**準時起床**）→ 自己勾的習慣 → Add a habit。點一條開編輯頁（照使用者給的參考圖：Time、Notify me、Repeat、Save）。**決定、措辭、文獻全在 `Research-Background/睡眠計畫.md`**。

| 規則 | 理由 |
|---|---|
| **量測那幾列與進度條照抄 `/challenges`**，沒量到寫「—」不是空圈 | Dart 不判 |
| **準時起床**（`behavior/wake.py`）：Out of bed 按鈕 → 手錶起床 → 都沒有＝沒量到；目標 **±60 分**、七天都算（Bootzin & Perlis 2011，⚠️ **不是 Bootzin 1972**——原文沒有起床那條）。**讀取時才併**（`main._behavior_rows_with_wake`），手錶晚到也算得出來；`/challenges` 與遊戲化都要經過它 | 不併的話一律 None，看起來跟沒量到一樣 |
| 每晚存 `nightly_behavior.target_wake` 快照 | 改目標不改歷史（同 target_bedtime） |
| **自己勾的只存在手機上**（`services/sleep_plan.dart`）、不送後端不給 AI；**不進分數、不改心情、不給 XP**，只寫「N days in a row」；沒勾是空心圈 | 紅線 4、5：自己勾不需要證據 |
| **勾下去只有當下的回饋、不累積**（11-19 grill Q36，`widgets/plan_check_button.dart`）：方格彈一下＋金色光點、浮出「Nice!」（**只用這一個詞**）、輕震、寵物跳一下（11-19 改成蹲→拋物線→落地壓扁＋腳下影子、不冒星星，`petJumpPose()`；原本整張平移上下像被線提起來）；**寵物的臉不換**（臉＝後端心情）；取消勾選什麼都沒有；全勾完只換標題那行字；減少動態效果時不彈不跳不飄。參考圖的「每條 5⚡」「Complete a goal → Claim」「寵物去冒險」都不做 | 沒有東西可以累積就沒有東西可以灌（紅線 5） |
| 版面（照使用者的參考圖）：整頁背景是使用者生成的直式長圖 `assets/plan/room.jpg`（**固定不動**），寵物站在地毯上（`kPlanRugCenter`＝0.43，換圖要重量），清單**從寵物腳下開始捲、不蓋過寵物**（11-19 改：要看得到牠跳，上緣淡出）；加習慣是「選一條 → 先開設定頁 → 按 Add to my plan 才加」，沒寫字或一天都沒選不能加；卡片深藍約 90% 不透明；習慣圖示 `assets/plan/<id>.png`（使用者生成的圖示表切的），缺圖退回系統圖示 | 使用者定（Q35、Q37–Q39） |
| 建議清單**逐字照抄研究文件**（`sleep_plan_test` 讀文件比對）；對得上起床自評的 id 與 `morning_tips.TAGS` 相同，但**兩邊不互相代填** | 改措辭先改文件；之後才比得起來 |
| 時間**跟著作息走**（存相對就寢／起床幾分鐘）；一天從**目標起床前 3 小時**開始（設計決策） | 凌晨三點還沒睡算前一天 |
| 習慣提醒走 `sonnap/notify` 的 **slot 1..20**、可只在星期幾響；**slot 0 是就寢提醒，計畫永遠不碰**；改了就全部取消再排 | 拿掉一條後舊位置不取消會每天響 |
| 寵物 notes 對得上的建議有 **Add to my plan**（`kTipToPlan`），加的是**清單那句**不是 AI 改寫的；「說明」那幾句沒有 | AI 那句每晚不一樣 |
| 挑戰卡**搬到 Plan**，Insights 不再有那一行；領 XP 仍在獎勵頁（準時起床、上床少滑各 10） | 只在一個地方出現 |
| 不做：一天幾次、沒完成延到下次、Link（清單裡沒有適合連的） | 使用者定 |

#### Journey（2026-11-19 grill，`feature/journey`）：起床一站一站往前移

計畫頁作息條底下（`widgets/journey_section.dart`）。**作息條與 Journey 合成一張卡**（11-19 使用者定）：上半是作息（點了開轉盤），下半進行中是**一條路**（參考圖、少字）：「Stop 2 of 5」，起點 ━ 寵物的頭 ┄•┄ 🏁，**點一個點冒出那一站的起床時間**，下面三顆太陽＝連續幾天準時；說明與 Stop 收進 ⋯；剛前進時寵物沿路走過來一次（減少動態效果不走）。寵物的頭是 `assets/plan/journey_dog.png`／`journey_cat.png`（使用者生成，**側面走路、不帶心情**——心情臉只代表後端心情），缺圖退回 🐾。**規則與理由全在 `Research-Background/睡眠計畫.md`「Journey 的規則」**；判定只在 `behavior/journey.py`。

| 規則 | 不遵守的後果 |
|---|---|
| 🔴 **這一站就是目標**：進行中時後端每次同步都把 `users.target_bedtime／target_wake` 設成這一站（冪等）；App 開啟、回到前景、上傳完 `/nightly` 都問一次 `GET /journey`，再把就寢、鬧鐘、提醒、守門換過去（`main._applyJourney`） | 兩組時間：提醒說還有 30 分、Journey 說要早睡，熬夜用舊目標判 |
| 進度**每次從每晚的 `up_on_time` 重算**（同挑戰引擎）；`journeys.stop_index` 只用來知道剛前進了沒 | 手錶晚到、事後補按鈕時進度不會自己更正 |
| 每晚照**當晚的快照**判準時；前進之後以前的夜晚不重判 | — |
| Journey 進行中**轉盤鎖住**，鎖在 `showSleepScheduleSheet` 一處（讀 `journey_active`），四個入口共用 | 鎖在入口的話漏一個就能把目標轉掉 |
| 站、跨午夜、「已經到了」（422 `already_there`）**都在後端**；Dart 照抄 `stops`，30 分、建議睡 7 小時從 `step_minutes`／`recommended_sleep_minutes` 拿。**睡眠長度不設下限**（使用者 11-19 改：每個人需要的不一樣），7 小時只寫成參考、不擋、不變色 | 第二個定義處 |
| 前進／走完：**不給 XP、不發通知**，計畫頁與首頁小卡各一行（`journeyNoticeText`），**離開計畫頁算看過**；第 1 站不提示 | 準時起床的 Quest 已給過 XP，同一件事不獎勵兩次 |
| Stop：停在這一站、目標不還原；停了之後轉盤解鎖、後端不再拉回 | — |
| ⚠️ 合併後要在 MariaDB 跑 `python db.py --init`（新表 `journeys`），再重開後端 | 後端啟動不建表 |

### ✅ 轉盤＋鬧鐘（2026-11-12，`feature/alarm-dial`）

點首頁時鐘卡或設定頁的目標就寢時間 → 滑出轉盤（月亮＝就寢、太陽＝起床，5 分鐘一格）＋ Alarm 開關。

| 規則 | 理由 |
|---|---|
| **鬧鐘只有按了 Start Sleep 才排**，排在下一個起床時刻；超過 14 小時不排 | 使用者決定不每天自動響；14 小時與睡覺畫面同一個 |
| Out of bed、Cancel、鬧鐘畫面的 Dismiss 都會取消；**響了不會自動按 Out of bed** | 按鈕是攝影機上床偵測唯一的 ground truth，不能代按 |
| 起床時間與開關存在手機上（`alarm.dart`）；預設起床 = 目標就寢 + 8 小時；開關預設開。⚠️ **2026-11-19 起起床時間也 PATCH 到後端**（`users.target_wake`，睡眠計畫的「準時起床」要在後端判），同步方式同就寢時間：`UserSettingsStore.syncedWake` 記上次送成功的值，不同就補送；開關仍只在手機上 | 判準時只能有一份（跨午夜） |
| 轉盤中間只顯示睡幾小時，**不判斷好壞** | 好壞只能由後端判斷 |
| 判斷全在 Dart，原生端（`AlarmService.kt` 等四支）只做「在這個時刻響」 | 與就寢提醒同一條紀律 |
| 鈴聲是程式合成的原創音檔（`res/raw/sonnap_alarm.wav`），USAGE_ALARM（勿擾也響），30 秒漸強、10 分鐘沒人理自己停 | 沒有版權問題 |
| 不加「不保證會響」的提示；**重開機後不重排** | 使用者決定／已知限制 |
| ⚠️ 測試裡要注入假的 `AlarmScheduler`：真的 channel 在測試環境沒人回應，Start sleep 會卡住 | 2026-11-12 踩過 |

🔴 **還沒在實機驗證會響**：要在三星上測螢幕鎖住、App 被滑掉、開著勿擾三種情況。

### ✅ 事後補上床／起床時間（2026-11-12，`feature/backfill-bed-times`）

兩個入口，都用同一個轉盤、都沒有 Alarm 開關：睡覺畫面的 **I already got up**（月亮鎖在上床時刻），
首頁 Start Sleep 下面的 **Forgot to tap last night? Add times**（昨晚有按上床就鎖月亮）。

| 規則 | 理由 |
|---|---|
| 每個時刻記 `tap`（當下按）或 `recalled`（事後補）：`nightly_behavior.bed_start_kind`／`bed_end_kind`，NULL＝舊資料當 `tap` | 使用者定 |
| **只補缺的那一個**；當下按的不能被回想的蓋掉——App 只讓補缺的，後端 `POST /nightly` 再守一次 | 按鈕是攝影機上床偵測的標準答案，比回想準 |
| 補的照樣算進效率；用到回想那一端的晚上，效率警語後面接 `score_claim.RECALLED_EFFICIENCY_NOTE`（② 只看上床） | 使用者定。判準 `efficiency_uses_recalled()` 一份，API 與打包檔共用 |
| 補的下床**不過** `kBedEndGrace`（比手機第一次被碰晚 2 小時）；仍檢查：晚於上床、不晚於現在、≤14 小時 | 那條擋的正是「起床好幾小時才按」 |
| 攝影機比對（`compare_night_sources.py`）**只拿 `tap` 的上床** | 回想可能差幾十分鐘，會把偵測器算成錯的 |
| 預設值不用手機偵測的時間：上床＝目標就寢，起床＝今晚鬧鐘或轉盤上的起床 | 使用者定 |
| 首頁「不按也沒關係」那句**照留**，連結加在它下面 | `bed_mark_buttons_test` 守著那句 |
| 「昨晚按齊了沒」看 `bed_log_*` 紀錄，不看上傳用的那幾個槽 | 上傳收下後槽會清掉，分不出「按齊而且傳了」與「沒按」 |

### ✅ 睡覺畫面＋助眠聲音（2026-11-12，`feature/sleep-sounds`）

背景是**房間＋睡覺小狗的循環 GIF**（`sleeping_loop.gif`，剛按 Start Sleep 先播一次 `go_to_sleep.gif` 過場、半夜重開不播、減少動態效果用靜止圖、缺檔退回 bedroom.png＋`sleeping.png`；怎麼做見 [SLEEP_GIF.md](docs/SLEEP_GIF.md)）。由上到下：大時間 → `Sleeping… your watch is tracking` → （小狗在場景裡）
→ 鬧鐘列 → 助眠聲音列 → 外框 Out of bed → Cancel 小字。背景是房間（`assets/backgrounds/bedroom.png`）。

| 規則 | 理由 |
|---|---|
| 副標只准說「**手錶**在量」；measuring／monitoring 與其他 tracking 說法都不准（`home_screen_test` 守著） | App 睡覺時沒有在量東西 |
| 點鬧鐘列開**同一個轉盤**，月亮鎖在按 Start Sleep 的時刻；**只改今晚**，轉盤上存的設定不變 | 使用者定 |
| 聲音三種（Rain／Ocean／Brown noise）**在 Kotlin 即時合成**（`SleepSoundService.kt`），沒有音檔 | 沒有版權問題、循環沒有接縫。要換成錄音只改原生端 |
| 播多久（15／30／60，預設 30）、淡出 1 分鐘由 Dart 決定（`sleep_sounds.dart`），選擇記在手機上 | 與鬧鐘同一條紀律 |
| **鬧鐘響、Out of bed、Cancel 都會停聲音**；鬧鐘那條在原生端（`AlarmRingService`） | App 沒開著也要停 |
| 要求音訊焦點：Spotify 會暫停；別人搶走就停、來電先靜音 | 使用者定 |
| ⚠️ 睡姿圖或背景缺檔時退回月亮小狗／漸層，**不會報錯** | 換新圖後若畫面沒變，先查 APK 裡有沒有那張圖——2026-11-12 建置快取漏包過一次，`flutter clean` 才好 |

### ✅ Sleep Stages 卡的疊線：Heart rate／Movement（2026-11-13，`feature/garmin-daily`）

照 Garmin Connect 的做法：Sleep Stages 卡（首頁與早晨報告同一個元件）圖下面兩顆，**點 Heart rate 疊心率線、
點 Movement 疊手錶動作線，再點一次回到只有階梯，一次只能選一個**。後端 `garmin/sleep_heart_rate.py`（純函式）
從 Garmin 原始檔取入睡 → 起床那段（心率每 2 分鐘、動作每 1 分鐘），每 5 分鐘一點，經 `/home` 與打包檔的
`metrics.heart_rate_curve`／`movement_curve` 給 App。

| 規則 | 理由 |
|---|---|
| **不寫 Normal／High**，不畫「正常範圍」色帶（使用者定，參考圖的 Normal 不照做）。心率選了之後下面一行只照抄「平均 · 最低 · 靜止」；右邊刻度寫 bpm | 夜間心率沒有文獻門檻（紅線 2） |
| **Movement 是手錶的**，不是攝影機的；沒有單位，右邊只寫 **More／Less**（不寫 High），下面寫 `Movement from your watch` | 首頁的 Movement 小卡與報告的 Movement (camera) 格子是攝影機的，另一個量；High 會被讀成「太高」 |
| 心率平均、最低從**那一段的原始讀數**算，**不用** `avg_heart_rate`；報告的心率格**有曲線就用曲線那段的平均**、沒曲線才用 `avg_heart_rate` | `avg_heart_rate` 混了清醒時段，並列會是兩個不同的「平均心率」 |
| 線是**單調三次插值**（`widgets/curve_path.dart`），`sleep_stages_overlay_test.dart` 沿整條線取樣驗證不衝出範圍 | 一般平滑曲線在急轉處會畫出沒發生的值（同階梯不畫平滑波浪的理由） |
| 選了線之後階梯變淡（35%、不畫光暈）；那一條沒有 → 那顆不出現；兩條都沒有 → 原本的卡 | — |
| 心率 0 或負數＝沒有讀數；**動作 0 是「沒動」，是真的值** | 寫錯不會報錯 |
| 只有 Garmin 來源才有；動作也**只呈現、不計分** | movement 永不進評分 |
| 首頁的曲線來自打包檔：`build_app_payload.py` 已經會帶，要等下一次早晨匯入重新產生 | 動 app/ 的 session 不跑 build_app_payload.py |
| **Camera**（第三顆）：攝影機在床鋪範圍看到的動作，**每 5 分鐘有幾成時間在動**（同一個校準門檻，`tapo_sleep_onset.motion_curve()`，門檻呼叫時才讀）。早晨匯入時從 CSV 算好存進 `camera_nightly.motion_curve`；`/home` 只留手錶入睡 → 起床那段（**牆鐘比**，攝影機時間沒有時區標記）。只收有床鋪 ROI 的夜晚；下面寫 `Movement seen by the camera` | 攝影機動作率已驗證與任何結果都沒有相關，只呈現。CSV 只在電腦上，後端讀不到 |
| 舊夜晚回填用 `migrate_camera_to_db.py --curves-only`：**只補 motion_curve，不重算覆寫整列** | 整列重算會用現在的程式悄悄換掉舊夜晚的事件數 |
| **首頁**的 Camera 線來自打包檔（`/get-sleep-data` 吐的就是 `app_payload.json`，**不是** `/home`）：`build_app_payload.camera_curve_for_night()` 直接讀那一晚的錄影 CSV（打包檔不碰資料庫）。「只留睡著那段＋貼時區」只有一份：`camera_curve.clip_curve()`，`/home` 與打包檔共用 | 2026-11-13 首頁沒有 Camera 那顆就是這個原因 |
| `camera_curve.py` 只用標準庫；`tapo_sleep_onset` 會連帶載入 OpenCV（錄影器的相依），打包檔**用到才 import**、後端不 import | 不讓後端啟動與打包檔多一個重相依 |
| **點線看那一刻**（2026-11-13 使用者定，照參考圖：白點＋小泡泡）：Sleep Stages 卡（首頁與報告同一個）與整天心率圖，點一下或按住左右滑，放開留著、點圖外面才收（下面那幾顆換線的按鈕不算外面）。泡泡：沒選線 `02:41 · Deep`；心率 `02:41 · 58 bpm · Deep`；手錶動作只寫 `Moving`／`Still`；攝影機寫那 5 分鐘裡動了多久 `moving 12 sec`（不寫百分比）；整天心率 `14:20 · 96 bpm`。規則只在 `widgets/chart_probe.dart` | **吸到最近的真實讀數、不內插**（內插的數字手錶沒量過）；離最近的點超過一個取樣間隔（夜間 5 分、整天 10 分）寫 `no reading`，**不吸到遠處、不寫 0**；不寫 Normal／High。`chart_probe_test.dart` 守著 |

### ✅ 早晨報告的「Yesterday」：Garmin 白天資料（2026-11-13，`feature/garmin-daily`）

前一個**日曆日**的步數、距離、活動卡路里、活動時間（高強度／活動／久坐）、爬樓、各壓力程度的時間、
Body Battery、VO2 max、Move IQ。報告裡 Sleep phases 之後的「Yesterday」那段圖形格子（`widgets/report_tiles.dart`；VO2 max 同首頁不放）。`/home` 的 yesterday 另帶 `history`（最近 14 天，步數那座山與長條圖）與 `heart_rate`（整天心率線），形狀與打包檔 `activity_block` 相同。

```
garmin_connect_fetch.py（同一次登入）→ garmin/data/garmin_daily_activity.json（只增不減）
  → migrate_garmin_to_db.py → garmin_daily 表 → /home 的 yesterday → App
```

| 規則 | 理由 |
|---|---|
| **只呈現、不計分**：評分、寵物心情、XP、挑戰一律不讀（`tests/test_garmin_daily.py`【9】守著）；好友看不看得到由本人在 What friends can see 選（2026-11-15 起，預設關，經 `social/sharing.py` 從 /home 挑） | 紅線 4 |
| **不判斷**：步數只寫「goal 9,430」（不寫 reached、不變色）；VO2 max 只給數字＋量到的日期（不分等級）；**壓力只給各程度的時間，不加說明、不用紅黃**（使用者定） | 紅線 2；VO2 max 的常模要年齡與性別 |
| 寫到**另一個檔**，不碰 `garmin_standard_data.json`；這個檔**只增不減**（沒抓到的欄位留舊的、從不刪一天）；**進版控**（使用者定，Move IQ 會露出每天幾點出門走路） | 那份有自己的合併規則，也丟過資料 |
| 白天資料的檔放在 `--output` **同一個資料夾** | 測試把 --output 指到暫存資料夾時，不會寫到真的 `garmin/data/`（2026-11-13 測試抓到過） |
| **429 立刻停**，已經抓到的照樣存；白天資料失敗**不影響**睡眠那份 | Garmin 會擋（2026-11-13 試抓三次都先 429） |
| 補抓從本人戴錶那天（`WEARER_SEGMENTS` 最後一段的起日，08-28）起，一次最多 30 天，早晨匯入自動帶 `--daily-since` | 更早是另外三個人戴的 |
| 匯入只寫**手機那個帳號**、只收 `wearer_c` 那段；找不到手機帳號就整個跳過 | 同手錶與攝影機匯入的判準 |
| 那一天沒資料 → **整塊不畫**；單一項沒值 → 那一項不畫（不畫成 0）；VO2 max 只給 **90 天內**最近一次；Move IQ 沒抓到是 null、那天沒有是 [] | 不編數字 |
| 白天資料跟睡眠分數無關：手錶睡眠還沒到（沒分數）也照樣畫 | — |
| **每個鐘頭走幾步**（2026-11-15）：同一次登入多打一個 `get_steps_data`（每 15 分鐘一格、`startGMT` 是 **GMT**，換成當地時間只在 `garmin/steps_intraday.py`）→ `garmin/data/garmin_steps_intraday.json`（**不進版控**，使用者定：等於公開作息）→ `migrate_garmin_to_db.py` 寫進 `garmin_daily.steps_hourly`（24 格 JSON；**另一支 `set_garmin_steps_hourly` 寫**，存白天資料時不會被蓋掉）→ `/home` 的 `yesterday.steps_hourly`。**打包檔刻意不帶**（它進版控）。補抓同白天資料：`--daily-since`、一次最多 30 天、429 就停 | Garmin 標 `none` 的格子＝沒戴錶，那個鐘頭整個沒有就是 null |
| ⚠️ Move IQ 的 `duration` **單位是分鐘**（對過起訖時刻）；一整天沒戴錶時 Garmin 回步數 0，那是「沒資料」不是「走了 0 步」；Garmin 用負數表示沒有值 | 寫錯都不會報錯 |
| 這支錶（Vivoactive 3）**沒有** SpO2、HRV、呼吸、訓練準備度、**Body Battery**（2026-11-15 實測：Garmin 回的全是空值，本人 78 天一天都沒有；報告那一格的程式留著，沒資料就不畫）；VO2 max 只在有 GPS 走路／跑步的日子更新 | 2026-11-13 試抓 |

### ✅ 早晨報告（2026-11-12，`feature/morning-report`）

滑完 Slide to get up（或 I already got up）→ **起床動畫**（`screens/wake_up_screen.dart`）
→ **起床自評卡**（`screens/rested_screen.dart`）→ **等待畫面**（`screens/report_loading_screen.dart`，
按 View sleep report）→ 報告；首頁一週心情列點任一天、補填自評之後則直接開報告（不經等待畫面）。`screens/morning_report_screen.dart`，合併規則在
`services/morning_report.dart` 的 `buildMorningReport()`（純函式）。

版面（11-13 依示意圖定案，11-14 依參考圖改）：日期 → **一條半圓線**的分數（只有線、不墊深色底盤；數字在弧裡、小狗頭上）＋小狗置中坐在弧下的草坡（腳下淡影子）＋左下起床自評（只有臉＋字、不寫 You felt、不加框，11-14 使用者定）＋右下 notes 日記本（**這一晚的 notes（這個 version）還沒看過就每隔幾秒抖一下、右上角一個紅點**，看過或減少動態效果時靜止；看過沒看過用首頁同一份 `NotesReadStore`） → 那句話置中（背景是使用者生成的日出 `assets/backgrounds/report_dawn.jpg`，壓一層薄深藍、下緣淡成透明接到報告背景——**淡成某個顏色會多一條分界線**；讀不到圖退回程式畫的山丘）→ 大字 Lv.6、「Your experience」＋右邊這一晚的 +N XP、經驗條（**沒有卡片框，直接在草坡上**；「215 / 400 XP」寫在條裡；條只有**白與金兩種顏色、不畫分隔線**（11-14 使用者定）：之前累積的是白，這一晚那段金色（`xpBarSegments()` 只排版不算 XP）；+0 的晚上沒有格子、+0 XP 照寫）→ 那句話置中（背景圖要蓋到經驗條，所以是 2:3、下半是一整片平整草地）
→ **Last night 圖形格子**（11-17 起 From your buddy 那張卡整段搬進日記本，`pet_notes_test.dart` 守著不再出現） → Sleep phases → **Yesterday 圖形格子**
→ View sleep insights → Back to home。

**圖形格子**（2026-11-14 使用者定，參考圖：每一格的圖就是那個數字，`widgets/report_tiles.dart`）：
**Last night 的格子（11-15 使用者定 Q1–Q7）**：同 Yesterday，`ReportArtTile` 整張是圖、標題左上、字左下（圖在 `widgets/last_night_art.dart`，**圖就是那個數字**）：Total sleep＝極光光帶從左往右填（睡了多久÷目標，超過就滿、不變色；**不放月亮**；手錶還沒到是虛線框＋暗光帶＋「—」）；Time in bed＝**12 小時鐘面**（使用者給參考圖：12 在上、順時針，上床＝月亮圖示、下床＝鬧鐘圖示，那段亮；多久寫在圓心、時刻寫在底下；超過 12 小時畫滿一圈）；Phone down＝半圓鐘面，空心圈＝目標、亮點＝實際（同一色不分好壞）；**點開頁最上面「This night」一塊**：「Start Sleep 03:20 → phone down 03:27」＋「7m after Start Sleep」（11-15 使用者定放在點開的頁、不放格子上：照抄後端 `phone_in_bed_minutes`＝lights_out − bed_start，是下界、滑到睡著的晚上偏大；沒按 Start Sleep 整塊不出現、不寫 0）；Awake＝星河上醒著的幾段亮琥珀色；Sleeping HR＝**靛藍慢線、不跳、不放月亮**（跟會跳的珊瑚紅 Awake HR 分開，靜止心率只在這一格；**點開的頁也用同一個靛藍**，使用者：裡面的顏色不統一）；Movement (camera)＝**光柱**（使用者給參考圖）：每 5 分鐘一根、高度＝那 5 分鐘有幾成時間在動（後端 motion_curve 照抄、不平滑），越高越從淡紫轉金色、帶光暈；0＝沒動是真的值，畫很淡的短柱；底下時間軸標整點（夜長 ≥4 小時每 3 小時）、兩個下角淡雲；**大字＝一小時動幾次**（11-15 使用者定：後端 `events_per_hour` 四捨五入，「18 moves / hour」），後端那句「跟平常比」照抄成小字、沒有次數時退回那句當大字；🔴 **不放文獻常模**（Montini 11 次／小時）——事件率跨夜不穩 3.1 倍、我們的「一次」跟文獻不是同一個構念，並列會被讀成「比一般人多」；**點開頁的「Movement through the night」也是同一套光柱**（柱頂＝原本的線高，片段的點與點選泡泡位置不變）；**排最後佔整列、高 210**；**Efficiency 維持「從底下填滿」**（使用者喜歡，只嫌靜態）→ 頂端水面輕輕晃、光點往上浮（`LiquidFill`），減少動態效果時靜止，填多高照舊＝效率；跟上一晚比的箭頭在大字右邊（`ReportArtText.valueTrailing`）。順序 Total sleep · Time in bed／Phone down · Awake／Sleeping HR · Efficiency／Camera。這一輪**只換格子，點開的頁不動**。以下是各格點開的頁：
Last night＝睡多久（格子標題 **Total sleep**，11-15 使用者定，原本的 Time asleep 讀起來怪；波浪光帶＝睡了多久÷目標；**點開是一週圖**，同首頁 Sleep 小卡，`widgets/sleep_week_sheet.dart`：這一晚往回 7 個日曆晚上、沒資料的晚上寫「—」且**不算進平均**（寫「5 of 7 nights with data」）、目標畫虛線、長條**不依達標變色**；這一晚的數字以報告為準，11-14 使用者定。樣子照參考圖：膠囊長條＋底槽到頂、左邊 0–12 h 刻度、底下圓環＝平均÷目標；**參考圖的「Your sleep improved by 6%」不照做**（improved 是判斷），改寫「↓ 3m vs the week before」，只代表方向、上升紅下降綠；標題跟外面那張卡同圖示同顏色同字型）、臥床（18:00→12:00 時間軸上的上床／下床；**點開是一週上床圖**，`widgets/bed_week_sheet.dart`：左邊是時鐘、每晚一根膠囊從上床畫到起床，看幾點睡的規律性；**按鈕上床＋下床都有才用按鈕、不然退回手錶入睡→醒來**（使用者定），手錶的晚上畫空心並在底下說明幾晚是手錶的——兩個不是同一個量；11-15 使用者試過 B 案（淡色帶＋月亮＋四項圖例）覺得太複雜，簡化成：**數字放最上面**「Usually in bed 03:02 → 08:00」（上床、起床各自的**中間值**——平均會被一兩個特別早或晚的晚上拉走，那週平均是 02:14）＋平均臥床多久；圖上**兩條白色虛線就是那兩個數字**（時刻寫在**圖裡、線的左端**，**只有淡白色的字、不加框**（使用者定：框會擋住最左邊那根長條；字再淡一點不搶膠囊，加一點陰影才讀得到；虛線從字的右邊開始、不穿過字）；**左邊刻度照常全部顯示**——使用者兩個都要，放右邊外面又會讓圖上下空空的，≥3 晚才畫；淡色帶不放——兩條線＋膠囊已經看得出哪晚偏離，帶子要另外解釋）；只留一行小字「Hollow = watch」；按鈕與手錶的晚上一起算；**不說規律好壞**；按鈕時間由 `/insights` 的 `behavior.history` 順便帶回（`CameraInsightsResult.bedButtons`），這一晚以報告上的為準；**躺多久才睡著**（11-15 grill 定）：按鈕的晚上從上床到**手錶認定睡著**那段畫淡、交界一條白線，最上面「This night」寫「Start Sleep 03:20 → asleep 03:33」＋「Fell asleep 12m after Start Sleep」；當下按、事後補的都算不另外標；**手錶在按鈕之前就睡著（負數）那晚不畫、不寫**；不套文獻 30 分鐘切點、不說好壞。手錶入睡時刻來自 `/insights` 的 `wearable.history[].sleep_start_time`（`CameraInsightsResult.watchSleep`，比打包檔新），這一晚用報告的。⚠️ **只比牆鐘**：手錶時刻是 parseWallClock 的 UTC 標記牆鐘、按鈕是本地時間，直接相減差 8 小時（11-15 真資料預覽抓到，每晚都被當成入睡晚於下床））、Phone down（半圓弧上目標與實際兩點；**點開是一週放下手機圖**，`widgets/phone_week_sheet.dart`，11-15 使用者定：第一版是一晚一列、橫的時間軸，使用者覺得不好看，改成 **B：跟 Total sleep／Time in bed 同一套**——7 欄、左邊時鐘刻度（上早下晚）、每欄一條底槽，每晚一個點＋點到目標虛線的細棒（離目標多遠），時刻寫在點旁邊（遠離目標那一側），目標的時刻用白色粗字寫在刻度上，舊的在左、這一晚在最右邊；最上面「Usually phone down 03:03」（中間值）＋「N of M nights over 30m past your 03:00 target」（11-15 使用者定寫出 30m：只寫 later 的話 03:26 晚於 03:00 卻沒被算，像算錯；那個 30 是 `kLateThresholdMinutes`，只用來寫字，`phone_week_test` 直接讀 adherence.py 比對）——**晚不晚只照抄後端每一晚的 `is_late`**（跨午夜只在 adherence.py 算；後端沒判的晚上不進 M）；圖上只有一條目標虛線（現在的目標）；**點全部同一個顏色、不分紅綠**，這一晚亮一點；沒資料寫「— no data」不畫 0；**12:00–18:00 的放下手機不算那一晚的就寢**（11-15 使用者定，實例 10-05 偵測成 14:07、晚 607 分鐘），當作沒資料、不進中間值與晚幾晚；11-15 使用者另選 A＋C：A＝按了 Start Sleep 之後手機還在用多久（照抄後端 `phone_in_bed_minutes`），11-15 grill 改成**圖底下一排小長條**「Phone use after Start Sleep」（取代原本星期底下的「+7m」）：欄位跟上面對齊、**這一排自己的刻度**（最長那晚＝滿、至少 5 分鐘高）、數字寫在柱子上、一個顏色、不分紅綠、沒有目標線；事後補的上床也算；**沒按 Start Sleep 寫「—」不畫 0**，一晚都沒按整排不出現（⚠️ 不畫成點上方的一段線——實際多半只有幾分鐘，在圖上 2–3 px 整段藏在點後面），**標題下「↑ 14m later than the week before」**（這週中間值 vs 前 7 晚中間值，同 Total sleep 只代表方向、晚了紅早了綠，前一週沒資料不寫）；時刻由 `/insights` 的 `behavior.history` 順便帶回（`CameraInsightsResult.phoneDowns`），這一晚以報告上的為準）、
Awake（整晚一條、只亮清醒段；**點開是 `widgets/awake_week_sheet.dart`**，11-15 使用者定：上半**這一晚**——大數字是手錶的總數（不是段落加總），入睡→起床一條時間軸亮出清醒段落，下面每段一個小標籤「03:42 · 1m」（照時間排、多了換行不藏，不到 1 分寫 <1m），**醒了幾次**（11-15 grill 改：原本不寫）——大數字底下「Woke up 2 times · 2m in total」、一週每根長條底下「×2」，**0 次寫 ×0、沒資料（Health Connect 的晚上）寫「—」**；次數＝**還原的時間軸上清醒的段數**（`garmin/sleep_stages.awake_count`，跟畫出來的段落同一份），存在 `wearable_nightly.awake_count`，由 `/home` 的 `metrics.awake_count` 與 `/insights` 的 `wearable.history[].awake_count` 帶出；🔴 **不是 summary 的 `awake_count`**：那個把入睡時刻的整晚摘要也算成一次，**每晚多 1**（11-15 真資料預覽發現，124/124 晚都正好差 1；Tier3 是跟自己平常比，固定多 1 互相抵掉，評分不動）。舊夜晚回填：`migrate_garmin_to_db.py --awake-count-only [--standard 原始檔]`，只補這一欄、寫完逐晚重算核對；沒有時間軸的晚上只寫總數＋「No timeline for this night」。下半**這一週**——同 Total sleep 的 7 欄膠囊，平均／幾晚有資料／跟前一週比**直接用 sleep_week_sheet 的函式**，**0 分寫「0m」算進平均、沒資料寫「—」不算**，沒有目標線；一週資料來自 `/insights` 的 `wearable.history[].waso_minutes`（`CameraInsightsResult.awakeMinutes`），連不到後端整段不出現。不判斷好壞、不掛手錶準確度警語）、Efficiency（**11-15 使用者定照參考圖（Battery 卡）改成從底下往上填滿**（`ReportFillTile`，填多高＝效率、取代圓環，數字左下、% 小一號，下面一行是那一種的名字）；**點開是 `widgets/efficiency_sheet.dart`**，11-15 使用者定：上半**這一晚**——數字照抄（只把 100.0 寫成 100），下面是那一種的**名字**（`composition.efficiency_label`，字只在 `score_claim.EFFICIENCY_BASIS_LABELS`，**機器標籤 `Basis: …` 拿掉**），一條「算進去的時間＝整條、睡著＝亮的」＋「6h 16m asleep of 6h 18m counted」＋分母那兩個時刻（① 兩個按鈕、② Start sleep→手錶醒來、③ 手錶入睡→醒來；**百分比不在 Dart 重算**，分鐘只是說明），**只有 ③ 多一行請按按鈕的提示**；**不放警語**（使用者定：上面的分子分母已經說明怎麼算的；⚠️ 2026-11-19 起分數卡也拿掉了，**警語只留在書面報告**，App 上一處都沒有）；**不畫 85% 線**。下半**這一週**——0–100%、**畫面上只分兩種**（11-15 使用者定）：有按按鈕（①②）**實心**、沒按（③）**空心**（同「空心＝手錶」）——② 只按了 Start sleep 也算有按，後端給 ①② **同一個名字 `Sleep button`**、③ 是 `Watch only`，**計分照舊三段式**，② 的分母差在哪由那一行「Start sleep → watch wake」交代；數字照抄；**不算平均、不比前一週**（三種不是同一個量，③ 幾乎都 100%），標題是**一個名字一行**、各幾晚（同名就合成一行，Dart 不寫死哪幾種算一組）；**後端沒給名字的那一種不寫，Dart 不自己取名**。種類靠那晚 behavior 自己帶的 `*_basis` 對出來（`efficiencyKindOf`，不寫死 basis）；每晚的數字跟格子**同一支** `scoredEfficiency`，這一晚的長條用報告的數字蓋過去）、心率（睡著那段的小折線；**格子標題 Sleeping HR**（11-15 使用者定：講清楚不是整天的；格子窄寫縮寫，點開的標題寫全名 Sleeping heart rate）；**點開是 `widgets/heart_rate_sheet.dart`**：上半**這一晚**——大數字＝睡著那段的平均（同格子），「Lowest 46 at 03:48 · 18m after falling asleep」（最低與那一刻都是**原始讀數**，後端 `min_at`；5 分鐘平均的最低會跟 min 對不上）＋「Resting 55 (all day)」；線**依那一刻的睡眠階段上色**（同 Sleep Stages 的顏色），虛線＝平均、白點＝最低，點／滑看那一刻；下面各階段的平均心率（線上的點照階段分組，沒量到 REM 不給）。⚠️ **參考圖的運動心率區間不照做**：那是最大心率的百分比，睡著全落在最低一區以下，且睡眠心率沒有文獻門檻（紅線 2）；**不寫 Normal／High、不寫最高**（最高多半是短暫醒來）。「夜間心率下降幅度」（<10% 有死亡率關聯，但證據主要來自糖尿病族群）11-15 討論過、**這一輪不做**，要做先寫進研究文件。下半**這一週**——7 欄，實心點＝平均、空心點＝最低；「Usually 56 bpm」＝7 晚平均的**中間值**，跟前一週比只代表方向；靜止心率是整天的另一個量，**不進一週圖**。一週來自 `/insights` 的 `wearable.history.sleep_heart_rate`（跟格子**同一支** `night_heart_rate`，只有 Garmin 來源有），這一晚那一欄用報告的數字蓋過去）、攝影機（小折線＋後端那句；**點開是 `widgets/movement_sheet.dart`**，11-15 使用者定（照參考的監視器 App 版面）：**順序是 摘要 → 播放器 → 動作線 → 每小時 → 一週 → 片段列表**；後端那句「跟你平常比」＋「105 movements · 25m moving in total」（次數照抄 `events_total`，11-15 使用者改：原本 11-09 定不寫；總共動多久＝每段秒數加起來；**不寫每小時平均、不跟常模並列**）＋not part of your score；**動作線**（11-15 使用者改回：線比膠囊好看；畫**整段錄影**那條＝`/insights` 的 `camera.history[].motion_curve`，不剪成睡著那段，才跟每小時次數涵蓋同一段時間；每 5 分鐘有幾成在動，片段時刻的點**畫在線上那一刻**（不是貼底線）、白線＝正在看的；**按住左右滑有泡泡**「03:42 · moving 12 sec · Light」（同 chart_probe 的規則：吸到最近的真實讀數、不內插）；**滑到或點到某段動作 3 分鐘內，泡泡吸到那段的點、寫那段動作，影片跟著換成那段**（11-15 使用者：原本滑的時候影片不動，泡泡跟正在播的像兩個不同的點）；沒有線才退回膠囊時間軸）；段落之間有細線分隔；**每個鐘頭動幾次**（頭尾不滿一小時的畫淡、寫涵蓋幾分鐘）；**播放器**循環播選到的那段，影片上有**觀景窗框**（四角括號、左上「● 04:10」、右上「2 / 10」；**不寫 REC**，是錄好的片段），點畫面全螢幕、兩指放大；底下一條圓角**控制列**（照使用者給的參考圖）：⏮ ⏯ ⏭（中間是暫停／繼續：GIF 停在當下那一格、畫面左下寫 Paused，**換一段就從頭播**）＋一顆主色的 Full screen 大鈕，選到沒有片段的動作寫「No clip for this movement」（**不跳去播別段**）；**片段列表**照時間排（縮圖＋大的時刻＋「moved for 21 s · Light」）。每段動作來自 `camera_nightly.motion_episodes`（`tapo_sleep_onset.motion_episodes()`，**跟 events_total 同一個定義**，個數一定一樣；`/insights` 的 `camera.history[].episodes` 帶標籤，**跟片段同一支 `camera_clips.label_for`**；舊夜晚用 `migrate_camera_to_db.py --curves-only` 回填，只補曲線與每段動作）。片段的 `start_at` 就是那段動作的開始，可以直接配對。標籤後面接**那一刻手錶的睡眠階段**（三種時間基準要換成同一種）。下半一週——7 欄每晚的 `usual.delta_pct` 從中線往上／往下，灰帶＝「差不多」，**寬度照抄後端 `usual.same_as_usual_pct`**（Dart 不寫 25，舊版後端沒給就不畫）；**只用一個顏色**（動得多不代表睡不好）。不做「最長靜止多久」、不放整夜錄影（一晚約 460 MB、只在電腦上、要另裝播放器外掛）；
Yesterday＝步數（**11-15 使用者定照參考圖 Step Counter 改成圓弧**：填多少＝步數÷那天的目標，**超過就滿圈、不變色、不打勾、不寫 reached**；中間人形＋大字、下面「Goal 9,540」、最底「3.7 km · 10 floors」；**點開是 `widgets/steps_sheet.dart`**：上半那一天——大圓弧、「Goal set by Garmin, changes daily」（Garmin 每天自己調目標）、距離／活動卡路里／活動時間／爬樓，**每個鐘頭走幾步**（24 根，點／滑出「14:00 · 1,230 steps」；沒戴錶的鐘頭空著不畫成 0、有戴走 0 步畫細線；不寫加總——大數字已是官方總數。2026-11-15 實抓 30 天：照當地日期切後 96 格加起來與官方**逐天相同**；「none＝沒戴錶」那 30 天沒出現過，還沒在真資料上驗證）；下半這一週——7 根，**目標畫成一根淡色空長條、走了多少從底下往上填**（11-15 使用者：原本只有一條目標線太空；超過目標就長出空條上緣、不變色；沒資料的那天只剩空條），「Usually」＝中間值，跟前一週比只代表方向；**0 步＝沒戴錶 → 「—」不算**；只用一個顏色。不放 Move IQ（有自己的格子））、**活動卡路里**（11-15 使用者定拆出來自成一格，緊接 Steps 右邊：大字＋最近 7 天小長條，小字「active only, not total burn」，**點開是 `widgets/kcal_sheet.dart`**（11-15 使用者定，參考圖 My Diary）：上半右邊圓環＝一整天總消耗（淡＝靜止代謝、亮＝活動），左邊 Resting／Active 兩行，底下寫明兩個都是 Garmin 估的；**參考圖的 Eaten／kcal left 不做**（沒有飲食資料，「還剩多少」是好壞判斷）——不給目標、不寫剩多少；靜止代謝與總消耗是同一個 `get_stats` 的 `bmrKilocalories`／`totalKilocalories`（`garmin_daily.resting_kcal`／`total_kcal`，**舊日子不特地重抓**，沒有就不畫圓環、只畫活動大數字）；下半一週 7 根活動卡路里，Usually＝中間值、比前一週只代表方向、0＝沒資料寫「—」；不做三餐卡片）、**活動時間**（11-15 使用者定，參考圖 Activity：**一座山＝一整天 24 小時**，漸層由下往上 睡（深藍）→ 坐（淺藍）→ 活動（橘）→ 高強度（山尖），**每一段的面積＝那段的比例**——照面積切不照高度切（三角形分界在 √累積比例；照高度切的話 5% 的活動只剩山尖一個點），段之間只留很短的過渡；太陽只是裝飾；大字＝高強度＋活動，小字「high 12m · still 16h 20m」，**參考圖的 Perfect day 不照做**。**點開是 `widgets/active_sheet.dart`**：24 小時圓環四段＋左邊四行、**一整天的時間軸**（每 15 分鐘一格依 Garmin 的程度上色，沒戴錶空著；Move IQ 是上面的白線；點／滑出「09:00–09:15 · Active · 736 steps」；Garmin 的 `generic` 意思不明，照實標 Unlabeled）、一週（高強度疊在下面、Usually＝中間值、比前一週只代表方向、0＝沒資料寫「—」）。⚠️ **睡是 Garmin 以日曆日切的 `sleepingSeconds`**，跟「昨晚睡多久」不是同一個數字：只當顏色、四行裡標 `Asleep (this day)`，不在別處寫。舊日子沒存這欄時後端用「86400 − 其他三種」補（Garmin 四種加起來剛好一天，實測兩天）。⚠️ **不放強度分鐘與 150 分鐘週目標**：這支錶給 0，而且那是 WHO 對中高強度運動的建議，Garmin 的活動時間不是同一個量。久坐只寫時間、不寫坐太久。每 15 分鐘的程度存在 `garmin_daily.activity_quarters`（同 steps_hourly：只在 /home，打包檔不帶）。第五輪：**鋪滿整張卡、山胖一點（兩邊 t^0.7 往外鼓）、不要太陽**、字在左下。同日第二輪（照參考圖）：**輪廓不規則**（`mountainEdges()`，分界改成對實際輪廓數值積分，測試直接積分驗算每段面積）、邊緣一圈淡淡的亮光、大字小字**疊在山的中間**、過渡柔一點、顏色換成珊瑚橘→桃→淡紫藍→藍）、**壓力**（11-15 使用者定，參考圖 Stress 卡：**半圓從底邊長出來、置中、比半張卡大（半徑 0.62 個卡片高，窄卡片時左右被卡片邊緣切掉），平均數字在半圓左邊**（第六輪定案；之前試過右上方露一角、貼底、上半、字在圓心。**圖鋪滿整張卡**——`ReportArtTile`，**底色維持報告的半透明紫**（第四輪試過近黑，使用者要回半透明紫）、標題疊左上；半圓像打了光的球：外圈光暈、左上亮、右下暗、亮邊，色帶過渡柔一點但每段面積不變。⚠️ **貼底之後不准讓底邊淡出**：會吃掉最下面「休息」那段（通常最大），比例就不準），由上往下 高 → 中 → 低 → 休息，**每一段的面積＝量到的時間裡各程度的比例**（對實際形狀數值積分）；**紫色系、不用紅黃**（11-13 的規矩，參考圖的橘紅不照做）；大字＝平均壓力，**不加 %**（Garmin 的是 0–100 分數，加 % 會被讀成「56% 的時間有壓力」）、**不寫 Elevated**。**點開是 `widgets/stress_sheet.dart`**：圓環（只算量到的時間）＋四行＋「Not measured …（moving or watch off）」（`activityStressDuration`＋`uncategorizedStressDuration`，舊日子沒存就不寫）；**一整天的壓力線**（`sleep_heart_rate.day_stress()`，每 3 分鐘＝Garmin 原本的間隔、不平均；量不到的空檔斷開；25／50／75 淡線標 Garmin 自己的四個名稱；睡著的時段淡底色、來自 activity_quarters；點／滑出「14:21 · 62 · Medium」，離讀數超過 3 分鐘寫 no reading、不內插）；一週（各程度疊起來、高在最下面最亮、Usually avg＝中間值、比前一週只代表方向）。⚠️ **平均是「每 3 分鐘讀數的平均」**（`stress_day_averages()`），14 天實測比 Garmin App 自己的平均常少 1（11/14 天），Garmin 的算法對不上四捨五入／進位／不算 0——只用一套（從讀數算，05-28 起每天都有、跟那條線同一份資料），畫面寫明。不提睡眠分數、不給呼吸之類的建議）、
Body Battery（**兩根柱子不畫電池**：只有充／耗、沒有剩幾 %）、**Awake HR**（11-15 使用者定，參考 Apple Watch：**發光的珊瑚紅愛心跟著醒著的平均心率跳**，減少動態效果時靜止；大字「78 BPM」、小字「peak 150 at 17:20」。**只放醒著的平均、最高、各區間時間**——**不放靜止心率、最低**（靜止心率在報告上半部已經有）、**不寫 Normal／High、不比平常**：`Research-Background/心率門檻.md` 查過，醒著的平均心率沒有結果關聯的切點（臨床「>80」套上去本人 76 天裡 47 天會是 High），又主要取決於那天走了多少路。醒著＝那個日曆日扣掉**手錶那兩晚的入睡→起床**聯集 **activity_quarters 標 sleep 的格子**（`sleep_heart_rate.awake_heart_rate()`）；跟上面的 Sleeping HR 分開、不混。區間是 **Garmin Connect 裡本人的設定**（`GARMIN_HR_ZONES`：最大 199、下緣 100／119／139／159／179），不是文獻門檻、畫面寫明「max 199」、不說哪一區好；⚠️ 只對本人成立，換人戴要重讀 Garmin 的設定。**點開是 `widgets/awake_hr_sheet.dart`**：平均＋最高、整天的線（每 2 分鐘的原始讀數、空檔斷開、睡著那段畫淡寫 Asleep · see Sleeping HR、Move IQ 底下細線、點／滑出「17:20 · 150 bpm」，離讀數超過 2 分鐘寫 no reading）、各區間幾分鐘、一週（點＝醒著平均、線到最高，**沒有 Usually、沒有跟前一週比**）。`awake_heart_rate` 只在 /home（打包檔沒有每晚的入睡時刻）；沒有時退回原本的整天心率格子）、**Move IQ**（11-15 使用者定：**24 小時鐘面**、00 在上、有動的時段亮一段弧（走路綠、其他藍），大字「2 walks」（混了別的寫 moves）、小字總分鐘數；🔴 **騎車（cycling）不顯示**：使用者多半騎機車，手錶分不出機車與腳踏車——08-28 起 79 段騎車每分鐘步數中間值 22、多數時段 Garmin 標坐著（走路是 90），放進來會把騎機車讀成運動。**資料照存、後端照給，只在畫面濾掉，一處：`move_iq_sheet.moveIqShown()`**（Awake HR 線圖底下的標記也走它）。代價：78 天裡 52 天剩不到一段 → 那天整格不畫，使用者知情。其他類型**照 Garmin 寫、不用步數改**（一段每分鐘 156 步的 swimming 照寫 Swim）。**點開是 `widgets/move_iq_sheet.dart`**：說明一句（Rides are left out — most are scooter trips）、那天的清單「Walk 17:42–17:56 · 14m」、最近 7 天每天幾分鐘；**不寫每段走了幾步**（只有 15 分鐘的格子，會把前後沒動的時間算進去）、**不比平常**。history 的 `move_iq` 只在 /home）。
⚠️ 底下那行只寫事實（參考圖的 Elevated／Perfect day 不照做）；沒值的格子不畫、不畫成 0；兩個一列一樣高，單數的最後一格佔整列。
⚠️ **點格子開的詳細頁一律用 `widgets/report_sheet.dart` 的 `showReportSheet()`**（2026-11-15 實機發現：內容一長就撐滿螢幕、標題頂到狀態列，頁裡的捲動又吃掉往下拉、關不掉）：最高 88% 螢幕、避開狀態列、頂端拉桿、**捲到最上面再往下拉就關**（`report_sheet_test.dart` 守著，拿掉修法那條會紅）。新的詳細頁不要直接呼叫 `showModalBottomSheet`。
字是 **Nunito**，只用在報告與自評卡（`assets/fonts/nunito/`，OFL；官方只出可變字型，切成五個固定粗細，
**刻意不裝 `google_fonts`**——它會在執行時上網抓字）。

| 規則 | 理由 |
|---|---|
| 分數、等級、心情、那句話、AI 那段、小建議、效率警語**全部照抄後端**；連不到才用打包檔那一晚 | Dart 不判斷好壞 |
| **沒有分數時不顯示分數也不顯示睡眠長度**（Time asleep 是「—」），寫 `Waiting for your watch data`，虛線圓環＋睡姿小狗，**也不問 `/night-summary`** | 剛起床時手錶資料幾乎一定還沒到，畫 0 或上一晚的數字都是編造 |
| 那句話用 `display.mood_description`，**不用 `mood_reason`** | 後者是規則標籤（`final_quality=Good`），不是給人讀的 |
| 不放晚數、日期圈圈列、最近 7 晚長條圖（使用者定：**只放這一晚**）；不放「Great work」、不另外發 XP | 紅線 5 |
| **「+N XP」照抄 `/game` 的 `recent_nights`**，差的晚上照實寫 +0；手錶還沒到寫 `so far`；後端還沒有這晚就不畫 | 好晚上回饋多、差晚上回饋少，規則只在 `game/xp.py` |
| 跟上一晚比（Time in bed／Time asleep）照抄 `previous_night`，**上升紅、下降綠、只代表方向**；沒有上一晚不畫 | 與首頁同一條；睡得多不一定好 |
| 睡眠目標＝轉盤「就寢→起床」的長度，**只寫「of your 8h goal」，不寫 reached、不變色** | 好壞只有後端能判斷；分數以時長為主，兩個說法會打架 |
| 達成度那一行（`2h 12m after your target`／`On time`）**只照抄 `adherence_minutes`**，沒有後端就整張 Phone down 卡不出現 | 跨午夜只在 `behavior/adherence.py` 算 |
| 報告的效率是**進分數的那一個**：依 `composition.efficiency_basis` 去 behavior 找同一個 basis 的欄位，都對不上才用手錶的；**basis 字串不寫死在 Dart**，畫面上照列 basis 與警語 | App 裡有五個叫「效率」的數字，只有 basis 分得開 |
| 攝影機只顯示後端那句「跟你平常比」＋「not part of your score」 | 攝影機計分項 0 項 |
| Sleep phases 圖用 `/home` 的 `metrics.sleep_stages`（Garmin 來源每晚都有）；沒有就比例條 | — |
| 比例條要後端的 `light_minutes`（總睡眠 − 深睡 − REM），**沒量到 REM 時是 null** | 減出來的淺睡會把 REM 吃進去 |
| 沒按按鈕時 Time in bed 是「—」、寫 `No bedtime recorded`，**不拿手錶的入睡冒充上床** | 入睡不是上床 |
| Cancel 不開自評也不開報告：睡覺畫面只有真的結束才呼叫 `onEnded`（Cancel 是自己 pop） | `morning_report_test.dart` 守著 |
| 日期自己組（`reportDateTitle`），不用 intl 的 DateFormat | 那會跟手機語言走 |

**起床動畫**（2026-11-13，`feature/wake-animation`）：

| 規則 | 理由 |
|---|---|
| 有 `assets/pets/dog01/wake_up.gif` 就播它（鋪滿畫面，上面疊 Good morning＋起床時間），**長度照 GIF 本身**（讀檔頭每格的停留時間，夾在 1–6 秒）；沒有就退回程式畫的那一版 | 使用者定改用 GIF；缺檔不會報錯。現在那支是 Kling 生的，怎麼做、怎麼重做見 [WAKE_UP_GIF.md](docs/WAKE_UP_GIF.md) |
| ⚠️ **GIF 長度不准用 `instantiateImageCodec` 解碼來算** | 在測試的假時鐘底下永遠不會完成，畫面卡在空白（2026-11-13 踩過）；改成 `gifDurationFromBytes()` 讀檔頭 |
| 🔴 **從睡覺畫面到報告，一格都不能露出首頁**（首頁有分數卡）：每一步都是「新的一頁蓋上來，才收掉底下那一頁」——睡覺畫面與自評卡都**不自己關**（`onEnded`／`onDone` 交給首頁），起床動畫播完也不自己關；減少動態效果時自評卡直接出現不滑 | 自評要在看到分數之前問。11-13 實機錄影抓到露出半秒；同日測試又抓到「睡覺畫面先關、讀手機儲存那幾格露出首頁」。⚠️ `morning_report_test.dart` 的逐格（16 毫秒）檢查要用 **`slowStore: true`**——記憶體版儲存當下就回來，那種錯在測試裡看不到 |
| **只說「Good morning」**：不放彩帶、金幣、XP、分數、Great job | 起床那一刻分數多半還沒到，慶祝＝每晚都誇（紅線 5）；而且排在自評之前，會把答案帶偏 |
| 程式版醒來的小狗用**首頁那一份心情**（後端 `pet_mood`），不自己挑 happy | 同 `HomePet`：不認得的一律 bored |
| 點一下跳過；系統開「減少動態效果」**整段不播** | 與首頁的流星同一條 |

**等待畫面**（2026-11-13，`feature/report-loading`）：自評卡之後、報告之前。

| 規則 | 理由 |
|---|---|
| 等分數那份（`/home`，最多 4 秒）；**有分數時 AI 那段再多等最多 10 秒**（`kReportSummaryWait`），好了或時間到才放「View sleep report」按鈕，**不自動進報告** | 使用者定（先等分數、AI 最多 10 秒）。AI 第一次生成最多 45 秒，全等會像當掉 |
| AI 那段超時**不丟掉**：還在路上的那一個交給報告畫面，回來再補上，**不重要一次** | 重要一次＝多花一次 API 額度 |
| 🔴 **AI 那段一定在自評送出之後才要**；分數那份則在起床動畫一開始就先抓 | `/night-summary` 會讀自評（標籤、你覺得怎樣），先要的話寫出來的不含自評 |
| 手錶還沒到（沒分數）不要 AI 那段、按鈕直接出現；連不到後端也照樣出按鈕 | 報告裡會照實說在等資料／打包檔 |
| 等待畫面不放分數、XP。畫面是**小狗在早晨臥室翻夢境日記**的循環 GIF（`report_wait.gif`，接著起床動畫最後那個房間），減少動態效果時用同場景靜止圖；讀不到才退回星空＋首頁那一份心情的小狗 | 同起床動畫。怎麼做、怎麼重做見 [REPORT_WAIT_GIF.md](docs/REPORT_WAIT_GIF.md) |
| 關報告直接回首頁，等待畫面不會又冒出來（報告蓋上之後就把它收掉） | — |


**起床自評卡**（`services/morning_rating.dart`）：

| 規則 | 理由 |
|---|---|
| 題目、五個選項、十個標籤與 `behavior/morning_tips.py` **逐字相同**（題目的「woke-up」連字號照抄 CSD 原文）；`morning_rating_test.dart` 直接讀那支 Python 與研究文件比對 | Dart 另存一份只為了離線也畫得出來，漂移時不會報錯 |
| 卡片上**不出現分數**；Skip 永遠按得到、不送任何東西、不擋報告 | 看到分數之前先問 |
| 先存在手機上再送；連不到（`retryLater`）下次開首頁補送，4xx 不再送 | 報告離線也畫得出 You felt；格式錯的再送也一樣 |
| 首頁補填小卡：**起床 6 小時內、那一晚還沒填**才出現（Skip 過也照樣出現）；記下起床後幾分鐘才填 | 使用者定；分析時可以只取一小時內的 |
| 不換寵物心情、不改那句話、不給 XP | 不進分數（紅線 4） |

#### 早晨報告的後端（2026-11-12）

| 規則 | 理由 |
|---|---|
| **起床自評**（`POST /rested`、表 `morning_ratings`）題目照抄 Consensus Sleep Diary-M 第 10 題；**不進分數、不給 XP**；給不給好友看由本人選（2026-11-15 起，**預設關**） | `test_morning_report.py`【4】存了「很累」與「很有精神」前後比分數與 XP，並掃 `garmin/`、`game/` 不得讀它、`social/` 只准 `sharing.py` 讀 |
| 標籤只收 `behavior/morning_tips.TAGS` 的 id，不收自由文字 | 隱私、無法統計，送進 AI 還可能被拿來改寫指令 |
| 記下 `minutes_after_wake` | 日誌標準是起床一小時內；App 允許 6 小時內補填，分析時可以只取 ≤ 60 的 |
| **建議清單 20 句（T1–T12＋P1–P8）只在 `behavior/morning_tips.py`**，措辭與 `Research-Background/起床小建議與自評.md` 逐字一致（測試【2】讀文件比對） | 改措辭先改文件；句子由使用者審過（P 系列 11-18） |
| ⚠️ T1（晚 30–59 分）與 T2（晚 ≥ 60 分）**不重疊** | 原本 T2 是 ≥ 60、T1 是 ≥ 30 且優先，T2 永遠輪不到（寫程式時發現） |
| **寵物 notes**（2026-11-17 使用者 grill 後定，取代夢境日記與 From your buddy；**推翻 11-12 的「AI 不寫建議」**）：`/night-summary` 回 `summary`（AI 寫，≤2 句）＋`tips`（AI **只能從後端今晚推薦的那幾條**挑 0–3 條、換成寵物口吻，`original` 附原句；11-18 起交給 AI 的清單只有推薦的、驗證也擋別的——11-17 AI 自己挑了沒觸發的 P4 還把意思寫反）＋`version`（依回傳內容算，App 用它讓紅點再亮）。`text`／`tip` 是舊版 App 的欄位 | 使用者要 AI 實際幫忙改善睡眠；**行動只能來自清單**，驗證擋清單外的 id、換掉重點字（`KEYWORDS`）、總結裡塞建議 |
| 交給 AI 的是**整晚資料＋後端判讀**（`ai/night_summary.judge_night()`：評分器的級距常數、心率用 Tier3 修正值＋`ANXIOUS_HR_CONFIRM`）；同一份判讀也給 `morning_tips.triggered()` 挑原句 | AI 不自己判「45 分鐘深睡算少」；判讀不另訂門檻 |
| 🔴 **攝影機與 Garmin 壓力不交給 AI**；昨天的步數要給，但**不准當成任何一晚的原因**（Atoui 2021 逐日研究不支持）。研究文件「AI 不准說」那張表能用字串抓的在 `FORBIDDEN_CLAIMS` 擋（`test_morning_report.py`【6c】【6d】） | 攝影機 11-09 驗證過跟任何結果都沒有相關；壓力對自評壓力預測力弱 |
| AI 每晚只生成一次，存 `night_summaries`（`text` 欄存 JSON）；`facts_hash`（事實＋清單）變了才重生；手錶資料沒到**不呼叫**、只給行為那幾條原句。**存的時候連同當時的事實與清單 id 一起存**（`facts`／`tip_ids`，2026-11-21），重寫前後端印一行 `night-summary: rewriting <日期>, changed: phone_down.at, tip_list`（`ns.changed_fact_keys()`）——**只印日期與項目名稱，不印 user_id、不印數值**；看後端終端機就知道是哪一項讓它重寫 | 每呼叫一次花一次額度；11-21 那晚寫好 12 分鐘就重寫，舊事實沒存、查不出是哪一項 |
| 寫不出來（沒金鑰／連不上／兩次沒過驗證）→ `summary` 是 null、`tips` 是 `applicable_tips()` 挑的原句；**不拿 `/home` 的句子冒充總結**。沒金鑰不存，失敗的存起來、**60 分鐘內不再試** | 連不上時每打開一次報告就花一次額度 |
| 驗證沿用 `ai/chat.validate_answer`，另加：全部 ≤ 120 字、總結 ≤ 2 句、每條 ≤ 2 句；**可以說可能原因但只准 might／can**，because／due to 照擋。數字：總結只能用事實裡的，每條建議只能用事實或**它自己那一句**的 | 放寬成「整份清單的數字都算」的話，P1 的 7–9 hours 會讓「睡了 9h」過關（測試抓到過） |
| 時長在事實區塊裡寫成「3h 25m less」這種字串，要 AI 照抄 | 讓 AI 自己換算，換錯了看起來也很合理；測試寫錯一個數字就被數字檢查擋下過 |
| `/home?date=` 的 `metrics.sleep_stages`：**只有 Garmin 來源**有每晚曲線 | 逐段資料只在電腦上的 `garmin_standard_data.json`（25 MB，讀一次留在記憶體，mtime 變了才重讀）；Health Connect 的逐段資料沒存 |
| `/home` 另回 `morning_rating` 與 `previous_night`（上一個有資料的晚上的臥床、睡眠分鐘數） | 「跟上一晚比」的箭頭方向由 App 比，只代表方向 |
| **一週心情列以「今天」為終點、每一格都能點**（使用者定） | 分數可能由 Health Connect 先送到，心情列要等早晨匯入才多出那晚；等待畫面叫人回首頁點這一天，那一格就必須在 |
| 只有今天剛結束的那一晚寫 `Waiting for your watch data`；更早的空日子寫 `No watch data for this night yet` | 幾天前沒戴錶的晚上，資料不會來了 |

#### ⚠️ 已知限制：18:00 以前按 Start Sleep 會被算進「前一晚」（2026-11-12 實機發現，**刻意不修**）

哪一晚 = （時刻 ＋ 6 小時）落在哪一天（`nightDateOf` 與後端 `night_date` 同一個約定）。
11-12 16:44 按、19:16 滑掉 → 算成 11-12，報告把「In bed 16:44–19:16」配上**昨晚**手錶量的 3h 35m。
⚠️ 更糟的是上傳：那一晚資料庫還沒有按鈕的話，後端 `same_night` 會**收下**這組時間，當成昨晚的上床／下床。
正常晚上與凌晨就寢不會遇到；**只有午睡會**。使用者決定不測午睡、這次不修，但要留方案：

**方案（只改 App，不動「加 6 小時」那條共用規則）**
1. 判定午睡：Start Sleep 在 **06:00–18:00** 之間按，且 **4 小時內**就結束 → 這一段是午睡
2. 午睡**不上傳**成任何一晚的上床／下床（不進 `POST /nightly`）、不配手錶資料、不開早晨報告；
   滑完改顯示一張小卡「Nap · 1h 32m」
3. 午睡**不算進任何東西**（挑戰、熬夜、效率、XP）：那些門檻都是為夜間睡眠訂的
4. 測試：16:44→19:16 不得出現在 11-12 的 bed marks；23:40→07:10 照舊；17:59 開始但睡了 9 小時（超過 4 小時）照夜間處理

⚠️ 06:00／18:00／4 小時是**設計決策**，沒有文獻。動手前先 grill：輪班工作者白天睡主覺時會被誤判成午睡。


### ⚠️ 三個已修、但規則仍然有效的地方

⚠️ **不要拿 `sleep_start_time` 當 `lights_out_at`**——前者是手錶偵測到你
「睡著」（生理），後者是「放下手機」（行為）。
（理由寫在 `migrate_garmin_to_db.py:24-27`。）
⚠️ 後者**通常**較早，但**不是一定**：**滑手機滑到睡著**時，手機要到螢幕逾時
自動鎖定才算「停止使用」，`lights_out_at` 因此落在睡著之後（09-08 晚 55.9 分鐘、
09-11 晚 21 分鐘；原因由使用者 2026-09-12 說明）。`adherence_minutes` 會多報熬夜，
`phone_in_bed_minutes` 會把那段睡眠算成滑手機。四晚實測與兩條可能的修法見
`Research-Background/攝影機分數.md` C 節末。
✅ **2026-10-22 使用者決定：走第 1 條（多收 `USER_INTERACTION`）**。還沒實作——
⚠️ 先用 `adb shell dumpsys usagestats` 在實機上確認這個事件在「滑手機」時真的
密集出現，再動 Kotlin 與 `lights_out.dart`（它可能只在點通知、開 App 時才發，
那就分不出「螢幕亮著但沒人碰」）。改 `lights_out.dart` 之前照交接區那三條規則逐條確認。

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

**② AI 夢境日記 —— 2026-11-17 退場，程式 2026-11-18 刪除**

使用者決定改成寵物 notes（AI 總結＋從清單挑的建議，見早晨報告後端那張表）。
`ai/generate_advice.py`、`ai/night_profile.py` 已刪；**`ai/data/ai_advice.json` 留著當歷史資料**
（117 筆、116 晚，全部 llm），沒有任何程式再讀它。打包檔的 `ai_content` 照舊輸出、
`dream_summary` 一律 null（舊版 App 讀得到這個鍵）。
夢境那幾條驗證規則裡還有用的（禁用字、中文洩漏、拼字數字）搬到 `ai/text_guards.py`，
⚠️ **讀 `ai/.env` 金鑰也從夢境程式搬到 `ai/chat.py`**——原本助理與 notes 都靠夢境程式在 import 時
讀金鑰，少了那一行會悄悄變成「永遠沒有金鑰」（`test_chat.py`【6b】守著）。

**③ TAPO 的 `sonnap` 資料庫不在這台機器上**

已實測確認：本機 MySQL 9.5 有在跑（port 3306），但**資料目錄裡只有系統內建的
五個資料庫，沒有 `sonnap`**，也沒有任何 `sleep_records` 檔案；
17 個 binlog 全是 198–221 bytes（只有啟動/關閉事件）→ **這個 server 從沒被寫過東西**。
→ 資料在影像組的電腦上，只能跟他們要。不必再花時間找。

✅ 但那條「請影像組跑 `SHOW CREATE TABLE sleep_records`」的待辦**可以劃掉了**——
他們 08-26 推上來的 `tapo/sleep_records.sql` 第 38 行有 `created_at`，
先前記錄的「建表後 `sleep_anylzer.py` 會 `Unknown column`」在新檔裡不存在。

### 工作位置（重要）

**真正的 git clone：`C:\Users\user\Projects\Sonnap-Project`**

⚠️ **多開 session 時用 git worktree**，那是**安全措施不是便利措施**。
目前有哪些 worktree，**看 `git worktree list`**，這裡不列，列了就會過期。

理由是這個 repo 已經因為兩個 session 共用一份 working copy 而外洩過密碼
（`8c52874` 的 `git add -A` 把另一個 session 沒 commit 的 `tapo 2.0/.env`
掃進 commit 並推上公開 repo）。各目錄**各自有 working directory 與 staging
area**，`git add -A` 在結構上不可能掃到另一個 session 的檔案。額外的好處是
**worktree 裡完全沒有 `.env`**（三個 `.env` 都是未追蹤的，只存在於主目錄）。

用完 `git worktree remove ../<目錄>` 收掉，不要放著長草。

🔴 **收掉之前一定要查「被忽略的檔案」——`git status` 不會告訴你。**
這個陷阱**已經踩過兩次**（2026-09-06 弄丟一份錄影；2026-10-04 差點弄丟
09-08 整晚的錄影 336 MB 與三份人工標註）。原因是 `.gitignore` 忽略的檔案
**既不算未提交也不算未追蹤**，所以「分支已合併 + `git status` 乾淨」
這兩個條件同時成立時，目錄看起來完全可以刪，裡面卻有只存在那裡的資料。

最容易中的是 **`data/`**（每個 worktree 各有一份 `sonnap.db`）與
**`tapo_metrics/`**（錄影、熱區圖、人工標註）。

```bash
# ① 有哪些被忽略的東西（排掉編譯產物）
git -C ../<目錄> status --porcelain --ignored | grep '^!!' |
  grep -Ev '__pycache__|\.dart_tool|\.gradle|app/build|app/ios|app/linux|app/macos|app/windows|local\.properties|gradlew|gradle-wrapper|src/main/java'

# ② 錄影有沒有只存在那裡（比對檔名，不要只看資料夾在不在）
comm -23 <(ls ../<目錄>/tapo_metrics | sort) <(ls tapo_metrics | sort)
```

有獨有檔案就先**複製出來、逐一核對大小相符**，再刪目錄。
`sonnap.db` 放到 `sonnap-data/` 底下**另開的子資料夾**，不要蓋掉現行那一份。

⚠️ 唯一跨疆界的檔案是 `app/assets/data/app_payload.json`——它是 pipeline 產物。
**動 `app/` 的 session 永遠不跑 `build_app_payload.py`**，只從 main 拿。
它被重新產生時 history 的 30 晚窗格會整個滑動（09-03 那次多了 5 晚），
所以**釘住特定夜晚的驗收測試要跟著重看**。

⚠️ worktree **不需要自己的 venv**，直接用主目錄那個：
`C:\Users\user\Projects\Sonnap-Project\.venv\Scripts\python.exe`
（腳本用 `Path(__file__).parent` 定位，資料路徑會正確落在 worktree 內）。
⚠️ **`data/sonnap.db` 預設跟著 `db.py` 的目錄走，所以每個 worktree 各有一份、
互不相通。** 2026-09-07 為此踩過坑：手機建的帳號只存在於某一個 worktree 的
DB 裡，換個目錄啟動後端就變成「查無此使用者」——症狀是上傳 404，看起來像
App 壞了。

→ 多個 worktree 同時在用時，用 **`SONNAP_DB`** 指到同一個絕對路徑，
  而且那個路徑要**放在所有 worktree 之外**（放在 worktree 裡的話，
  `git worktree remove` 會把它一起帶走——2026-09-06 的錄影檔就是這樣沒的）：

```bash
# 現行的正式位置（不在任何 worktree 裡）
SONNAP_DB=C:/Users/user/Projects/sonnap-data/sonnap.db   python -m uvicorn main:app --host 0.0.0.0 --port 8000
```

⚠️ 這是**啟動時決定一次**的；跑到一半改環境變數不會生效。
⚠️ 測試刻意**不看**這個變數（直接指派 `db.DB_PATH`），
   免得被開發機上剛好設了什麼影響。`tests/test_api.py` 有兩條互為反面的測試守著。

第一次在新位置建 DB：`python db.py --init && python db.py --seed`
再 `python migrate_garmin_to_db.py`（都要帶著同一個 `SONNAP_DB`）。

⚠️ **更上一層：跑著的後端可能根本不是 SQLite。**（2026-09-10 連踩兩次）

PR #42 把後端搬到 XAMPP 的 MariaDB（`SONNAP_DB_URL=mysql://root@localhost/sonnap`），
09-10 04:20 合併。但**跑著的 uvicorn 是 09-10 01:16 從 `Sonnap-onset` worktree 啟動的**
（比合併還早三小時）——那個目錄 checkout 的正是那條分支。而去查的人工作目錄
停在較舊的分支上，grep `main.py`／`db.py` 看不到任何 MySQL，於是**更加確信是 SQLite**。
所以手機上傳全進了 MariaDB，
而去讀 `sonnap.db` 的人會看到「少了兩晚」、做出錯的結論（實際 5 晚都在）。
四個 worktree 的 `sonnap.db` 全查過也一樣找不到，因為資料根本不在任何 sqlite 檔裡。

**為什麼查不出來**：uvicorn 的 CommandLine 只顯示直譯器路徑，而 worktree
共用主目錄的 venv，所以**所有 worktree 啟動的 uvicorn 看起來一模一樣**，
看不出工作目錄、也看不出連哪種資料庫。

→ **怎麼正確啟動**（少了 `SONNAP_DB_URL` 就會寫進空的 SQLite，資料分成兩邊）：

```powershell
cd C:\Users\user\Projects\Sonnap-Project
$env:SONNAP_DB_URL="mysql://root@localhost/sonnap"
.venv\Scripts\python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000
```

⚠️ 這份文件先前**沒有寫這條指令**，是 2026-09-12 補的。缺了它就只能靠猜，
而猜錯的代價是上面那整段（連踩兩次）。

⚠️ 症狀對照：啟動時出現
`[Errno 10048] only one usage of each socket address` **不是設定錯了**，
是 8000 埠已經有人在聽（常見原因：Claude 在背景跑了一個）。先找出來停掉：

```powershell
Get-NetTCPConnection -LocalPort 8000 -State Listen |
  ForEach-Object { Get-CimInstance Win32_Process -Filter "ProcessId=$($_.OwningProcess)" } |
  Select-Object ProcessId, CommandLine
```

⚠️ **背景啟動的後端活不過一個 session**。要整夜開著就自己在終端機跑。

→ **查資料一律先問跑著的那個 server，不要直接讀檔：**

```bash
curl -s "http://127.0.0.1:8000/insights?user_id=<id>"     # 以 server 回的為準
```

server 說的晚數跟你讀檔讀到的對不上，就是讀錯地方了。
要直接讀 MariaDB：`mysql.connector.connect(host='127.0.0.1', user='root', password='', database='sonnap')`。
⚠️ PR #42 現在合併了沒、main 上是哪種後端，**問 git 不要問這一段**。

桌面上那份 `OneDrive\桌面\Sonnap-Project-main\Sonnap-舊工作副本_勿用\` 是最初下載的 zip，
**沒有版控、已停用**。它裡面只剩三樣東西沒被搬過來，都是刻意的：`garmin/.env`（帳密）、
除錯 log、`garmin/data/_backup_20260811/`（重抓資料前的保險）。

> 為什麼不放 OneDrive：OneDrive 同步 `.git` 資料夾會弄壞 repo。

### git 狀態

**這一節只列「哪些 PR 帶來了什麼」。`origin/main` 現在是哪個 commit、
有哪些分支，一律問 git 不要問這裡**（理由見下面那個引言框）。

09-01 ~ 09-03 合併的：

| PR | 內容 |
|---|---|
| #26 / #27 | history 每晚補 `pet_mood` / `mood_reason` |
| #28 | 就寢時間同步、開通後端連線、手機使用時間、點歷史換寵物 |
| #29 | TAPO 首事件是暖機假影不是上床時刻；Garmin 補抓到 09-01 |

08-28 ~ 09-01 那幾輪：

| PR | 內容 |
|---|---|
| #17 | 寵物動畫四態化 + 戴錶者分段（`WEARER_SEGMENTS`）+ baseline 日曆天窗格 |
| #18 | `tapo 2.0/.env` 停止追蹤，改附 `.env.example` |
| #20 | 睡眠助理接真實 payload + 修掉時區解析錯 8 小時 |
| #21 / #22 | 文件狀態同步 |
| #23 | 補上 bored/tired/anxious 三個 Lottie（從 happy 衍生） |
| #24 | TAPO 原始度量記錄器：門檻從錄製階段移到事後 |
| #25 | 用整夜資料把 TAPO 偵測門檻校準到文獻常模 |

更早的 PR #11（多使用者後端）、#12~15（文件與英文化）、#16（Jeremy 的
Insights 頁）也都在裡面。

**開著哪些 PR，問 `gh pr list`，不要問這裡。**

遠端還有幾條非 main 分支，**以 `git ls-remote --heads origin` 為準**。其中 `feature/opencv-motion-garmin` 是影像組的，整條不能合，見下。
**別人的分支不代刪。**

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

### ⚠️ 環境

**Python**：`.venv` 在專案根目錄。2026-09-03 實測，`requirements.txt` 的東西
**全部裝好了**（`fastapi` / `uvicorn` / `httpx` / `garminconnect` /
`mysql-connector-python` / `pandas` / `numpy` / `matplotlib` / `seaborn` /
`opencv-python`）。要確認就直接跑：

```bash
.venv/Scripts/python.exe -m pip list
```

⚠️ **`garminconnect` 只有 `--fetch`（重抓資料）那一步需要**，pipeline 的後四步
讀既有的 `garmin_standard_data.json`，不受影響。

⚠️ **worktree 不需要自己的 venv**，直接用主目錄那個絕對路徑：
`C:\Users\user\Projects\Sonnap-Project\.venv\Scripts\python.exe`。
腳本用 `Path(__file__).parent` 定位，資料路徑會正確落在 worktree 內。
但 **`data/sonnap.db` 不會跟過去**（未追蹤），要先
`python db.py --init && python db.py --seed && python migrate_garmin_to_db.py`。

**Flutter/Android**：Flutter 3.44.9（`C:\Users\user\flutter`）+ Android SDK
+ Temurin JDK 17，08-27 從零裝起。踩過的坑（`compileSdk` 版本不對、機器上一度有
兩份 Flutter SDK 互相污染、`local.properties` 反斜線跳脫、VS Code Gradle 外掛搶鎖）
記在 `DEVLOG.md` 2026-08-27 那則。`flutter build apk` 與 `adb install` 都能跑。

⚠️ **`flutter build` 會動到 `app/linux`、`app/macos`、`app/windows` 的
generated plugin 檔**。那是雜訊（這個專案不出那三個平台），commit 前
`git checkout -- app/linux app/macos app/windows` 丟掉。
⚠️ **`adb` 在 Git Bash 底下要 `MSYS_NO_PATHCONV=1`**，否則 `/sdcard/x.png`
會被改寫成 `C:/Program Files/Git/sdcard/x.png`。

### ⚠️ 重抓資料是**合併**：只換這次抓的日子（2026-10-03 改）

`garmin_connect_fetch.py` 預設把新抓的併進既有的 `garmin_standard_data.json`：
**只換這次抓的那幾天，其餘原樣保留**。`--days 1` 不會再讓歷史變少。
規則寫在 `garmin/merge_standard_data.py` 檔頭（純函式），三條：

| 規則 | 不遵守的後果 |
|---|---|
| **切點不落在一段睡眠中間**，落進去就往視窗內縮，那一晚整晚留舊的 | 那一晚前半舊後半新；Garmin 修正過入睡時刻的話，同一晚會有兩筆 `sleep_start_time`。這份資料作息很晚（入睡 22:00~08:00、起床最晚 16:00），午夜或中午切都會切到人 |
| **視窗內新的贏** | 最近幾天會晚到補齊（09-29：55 → 1578 筆），留舊的就永遠拿不到完整版 |
| **某天某個來源（睡眠／心率／壓力／步數）這次一筆都沒抓到 → 留舊的**，並印出來 | API 那一次沒回東西，會把有值的日子洗成空的 |

⚠️ **不要加 `--replace`**——那是舊的整份覆寫行為，沒抓到的日子全部消失。
⚠️ 舊檔讀不出來時 fetch 會**直接停下**，不會退回覆寫。

→ **每天早上用 `morning_import.py`**：它只抓「最近 7 天，或從上次抓到的那天起」
  （取較早者——停跑很久之後只抓 7 天會留下永遠補不上的空洞），抓之前備份、
  抓完比對「原本的夜晚都還在」，沒過就還原並停下。

要手動抓：

```bash
python garmin/garmin_connect_fetch.py --days 7
python garmin/run_pipeline.py          # 再跑後四步
```

🔴 **為什麼不能每次重抓全部：Garmin 會把約 4 個月前的日子的細節收掉。**
2026-10-02 那次全區間重抓（83 → 87 晚），05-28 ~ 05-31 從 4768 筆掉到 441 筆
（心率、壓力、動作、睡眠分段幾乎全沒了），10 個六月夜晚的分數跟著變
（那 10 晚的 Tier3 基線窗格往前 28 日曆天涵蓋那幾天）。

✅ **那 4 天已於 2026-10-03 從備份救回**，07-15 之前所有夜晚的分數與 10-02
重抓前逐晚相同。最早的完整版本另存在
`C:/Users/user/Projects/sonnap-data/garmin-earliest-full/`（不參與自動清除）。

⚠️ 代價：視窗外的日子**完全凍結**。Garmin 事後修正了舊日子，或解析程式
多抓一種指標，舊日子都拿不到——而此時去重抓，拿到的是被收掉細節的版本。
要做的話得另外寫「只增不減」的模式（刻意沒做，目前沒有需求）。

⚠️ 舊夜晚的分數若又變了，先看**原始彙總**有沒有變、再看分數
（`git show HEAD:garmin/data/garmin_sleep_summary.json` 和現檔逐欄 diff），
倒過來看會誤判成自己的程式壞了。

分支現況不在這裡列（會過期），**以 `git ls-remote --heads origin` 為準**。
`feature/opencv-motion-garmin` 整條不能合；其他人的分支不代刪。

### ⚠️ TAPO 資料：哪些能引用、哪些不能

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
- **116 晚**實測資料（**2026-05-29 ~ 11-06**），每晚 0–100 分 +
  Good/Normal/Poor/Bad，**跨 3 名戴錶者**：

  | 區段 | 晚數 | 可信 |
  |---|---|---|
  | `wearer_a`（2026-05-28 ~ 07-27） | 40 | ✅ |
  | `unverified`（07-28 ~ 08-27） | 11 | ❌ 已知多人戴過 |
  | `wearer_c`（08-28 起，負責人本人） | **65** | ✅ |

  來源：`migrate_garmin_to_db.py` 2026-09-29 執行輸出為 41 / 11 / 32 = 84 晚；
  2026-09-30 的資料一致性修正排除了 2026-06-27（落在 `wearer_a` 區間），
  故為 40 / 11 / 32 = 83。

  ⚠️ **這個數字每次重抓 Garmin 都會變**，寫進報告前跑一次確認：
  `python -c "import json;d=json.load(open('garmin/data/garmin_sleep_quality_final.json',encoding='utf-8'));print(len(d),d[0]['date'],d[-1]['date'])"`

  ✅ **Tier3 對本人的啟動狀況（2026-11-09 重新清點）：51 / 65 晚有修正值，
  09-11 起連續都有**。全體 78 晚（前一位配戴者 27、本人 51）；
  `unverified` 那 11 晚一律停用。先前記的「2 / 16 晚」是 09-12 的狀態，已過期。
  ⚠️ 基線窗格是日曆天（`MAX_BASELINE_DAYS = 28`），配戴一稀疏就會再次停用，
  所以「現在有幾晚有修正值」不是一個會單調成長的數字——**寫進報告前重算**。
  ⚠️ 報告數字以 **[PPT_NUMBERS_2026-10-01.md](docs/PPT_NUMBERS_2026-10-01.md)** 為準，
  **2026-11-09 已依三段式計分重算**（116 晚）。每一節都附重算指令，資料再長就再算一次。誠實寫法見 [REPORT_CAVEATS.md](docs/REPORT_CAVEATS.md)。
- Tier1/2 基礎分數（文獻加權）+ Tier3 個人化修正值（±12，戴錶者分段後）
  + SRI（呈現不計分）
- 完整文獻依據：`Research-Background/Garmin手錶分數.md`
- 後端多使用者 API、Health Connect adapter（PR #11）
- **Tier A 行為迴圈端到端接通**（PR #30）：手機偵測就寢時刻 → 上傳 →
  挑戰進度。暱稱制帳號，一支 APK 給所有人
- Flutter App 已能自己建置 APK 並裝進實體 Android 手機執行

---

## 🚧 設計紅線與待補迴圈（2026-08-17 定．動評分或遊戲化之前必讀）

來源：拿 GitHub 上同類型開源專案 **NightBloom**（`shev0k/sleep_tracker`）逐行對照的結論。
4 stars／34 commits／**最後一次 push 是 2024-11-02**，停更約 21 個月
（2026-08-28 用 GitHub API 複查，仍是最新版本；為什麼要複查見方法論第 2 點）。
⚠️ **授權不明**：README 宣稱 MIT，但 repo 裡沒有 LICENSE 檔（見方法論第 1 點）。
**完整證據與行號在 [PROJECT_STATUS.md](docs/PROJECT_STATUS.md) 第八節**，這裡只留規則。

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

→ ✅ **`Research-Background/攝影機分數.md` 已於 2026-09-06 寫好**，
  而它的結論是**現行有效的攝影機計分項目：0 項**——四個構念逐一判定不可計分，
  各自記錄了缺什麼。動作率（A 節）偵測層已校準（三晚人工標註、F1 0.84–0.88），
  但 Montini 2024 是**描述性常模不是結果關聯研究**，
  且我們的「一次動作」與文獻的不是同一個構念（**12.8 秒** vs 4 秒，31 晚，
  已排除是參數問題），所以照 SRI 的先例：照算、照輸出、不進 `total_modifier`。
  🔴 **而且事件率跨夜不穩，所以不得與常模並列呈現**（2026-11-07，n=31 從 n=4 擴大）：
  同一個人、同一組 ROI、校準門檻 0.75%，31 晚跨了 **11.7 ~ 36.8 次/小時（3.1 倍）**，
  中位是文獻的 **1.72 倍**。先前文件寫的「穩定地是 1.4 倍」是從**最低那一端的四晚**
  取出來的（那四晚在 31 晚裡排第 1~9 名），而「錄影長度是共變項」也被否證
  （r = +0.049）。照明閃爍、攝影機位置也都排除了；目前最強的線索是
  **多出來的事件都是小振幅、剛好擦過門檻的**（峰值中位 r = −0.639），
  但要分辨「畫面吵」還是「真的小動作多」只能人工看影片，**而那幾晚沒留影片**。
  → **報告與台上可以講 F1 0.84–0.88（那是偵測器準不準），不要講事件率接近常模。**
  🔴 **第 3 關（內部效標驗證）2026-11-09 做完了，結果是沒有相關**：重疊夜數
  3 → **31 晚**，攝影機事件率 vs 同一晚 Garmin 的 WASO（Pearson −0.197／Spearman +0.050）、
  `awake_count`（+0.154／+0.200）、`final_score`（−0.181／−0.235）。**WASO 兩種算法
  連正負號都相反**，是雜訊不是弱相關。只數大振幅事件（峰值 ≥10／20／40%）四個切點
  也全部沒有相關，所以**不能用「我們量不準」解釋**。判定規則是 09-10 事先寫好的：
  無相關 → 只能當呈現用。⚠️ 保留一點：Garmin WASO 自己的裝置誤差就很大，
  要翻案得換更好的效標（PSG），不是重新解讀同一批數字。
  → **所以想讓攝影機計分，不要再投資動作率**。四個構念裡只有 **C 節（上床時刻／
  入睡潛伏期）的文獻給了切點**（Ohayon 2017：0–30 好／31–45 無共識／≥46 差），
  其餘三個只有常模——而紅線 2 要的是切點。C 節卡的是「上床時刻必須量測得到」→ 人形偵測。
  ✅ **2026-11-09 起畫面顯示的是「跟你平常比」而不是原始數字**（`camera_usual.py`）：
  「About the same as usual」／「27% less movement than usual」／基線不足時
  「Needs N more recorded nights…」。**不計分、不主張動得多是好是壞**，所以不欠文獻債
  （需要常模的是判好壞，個人內比較不需要——同 SRI 當挑戰目標、壓力修正改用個人波動）。
  ⚠️ **一旦讓它加分或扣分就破功**：分數天生有方向，而那個方向正是第 3 關測出沒有相關的。
  ⚠️ 兩個常數是設計決策不是文獻：基線 **5 晚**（32 晚實測覆蓋 27/32＝84%；手錶那邊的
  14 晚只剩 12%）、「差不多」門檻 **±25%**（跨夜不穩 3.1 倍，小幅偏離多半是雜訊）。
  🔴 **基線只取 `motion_threshold_basis` 與 `roi` 都相同的夜晚**——09-01／09-03 錄於
  ROI 之前是 `frame`（分母＝整個畫面），混進來就是同一個 0.75% 差一個數量級而數字看起來正常。
  ⚠️ 那幾句話**只在 `camera_usual.py` 定義**，API 與 Dart 都照抄；Dart 也不重算百分比。
  ⚠️ `/insights` 會**多抓一段只當基線、不顯示**——`db.get_camera_nightly` 的 `days`
  其實是「最近 N 列」不是「N 天」，不多抓的話視窗裡最舊的幾晚會誤報「還需要幾晚」。
  要真的計分，關卡清單在該文件 F 節。TAPO 那四代公式
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

### ✅ 行為介入迴圈：已經接通（2026-09-03）

當初的診斷是「它是**假量測 + 真迴圈**，我們是**真量測 + 無迴圈**」——
使用者看完分數與夢境日記就結束了，沒有可以「做」的事。

那一層現在通了：手機量到 `lights_out_at` → `POST /nightly` →
`behavior/adherence.py` 算達成度 → 挑戰進度。實測數字見交接區。

當初定下、現在仍然有效的三條：

- **挑戰標的必須是行為**（幾點放下手機），不能是**生理結果**（深睡幾分鐘）。
  使用者控制得了前者，控制不了後者。三個挑戰目前沒有一個讀 `wearable_nightly`
- ⚠️ **拿作息收斂當挑戰目標不違反「SRI 不計分」的決定**——當初不計分的理由是
  「不同計算方法算出的 SRI 差異大到不能對照外部常模」（Czeisler 2026），
  而「這 7 天你的上床時間有沒有收斂」是**個人內比較**，不受該問題影響。
  但**它仍然不准進 `total_modifier`**，兩件事不要混淆
- ⚠️ 實際用的不是 SRI 而是 `bedtime_spread_minutes`（`lights_out_at` 的收斂），
  理由寫在 `behavior/challenges.py`：**SRI 需要手錶的睡眠時間軸，而 D2 的
  受測者沒有錶**

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
| `avg_stress_score` | 不是單純睡眠期間的壓力，也不是單純白天的 | **兩段混在一起**：落在睡眠區間內的讀數歸起床日、其餘照日曆日歸。24994 筆讀數裡 **46.6% 落在睡眠期間**（先前寫的「8.6%」是時刻早 8 小時那時算的，已作廢）。**已不計分**，保留只因 `itegration/if_integrate.py` 的相關性分析還在讀 |
| `presleep_stress_score` | — | 「上一次起床 → 這一次入睡」整段清醒時段。Tier3 壓力修正值用這個 |
| `avg_heart_rate` | 不是單純「睡眠期間」的平均心率 | 與上面同一種混法：睡眠區間內的讀數 + 起床日那個日曆日其餘時段的讀數。文件多處稱它「睡眠期間平均心率」，那是不精確的（2026-10-04 發現，**未處理**）。Tier3 的 ±2 用這個 |
| `sleep_efficiency` | 不是臨床睡眠效率 | 分母是（起床 − 入睡），**不含入睡潛伏期**。報告中須誠實標註。⚠️ 而且**現在有三個東西叫這個名字**，見下 |

### ⚠️ **五個**「睡眠效率」，讀的時候一定要看 `*_basis`

| 欄位 | 分子 | 分母 | 有文獻 | 進 `final_score` |
|---|---|---|---|---|
| `wearable_nightly.efficiency` | 手錶量的總睡眠 | 起床 − **入睡** | 🔴 **門檻套錯量**，見下 | ⚠️ 只在沒按按鈕的夜晚（三段式的 ③） |
| `wearable_nightly.clinical_efficiency` | 手錶量的總睡眠 | 起床 − **上床**（只有 Health Connect 給得出） | ✅ | ❌ 只供呈現 |
| **`nightly_behavior.sleep_efficiency`**（2026-09-06 新增） | **假定**睡眠（放下手機就算睡著、且整夜沒醒） | 結束 − 開始（**自述**） | ❌ | ❌ **絕不** |
| **`measured_efficiency`**（2026-09-30 新增，**不存資料庫**） | **手錶量的總睡眠** | 結束 − 開始（**自述**，= TATS） | ✅ Ohayon 2017 / ANSI-2110 正是為這種分母訂的 | ✅ 算得出來就用它（三段式的 ①） |
| **`watch_wake_efficiency`**（2026-10-02 新增，**不存資料庫**） | **手錶量的總睡眠** | 按 Start sleep（自述）− **手錶認定起床**（量測） | ⚠️ 不是 TATS（終點早於真正離開床），**沒有對應的常模** | ✅ ① 算不出來時（三段式的 ②） |

⚠️ **第五個不是「比較好的第四個」，是另一個量。** 它存在的理由只有一個：
第四個**兩端都是自述的**，忘了按 Out of bed 整晚就沒有數字。實測 22 晚裡
2 晚只按了 Start sleep（09-14、09-30），加上 09-20 那種「按完又睡著」，
換成手錶的起床時刻就有數字了——**3 晚 → 6 晚**。
⚠️ 代價：手錶認定的起床通常早於真正離開床，分母偏小、數字偏高
（實測三晚兩者都算得出來：92.1→93.5、91.7→91.5、74.6→78.9）。
⚠️ **兩個一起顯示、各自標 basis**，少顯示一個就會被拿去跟另一個定義比。
⚠️ 兩張表的時間慣例不一樣（`wake_time` 帶 `+08:00`、`bed_start_at` 不帶），
所以 `_wall()` 一律當**牆鐘**讀。**不可以換算 UTC**，那會差 8 小時
（Flutter 端 `parseWallClock` 當初修的就是這個）。

### ⚠️ 睡眠效率：2026-11-07 起三段式計分（使用者決定，恢復條件**未**達成）

每晚依序取（`behavior/sleep_efficiency.scoring_efficiency()`）：
① 兩個按鈕都按、算得出來 → `measured_efficiency`（TATS，門檻適用）
② ① 算不出來、有按 Start sleep → `watch_wake_efficiency`（**無常模**，門檻是借用的）
③ 都沒按 → 手錶自己的效率（**構念錯配**，就是 10-01 停止計分的原因）

| 實測 116 晚（與 10-01 停止計分版比） | |
|---|---|
| 最終分數平均 | 73.5 → **79.7** |
| 標準差 | 19.5 → **15.1**（鑑別力降 23%） |
| 品質等級改變 | **44 晚**（只看基礎分數 43 晚） |
| Good/Normal/Poor/Bad | 51/29/23/13 → **63/38/11/4** |
| ① 6 晚 / ② 8 晚 / ③ 102 晚 | 平均變化 −1.7 / +3.7 / **+6.8**；③ 有 **100/102 晚**拿滿 25 分 |

🔴 **已知且接受的代價**（使用者 11-06、11-07 兩次看過數字後決定）：
**沒按按鈕的夜晚平均比兩個都按的高 8.5 分**——誘因是「別按」，而按鈕是攝影機上床偵測
唯一的 ground truth。③ 的錯配沒有被推翻：手錶效率的分母（起床 − 入睡）不含入睡潛伏期，
Ohayon 2017 的 ≥85% 卻是為**臥床時間**訂的。最直接的證據：有按按鈕的 6 晚，① 跨 74.6~98.9%
（24 個百分點），手錶自己的效率幾乎都在 96~100%。完整記錄：`Research-Background/Garmin手錶分數.md` **B-7**。

**資料怎麼流**：`export_bed_marks.py` 從資料庫匯出按鈕 → `garmin/data/bed_marks.json`
→ pipeline 讀檔（pipeline 依舊不碰資料庫）。`morning_import.py` 在評分前自動匯出，**匯出失敗就停**
（不停的話每晚都退回 ③，分數悄悄變高）。⚠️ **手動跑 `run_pipeline.py` 前先跑 `export_bed_marks.py`**，
否則用的是上一次匯出的按鈕。
**每晚用哪一種**存在 `wearable_nightly.efficiency_basis`（評分器的判定，同 `rem_measured`），
一路帶到 API 與 App 分數卡，`score_claim.EFFICIENCY_CAVEATS` 依它掛**那一種**的警語。
要關掉：`EFFICIENCY_SCORING_ENABLED = False`。

⚠️ 回到「只靠量測」的路線：上床時刻要由**人形偵測**量到（背景相減做不到——實測 09-30
那夜床鋪 ROI 前景像素 **84% 的幀為 0**，躺著不動的人與空床在 MOG2 底下完全相同；
它偵測得到**入睡**但入睡不是上床）。規格與驗收條件在 [TAPO_HANDOFF.md](docs/TAPO_HANDOFF.md)。

⚠️ **這個分數宣稱自己是「以睡眠時長為主」,不是多維度等權合成**（2026-10-01
使用者決定）。四個計分項裡只有 duration 的裝置誤差明確小於它的判讀級距:

| 分項 | 級距寬度 | 已知裝置偏差 | 偏差÷級距 |
|---|---|---|---|
| duration | **120 分** | −16.9 分 | **14%** ✅ |
| waso | **15 分** | +13.3~24.1 分 | **89–161%** 🔴 |
| deep | 42 分 | 高估,量級不明 | ⚠️ 算不出來 |
| rem | 21 分 | 低估,量級不明 | ⚠️ 算不出來 |

**關鍵是級距寬度差了 8 倍**——同樣約 17 分鐘的誤差對 duration 無關痛癢,
對 WASO 足以翻掉一整級。所以「消費級手錶每一項都一樣不可靠」是錯的。
⚠️ 回到「多維度合成」的宣稱要**兩件事**:①效標驗證(E-6)②把 30/25/10/10
這組權重本身 justify(I 節自承那是設計決策不是文獻推導)。比現狀更嚴格。

⚠️ **API 回傳分數組成**（`scoring.composition` 與 `history[].composition`）:
除了 `scored` / `unscored` / `scored_weight`,還帶 **`primary_component`**（= `duration`）
與 **`caveats`**（有計分但門檻效度存疑的分項)。⚠️ **`caveats` 與 `unscored` 是不同的
兩件事**:`unscored` 是「沒測到」,`caveats` 是「測到了也算了,但門檻能不能套上證據不足」。
`duration` 刻意沒有 caveat——每項都掛警語的話警語就沒有意義。
`waso` 也刻意沒有（2026-10-22 使用者決定，限制改寫在報告裡）。現在有警語的是 `deep`／`rem`，
以及 `efficiency`——**依那晚的 basis 掛三種不同的警語**，composition 另帶 `efficiency_basis`。
裝置組合因人而異，兩個都是 82 分的夜晚可能由不同項目組成。
`main.score_composition()` 是**刻意寫的第二份判準**（評分在 pipeline 讀 CSV、
API 讀資料庫，拿不到同一份資料），由 `tests/test_score_composition.py` 逐夜比對守著。

⚠️ **警語與那段 note 的文字只有一個定義處：`score_claim.py`。**
兩個消費端（API、打包檔）照抄它。🔴 **2026-11-19 起 App 不顯示分數組成與深睡／REM／效率警語**
（使用者定：Insights 改版拿掉舊分數卡，警語只留在書面報告 `REPORT_CAVEATS.md`）。
API 與打包檔照舊輸出，之後要放回 App 時照抄它們，不在 Dart 產生：

| 哪一端 | 怎麼拿到 | 判準寫在哪 |
|---|---|---|
| `main.py`（API） | `score_claim.compose(...)` | 從資料庫原始度量**推論**哪幾項有算 |
| `build_app_payload.py`（打包檔） | 同上 | 直接讀 pipeline 的 `{項目}_score` 是否為 None |

⚠️ `build_app_payload.py` **不能 import `main.py`**（反向已經 import 了
`map_pet_mood`，會循環），這就是文字單獨抽成 `score_claim.py` 的原因。
⚠️ 打包檔的分項得分只在 `garmin_sleep_quality.json` 裡（`*_final.json` 沒有），
所以打包腳本要**多讀那一份檔**。
⚠️ Dart 端刻意**沒有**配分表：`scored_weight` 照抄後端。在 Dart 把
30+25 加起來就是第二份配分表，而兩份漂移時不會有任何錯誤訊息。
⚠️ 判斷一律用 `is not None` **不可用真假值**——WASO 0 分鐘拿滿分 25、深睡 0 分鐘拿 0 分，
兩者都是「有測到」。實測真實資料有 **16 晚 WASO 是 0**，用真假值會誤報那 16 晚。

✅ **第四個讓 ≥85% 第一次用在適用的量上**：手機「開始睡覺／結束睡覺」按鈕記錄的正是
**TATS**。11-07 起它就是三段式的 ①。App 上它與第五個的說明都會講「分數什麼時候用它」
（`tests/test_sleep_efficiency.py`【6b】、`measured_efficiency_test.dart`【3】守著）。

⚠️ **第四個刻意不存資料庫**：它要 join `nightly_behavior`（按鈕）與
`wearable_nightly`（手錶睡眠），而兩張表的寫入時機不固定——手機早上自己上傳，
手錶要有人跑 `morning_import.py`。寫入時算的話，手錶晚到的夜晚會**永遠是 null
且不會回頭補**。改成**讀取時在 `main.py` 現算**（`/home` 與 `/insights` 共用
同一支純函式），手錶哪天進來哪天就對。

第三個在代數上等於「臥床時間裡沒在滑手機的比例」——**睡眠本身不影響它**，
所以會出現方向相反的誤判（半夜醒著兩小時但沒碰手機 → 99%「良好」；
睡得好但睡前滑兩小時 → 75%「不良」）。使用者 2026-09-06 知悉後仍決定
沿用這個名稱，完整說明與那張反向判讀表在 `behavior/sleep_efficiency.py` 檔頭。

→ **API 回應裡三個可能同時出現**，所以每一列都帶 `efficiency_basis`
  （`phone_lights_out__waso_assumed_zero`）。只讀數字不讀 basis 就會混淆。
→ 行為迴圈（挑戰、寵物）應該讀 `phone_in_bed_minutes` 而不是效率：
  使用者控制得了「躺下後少滑 20 分鐘」，控制不了「今晚別醒來」。

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

### ⚠️ 每日心率與壓力的時刻：2026-10-04 之前早了 8 小時

`garmin_connect_fetch._iso_from_epoch_ms` 回傳的是 **UTC 鐘面貼上 `+08:00`**。
睡眠那幾段另外過了 `gmt_to_local_iso` 所以一直是對的；每日心率與壓力沒有，
整批早 8 小時。分數、評分、匯入全部照常成功——錯的只是 Tier3 讀到哪一段時間。

證據：心率有兩個來源（睡眠 API、每日 API），同一個真實時刻該是同一個值。
睡眠時段同一時刻有兩個值的 8312 個時刻，往前 8 小時找得到相同值的佔 **99.7%**
（對照組 6／7／9 小時是 6.5~7.6%）。壓力只有一個來源，旁證是修正後落在睡眠
時段的比例由 15.2% 變 46.6%（Garmin 的壓力讀數要靜止才有）。

| 修了什麼 | 在哪 |
|---|---|
| 兩支解析函式在**出口**整批換算 | `_gmt_labelled_to_local()`。不逐個分支改——那兩支各有四、五個分支，漏一個不會報錯 |
| 同一時刻的心率只留一份 | `_drop_sleep_hr_covered_by_daily()`。時刻對了之後兩個來源會重疊，都留的話睡眠時段權重變兩倍 |
| 既有檔案一次性轉換 | `garmin/migrate_daily_series_tz.py`。**不能靠重抓**（舊日子的細節已被上游收掉） |

⚠️ **不要把 `_iso_from_epoch_ms` 本身「改對」。** 睡眠那幾段把它的輸出再餵給
`gmt_to_local_iso`，那邊會多加一次 8 小時，入睡與起床時刻全部晚 8 小時。

⚠️ 轉過的檔案標頭有 `"daily_series_tz": "local"`。轉換腳本看到就不再轉
（再轉一次會變成晚 8 小時）；fetch 看到**沒有**就拒絕合併
（不然會是一份前半錯位、後半正確的檔案）。從很舊的備份還原之後要先跑一次轉換。

實測影響（修正當下的 87 晚）：**40 晚分數變了**（−6.7 ~ +4.1，18 晚差 2 分以上）、
**3 晚換等級**（06-24 Poor→Normal、09-18 與 09-26 Good→Normal）、
**基礎分數 0 晚變動**——只有 Tier3 的心率修正（42 晚）與壓力修正（28 晚）受影響。
`presleep_stress_score` 的中位數 19.6 → 30.5。

### ⚠️ 壓力修正值：依「偏離幾倍個人波動」換算（2026-10-22 改）

時刻修正後真正量到入睡前的清醒時段，起伏比原本大得多，舊的「每單位 0.4 分、
偏離 10 分扣滿」（沒有出處）讓 32 晚裡 15 晚打到 ±4。現在：

| | 取值 | 依據 |
|---|---|---|
| 單位 | 個人波動 = baseline 窗格內 MAD × 1.4826 | ✅ Buchheit 2014：以個人變異為 SWC 參考 |
| 開始扣分 | > 0.5 倍（以內 0 分） | ⚠️ Le Meur 2013 用過，原作者自承倍數無實證 |
| 扣滿 ±4 | ≥ 2.0 倍 | ❌ **設計決策**，報告須如實標註 |
| 波動下限 | 1 分（讀數為整數） | 量測解析度 |

116 晚（2026-11-09 重算）：有壓力修正的夜晚裡打滿 **24 / 54 → 8 / 36 晚**、修正值變動 46 晚（最終分數 −3.1 ~ +3.3）、現行計分下 3 晚換等級、基礎分數 0 晚變動。（89 晚那時是 15 → 3 晚。）
完整論證在 `Garmin手錶分數.md` G 節「換算改版」。`test_scoring_guards.py`【6】守著
（含「主迴圈沒有改回舊換算」）。
⚠️ 波動與 baseline 必須用**同一個窗格**（`baseline_window()`），分開算比值就沒有意義。
⚠️ 這是把「兩半都沒出處」換成「單位有出處、倍數標為設計決策」，**不是**「已有文獻門檻」。

**`anxious` 要兩個訊號同向**（`map_pet_mood()`）：一個過 −3，另一個也確實比平常差——
心率 ≤ `ANXIOUS_HR_CONFIRM`（−0.4 = 1 bpm，讀數解析度）、壓力 < 0（新換算在 0.5 倍以內給 0，
負值本身就代表超過最小有意義變化）。原本是「任一個過門檻」，與它自己的常數註解
「**同時**高於常態」不一致，讓 10-02（Good 83.8 分）這種壓力扣滿、心率卻比平常好的夜晚
顯示焦慮寵物。Rosenbach 2025 也支持要心率佐證（Garmin 壓力分數對自評壓力預測力很弱）。
⚠️ 兩項一起改完，89 晚只剩 **1 晚 anxious**（07-07）；116 晚是 **4 晚**（07-07、10-28、11-01、11-05，Good 2／Normal 2）——**使用者決定接受焦慮很少見**，
不另訂門檻。`test_history_mood.py`【4】守規則本身；Flutter 的 `history_pet_test.dart`
改成守「同一品質等級裡有 anxious 也有別的心情」，一晚就成立。
⚠️ 心率那邊**不要改成 < 0**：09-16 心率只差 0.09（約 0.2 bpm），低於解析度。

✅ 戴錶者分界重驗過：靜止心率來自睡眠 API、完全沒變；平均心率在 07 月底／08 月初
的跳躍仍是全資料最大的（修正後更大），`wearer_a` 內部沒有可比的跳躍。
`WEARER_SEGMENTS` 不動。⚠️ 當初找分界的腳本不在 repo 裡，這次是重寫統計量驗的，
所以上面「跳 4.13」那個數字本身沒有重現，驗的是結論。

### ⚠️ 睡眠階段時間軸（2026-11-12，`garmin/sleep_stages.py`）

首頁 Sleep Stages 圖用，**只呈現、不計分**。從 `garmin_standard_data.json` 的 `sleep_stage` 紀錄還原逐段時間軸。

- **入睡時刻那四筆是整晚摘要，不是時間段**（每階段一筆＋`*_duration_sec`），要按次數扣掉。
- **第一段常比 Garmin 的入睡時刻早一兩分鐘開始**（11-02：03:52 vs 03:53）。嚴格只收入睡之後的段會丟掉整段——
  修之前 118 晚只有 19 晚對得上手錶總數，修之後 116 晚（差 2 分鐘內）。容許 15 分鐘、起點夾到入睡時刻。
- 另 2 晚（09-12、09-24）差 13、22 分鐘，原因未查。**所以圖例分鐘數用手錶自己的總數，還原的段只畫曲線。**
- `history[]` 每晚另帶 `sleep_efficiency`、`deep_minutes`（首頁「跟上一晚比」用），與 metrics 同一個來源。

### 兩個 pipeline 層級的坑

**① 重抓資料是合併，不要加 `--replace`。**
`garmin_connect_fetch.py` 只換這次抓的那幾天；加了 `--replace` 才會整份覆寫，
**弄丟沒抓到的日子且沒有任何警告**。規則與理由見交接區「重抓資料是合併」那一節。

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
| `sleep_quality_score` | `tapo/tapo_detector.py:486`（V1，另有 V2/V2.5/V3 三代） | ⚠️ 扣分制，影像組的。**量的是 timeline 長度不是睡眠**——同一晚跨來源差 80 分。再往下一層：timeline 長度取決於**當晚的偵測門檻**，而門檻逐晚變過至少四組且沒記在任何欄位裡 → **跨夜比較在原理上不成立，不是調係數能修的**。見 [TAPO_HANDOFF.md](docs/TAPO_HANDOFF.md) |
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
寵物 notes、睡眠助理、console 輸出。**程式碼註解與 docstring 維持中文**：那是給團隊讀的
說明不是輸出，翻掉會讓專案最有價值的決策記錄變難讀。

⚠️ **換語言時最危險的不是翻譯，是驗證層會安靜地失效。**
`ai/text_guards.py` 有兩個機制與語言綁死，換掉任何一個而不改對應物，
**不會報錯，只會不再擋任何東西**：

| 機制 | 中文版 | 英文版 | 不改的後果 |
|---|---|---|---|
| 語言洩漏 | `SIMPLIFIED_CHARS` | `CJK_LEAK_PATTERN` | 模型漂回中文不會被擋 |
| 拼字數值 | `CHINESE_NUMERAL_PATTERN` | `SPELLED_NUMERAL_PATTERN` | "ten point three hours" 混進 App |

### AI 輸出的共用規則（`ai/`）

夢境日記 2026-11-17 退場；現在用 AI 的是睡眠助理（`ai/chat.py`）與寵物 notes（`ai/night_summary.py`）。
從夢境那一代留下來、仍然有效的決策：

| 決策 | 理由 |
|---|---|
| 用 Claude API + 標準庫 `urllib.request`，**不裝 SDK** | 這功能不讓 `requirements.txt` 多任何一行 |
| 驗證規則只有一份：`ai/text_guards.py` | 兩份禁詞清單漂移時，一邊擋得住的詞另一邊擋不住，不會有任何錯誤訊息 |
| 拼字數值規則**必須有 `point` 才擋** | 英文的數字詞是常用字，"give it one more try"／"half an hour earlier" 都必須放行 |
| `BANNED_WORDS` 用**完整單詞**比對（`\b...\b`） | `treat` 會命中 `retreat`、`ill` 命中 `still` |
| `ADVICE_LANG` **沒有實作** | 輸出固定英文（prompt 本身就是英文寫的） |

> ⚠️ **驗證規則寫寬很省事，但誤判的代價是使用者拿不到內容。**
> 夢境那一代踩過三次（「沒看清」無條件擋、`SIMPLIFIED_CHARS` 的于／后／里、
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

## 現有程式碼結構（端點、資料表、測試數 2026-09-13 核對過）

**後端（根目錄）**

- `main.py` — FastAPI。23 個端點：
  使用者 `POST /users`、`GET`+`PATCH`+`DELETE /users/{id}`；
  上傳 `POST /nightly /wearable`；
  讀取 `GET /home /insights /challenges /get-sleep-data /health`（`database_available` 照實際用的那種資料庫去問：MariaDB 真的連一次，2026-11-20 前一律看 SQLite 檔、跑 MariaDB 時永遠是 false）；
  攝影機片段 `GET /camera/clips/{clip_id}.gif`（**不收 user_id**，見 `camera_clips.py`）；
  遊戲化 `GET /game /closet`、`POST /game/claim /closet/equip`；
  好友 `GET`+`POST /friends`、`GET`+`DELETE /friends/{handle}`；
  助理 `POST /chat`；
  早晨報告 `POST /rested`（起床自評）、`GET /night-summary`（寵物 notes：AI 總結＋從清單挑的建議；`generate=false` 只讀不生成，首頁用）。
  🔴 **端點一律寫 `def`，不寫 `async def`**（2026-11-21）：裡面是同步的資料庫查詢，寫成 async 會佔住整個事件迴圈。
  實測 `/friends/feed`（替自己與每個朋友每晚各組一次 /home，約 3–4 秒）一跑，同時進來的 `/home`、`/game` 連 `/health`
  都排在它後面 4 秒，App 3 秒就放棄——**這就是 App 剛打開時 /game、/home 偶爾逾時的原因**。改成 `def` 後 FastAPI 丟執行緒池，
  `/health` 0.18 秒。**只有真的在 await 的才准 async**（現在只有 `POST /sleep-status`）；`tests/test_no_blocking.py` 開真的 uvicorn 守著
  （⚠️ TestClient 每個執行緒各開事件迴圈，在它裡面「卡住別人」不會發生，寫在 TestClient 裡的這種測試永遠綠）。
  因此跑在多執行緒裡：`main.py` 的記憶體快取（25 MB 原始檔、心率索引）**一次整份換掉**、重新載入加鎖，不分兩步改。
  ⚠️ `/get-sleep-data` **已接真實資料**（讀打包的 asset 檔），檔案不存在時回 **503
  而不 fallback 回假資料**——這是刻意的，見該函式的 docstring。
- `db.py` — 17 張表，暱稱制免註冊。預設 SQLite（標準庫 `sqlite3`，測試一律用它）；
  設了 `SONNAP_DB_URL` 就走 MariaDB（`db_backend.py`，DDL 從 SQLite 的 `SCHEMA`
  自動產生——**`SCHEMA` 是唯一定義處**，`tests/test_db_backends.py` 守著）。
  ⚠️ 有 `COLUMN_MIGRATIONS` 欄位遷移機制：`CREATE TABLE IF NOT EXISTS` 對**已存在**
  的表什麼都不做、連新加的欄位也不補，只改 SCHEMA 會讓已跑過 `--init` 的開發機
  `no such column`。加欄位時兩邊都要改。
- `build_app_payload.py` — `garmin/data/*.json` → `app/assets/data/app_payload.json`
- `migrate_garmin_to_db.py` — Garmin 的每一晚 → `wearable_nightly`，可重複執行。
  ⚠️ **2026-09-13 起依戴錶者分帳號**：`wearer_a` → 另開的 `WEARER_A_USER_ID`；
  `unverified` → 研究者帳號（「無法歸屬」的桶子，不當成任何一個人）；
  `wearer_c`（本人）→ **手機一直在上傳的那個帳號**，執行時用 `db.resolve_phone_account()` 找，
  跟攝影機匯入共用同一個判準——兩邊各寫一份的話同一晚的攝影機與手錶資料會分在兩個帳號。
  搬家後會清掉舊帳號裡的副本；手機 Health Connect 已經送過的同一晚會被 Garmin **蓋掉**
  （見「同一晚兩個來源」）。
  ⚠️ 在此之前所有夜晚都在研究者帳號，所以手機 App 依帳號撈手錶資料的功能一晚都拿不到。
  ⚠️ **評分檔已經沒有的手錶夜晚會被清掉**（2026-10-04）。某一晚被有效性檢查排除之後
  （06-27 是實例），資料庫那一列不會自己消失，API 會繼續對外回它，而早晨匯入會卡在
  「90 對 89」。現在寫入後會先把那些列備份到 `sonnap-data/deleted-rows/` 再刪，並印出日期。
  **一次超過 `MAX_PRUNE_NIGHTS`（3）晚就停、一列都不刪**——那多半是評分檔少了歷史，
  不是夜晚被排除。只刪 `garmin` 來源的；`--verify` 只核對不刪。
  ⚠️ 備份檔含帳號 id，所以放在專案外面，不要搬進 repo。
- **`morning_import.py`（2026-09-15 新增）— 每天早上一條指令。**
  資料庫連線 → 昨晚的錄影檢查 → 抓 Garmin（最近 7 天，併進既有的）＋匯出睡眠按鈕＋評分＋晚數檢查 → 全部過了才寫入
  （手錶、攝影機、App 資料檔；夢境 2026-11-17 退場，`--no-ai` 留著但沒有作用）。**任何一項沒過就停，資料庫一筆都不寫**；
  手錶那段停下來時會先把檔案還原。
  攝影機排在抓手錶**之前**檢查（本機檔案、幾秒查完），**三條擋法**，
  校準數字都寫在檔案裡：

  | 擋法 | 專擋哪種失效 |
  |---|---|
  | 臥床 < 120 分鐘 | 錄太短 |
  | 臥床 ÷ 錄影時長 < 0.8 | 09-13 那種**尾段**斷線——臥床被算短卻剛好過 120 分鐘 |
  | **最長連續片段 < 120 分鐘**（2026-10-04 新增） | 09-20 那種**中間**斷線 |

  ⚠️ **三條缺一不可，新的那條沒有涵蓋舊的。** 09-20 那晚筆電在電池模式下
  進了待機（4 分鐘就會進）、醒來繼續寫同一個檔案：首尾 625 分鐘、實際只錄到
  17.9 分鐘，而「臥床 ÷ 錄影時長」是**完美的 1.00**——分子分母都是首尾相減，
  中間的洞在兩邊同時出現、互相抵銷。反過來，09-13 那種尾段斷線的最長連續片段
  是 124 分鐘，**過得了**新那條（`tests/test_morning_import.py`【1b】有一條在守）。
  ⚠️ 間隔超過 `MAX_SAMPLE_GAP_SECONDS = 60` 秒算斷一次。這條只看「時間上有沒有列」，
  不管列裡有沒有資料——「有列但全是空值」（串流斷掉但 logger 還活著，約 25 秒
  寫一列標記）由 `MIN_BED_COVERAGE` 守。**所以兩條的分工依賴 logger 的重試間隔。**
  ⚠️ 新那條**刻意排在最後**：一段 60 分鐘、完全沒斷的錄影是「錄太短」不是「斷線」，
  排前面會把人送去查電源。
  ⚠️ 120 分鐘這個門檻**沒有針對新判準校準過**，是沿用既有常數。五晚實測落在
  16.0 / 78.9 / 17.9（該擋）與 293.5 / 611.5（該過），**78.9 到 293.5 之間是空的**，
  所以現在怎麼訂都對；將來出現落在那個區間的夜晚時要重新校準。

  單獨查一份錄影（不碰資料庫、不匯入）：

  ```bash
  python morning_import.py --check-camera tapo_metrics/<那一份>.csv
  ```

  要在主 clone 跑（`.env` 只在那裡），並先設 `SONNAP_DB_URL`。
  ⚠️ **但事後檢查只能告訴你「昨晚沒了」。** 真正的預防是開錄前擋「筆電沒插電」，
  那還沒做（要改 `tapo_metric_logger.py`）。
- **`demo_accounts.py`（2026-11-06 新增）— 成果展用的 4 個示範帳號。**
  `--create`／`--status`／`--remove`，加成手機帳號的好友，讓好友頁有東西看。
  🔴 **資料是腳本產生的，不是受測者**：暱稱帶 `(demo)`、`study_cohort = db.DEMO_COHORT`，
  畫面出現時要標 Demo accounts，**不得當成 D2 結果或算進使用者數**。
  ⚠️ 任何掃過所有使用者的查詢都要排除 `DEMO_COHORT`——`resolve_phone_account()`
  靠「夜數最多」認帳號，示範帳號比本人多的話，手錶與攝影機匯入會寫進假帳號且不報錯。
  **2026-11-16 起全部資料都產生**（使用者定，動態牆要有東西看）：行為＋按鈕時刻、手錶睡眠、白天資料、分享設定（各選一個場景）。
  ⚠️ 手錶資料的 `source` 一律是 **`demo`**（不是 garmin／health_connect），評分與匯入只認 `garmin`；
  睡眠階段由 `demo_sleep.night_segments()` 排（固定種子、決定性），**分數交給既有評分器**
  （`healthconnect_adapter.to_wearable_row`），不是手寫的數字；`/home` 要畫階梯圖時用存下來的分鐘數再排一次，
  得到同一份（`test_demo_accounts.py`【6】守著）。成果展前一天重跑 `--create`，日期才會是最新的。
  ⚠️ 好友頁的即時狀態（Mia 睡著、Leo 起床了）**以執行當下為準**，Asleep 14 小時、Up 到 18:00 就失效 → **展示前幾分鐘跑 `--live`**（只重設即時狀態，不重建）。Yuki／Ken 刻意沒有紀錄，狀態看時鐘（白天兩個都是 Awake，Past bedtime 只在他們目標後 6 小時內出現）。
- **`export_teammate.py`（2026-11-19 新增）— 給隊友在她自己電腦上跑後端用的資料庫副本。**
  手機帳號＋它的好友整份複製成一個 SQLite 檔（連片段），**每個帳號都換新 id**：
  user_id 是憑證，而且 App 沒有唯讀模式，用你的 id 的話她手機一打開就會把她的資料整列蓋進你的夜晚。
  第一次產生新 id；之後更新資料帶 `--user-id-file <上次的>/NEW_USER_ID.txt` 沿用，
  她手上那支 APK（`SONNAP_USER_ID`＝那個 id、`SONNAP_API_BASE=http://127.0.0.1:8000`，手機用 USB＋`adb reverse`）就不用重建。
  只讀來源、不印 id。⚠️ 產出物有真實睡眠資料、臥室畫面，放 `sonnap-data/` 底下，不進 repo。
  ⚠️ 新增指向帳號的欄位時要加進 `ID_COLUMNS`，不然那一欄會帶著你真正的 id 出去（測試【2】掃整個檔案守著）。
- **`camera_clips.py`（2026-11-07 新增）— 攝影機動作片段。** 一晚挑動作最大的 10 段（11-15 使用者定，原本 3 段；一段約 1.8 MB）、
  每段 10 秒，做成 GIF（**原始畫面**＋暖色外框框住在動的地方＋「02:41 · moved for 6 s」），
  App 的 Insights 攝影機卡跟著趨勢圖點選的那一晚顯示。早上匯入會自動跑；
  補舊的：`python camera_clips.py --all`（先加 `--dry-run` 看會挑哪幾段）。
  🔴 **錄影要加 `--save-video`**（`tapo_metric_logger.py --save-video 600`），
  09-15 之後的夜晚都只有 CSV、沒有畫面可剪。
  ⚠️ 片段是原始畫面，所以：檔案在 `sonnap-data/camera_clips/`（所有 worktree 之外、
  `SONNAP_CLIPS_DIR` 可改）；網址只用隨機 clip_id、**不含 user_id**（uvicorn 會把網址印進 log）；
  `DELETE /users` 先刪檔再刪列（CASCADE 清不到檔案）。
  ⚠️ 「哪裡算在動」**呼叫時才讀** `tapo_sleep_onset.MOTION_THRESHOLD` 與它的 `episodes()`，
  不抄一份。⚠️ **在不在動**看 CSV（校準過），**框畫在哪**看片段裡相隔 0.4 秒兩幀的畫面比對
  （`motion_box()`）——CSV 的外框不能用：床鋪區域那塊會被切成固定方框，整畫面那塊大動作時撐滿整個畫面。
  ⚠️ 標籤不寫「翻身」類分類（沒校準過）。保留最近 14 個**有片段的夜晚**，
  原始影片不自動刪（早上匯入超過 30 GB 會提醒）。
- **`tapo_index.py`（2026-08-30 新增）— 攝影機資料的單一事實來源。**
  同時讀 `tapo/sleep_records.sql` 與 `tapo/sleep_reports/*/*.json`，
  **依 `video_clip` 檔名定日期與時刻**（`report_date` 會錯、`time` 欄位會壞，
  兩者都已有實例）。依 6 小時間隔切夜、去重、每個欄位附 `provenance()` 標籤。
  ⚠️ 呼叫端有兩個（`build_app_payload.py`、`itegration/if_integrate.py`；`ai/night_profile.py` 隨夢境刪掉），**有效性判準只有一份**
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
| `game/` | 遊戲化：XP、等級、衣櫃、成就。**只讀評分層**（紅線 4） |
| `social/` | 好友：邀請碼、行為指標白名單 |
| `wearable/` | `healthconnect_adapter.py`：Health Connect → **既有評分器**（一個門檻都沒改） |
| `ai/` | 寵物 notes（`night_summary.py`）與睡眠助理（`chat.py`），都走 Claude API；共用驗證在 `text_guards.py`。`data/ai_advice.json` 是退場夢境的歷史資料。⚠️ `ai/.env` 有金鑰，已被 gitignore |
| `tapo/` | 影像組負責。⚠️ 檔名是 `tapo_detector.py`（不是 `motion_detector.py`） |
| `itegration/` | `if_integrate.py`（Garmin×TAPO 整合）。⚠️ `itegration` 是拼字錯誤，刻意不改名。2026-08-30 從 MySQL 改讀 `tapo_index`，**第一次真的跑得起來**（先前那個 `sonnap` 資料庫不在這台機器上）。需要 `pip install -r requirements.txt` |
| `tests/` | 43 支，**獨立腳本不需 pytest**（清單見下方驗收指令） |
| `app/` | Flutter（Jeremy 負責）。⚠️ **動之前先問他** |
| `Research-Background/` | 文獻依據，正式來源是 `Garmin手錶分數.md` |
| `docs` | 43 bytes 的佔位**檔案**（不是資料夾），待團隊決定 |

**環境**：見上方交接區的「⚠️ 環境」（`requirements.txt` 全部裝好了）。

**驗收指令**

Python 38 支，都是獨立腳本、不需要 pytest。全部跑一次：

```bash
for f in tests/*.py; do PYTHONIOENCODING=utf-8 python "$f" > /dev/null 2>&1 || echo "FAIL $f"; done
```

```bash
python tests/test_api.py                 # 端點與行為層（用暫存 DB，不碰 data/sonnap.db）
python tests/test_healthconnect_adapter.py
python tests/test_scoring_guards.py      # 2026-08-28 新增
python tests/test_tapo_index.py          # 2026-08-30 新增
python tests/test_history_mood.py        # 2026-09-01 新增
python tests/test_tapo_roi_csv.py        # 2026-09-06 新增
python tests/test_sleep_efficiency.py    # 2026-09-06 新增；【6b】守 measured_efficiency 那幾句話是給人讀的（會原封不動顯示在手機上）；【7】三段式的選擇規則（①② 與 App 顯示的是同一份計算）
python tests/test_sleep_onset.py         # 2026-09-06 新增（沒有錄影檔會自動跳過）
python tests/test_waso_annotate.py
python tests/test_db_backends.py         # SQLite SCHEMA → MariaDB DDL
python tests/test_db_show.py
python tests/test_camera_nightly.py      # PR #50
python tests/test_game_rewards.py        # PR #51。含紅線 4、5
python tests/test_friends.py             # PR #51。含「user_id 不出後端」「只回白名單欄位」
python tests/test_live_status.py         # 2026-11-19 新增：四種狀態與三個時間邊界、分享預設關、只寫準時與否拿掉時刻、Cancel 刪整列、不碰 nightly_behavior、刪帳號一起刪
python tests/test_friend_sharing.py      # 2026-11-15 新增：預設那 10 項以外沒打開的一個字都不出後端（哨兵值）、永遠不給的三項 422、只寫準時與否、沒公開連續天數不上榜、Streak 週列、刪帳號連設定一起刪、場景跟著動態卡帶出去且不認得的 422
python tests/test_chat.py                # PR #51。⚠️ 三道保險確保不打真的 Claude API
python tests/test_migrate_accounts.py    # 2026-09-13 新增：戴錶者分帳號；同一晚兩個來源時 Garmin 優先（PR #63）；評分檔已沒有的夜晚備份後清掉
python tests/test_morning_import.py      # 2026-09-15 新增：沒過就停不寫、手錶少夜晚要還原、抓資料只抓最近幾天且不覆寫；【1b】守錄影中間斷掉（三條擋法缺一不可）；評分前要先匯出按鈕、匯出失敗要停
python tests/test_garmin_fetch_merge.py  # 2026-10-03 新增：重抓時視窗外逐筆不變、切點不落在睡眠中間、沒抓到的來源留舊的
python tests/test_garmin_daily_tz.py     # 2026-10-04 新增：每日心率／壓力是當地時間、睡眠那幾段沒被多加 8 小時、舊檔轉換可重複執行
python tests/test_demo_accounts.py       # 2026-11-06 新增：示範帳號夜數比本人多時，手機帳號仍認得本人；刪除不傷本人資料；手錶資料 source 只有 demo、重排的階梯跟評分時同一份；動態牆各自的場景與時刻規則
python tests/test_camera_clips.py        # 2026-11-07 新增：門檻呼叫時才讀、刪帳號連檔案一起刪、網址不含 user_id、只留 14 晚
python tests/test_camera_usual.py        # 2026-11-09 新增：基線只取同一把尺（basis+roi）、不足時說「還需要幾晚」不給 0%、28 天窗格、門檻邊界、同一天不進自己的基線
python tests/test_steps_intraday.py     # 2026-11-15 新增：每 15 分鐘步數 GMT 換當地（不差 8 小時）、沒戴錶的鐘頭是 null 不是 0、只增不減、429 就停、存白天資料時不會蓋掉每小時、只收本人、不進版控（打包檔也不帶）
python tests/test_garmin_daily.py        # 2026-11-13 新增：白天資料的解析、只增不減、429 就停、只收本人、/home 的 yesterday、不進分數也不給好友
python tests/test_sleep_heart_rate.py    # 2026-11-13 新增：心率與手錶動作曲線只取睡著那段、平均從原始讀數算（不是 avg_hr）、動作 0 算真的值、資料不夠回 None、Health Connect 沒有；【5c】Awake HR 只算醒著的（扣掉手錶那兩晚＋標 sleep 的格子）、區間一筆＝2 分鐘、不給靜止心率與最低
python tests/test_camera_curve.py        # 2026-11-13 新增：攝影機曲線每 5 分鐘有幾成在動、不可用的幀不算、沒 ROI 不給、門檻呼叫時才讀、/home 只留睡著那段、回填只補曲線不動別的欄位
python tests/test_scored_efficiency.py   # 2026-11-13 新增：首頁效率顯示進分數的那一個——每種 basis 都有那行字、與 behavior 常數一致、打包檔逐夜直讀評分器
python tests/test_home_activity.py       # 2026-11-13 新增：首頁 Activity 是前一個日曆日、沒資料整塊 None、VO2 max 90 天內、整天心率只取那個日曆日（終點不含隔天 00:00）
python tests/test_morning_report.py      # 2026-11-12 新增（11-17 改寵物 notes：清單外行動、不准說、攝影機與壓力不進 prompt）：小建議觸發與優先順序、12 句與文件逐字一致、自評不進分數不給 XP、AI 每晚只呼叫一次且驗證擋得住、刪帳號一起刪、每晚曲線；不碰網路
python tests/test_awake_count.py         # 2026-11-15 新增：醒來次數＝時間軸的清醒段數（不是 summary 那個多 1 的）、回填只補這一欄、只改 Garmin、舊資料庫補欄位、/home 與 /insights 帶出來
python tests/test_backfill_marks.py      # 2026-11-12 新增：事後補的時間記 recalled、當下按的不能被回想的蓋掉、警語只在用到回想那一端時掛、API 與打包檔同一句
python tests/test_nightly_is_late.py    # 2026-11-15 新增：每晚的 is_late 三種狀態，「沒判」存成 NULL 不是 0（準時）；原本 None 會被存成準時、算進熬夜比率分母（手動補資料才會遇到，11-07 中過）
python tests/test_lights_out_resolve.py  # 2026-11-16 新增：手機挑錯時後端用手錶改正——11-16 真實事件流要挑回 00:49；沒手錶／沒候選／換了日期三種都不動；一段都沒過關存 NULL 不是繼續說熬夜；可重複執行
python tests/test_bridged_unlocks.py     # 2026-11-15 新增：就寢偵測規則 4 的標記——POST /nightly 收 bridged_unlocks；沒送存 NULL 不是 0、送 0 存 0、負數 422、舊資料庫遷移補欄位
python tests/test_wake_on_time.py        # 2026-11-19 新增：準時起床——跨午夜、按鈕優先於手錶、沒量到是 None、牆鐘不差 8 小時、快照不被改目標改寫、手錶晚到讀取時才算、遊戲化走同一份
python tests/test_journey.py             # 2026-11-19 新增：Journey——每站與最後一站、往後移不建立、連 3 天才前進（沒準時重數、沒量到不打斷、不退站）、睡眠長度照送來的存（不拉到 7 小時）、前進後目標＝下一站但以前的快照不變、舊版 App PATCH 掉會被拉回、Stop 後不再拉回、game/ 不讀它、刪帳號一起刪
python tests/test_export_teammate.py     # 2026-11-19 新增：給隊友的副本——真的 id 在輸出檔裡一個位元組都找不到、別的帳號不帶、好友兩個方向都在、沿用 id、不動來源、後端讀副本跟讀來源一樣
python tests/test_no_blocking.py         # 2026-11-21 新增：慢的請求不准卡住別人（開真的 uvicorn 量 /health）、只有真的在 await 的端點才准 async、快取一次整份換掉
python tests/test_camera_auto.py         # 2026-11-21 新增：按 Start Sleep 自動開錄——只認手機帳號＋區網、在錄不開第二個、停錄只放旗標（錄影程式自己收尾，拿掉檢查會紅）、Cancel 搬檔不刪、鎖檔死了當沒在錄、攝影機移動偵測（平移 40 判移動、亮度與床上的人不算、中間值）、早上匯入移動了只擋攝影機、重新框有備份並換基準、API 出錯不讓端點失敗
```

⚠️ `compare_night_sources.py` 不是測試但屬於同一條驗收路徑：它把同一晚的
**四個時刻**擺在一起（開錄／按按鈕／`lights_out`／攝影機測到的入睡），
算出 **D2 唯一用得上的那個數字：手機代理值比實際上床晚多少**（2026-09-06 首測 +3.4 分，n=1）。

```bash
SONNAP_DB=C:/Users/user/Projects/sonnap-data/sonnap.db   python compare_night_sources.py --metrics-dir <有錄影檔的目錄>
```

Flutter（在 `app/` 底下跑，**1092 條全過**，2026-11-21 實測）：

```bash
flutter test
flutter analyze     # No issues found
```

⚠️ Flutter 這邊有幾條測試守的是**壞掉時不會報錯**的機制，改到對應的檔案時要一起看：

| 測試檔 | 守什麼 |
|---|---|
| `lights_out_test.dart` | 就寢時刻偵測的三條規則（見交接區）。含「把 `resumed` 濾掉答案就會壞」的反向對照 |
| `nightly_uploader_test.dart` | 三種「沒上傳」的原因要分得開；body 不含 `target_bedtime`；達成度照抄後端 |
| `account_test.dart` | 建置參數優先於問暱稱；建完一定要存下來（否則使用者每天都是新的一個人）；建不了帳號不能擋住 App |
| `history_pet_test.dart` | 心情不可以從 `final_quality` 推（實測資料裡存在「Good 但 anxious」的夜晚）。⚠️ 釘住日期的那兩條隨效率計不計分改過兩次期望值（10-01 停止計分：08-09 Poor→Bad、08-23 Good→Normal；11-07 恢復計分又改回 Poor／Good），**真正要守的那件事改成由資料推導**（anxious 要橫跨多個品質等級），下次分數位移時才不會又無預警地紅 |
| `measured_efficiency_test.dart` | 只剩服務層：兩個效率的欄位解析得出來、算不出來是 null 不是 0（舊 Insights 那張卡 2026-11-19 拿掉了） |
| `nightly_trigger_test.dart` | 上傳（`NightlySync`）真的有被觸發：打開 App 一次、每次回到前景一次、帳號還沒解析完不跑。拿掉 `main.dart` 任一處觸發，App 照樣開得起來、畫面正常，只有這支會紅 |
| `usage_stats_test.dart` | 服務層的解析與合併；上傳規則改測 `NightlySync`：按過的標記要送、**沒按不得擋住上傳**、後端沒收下（`marksStored`）或進佇列都**不清**標記、送的是待送格就只清待送格 |
| `pre_bed_apps_test.dart` | 睡前 60 分鐘的 App 切段。三個寫錯不會報錯的地方：未配對的 `resumed` 要延續（拿著手機睡著了）、螢幕關閉要關掉區段、區段要與視窗**取交集**不是整段算 |
| `bed_mark_buttons_test.dart` | 首頁那兩個按鈕。⚠️ 第一條驗的是**畫面上要寫「不按也沒關係」**——少了它，忘記按的人會以為那一晚白過了 |
| `bed_marks_test.dart` | 上床／下床標記的保存。過期（>36 小時）與順序顛倒的一律當作沒有——不然上禮拜按的會被配成今晚的一對，算出 40 小時的臥床時間而且不會報錯 |
| `camera_night_parse_test.dart` | 攝影機每晚資料的解析：相對網址接上 baseUrl、clips／usual 欄位有沒有、點了某一晚沒有錄影時**不退回最近一晚**（2026-11-19 舊攝影機卡拿掉，畫面那一半刪了） |
| `game_test.dart` | 等級、解鎖、衣服**照抄後端**（Dart 不反推等級）；沒有後端時要說「需要後端」而不是「以後才有」。衣櫃（2026-11-19 第二版）另守：**點一下只是試穿、右上 ✓ 才送後端，左上 ‹ 離開不送**（壞掉會變成點到就存進後端，畫面看起來一樣正常）、沒解鎖的連試穿都不行、**`kClosetSlotFor` 要含每一件**（漏了就點分類整件消失、不報錯）、禮帽與皇冠的逐姿勢戴法 8 格齊全（見「衣櫃改版」）。⚠️ 衣櫃的預覽用 `HomePet`，不另開一份「現在選哪隻寵物」的狀態——隊友原版自帶 `PetAppearance`，那會是第二個定義處 |
| `friends_test.dart` | 沒有後端時原本的假朋友**一個都不出現**；排行照後端的順序、Dart 不重排；放下手機的時刻是牆鐘時間不是 UTC |
| `assistant_chat_test.dart` | 助理只走 `POST /chat`；後端答不出來（503）時照實說，不退回查表；前文只送最近 5 輪完整的一問一答；失敗的問題不存進手機 |
| `bedtime_reminder_test.dart` | 提醒時刻（含跨午夜）；關掉要 cancel；改目標要重排；提前量不得寫進 Kotlin（含 `1800000L` 這種 Long 寫法） |
| `bedtime_guard_test.dart` | 守門的時間窗（半夜滑手機守的是「昨晚那一窗」）；改目標要重推到原生端；不讀畫面內容；三個 30 分鐘一致 |
| `health_connect_test.dart` | 每個起床日只送最長一段；起床日照牆鐘時間不是 UTC；連不上的下次再送、422 的不再送；沒有後端的 build 不碰 Health Connect；只要睡眠權限 |

⚠️ **`TestWidgetsFlutterBinding` 會把全域 `HttpClient` 換成「一律回 400」的假實作**，
只要同一個檔案裡有任何一條 `testWidgets` 就會裝上。症狀是連 `127.0.0.1:1`
（根本沒有東西在聽）都「成功」拿到 400 而不是丟 `SocketException`，
錯誤訊息完全不會指向 `HttpOverrides`。要打真的 local server 就在該 group 的
`setUp` 裡 `HttpOverrides.global = null`，`tearDown` 還原
（`account_test.dart` 有現成的寫法）。

⚠️ `test_tapo_roi_csv.py` 守的是 `tapo_metric_logger --roi` 的**分母**。
換分母不會拋例外也不會有空值，只會讓門檻整個差一個數量級而數字看起來正常
（第 4 晚的 ROI 只佔畫面 28.9%，用錯分母時「0.75%」會變成「2.6%」）。
四條都用「把 bug 重新引入、確認測試會紅」驗證過。

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
4. （2026-11-18 移除：夢境退場。編號保留）

⚠️ `test_history_mood.py` 守的是 **history 每晚的 `pet_mood` 在兩條路徑上一致**。
同樣三條都用「把 bug 重新引入、確認測試會紅」驗證過：

1. `history[-1].pet_mood` 與 `status.pet_mood` 逐字相同，**且講的是同一晚**
   （少了後面那半句，兩晚剛好都是 Good 時會假性通過）
2. history 每晚都有 `pet_mood`，值落在四個合法值內
3. `/insights`（讀 SQLite）與 asset（讀 JSON）對同一晚給出相同的心情

⚠️ 第 3 條是這支測試存在的主因：兩條路徑讀**不同的資料來源**、走**不同的函式**
（asset 用 `map_pet_mood`、API 用 `resolve_mood`），任何一邊改了規則而另一邊
沒改，都不會有錯誤訊息，只會讓使用者在首頁與 Insights 看到兩隻不同的寵物。
測試裡有一條**反向對照**（確認樣本裡真的有 anxious 的夜晚）——沒有它的話，
把 anxious 覆寫整個拿掉，測試仍然全綠。

**資料通道走 bundled asset，不走 HTTP**（已定案）：

```
garmin/data/*.json → build_app_payload.py → app/assets/data/app_payload.json
                                              ├─→ Flutter rootBundle 讀
                                              └─→ main.py 對外服務同一個檔
```

只產一份檔的理由：兩份就會有「App 顯示的跟 API 回傳的對不上」這種最難查的 bug。
之後要接 HTTP 只要實作 `sleep_repository.dart` 裡預留的 `ApiSleepRepository`。

✅ **四個有資料的分頁都接上真實資料了**：`home_screen` / `insights_screen`（2026-11-19 取代 `report_screen`）/
`assistant_screen`（PR #51 起改問 Claude）/ `friends_screen`（PR #51 起接好友後端）。
⚠️ 好友、助理、遊戲化**需要後端**；沒給 `SONNAP_API_BASE` 的 build 會照實說「需要後端」。

`app/lib/services/` 現在的分工：

| 檔案 | 做什麼 |
|---|---|
| `sleep_repository.dart` | 睡眠資料。asset / API 兩種來源 + 失敗退回，來源顯示在設定頁「Data」 |
| `nightly_sync.dart` | 偵測就寢＋上傳＋問挑戰，App 層在跑（開 App、回到前景）。2026-11-19 從舊 Insights 頁搬出來 |
| `report_loader.dart` | 組一晚的早晨報告（首頁與 Insights 的 Day 共用同一份） |
| `insights_periods.dart` | Insights W/M/Y 的期間切法與加總（中位數、上一期、熬夜照抄 is_late）。純函式 |
| `usage_stats.dart` | 包 `sonnap/usage` channel：手機使用時間 + 就寢時刻查詢 |
| `lights_out.dart` | **純函式**：把互動事件流變成一個就寢時刻。沒有 I/O，測得到 |
| `pre_bed_apps.dart` | 睡前 60 分鐘的 App 切段 |
| `nightly_uploader.dart` / `pending_nightly.dart` | `POST /nightly`；連不上的那一晚進離線佇列，下次補送 |
| `bed_marks.dart` | 上床／下床標記 |
| `backfill.dart` | 補填**過去**沒上傳到的夜晚（連續兩天沒開 App，中間那一晚原本會永遠傳不上去）。只換 `now`，偵測走同一條 `lightsOut()` 路徑 |
| `user_identity.dart` / `account_service.dart` | 身分的兩條路（見交接區） |
| `user_settings.dart` | 目標就寢時間與提醒開關的保存與同步（PATCH 後端） |
| `key_value_store.dart` | 包 `sonnap/store` channel（Android SharedPreferences） |
| `challenges_service.dart` / `home_service.dart` / `camera_insights.dart` | 讀後端算好的挑戰進度、熬夜比率、攝影機臥床時間（Dart 不重算） |
| `game_service.dart` / `friends_service.dart` / `chat_service.dart` | 遊戲化、好友、助理（PR #51） |
| `bedtime_reminder.dart` / `notification_service.dart` | 就寢提醒（`sonnap/notify`） |
| `bedtime_guard.dart` | 就寢守門（`sonnap/guard`） |
| `health_connect.dart` | Health Connect（`sonnap/health`） |

原生端在 `app/android/app/src/main/kotlin/com/example/app/`，
`MainActivity.kt` 註冊 5 個 channel：

| channel | Kotlin |
|---|---|
| `sonnap/usage` | `UsageStatsService.kt`（使用時間 + `queryEvents`） |
| `sonnap/store` | `KeyValueStore.kt` |
| `sonnap/notify` | `NotificationService.kt`、`BedtimeReminderReceiver.kt` |
| `sonnap/guard` | `BedtimeGuardBridge.kt`、`BedtimeGuardService.kt`、`GuardConfigStore.kt`、`GuardReminderActivity.kt` |
| `sonnap/health` | `HealthConnectService.kt`、`HealthPrivacyActivity.kt` |

⚠️ **原生端只回事實，產品判斷留在 Dart。** 「哪些 App 要顯示」「哪一段安靜算睡覺」
都在 Dart——門檻寫進 Kotlin 的話，每次調整都要重編 APK 才驗得了。

⚠️ `assistant_screen` 的答案來自 **`POST /chat`**（`ai/chat.py`，呼叫 Claude）：

- 🔴 **每問一次就花一次 API 額度。** 測試（`tests/test_chat.py`）有三道保險確保不打真的 API，
  改測試時不要拆掉任何一道。
- 模型只拿到 `build_facts()` 組好的**既有欄位**。**不要在這裡加「算出來」的建議**——
  那會變成第二套沒有文獻依據的評分層（紅線 4）。
- 回答要過驗證才交出去，禁字、中文洩漏、拼字數值**直接 import 自 `ai/text_guards.py`**
  （與寵物 notes 共用同一份定義，不要複製一份）；回答裡的數字要跟事實對得上。
  最多試 `MAX_ATTEMPTS = 2` 次，都沒過就回 **503**，App 照實說答不出來——
  **不交出沒通過驗證的回答，也不退回舊的查表**。
- 伺服器沒設金鑰時同樣回 503。

**助理頁是對話**（2026-11-19，`screens/assistant_screen.dart`、`services/chat_thread.dart`）：說話的是寵物「Your buddy」，背景是使用者生成的寵物房間 `assets/backgrounds/assistant_room.jpg`。

| 規則 | 不遵守的後果 |
|---|---|
| **追問要帶前文**：App 每次送最近 **5 輪**（`kChatContextRounds`，只取一問一答都在的）到 `POST /chat` 的 `history`；後端最多收 10 則（超過 422）、角色只收 user／assistant，再夾一次取最後 10 則（`ai/chat.MAX_HISTORY_MESSAGES`） | 「為什麼？」接不上；送整串會讓 prompt 與額度一直長 |
| 🔴 **前文不是事實來源**：數字驗證照舊只認 FACTS，前文裡的數字不算（`test_chat.py`【6c】守著）；前文排在 FACTS 之後、QUESTION 之前 | 使用者說「我睡了 9 小時」，AI 就能照抄成事實 |
| 對話**只存在手機上**（`sonnap/store` 的 `assistant_thread_v1`，最多 40 則），不送後端存；✎ 開新對話＝清掉；**沒有歷史頁** | 使用者定 |
| **只存一問一答都成功的**：答不出來（503）的問題留在畫面上可以重試（`assistant-retry`），但不存、也不當前文送出 | 存了的話重開 App 會留一句沒有回答的孤兒問題，下一次還會被當成前文（2026-11-20 修，`assistant_chat_test.dart` 守著） |
| 建議問題是固定清單（`kAssistantSuggestions`）；原本寫死的「What affected your sleep」拿掉了 | — |
| **寵物心情與目標時間**（2026-11-21／22）：事實裡有 `pet_mood`（跟 `/home` 同一隻、同一支 `resolve_mood`），只給「這一晚由哪一類訊號決定」＋一般規則 `PET_MOOD_RULE`，不給 `mood_reason`、不給壓力；目標分成 `current_target_bedtime` 與那一晚的 `target_bedtime_that_night` | 只給這一晚的話 AI 會推成「心情完全跟睡眠無關」；只給現在的目標的話，目標改過之後 AI 會拿新目標去對舊的一晚（手機實測：那晚用 01:25 判，AI 說 04:00）。`test_chat.py`【6d】【6e】守著 |
| **分段回答**（2026-11-22 grill，參考 Oura／WHOOP）：`/chat` 回 `headline`（一句、≤25 字）、`why`（0–1 句、≤30 字、只准 might／can）、`tips`（0–2 條）、`link`（0–1 個）；合起來的 `answer` 留給舊版 App。**建議只能從那一晚適用的清單挑**（跟寵物 notes 同一支 `morning_tips.applicable_tips()`，自評標籤也交給 AI）；headline／why 講到某條建議的重點字卻沒選它就擋（準時放手機、固定就寢可以講）。每條建議的 **Why 那一行是後端固定表 `ai/chat.WHY`**（使用者審過），不是 AI 寫的；鍵＝App 的 `kTipToPlan`。App：對得上計畫的才出現「+ Add "caffeine earlier" to my plan」（短名字 `kPlanShortNames`，加進去的是清單整句）；連結只有首頁 `NightSheets` 開得了的四頁（`ai/chat.LINKS`，首頁登記 `NightSheetLinks.shared`）；回答底下兩顆追問＝`kAssistantSuggestions` 裡還沒問過的（不經過 AI）；輸入框上方固定 `kAssistantDisclaimer`。對話存 `assistant_thread_v2`，v1 照一段文字讀。⚠️ 資料仍只有最近一晚（「哪一晚／哪一週」是下一個 PR） | AI 自己挑建議會替文獻下結論（同 notes 11-17）；Why 交給 AI 寫就會編原因。`test_chat.py`【6f】、`assistant_answer_format_test.dart` 守著 |

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
   加新規則前先問「它會不會誤傷正常說法」——AI 夢境（已退場）那三次全是這個原因。
6. **引用文獻一律核對第一作者。**已經誤植過兩次（K 節 Troxel/Iskander、
   RIRI 論文的 Czeisler ME 被寫成 Mason et al.）。
