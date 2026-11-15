import 'wall_clock.dart';

/// 早晨報告 Yesterday 的 **Awake HR**（2026-11-15 使用者定）：前一個日曆日**扣掉睡著**之後的心率。
///
/// - 平均、最高（含時刻）、各區間幾分鐘：**全部照抄後端**（`garmin/sleep_heart_rate.awake_heart_rate`）。
/// - 🔴 **不寫 Normal／High、不比「平常」、不放靜止心率與最低**：
///   `Research-Background/心率門檻.md` 查過，醒著的平均心率沒有結果關聯的切點，
///   它又主要取決於那天走了多少路。靜止心率在報告上半部已經有了。
/// - 區間是 Garmin Connect 裡本人的設定（最大心率 199 的 50–90%），不是文獻門檻，
///   畫面照寫「max 199」讓人知道是哪一把尺；**不說哪一區好**。
class AwakeHeartRate {
  final int avg;
  final int max;

  /// 最高那一筆原始讀數的牆鐘時刻。
  final DateTime? maxAt;

  /// 那天**全部**原始讀數（每 2 分鐘，含睡著那段），照時間排。
  final List<HrReading> readings;

  /// 睡著的時段（畫淡、寫 asleep）。
  final List<(DateTime, DateTime)> asleep;

  /// 各區間：[低於 1 區, 1 區, …, 5 區] 的分鐘數；沒有是 null。
  final List<int>? zoneMinutes;

  /// 區間下緣（5 個）與最大心率。
  final List<int>? zoneFloors;
  final int? zoneMax;

  const AwakeHeartRate({
    required this.avg,
    required this.max,
    this.maxAt,
    this.readings = const [],
    this.asleep = const [],
    this.zoneMinutes,
    this.zoneFloors,
    this.zoneMax,
  });

  bool isAsleep(DateTime t) =>
      asleep.any((s) => !t.isBefore(s.$1) && t.isBefore(s.$2));

  static AwakeHeartRate? fromJsonOrNull(Object? raw) {
    if (raw is! Map) return null;
    final avg = raw['avg'];
    final max = raw['max'];
    if (avg is! num || max is! num) return null;
    final readings = <HrReading>[];
    for (final r in (raw['readings'] as List?) ?? const []) {
      if (r is! Map) continue;
      final t = parseWallClock(r['t'] as String?);
      final v = r['value'];
      if (t != null && v is num && v > 0) readings.add(HrReading(t, v.round()));
    }
    readings.sort((a, b) => a.t.compareTo(b.t));
    final asleep = <(DateTime, DateTime)>[];
    for (final s in (raw['asleep'] as List?) ?? const []) {
      if (s is! Map) continue;
      final a = parseWallClock(s['start'] as String?);
      final b = parseWallClock(s['end'] as String?);
      if (a != null && b != null && b.isAfter(a)) asleep.add((a, b));
    }
    List<int>? minutes;
    List<int>? floors;
    int? zoneMax;
    final z = raw['zones'];
    if (z is Map) {
      final m = z['minutes'];
      final f = z['floors'];
      if (m is List && f is List && m.length == f.length + 1) {
        minutes = [for (final v in m) (v as num?)?.round() ?? 0];
        floors = [for (final v in f) (v as num).round()];
        zoneMax = (z['max'] as num?)?.round();
      }
    }
    return AwakeHeartRate(
      avg: avg.round(),
      max: max.round(),
      maxAt: parseWallClock(raw['max_at'] as String?),
      readings: readings,
      asleep: asleep,
      zoneMinutes: minutes,
      zoneFloors: floors,
      zoneMax: zoneMax,
    );
  }
}

class HrReading {
  final DateTime t;
  final int bpm;
  const HrReading(this.t, this.bpm);
}
