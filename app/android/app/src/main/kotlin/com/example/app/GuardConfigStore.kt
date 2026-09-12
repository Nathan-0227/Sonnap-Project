package com.example.app

import android.content.Context

/**
 * 就寢守門的設定，Dart 推過來、無障礙服務讀。
 *
 * ## ⚠️ 這裡沒有任何產品判斷
 *
 * 從幾點守到幾點、守哪些 App、哪一種模式、提醒多久不重複——全部是 Dart
 * （bedtime_guard.dart）算好推過來的。這裡唯一自己做的事是「時間窗過了就
 * 往後推一天」：那是機械式的重複（跟就寢提醒的鬧鐘一樣），窗的長度與位置
 * 仍然是 Dart 算的。使用者改了目標時間，Dart 會推一個新的窗蓋掉。
 */
class GuardConfigStore(context: Context) {

    companion object {
        private const val PREFS = "sonnap_guard"
        private const val DAY_MS = 24L * 60L * 60L * 1000L
    }

    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun save(
        mode: String,
        startMillis: Long,
        endMillis: Long,
        packages: List<String>,
        title: String,
        body: String,
        cooldownMillis: Long,
    ) {
        prefs.edit()
            .putString("mode", mode)
            .putLong("start", startMillis)
            .putLong("end", endMillis)
            .putStringSet("packages", packages.toSet())
            .putString("title", title)
            .putString("body", body)
            .putLong("cooldown", cooldownMillis)
            .commit()
    }

    fun mode(): String = prefs.getString("mode", "off") ?: "off"

    fun packages(): Set<String> = prefs.getStringSet("packages", emptySet()) ?: emptySet()

    fun title(): String = prefs.getString("title", "") ?: ""

    fun body(): String = prefs.getString("body", "") ?: ""

    /** 現在在不在守的時間窗裡。窗過了就往後推一天（見類別說明）。 */
    fun isActive(now: Long): Boolean {
        var start = prefs.getLong("start", 0L)
        var end = prefs.getLong("end", 0L)
        if (end <= start) return false
        while (end <= now) {
            start += DAY_MS
            end += DAY_MS
        }
        return now >= start && now < end
    }

    /** 提醒模式下，這個 App 距離上次提醒夠久了嗎。 */
    fun reminderDue(pkg: String, now: Long): Boolean {
        val last = prefs.getLong("reminded:$pkg", 0L)
        return now - last >= prefs.getLong("cooldown", 0L)
    }

    fun markReminded(pkg: String, now: Long) {
        prefs.edit().putLong("reminded:$pkg", now).apply()
    }
}
