package com.example.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/**
 * 鬧鐘正在響：播鈴聲（USAGE_ALARM，勿擾模式下也會響）、震動、
 * 發一則帶全螢幕畫面的通知（鎖屏時直接跳出 [AlarmRingActivity]）。
 *
 * 鈴聲是程式合成的原創音檔（res/raw/sonnap_alarm.wav），音量 30 秒內由小到大。
 * 響 10 分鐘沒人理就自己停，免得整個早上一直響。
 */
class AlarmRingService : Service() {

    companion object {
        const val CHANNEL_ID = "sonnap_alarm"
        const val NOTIFY_ID = 5102
        const val ACTION_DISMISS = "com.example.app.ALARM_DISMISS"
        const val ACTION_SNOOZE = "com.example.app.ALARM_SNOOZE"
        private const val RAMP_MS = 30_000L
        private const val AUTO_STOP_MS = 10 * 60_000L
    }

    private var player: MediaPlayer? = null
    private val handler = Handler(Looper.getMainLooper())
    private var rampStart = 0L

    private val ramp = object : Runnable {
        override fun run() {
            val p = player ?: return
            val f = ((System.currentTimeMillis() - rampStart).toFloat() / RAMP_MS).coerceIn(0.15f, 1f)
            p.setVolume(f, f)
            if (f < 1f) handler.postDelayed(this, 500)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_DISMISS -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_SNOOZE -> {
                AlarmService(this).snooze()
                return START_NOT_STICKY
            }
        }
        startInForeground()
        startSound()
        startVibration()
        handler.postDelayed({ stopSelf() }, AUTO_STOP_MS)
        return START_NOT_STICKY
    }

    private fun startInForeground() {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Alarm", NotificationManager.IMPORTANCE_HIGH)
            channel.setSound(null, null) // 鈴聲由 MediaPlayer 播，通知本身不出聲
            channel.enableVibration(false)
            manager.createNotificationChannel(channel)
        }
        val full = PendingIntent.getActivity(
            this, 0,
            Intent(this, AlarmRingActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Good morning")
            .setContentText("Your Sonnap alarm")
            .setCategory(Notification.CATEGORY_ALARM)
            .setOngoing(true)
            .setFullScreenIntent(full, true)
            .setContentIntent(full)
            .addAction(Notification.Action.Builder(null, "Snooze 9 min", actionIntent(ACTION_SNOOZE, 1)).build())
            .addAction(Notification.Action.Builder(null, "Dismiss", actionIntent(ACTION_DISMISS, 2)).build())
            .build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIFY_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIFY_ID, notification)
        }
    }

    private fun actionIntent(action: String, code: Int): PendingIntent =
        PendingIntent.getService(
            this, code,
            Intent(this, AlarmRingService::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun startSound() {
        if (player != null) return
        val afd = resources.openRawResourceFd(R.raw.sonnap_alarm) ?: return
        player = MediaPlayer().apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            afd.close()
            isLooping = true
            setVolume(0.15f, 0.15f)
            prepare()
            start()
        }
        rampStart = System.currentTimeMillis()
        handler.post(ramp)
    }

    private fun vibrator(): Vibrator =
        if (Build.VERSION.SDK_INT >= 31) {
            getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }

    private fun startVibration() {
        val pattern = longArrayOf(0, 600, 800)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator().vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vibrator().vibrate(pattern, 0)
        }
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        player?.run {
            runCatching { stop() }
            release()
        }
        player = null
        vibrator().cancel()
        getSystemService(NotificationManager::class.java).cancel(NOTIFY_ID)
        // 告訴全螢幕畫面：鬧鐘停了，可以關掉。
        sendBroadcast(Intent(AlarmRingActivity.ACTION_FINISH).setPackage(packageName))
        super.onDestroy()
    }
}
