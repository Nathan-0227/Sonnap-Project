package com.example.app

import android.app.AppOpsManager
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

        val stats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            startTime,
            endTime
        )

        val packageManager = context.packageManager
        val launchers = launcherPackages()

        return stats
            .filter { it.totalTimeInForeground > 0 }
            .mapNotNull { usage ->

                val packageName = usage.packageName

                try {
                    val applicationInfo =
                        packageManager.getApplicationInfo(
                            packageName,
                            0
                        )

                    val appName =
                        packageManager.getApplicationLabel(
                            applicationInfo
                        ).toString()

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

                } catch (_: Exception) {
                    null
                }
            }
            .filter {
                (it["usage_minutes"] as Int) > 0
            }
            .sortedByDescending {
                it["usage_minutes"] as Int
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
