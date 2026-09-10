package com.example.app

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/**
 * Health Connect（B8）：讀睡眠 session，原封不動交給 Dart。
 *
 * ## ⚠️ 只回事實
 *
 * 往回看幾天、要送哪一段、怎麼算分——都不在這裡。讀的時間範圍是 Dart 傳進來的
 * （health_connect.dart 的 kHealthLookback），分數在後端的
 * wearable/healthconnect_adapter.py 用既有評分器算。
 *
 * ## ⚠️ 只要睡眠這一個權限
 *
 * 多要的權限會一起出現在授權畫面上，受測者看到「心率、步數、體重」很可能整組拒絕。
 */
class HealthConnectService(private val context: Context) {

    companion object {
        const val PROVIDER = "com.google.android.apps.healthdata"
        val PERMISSIONS = setOf(HealthPermission.getReadPermission(SleepSessionRecord::class))
    }

    private val contract = PermissionController.createRequestPermissionResultContract(PROVIDER)

    fun status(): String = when (HealthConnectClient.getSdkStatus(context, PROVIDER)) {
        HealthConnectClient.SDK_AVAILABLE -> "available"
        HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> "needs_update"
        else -> "unavailable"
    }

    suspend fun hasPermission(): Boolean =
        HealthConnectClient.getOrCreate(context).permissionController
            .getGrantedPermissions().containsAll(PERMISSIONS)

    fun permissionIntent(): Intent = contract.createIntent(context, PERMISSIONS)

    fun permissionGranted(resultCode: Int, data: Intent?): Boolean =
        contract.parseResult(resultCode, data).containsAll(PERMISSIONS)

    /** 帶到 Play 商店。沒有 Play 商店的手機退回網頁。 */
    fun openProviderStore() {
        val market = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("market://details?id=$PROVIDER&url=healthconnect%3A%2F%2Fonboarding")
        ).setPackage("com.android.vending").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(market)
        } catch (e: ActivityNotFoundException) {
            context.startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=$PROVIDER"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }

    /**
     * [startMillis, endMillis) 之間的睡眠 session。
     *
     * 格式照 wearable/healthconnect_adapter.py 的 parse_session()：
     * startTime / endTime / stages[{startTime, endTime, stage}]，stage 是
     * Health Connect 原生的整數代碼（adapter 認得 0–7）。
     */
    suspend fun readSleepSessions(startMillis: Long, endMillis: Long): List<Map<String, Any?>> {
        val response = HealthConnectClient.getOrCreate(context).readRecords(
            ReadRecordsRequest(
                recordType = SleepSessionRecord::class,
                timeRangeFilter = TimeRangeFilter.between(
                    Instant.ofEpochMilli(startMillis),
                    Instant.ofEpochMilli(endMillis)
                ),
            )
        )
        return response.records.map { r ->
            mapOf(
                "startTime" to iso(r.startTime, r.startZoneOffset),
                "endTime" to iso(r.endTime, r.endZoneOffset),
                // 分期沒有自己的時區，一律用 session 開始時的偏移。
                "stages" to r.stages.map { s ->
                    mapOf(
                        "startTime" to iso(s.startTime, r.startZoneOffset),
                        "endTime" to iso(s.endTime, r.startZoneOffset),
                        "stage" to s.stage,
                    )
                },
                "origin" to r.metadata.dataOrigin.packageName,
            )
        }
    }

    /**
     * 帶偏移量的 ISO8601，秒數一定寫出來（2026-09-10T23:10:00+08:00）。
     *
     * ⚠️ 偏移量要用**記錄當下的**（Health Connect 有存），不是手機現在的時區：
     *    專案規範是時間照字串上的牆鐘時間解讀（見 wall_clock.dart），
     *    換時區看同一晚不該變成另一個時刻。
     */
    private fun iso(t: Instant, offset: ZoneOffset?): String {
        val whole = Instant.ofEpochSecond(t.epochSecond)
        val zone = offset ?: ZoneId.systemDefault().rules.getOffset(whole)
        return DateTimeFormatter.ISO_OFFSET_DATE_TIME.format(whole.atOffset(zone))
    }
}
