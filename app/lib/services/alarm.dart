import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'home_mode.dart';
import 'key_value_store.dart';

/// 鬧鐘（2026-11-12 使用者定案）。
///
/// - **自己做**，不交給系統時鐘 App。原生端在 `AlarmService.kt` 那幾支。
/// - **只有按了 Start Sleep 才排**；排在「下一個起床時刻」，超過 14 小時就不排
///   （與睡覺畫面的 [kMaxSleepSession] 同一個 14 小時）。
/// - 按 Out of bed、Cancel、或鬧鐘畫面的 Dismiss 都會取消。響了**不會**自動按 Out of bed。
/// - 起床時間與開關**只存在手機上**（後端用不到）。
/// - 不加「不保證會響」的提示（使用者決定）；重開機後不重排（已知限制）。
///
/// 判斷全在 Dart，原生端只做「在這個時刻響」——與就寢提醒同一條紀律。

const String kWakeTimeKey = 'alarm_wake_time'; // "HH:mm"
const String kAlarmEnabledKey = 'alarm_enabled'; // "1" / "0"
const String kAlarmTonightKey = 'alarm_tonight_at'; // ISO8601，今晚排了幾點

/// 起床時間的預設：目標就寢時間加 8 小時（使用者決定，Q8）。
TimeOfDay defaultWakeTime(TimeOfDay bedtime) {
  final total = (bedtime.hour * 60 + bedtime.minute + 8 * 60) % (24 * 60);
  return TimeOfDay(hour: total ~/ 60, minute: total % 60);
}

/// 下一次鬧鐘的時刻：[now] 之後第一個 [wake]。超過 [kMaxSleepSession] 就不排（回 null）。
DateTime? nextAlarmTime(DateTime now, TimeOfDay wake) {
  var at = DateTime(now.year, now.month, now.day, wake.hour, wake.minute);
  if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
  if (at.difference(now) > kMaxSleepSession) return null;
  return at;
}

String _hhmm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay? _parseHhmm(String? s) {
  if (s == null) return null;
  final p = s.split(':');
  if (p.length != 2) return null;
  final h = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
  return TimeOfDay(hour: h, minute: m);
}

/// 鬧鐘的設定與「今晚排了幾點」，存在手機上。
class AlarmSettingsStore {
  final KeyValueStore store;
  const AlarmSettingsStore(this.store);

  /// 還沒設定過時用 [defaultWakeTime]。
  Future<TimeOfDay> wakeTime(TimeOfDay bedtime) async =>
      _parseHhmm(await store.getString(kWakeTimeKey)) ??
      defaultWakeTime(bedtime);

  /// 預設開（使用者決定，Q9）。
  Future<bool> enabled() async =>
      (await store.getString(kAlarmEnabledKey)) != '0';

  Future<void> save({required TimeOfDay wake, required bool enabled}) async {
    await store.setString(kWakeTimeKey, _hhmm(wake));
    await store.setString(kAlarmEnabledKey, enabled ? '1' : '0');
  }

  Future<DateTime?> tonight() async {
    final s = await store.getString(kAlarmTonightKey);
    return s == null ? null : DateTime.tryParse(s);
  }

  Future<void> setTonight(DateTime? at) async {
    if (at == null) {
      await store.remove(kAlarmTonightKey);
    } else {
      await store.setString(kAlarmTonightKey, at.toIso8601String());
    }
  }
}

/// 原生端的介面。測試換成假的。
abstract class AlarmScheduler {
  Future<void> schedule(DateTime at);
  Future<void> cancel();

  /// 通知與全螢幕通知都允許了沒（Android 13+／14+ 才需要問）。
  Future<bool> canRing();
  Future<void> requestPermission();
  Future<void> openSettings();
}

/// 走 `sonnap/alarm`，另一頭是 `AlarmService.kt`。
/// ⚠️ 失敗一律吞掉、不拋例外（與 [PlatformReminderScheduler] 同一條紀律）。
class PlatformAlarmScheduler implements AlarmScheduler {
  static const MethodChannel _channel = MethodChannel('sonnap/alarm');
  const PlatformAlarmScheduler();

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      debugPrint('Alarm: $method failed - $e');
      return null;
    } on MissingPluginException {
      return null; // 非 Android 平台，或測試環境。
    }
  }

  @override
  Future<void> schedule(DateTime at) =>
      _call<void>('schedule', {'triggerAtMillis': at.millisecondsSinceEpoch});

  @override
  Future<void> cancel() => _call<void>('cancel');

  @override
  Future<bool> canRing() async => (await _call<bool>('canRing')) ?? false;

  @override
  Future<void> requestPermission() => _call<void>('requestPermission');

  @override
  Future<void> openSettings() => _call<void>('openSettings');
}

/// 把「按 Start Sleep → 排鬧鐘」「下床／取消 → 取消鬧鐘」接起來。
class AlarmController {
  final AlarmSettingsStore settings;
  final AlarmScheduler scheduler;
  const AlarmController({required this.settings, required this.scheduler});

  /// 按了 Start Sleep。回傳排了幾點（沒排就是 null）。
  Future<DateTime?> onStartSleep(DateTime now, TimeOfDay bedtime) async {
    if (!await settings.enabled()) {
      await settings.setTonight(null);
      return null;
    }
    final at = nextAlarmTime(now, await settings.wakeTime(bedtime));
    if (at == null) {
      await settings.setTonight(null);
      return null;
    }
    await scheduler.schedule(at);
    await settings.setTonight(at);
    return at;
  }

  /// 睡覺畫面上改今晚的鬧鐘（半夜想到明天要早起）。轉盤上的設定不受影響。
  /// 回傳排了幾點；超過 14 小時就不排，回 null（原本排的不動）。
  /// 原生端用同一個 PendingIntent，重排會直接蓋掉舊的那個。
  Future<DateTime?> setTonightAt(DateTime now, TimeOfDay wake) async {
    final at = nextAlarmTime(now, wake);
    if (at == null) return null;
    await scheduler.schedule(at);
    await settings.setTonight(at);
    return at;
  }

  /// 下床、取消、或在睡覺畫面點「只關今晚」。轉盤上的設定不受影響。
  Future<void> cancelTonight() async {
    await scheduler.cancel();
    await settings.setTonight(null);
  }
}
