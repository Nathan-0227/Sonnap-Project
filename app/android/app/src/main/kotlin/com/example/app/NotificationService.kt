package com.example.app

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

/**
 * 就寢提醒的原生端：在指定時刻發一則通知。
 *
 * ## ⚠️ 這裡只做「在這個時刻發這則通知」
 *
 * 目標就寢時間、提前幾分鐘、通知寫什麼——全部由 Dart
 * （`bedtime_reminder.dart`）決定好了才傳過來。門檻寫在這裡的話，
 * 每次調整都要重編 APK 才驗得了。`bedtime_reminder_test.dart` 有一條會掃
 * 這個檔案，確認沒有「提前幾分鐘」這種常數偷偷長出來。
 *
 * ## 為什麼不裝 flutter_local_notifications
 *
 * 它會動到 linux / macos / windows 三個平台的 generated plugin 檔，
 * 而這個專案不出那三個平台。用平台自己的 AlarmManager + Notification 就夠了，
 * 也不需要 androidx。
 *
 * ## ⚠️ 為什麼要精準鬧鐘（2026-09-13 實機看到的）
 *
 * 原本用 setAndAllowWhileIdle（不精準），註解寫「省電模式下可能晚幾分鐘」——那是錯的。
 * 實機（S24、Android 16）`dumpsys alarm` 顯示那則 23:00 的提醒帶著
 * `window=+1h`：系統有權拖到 **24:00** 才響，那時已經過了 23:30 的就寢時間，
 * 「睡前 30 分鐘提醒」整個失去意義，而且不會有任何錯誤訊息。
 *
 * 現在：拿得到精準鬧鐘就用 setExactAndAllowWhileIdle，拿不到才退回不精準的。
 * 權限用 USE_EXACT_ALARM（Android 13+ 安裝時自動給，受測者不用多按一步）。
 *
 * ⚠️ **上架 Google Play 前要拿掉 USE_EXACT_ALARM**：Play 只准鬧鐘／行事曆類 App 用。
 *    現在不構成代價，因為就寢守門（Accessibility）本來就讓這個 App 上不了 Play，
 *    要上架時兩個一起處理。
 *
 * ## ⚠️ 已知限制（寫進報告的限制一節）
 *
 * - 手機不給精準鬧鐘時（Android 12，或使用者在設定裡關掉）退回不精準的，
 *   可能晚到 1 小時。
 * - **重開機之後鬧鐘會消失**，要等使用者下次開 App 才會重排。沒有處理
 *   BOOT_COMPLETED，因為那需要多一個常駐的 receiver，而三星會殺背景。
 */
class NotificationService(private val context: Context) {

    companion object {
        const val CHANNEL_ID = "bedtime_reminder"
        const val NOTIFY_ID = 4201
        private const val REQUEST_CODE = 4201
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_TRIGGER_AT = "triggerAtMillis"
    }

    private val alarms: AlarmManager
        get() = context.getSystemService(AlarmManager::class.java)

    /** Android 8+ 一定要先有 channel，否則通知直接不出現、也沒有錯誤。 */
    fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Bedtime reminder",
                    NotificationManager.IMPORTANCE_DEFAULT,
                )
            )
        }
    }

    /** Android 13+ 要執行時權限；更早的版本預設允許。 */
    fun canPostNotifications(): Boolean =
        if (Build.VERSION.SDK_INT >= 33) {
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            true
        }

    /**
     * 在 triggerAtMillis 發一則通知，取代先前排的那一則。
     * 回傳「現在能不能發通知」——false 代表排了但使用者關了權限。
     */
    fun schedule(triggerAtMillis: Long, title: String, body: String): Boolean {
        ensureChannel()
        val operation = pendingIntent(triggerAtMillis, title, body)
        if (canScheduleExact()) {
            alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, operation)
        } else {
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, operation)
        }
        return canPostNotifications()
    }

    /**
     * 拿不拿得到精準鬧鐘。Android 12 以前不用權限；12 起要問系統。
     * ⚠️ 不能省：沒有權限時呼叫 setExactAndAllowWhileIdle 會丟 SecurityException，
     *    整個提醒就排不上了。
     */
    private fun canScheduleExact(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()

    /**
     * 取消已經排好的那一則。
     *
     * ⚠️ PendingIntent 相等的判準是 request code + Intent 的 action/component
     *    （**不看 extras**），所以這裡隨便帶什麼 extras 都取消得到同一則。
     */
    fun cancel() {
        alarms.cancel(pendingIntent(0L, "", ""))
    }

    private fun pendingIntent(triggerAtMillis: Long, title: String, body: String): PendingIntent {
        val intent = Intent(context, BedtimeReminderReceiver::class.java)
            .putExtra(EXTRA_TRIGGER_AT, triggerAtMillis)
            .putExtra(EXTRA_TITLE, title)
            .putExtra(EXTRA_BODY, body)
        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
