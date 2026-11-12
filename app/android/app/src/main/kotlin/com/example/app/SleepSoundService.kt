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
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import java.util.Random
import kotlin.math.PI
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * 助眠聲音（2026-11-12 使用者定案）：前景服務，螢幕鎖住也繼續播。
 *
 * 三種聲音都是**即時合成**的（沒有音檔、沒有版權問題、循環不會有接縫）。
 * 播多久、淡出多久、哪一種都由 Dart 決定（sleep_sounds.dart），這裡只照做。
 *
 * - 開頭 3 秒淡入、最後 [fadeMillis] 淡出，然後自己停。
 * - 要求音訊焦點：Spotify 之類正在播的會暫停（使用者定）；別人搶走焦點（例如另一個
 *   App 開始放音樂）就停；短暫被搶（來電）先靜音，還回來再出聲。
 * - 鬧鐘響的時候 [AlarmRingService] 會叫 [stop]。
 */
class SleepSoundService : Service() {

    companion object {
        const val CHANNEL_ID = "sonnap_sounds"
        const val NOTIFY_ID = 5201
        const val ACTION_PLAY = "com.example.app.SOUNDS_PLAY"
        const val ACTION_STOP = "com.example.app.SOUNDS_STOP"
        const val EXTRA_SOUND = "sound"
        const val EXTRA_LENGTH = "lengthMillis"
        const val EXTRA_FADE = "fadeMillis"
        private const val RATE = 22050
        private const val FADE_IN_MS = 3_000L

        /** 正在播的話，幾點（epoch ms）會停；沒在播是 null。 */
        @Volatile
        var endsAt: Long? = null
            private set

        fun play(context: Context, sound: String, lengthMillis: Long, fadeMillis: Long) {
            val i = Intent(context, SleepSoundService::class.java)
                .setAction(ACTION_PLAY)
                .putExtra(EXTRA_SOUND, sound)
                .putExtra(EXTRA_LENGTH, lengthMillis)
                .putExtra(EXTRA_FADE, fadeMillis)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(i)
            } else {
                context.startService(i)
            }
        }

        /** stopService 在任何時候都叫得動（不受背景啟動限制）。 */
        fun stop(context: Context) {
            context.stopService(Intent(context, SleepSoundService::class.java))
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var worker: Thread? = null
    /** 每換一次聲音就 +1；執行緒只在自己那一代還有效時繼續寫。 */
    @Volatile private var generation = 0
    @Volatile private var muted = false
    private var startedAt = 0L
    private var fadeMillis = 60_000L
    private var sound = "rain"
    private var focusRequest: AudioFocusRequest? = null
    private var wakeLock: PowerManager.WakeLock? = null

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> handler.post { stopSelf() }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> muted = true
            AudioManager.AUDIOFOCUS_GAIN -> muted = false
        }
    }

    private val tick = object : Runnable {
        override fun run() {
            notifyRemaining()
            handler.postDelayed(this, 30_000)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action != ACTION_PLAY) {
            stopSelf()
            return START_NOT_STICKY
        }
        sound = intent.getStringExtra(EXTRA_SOUND) ?: "rain"
        val length = intent.getLongExtra(EXTRA_LENGTH, 30 * 60_000L)
        fadeMillis = intent.getLongExtra(EXTRA_FADE, 60_000L).coerceAtLeast(1L)
        startedAt = System.currentTimeMillis()
        endsAt = startedAt + length

        startInForeground()
        requestFocus()
        holdWakeLock(length + 60_000L)
        startWorker()
        handler.removeCallbacks(tick)
        handler.post(tick)
        return START_NOT_STICKY
    }

    private fun label(): String = when (sound) {
        "ocean" -> "Ocean"
        "brown" -> "Brown noise"
        else -> "Rain"
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Sleep sounds", NotificationManager.IMPORTANCE_LOW)
            channel.setSound(null, null)
            manager.createNotificationChannel(channel)
        }
        val open = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE)
        }
        val stop = PendingIntent.getService(
            this, 1,
            Intent(this, SleepSoundService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val left = ((endsAt ?: 0L) - System.currentTimeMillis()).coerceAtLeast(0L)
        val minutes = (left + 59_999L) / 60_000L
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Sleep sounds")
            .setContentText("${label()} · $minutes min left")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
            .addAction(Notification.Action.Builder(null, "Stop", stop).build())
            .build()
    }

    private fun startInForeground() {
        val n = buildNotification()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIFY_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIFY_ID, n)
        }
    }

    private fun notifyRemaining() {
        if (endsAt == null) return
        getSystemService(NotificationManager::class.java).notify(NOTIFY_ID, buildNotification())
    }

    private fun attributes(): AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        .build()

    private fun requestFocus() {
        if (focusRequest != null) return
        val audio = getSystemService(AudioManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attributes())
                .setOnAudioFocusChangeListener(focusListener, handler)
                .build()
            audio.requestAudioFocus(req)
            focusRequest = req
        } else {
            @Suppress("DEPRECATION")
            audio.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
        }
    }

    private fun abandonFocus() {
        val audio = getSystemService(AudioManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audio.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            audio.abandonAudioFocus(focusListener)
        }
        focusRequest = null
    }

    private fun holdWakeLock(timeout: Long) {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "sonnap:sleep-sounds")
            .apply { acquire(timeout) }
    }

    /** 換聲音或重播時，舊的執行緒先停、再開新的。 */
    private fun startWorker() {
        val mine = ++generation
        worker?.join(500)
        val kind = sound
        worker = Thread({ synthLoop(kind, mine) }, "sleep-sounds").apply { start() }
    }

    private fun synthLoop(kind: String, mine: Int) {
        val minBuf = AudioTrack.getMinBufferSize(
            RATE, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT,
        )
        val track = AudioTrack.Builder()
            .setAudioAttributes(attributes())
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(RATE)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(max(minBuf, 8192))
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        val gen = Generator(kind)
        val buf = ShortArray(2048)
        track.play()
        var gain = 0f
        try {
            while (generation == mine) {
                val now = System.currentTimeMillis()
                val end = endsAt ?: break
                val left = end - now
                if (left <= 0) break
                val fadeIn = min(1f, (now - startedAt).toFloat() / FADE_IN_MS)
                val fadeOut = min(1f, left.toFloat() / fadeMillis)
                val target = if (muted) 0f else fadeIn * fadeOut
                // 一個 buffer（約 0.09 秒）內線性過渡，音量變化不會有喀聲。
                val step = (target - gain) / buf.size
                for (i in buf.indices) {
                    gain += step
                    val v = gen.next() * 0.8f * gain
                    buf[i] = (v.coerceIn(-1f, 1f) * 32767f).toInt().toShort()
                }
                track.write(buf, 0, buf.size)
            }
        } finally {
            runCatching { track.stop() }
            track.release()
        }
        // 自然播完（不是被換掉）就收掉服務。
        if (generation == mine) handler.post { stopSelf() }
    }

    override fun onDestroy() {
        generation++
        endsAt = null
        handler.removeCallbacksAndMessages(null)
        abandonFocus()
        wakeLock?.let { if (it.isHeld) it.release() }
        getSystemService(NotificationManager::class.java).cancel(NOTIFY_ID)
        super.onDestroy()
    }

    /**
     * 三種聲音的合成。音量已在 Python 試算過（RMS 約 0.16～0.20），彼此差不多大。
     * - brown：白噪音的漏積分，低沉。
     * - rain：粉紅噪音當底，加上隨機的短促雨滴，再柔化高頻。
     * - ocean：低沉噪音乘上約 9 秒一個週期的浪的起伏，浪頭多一點沙沙聲。
     */
    private class Generator(private val kind: String) {
        private val rnd = Random()
        private var b = 0f
        private var b0 = 0f
        private var b1 = 0f
        private var b2 = 0f
        private var y = 0f
        private var drop = 0f
        private var t = 0f
        private var period = 9f

        fun next(): Float {
            val x = rnd.nextFloat() * 2f - 1f
            b = (b + 0.02f * x) / 1.02f
            b0 = 0.99765f * b0 + x * 0.0990460f
            b1 = 0.96300f * b1 + x * 0.2965164f
            b2 = 0.57000f * b2 + x * 1.0526913f
            val pink = b0 + b1 + b2 + x * 0.1848f
            return when (kind) {
                "brown" -> b * 3.5f
                "ocean" -> {
                    t += 1f / RATE
                    if (t >= period) {
                        t -= period
                        period = 7f + rnd.nextFloat() * 4f // 每道浪長短不一
                    }
                    val s = sin(PI * t / period).toFloat()
                    val env = 0.12f + 0.88f * s * s
                    b * 3.2f * env + pink * 0.06f * env * env
                }
                else -> {
                    if (rnd.nextFloat() < 40f / RATE) drop += 0.2f + rnd.nextFloat() * 0.6f
                    drop *= 0.993f
                    val s = pink * 0.12f + drop * (rnd.nextFloat() * 2f - 1f) * 0.5f
                    y += 0.55f * (s - y)
                    y
                }
            }
        }
    }
}
