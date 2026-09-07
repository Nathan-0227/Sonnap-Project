import 'package:flutter/foundation.dart';

import 'lights_out.dart';
import 'usage_stats.dart';

/// 睡前那一段要往回看多久。
///
/// ⚠️ 60 分鐘是**產品決定，不是文獻門檻**——與 `behavior/adherence.py` 的
/// `LATE_THRESHOLD_MINUTES` 同一種狀態。它可以這樣訂，是因為這個量
/// **不進任何分數**，只是呈現與行為迴圈的材料。
const Duration kPreBedWindow = Duration(minutes: 60);

/// 把互動事件流切成「上床前 N 分鐘，每個 App 各佔多久」。
///
/// ## 為什麼需要這支
///
/// `getUsage` 給的是**整個日曆日**的彙總，答不出「睡前那一小時你在幹嘛」。
/// 而睡前使用才是行為迴圈想介入的東西——整天用了 3 小時 IG 跟
/// 「躺下前那一小時都在滑 IG」是完全不同的兩件事，前者管不著，後者可以改。
///
/// 材料就是 `lights_out` 那條路已經在拿的事件流（`resumed`/`paused` 帶
/// `package_name`），只是先前沒有依 App 切段。
///
/// ## 演算法
///
/// Android 同一時間只有一個 App 在前景，所以事件流可以還原成一串不重疊的
/// 區段：`resumed` 開一段，下一個 `resumed`／`paused`／螢幕關閉關掉它。
/// 每一段與 `[lightsOutAt − window, lightsOutAt]` 的**交集**就是它的貢獻。
///
/// ⚠️ **這是「前景時間」不是「盯著螢幕的時間」**（同 [AppUsage] 的說明）。
///
/// ⚠️ 三個容易寫錯、而且寫錯不會報錯的地方：
///
/// 1. **`resumed` 沒有配對的結束事件是常態**，不是壞資料——使用者就這樣
///    拿著手機睡著了。那一段要延續到「螢幕關閉」或視窗結尾，丟掉的話
///    最後那個 App（通常正是睡前一直在滑的那個）會整段消失。
/// 2. **螢幕關閉要關掉開著的區段。** Android 多數時候會補一個 `paused`，
///    但不保證。不處理的話，關螢幕之後的整夜都會被算成那個 App 在前景。
/// 3. **區段要跟視窗取交集，不是「起點落在視窗內就整段算」**。
///    22:00 開始滑、23:30 放下手機、視窗從 22:30 起算——那一段只有
///    60 分鐘在視窗內，不是 90 分鐘。
List<AppUsage> preBedApps(
  List<InteractionEvent> events, {
  required DateTime lightsOutAt,
  Duration window = kPreBedWindow,
  Map<String, String> labels = const {},
  Set<String> excludePackages = const {},
}) {
  final windowStart = lightsOutAt.subtract(window);

  // 只留有意義的事件，並依時間排序。原生端已經排過，但下游整個建立在
  // 順序上，所以自己再排一次（同 UsageStatsService 的作法）。
  final relevant = events
      .where((e) =>
          e.type == 'resumed' ||
          e.type == 'paused' ||
          e.type == 'screen_off' ||
          e.type == 'keyguard_shown')
      .toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  final totals = <String, int>{};   // package -> 秒
  String? openPackage;
  DateTime? openedAt;

  void close(DateTime at) {
    if (openPackage == null || openedAt == null) return;
    // 與視窗取交集
    final from = openedAt!.isBefore(windowStart) ? windowStart : openedAt!;
    final to = at.isAfter(lightsOutAt) ? lightsOutAt : at;
    if (to.isAfter(from)) {
      totals[openPackage!] =
          (totals[openPackage!] ?? 0) + to.difference(from).inSeconds;
    }
    openPackage = null;
    openedAt = null;
  }

  for (final e in relevant) {
    // 視窗結束之後的事件不用再看了，但**視窗開始之前的要看**——
    // 上床前一小時之前就開著的那個 App，它的區段跨進視窗裡。
    if (e.timestamp.isAfter(lightsOutAt)) break;

    switch (e.type) {
      case 'resumed':
        close(e.timestamp);          // 前景只有一個，新的來就關掉舊的
        if (e.packageName.isNotEmpty) {
          openPackage = e.packageName;
          openedAt = e.timestamp;
        }
        break;
      case 'paused':
        // 只有關掉「同一個 App」才算數。實機上會出現 A 的 paused 晚於
        // B 的 resumed（系統事件順序不保證嚴格交錯），照收會把 B 誤關。
        if (openPackage == e.packageName) close(e.timestamp);
        break;
      case 'screen_off':
      case 'keyguard_shown':
        close(e.timestamp);
        break;
    }
  }

  // 到最後都還開著 → 延續到上床時刻。這是常態不是異常，見上面第 1 點。
  close(lightsOutAt);

  final apps = <AppUsage>[];
  totals.forEach((pkg, seconds) {
    if (excludePackages.contains(pkg)) return;
    final minutes = (seconds / 60).round();
    if (minutes < 1) return;         // 不到一分鐘的不顯示，那是切換過去的雜訊
    apps.add(AppUsage(
      packageName: pkg,
      appName: labels[pkg] ?? pkg,
      minutes: minutes,
    ));
  });

  // 依顯示名稱合併（兩個都叫 Google 的東西對使用者而言是同一個），
  // 判準與日彙總那條路共用 mergeByLabel，不要各自再寫一份。
  return mergeByLabel(apps);
}

/// 睡前那一段的結果。把「算得出來」與「為什麼算不出來」分開，
/// 因為畫面上要講的話不一樣（同 [UsageStatsResult] 的作法）。
@immutable
class PreBedResult {
  /// 上床時刻。null 代表偵測不到，那時 [apps] 一定是空的。
  final DateTime? lightsOutAt;
  final Duration window;
  final List<AppUsage> apps;

  const PreBedResult({
    this.lightsOutAt,
    this.window = kPreBedWindow,
    this.apps = const [],
  });

  bool get hasData => lightsOutAt != null && apps.isNotEmpty;

  /// 這一段總共用了幾分鐘。
  int get totalMinutes => apps.fold(0, (sum, a) => sum + a.minutes);
}
