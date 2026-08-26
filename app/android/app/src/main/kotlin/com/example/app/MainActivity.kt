package com.example.app

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private lateinit var usageStatsService: UsageStatsService

    companion object {
        private const val CHANNEL = "sonnap/usage"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        usageStatsService = UsageStatsService(this)
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

                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}