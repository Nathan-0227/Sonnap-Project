package com.example.app

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.health.connect.client.PermissionController
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * ## ⚠️ 必須是 FlutterFragmentActivity，不能是 FlutterActivity（2026-09-13 實機閃退）
 *
 * Health Connect 的授權 contract 產生的 Intent 是
 * `androidx.activity.result.contract.action.REQUEST_PERMISSIONS`——那**不是真的畫面**，
 * 是 AndroidX 的暗號，只有 ComponentActivity 的 registerForActivityResult 會攔下來
 * 轉成系統授權視窗。FlutterActivity 是最陽春的 Activity，拿去 startActivityForResult：
 *
 *   1. 丟 ActivityNotFoundException → Flutter 自動回 Dart 一次錯誤
 *   2. 系統又送 RESULT_CANCELED 回來 → 再回一次 → `Reply already submitted` → **整個 App 閃退**
 *
 * 單元測試與 `flutter build apk` 都抓不到（編得過、Dart 端測的是假的平台），
 * 只有實機按下「Connect and sync」才會發生。`health_connect_test.dart` 有一條在守。
 */
class MainActivity : FlutterFragmentActivity() {

    private lateinit var usageStatsService: UsageStatsService
    private lateinit var keyValueStore: KeyValueStore
    private lateinit var notificationService: NotificationService
    private val guardBridge by lazy { BedtimeGuardBridge(this) }
    private val healthService by lazy { HealthConnectService(this) }

    /** Health Connect 的 API 都是 suspend。Main：MethodChannel 的回覆要在主執行緒。 */
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    /** 等授權畫面回來的那一個呼叫。只准由 [finishHealthRequest] 回覆。 */
    private var pendingHealthResult: MethodChannel.Result? = null

    /** ⚠️ 要在 Activity 建構時就註冊（STARTED 之後註冊會丟例外），所以是欄位不是區域變數。 */
    private val healthPermissionLauncher = registerForActivityResult(
        PermissionController.createRequestPermissionResultContract(HealthConnectService.PROVIDER)
    ) { granted ->
        finishHealthRequest(granted.containsAll(HealthConnectService.PERMISSIONS))
    }

    companion object {
        private const val CHANNEL = "sonnap/usage"
        private const val STORE_CHANNEL = "sonnap/store"
        private const val NOTIFY_CHANNEL = "sonnap/notify"
        private const val GUARD_CHANNEL = "sonnap/guard"
        private const val HEALTH_CHANNEL = "sonnap/health"
        private const val NOTIFY_PERMISSION_REQUEST = 4202
    }

    /**
     * 回覆等授權的那一個呼叫，**而且只回一次**：先清掉再回，
     * 回覆途中有任何東西再進來，看到的都是 null。
     */
    private fun finishHealthRequest(granted: Boolean) {
        val pending = pendingHealthResult ?: return
        pendingHealthResult = null
        pending.success(granted)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        usageStatsService = UsageStatsService(this)
        keyValueStore = KeyValueStore(this)
        notificationService = NotificationService(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                "hasUsageAccess" -> {
                    result.success(
                        usageStatsService.hasUsageAccess()
                    )
                }

                "openUsageAccessSettings" -> {
                    usageStatsService.openUsageAccessSettings()
                    result.success(null)
                }

                "getUsage" -> {
                    val startTime =
                        call.argument<Long>("startTime")

                    val endTime =
                        call.argument<Long>("endTime")

                    if (startTime == null || endTime == null) {
                        result.error(
                            "INVALID_ARGUMENTS",
                            "startTime and endTime are required.",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    val usage =
                        usageStatsService.getUsage(
                            startTime,
                            endTime
                        )

                    result.success(usage)
                }

                "getInteractionEvents" -> {
                    val startTime =
                        call.argument<Long>("startTime")

                    val endTime =
                        call.argument<Long>("endTime")

                    if (startTime == null || endTime == null) {
                        result.error(
                            "INVALID_ARGUMENTS",
                            "startTime and endTime are required.",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    result.success(
                        usageStatsService.getInteractionEvents(
                            startTime,
                            endTime
                        )
                    )
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        // 鍵值儲存。分成另一個 channel 而不是塞進 sonnap/usage——
        // 兩者沒有任何關係，混在一起只會讓 when 分支越長越難讀。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            STORE_CHANNEL
        ).setMethodCallHandler { call, result ->

            val key = call.argument<String>("key")
            if (key == null) {
                result.error("INVALID_ARGUMENTS", "key is required.", null)
                return@setMethodCallHandler
            }

            when (call.method) {

                "getString" -> {
                    result.success(keyValueStore.getString(key))
                }

                "setString" -> {
                    val value = call.argument<String>("value")
                    if (value == null) {
                        result.error(
                            "INVALID_ARGUMENTS",
                            "value is required.",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    keyValueStore.setString(key, value)
                    result.success(null)
                }

                "remove" -> {
                    keyValueStore.remove(key)
                    result.success(null)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        // 就寢提醒。⚠️ 這裡只收「在哪個時刻、發什麼字」，提前幾分鐘由 Dart 決定
        // （bedtime_reminder.dart）。門檻寫在這裡的話，每次調整都要重編 APK。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFY_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "schedule" -> {
                    // Number 而不是 Long：標準 codec 把小的整數解成 Integer。
                    val at = call.argument<Number>("triggerAtMillis")?.toLong()
                    val title = call.argument<String>("title")
                    val body = call.argument<String>("body") ?: ""
                    if (at == null || title == null) {
                        result.error("INVALID_ARGUMENTS", "triggerAtMillis and title are required.", null)
                        return@setMethodCallHandler
                    }
                    result.success(notificationService.schedule(at, title, body))
                }
                "cancel" -> {
                    notificationService.cancel()
                    result.success(null)
                }
                "canPostNotifications" -> result.success(notificationService.canPostNotifications())
                "requestPermission" -> {
                    if (Build.VERSION.SDK_INT >= 33 && !notificationService.canPostNotifications()) {
                        requestPermissions(
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            NOTIFY_PERMISSION_REQUEST
                        )
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // 就寢守門。⚠️ 從幾點守到幾點、守哪些 App 都是 Dart 算好推過來的
        // （bedtime_guard.dart），這裡只存起來給無障礙服務讀。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            GUARD_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "configure" -> {
                    val mode = call.argument<String>("mode")
                    val start = call.argument<Number>("startMillis")?.toLong()
                    val end = call.argument<Number>("endMillis")?.toLong()
                    val packages = call.argument<List<String>>("packages") ?: emptyList()
                    val cooldown = call.argument<Number>("cooldownMillis")?.toLong() ?: 0L
                    if (mode == null || start == null || end == null) {
                        result.error("INVALID_ARGUMENTS", "mode, startMillis and endMillis are required.", null)
                        return@setMethodCallHandler
                    }
                    GuardConfigStore(this).save(
                        mode, start, end, packages,
                        call.argument<String>("title") ?: "",
                        call.argument<String>("body") ?: "",
                        cooldown,
                    )
                    result.success(null)
                }
                "isEnabled" -> result.success(guardBridge.isEnabled())
                "openSettings" -> {
                    guardBridge.openSettings()
                    result.success(null)
                }
                "listApps" -> result.success(guardBridge.listApps())
                else -> result.notImplemented()
            }
        }

        // Health Connect。⚠️ 往回讀幾天是 Dart 傳進來的（health_connect.dart）。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            HEALTH_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(healthService.status())
                "hasPermission" -> {
                    if (healthService.status() != "available") {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    scope.launch {
                        result.success(runCatching { healthService.hasPermission() }.getOrDefault(false))
                    }
                }
                "requestPermission" -> {
                    if (healthService.status() != "available") {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    // 上一個還沒回來就又按了一次：先把舊的結掉，免得它永遠等不到。
                    finishHealthRequest(false)
                    pendingHealthResult = result
                    try {
                        healthPermissionLauncher.launch(HealthConnectService.PERMISSIONS)
                    } catch (e: Exception) {
                        // ⚠️ 自己接住並清掉 pending。讓例外跑出去的話，Flutter 會替我們回一次錯誤，
                        //    而 pending 還握著同一個 result——之後再回就是閃退的那條路。
                        pendingHealthResult = null
                        result.error("HEALTH_PERMISSION_FAILED", e.message, null)
                    }
                }
                "openProviderStore" -> {
                    healthService.openProviderStore()
                    result.success(null)
                }
                "readSleepSessions" -> {
                    val start = call.argument<Number>("startMillis")?.toLong()
                    val end = call.argument<Number>("endMillis")?.toLong()
                    if (start == null || end == null) {
                        result.error("INVALID_ARGUMENTS", "startMillis and endMillis are required.", null)
                        return@setMethodCallHandler
                    }
                    scope.launch {
                        try {
                            result.success(healthService.readSleepSessions(start, end))
                        } catch (e: Exception) {
                            result.error("HEALTH_READ_FAILED", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
