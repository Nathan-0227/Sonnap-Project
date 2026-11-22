import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/metrics.dart';
import '../models/sleep_session.dart';
import '../models/status.dart';
import '../models/yesterday_activity.dart';
import 'morning_report.dart' show scoredEfficiency;
import 'sleep_repository.dart';

/// 首頁、助理頁、計畫頁的「最近一晚」（2026-11-22 使用者 grill 定，甲-2）。
///
/// 打包檔（`/get-sleep-data`）只有早上匯入時才更新；手錶資料由 Health Connect 先到時，資料庫已經有
/// 今天那一晚，打包檔還停在昨天——首頁整塊（寵物、分數卡、兩欄、Sleep Stages）講的是前一晚，
/// 助理（讀 `/home`）講的是今天，同一隻寵物兩種心情（11-22 手機上看到 Feeling happy／tired mood）。
///
/// 做法：打包檔照舊給 30 晚的歷史；`/home` 那一晚比打包檔最後一晚新（或同一晚）就蓋上去
/// （[mergeLatestNight]）。「跟上一晚比」、一週長條、一週心情列都看歷史，所以自動跟上。
///
/// - 哪一晚：今天日曆日；那一晚手錶、手機都沒有資料就退回前一晚，**只退一晚**（同首頁日記本）。
/// - 最多等 [LatestNightRepository.wait]（3 秒），等不到或連不到後端就用打包檔（設定頁照實標來源）。
/// - 三頁共用同一份結果；打開 App、回到前景、關掉早晨報告之後 [LatestNightRepository.refresh]。

String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// `/home` 那一晚有沒有資料：手錶有分數，或有放下手機的時刻。
bool homeHasNight(Map<String, dynamic>? home) {
  if (home == null) return false;
  return _map(home['scoring'])['final_score'] != null ||
      _map(home['behavior'])['lights_out_at'] != null;
}

/// 問哪一晚：今天；沒資料就前一晚（只退一晚）。都沒有回 null。
Future<Map<String, dynamic>?> fetchLatestNight(
  Future<Map<String, dynamic>?> Function(String date) fetch,
  DateTime now,
) async {
  final today = DateTime(now.year, now.month, now.day);
  for (final d in [today, today.subtract(const Duration(days: 1))]) {
    final home = await fetch(_day(d));
    if (homeHasNight(home)) return home;
  }
  return null;
}

/// 把 `/home` 那一晚蓋到打包檔的最近一晚上。**純函式。**
///
/// - 比打包檔最後一晚舊 → 原樣回傳（打包檔比較新，不倒退）。
/// - 同一晚 → 換掉那一格；比較新 → 接在後面。之前的晚上一格都不動（「跟上一晚比」比的是它們）。
/// - 效率照舊是**進分數的那一個**：同早晨報告，依 composition.efficiency_basis 去 behavior 找（[scoredEfficiency]）。
/// - Activity：`/home` 的 yesterday；沒有的話，只有同一晚才沿用打包檔那份（別晚的前一天不能冒充）。
SleepSession mergeLatestNight(SleepSession base, Map<String, dynamic> home) {
  final date = home['date'] as String?;
  if (date == null) return base;
  final last = base.history.isEmpty ? null : base.history.last.date;
  if (last != null && date.compareTo(last) < 0) return base;

  final scoring = _map(home['scoring']);
  final behavior = _map(home['behavior']);
  final status = _map(home['status']);
  final metrics = _map(home['metrics']);
  final composition = _map(scoring['composition']);
  final basis = composition['efficiency_basis'] as String?;
  metrics['scored_efficiency'] = scoredEfficiency(basis, behavior, metrics);
  metrics['scored_efficiency_basis'] = basis;
  metrics['scored_efficiency_label'] = composition['efficiency_label'];

  final minutes = (metrics['sleep_duration_minutes'] as num?)?.toDouble();
  final entry = HistoryEntry.fromJson({
    'date': date,
    'final_score': scoring['final_score'],
    'final_quality': scoring['final_quality'],
    'sleep_duration_hours': minutes == null ? null : minutes / 60,
    'sleep_efficiency': metrics['sleep_efficiency'],
    'deep_minutes': metrics['deep_minutes'],
    'scored_efficiency': metrics['scored_efficiency'],
    'scored_efficiency_basis': basis,
    'scored_efficiency_label': metrics['scored_efficiency_label'],
    'sleep_start_time': metrics['sleep_start_time'],
    'wake_time': metrics['wake_time'],
    'pet_mood': status['pet_mood'],
    'mood_reason': status['mood_reason'],
    'composition': scoring['composition'],
  });

  return SleepSession(
    schemaVersion: base.schemaVersion,
    sessionId: base.sessionId,
    status: Status.fromJson(status),
    metrics: Metrics.fromJson(metrics),
    aiContent: base.aiContent,
    scoring: Scoring.fromJson(scoring),
    display: home['display'] is Map ? Display.fromJson(_map(home['display'])) : base.display,
    streak: base.streak,
    history: [...base.history.where((e) => e.date != date), entry],
    dataSources: base.dataSources,
    disclaimer: base.disclaimer,
    timestamp: base.timestamp,
    activity: YesterdayActivity.fromJsonOrNull(home['yesterday']) ?? (last == date ? base.activity : null),
  );
}

/// 打包檔＋`/home` 最近一晚。三頁共用一個實例（main.dart），[refresh] 之後大家一起換。
///
/// ⚠️ 設定頁「Data」看的是包在裡面的 [base]（FallbackSleepRepository），這一層不改來源的判斷。
class LatestNightRepository extends ChangeNotifier implements SleepRepository {
  LatestNightRepository({
    required this.base,
    required this.fetchNight,
    DateTime Function()? clock,
    this.wait = const Duration(seconds: 3),
  }) : clock = clock ?? DateTime.now;

  final SleepRepository base;

  /// `GET /home?date=`；沒有後端或還沒有帳號回 null。
  final Future<Map<String, dynamic>?> Function(String date) fetchNight;
  final DateTime Function() clock;
  final Duration wait;

  Future<SleepSession>? _current;

  @override
  Future<SleepSession> load() {
    final f = _current ??= _load();
    // 失敗的不留著：下一次（例如首頁的 Retry）要重讀
    f.then((_) {}, onError: (_) {
      if (identical(_current, f)) _current = null;
    });
    return f;
  }

  Future<SleepSession> _load() async {
    final session = base.load();
    Map<String, dynamic>? home;
    try {
      home = await fetchLatestNight(fetchNight, clock()).timeout(wait);
    } catch (_) {
      home = null; // 等不到、連不到：用打包檔
    }
    final s = await session;
    return home == null ? s : mergeLatestNight(s, home);
  }

  /// 重讀一次（回到前景、關掉早晨報告之後），聽的人（首頁、助理頁）跟著換。
  void refresh() {
    _current = null;
    notifyListeners();
  }
}
