package com.example.app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings

/**
 * `sonnap/guard` channel 背後的三件事：權限開了沒、帶人去開、列出候選 App。
 *
 * ⚠️ 只回事實，不做判斷（哪些 App 該守、幾點守，都在 Dart）。
 */
class BedtimeGuardBridge(private val context: Context) {

    /**
     * 使用者有沒有在系統設定裡打開 Sonnap 的無障礙服務。
     *
     * 讀 Settings.Secure 而不是 AccessibilityManager 的清單：後者只列
     * **正在跑的**服務，剛打開、系統還沒 bind 的那一瞬間會回 false。
     */
    fun isEnabled(): Boolean {
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        val me = ComponentName(context, BedtimeGuardService::class.java)
        return enabled.split(':').any {
            ComponentName.unflattenFromString(it) == me
        }
    }

    /** 無障礙服務要不到，只能帶過去讓使用者自己開（同使用情況存取）。 */
    fun openSettings() {
        context.startActivity(
            Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    /**
     * 桌面上看得到的 App。
     *
     * ⚠️ 靠 manifest 的 <queries> LAUNCHER 宣告才看得到別家的 App（Android 11+），
     *    那一段本來就為了使用時間分析加過了。Sonnap 自己不列——擋自己沒有意義。
     */
    fun listApps(): List<Map<String, String>> {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(intent, 0)
            .map { it.activityInfo.packageName to it.loadLabel(pm).toString() }
            .filter { it.first != context.packageName }
            .distinctBy { it.first }
            .map { mapOf("package" to it.first, "label" to it.second) }
    }
}
