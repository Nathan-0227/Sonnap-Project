import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'lights_out.dart';

/// 一個 App 在某段期間的前景使用時間。
///
/// ⚠️ **這是「前景時間」不是「盯著螢幕的時間」**——App 在前景但使用者
/// 去倒水，那段時間照樣算進去。報告裡要寫成 proxy，不要寫成使用時間。
@immutable
class AppUsage {
  final String packageName;
  final String appName;
  final int minutes;

  /// 是不是桌面啟動器（One UI Home、Pixel Launcher…）。
  ///
  /// 原生端問系統「誰接得住 HOME intent」得到的，不是寫死的名單。
  final bool isLauncher;

  const AppUsage({
    required this.packageName,
    required this.appName,
    required this.minutes,
    this.isLauncher = false,
  });

  factory AppUsage.fromMap(Map<Object?, Object?> map) {
    return AppUsage(
      packageName: (map['package_name'] as String?) ?? '',
      appName: (map['app_name'] as String?) ?? '',
      minutes: (map['usage_minutes'] as num?)?.toInt() ?? 0,
      isLauncher: (map['is_launcher'] as bool?) ?? false,
    );
  }
}

/// 合併顯示名稱相同的項目，並依分鐘數重新排序。
///
/// ## 為什麼需要這一步
///
/// 實機上曾出現「One UI Home 24m」「One UI Home 12m」兩列，看起來像程式壞了。
///
/// ⚠️ 當時我判斷成「兩個不同的 package 共用同一個顯示名稱」，**那個診斷是錯的**。
/// 真正的原因是原生端用了 `queryUsageStats`，它回傳的是原始 bucket，同一個
/// package 跨多個 bucket 就會出現好幾筆。改用 `queryAndAggregateUsageStats`
/// 之後那個重複已經在源頭消失了。
///
/// 這一層仍然留著，因為「不同 package 真的共用顯示名稱」是會發生的
/// （Google 搜尋與 Play 服務都叫「Google」）。依**顯示名稱**合併而不是
/// package：使用者認得的是名稱，兩個都叫 Google 的東西對他而言就是同一個。
/// 代價是技術上不同的元件被算在一起，但這張卡問的是「你花時間在什麼上面」，
/// 那個層級才是對的。
List<AppUsage> mergeByLabel(Iterable<AppUsage> apps) {
  final merged = <String, AppUsage>{};

  for (final app in apps) {
    final existing = merged[app.appName];
    merged[app.appName] = existing == null
        ? app
        : AppUsage(
            // package 取用得比較久的那一個，只是為了讓值有個確定的來源
            packageName: existing.minutes >= app.minutes
                ? existing.packageName
                : app.packageName,
            appName: app.appName,
            minutes: existing.minutes + app.minutes,
            isLauncher: existing.isLauncher || app.isLauncher,
          );
  }

  final result = merged.values.toList()
    ..sort((a, b) => b.minutes.compareTo(a.minutes));
  return result;
}

/// 查詢結果。把「拿到資料」與「為什麼沒有資料」分成不同的狀態，
/// 因為它們在畫面上要講完全不同的話（而且解法不同）。
enum UsageStatsStatus {
  /// 有資料
  ok,

  /// 使用者還沒在系統設定裡開啟「使用情況存取」
  permissionRequired,

  /// 這個平台沒有這個能力（iOS、桌機、以及 widget test）
  unsupported,

  /// 有權限、查詢也成功，但那段期間沒有任何 App 有前景時間
  empty,

  /// 呼叫原生端時出錯
  failed,
}

@immutable
class UsageStatsResult {
  final UsageStatsStatus status;
  final List<AppUsage> apps;
  final String? error;

  const UsageStatsResult(this.status, {this.apps = const [], this.error});
}

/// 包住 Android 原生的 `sonnap/usage` channel。
///
/// ## 原生端早就寫好了，只是沒人呼叫
///
/// `UsageStatsService.kt`（97 行）與 `MainActivity` 的 channel 註冊在 PR #16
/// 就進 main 了，但 `app/lib/` 底下一個 `MethodChannel` 都沒有——橋搭了一半。
/// 這個檔案是另外一半。
///
/// ## ⚠️ 它給得出什麼、給不出什麼
///
/// 原生端用的是 `queryAndAggregateUsageStats()`，回傳的是
/// **一段期間內每個 App 的前景總分鐘數**。所以：
///
/// - ✅ 「昨天你最常用哪些 App」——算得出來
/// - ❌ 「睡前 60 分鐘用了什麼」——**算不出來**，日彙總沒有時間軸
///
/// **畫面上不可以把日彙總說成「睡前使用」**——那是兩個不同的量。
///
/// `lights_out_at`（最後一次放下手機的時刻）走的是另一條路：[lightsOut]
/// 用 `queryEvents()` 的逐筆事件推出來，判斷邏輯在 `lights_out.dart`。
/// 要做「睡前 60 分鐘用了什麼」的話，材料已經在那條路上了——把事件流
/// 依 App 切段即可，但那是另一件工作。
///
/// ## ⚠️ 這個數字不會跟系統「數位健康」一樣，那是正常的
///
/// 實機對照（2026-08-31，兩次量測差約 20 分鐘）：
///
/// | | 數位健康 | Sonnap |
/// |---|---|---|
/// | 抖音 | 2h9m | 2h28m |
/// | YouTube | 32m | 35m |
/// | Instagram | 33m | 1h28m |
///
/// 兩者量的**不是同一件事**：`totalTimeInForeground` 是「App 的 Activity
/// 處於前景」，數位健康量的是「螢幕亮著且已解鎖」。App 停在前景但螢幕關掉、
/// 或人離開去做別的事，前者照算、後者不算。
///
/// → 報告一律寫成 **proxy（替代測量）**，比照本專案對 `sleep_efficiency`
///   與 `movement_sample_minutes` 的既有處理標準。不要寫成「使用時間」。
///
/// ## ⚠️ 「昨天」的邊界是近似的
///
/// `queryAndAggregateUsageStats` 會把**與查詢區間有重疊的**日 bucket 全部
/// 算進來，而系統的日 bucket 不保證切在午夜。所以「昨天」可能沾到一點今天。
/// 要精確的區間同樣得靠 `queryEvents()`。
///
/// ## 權限
///
/// `PACKAGE_USAGE_STATS` 不是一般權限，`requestPermissions()` 要不到。
/// 使用者必須自己到「設定 → 使用情況存取」開啟，[openSettings] 會把人帶過去。
class UsageStatsService {
  static const MethodChannel _channel = MethodChannel('sonnap/usage');

  const UsageStatsService();

  /// 只有 Android 有這個能力。
  ///
  /// ⚠️ 這個檢查不能省。iOS 沒有等價 API，而 widget test 跑在 Dart VM 上
  /// 根本沒有原生端——沒有這一行的話測試會拿到 MissingPluginException。
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<bool> hasAccess() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('hasUsageAccess') ?? false;
    } on PlatformException catch (e) {
      debugPrint('UsageStats: hasUsageAccess failed - $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 把使用者帶到系統的「使用情況存取」設定頁。
  ///
  /// ⚠️ 回來之後**必須重新查一次權限**——這個呼叫不會等使用者操作完，
  /// 也拿不到他按了什麼。
  Future<void> openSettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('openUsageAccessSettings');
    } on PlatformException catch (e) {
      debugPrint('UsageStats: openUsageAccessSettings failed - $e');
    } on MissingPluginException {
      // 沒有原生端可以帶路，安靜跳過就好
    }
  }

  /// 查 [start] 到 [end] 之間的前景使用時間，已依分鐘數遞減排序。
  ///
  /// ⚠️ 系統是**以日為單位存桶**的，傳進去的區間只是用來挑桶子，
  /// 不會把某一天切成幾個小時。要一小時的解析度得改用 `queryEvents()`。
  Future<UsageStatsResult> query({
    required DateTime start,
    required DateTime end,
    int limit = 5,
  }) async {
    if (!isSupported) {
      return const UsageStatsResult(UsageStatsStatus.unsupported);
    }

    if (!await hasAccess()) {
      return const UsageStatsResult(UsageStatsStatus.permissionRequired);
    }

    try {
      final raw = await _channel.invokeMethod<List<Object?>>('getUsage', {
        'startTime': start.millisecondsSinceEpoch,
        'endTime': end.millisecondsSinceEpoch,
      });

      final apps = mergeByLabel(
        (raw ?? const [])
            .whereType<Map<Object?, Object?>>()
            .map(AppUsage.fromMap)
            .where((a) => a.appName.isNotEmpty && a.minutes > 0)
            // ⚠️ 排除桌面啟動器。實機實測它永遠是第一名（24 分鐘，比所有
            // 真正的 App 都多）——因為只要人停在主畫面就累積它的前景時間。
            // 把「你在主畫面待了多久」列成第一個睡眠干擾源，這張卡就沒有
            // 任何意義了。這是產品判斷，所以做在這裡而不是原生端。
            .where((a) => !a.isLauncher),
      ).take(limit).toList();

      // 原生端在「沒有權限」時也是回空陣列。上面已經先問過權限了，
      // 所以走到這裡的空陣列是真的沒有使用紀錄（例如剛開機）。
      return apps.isEmpty
          ? const UsageStatsResult(UsageStatsStatus.empty)
          : UsageStatsResult(UsageStatsStatus.ok, apps: apps);
    } on PlatformException catch (e) {
      return UsageStatsResult(UsageStatsStatus.failed, error: e.message);
    } on MissingPluginException {
      return const UsageStatsResult(UsageStatsStatus.unsupported);
    }
  }

  /// 逐筆互動事件（`getUsage` 的日彙總沒有時間軸，答不出就寢時刻）。
  ///
  /// 回傳原始事件，判斷交給 [detectLightsOut]。
  Future<List<InteractionEvent>> interactionEvents({
    required DateTime start,
    required DateTime end,
  }) async {
    if (!isSupported) return const [];

    final raw = await _channel.invokeMethod<List<Object?>>(
      'getInteractionEvents',
      {
        'startTime': start.millisecondsSinceEpoch,
        'endTime': end.millisecondsSinceEpoch,
      },
    );

    return (raw ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(InteractionEvent.fromMap)
        .toList();
  }

  /// 上一次放下手機的時刻。
  ///
  /// ⚠️ 視窗刻意用「往回 24 小時」而不是「昨天 18:00 到今天 18:00」：
  /// 不管使用者是早上八點開 App 還是深夜十一點開，上一段睡眠都會落在
  /// 視窗裡。固定日界的話，深夜查詢會查到還沒發生的今晚。
  Future<LightsOutResult> lightsOut({
    Duration window = kLightsOutWindow,
    int minQuietMinutes = kMinQuietMinutes,
    DateTime? now,
  }) async {
    if (!isSupported) {
      return const LightsOutResult(LightsOutStatus.unsupported);
    }

    if (!await hasAccess()) {
      return const LightsOutResult(LightsOutStatus.permissionRequired);
    }

    final end = now ?? DateTime.now();
    final start = end.subtract(window);

    try {
      final events = await interactionEvents(start: start, end: end);

      // ⚠️ 原生端筆數超過上限時會**丟掉最舊的**，而昨晚睡覺那段正好在最舊
      // 的那一半。實機上這件事真的發生過（上限 2000、24 小時有 4057 筆），
      // 結果是「偵測不到就寢時刻」——看起來完全正常的錯誤答案。
      //
      // 上限已經拉到有餘裕，但真的又撞到時要**把視窗起點夾到第一筆事件**：
      // 那之前的資料我們沒有，宣稱查過等於拿半截資料算出一個像真的答案。
      // 夾住之後，「視窗開頭的空白不算安靜期」那條規則就會自然接手。
      final truncated = events.length >= kMaxInteractionEvents;
      final effectiveStart =
          truncated && events.isNotEmpty ? events.first.timestamp : start;

      final result = detectLightsOut(
        events,
        windowStart: effectiveStart,
        windowEnd: end,
        minQuietMinutes: minQuietMinutes,
      );

      // ⚠️ 這一行不是暫時的除錯輸出，請不要順手刪掉。
      //
      // 這個功能會不會運作，取決於**這支手機給不給 keyguard 事件**——
      // 而給不給是看不出來的：畫面上「偵測不到就寢時刻」跟「這支手機
      // 只能跑退化模式」長得一模一樣。第一次實機測試就是卡在這裡：
      // 演算法對、資料錯，但沒有任何跡象指向資料。
      //
      // 印的是型別分布而不是逐筆事件，因為要判斷的就是「有沒有收到
      // keyguard_hidden」；逐筆會有幾千行，也會把使用者用了哪些 App
      // 寫進 logcat。
      final histogram = <String, int>{};
      for (final e in events) {
        histogram[e.type] = (histogram[e.type] ?? 0) + 1;
      }
      debugPrint(
        'LightsOut[${result.mode.name}] ${result.status.name} '
        'raw=${events.length} used=${result.eventCount} '
        'quiet=${result.quietMinutes}m at=${result.at} $histogram',
      );

      return result;
    } on PlatformException catch (e) {
      return LightsOutResult(LightsOutStatus.failed, error: e.message);
    } on MissingPluginException {
      return const LightsOutResult(LightsOutStatus.unsupported);
    }
  }

  /// 昨天一整天。
  ///
  /// ⚠️ 刻意用「昨天」而不是「今天」，有兩個理由：
  /// 1. 當天的桶還在累積中，數字會隨著使用一直變，跨天比較沒有意義
  /// 2. 這張卡跟 Insights 上「昨晚的睡眠」放在一起，期間要對得上——
  ///    配今天的手機使用等於把兩個不同時期的東西並排
  Future<UsageStatsResult> queryYesterday({int limit = 5}) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return query(
      start: todayStart.subtract(const Duration(days: 1)),
      end: todayStart,
      limit: limit,
    );
  }
}
