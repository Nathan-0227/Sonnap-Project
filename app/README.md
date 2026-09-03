# Sonnap App（Flutter 前端）

> 這份取代了 `flutter create` 產生的樣板 README。
> 專案整體現況見 [`../PROJECT_STATUS.md`](../docs/PROJECT_STATUS.md)。

睡眠監測 + AI 寵物陪伴的 App 前端。五個分頁，底部導覽列切換。

**環境**：Flutter 3.44.9（stable）/ Dart 3.12.2

---

## 快速開始

```bash
cd app
flutter pub get
flutter run -d chrome        # 也可以 -d edge 或 -d windows
```

跑起來後在終端機按 `r` 熱重載、`R` 完整重啟、`q` 離開。

⚠️ **資料要先產生**。App 讀的是 `assets/data/app_payload.json`，
那個檔由 Python 產生，沒有它首頁會顯示錯誤狀態：

```bash
cd ..
python garmin/run_pipeline.py    # 約 2 秒
```

---

## 五個分頁的真實狀態（2026-09-04）

**五頁裡有三頁接了真實資料。**

| 分頁 | 檔案 | 行數 | 狀態 |
|---|---|---|---|
| Home | `screens/home_screen.dart` | 333 | ✅ **真實睡眠資料** |
| Insights | `screens/report_screen.dart` | 2606 | ✅ **真實資料**（`payload.history` 30 晚 + 手機使用時間） |
| Assistants | `screens/assistant_screen.dart` | 212 | ✅ **真實 payload**（罐頭回覆已移除） |
| Friends | `screens/friends_screen.dart` | 303 | ❌ 四個好友寫死（Mochi/Coco/Nala/Dango）<br>**卡在社交功能還沒有後端** |
| Settings | `screens/settings_screen.dart` | 548 | 🟡 就寢時間已與首頁同步，但**存不下來**（見下） |

### ⚠️ Settings 的設定目前不會被記住

就寢時間現在兩頁同步了（state 提到 `_MainPageState`），但：

- **沒有存到裝置**——關掉 App 就回到預設值
- **沒有送到後端**——`users.target_bedtime` 才是 Tier A 一切計算的基準，
  改了 UI 不影響任何計算
- `username` / `email` 仍寫死為 `"Jeremy"` / `"jeremy@email.com"`。
  ⚠️ 後端**刻意不收 email**（暱稱制免註冊，隱私設計），
  所以 UI 顯示一個假 email 是在展示一個不存在的功能

→ 要讓「使用者自行設定」成真，就是 `PATCH /users/{user_id}`，
跟多使用者接線是同一條路。

### ⚠️ 睡眠助理是「路由器」不是「生成器」

`services/assistant_answers.dart` 用 `_topicKeywords` 把問題分到 12 個主題，
每個主題**只從 payload 取既有欄位組句子**，**不自己產生任何建議**。

理由是專案紅線 4：自己算出來的建議會變成**第二套沒有文獻依據的評分層**。
→ 問不出來的題目要**老實說「我沒有這項資料」**並列出真的做得到的事。

### ⚠️ 解析 payload 的時間一律走 `parseWallClock()`

`models/wall_clock.dart`。**不要用 `DateTime.tryParse(...).hour`**——
`tryParse("2026-08-22T22:32:00+08:00")` 回傳的是 **UTC**，`.hour` 因此早 8 小時
（22:32 會顯示成 14:32）。這個 bug 曾經同時出現在 Insights 圖表與睡眠助理上。

**也不要用 `.toLocal()`**：那會跟著手機時區跑，而這些是已經記錄下來的事實，
要的是字串裡那個 `+08:00` 的牆鐘時間。

### 寵物動畫跟著 `pet_mood` 走

`widgets/pet_mood_animation.dart` + 四個 Lottie 資產：
`happy_dog.json` / `tired_dog.json` / `bored_dog.json` / `anxious_dog.json`。

## 程式碼結構

只有 `lib/` 是要看的。`android/` `ios/` `linux/` `macos/` `windows/` `web/`
是 `flutter create` 產生的平台外殼，`build/` 與 `.dart_tool/` 是建置快取。

```
lib/
├── main.dart              啟動點 + 底部五個分頁的切換
│
├── models/                「資料長什麼樣」——等於 Python 的 dataclass
│   ├── sleep_session.dart   根物件，持有下面三個 + scoring / streak / history
│   ├── metrics.dart         量測數值（含 Dart 語法導覽，第一次讀 Dart 可以從這裡開始）
│   ├── ai_content.dart      AI 生成的建議與夢境
│   ├── status.dart          寵物心情與能量
│   ├── wall_clock.dart      ⚠️ 解析 payload 時間一律走這裡（見上方時區說明）
│   └── friend_pet.dart      好友（目前只有假資料在用）
│
├── services/              「資料從哪裡來」
│   ├── sleep_repository.dart    asset / API / 失敗退回，三種實作
│   ├── assistant_answers.dart   睡眠助理的查表路由（不是生成器）
│   └── usage_stats.dart         Android 手機使用時間（UsageStats）
│
├── screens/               五個分頁，一頁一個檔
└── widgets/               14 個可重用元件（卡片、按鈕、寵物動畫…）
```

**screens 和 widgets 的差別**：widget 是一張卡片，screen 是把卡片排成一頁。
例如首頁由 `HeaderCard` + `PetCard` + `SleepScoreCard` + `PetMoodCard` +
`SleepStreakCard` 組成。分開的好處是同一張卡片能在多個頁面重複使用。

---

## 資料從哪裡來

```
garmin/run_pipeline.py            ← Python 端，約 2 秒
        ↓ 產生
assets/data/app_payload.json      ← 只有這一份檔
        ↓ rootBundle.loadString()
services/sleep_repository.dart    ← 讀檔
        ↓ SleepSession.fromJson()
models/sleep_session.dart         ← 變成 Dart 物件
        ↓ FutureBuilder
screens/home_screen.dart          ← 決定畫什麼
        ↓ 傳參數
widgets/sleep_score_card.dart     ← 畫出「46」
```

**同一份檔案 `main.py` 也拿去對外服務**（`GET /get-sleep-data`）。
刻意只產一份：兩份就會出現「App 顯示的跟 API 回傳的對不上」這種最難查的 bug。

### ⚠️ 兩個要知道的限制

1. **預設仍是打包的 asset，資料凍結在 build 當下**。`ApiSleepRepository` 已經實作好了
   （用 `dart:io` 的 `HttpClient`，**沒有加 `http` 套件**，延續「優先用標準庫」的原則），
   base URL 由 `--dart-define=SONNAP_API_BASE` 帶入；沒帶就走 asset。
   `FallbackSleepRepository` 連不到後端會退回 asset，demo 不會因為後端沒開就掛掉。

   ⚠️ **但退回這件事必須說出來**——Insights 的 Tracking Sources 卡會明講現在是
   live 還是 bundled。退回的 asset 是真資料、只是可能過期，
   **而過期卻不自知同樣是說謊**。
2. **前端不做任何判斷**。分數好不好、顯示哪種心情、說哪句話，全部由 Python
   算好放在 payload 裡。沿用專案原則「Python 判斷，Dart 只負責畫」——
   這樣所有判斷都能追溯到有文獻依據的那一層。
   **要改判斷邏輯是改 `build_app_payload.py`，不是改 Dart。**

---

## 套件相依（刻意維持極少）

```yaml
cupertino_icons   # 圖示
lottie            # 寵物動畫（assets/animations/happy_dog.json）
intl              # 日期格式
```

**資料層沒有增加任何套件**——`rootBundle` 與 `dart:convert` 都是 Flutter/Dart
內建。這跟 AI 模組選 `urllib.request` 不裝 SDK 是同一個理由：多一個相依要有
實際需求才值得。

---

## 測試

```bash
flutter analyze     # 目前 3 個 warning（report_screen 未使用的顏色常數）
flutter test        # 實測 72 個測試全過
```

| 檔案 | 測什麼 | 條數 |
|---|---|---|
| `test/widget_test.dart` | App 起得來、五個分頁都在、首頁顯示真值、讀不到資料時顯示錯誤狀態 | 3 |
| `test/sleep_repository_test.dart` | 讀**真實的** asset，驗證整條解析路徑 | 1 |
| `test/sleep_repository_fallback_test.dart` | 成功走 api、失敗退 asset 且 `lastSource` 要跟著改、失敗原因不能吞掉 | 6 |
| `test/pet_mood_animation_test.dart` | 四種心情各自對到自己的資產，資產缺席時退到濾鏡版 | 7 |
| `test/assistant_answers_test.dart` | 12 個主題的路由；問不出來的要老實說沒有，**不得自己編建議** | 17 |
| `test/wall_clock_test.dart` | `+08:00` 解析成牆鐘時刻，不轉 UTC 也不跟著手機時區跑 | 8 |
| `test/bedtime_sync_test.dart` | 兩頁初始值一致、雙向同步，且要走到 `HeaderCard` 那一層 | 5 |
| `test/history_pet_test.dart` | 點趨勢圖某一晚，寵物跟著那一晚變 | 13 |
| `test/usage_stats_test.dart` | 手機使用時間的解析與彙總 | 12 |

### 寫測試踩過的三個坑（留著避免有人改回去）

1. **不要用 `pumpAndSettle()`** — `PetCard` 的 Lottie 是無限循環動畫，
   `pumpAndSettle` 會一直等它停下來然後逾時。用固定次數的 `pump()`。
2. **分數要用 `findRichText`** — `SleepScoreCard` 用 `Text.rich` 把 "46" 和
   "/100" 併成一個 `RichText`，普通的 `find.text('46')` 抓不到。
3. **讀真實 asset 的測試必須獨立成一個檔** — 它用 `tester.runAsync()` 跑真實
   非同步 I/O，會跟前面 widget 測試留下的 `Timer.periodic` 互相卡住（實測會整個
   hang）。`flutter test` 每個檔跑在獨立 isolate，拆檔就解決。

---

## 待處理

依「投報比」排序：

1. **Settings 存下來** — 就寢時間要 (a) 存到裝置、(b) `PATCH /users/{id}` 送到後端。
   目前改了只在這次開 App 期間有效
2. **使用者名稱去寫死** — `username` / `email` 拿掉硬編碼；email 那一列**直接移除**
   （後端刻意不收 email）
3. **多使用者接線** — 首次啟動 `POST /users` 拿 `user_id` 並存住，資料改走
   `GET /home?user_id=`。後端 11 個端點已就緒且結構相容，`models/` 一行都不用改。
   ⚠️ `user_id` 本身就是憑證（沒有密碼），同意書要寫清楚
4. **Friends** — 卡在社交功能沒有後端，那是全隊決策

✅ 已完成（先前排在這張表上的）：Insights 接 `payload.history`、Assistants 接真實
payload、寵物動畫四態化、就寢時間兩頁同步、`ApiSleepRepository` + 失敗退回、
手機使用時間（UsageStats）。

完整的優先順序與理由見 [`../docs/PROJECT_STATUS.md`](../docs/PROJECT_STATUS.md) 第七節。
