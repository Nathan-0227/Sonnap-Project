package com.example.app

import android.app.Activity
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 鎖屏時跳出的全螢幕鬧鐘畫面：只有 Snooze 9 min 與 Dismiss（使用者決定）。
 * 用原生 View 畫，不啟動 Flutter——鬧鐘要在 App 沒開著、手機鎖著的時候也能馬上出現。
 */
class AlarmRingActivity : Activity() {

    companion object {
        const val ACTION_FINISH = "com.example.app.ALARM_RING_FINISH"
    }

    private val finisher = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = finish()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            getSystemService(KeyguardManager::class.java)?.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(64, 64, 64, 64)
            background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(Color.parseColor("#0F1530"), Color.parseColor("#2A2766")),
            )
        }
        root.addView(TextView(this).apply {
            text = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
            textSize = 72f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        })
        root.addView(TextView(this).apply {
            text = "Good morning"
            textSize = 20f
            setTextColor(Color.parseColor("#B3FFFFFF"))
            gravity = Gravity.CENTER
            setPadding(0, 8, 0, 96)
        })
        root.addView(pill("Snooze 9 min", "#33FFFFFF", Color.WHITE) {
            startService(Intent(this, AlarmRingService::class.java).setAction(AlarmRingService.ACTION_SNOOZE))
            finish()
        })
        root.addView(pill("Dismiss", "#B9A6FF", Color.parseColor("#1B2350")) {
            startService(Intent(this, AlarmRingService::class.java).setAction(AlarmRingService.ACTION_DISMISS))
            finish()
        })
        setContentView(root)

        val filter = IntentFilter(ACTION_FINISH)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(finisher, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(finisher, filter)
        }
    }

    private fun pill(label: String, bg: String, fg: Int, onTap: () -> Unit): Button =
        Button(this).apply {
            text = label
            isAllCaps = false
            textSize = 18f
            setTextColor(fg)
            background = GradientDrawable().apply {
                cornerRadius = 999f
                setColor(Color.parseColor(bg))
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                160,
            ).apply { setMargins(0, 24, 0, 0) }
            setOnClickListener { onTap() }
        }

    override fun onDestroy() {
        runCatching { unregisterReceiver(finisher) }
        super.onDestroy()
    }
}
