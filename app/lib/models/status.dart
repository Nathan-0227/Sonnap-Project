/// 寵物狀態 — 對應 data contract 的 `status` 區塊。
///
/// 這些值全部由後端 (build_app_payload.py) 決定，App 不做任何判斷。
/// 專案原則是「Python 判斷，Dart 只負責畫」——分數要對應到哪種心情，
/// 是有文獻依據的映射，集中在一處才能稽核。
class Status {
  /// happy / tired / bored / anxious（README data contract 定義的四種）
  final String petMood;

  /// sleeping / dreaming / waking_up。
  ///
  /// 目前一定是 null：這需要「此刻」的即時狀態，而 pipeline 是隔日批次產出，
  /// 給不出來。硬填一個值就是編造，所以後端誠實留 null，UI 走 idle 動畫。
  final String? currentActivity;

  /// 0–100，等於四捨五入後的 final_score。
  final int? energyLevel;

  /// 這個心情是哪一條規則造成的，方便除錯與稽核。
  final String? moodReason;

  const Status({
    required this.petMood,
    this.currentActivity,
    this.energyLevel,
    this.moodReason,
  });

  factory Status.fromJson(Map<String, dynamic> json) {
    return Status(
      petMood: json['pet_mood'] as String? ?? 'bored',
      currentActivity: json['current_activity'] as String?,
      energyLevel: (json['energy_level'] as num?)?.round(),
      moodReason: json['mood_reason'] as String?,
    );
  }
}
