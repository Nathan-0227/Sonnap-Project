import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'key_value_store.dart';

/// 就寢守門（B4）：在就寢時間窗裡打開黑名單 App 時，跳回桌面或跳出提醒。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 判斷在 Dart，原生端只套用 Dart 算好的時間窗
/// ═══════════════════════════════════════════════════════════════════
///
/// 無障礙服務（`BedtimeGuardService.kt`）在背景跑的時候 Flutter 根本沒在執行，
/// 所以它不可能每次都問 Dart。做法跟就寢提醒一樣：Dart 把「今晚從幾點守到幾點、
/// 守哪些 App、哪一種模式、提醒寫什麼、多久不重複」算好推給原生端
/// （[GuardConfig]），原生端只做「現在在窗裡嗎、這個 App 在名單上嗎」。
/// 門檻寫進 Kotlin 的話，每次調整都要重編 APK 才驗得了。
///
/// [GuardConfig.actionFor] 是原生端行為的**參考實作**：Kotlin 那一邊照它做，
/// 測試驗的是它。
///
/// ⚠️ Google Play 政策規定 Accessibility API 只能用於協助身心障礙者，
///    這類 App 上架會被駁回。D2 走側載沒問題，限制寫在 docs/BEDTIME_GUARD.md。

enum GuardMode {
  /// 不守。
  off,

  /// 蓋一層可以關掉的提醒，不強制。
  reminder,

  /// 直接跳回桌面。
  block,
}

enum GuardAction { none, remind, sendHome }

/// 目標就寢時間前多久開始守。
///
/// ⚠️ 行為提示的工程判斷，不是計分門檻。與就寢提醒（kReminderLead）、首頁倒數
///    變紅（kImminentThreshold）同一個 30 分——三者不一致的話，通知說「還有
///    30 分」、倒數還是綠的、App 卻已經被擋了。
const Duration kGuardLeadIn = Duration(minutes: 30);

/// 目標就寢時間之後守多久。
///
/// 取 6 小時：要蓋得住「過了就寢時間還在滑」的那幾個小時（那正是睡眠拖延），
/// 又不能守到白天——早上起床要查公車時被擋，只會讓人把守門整個關掉。
const Duration kGuardTail = Duration(hours: 6);

/// 提醒模式下，同一個 App 多久內不重複跳提醒。每次切換視窗都跳的話，
/// 使用者會在第三次就把功能關掉。
const Duration kReminderCooldown = Duration(minutes: 10);

@immutable
class GuardWindow {
  final DateTime start;
  final DateTime end;

  const GuardWindow(this.start, this.end);

  /// 起點算在內、終點不算在內。
  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);
}

/// 現在正在守的那一窗，或下一窗。
///
/// ⚠️ 要從**昨天**的目標時刻開始看：目標 23:30、現在 01:00 的時候，正在守的是
///    「昨天 23:00 → 今天 05:30」那一窗。只看今天的話會跳到今晚那一窗，
///    半夜正在滑手機的時候反而不守。
GuardWindow guardWindow(DateTime now, TimeOfDay bedtime) {
  final today = DateTime(now.year, now.month, now.day, bedtime.hour, bedtime.minute);
  for (final anchor in [
    today.subtract(const Duration(days: 1)),
    today,
    today.add(const Duration(days: 1)),
  ]) {
    final w = GuardWindow(anchor.subtract(kGuardLeadIn), anchor.add(kGuardTail));
    if (now.isBefore(w.end)) return w;
  }
  final tomorrow = today.add(const Duration(days: 1));
  return GuardWindow(tomorrow.subtract(kGuardLeadIn), tomorrow.add(kGuardTail));
}

/// 推給原生端的完整設定。原生端只照它做，不自己判斷任何門檻。
@immutable
class GuardConfig {
  final GuardMode mode;
  final GuardWindow window;
  final Set<String> packages;
  final String title;
  final String body;
  final Duration cooldown;

  const GuardConfig({
    required this.mode,
    required this.window,
    required this.packages,
    required this.title,
    required this.body,
    this.cooldown = kReminderCooldown,
  });

  /// 原生端行為的參考實作。Kotlin 的 BedtimeGuardService 照這個做。
  GuardAction actionFor(DateTime now, String? package) {
    if (mode == GuardMode.off || package == null) return GuardAction.none;
    if (!window.contains(now)) return GuardAction.none;
    if (!packages.contains(package)) return GuardAction.none;
    return mode == GuardMode.block ? GuardAction.sendHome : GuardAction.remind;
  }

  Map<String, Object> toMap() => {
        'mode': mode.name,
        'startMillis': window.start.millisecondsSinceEpoch,
        'endMillis': window.end.millisecondsSinceEpoch,
        'packages': packages.toList()..sort(),
        'title': title,
        'body': body,
        'cooldownMillis': cooldown.inMilliseconds,
      };
}

/// 使用者的選擇：哪一種模式、守哪些 App。
@immutable
class GuardSettings {
  final GuardMode mode;
  final Set<String> packages;

  const GuardSettings({this.mode = GuardMode.off, this.packages = const {}});

  GuardSettings copyWith({GuardMode? mode, Set<String>? packages}) =>
      GuardSettings(mode: mode ?? this.mode, packages: packages ?? this.packages);
}

@immutable
class LaunchableApp {
  final String packageName;
  final String label;

  const LaunchableApp(this.packageName, this.label);
}

/// 原生端的介面。真的實作走 `sonnap/guard`；測試用假的。
abstract class GuardPlatform {
  Future<void> configure(GuardConfig config);

  /// 使用者有沒有在系統設定裡打開 Sonnap 的無障礙服務。
  Future<bool> isEnabled();

  /// 帶使用者到系統的無障礙設定頁（跟使用情況存取一樣，要不到、只能帶過去）。
  Future<void> openSettings();

  /// 桌面上看得到的 App（黑名單的候選）。
  Future<List<LaunchableApp>> listApps();
}

/// 走 `sonnap/guard`。⚠️ 失敗一律吞掉：守門是加分項，不能讓設定頁掛掉。
class PlatformGuard implements GuardPlatform {
  static const MethodChannel _channel = MethodChannel('sonnap/guard');

  const PlatformGuard();

  @override
  Future<void> configure(GuardConfig config) async {
    try {
      await _channel.invokeMethod<void>('configure', config.toMap());
    } on PlatformException catch (e) {
      debugPrint('Guard: configure failed - $e');
    } on MissingPluginException {
      // 非 Android 平台，或測試環境。
    }
  }

  @override
  Future<bool> isEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openSettings');
    } on PlatformException catch (e) {
      debugPrint('Guard: openSettings failed - $e');
    } on MissingPluginException {
      // 同上
    }
  }

  @override
  Future<List<LaunchableApp>> listApps() async {
    try {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('listApps') ?? const [];
      return [
        for (final m in raw)
          if (m['package'] is String)
            LaunchableApp(m['package'] as String, (m['label'] as String?) ?? (m['package'] as String)),
      ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }
}

/// 存設定、把設定推給原生端。
class BedtimeGuardController {
  static const String modeKey = 'guard_mode';
  static const String packagesKey = 'guard_packages';

  final GuardPlatform platform;
  final KeyValueStore store;
  final DateTime Function() clock;

  BedtimeGuardController({
    required this.platform,
    required this.store,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  Future<GuardSettings> load() async {
    final rawMode = await store.getString(modeKey);
    final mode = GuardMode.values.firstWhere((m) => m.name == rawMode, orElse: () => GuardMode.off);
    final rawPackages = await store.getString(packagesKey);
    var packages = <String>{};
    if (rawPackages != null) {
      try {
        packages = (jsonDecode(rawPackages) as List).whereType<String>().toSet();
      } catch (_) {
        // 存壞了就當沒選——最壞的後果是守門不擋任何 App，不是整頁掛掉。
      }
    }
    return GuardSettings(mode: mode, packages: packages);
  }

  Future<void> save(GuardSettings settings) async {
    await store.setString(modeKey, settings.mode.name);
    await store.setString(packagesKey, jsonEncode(settings.packages.toList()..sort()));
  }

  static String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  GuardConfig configFor(GuardSettings settings, TimeOfDay bedtime) => GuardConfig(
        mode: settings.mode,
        window: guardWindow(clock(), bedtime),
        packages: settings.packages,
        title: "It's close to bedtime",
        body: 'Your target bedtime is ${_hhmm(bedtime)}. '
            'This app is on your bedtime list - maybe put the phone down.',
      );

  /// 依目前的設定與目標時間推給原生端。
  ///
  /// ⚠️ 改了目標就寢時間也要推，否則原生端還在守舊的時間窗。
  Future<void> push(TimeOfDay bedtime) async {
    final settings = await load();
    await platform.configure(configFor(settings, bedtime));
  }
}
