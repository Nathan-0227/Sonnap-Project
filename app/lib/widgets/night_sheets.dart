import 'package:flutter/material.dart';

import '../services/camera_insights.dart';
import '../services/morning_report.dart';
import '../services/night_compare.dart';
import '../services/report_loader.dart';
import '../theme/report_style.dart';
import 'awake_week_sheet.dart';
import 'deep_sheet.dart';
import 'efficiency_sheet.dart';
import 'night_week.dart';
import 'score_sheet.dart';
import 'sleep_week_sheet.dart';

/// 「這一晚的某個詳細頁」只有這一份（2026-11-21）：早晨報告（含 Insights 的 Day）與首頁都從這裡開。
///
/// ⚠️ 這幾頁原本寫在報告畫面裡（私有方法），首頁點同一個量開的是另一個長條圖頁——
///    同一個量兩頁、兩邊說的不一樣。搬到這裡之後兩邊都呼叫同一支，一週資料也從同一個 [ReportLoader] 來。
/// ⚠️ 這一晚的數字一律以 [MorningReport] 為準（後端 `/home?date=` 組的），一週資料只有後端有，
///    這一晚那一欄用報告上的數字蓋過去，保證跟格子一樣。
class NightSheets {
  final MorningReport r;
  final Future<List<NightValue>> Function()? loadSleepSeries;
  final Future<Map<String, double>?> Function()? loadAwakeMinutes;
  final Future<Map<String, int>?> Function()? loadAwakeCounts;
  final Future<Map<String, EfficiencyNight>?> Function()? loadEfficiencyNights;
  final Future<Map<String, WearableNight>?> Function()? loadWearableNights;

  const NightSheets(
    this.r, {
    this.loadSleepSeries,
    this.loadAwakeMinutes,
    this.loadAwakeCounts,
    this.loadEfficiencyNights,
    this.loadWearableNights,
  });

  NightSheets.fromLoader(this.r, ReportLoader loader)
      : loadSleepSeries = loader.sleepSeries,
        loadAwakeMinutes = loader.awakeMinutes,
        loadAwakeCounts = loader.awakeCounts,
        loadEfficiencyNights = loader.efficiencyNights,
        loadWearableNights = loader.wearableNights;

  // 標題的顏色跟報告格子同一個（使用者定：點開的頁跟外面那張卡同圖示同顏色）
  static const asleepColor = Color(0xFFB9A6FF);
  static const effColor = Color(0xFF7EC8FF);
  static const awakeColor = Color(0xFFFFC27A);
  static const remColor = Color(0xFFC9A7FF);

  bool get canTotalSleep => r.hasScore && r.sleepMinutes != null && loadSleepSeries != null;
  bool get canEfficiency => r.hasScore && r.efficiency != null;
  bool get canAwake => r.hasScore && r.wasoMinutes != null;
  bool get canDeep => r.hasScore && r.deepMinutes != null;
  bool get canScore => r.hasScore;

  /// 「Sat, Nov 21」。自己組，不跟手機語言走（同 reportDateTitle）。
  static String shortDate(String date) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = DateTime.parse(date);
    return '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }

  static Color? _hex(String? s) {
    if (s == null) return null;
    final v = int.tryParse(s.replaceFirst('#', ''), radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }

  Future<Map<String, WearableNight>?> _wearable() async {
    try {
      return await loadWearableNights?.call();
    } catch (_) {
      return null;
    }
  }

  // ── 分數 ─────────────────────────────────────────────────────

  Future<void> score(BuildContext context) async {
    if (!canScore) return;
    final nights = await _wearable();
    MedianWeek? week;
    var colors = <Color?>[];
    if (nights != null && nights.isNotEmpty) {
      final values = <String, double>{
        for (final e in nights.entries)
          if (e.value.score != null) e.key: e.value.score!,
        r.date: r.score!,
      };
      week = medianWeek(values, r.date);
      colors = [
        for (final (date, _) in week.nights)
          date == r.date
              ? _hex(r.qualityColor)
              : _hex(nights[date]?.scoreColor),
      ];
    }
    if (!context.mounted) return;
    // 分數頁點列再開別頁：先收掉分數頁，避免一層疊一層（返回就回到原本那一頁）
    void open(Future<void> Function(BuildContext) f) {
      Navigator.of(context).pop();
      f(context);
    }

    await showScoreSheet(
      context,
      fontFamily: kReportFont,
      dateTitle: shortDate(r.date),
      score: r.score!,
      quality: r.quality,
      qualityColor: _hex(r.qualityColor),
      week: week,
      weekColors: colors,
      rows: [
        ScoreRow(
          id: 'sleep',
          name: 'Total sleep',
          color: asleepColor,
          value: r.sleepMinutes == null ? null : reportHm(r.sleepMinutes!),
          onTap: canTotalSleep ? () => open(totalSleep) : null,
        ),
        ScoreRow(
          id: 'efficiency',
          name: 'Efficiency',
          color: effColor,
          value: r.efficiency == null ? null : '${effNumber(r.efficiency!)}%',
          note: r.efficiencyLabel,
          onTap: canEfficiency ? () => open(efficiency) : null,
        ),
        ScoreRow(
          id: 'awake',
          name: 'Awake',
          color: awakeColor,
          value: r.wasoMinutes == null ? null : reportHm(r.wasoMinutes!),
          onTap: canAwake ? () => open(awake) : null,
        ),
        ScoreRow(
          id: 'deep',
          name: 'Deep sleep',
          color: kDeepColor,
          value: r.deepMinutes == null ? null : reportHm(r.deepMinutes!),
          onTap: canDeep ? () => open(deep) : null,
        ),
        // REM 沒有自己的詳細頁；沒量到寫 N/A（不寫 0m，0m 會被讀成整晚沒有 REM）
        ScoreRow(
          id: 'rem',
          name: 'REM',
          color: remColor,
          value: r.remMinutes == null ? null : reportHm(r.remMinutes!),
          notMeasured: !r.remMeasured,
        ),
      ],
    );
  }

  // ── 深睡 ─────────────────────────────────────────────────────

  Future<void> deep(BuildContext context) async {
    if (!canDeep) return;
    final nights = await _wearable();
    MedianWeek? week;
    if (nights != null && nights.isNotEmpty) {
      week = medianWeek({
        for (final e in nights.entries)
          if (e.value.deepMinutes != null) e.key: e.value.deepMinutes!,
        r.date: r.deepMinutes!,
      }, r.date);
    }
    if (!context.mounted) return;
    await showDeepSheet(
      context,
      fontFamily: kReportFont,
      dateTitle: shortDate(r.date),
      deepMinutes: r.deepMinutes!,
      sleepMinutes: r.sleepMinutes,
      stages: r.stages,
      heartRate: r.heartRate,
      week: week,
    );
  }

  // ── 以下三頁原本在 morning_report_screen.dart（搬過來，內容不變）──────────

  /// Total sleep 點開。這一晚以報告為準；一週是打包檔的 history。
  Future<void> totalSleep(BuildContext context) async {
    if (!canTotalSleep) return;
    List<NightValue> series;
    try {
      series = await loadSleepSeries!();
    } catch (_) {
      series = const [];
    }
    final mine = r.hasScore ? r.sleepMinutes : null;
    if (mine != null) {
      series = [
        for (final n in series)
          if (n.date != r.date) n,
        NightValue(r.date, mine.toDouble()),
      ];
    }
    if (!context.mounted) return;
    await showSleepWeekSheet(
      context,
      title: 'Total sleep',
      // 標題跟這張格子同一個圖示、同一個顏色（使用者定）
      icon: Icons.nightlight_round,
      color: asleepColor,
      fontFamily: kReportFont,
      series: series,
      endDate: r.date,
      goalMinutes: r.goalMinutes,
    );
  }

  /// Efficiency 點開。這一晚的數字、種類、名字都以報告上的為準（同一支 scoredEfficiency 挑的）；
  /// 一週只有後端有，這一晚那根長條用報告上的數字蓋過去，保證跟格子一樣。
  Future<void> efficiency(BuildContext context) async {
    if (!canEfficiency) return;
    Map<String, EfficiencyNight>? week;
    try {
      final m = await loadEfficiencyNights?.call();
      if (m != null && m.isNotEmpty) {
        week = {
          ...m,
          if (r.efficiencyKind != null)
            r.date: EfficiencyNight(
              r.efficiency!,
              r.efficiencyKind!,
              r.efficiencyLabel,
            ),
        };
      }
    } catch (_) {}
    if (!context.mounted) return;
    await showEfficiencySheet(
      context,
      color: effColor,
      fontFamily: kReportFont,
      date: r.date,
      value: r.efficiency!,
      label: r.efficiencyLabel,
      kind: r.efficiencyKind,
      // 11-15 使用者定：點開不放警語（上面「asleep of counted」已經說明怎麼算的）
      asleepMinutes: r.sleepMinutes,
      span: countedSpan(
        r.efficiencyKind,
        bedStart: r.bedStart,
        bedEnd: r.bedEnd,
        asleepAt: r.asleepAt,
        wokeAt: r.wokeAt,
      ),
      week: week,
    );
  }

  /// Awake 點開。這一晚以報告為準；一週是後端 /insights。
  Future<void> awake(BuildContext context) async {
    if (!canAwake) return;
    List<NightValue>? series;
    try {
      final m = await loadAwakeMinutes?.call();
      if (m != null && m.isNotEmpty) {
        series = [
          for (final e in m.entries)
            if (e.key != r.date) NightValue(e.key, e.value),
          NightValue(r.date, r.wasoMinutes!.toDouble()),
        ];
      }
    } catch (_) {}
    Map<String, int>? counts;
    try {
      final c = await loadAwakeCounts?.call();
      if (c != null) {
        counts = {...c, if (r.awakeCount != null) r.date: r.awakeCount!};
      }
    } catch (_) {}
    if (!context.mounted) return;
    await showAwakeSheet(
      context,
      title: 'Awake',
      icon: Icons.visibility_rounded,
      color: awakeColor,
      fontFamily: kReportFont,
      date: r.date,
      totalMinutes: r.wasoMinutes!.toDouble(),
      // 醒了幾段：報告上的優先（/home 剛算好的），沒有才用一週那份
      count: r.awakeCount ?? counts?[r.date],
      counts: counts,
      stages: r.stages,
      series: series,
    );
  }
}
