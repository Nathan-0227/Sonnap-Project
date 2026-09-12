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
 * ## ⚠️ 已知限制（寫進報告的限制一節）
 *
 * - 用 setAndAllowWhileIdle（不精準鬧鐘）：省電模式下可能晚幾分鐘。精準鬧鐘在
 *   Android 12+ 要另外申請 SCHEDULE_EXACT_ALARM，對「睡前提醒」不值得。
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
        alarms.setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            triggerAtMillis,
            pendingIntent(triggerAtMillis, title, body),
        )
        return canPostNotifications()
    }

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
