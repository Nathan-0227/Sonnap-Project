package com.example.app

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent

/**
 * 就寢守門的無障礙服務。
 *
 * 只聽「哪個視窗跑到前景」（typeWindowStateChanged），**不讀畫面內容**
 * （bedtime_guard_config.xml 的 canRetrieveWindowContent=false）。
 *
 * ## ⚠️ 行為照 Dart 的參考實作
 *
 * `bedtime_guard.dart` 的 GuardConfig.actionFor() 是這裡的規格：
 *   模式 off → 不動作；不在時間窗裡 → 不動作；不在名單上 → 不動作；
 *   block → 跳回桌面；reminder → 跳一個可以關掉的提醒（有冷卻時間）。
 * 這裡不自己訂任何門檻。
 *
 * ## ⚠️ Google Play 政策
 *
 * Accessibility API 只能用於協助身心障礙者，這類 App 上架會被駁回。
 * D2 走側載，限制寫在 docs/BEDTIME_GUARD.md。
 */
class BedtimeGuardService : AccessibilityService() {

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        // 自己不擋：提醒畫面本身就是 Sonnap 的，擋自己會無限迴圈。
        if (pkg == packageName) return

        val store = GuardConfigStore(this)
        val mode = store.mode()
        if (mode == "off") return
        val now = System.currentTimeMillis()
        if (!store.isActive(now)) return
        if (pkg !in store.packages()) return

        when (mode) {
            "block" -> performGlobalAction(GLOBAL_ACTION_HOME)
            "reminder" -> {
                if (!store.reminderDue(pkg, now)) return
                store.markReminded(pkg, now)
                startActivity(
                    Intent(this, GuardReminderActivity::class.java)
                        .putExtra(GuardReminderActivity.EXTRA_TITLE, store.title())
                        .putExtra(GuardReminderActivity.EXTRA_BODY, store.body())
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_HISTORY)
                )
            }
        }
    }

    override fun onInterrupt() {
        // 沒有要中斷的回饋（不發聲、不震動）。
    }
}
