package com.example.app

import android.Manifest
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private lateinit var usageStatsService: UsageStatsService
    private lateinit var keyValueStore: KeyValueStore
    private lateinit var notificationService: NotificationService
    private val guardBridge by lazy { BedtimeGuardBridge(this) }

    companion object {
        private const val CHANNEL = "sonnap/usage"
        private const val STORE_CHANNEL = "sonnap/store"
        private const val NOTIFY_CHANNEL = "sonnap/notify"
        private const val GUARD_CHANNEL = "sonnap/guard"
        private const val NOTIFY_PERMISSION_REQUEST = 4202
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

    }
}
