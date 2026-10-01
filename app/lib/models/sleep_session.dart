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

  /// 這個分數由哪幾項組成，以及哪幾項的門檻效度存疑。
  ///
  /// ⚠️ **可以是 null**：舊的打包檔沒有這個欄位。null 時畫面要**什麼都不顯示**，
  ///    不可以憑空生一個組成清單——那會變成對使用者謊稱分數的可信度。
  final ScoreComposition? composition;

  const Scoring({
    this.finalScore,
    this.finalQuality = 'Normal',
    this.baseScore,
    this.totalModifier,
    this.sri,
    this.modifierNote,
    this.recommendation,
    this.composition,
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
      composition: ScoreComposition.fromJsonOrNull(json['composition']),
    );
  }
}

/// 分數由哪幾項組成，以及哪幾項雖然有計分、但門檻效度存疑。
///
/// ═══════════════════════════════════════════════════════════════
/// 為什麼畫面需要這個
/// ═══════════════════════════════════════════════════════════════
/// **裝置組合因人而異**：只有手機的人、有手錶的人、手錶加攝影機的人，
/// 量得到的構念不一樣。評分器對量不到的項目會把配分按比例分給其他項，
/// 所以兩個都是「82 分」的夜晚**可能由不同的項目組成**。
///
/// 而且四項的可信度並不相同——只有睡眠時長的裝置誤差明確小於它的判讀級距
/// （偏差約 17 分鐘 vs 級距 120 分鐘）。WASO 的級距只有 15 分鐘，
/// 而裝置誤差就有 13~24 分鐘。完整依據見
/// `Research-Background/Garmin手錶分數.md` 的 I-0 與 E-3～E-6。
///
/// ⚠️ **一個字都不在 Dart 這邊產生。** `caveats` 的文字、`primaryComponent`
///    是哪一項，全部照抄後端（`score_claim.py` 是唯一定義處）。
///    在這裡自己寫警語就會有第二份說法，而兩份漂移時不會有任何錯誤訊息。
class ScoreComposition {
  /// 這一晚真的有算分的項目（後端的順序，Dart 不重排）
  final List<String> scored;

  /// 沒算分的項目與原因
  final List<ScoreComponentNote> unscored;

  /// 有算分項目的配分總和（滿分 100 中的多少）
  final int scoredWeight;

  /// 這個分數以哪一項為主。⚠️ 有值代表「**不是**四項等權合成」。
  final String? primaryComponent;

  /// 有計分、但門檻效度存疑的項目。
  /// ⚠️ 與 [unscored] 是不同的兩件事：unscored 是「沒測到」，
  ///    caveats 是「測到了也算了，但門檻能不能套上證據不足」。
  final List<ScoreComponentNote> caveats;

  final String? note;

  const ScoreComposition({
    this.scored = const [],
    this.unscored = const [],
    this.scoredWeight = 0,
    this.primaryComponent,
    this.caveats = const [],
    this.note,
  });

  /// 舊的 payload 沒有這個欄位 → 回 null，畫面就什麼都不顯示。
  static ScoreComposition? fromJsonOrNull(dynamic raw) {
    if (raw is! Map) return null;
    final json = raw.cast<String, dynamic>();
    return ScoreComposition(
      scored: (json['scored'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(growable: false),
      unscored: ScoreComponentNote.listFrom(json['unscored'], 'reason'),
      scoredWeight: (json['scored_weight'] as num?)?.toInt() ?? 0,
      primaryComponent: json['primary_component'] as String?,
      caveats: ScoreComponentNote.listFrom(json['caveats'], 'caveat'),
      note: json['note'] as String?,
    );
  }
}

/// 某一個計分項目的附註（沒算的原因，或有算但要注意的限制）。
class ScoreComponentNote {
  final String component;
  final String text;

  const ScoreComponentNote(this.component, this.text);

  /// [textKey] 是後端放說明文字的鍵名：unscored 用 `reason`、caveats 用 `caveat`。
  static List<ScoreComponentNote> listFrom(dynamic raw, String textKey) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => ScoreComponentNote(
              e['component']?.toString() ?? '',
              e[textKey]?.toString() ?? '',
            ))
        .where((e) => e.component.isNotEmpty && e.text.isNotEmpty)
        .toList(growable: false);
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

/// 歷史夜晚，供 Insights 頁畫趨勢圖用。
class HistoryEntry {
  final String date;
  final double? finalScore;
  final String? finalQuality;
  final double? sleepDurationHours;

  /// Optional bedtime / wake time from backend.
  final String? bedtime;
  final String? wakeTime;

  /// 這一晚寵物的心情，由後端 `build_app_payload.py` 的 `map_pet_mood()` 算好。
  ///
  /// ⚠️ **不要在 Dart 端從 [finalQuality] 自己推。** `anxious` 是 Tier3 生理
  /// 修正值（壓力、心率相對個人 baseline）的覆寫，那幾個欄位根本不在 history
  /// 裡——照品質推會把 anxious 的夜晚畫成 happy。而且那等於讓
  /// `QUALITY_TO_MOOD` 有第二個定義處，違反「Python 判斷、Dart 只負責畫」。
  final String? petMood;

  /// 這個心情是哪一條規則造成的（例：`final_quality=Good`、
  /// `stress_modifier=-4.2 ≤ -3.0`）。讓畫面上的心情可以追溯到依據。
  final String? moodReason;

  const HistoryEntry({
    required this.date,
    this.finalScore,
    this.finalQuality,
    this.sleepDurationHours,
    this.bedtime,
    this.wakeTime,
    this.petMood,
    this.moodReason,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      date: json['date'] as String? ?? '',
      finalScore: (json['final_score'] as num?)?.toDouble(),
      finalQuality: json['final_quality'] as String?,
      sleepDurationHours:
          (json['sleep_duration_hours'] as num?)?.toDouble(),
      bedtime: json['sleep_start_time'] as String?,
      wakeTime: json['wake_time'] as String?,
      petMood: json['pet_mood'] as String?,
      moodReason: json['mood_reason'] as String?,
    );
  }
}
