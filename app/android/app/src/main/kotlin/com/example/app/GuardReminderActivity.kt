package com.example.app

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * 就寢守門「提醒模式」的全螢幕提醒。按一下或按返回就關掉，原本的 App 還在。
 *
 * ⚠️ 用平台自己的 Activity，不開 Flutter：服務在背景觸發時 Flutter 引擎
 *    根本沒在跑，為了一句提醒啟動整個引擎太慢，使用者早就滑走了。
 * ⚠️ 文字是 Dart 推過來的（GuardConfigStore），這裡不寫任何文案。
 */
class GuardReminderActivity : Activity() {

    companion object {
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
    }

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
            text = intent.getStringExtra(EXTRA_TITLE) ?: ""
            textSize = 26f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        })
        layout.addView(TextView(this).apply {
            text = intent.getStringExtra(EXTRA_BODY) ?: ""
            textSize = 16f
            setTextColor(Color.parseColor("#B3FFFFFF"))
            gravity = Gravity.CENTER
            setPadding(0, pad / 2, 0, pad)
        })
        layout.addView(Button(this).apply {
            text = "OK"
            setOnClickListener { finish() }
        })
        setContentView(layout)
    }
}
