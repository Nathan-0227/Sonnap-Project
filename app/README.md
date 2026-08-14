# Sonnap App（Flutter 前端）

> 這份取代了 `flutter create` 產生的樣板 README。
> 專案整體現況見 [`../PROJECT_STATUS.md`](../PROJECT_STATUS.md)。

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

## 五個分頁的真實狀態

⚠️ **只有 Home 接了真實資料**，其餘四頁仍是寫死的內容。

| 分頁 | 檔案 | 行數 | 狀態 |
|---|---|---|---|
| Home | `screens/home_screen.dart` | 321 | ✅ **顯示真實睡眠資料** |
| Friends | `screens/friends_screen.dart` | 303 | ❌ 四個好友寫死（Mochi/Coco/Nala/Dango）<br>**卡在「沒有多使用者系統」** |
| Insights | `screens/report_screen.dart` | 1231 | ❌ 圖表資料寫死在 `CustomPainter` 裡<br>**最容易補**：`payload.history` 已備好 30 晚，後端零改動 |
| Assistants | `screens/assistant_screen.dart` | 200 | ❌ `_getMockAiResponse()` 罐頭回覆<br>真實建議已在 `ai_content.advice` 裡，可直接接 |
| Settings | `screens/settings_screen.dart` | 548 | ❌ 開關不持久化；使用者名稱寫死為 "Jeremy"<br>登出未實作（UI 自己有標註） |

---

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
│   └── friend_pet.dart      好友（目前只有假資料在用）
│
├── services/              「資料從哪裡來」
│   └── sleep_repository.dart
│
├── screens/               五個分頁，一頁一個檔
└── widgets/               17 個可重用元件（卡片、按鈕…）
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

1. **資料凍結在 build 當下**。走的是打包進 App 的 asset，所以使用者裝了之後
   數字永遠不會變。要改成即時更新得實作 `sleep_repository.dart` 裡預留的
   `ApiSleepRepository`（後端已備好，CORS 也開了；那時才需要加 `http` 套件）。
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
flutter analyze     # 應該是 No issues found
flutter test        # 4 個測試
```

| 檔案 | 測什麼 |
|---|---|
| `test/widget_test.dart` | App 起得來、五個分頁都在、首頁顯示真值、讀不到資料時顯示錯誤狀態 |
| `test/sleep_repository_test.dart` | 讀**真實的** asset，驗證整條解析路徑；並鎖住幾個不該被改壞的約定 |

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

1. **Insights 接上 `payload.history`** — 後端零改動，最划算
2. **Assistants 接上 `ai_content.advice`** — 資料已經在 payload 裡
3. **Settings 加設定持久化** — 需要 `shared_preferences` 套件
4. **Friends** — 卡在多使用者架構，那是全隊決策，沒定案前做不了

完整的優先順序與理由見 [`../PROJECT_STATUS.md`](../PROJECT_STATUS.md) 第七節。
