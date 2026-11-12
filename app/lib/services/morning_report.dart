import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/sleep_session.dart';
import '../models/sleep_stages.dart';
import '../models/wall_clock.dart';
import 'bed_marks.dart';
import 'user_identity.dart';

/// 早晨報告（2026-11-12 定案）：滑完 Slide to get up 立刻出現，
/// 或從首頁一週心情列點某一天打開。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 報告上每個「好不好」的東西都照抄後端
/// ═══════════════════════════════════════════════════════════════════
///
/// 分數、等級、心情、那句話（`display.mood_description`）一律來自 `/home?date=`；
/// 連不到後端時退回打包檔裡那一晚的 history。**Dart 一個都不推**——
/// 心情要是從 [finalQuality] 推，Good 但 anxious 的夜晚就會畫錯寵物。
///
/// ⚠️ **沒有分數時不顯示睡眠長度也不顯示分數**，只寫
/// [kWaitingForWatch]。剛起床時手錶資料幾乎一定還沒到，
/// 那時畫 0 或畫上一晚的數字都是編造。
///
/// ⚠️ 心情只在有分數時才用（使用者定：還在等資料時畫睡姿小狗）。
const String kWaitingForWatch = 'Waiting for your watch data';

/// 不是剛結束的那一晚、又沒有分數時的說法。
const String kNoWatchData = 'No watch data for this night yet';

/// 資料從哪來。畫面上會照實標出來。
enum ReportSource {
  /// 後端 `/home?date=`
  backend,

  /// 連不到後端，用的是打包在 App 裡的那一晚
  bundled,

  /// 只有手機上的上床／下床時間
  phoneOnly,
}

@immutable
class MorningReport {
  /// 那一晚的日期（起床日，與後端 night_date 同一個約定），YYYY-MM-DD。
  final String date;

  /// 上床／下床（按鈕）。沒按就是 null。
  final DateTime? bedStart;
  final DateTime? bedEnd;

  /// 手錶認定的入睡／起床。沒有按鈕時，畫面改顯示這一對（標成 Asleep）。
  final DateTime? asleepAt;
  final DateTime? wokeAt;

  final double? score;
  final String? quality;

  /// 後端給的等級顏色（#RRGGBB）。打包檔的舊夜晚沒有，畫面用預設色。
  final String? qualityColor;

  /// 後端的那句話（`display.score_message`，例：Great job!）。
  final String? scoreMessage;

  /// 後端的心情與那句心情說明（`display.mood_description`）。
  final String? mood;
  final String? moodDescription;

  /// 手錶量到的睡眠（分鐘）與三個階段。淺睡只有量到 REM 時才有（後端定）。
  final double? sleepMinutes;
  final double? lightMinutes;
  final double? deepMinutes;
  final double? remMinutes;
  final bool remMeasured;

  /// Sleep Stages 圖。只有打包檔最新那一晚有（`metrics.sleep_stages`）。
  final SleepStages? stages;

  /// 夢境日記。只有打包檔最新那一晚有，而且是電腦上生成的，早上通常還沒有。
  final String? dream;

  final ReportSource source;

  const MorningReport({
    required this.date,
    this.bedStart,
    this.bedEnd,
    this.asleepAt,
    this.wokeAt,
    this.score,
    this.quality,
    this.qualityColor,
    this.scoreMessage,
    this.mood,
    this.moodDescription,
    this.sleepMinutes,
    this.lightMinutes,
    this.deepMinutes,
    this.remMinutes,
    this.remMeasured = false,
    this.stages,
    this.dream,
    this.source = ReportSource.phoneOnly,
  });

  /// 有分數才算「手錶資料到了」。
  bool get hasScore => score != null;

  /// 比例條要三個都有（淺睡由後端決定給不給）。
  bool get hasStageSplit =>
      lightMinutes != null && deepMinutes != null && remMinutes != null;
}

/// 日期 → YYYY-MM-DD。
String reportDateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 把三個來源併成一份報告。**純函式**，測試直接打這支。
///
/// - [marks]：手機上的上床／下床。只在它屬於 [date] 那一晚時採用。
/// - [home]：`GET /home?date=` 的整份回應；null 代表沒有後端或連不到。
/// - [session]：打包檔。[home] 是 null 時用它那一晚的 history；
///   Sleep Stages 與夢境只在它最新那一晚就是 [date] 時才用。
MorningReport buildMorningReport({
  required String date,
  BedMarks? marks,
  Map<String, dynamic>? home,
  SleepSession? session,
}) {
  DateTime? bedStart;
  DateTime? bedEnd;
  final start = marks?.startAt;
  if (start != null && reportDateKey(nightDateOf(start)) == date) {
    bedStart = start;
    bedEnd = marks?.endAt;
  }

  // 打包檔最新那一晚就是這一晚 → 才拿它的 Sleep Stages 與夢境
  final latest = session != null && session.history.isNotEmpty
      ? session.history.last
      : null;
  final sameNightAsBundle = latest != null && latest.date == date;
  final stages = sameNightAsBundle ? session!.metrics.sleepStages : null;
  final dream = sameNightAsBundle && session!.aiContent.hasDream
      ? session.aiContent.dreamSummary
      : null;

  if (home != null && home['date'] == date) {
    final behavior = (home['behavior'] as Map?)?.cast<String, dynamic>();
    final metrics = (home['metrics'] as Map?)?.cast<String, dynamic>();
    final scoring = (home['scoring'] as Map?)?.cast<String, dynamic>();
    final status = (home['status'] as Map?)?.cast<String, dynamic>();
    final display = (home['display'] as Map?)?.cast<String, dynamic>();
    final score = (scoring?['final_score'] as num?)?.toDouble();
    double? n(String k) => (metrics?[k] as num?)?.toDouble();
    return MorningReport(
      date: date,
      bedStart: bedStart ?? parseWallClock(behavior?['bed_start_at']),
      bedEnd: bedStart != null
          ? bedEnd
          : parseWallClock(behavior?['bed_end_at']),
      asleepAt: parseWallClock(metrics?['sleep_start_time']),
      wokeAt: parseWallClock(metrics?['wake_time']),
      score: score,
      quality: score == null ? null : scoring?['final_quality'] as String?,
      qualityColor: score == null ? null : display?['score_color'] as String?,
      scoreMessage: score == null ? null : display?['score_message'] as String?,
      // ⚠️ 心情與那句話只在有分數時用：沒分數時後端的心情是行為驅動的，
      //    而使用者定的是「還在等資料就畫睡姿小狗」。
      mood: score == null ? null : status?['pet_mood'] as String?,
      moodDescription:
          score == null ? null : display?['mood_description'] as String?,
      sleepMinutes: score == null ? null : n('sleep_duration_minutes'),
      lightMinutes: score == null ? null : n('light_minutes'),
      deepMinutes: score == null ? null : n('deep_minutes'),
      remMinutes: score == null ? null : n('rem_minutes'),
      remMeasured: scoring?['rem_measured'] == true,
      stages: score == null ? null : stages,
      dream: dream,
      source: ReportSource.backend,
    );
  }

  // 沒有後端 → 打包檔裡那一晚
  HistoryEntry? entry;
  for (final e in session?.history ?? const <HistoryEntry>[]) {
    if (e.date == date) entry = e;
  }
  if (entry != null && entry.finalScore != null) {
    final hours = entry.sleepDurationHours;
    return MorningReport(
      date: date,
      bedStart: bedStart,
      bedEnd: bedEnd,
      asleepAt: parseWallClock(entry.bedtime),
      wokeAt: parseWallClock(entry.wakeTime),
      score: entry.finalScore,
      quality: entry.finalQuality,
      // 打包檔只有最新那一晚有 display；舊夜晚就不放那兩句話
      qualityColor: sameNightAsBundle ? session!.display.scoreColor : null,
      scoreMessage: sameNightAsBundle ? session!.display.scoreMessage : null,
      mood: entry.petMood,
      moodDescription:
          sameNightAsBundle ? session!.display.moodDescription : null,
      sleepMinutes: hours == null ? null : hours * 60,
      deepMinutes: entry.deepMinutes?.toDouble(),
      remMeasured: stages?.remMeasured ?? false,
      stages: stages,
      dream: dream,
      source: ReportSource.bundled,
    );
  }

  return MorningReport(
    date: date,
    bedStart: bedStart,
    bedEnd: bedEnd,
    dream: dream,
    source: ReportSource.phoneOnly,
  );
}

/// 讀 `/home?date=`。可以換成假的來測。
abstract class MorningReportSource {
  /// 成功回整份 JSON；沒有後端、沒有帳號、連不到都回 null。
  Future<Map<String, dynamic>?> fetchNight(String date);
}

class MorningReportService implements MorningReportSource {
  final String baseUrl;
  final UserIdentity identity;
  final Duration timeout;

  const MorningReportService({
    required this.baseUrl,
    required this.identity,
    this.timeout = const Duration(seconds: 4),
  });

  @override
  Future<Map<String, dynamic>?> fetchNight(String date) async {
    if (baseUrl.trim().isEmpty) return null;
    final userId = await identity.currentUserId();
    if (userId == null) return null;
    final uri = Uri.parse('$baseUrl/home').replace(queryParameters: {
      'user_id': userId,
      'date': date,
    });
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        // ⚠️ 不印 uri：query 帶著 user_id（憑證）。
        debugPrint('MorningReport: GET /home returned ${response.statusCode}');
        return null;
      }
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (error) {
      debugPrint('MorningReport: failed - $error');
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
