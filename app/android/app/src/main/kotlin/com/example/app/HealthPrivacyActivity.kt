package com.example.app

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Health Connect 授權畫面上「這個 App 怎麼使用你的資料」那一頁。
 *
 * ⚠️ 少了這一頁，Health Connect **拒絕顯示授權畫面**，而且不會有任何錯誤訊息——
 *    requestPermission 直接回「沒授權」。manifest 裡兩個入口都要宣告：
 *    Android 13 以下的 ACTION_SHOW_PERMISSIONS_RATIONALE，
 *    Android 14 以上的 VIEW_PERMISSION_USAGE（activity-alias）。
 */
class HealthPrivacyActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val pad = (24 * resources.displayMetrics.density).toInt()
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(pad, pad, pad, pad)
            setBackgroundColor(Color.parseColor("#081326"))
        }
        layout.addView(TextView(this).apply {
            text = getString(R.string.health_privacy_title)
            textSize = 22f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        })
        layout.addView(TextView(this).apply {
            text = getString(R.string.health_privacy_body)
            textSize = 15f
            setTextColor(Color.parseColor("#B3FFFFFF"))
            setPadding(0, pad / 2, 0, pad)
        })
        layout.addView(Button(this).apply {
            text = getString(R.string.health_privacy_close)
            setOnClickListener { finish() }
        })
        setContentView(layout)
    }
}
