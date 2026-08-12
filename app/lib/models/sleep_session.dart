import 'ai_content.dart';
import 'metrics.dart';
import 'status.dart';

/// 一整晚的睡眠資料 — `app_payload.json` 的根物件。
///
/// 頂層沿用團隊 README 議定的 data contract（session_id / status / metrics /
/// ai_content / timestamp），往下擴充 scoring / display / streak / history。
/// 刻意不另開一套格式：那份 contract 是全隊共識，該做的是擴充並提報 PM。
///
/// 只實作 fromJson——App 目前不需要往回寫。
class SleepSession {
  final int schemaVersion;
  final String sessionId;
  final Status status;
  final Metrics metrics;
  final AiContent aiContent;
  final Scoring scoring;
  final Display display;
  final Streak streak;
  final List<HistoryEntry> history;
  final List<String> dataSources;
  final String? disclaimer;
  final DateTime? timestamp;

  const SleepSession({
    required this.schemaVersion,
    required this.sessionId,
    required this.status,
    required this.metrics,
    required this.aiContent,
    required this.scoring,
    required this.display,
    required this.streak,
    required this.history,
    required this.dataSources,
    this.disclaimer,
    this.timestamp,
  });

  factory SleepSession.fromJson(Map<String, dynamic> json) {
    return SleepSession(
      schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 1,
      sessionId: json['session_id'] as String? ?? '',
      status: Status.fromJson(_map(json['status'])),
      metrics: Metrics.fromJson(_map(json['metrics'])),
      aiContent: AiContent.fromJson(_map(json['ai_content'])),
      scoring: Scoring.fromJson(_map(json['scoring'])),
      display: Display.fromJson(_map(json['display'])),
      streak: Streak.fromJson(_map(json['streak'])),
      history: (json['history'] as List<dynamic>? ?? [])
          .map((e) => HistoryEntry.fromJson(_map(e)))
          .toList(),
      dataSources: (json['data_sources'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      disclaimer: json['disclaimer'] as String?,
      timestamp: json['timestamp'] is String
          ? DateTime.tryParse(json['timestamp'] as String)
          : null,
    );
  }

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map<String, dynamic> ? value : const {};
}

/// 評分結果。分數的計算方式見 Research-Background/Garmin手錶分數.md。
class Scoring {
  final double? finalScore;

  /// Good / Normal / Poor / Bad
  final String finalQuality;

  /// Tier1/2 文獻加權的基礎分數
  final double? baseScore;

  /// Tier3 個人化生理修正值（±12）
  final double? totalModifier;

  /// 作息規律指數。**刻意不計分**，只呈現數值與趨勢——
  /// 因為不同計算方法算出的 SRI 差異足以改變結論，拿去對照外部常模沒有意義。
  final double? sri;

  /// 說明哪些修正項因冷啟動或資料無效而未啟用
  final String? modifierNote;

  /// 規則式建議**原文**。這是事實來源，AI 的 advice 是它的重新配音。
  final String? recommendation;

  const Scoring({
    this.finalScore,
    this.finalQuality = 'Normal',
    this.baseScore,
    this.totalModifier,
    this.sri,
    this.modifierNote,
    this.recommendation,
  });

  /// UI 的分數環要用整數
  int get scoreAsInt => finalScore?.round() ?? 0;

  factory Scoring.fromJson(Map<String, dynamic> json) {
    return Scoring(
      finalScore: (json['final_score'] as num?)?.toDouble(),
      finalQuality: json['final_quality'] as String? ?? 'Normal',
      baseScore: (json['base_score'] as num?)?.toDouble(),
      totalModifier: (json['total_modifier'] as num?)?.toDouble(),
      sri: (json['sri'] as num?)?.toDouble(),
      modifierNote: json['modifier_note'] as String?,
      recommendation: json['recommendation'] as String?,
    );
  }
}

/// 後端算好的顯示字串與顏色。
///
/// 為什麼文案也由後端決定：「昨晚睡得好不好、該說哪句鼓勵的話」是對那一晚的
/// 判斷，跟分數同源。放後端才只有一個定義處，日後要做 i18n 也是改一個地方。
class Display {
  final String lang;
  final String scoreMessage;
  final String moodDescription;
  final String headerMessage;
  final String petMessage;
  final String streakEncouragement;

  /// "#9AD36A" 這種格式，由 [colorValue] 轉成 Flutter 的 Color 用的 int
  final String scoreColor;

  const Display({
    this.lang = 'en',
    this.scoreMessage = '',
    this.moodDescription = '',
    this.headerMessage = '',
    this.petMessage = '',
    this.streakEncouragement = '',
    this.scoreColor = '#FFC83D',
  });

  /// 把 "#RRGGBB" 轉成 Color 建構子吃的 0xFFRRGGBB。
  /// 格式不對就回傳預設的黃色，不讓一個壞掉的字串弄崩整個畫面。
  int get colorValue {
    final hex = scoreColor.replaceFirst('#', '');
    if (hex.length != 6) return 0xFFFFC83D;
    return int.tryParse('FF$hex', radix: 16) ?? 0xFFFFC83D;
  }

  factory Display.fromJson(Map<String, dynamic> json) {
    return Display(
      lang: json['lang'] as String? ?? 'en',
      scoreMessage: json['score_message'] as String? ?? '',
      moodDescription: json['mood_description'] as String? ?? '',
      headerMessage: json['header_message'] as String? ?? '',
      petMessage: json['pet_message'] as String? ?? '',
      streakEncouragement: json['streak_encouragement'] as String? ?? '',
      scoreColor: json['score_color'] as String? ?? '#FFC83D',
    );
  }
}

/// 連續記錄天數。
///
/// ⚠️ 這兩個數字目前會偏小，那是**誠實的結果**不是 bug：手錶沒戴的夜晚
/// 不算在內，而實測 74 個日曆日裡只有 46 晚有記錄。[definition] 帶著定義文字，
/// 讓 UI 上的數字可以追溯。
class Streak {
  final int streakDays;
  final int completedDays;
  final String definition;

  const Streak({
    this.streakDays = 0,
    this.completedDays = 0,
    this.definition = '',
  });

  factory Streak.fromJson(Map<String, dynamic> json) {
    return Streak(
      streakDays: (json['streak_days'] as num?)?.toInt() ?? 0,
      completedDays: (json['completed_days'] as num?)?.toInt() ?? 0,
      definition: json['definition'] as String? ?? '',
    );
  }
}

/// 歷史夜晚，供 Insights 頁畫趨勢圖用（目前尚未接上）。
class HistoryEntry {
  final String date;
  final double? finalScore;
  final String? finalQuality;
  final double? sleepDurationHours;

  const HistoryEntry({
    required this.date,
    this.finalScore,
    this.finalQuality,
    this.sleepDurationHours,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      date: json['date'] as String? ?? '',
      finalScore: (json['final_score'] as num?)?.toDouble(),
      finalQuality: json['final_quality'] as String?,
      sleepDurationHours: (json['sleep_duration_hours'] as num?)?.toDouble(),
    );
  }
}
