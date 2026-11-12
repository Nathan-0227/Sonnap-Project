package com.example.app

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings

/**
 * 鬧鐘的原生端（2026-11-12）。走 `sonnap/alarm` channel，另一頭是 `alarm.dart`。
 *
 * ## ⚠️ 這裡只做「在這個時刻響」
 *
 * 幾點響、要不要排（只有按了 Start Sleep 才排、超過 14 小時不排）全部由 Dart 決定。
 * 判斷寫在這裡的話，每次調整都要重編 APK 才驗得了——與就寢提醒同一條紀律。
 *
 * ## 為什麼用 setAlarmClock
 *
 * 它是 Android 給鬧鐘 App 的那一個：準時、省電模式（Doze）照樣響、狀態列會出現鬧鐘圖示，
 * 而且鬧鐘響時允許從背景啟動前景服務（播鈴聲要用）。權限沿用就寢提醒的
 * USE_EXACT_ALARM（Android 13+ 安裝時自動給）。
 *
 * ## ⚠️ 已知限制（使用者決定不加「不保證會響」的提示）
 *
 * - 重開機之後鬧鐘會消失（沒有處理 BOOT_COMPLETED，理由同就寢提醒）。
 * - Android 14+ 若「全螢幕通知」被關掉，鎖屏時不會跳出全螢幕畫面，
 *   但鈴聲與震動照樣有（由前景服務負責）。
 */
class AlarmService(private val context: Context) {

    companion object {
        const val REQUEST_CODE = 5101
        const val SNOOZE_MINUTES = 9L
    }

    private val alarms: AlarmManager
        get() = context.getSystemService(AlarmManager::class.java)

    fun schedule(triggerAtMillis: Long) {
        val operation = receiverIntent()
        // 點狀態列的鬧鐘圖示時打開 App。
        val show = context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            PendingIntent.getActivity(context, REQUEST_CODE, it, PendingIntent.FLAG_IMMUTABLE)
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()) {
            alarms.setAlarmClock(AlarmManager.AlarmClockInfo(triggerAtMillis, show), operation)
        } else {
            // 拿不到精準鬧鐘時退回不精準的（Android 12 使用者手動關掉才會發生）。
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, operation)
        }
    }

    fun cancel() {
        alarms.cancel(receiverIntent())
        // 正在響的話也停掉。
        context.stopService(Intent(context, AlarmRingService::class.java))
    }

    fun snooze() {
        context.stopService(Intent(context, AlarmRingService::class.java))
        schedule(System.currentTimeMillis() + SNOOZE_MINUTES * 60_000L)
    }

    fun canPostNotifications(): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun canUseFullScreen(): Boolean =
        Build.VERSION.SDK_INT < 34 ||
            context.getSystemService(NotificationManager::class.java).canUseFullScreenIntent()

    /** 通知與全螢幕通知都允許了沒。 */
    fun canRing(): Boolean = canPostNotifications() && canUseFullScreen()

    /** 帶到該開的那一頁：通知沒開就到通知設定；通知開了但全螢幕沒開就到全螢幕那頁。 */
    fun openSettings() {
        val intent = if (!canPostNotifications() || Build.VERSION.SDK_INT < 34) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        } else {
            Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
                .setData(Uri.parse("package:${context.packageName}"))
        }
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /**
     * ⚠️ PendingIntent 相等的判準是 request code + Intent 的 action/component（不看 extras），
     *    所以 schedule 與 cancel 拿到的是同一個，取消得到。
     */
    private fun receiverIntent(): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            Intent(context, AlarmReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
}
