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
| **同一晚已經有 Garmin → 後端回 409、不蓋，App 不再送**（2026-09-13 使用者決定：Garmin 優先） | 實機上兩者常是**同一支錶**：Garmin Connect 把睡眠同步進 Health Connect，Sonnap 再讀一次，同一晚變兩個分數（09-11：Garmin 69.8、Health Connect 75.9）。留 Garmin 是因為它有戴錶者分段與 Tier3。反方向：`migrate_garmin_to_db.py` 會蓋掉 Health Connect 的那一列。畫面上會寫「N nights already had Garmin data」 |
| 沒有後端的 build 完全不碰 Health Connect | demo build 開起來跳授權畫面、授權了也沒地方送 |
| 只要 `READ_SLEEP` | 多要的權限會一起出現在授權畫面，受測者看到心率、步數、體重可能整組拒絕 |

## ⚠️ 已知限制

1. ✅ **實機驗證過：2026-11-17 第一次真的送出，整條通了。**

   | 事實 | 證據 |
   |---|---|
   | 手機真的讀到 Health Connect 並送出去 | 手機本機的 `health_uploaded_sessions` 有 3 段：`2026-11-17 06:00→11:22`、`2026-11-17 23:30→11-18 02:30`、`2026-11-19 01:24→06:05`（`adb shell run-as com.example.app cat shared_prefs/sonnap_store.xml`） |
   | 後端真的收下、寫成 `source=health_connect` | 2026-11-19 早晨匯入印出 `Replaced Health Connect data with Garmin on 1 nights (Garmin takes priority): ['2026-11-19']`——能被蓋掉就表示那一列先存在過 |
   | **Garmin 優先那條規則在真實資料上生效了** | 同上那一行。這是 2026-09-13 定的規則第一次被真的觸發，不是測試情境 |
   | 「同一支錶兩個來源」真的會發生 | 送出的兩段與 Garmin 自己量的視窗**逐分相同**（11-18 的 23:30→02:30、11-19 的 01:24→06:05）。Garmin Connect 把睡眠同步進 Health Connect，Sonnap 再讀一次——這正是當初訂優先權的理由 |

   ⚠️ **還沒驗到的**：
   - 授權畫面上「這個 App 怎麼使用你的資料」點不點得開（`HealthPrivacyActivity`）
   - 設定頁在「沒有 Health Connect」「要更新」兩種手機上的狀態
   - **只有「睡著／醒著」沒有深淺睡的裝置**送不送得進去（本人這支是 Garmin，一直有分期）
   - 第一段 `2026-11-17 06:00→11:22` 是白天那一覺，落在 11-17 這個起床日。它後來被 Garmin 蓋掉了，所以「午覺會被當成那天的睡眠」（限制 4）這件事**在真實資料上發生過一次**，只是剛好有 Garmin 接手
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
