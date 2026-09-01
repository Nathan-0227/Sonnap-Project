package com.example.app

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings

class UsageStatsService(private val context: Context) {

    fun hasUsageAccess(): Boolean {
        val appOps =
            context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager

        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                context.packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                context.packageName
            )
        }

        return mode == AppOpsManager.MODE_ALLOWED
    }

    fun openUsageAccessSettings() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    fun getUsage(
        startTime: Long,
        endTime: Long,
    ): List<Map<String, Any>> {

        if (!hasUsageAccess()) {
            return emptyList()
        }

        val usageStatsManager =
            context.getSystemService(
                Context.USAGE_STATS_SERVICE
            ) as UsageStatsManager

        // ⚠️ 用 queryAndAggregateUsageStats 而不是 queryUsageStats。
        //
        // `queryUsageStats(INTERVAL_DAILY, ...)` 回傳的是一串**原始 bucket**，
        // 同一個 package 只要跨到多個 bucket 就會出現好幾筆，而每一筆的
        // totalTimeInForeground 只是那個 bucket 的片段。不自己加總的話：
        //
        //   - 同一個 App 在畫面上重複出現（實機看到 One UI Home 兩列、
        //     Google 兩列——那不是兩個不同的 package，是同一個的不同 bucket）
        //   - 每一筆的數字都遠小於真實使用時間，跟系統「數位健康」對不上
        //     （實機：Sonnap 顯示 Google 10 分鐘，數位健康顯示的量級完全不同）
        //
        // `queryAndAggregateUsageStats` 是專門為此設計的：回傳
        // Map<packageName, UsageStats>，已經依 package 把區間內的量加總好。
        val aggregated = usageStatsManager.queryAndAggregateUsageStats(
            startTime,
            endTime
        )

        val packageManager = context.packageManager
        val launchers = launcherPackages()

        return aggregated.values
            .filter { it.totalTimeInForeground > 0 }
            .map { usage ->

                val packageName = usage.packageName

                // ⚠️ 查不到名稱時**退回套件名，不要把整筆丟掉**。
                //
                // 前一版是 `catch { null }` + mapNotNull，於是每一個查不到
                // 名稱的 App 都被安靜刪除，清單看起來正常但漏掉了重點
                // （見 AndroidManifest 的 <queries> 註解）。
                // <queries> 補上之後這種情況應該極少，但真的發生時，
                // 顯示 "com.某個.套件" 遠好過假裝那段使用時間不存在。
                val appName = try {
                    packageManager
                        .getApplicationLabel(
                            packageManager.getApplicationInfo(packageName, 0)
                        )
                        .toString()
                } catch (_: Exception) {
                    packageName
                }

                mapOf(
                    "package_name" to packageName,
                    "app_name" to appName,
                    "usage_minutes" to
                        (usage.totalTimeInForeground / 60000L).toInt(),
                    // 是不是桌面啟動器。實機實測它永遠排第一——只要人停在
                    // 主畫面就累積它的前景時間，但那不是「讓你熬夜的 App」。
                    // 這裡只標記、不過濾：原生端提供事實，
                    // 「要不要顯示」是產品決定，留在 Dart 端。
                    "is_launcher" to launchers.contains(packageName),
                )
            }
            .filter {
                (it["usage_minutes"] as Int) > 0
            }
            .sortedByDescending {
                it["usage_minutes"] as Int
            }
    }

    /**
     * 區間內的「互動事件」逐筆流，時間遞增。
     *
     * ## 為什麼需要這個，getUsage 不夠嗎
     *
     * `getUsage()` 給的是**日彙總**——「昨天抖音 2h28m」。它沒有時間軸，
     * 所以答不出 `lights_out_at`（最後一次放下手機的時刻），而那是
     * `POST /nightly` 的必填欄位、整個 Tier A 行為層的入口。
     *
     * ## ⚠️ 這裡只回事實，不回結論
     *
     * 本方法**不判斷哪一刻是就寢**。它回傳原始事件，讓 Dart 端做
     * 「哪一段安靜長到像睡覺」的推論。理由同 `is_launcher`：原生端提供
     * 事實，產品判斷留在一個看得到、改得動、測得到的地方。
     * 把門檻寫進 Kotlin 的話，每次調整都要重編 APK 才驗得了。
     *
     * ## 為什麼 RESUMED 也要回，不是只回 PAUSED
     *
     * 直覺是「只要最後一筆 ACTIVITY_PAUSED 就好」。那會錯，因為
     * **連續使用同一個 App 期間一個事件都不會產生**：
     *
     *     23:05 RESUMED（打開 YouTube）
     *     …看了兩小時，中間沒有任何事件…
     *     01:00 PAUSED（螢幕關掉）
     *
     * 只看 PAUSED 的話，23:05 與 01:00 之間看起來是「兩小時沒動手機」，
     * 會被誤判成睡著。要有 RESUMED 才知道那兩小時是**在用**不是安靜。
     *
     * ## 事件型別
     *
     * `ACTIVITY_RESUMED` / `ACTIVITY_PAUSED` 是各家 ROM 都給的。
     * `SCREEN_NON_INTERACTIVE` 與 `KEYGUARD_SHOWN` 更貼近「放下手機」，
     * 但**不保證拿得到**（部分 ROM 只發給系統 App）。所以兩者都收，
     * 有就更準、沒有也不會失效，並在每一筆標上 type 讓上層看得出來源。
     *
     * @param limit 上限筆數，超過時**保留最新的**（就寢時刻在區間尾端）。
     */
    fun getInteractionEvents(
        startTime: Long,
        endTime: Long,
        limit: Int = 2000,
    ): List<Map<String, Any>> {

        if (!hasUsageAccess()) {
            return emptyList()
        }

        val usageStatsManager =
            context.getSystemService(
                Context.USAGE_STATS_SERVICE
            ) as UsageStatsManager

        val events = usageStatsManager.queryEvents(startTime, endTime)
        val collected = ArrayList<Map<String, Any>>()
        val event = UsageEvents.Event()

        while (events.hasNextEvent()) {
            events.getNextEvent(event)

            val type = when (event.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> "resumed"
                UsageEvents.Event.ACTIVITY_PAUSED -> "paused"
                UsageEvents.Event.SCREEN_NON_INTERACTIVE -> "screen_off"
                UsageEvents.Event.SCREEN_INTERACTIVE -> "screen_on"
                UsageEvents.Event.KEYGUARD_SHOWN -> "keyguard_shown"
                UsageEvents.Event.KEYGUARD_HIDDEN -> "keyguard_hidden"
                else -> null
            } ?: continue

            collected.add(
                mapOf(
                    "timestamp" to event.timeStamp,
                    "type" to type,
                    // ⚠️ 螢幕與鎖定畫面事件的 packageName 可能是 null 或
                    //    "android"，那不是錯誤——那些事件本來就不屬於某個 App。
                    "package_name" to (event.packageName ?: ""),
                )
            )
        }

        // queryEvents 已經是時間遞增，但那是文件沒有明講的實作行為，
        // 而下游的間隔分析完全建立在順序上，所以自己排一次。
        collected.sortBy { it["timestamp"] as Long }

        return if (collected.size > limit) {
            collected.subList(collected.size - limit, collected.size)
        } else {
            collected
        }
    }

    /**
     * 目前所有能處理 HOME intent 的 package（也就是桌面啟動器）。
     *
     * 不寫死 `com.sec.android.app.launcher` 之類的名字——各家 ROM 都不一樣，
     * 使用者也可能裝第三方桌面。問系統誰接得住 HOME intent 才可靠。
     */
    private fun launcherPackages(): Set<String> {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        return try {
            context.packageManager
                .queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
                .mapNotNull { it.activityInfo?.packageName }
                .toSet()
        } catch (_: Exception) {
            emptySet()
        }
    }
}
