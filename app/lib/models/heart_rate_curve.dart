import 'wall_clock.dart';

/// 一晚睡著期間的心率曲線（`/home` 的 `metrics.heart_rate_curve`，2026-11-13）。
///
/// ⚠️ 全部照抄後端：平均、最低、最高是後端從睡著那一段的原始讀數算的
///    （不是 metrics.avg_heart_rate——那個混了清醒時段）。Dart 不重算、不判斷 Normal。
class HeartRateCurve {
  final List<HeartRatePoint> points;
  final int avg;
  final int min;
  final int max;

  const HeartRateCurve({
    required this.points,
    required this.avg,
    required this.min,
    required this.max,
  });

  static HeartRateCurve? fromJsonOrNull(Object? raw) {
    if (raw is! Map) return null;
    final rawPoints = raw['points'];
    final avg = raw['avg'];
    final min = raw['min'];
    final max = raw['max'];
    if (rawPoints is! List || avg is! num || min is! num || max is! num) {
      return null;
    }
    final points = <HeartRatePoint>[];
    for (final p in rawPoints) {
      if (p is! Map) continue;
      // ⚠️ 牆鐘時間：字串裡的 +08:00 照抄，不換成 UTC（同 parseWallClock）
      final t = parseWallClock(p['t']);
      final bpm = p['bpm'];
      if (t != null && bpm is num) {
        points.add(HeartRatePoint(t, bpm.toDouble()));
      }
    }
    if (points.length < 2) return null;
    return HeartRateCurve(
      points: points,
      avg: avg.round(),
      min: min.round(),
      max: max.round(),
    );
  }
}

class HeartRatePoint {
  final DateTime time;
  final double bpm;
  const HeartRatePoint(this.time, this.bpm);
}
