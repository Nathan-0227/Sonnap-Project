# Health Connect 串接（B8）

有戴手錶／手環的受測者，手錶 App（Samsung Health、Garmin Connect、Fitbit、小米…）會把睡眠寫進 Android 的 Health Connect。Sonnap 從那裡讀睡眠 session，送到 `POST /wearable`，後端用**跟 Garmin 同一套評分器**打分（`wearable/healthconnect_adapter.py`，一個門檻都沒改）。

## 使用者看到什麼

Settings → Health Connect：

1. 手機沒有 Health Connect → 顯示「這支手機沒有」
2. 要安裝／更新 → 按鈕帶去 Play 商店
3. 有 → 「Connect and sync」→ 跳 Health Connect 的授權畫面（只要「睡眠」一項）→ 送出 → 顯示「送了幾晚、最新一晚後端評為 Good/Normal/…」

授權之後，每次開 App 會自動同步一次（**不會**再跳授權畫面）。

## 規則

| 規則 | 為什麼 |
|---|---|
| 往回讀 **3 天** | 涵蓋週末沒開 App。寫在 Dart（`kHealthLookback`），Kotlin 只照 Dart 給的範圍讀 |
| **每個起床日只送最長的那一段** | 後端以（使用者, 起床日）upsert。午覺也是一筆 session、起床日跟前一晚一樣，照順序全送的話午覺會蓋掉那一晚，而且照樣回 201 |
| 同一天後來出現更長的一段 → 送新的 | 手錶可能先寫半段、同步後補成完整的一段 |
| 連不上 → 下次開 App 再送；後端 422 → 不再送 | 422 代表這一段算不了（例如沒有分期），送幾次都一樣 |
| 沒有後端的 build 完全不碰 Health Connect | demo build 開起來跳授權畫面、授權了也沒地方送 |
| 只要 `READ_SLEEP` | 多要的權限會一起出現在授權畫面，受測者看到心率、步數、體重可能整組拒絕 |

## ⚠️ 已知限制

1. **沒有在實機驗證過**（2026-09-11 只驗證了 `flutter build apk --debug` 編得過、Dart 端測試全過）。要實機確認的：
   - 設定頁狀態正確（有／沒有／要更新）
   - 按「Connect and sync」會跳 Health Connect 授權畫面，而且畫面上「這個 App 怎麼使用你的資料」點得開（`HealthPrivacyActivity`）
   - 授權後送出，後端 `wearable_nightly` 多一列 `source=health_connect`
   - 手錶那晚有分期時後端給分；只有「睡著／醒著」沒有深淺睡的裝置也要送得進去（adapter 把 `sleeping` 算進總睡眠）
2. **心率沒有送。** 後端那一欄是「睡眠期間」的平均心率，要算對得先知道入睡時刻（那是後端從分期推出來的），在 Dart 重算就有第二個定義處。Tier3 對 Health Connect 來源本來就是 0（見 adapter 的 `HC_MODIFIER_NOTE`），所以分數不受影響。
3. **最低 Android 版本從 7.0 拉到 8.0**（`minSdk` 24 → 26）：Health Connect 的函式庫要求的。Health Connect 本身要 Android 9 以上，更舊的手機 App 照樣能用，只是設定頁顯示「沒有 Health Connect」。
4. **只有午覺、沒有夜間睡眠的那一天**，午覺會被當成那天的睡眠送出去。要擋就得訂「多短不算一晚」的門檻，那個門檻沒有文獻依據，所以沒訂。
5. Health Connect 預設只給授權前 30 天的資料；3 天的回看不受影響。

## 程式在哪

| 檔案 | 做什麼 |
|---|---|
| `app/lib/services/health_connect.dart` | 挑哪幾段、上傳、記住送過哪些 |
| `app/lib/screens/health_connect_screen.dart` | 設定頁 |
| `.../kotlin/.../HealthConnectService.kt` | 讀 SleepSessionRecord，轉成 adapter 要的格式（帶記錄當下的時區偏移） |
| `.../kotlin/.../HealthPrivacyActivity.kt` | 授權畫面上的隱私說明頁。⚠️ 少了它授權畫面不會出現，也不會報錯 |
| `app/android/app/build.gradle.kts` | `connect-client:1.1.0`、`kotlinx-coroutines-android` |
