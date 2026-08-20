package com.example.app

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
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
}