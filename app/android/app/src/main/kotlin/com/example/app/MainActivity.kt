package com.example.app

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private lateinit var usageStatsService: UsageStatsService
    private lateinit var keyValueStore: KeyValueStore

    companion object {
        private const val CHANNEL = "sonnap/usage"
        private const val STORE_CHANNEL = "sonnap/store"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        usageStatsService = UsageStatsService(this)
        keyValueStore = KeyValueStore(this)
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
    }
}