import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'key_value_store.dart';
import 'user_identity.dart';

/// 睡眠計畫的 Journey（2026-11-19 使用者 grill 定）：把起床一站一站往前移。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 這個檔案不算任何東西
/// ═══════════════════════════════════════════════════════════════════
/// 每一站幾點、現在第幾站、連續幾天準時、能不能前進、終點是不是比起點早，
/// **全部由後端 `behavior/journey.py` 算**（準時起床只在後端判）。這裡只把 JSON
/// 變成 Dart 物件、記住「這一站的提示看過了沒」、告訴轉盤要不要鎖。
///
/// ⚠️ 這一站就是目標（Q2）：主程式拿到 [JourneyState.current] 就把目標就寢、
///    鬧鐘的起床換成它；後端那邊也已經換好了。

TimeOfDay? _parse(Object? s) {
  if (s is! String) return null;
  final p = s.split(':');
  if (p.length != 2) return null;
  final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
  if (h == null || m == null) return null;
  return TimeOfDay(hour: h, minute: m);
}

String journeyHhmm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

@immutable
class JourneyStop {
  final TimeOfDay wake;
  final TimeOfDay bedtime;
  const JourneyStop(this.wake, this.bedtime);

  static JourneyStop? fromJson(Object? j) {
    if (j is! Map) return null;
    final w = _parse(j['wake']), b = _parse(j['bedtime']);
    return (w == null || b == null) ? null : JourneyStop(w, b);
  }
}

enum JourneyStatus { active, done, stopped }

@immutable
class JourneyState {
  final JourneyStatus status;
  final TimeOfDay startWake;
  final TimeOfDay endWake;
  final int sleepMinutes;
  final String firstNight;
  final List<JourneyStop> stops;
  final int stopIndex;
  final int onTimeStreak;
  final int onTimeNeeded;
  final JourneyStop? current;

  const JourneyState({
    required this.status,
    required this.startWake,
    required this.endWake,
    required this.sleepMinutes,
    required this.firstNight,
    required this.stops,
    required this.stopIndex,
    required this.onTimeStreak,
    required this.onTimeNeeded,
    required this.current,
  });

  bool get active => status == JourneyStatus.active;

  /// 「這一站」的識別：同一段 Journey 的同一站才算看過（新開一段要重新提示）。
  String get noticeKey =>
      '${journeyHhmm(startWake)}|${journeyHhmm(endWake)}|$firstNight|$stopIndex|${status.name}';

  static JourneyState? fromJson(Object? j) {
    if (j is! Map) return null;
    final status = switch (j['status']) {
      'active' => JourneyStatus.active,
      'done' => JourneyStatus.done,
      'stopped' => JourneyStatus.stopped,
      _ => null,
    };
    final start = _parse(j['start_wake']), end = _parse(j['end_wake']);
    if (status == null || start == null || end == null) return null;
    final stops = (j['stops'] is List ? j['stops'] as List : const [])
        .map(JourneyStop.fromJson)
        .whereType<JourneyStop>()
        .toList();
    return JourneyState(
      status: status,
      startWake: start,
      endWake: end,
      sleepMinutes: (j['sleep_minutes'] as num?)?.toInt() ?? 0,
      firstNight: (j['first_night'] as String?) ?? '',
      stops: stops,
      stopIndex: (j['stop_index'] as num?)?.toInt() ?? 0,
      onTimeStreak: (j['on_time_streak'] as num?)?.toInt() ?? 0,
      onTimeNeeded: (j['on_time_needed'] as num?)?.toInt() ?? 3,
      current: JourneyStop.fromJson(j['current']),
    );
  }
}

@immutable
class JourneyInfo {
  final JourneyState? journey;

  /// 最近 7 晚實際起床的中間值；null＝量到的不到 3 晚（用轉盤上的起床時間）。
  final TimeOfDay? suggestedStart;
  /// 建議至少睡多久（後端照抄文獻，只當參考、不擋；使用者 11-19 定）。
  final int recommendedSleepMinutes;
  final int stepMinutes;

  const JourneyInfo({
    this.journey,
    this.suggestedStart,
    this.recommendedSleepMinutes = 420,
    this.stepMinutes = 30,
  });

  static JourneyInfo fromJson(Map<String, dynamic> j) => JourneyInfo(
        journey: JourneyState.fromJson(j['journey']),
        suggestedStart: _parse(j['suggested_start']),
        recommendedSleepMinutes: (j['recommended_sleep_minutes'] as num?)?.toInt() ?? 420,
        stepMinutes: (j['step_minutes'] as num?)?.toInt() ?? 30,
      );
}

enum JourneyStartOutcome { started, alreadyThere, failed }

/// 後端的三個端點。連不到一律回 null／failed，**不擋 App**。
abstract class JourneyApi {
  Future<JourneyInfo?> fetch();
  Future<(JourneyStartOutcome, JourneyState?)> start({
    required TimeOfDay startWake,
    required TimeOfDay endWake,
    required int sleepMinutes,
  });
  Future<JourneyState?> stop();
}

class HttpJourneyApi implements JourneyApi {
  final String baseUrl;
  final UserIdentity identity;
  final Duration timeout;

  const HttpJourneyApi({
    required this.baseUrl,
    required this.identity,
    this.timeout = const Duration(seconds: 6),
  });

  Future<(int, Map<String, dynamic>?)> _send(String method, String path,
      {Map<String, String>? query, Map<String, Object?>? body}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.openUrl(method, uri).timeout(timeout);
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join();
      final decoded = text.isEmpty ? null : jsonDecode(text);
      return (res.statusCode, decoded is Map<String, dynamic> ? decoded : null);
    } catch (_) {
      return (0, null);
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<JourneyInfo?> fetch() async {
    // ⚠️ user_id 是憑證，走 query string 是後端定的介面；不要印出來。
    final id = await identity.currentUserId();
    if (id == null) return null;
    final (code, j) = await _send('GET', '/journey', query: {'user_id': id});
    return code == 200 && j != null ? JourneyInfo.fromJson(j) : null;
  }

  @override
  Future<(JourneyStartOutcome, JourneyState?)> start({
    required TimeOfDay startWake,
    required TimeOfDay endWake,
    required int sleepMinutes,
  }) async {
    final id = await identity.currentUserId();
    if (id == null) return (JourneyStartOutcome.failed, null);
    final (code, j) = await _send('POST', '/journey', body: {
      'user_id': id,
      'start_wake': journeyHhmm(startWake),
      'end_wake': journeyHhmm(endWake),
      'sleep_minutes': sleepMinutes,
    });
    if (code == 201) return (JourneyStartOutcome.started, JourneyState.fromJson(j?['journey']));
    // 終點不比起點早：後端判、App 只照實說（Dart 不算跨午夜）
    if (code == 422 && '${j?['detail']}'.contains('already_there')) {
      return (JourneyStartOutcome.alreadyThere, null);
    }
    return (JourneyStartOutcome.failed, null);
  }

  @override
  Future<JourneyState?> stop() async {
    final id = await identity.currentUserId();
    if (id == null) return null;
    final (code, j) = await _send('POST', '/journey/stop', body: {'user_id': id});
    return code == 200 ? JourneyState.fromJson(j?['journey']) : null;
  }
}

/// 轉盤要不要鎖（三個入口共用：首頁時鐘卡、導覽列中間、設定頁、計畫頁）。
const String kJourneyActiveKey = 'journey_active';

/// 「Next stop from tonight」看過的那一站（[JourneyState.noticeKey]）。
const String kJourneySeenKey = 'journey_seen_stop';

Future<bool> journeyLocksSchedule(KeyValueStore store) async =>
    (await store.getString(kJourneyActiveKey)) == '1';

/// 整個 App 共用一份（主程式擁有）。計畫頁與首頁小卡都聽它。
class JourneyController extends ChangeNotifier {
  final KeyValueStore store;
  JourneyApi? api;
  JourneyInfo? info;
  String? _seen;

  JourneyController({required this.store, this.api});

  JourneyState? get journey => info?.journey;

  /// 要不要出現「Next stop from tonight」或「You reached your goal schedule」：
  /// 前進過（第 2 站起）或走完，而且這一站還沒看過。第 1 站是自己剛按的，不用提示。
  bool get showNotice {
    final j = journey;
    if (j == null || j.status == JourneyStatus.stopped) return false;
    if (j.active && j.stopIndex == 0) return false;
    return _seen != j.noticeKey;
  }

  Future<void> markSeen() async {
    final j = journey;
    if (j == null) return;
    _seen = j.noticeKey;
    await store.setString(kJourneySeenKey, j.noticeKey);
    notifyListeners();
  }

  Future<void> _apply(JourneyInfo? next) async {
    if (next == null) return; // 連不到：留著上一份，不拿失敗蓋掉
    info = next;
    _seen = await store.getString(kJourneySeenKey);
    if (next.journey?.active ?? false) {
      await store.setString(kJourneyActiveKey, '1');
    } else {
      await store.remove(kJourneyActiveKey);
    }
    notifyListeners();
  }

  Future<JourneyInfo?> refresh() async {
    final a = api;
    if (a == null) return info;
    await _apply(await a.fetch());
    return info;
  }

  Future<JourneyStartOutcome> start({
    required TimeOfDay startWake,
    required TimeOfDay endWake,
    required int sleepMinutes,
  }) async {
    final a = api;
    if (a == null) return JourneyStartOutcome.failed;
    final (outcome, _) =
        await a.start(startWake: startWake, endWake: endWake, sleepMinutes: sleepMinutes);
    if (outcome == JourneyStartOutcome.started) await refresh();
    return outcome;
  }

  Future<bool> stop() async {
    final a = api;
    if (a == null) return false;
    final s = await a.stop();
    if (s == null) return false;
    await refresh();
    return true;
  }
}
