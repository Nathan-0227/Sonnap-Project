/// 攝影機量到的兩個量：**臥床時間**與**入睡潛伏期**。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 這兩個量的可信度完全不同，畫面上必須分得開
/// ═══════════════════════════════════════════════════════════════════
///
/// | 量 | 來源 | 意思 |
/// |---|---|---|
/// | 臥床起訖 | **自述** | 開始／結束錄影的時刻，不是攝影機看到人躺下 |
/// | 入睡時刻 | **偵測** | 動作密度的轉折，對過生理效標的只有 2 晚 |
///
/// 等同臨床睡眠日誌（sleep diary）的作法——按一個鍵比隔天回想準確，
/// 但它終究是自述。寫進報告或畫面都要標明，不能寫成「攝影機偵測到」。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 這裡沒有分數，也不要加
/// ═══════════════════════════════════════════════════════════════════
///
/// `Research-Background/攝影機分數.md` 的結論是「現行有效的攝影機計分項目：
/// 0 項」，所以後端的 `camera` 區塊刻意沒有 score／quality 欄位，這裡也
/// 不從這些量推算任何分數。要計分得先過那份文件 F 節的關卡（設計紅線 2）。
///
/// ⚠️ **也不要在這裡算「睡眠效率」**：效率的分子要扣掉夜間清醒（WASO），
/// 而 WASO 量不到。後端刻意回 null，Dart 端補一個就是憑空生出一個數字。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'sleep_repository.dart';
import 'user_identity.dart';

/// 為什麼要有這個介面：測試要注入假的資料，不能依賴真的 HTTP。
/// 與 `SleepRepository` 同一個手法。
abstract class CameraInsightsSource {
  Future<CameraInsightsResult> load();
}

enum CameraInsightsStatus {
  /// 拿到了（可能是空的，見 [CameraInsightsResult.nights]）
  ok,

  /// 這支 build 沒有 `--dart-define=SONNAP_USER_ID`，也還沒建帳號
  noUser,

  /// 這支 build 沒有 `--dart-define=SONNAP_API_BASE`
  noBackend,

  /// 連不到、逾時、後端回錯
  failed,
}

/// 一晚的攝影機資料。欄名與後端 `/insights` 的 `camera.history` 一致。
@immutable
class CameraNight {
  /// 起床日 YYYY-MM-DD
  final String date;

  /// ⚠️ 自述（開始／結束錄影），不是偵測到的。
  final String? bedStartAt;
  final String? bedEndAt;
  final double? timeInBedMinutes;

  /// ⚠️ 低於偵測下限時這兩個是 **null，不是 0**。
  /// 報 0 會被讀成「躺下就睡著」，而真值可能是 5 分鐘。
  final String? sleepOnsetAt;
  final double? sleepOnsetLatencyMinutes;

  /// 真時：潛伏期比偵測器分辨得出來的還短 → 只能說「≤ [floorMinutes] 分」。
  final bool belowFloor;
  final double? floorMinutes;

  final int? eventsTotal;
  final double? eventsPerHour;

  /// 哪個量來自哪裡。畫面上的「Self-reported／Detected」就是照這個標的。
  final String? bedTimesProvenance;
  final String? sleepOnsetProvenance;

  const CameraNight({
    required this.date,
    this.bedStartAt,
    this.bedEndAt,
    this.timeInBedMinutes,
    this.sleepOnsetAt,
    this.sleepOnsetLatencyMinutes,
    this.belowFloor = false,
    this.floorMinutes,
    this.eventsTotal,
    this.eventsPerHour,
    this.bedTimesProvenance,
    this.sleepOnsetProvenance,
  });

  factory CameraNight.fromJson(Map<String, dynamic> json) {
    double? num_(Object? v) => (v as num?)?.toDouble();
    return CameraNight(
      date: (json['date'] as String?) ?? '',
      bedStartAt: json['bed_start_at'] as String?,
      bedEndAt: json['bed_end_at'] as String?,
      timeInBedMinutes: num_(json['time_in_bed_minutes']),
      sleepOnsetAt: json['sleep_onset_at'] as String?,
      sleepOnsetLatencyMinutes: num_(json['sleep_onset_latency_minutes']),
      belowFloor: json['sleep_onset_below_floor'] == true,
      floorMinutes: num_(json['sleep_onset_floor_minutes']),
      eventsTotal: (json['events_total'] as num?)?.toInt(),
      eventsPerHour: num_(json['events_per_hour']),
      bedTimesProvenance: json['bed_times_provenance'] as String?,
      sleepOnsetProvenance: json['sleep_onset_provenance'] as String?,
    );
  }

  /// 臥床時間是**自述**嗎。後端的 provenance 說了就照它說的。
  bool get bedTimesSelfReported =>
      (bedTimesProvenance ?? '').startsWith('SELF_REPORTED');

  /// 入睡時刻是**偵測**的嗎。
  bool get onsetDetected => (sleepOnsetProvenance ?? '').startsWith('DETECTED');
}

@immutable
class CameraInsightsResult {
  final CameraInsightsStatus status;

  /// 由舊到新（後端就是這個順序）。
  final List<CameraNight> nights;

  /// 後端隨身帶的限制說明。**不要在 Dart 重寫一份**——兩份會漂移。
  final String? note;
  final String? floorNote;

  final String? error;

  const CameraInsightsResult(
    this.status, {
    this.nights = const [],
    this.note,
    this.floorNote,
    this.error,
  });

  /// 最近一晚。沒有資料時回 null（**不要回一個全是 0 的假夜晚**）。
  CameraNight? get latest => nights.isEmpty ? null : nights.last;
}

/// 打 `GET /insights` 取 `camera` 區塊。
class CameraInsightsService implements CameraInsightsSource {
  final String baseUrl;
  final UserIdentity identity;

  /// 與 `ApiSleepRepository` 一樣短：這是「畫面等多久才放棄」，
  /// 後端沒開是 demo 的常態，不能讓它卡住整頁。
  final Duration timeout;

  /// 要幾晚。畫面目前只用最近一晚，多取是為了之後畫趨勢。
  final int days;

  const CameraInsightsService({
    required this.baseUrl,
    required this.identity,
    this.timeout = const Duration(seconds: 3),
    this.days = 30,
  });

  @override
  Future<CameraInsightsResult> load() async {
    if (baseUrl.trim().isEmpty) {
      return const CameraInsightsResult(CameraInsightsStatus.noBackend);
    }
    final userId = await identity.currentUserId();
    if (userId == null) {
      return const CameraInsightsResult(CameraInsightsStatus.noUser);
    }

    final uri = Uri.parse('$baseUrl/insights').replace(queryParameters: {
      'user_id': userId,
      'days': '$days',
    });
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        // ⚠️ 不要把 uri 印出來——它的 query 帶著 user_id（憑證）。
        return CameraInsightsResult(
          CameraInsightsStatus.failed,
          error: 'GET /insights returned ${response.statusCode}',
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return const CameraInsightsResult(
          CameraInsightsStatus.failed,
          error: '/insights 回傳的根節點不是物件',
        );
      }
      // camera 是 null = 這個使用者沒有攝影機資料。那是正常狀態，不是錯誤。
      final camera = decoded['camera'];
      if (camera is! Map<String, dynamic>) {
        return const CameraInsightsResult(CameraInsightsStatus.ok);
      }
      final history = (camera['history'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(CameraNight.fromJson)
          .toList();
      debugPrint('CameraInsights: ok ${history.length} nights');
      return CameraInsightsResult(
        CameraInsightsStatus.ok,
        nights: history,
        note: camera['note'] as String?,
        floorNote: camera['floor_note'] as String?,
      );
    } catch (error) {
      debugPrint('CameraInsights: failed - $error');
      return CameraInsightsResult(
        CameraInsightsStatus.failed,
        error: error.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }
}

/// 依建置參數決定要不要啟用。沒給 `SONNAP_API_BASE` 就回 null，
/// 整張卡片不存在——行為與加這一層之前完全相同，與
/// `buildNightlyUploader()` 同一個原則。
CameraInsightsService? buildCameraInsights({
  String? baseUrlOverride,
  String? userIdOverride,
}) {
  final baseUrl = (baseUrlOverride ?? ApiSleepRepository.configuredBaseUrl).trim();
  if (baseUrl.isEmpty) return null;
  return CameraInsightsService(
    baseUrl: baseUrl,
    identity: buildUserIdentity(userIdOverride: userIdOverride),
  );
}
