import 'package:flutter/foundation.dart';

import 'wall_clock.dart';

/// 一晚的睡眠階段時間軸（後端 `metrics.sleep_stages`，2026-11-12 加）。
/// **只呈現、不計分。**
///
/// - [segments] 只用來畫曲線（後端從原始資料還原，118 晚中 116 晚與手錶總數差 2 分鐘內）。
/// - [minutes] 是圖例的數字，**用手錶自己的總數**，所以圖例與曲線可能差幾分鐘，以圖例為準。
/// - [remMeasured] 為 false 時那晚手錶沒量到 REM：不畫 REM 那一層，圖例寫 not measured。
@immutable
class SleepStages {
  final List<StageSegment> segments;
  final int? awakeMinutes;
  final int? remMinutes;
  final int? lightMinutes;
  final int? deepMinutes;
  final bool remMeasured;

  const SleepStages({
    required this.segments,
    this.awakeMinutes,
    this.remMinutes,
    this.lightMinutes,
    this.deepMinutes,
    this.remMeasured = true,
  });

  /// 沒有這個區塊（舊版後端、API 路徑）或格式不對時回 null，畫面就不畫這張卡。
  static SleepStages? fromJsonOrNull(dynamic raw) {
    if (raw is! Map) return null;
    final json = raw.cast<String, dynamic>();
    final segs = <StageSegment>[];
    for (final s in (json['segments'] as List?) ?? const []) {
      if (s is! Map) continue;
      final start = parseWallClock(s['start']);
      final end = parseWallClock(s['end']);
      final stage = s['stage'] as String?;
      if (start == null || end == null || stage == null) continue;
      if (!end.isAfter(start)) continue;
      segs.add(StageSegment(stage, start, end));
    }
    if (segs.isEmpty) return null;
    final m = (json['minutes'] as Map?)?.cast<String, dynamic>() ?? const {};
    int? n(String k) => (m[k] as num?)?.round();
    return SleepStages(
      segments: segs,
      awakeMinutes: n('awake'),
      remMinutes: n('rem'),
      lightMinutes: n('light'),
      deepMinutes: n('deep'),
      remMeasured: json['rem_measured'] as bool? ?? true,
    );
  }

  DateTime get start => segments.first.start;
  DateTime get end => segments.last.end;
}

@immutable
class StageSegment {
  /// awake / rem / light / deep
  final String stage;
  final DateTime start;
  final DateTime end;
  const StageSegment(this.stage, this.start, this.end);
}
