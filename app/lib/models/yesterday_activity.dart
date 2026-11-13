import 'night_curve.dart';

/// 早晨報告「Yesterday」那一塊：前一個日曆日的 Garmin 白天資料（`/home` 的 `yesterday`）。
///
/// ⚠️ **全部照抄後端**，Dart 不算、不判斷：沒有「達標」、沒有 Good/Normal、
///    壓力不加說明也不變色（2026-11-13 使用者定）。只呈現、不計分。
/// ⚠️ 後端整塊是 null → 報告整塊不畫；單一項是 null → 那一項不畫（不畫成 0）。
class YesterdayActivity {
  /// 那個日曆日（YYYY-MM-DD）。
  final String date;
  final int? steps;
  final int? stepGoal;
  final int? distanceM;
  final int? activeKcal;
  final double? floorsUp;

  final int? highlyActiveSec;
  final int? activeSec;
  final int? sedentarySec;

  final int? stressRestSec;
  final int? stressLowSec;
  final int? stressMediumSec;
  final int? stressHighSec;

  final int? bodyBatteryCharged;
  final int? bodyBatteryDrained;

  /// 最近一次量到的 VO2 max（後端只給 90 天內的）與量到的日期。
  final double? vo2max;
  final String? vo2maxMeasuredOn;

  /// Move IQ 偵測到的走路／騎車。null = 沒抓到；空 = 那天沒有。
  final List<MoveIqEvent>? moveIq;

  /// 那天整天的心率（首頁 Activity 卡，只有打包檔帶）：最低、最高、每 10 分鐘的曲線。
  /// ⚠️ 不判斷 Normal／High；也算不出 HRV（手錶只存 2 分鐘平均，沒有每一下心跳的間隔）。
  final NightCurve? dayHeartRate;

  /// 那天的靜止心率（Garmin 每天一個數字）。
  final int? restingHeartRate;

  /// 最近幾天的步數、活動卡路里、活動分鐘（首頁點小卡開的長條圖用）。
  final List<ActivityHistoryDay> history;

  const YesterdayActivity({
    required this.date,
    this.steps,
    this.stepGoal,
    this.distanceM,
    this.activeKcal,
    this.floorsUp,
    this.highlyActiveSec,
    this.activeSec,
    this.sedentarySec,
    this.stressRestSec,
    this.stressLowSec,
    this.stressMediumSec,
    this.stressHighSec,
    this.bodyBatteryCharged,
    this.bodyBatteryDrained,
    this.vo2max,
    this.vo2maxMeasuredOn,
    this.moveIq,
    this.dayHeartRate,
    this.restingHeartRate,
    this.history = const [],
  });

  /// 活動時間（高強度＋活動）的分鐘數。兩個都沒有是 null。
  int? get activeMinutes {
    if (highlyActiveSec == null && activeSec == null) return null;
    return (((highlyActiveSec ?? 0) + (activeSec ?? 0)) / 60).round();
  }

  bool get hasActivity =>
      highlyActiveSec != null || activeSec != null || sedentarySec != null;

  bool get hasStress =>
      stressRestSec != null ||
      stressLowSec != null ||
      stressMediumSec != null ||
      stressHighSec != null;

  bool get hasBodyBattery =>
      bodyBatteryCharged != null || bodyBatteryDrained != null;

  /// 四張小卡（步數、活動卡路里、爬樓、VO2 max）至少一張有值。
  bool get hasTiles =>
      steps != null || activeKcal != null || floorsUp != null || vo2max != null;

  static YesterdayActivity? fromJsonOrNull(Object? raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    final date = j['date'];
    if (date is! String) return null;
    int? i(Map? m, String k) => (m?[k] as num?)?.round();
    final activity = j['activity'] as Map?;
    final stress = j['stress'] as Map?;
    final bb = j['body_battery'] as Map?;
    final vo2 = j['vo2max'] as Map?;
    List<MoveIqEvent>? moves;
    final rawMoves = j['move_iq'];
    if (rawMoves is List) {
      moves = [for (final e in rawMoves) ?MoveIqEvent.fromJsonOrNull(e)];
    }
    return YesterdayActivity(
      date: date,
      steps: i(j, 'steps'),
      stepGoal: i(j, 'step_goal'),
      distanceM: i(j, 'distance_m'),
      activeKcal: i(j, 'active_kcal'),
      floorsUp: (j['floors_up'] as num?)?.toDouble(),
      highlyActiveSec: i(activity, 'highly_active_sec'),
      activeSec: i(activity, 'active_sec'),
      sedentarySec: i(activity, 'sedentary_sec'),
      stressRestSec: i(stress, 'rest_sec'),
      stressLowSec: i(stress, 'low_sec'),
      stressMediumSec: i(stress, 'medium_sec'),
      stressHighSec: i(stress, 'high_sec'),
      bodyBatteryCharged: i(bb, 'charged'),
      bodyBatteryDrained: i(bb, 'drained'),
      vo2max: (vo2?['value'] as num?)?.toDouble(),
      vo2maxMeasuredOn: vo2?['measured_on'] as String?,
      moveIq: moves,
      dayHeartRate: NightCurve.fromJsonOrNull(j['heart_rate']),
      restingHeartRate: ((j['heart_rate'] as Map?)?['resting'] as num?)?.round(),
      history: [
        for (final h in (j['history'] as List?) ?? const [])
          ?ActivityHistoryDay.fromJsonOrNull(h),
      ],
    );
  }
}

/// 一段 Move IQ：走路或騎車，幾點開始、幾分鐘。
class MoveIqEvent {
  final String type;

  /// 牆鐘時間「HH:MM」（後端照抄 Garmin 的 local 時間，不換時區）。
  final String start;
  final int minutes;

  const MoveIqEvent({
    required this.type,
    required this.start,
    required this.minutes,
  });

  /// 從午夜起算的分鐘數（時間軸用）。格式不對回 null。
  int? get startMinuteOfDay {
    final parts = start.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  static MoveIqEvent? fromJsonOrNull(Object? raw) {
    if (raw is! Map) return null;
    final type = raw['type'];
    final start = raw['start'];
    final minutes = raw['minutes'];
    if (type is! String || start is! String || minutes is! num) return null;
    return MoveIqEvent(type: type, start: start, minutes: minutes.round());
  }
}

/// 一天的步數、活動卡路里、活動分鐘（首頁點小卡開的最近 7 天長條圖）。
class ActivityHistoryDay {
  final String date;
  final int? steps;
  final int? activeKcal;
  final int? activeMinutes;

  const ActivityHistoryDay({
    required this.date,
    this.steps,
    this.activeKcal,
    this.activeMinutes,
  });

  static ActivityHistoryDay? fromJsonOrNull(Object? raw) {
    if (raw is! Map || raw['date'] is! String) return null;
    return ActivityHistoryDay(
      date: raw['date'] as String,
      steps: (raw['steps'] as num?)?.round(),
      activeKcal: (raw['active_kcal'] as num?)?.round(),
      activeMinutes: (raw['active_minutes'] as num?)?.round(),
    );
  }
}
