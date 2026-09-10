package com.example.app

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * 鬧鐘響的時候發通知，並把同一則排到**隔天同一時刻**。
 *
 * ⚠️ 「隔天同一時刻」不是產品判斷，是機械式的重複：時刻本身是 Dart 算好
 *    傳進來的（目標就寢時間 − 提前量）。使用者改了目標或關掉提醒時，
 *    Dart 會重排或取消，取代這裡排的那一則。
 * ⚠️ 不重排的話只會響一次——使用者隔天沒開 App，就再也沒有提醒。
 */
class BedtimeReminderReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val service = NotificationService(context)
        val title = intent.getStringExtra(NotificationService.EXTRA_TITLE) ?: return
        val body = intent.getStringExtra(NotificationService.EXTRA_BODY) ?: ""
        val triggerAt = intent.getLongExtra(NotificationService.EXTRA_TRIGGER_AT, 0L)

        // 先排明天的，再發今天的：發通知那一步就算失敗（權限被關），
        // 提醒也不會因此整個停掉——使用者之後打開權限，明天就會出現。
        if (triggerAt > 0L) {
            service.schedule(triggerAt + 24L * 60L * 60L * 1000L, title, body)
        }

        if (!service.canPostNotifications()) return
        service.ensureChannel()

        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val contentIntent = launch?.let {
            PendingIntent.getActivity(context, 0, it, PendingIntent.FLAG_IMMUTABLE)
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, NotificationService.CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .apply { if (contentIntent != null) setContentIntent(contentIntent) }
            .build()

        context.getSystemService(NotificationManager::class.java)
            .notify(NotificationService.NOTIFY_ID, notification)
    }
}
