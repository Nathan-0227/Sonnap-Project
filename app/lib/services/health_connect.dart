import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/wall_clock.dart';
import 'key_value_store.dart';
import 'user_identity.dart';

/// Health Connect（B8）：把手錶／手環寫進 Health Connect 的睡眠 session
/// 送到 `POST /wearable`，由後端用**既有的評分器**打分。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ Dart 不算分，只挑「要送哪幾段」
/// ═══════════════════════════════════════════════════════════════════
///
/// 分數、效率、WASO 全部在 `wearable/healthconnect_adapter.py` 算，
/// 走的是 Garmin 那一套文獻門檻。這裡只做兩件事：
///   1. 挑出要送的 session（每個起床日只送最長的那一段，見 [sessionsToUpload]）
///   2. 記住送過哪些，免得每次開 App 重送
///
/// 原生端（`HealthConnectService.kt`）只回事實：有哪些 session、各自的分期。
/// 往回看幾天也是 Dart 決定的（[kHealthLookback]）。
///
/// ⚠️ 心率沒有送。`avgHeartRate` 在後端是選填，而 Garmin 那一欄的構念是
///    「睡眠期間」的平均心率——要算對得先知道入睡時刻，那是後端從分期推出來的，
///    在 Dart 重算就是第二個定義處。Tier3 對 Health Connect 來源本來就是 0
///    （見 adapter 的 HC_MODIFIER_NOTE），所以少了它分數不變。

/// 往回看幾天的 session。
///
/// 三天：涵蓋「週末沒開 App」。Health Connect 的資料留得比這久，但越往回讀
/// 越可能撞到授權前的資料（Health Connect 預設只給授權前 30 天）。
const Duration kHealthLookback = Duration(days: 3);

enum HealthAvailability { available, needsUpdate, unavailable }

/// 原生端的介面。真的實作走 `sonnap/health`；測試用假的。
abstract class HealthPlatform {
  Future<HealthAvailability> availability();
  Future<bool> hasPermission();

  /// 跳出 Health Connect 的授權畫面。回傳使用者有沒有給。
  Future<bool> requestPermission();

  /// 帶到 Play 商店安裝／更新 Health Connect。
  Future<void> openProviderStore();

  /// [start, end) 之間的睡眠 session，格式見 [HealthSession.tryParse]。
  Future<List<Map<Object?, Object?>>> readSleepSessions(DateTime start, DateTime end);
}

/// 走 `sonnap/health`。⚠️ 失敗一律當成「沒有」，不能讓 App 掛掉。
class PlatformHealth implements HealthPlatform {
  static const MethodChannel _channel = MethodChannel('sonnap/health');

  const PlatformHealth();

  @override
  Future<HealthAvailability> availability() async {
    try {
      switch (await _channel.invokeMethod<String>('status')) {
        case 'available':
          return HealthAvailability.available;
        case 'needs_update':
          return HealthAvailability.needsUpdate;
        default:
          return HealthAvailability.unavailable;
      }
    } on PlatformException {
      return HealthAvailability.unavailable;
    } on MissingPluginException {
      return HealthAvailability.unavailable;
    }
  }

  @override
  Future<bool> hasPermission() => _bool('hasPermission');

  @override
  Future<bool> requestPermission() => _bool('requestPermission');

  Future<bool> _bool(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on PlatformException catch (e) {
      debugPrint('Health: $method failed - $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> openProviderStore() async {
    try {
      await _channel.invokeMethod<void>('openProviderStore');
    } on PlatformException catch (e) {
      debugPrint('Health: openProviderStore failed - $e');
    } on MissingPluginException {
      // 非 Android 平台，或測試環境。
    }
  }

  @override
  Future<List<Map<Object?, Object?>>> readSleepSessions(DateTime start, DateTime end) async {
    try {
      return await _channel.invokeListMethod<Map<Object?, Object?>>('readSleepSessions', {
            'startMillis': start.millisecondsSinceEpoch,
            'endMillis': end.millisecondsSinceEpoch,
          }) ??
          const [];
    } on PlatformException catch (e) {
      debugPrint('Health: readSleepSessions failed - $e');
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }
}

/// 一筆 Health Connect 睡眠 session，照 `parse_session()` 要的格式。
@immutable
class HealthSession {
  final String startTime;
  final String endTime;
  final List<Map<String, Object?>> stages;

  /// 寫入的 App（例如 Samsung Health、Garmin Connect）。只供除錯，不上傳。
  final String? origin;

  const HealthSession({
    required this.startTime,
    required this.endTime,
    required this.stages,
    this.origin,
  });

  /// 時間壞掉的回 null。⚠️ 分期壞掉**不在這裡擋**：那是後端的判斷
  /// （adapter 會回 422 並說明原因），在這裡擋的話使用者永遠看不到原因。
  static HealthSession? tryParse(Map<Object?, Object?> raw) {
    final start = raw['startTime'];
    final end = raw['endTime'];
    if (start is! String || end is! String) return null;
    if (DateTime.tryParse(start) == null || DateTime.tryParse(end) == null) return null;
    final rawStages = raw['stages'];
    return HealthSession(
      startTime: start,
      endTime: end,
      stages: [
        if (rawStages is List)
          for (final s in rawStages)
            if (s is Map) {'startTime': s['startTime'], 'endTime': s['endTime'], 'stage': s['stage']},
      ],
      origin: raw['origin'] as String?,
    );
  }

  /// 認得同一段 session 用。
  String get key => '$startTime|$endTime';

  /// 絕對時間長度（比哪一段長用）。
  Duration get length => DateTime.parse(endTime).difference(DateTime.parse(startTime));

  /// 起床日，照**字串上的牆鐘時間**。
  ///
  /// ⚠️ 只拿來分組（同一天只送一段），**不上傳**——後端存哪一天由
  ///    adapter 從最後一個睡眠分期決定。
  /// ⚠️ 不能用 `DateTime.parse(endTime)` 的日期：07:30+08:00 在 UTC 是
  ///    前一天 23:30，同一晚會被分到兩個不同的日子。
  String get wakeDate {
    final end = parseWallClock(endTime)!;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${end.year}-${two(end.month)}-${two(end.day)}';
  }

  /// 送給 `POST /wearable` 的 `session` 欄位。
  Map<String, Object?> toPayload() => {
        'startTime': startTime,
        'endTime': endTime,
        'stages': stages,
      };
}

/// 這一次要送哪幾段。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 每個起床日只送最長的那一段
/// ═══════════════════════════════════════════════════════════════════
///
/// 後端以（使用者, 起床日）upsert。下午睡 40 分鐘的午覺也是一筆 session，
/// 起床日跟前一晚一樣——照順序全送的話，**午覺會蓋掉那一晚**，
/// 而且回 201、沒有任何錯誤訊息。
///
/// 已經送過的那一段不再送；但同一天出現**更長**的一段（例如手錶先寫了
/// 半段、同步後補成完整的一段）就送新的，讓後端覆寫。
/// 回傳時由舊到新排，最新的那一晚最後送。
List<HealthSession> sessionsToUpload(Iterable<HealthSession> sessions, Set<String> uploaded) {
  final longest = <String, HealthSession>{};
  for (final s in sessions) {
    final current = longest[s.wakeDate];
    if (current == null || s.length > current.length) longest[s.wakeDate] = s;
  }
  return longest.values.where((s) => !uploaded.contains(s.key)).toList()
    ..sort((a, b) => DateTime.parse(a.endTime).compareTo(DateTime.parse(b.endTime)));
}

enum WearableUploadStatus {
  /// 後端收下、打完分了
  ok,

  /// 後端說這一段算不了（422，例如沒有分期）。**不重送**——送幾次都一樣。
  rejected,

  /// 還沒有帳號
  noUser,

  /// 連不上、逾時、後端回錯。下次開 App 再送。
  failed,
}

@immutable
class WearableUploadResult {
  final WearableUploadStatus status;

  /// 以下都是**後端算的**，Dart 只顯示。
  final String? date;
  final String? baseQuality;
  final double? finalScore;
  final String? error;

  const WearableUploadResult(this.status, {this.date, this.baseQuality, this.finalScore, this.error});
}

/// `POST /wearable`。
class WearableUploader {
  final String baseUrl;
  final UserIdentity identity;
  final Duration timeout;

  const WearableUploader({
    required this.baseUrl,
    required this.identity,
    this.timeout = const Duration(seconds: 5),
  });

  Future<WearableUploadResult> upload(HealthSession session) async {
    final userId = await identity.currentUserId();
    if (userId == null) return const WearableUploadResult(WearableUploadStatus.noUser);

    final uri = Uri.parse('$baseUrl/wearable');
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.postUrl(uri).timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'user_id': userId, 'session': session.toPayload()}));
      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == 422) {
        return WearableUploadResult(WearableUploadStatus.rejected, error: body);
      }
      if (response.statusCode != 201) {
        return WearableUploadResult(WearableUploadStatus.failed,
            error: 'POST $uri returned ${response.statusCode}');
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return const WearableUploadResult(WearableUploadStatus.failed, error: 'response is not an object');
      }
      // ⚠️ 不印 user_id（它是憑證）。
      debugPrint('WearableUpload: ok date=${decoded['date']} quality=${decoded['base_quality']}');
      return WearableUploadResult(
        WearableUploadStatus.ok,
        date: decoded['date'] as String?,
        baseQuality: decoded['base_quality'] as String?,
        finalScore: (decoded['final_score'] as num?)?.toDouble(),
      );
    } catch (error) {
      debugPrint('WearableUpload: failed - $error');
      return WearableUploadResult(WearableUploadStatus.failed, error: error.toString());
    } finally {
      client.close(force: true);
    }
  }
}

enum HealthSyncStatus { noBackend, unavailable, needsUpdate, noPermission, done }

@immutable
class HealthSyncResult {
  final HealthSyncStatus status;

  /// Health Connect 裡找到幾段（含已經送過的）。
  final int found;
  final List<WearableUploadResult> uploads;

  const HealthSyncResult(this.status, {this.found = 0, this.uploads = const []});
}

/// 讀 → 挑 → 送 → 記住送過哪些。
class HealthSyncController {
  static const String uploadedKey = 'health_uploaded_sessions';

  final HealthPlatform platform;
  final KeyValueStore store;

  /// null = 這支 build 沒有後端。⚠️ 那時連 Health Connect 都不碰——
  /// demo build 開起來就跳授權畫面，而授權了也沒地方送。
  final WearableUploader? uploader;
  final DateTime Function() clock;

  HealthSyncController({
    required this.platform,
    required this.store,
    this.uploader,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  /// [askPermission]：沒授權時要不要跳授權畫面。開 App 時的自動同步
  /// **不問**（使用者沒按任何東西就跳系統畫面很突兀），只有設定頁的按鈕問。
  Future<HealthSyncResult> sync({bool askPermission = false}) async {
    final up = uploader;
    if (up == null) return const HealthSyncResult(HealthSyncStatus.noBackend);

    switch (await platform.availability()) {
      case HealthAvailability.unavailable:
        return const HealthSyncResult(HealthSyncStatus.unavailable);
      case HealthAvailability.needsUpdate:
        return const HealthSyncResult(HealthSyncStatus.needsUpdate);
      case HealthAvailability.available:
        break;
    }

    var granted = await platform.hasPermission();
    if (!granted && askPermission) granted = await platform.requestPermission();
    if (!granted) return const HealthSyncResult(HealthSyncStatus.noPermission);

    final now = clock();
    final raw = await platform.readSleepSessions(now.subtract(kHealthLookback), now);
    final sessions = raw.map(HealthSession.tryParse).whereType<HealthSession>().toList();

    final uploaded = await _loadUploaded();
    final results = <WearableUploadResult>[];
    for (final s in sessionsToUpload(sessions, uploaded)) {
      final r = await up.upload(s);
      results.add(r);
      // ⚠️ 只有 failed / noUser 要重送；rejected 送幾次都是 422。
      if (r.status == WearableUploadStatus.ok || r.status == WearableUploadStatus.rejected) {
        uploaded.add(s.key);
      }
    }

    // 只留還在視窗裡的，免得清單無限長。視窗外的不會再被讀到，
    // 就算讀到了重送一次也無害（後端是 upsert）。
    final live = sessions.map((s) => s.key).toSet();
    await store.setString(uploadedKey, jsonEncode(uploaded.intersection(live).toList()..sort()));
    return HealthSyncResult(HealthSyncStatus.done, found: sessions.length, uploads: results);
  }

  Future<Set<String>> _loadUploaded() async {
    final raw = await store.getString(uploadedKey);
    if (raw == null) return <String>{};
    try {
      return (jsonDecode(raw) as List).whereType<String>().toSet();
    } catch (_) {
      // 存壞了最壞是重送一次，後端是 upsert。
      return <String>{};
    }
  }
}

/// 設定頁上那一句。⚠️ 分數與等級照抄後端的回應。
String describeHealthSync(HealthSyncResult result) {
  switch (result.status) {
    case HealthSyncStatus.noBackend:
      return 'Health Connect sync needs the Sonnap backend.';
    case HealthSyncStatus.unavailable:
      return 'Health Connect is not available on this phone.';
    case HealthSyncStatus.needsUpdate:
      return 'Install or update Health Connect first.';
    case HealthSyncStatus.noPermission:
      return 'Sonnap is not allowed to read sleep from Health Connect yet.';
    case HealthSyncStatus.done:
      break;
  }
  if (result.uploads.isEmpty) {
    return result.found == 0
        ? 'No sleep sessions in Health Connect from the last ${kHealthLookback.inDays} days.'
        : 'Already up to date.';
  }
  final ok = result.uploads.where((u) => u.status == WearableUploadStatus.ok).toList();
  final failed = result.uploads.where((u) => u.status == WearableUploadStatus.failed).length;
  final rejected = result.uploads.where((u) => u.status == WearableUploadStatus.rejected).length;
  final parts = <String>[];
  if (ok.isNotEmpty) {
    final latest = ok.last;
    parts.add('Sent ${ok.length} night${ok.length == 1 ? '' : 's'}. '
        'Latest: ${latest.date ?? '?'}, rated ${latest.baseQuality ?? '?'} by the backend.');
  }
  if (failed > 0) parts.add('$failed could not be sent and will be retried.');
  if (rejected > 0) parts.add('$rejected could not be scored by the backend.');
  return parts.join(' ');
}
