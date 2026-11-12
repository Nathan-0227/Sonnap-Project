package com.example.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * 鬧鐘時間到：啟動前景服務（鈴聲＋震動＋全螢幕通知）。
 *
 * ⚠️ 不重排：鬧鐘只響這一次（只有按了 Start Sleep 才排，使用者決定）。
 *    也**不會**自動幫使用者按 Out of bed。
 */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val ring = Intent(context, AlarmRingService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(ring)
        } else {
            context.startService(ring)
        }
    }
}
