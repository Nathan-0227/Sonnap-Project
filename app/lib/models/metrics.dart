/// 睡眠量測數值 — 對應 data contract 的 `metrics` 區塊。
///
/// ⚠️ 有兩個欄位**故意是 null**，不是 bug：
///
/// - [motionCount]：README 定義它是「翻身次數，由影像組提供」。Garmin 的
///   movement_count 是我們自訂的翻動取樣筆數，語意不同，不能默默對映。
///   Garmin 的真值放在 [garminMovementSamples]，資訊沒有遺失。
/// - [ambientNoiseDb]：Garmin 沒有這個數據，而 TAPO 目前的分貝是
///   np.random 產生的模擬值。兩個來源都給不出真值。
///
/// UI 遇到 null 應該顯示「—」或隱藏該欄，不要顯示 0。
class Metrics {
  final int? motionCount;
  final int? garminMovementSamples;
  final int? sleepDurationMinutes;
  final double? ambientNoiseDb;
  final DateTime? sleepStartTime;
  final DateTime? wakeTime;
  final int? deepMinutes;
  final int? remMinutes;
  final int? wasoMinutes;
  final double? sleepEfficiency;
  final double? avgHeartRate;
  final int? restingHeartRate;

  const Metrics({
    this.motionCount,
    this.garminMovementSamples,
    this.sleepDurationMinutes,
    this.ambientNoiseDb,
    this.sleepStartTime,
    this.wakeTime,
    this.deepMinutes,
    this.remMinutes,
    this.wasoMinutes,
    this.sleepEfficiency,
    this.avgHeartRate,
    this.restingHeartRate,
  });

  /// REM 未測得 — 舊錶（Vivoactive 3）的偵測限制，不代表當晚沒有 REM 睡眠。
  /// 46 晚裡有 11 晚是這種情況，UI 不該顯示成「REM 0 分鐘」。
  bool get remUnmeasured => remMinutes == null || remMinutes == 0;

  factory Metrics.fromJson(Map<String, dynamic> json) {
    return Metrics(
      motionCount: (json['motion_count'] as num?)?.toInt(),
      garminMovementSamples:
          (json['garmin_movement_samples'] as num?)?.toInt(),
      sleepDurationMinutes: (json['sleep_duration_minutes'] as num?)?.toInt(),
      ambientNoiseDb: (json['ambient_noise_db'] as num?)?.toDouble(),
      sleepStartTime: _parseTime(json['sleep_start_time']),
      wakeTime: _parseTime(json['wake_time']),
      deepMinutes: (json['deep_minutes'] as num?)?.toInt(),
      remMinutes: (json['rem_minutes'] as num?)?.toInt(),
      wasoMinutes: (json['waso_minutes'] as num?)?.toInt(),
      sleepEfficiency: (json['sleep_efficiency'] as num?)?.toDouble(),
      avgHeartRate: (json['avg_heart_rate'] as num?)?.toDouble(),
      restingHeartRate: (json['resting_heart_rate'] as num?)?.toInt(),
    );
  }

  static DateTime? _parseTime(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
