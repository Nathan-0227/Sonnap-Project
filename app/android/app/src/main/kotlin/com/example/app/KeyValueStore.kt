package com.example.app

import android.content.Context

/**
 * 一個極小的鍵值儲存，包住 Android 的 SharedPreferences。
 *
 * ## 為什麼不裝 shared_preferences 套件
 *
 * 只需要存一個字串（user_id），而 `pubspec.yaml` 目前只有 lottie 與 intl。
 * 加一個套件會連帶動到 linux / macos / windows 三個平台的
 * generated_plugin_registrant——這個專案不出那三個平台，那些改動全是雜訊。
 *
 * 而 MethodChannel 的基礎建設**這個 App 已經有了**（sonnap/usage），
 * 再開一個 channel 是 25 行的事。同一個取捨也出現在
 * `ApiSleepRepository` 用 `dart:io` 而不裝 `package:http`、
 * `ai/llm_client.py` 用 `urllib` 而不裝 SDK。
 *
 * ## ⚠️ 這裡存的是憑證
 *
 * 後端是暱稱制免註冊，**user_id 本身就是憑證**——誰拿到就能讀寫那個人的
 * 資料。SharedPreferences 是 app-private 的（其他 App 讀不到，除非 root），
 * 對 D2「側載 APK、區網、十來個同學」的情境足夠。
 *
 * 但它**不是加密的**，而且會被裝置備份帶走。上架前要一併處理的技術債是
 * 「補認證」，不是「把這個檔案加密」——沒有認證的話，加密儲存也只是把
 * 同一把萬能鑰匙藏得深一點。
 */
class KeyValueStore(private val context: Context) {

    companion object {
        private const val PREFS_NAME = "sonnap_store"
    }

    private val prefs
        get() = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun getString(key: String): String? = prefs.getString(key, null)

    fun setString(key: String, value: String) {
        // commit() 而不是 apply()：呼叫端 await 完就會拿這個值去打 API，
        // apply() 是非同步寫入，理論上可以在中間被砍掉而遺失。
        // 寫的量極小，同步寫的代價可以忽略。
        prefs.edit().putString(key, value).commit()
    }

    fun remove(key: String) {
        prefs.edit().remove(key).commit()
    }
}
