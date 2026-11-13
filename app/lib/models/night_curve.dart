import 'wall_clock.dart';

/// 一晚睡著期間的一條曲線：心率或手錶動作（`metrics.heart_rate_curve`／`movement_curve`，2026-11-13）。
/// Sleep Stages 卡上點 Heart rate／Movement 才疊上去。
///
/// ⚠️ 全部照抄後端：平均、最低、最高是後端從睡著那一段的原始讀數算的
///    （心率不是 metrics.avg_heart_rate——那個混了清醒時段）。Dart 不重算、不判斷 Normal。
/// ⚠️ 手錶動作沒有單位（約 0–4 的相對值），畫面只寫 More／Less。
class NightCurve {
  final List<NightCurvePoint> points;
  final double avg;
  final double min;
  final double max;

  const NightCurve({
    required this.points,
    required this.avg,
    required this.min,
    required this.max,
  });

  static NightCurve? fromJsonOrNull(Object? raw) {
    if (raw is! Map) return null;
    final rawPoints = raw['points'];
    final avg = raw['avg'];
    final min = raw['min'];
    final max = raw['max'];
    if (rawPoints is! List || avg is! num || min is! num || max is! num) {
      return null;
    }
    final points = <NightCurvePoint>[];
    for (final p in rawPoints) {
      if (p is! Map) continue;
      // ⚠️ 牆鐘時間：字串裡的 +08:00 照抄，不換成 UTC（同 parseWallClock）。
      //    parseWallClock 對「有時區標記」的字串回傳 isUtc 的牆鐘、對「沒有標記」的回傳本地時間——
      //    兩種放在一起比較會差 8 小時（2026-11-13 實機抓到攝影機那條被整條濾光）。
      //    這裡一律換成同一種（isUtc 的牆鐘），跟 Sleep Stages 的時間同一個基準。
      final parsed = parseWallClock(p['t']);
      final t = parsed == null || parsed.isUtc
          ? parsed
          : DateTime.utc(parsed.year, parsed.month, parsed.day, parsed.hour,
              parsed.minute, parsed.second);
      final v = p['value'];
      if (t != null && v is num) {
        points.add(NightCurvePoint(t, v.toDouble()));
      }
    }
    if (points.length < 2) return null;
    return NightCurve(
      points: points,
      avg: avg.toDouble(),
      min: min.toDouble(),
      max: max.toDouble(),
    );
  }
}

class NightCurvePoint {
  final DateTime time;
  final double value;
  const NightCurvePoint(this.time, this.value);
}
