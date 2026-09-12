# 就寢守門（B4）

就寢時間快到時，打開自己選的 App（例如抖音、IG）會跳一個提醒，或直接被送回桌面。

## 兩種模式

| 模式 | 打開名單上的 App 時 | 適合 |
|---|---|---|
| Full-screen reminder | 蓋一層可以關掉的提醒，App 還在。同一個 App 10 分鐘內不重複 | 想被提醒、不想被管 |
| Send me back to the home screen | App 直接被關掉、回到桌面 | 自制力不夠、要硬擋 |

守的時間：**目標就寢時間前 30 分鐘 → 目標就寢時間後 6 小時**（目標 23:30 → 23:00 到隔天 05:30）。

- 前 30 分鐘與就寢提醒、首頁倒數變紅是同一個數字。三個不一致的話，通知說「還有 30 分」、倒數還是綠的、App 卻已經被擋了。
- 後 6 小時要涵蓋「過了就寢時間還在滑」那幾個小時（正是睡眠拖延的時段），但不能守到白天——早上查公車被擋，使用者只會把整個功能關掉。
- 這兩個數字是**行為提示的工程判斷，不是計分門檻**，不進任何分數（紅線 4）。

## 程式在哪

| 檔案 | 做什麼 |
|---|---|
| `app/lib/services/bedtime_guard.dart` | 全部的判斷：時間窗、模式、名單、提醒文字。`GuardConfig.actionFor()` 是原生端行為的規格 |
| `app/lib/screens/bedtime_guard_screen.dart` | 設定頁（Settings → Bedtime Guard） |
| `.../kotlin/.../BedtimeGuardService.kt` | 無障礙服務：只聽「哪個 App 跑到前景」，照 Dart 推來的設定動作 |
| `.../kotlin/.../GuardConfigStore.kt` | 存 Dart 推來的設定。唯一自己做的事是「時間窗過了就往後推一天」 |
| `.../kotlin/.../GuardReminderActivity.kt` | 提醒模式的全螢幕畫面（平台原生，不開 Flutter——背景觸發時啟動引擎太慢） |
| `.../res/xml/bedtime_guard_config.xml` | `canRetrieveWindowContent="false"`：**不讀畫面內容**。設定頁上的承諾靠這一行成立 |

⚠️ 門檻都在 Dart。寫進 Kotlin 的話每次調整都要重編 APK 才驗得了（`bedtime_guard_test.dart` 有一條在守）。

## ⚠️ 已知限制

1. **Google Play 不會讓它上架。** Play 政策規定 Accessibility API 只能用於協助身心障礙者。D2 走側載，沒有這個問題；要上架的話得換成 Digital Wellbeing 那類做法或整個拿掉。
2. **Android 13 起側載 App 的無障礙開關預設是灰的**（「受限設定」）。使用者要先到「應用程式資訊 → 右上角選單 → 允許受限設定」，才能在無障礙設定裡打開 Sonnap。設定頁上有寫這一句。
3. **沒有在實機驗證過**（2026-09-11 只驗證了 `flutter build apk --debug` 編得過、Dart 端測試全過）。要實機確認的：
   - 打開無障礙服務後，設定頁顯示 "Accessibility access is on."
   - Send-home 模式：守的時段內打開名單上的 App → 立刻回桌面；時段外 → 正常打開
   - Reminder 模式：跳出提醒、按 OK 回到原本的 App；10 分鐘內再開同一個 App 不再跳
   - 改了目標就寢時間 → 守的時段跟著移動
4. **三星等 ROM 可能在省電時殺掉無障礙服務**，症狀是「開關還開著但沒作用」。沒有辦法從 App 端偵測。
5. **擋得住「打開」，擋不住「一直開著」**：服務只在視窗切換時觸發。在守的時段開始之前就已經開著的 App，要等使用者切出去再切回來才會被擋。
