import '../models/sleep_session.dart';

/// 睡眠助理的回答引擎。
///
/// ## 這一層是「路由器」不是「生成器」
///
/// 本專案的既定原則是「**Python 判斷，Dart 只負責畫**」——分數好不好、
/// 該給什麼建議，全部由後端算好放進 payload，這樣每一句話都能追溯到
/// `Research-Background/Garmin手錶分數.md` 的文獻依據。
///
/// 所以這裡**不產生任何新建議**，只做兩件事：
///
///   1. 判斷使用者問的是哪個主題
///   2. 把 payload 裡**已經存在**的對應欄位取出來組成句子
///
/// ⚠️ **不要在這裡加「如果分數低於 X 就建議 Y」這種規則。**
///    那會變成第二套沒有文獻依據的評分邏輯，而「每一項計分都有引文」
///    是這個專案最難複製的資產（見 CLAUDE.md 紅線 2）。
///    要新增建議，改 `garmin/evaluate_sleep_quality.py` 或 `ai/`，
///    讓它進 payload，這裡再取出來。
///
/// 唯一的例外是**算術彙總**（平均、最高、最低、天數）——那是把後端已經
/// 算好的分數做描述性統計，不是新的判斷。
///
/// ## 答不出來就說答不出來
///
/// 修改前這個畫面回的是寫死的字串，最後一段是
/// "The real AI response will appear here after the backend is connected."
/// ——那等於對使用者謊稱系統之後會變聰明。現在答不出來就明講答不出來，
/// 並列出**真的答得出來**的主題。
class AssistantAnswer {
  /// 要顯示的回答本文。
  final String text;

  /// 這個回答用到 payload 的哪些欄位。UI 目前沒有顯示，
  /// 但測試靠它驗證「答案真的來自資料」而不是寫死的字串。
  final List<String> sources;

  /// 是否答得出來。false 代表走了 fallback。
  final bool answered;

  const AssistantAnswer({
    required this.text,
    this.sources = const [],
    this.answered = true,
  });
}

/// 主題判斷用的關鍵字。
///
/// ⚠️ 順序有意義——由上往下比對，第一個命中的就是答案。
///    `dream` 排在 `sleep` 前面，因為「dream」的問題一定是問夢境，
///    但含「sleep」的問題可能是任何主題。
const List<(String, List<String>)> _topicKeywords = [
  ('dream', ['dream', 'diary', 'nightmare']),
  ('pet', ['pet', 'buddy', 'dog', 'mood', 'anxious', 'happy', 'tired pet']),
  ('streak', ['streak', 'consecutive', 'how many days', 'in a row']),
  ('deep', ['deep sleep', 'deep']),
  ('rem', ['rem']),
  ('heart', ['heart', 'hr', 'pulse', 'bpm']),
  ('bedtime', ['bedtime', 'what time', 'go to bed', 'wake', 'woke']),
  ('duration', ['how long', 'duration', 'hours', 'enough sleep']),
  // 「recent / recently / compare」是實測時發現漏掉的自然問法
  // （測試裡的 "how has my sleep been recently" 原本落到 unknown）
  ('trend', ['trend', 'history', 'last week', 'past', 'average', 'improving',
             'recent', 'recently', 'compare', 'lately', 'this week']),
  ('improve', ['improve', 'better', 'tips', 'advice', 'should i', 'how can i']),
  ('score', ['score', 'rating', 'quality', 'how did i sleep']),
  ('tired', ['tired', 'exhausted', 'sleepy', 'why am i']),
];

String _topicFor(String question) {
  final q = question.toLowerCase();
  for (final (topic, words) in _topicKeywords) {
    for (final w in words) {
      if (q.contains(w)) return topic;
    }
  }
  return 'unknown';
}

/// 分鐘轉「X h Y min」。null 回傳 null，呼叫端自己決定怎麼講。
String? _hm(int? minutes) {
  if (minutes == null) return null;
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m min';
  if (m == 0) return '$h h';
  return '$h h $m min';
}

String _clock(DateTime? t) {
  if (t == null) return 'unknown';
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// 答得出來的主題清單，答不出來時列給使用者看。
const String _capabilities =
    'I can answer questions about your sleep score, sleep duration, deep sleep, '
    'REM, heart rate, bedtime and wake time, your streak, your pet\'s mood, '
    'your dream diary, and how your recent nights compare.';

/// 主入口。[session] 為 null 代表資料還沒載入完。
AssistantAnswer answerQuestion(String question, SleepSession? session) {
  final cleaned = question.trim();
  if (cleaned.isEmpty) {
    return const AssistantAnswer(
      text: 'Please type a question first.',
      answered: false,
    );
  }

  if (session == null) {
    return const AssistantAnswer(
      text: 'Your sleep data has not loaded yet. Please try again in a moment.',
      answered: false,
    );
  }

  final m = session.metrics;
  final s = session.scoring;
  final ai = session.aiContent;

  switch (_topicFor(cleaned)) {
    // ── 夢境日記 ────────────────────────────────────────────────
    case 'dream':
      if (!ai.hasDream) {
        return const AssistantAnswer(
          text: 'There is no dream diary entry for last night yet.',
          sources: ['ai_content.dream_summary'],
          answered: false,
        );
      }
      // ⚠️ 一定要講明這是「寵物的夢」而且是 AI 想像的。
      //    Garmin 完全沒有量測夢境內容，寫成「你的夢」就是誤述資料支持的範圍。
      //    這與 home_screen 的夢境對話框是同一條規則。
      return AssistantAnswer(
        text: 'Here is your buddy\'s dream diary from last night:\n\n'
            '${ai.dreamSummary}\n\n'
            '${session.disclaimer ?? ''}',
        sources: ['ai_content.dream_summary', 'disclaimer'],
      );

    // ── 寵物心情 ────────────────────────────────────────────────
    case 'pet':
      return AssistantAnswer(
        text: '${session.display.moodDescription}\n\n'
            'Your buddy\'s mood is "${session.status.petMood}", which follows '
            'your sleep result for last night (${s.finalQuality}'
            '${s.finalScore != null ? ', ${s.finalScore!.toStringAsFixed(1)} points' : ''}). '
            'Sleeping better and more consistently is what changes it.',
        sources: [
          'status.pet_mood',
          'status.mood_reason',
          'display.mood_description',
          'scoring.final_quality',
        ],
      );

    // ── 連續天數 ────────────────────────────────────────────────
    case 'streak':
      return AssistantAnswer(
        text: 'You are on a ${session.streak.streakDays}-night streak, and '
            '${session.streak.completedDays} of the last 7 nights were rated '
            'Good or Normal.\n\n'
            '${session.streak.definition}',
        sources: ['streak.streak_days', 'streak.completed_days', 'streak.definition'],
      );

    // ── 深睡 ────────────────────────────────────────────────────
    case 'deep':
      final deep = _hm(m.deepMinutes);
      if (deep == null) {
        return const AssistantAnswer(
          text: 'Deep sleep was not measured last night.',
          sources: ['metrics.deep_minutes'],
          answered: false,
        );
      }
      final total = m.sleepDurationMinutes;
      final pct = (total != null && total > 0 && m.deepMinutes != null)
          ? ' (${(m.deepMinutes! / total * 100).toStringAsFixed(0)}% of your sleep)'
          : '';
      return AssistantAnswer(
        text: 'You got $deep of deep sleep last night$pct.',
        sources: ['metrics.deep_minutes', 'metrics.sleep_duration_minutes'],
      );

    // ── REM ─────────────────────────────────────────────────────
    case 'rem':
      // ⚠️ REM = 0 的語意是「這支手錶沒測到」，不是「你沒有 REM 睡眠」。
      //    人一定會有 REM，說成 0 就是把量測限制講成生理事實。
      //    Metrics.remUnmeasured 這個 getter 存在就是為了這件事。
      if (m.remUnmeasured) {
        return const AssistantAnswer(
          text: 'Your watch did not record REM sleep for last night. '
              'That is a limitation of the device on this night, not a sign '
              'that you had no REM sleep.',
          sources: ['metrics.rem_minutes'],
        );
      }
      return AssistantAnswer(
        text: 'You got ${_hm(m.remMinutes)} of REM sleep last night.',
        sources: ['metrics.rem_minutes'],
      );

    // ── 心率 ────────────────────────────────────────────────────
    case 'heart':
      final parts = <String>[];
      if (m.avgHeartRate != null) {
        parts.add('Your average heart rate during sleep was '
            '${m.avgHeartRate!.toStringAsFixed(0)} bpm');
      }
      if (m.restingHeartRate != null) {
        parts.add('your resting heart rate was ${m.restingHeartRate} bpm');
      }
      if (parts.isEmpty) {
        return const AssistantAnswer(
          text: 'Heart rate was not recorded for last night.',
          sources: ['metrics.avg_heart_rate'],
          answered: false,
        );
      }
      return AssistantAnswer(
        text: '${parts.join(', and ')}.',
        sources: ['metrics.avg_heart_rate', 'metrics.resting_heart_rate'],
      );

    // ── 上床／起床時刻 ──────────────────────────────────────────
    case 'bedtime':
      // ⚠️ sleep_start_time 是手錶偵測到「睡著」的時刻（生理），
      //    不是「上床」或「放下手機」。措辭要用 fell asleep，
      //    理由同 migrate_garmin_to_db.py:24-27。
      return AssistantAnswer(
        text: 'You fell asleep at ${_clock(m.sleepStartTime)} and woke at '
            '${_clock(m.wakeTime)} last night.\n\n'
            'Note that this is when your watch detected sleep, which is later '
            'than the moment you got into bed.',
        sources: ['metrics.sleep_start_time', 'metrics.wake_time'],
      );

    // ── 睡多久 ──────────────────────────────────────────────────
    case 'duration':
      final dur = _hm(m.sleepDurationMinutes);
      if (dur == null) {
        return const AssistantAnswer(
          text: 'Sleep duration was not recorded for last night.',
          sources: ['metrics.sleep_duration_minutes'],
          answered: false,
        );
      }
      return AssistantAnswer(
        text: 'You slept $dur last night.'
            '${s.recommendation != null ? '\n\n${s.recommendation}' : ''}',
        sources: ['metrics.sleep_duration_minutes', 'scoring.recommendation'],
      );

    // ── 趨勢：對 history 做算術彙總 ─────────────────────────────
    case 'trend':
      final scored = session.history
          .where((h) => h.finalScore != null)
          .toList();
      if (scored.length < 2) {
        return const AssistantAnswer(
          text: 'There is not enough history yet to compare your nights.',
          sources: ['history'],
          answered: false,
        );
      }
      // 只做描述性統計，不下判斷——分數本身是後端算的
      final avg = scored.map((h) => h.finalScore!).reduce((a, b) => a + b) /
          scored.length;
      final best = scored.reduce((a, b) => a.finalScore! >= b.finalScore! ? a : b);
      final worst = scored.reduce((a, b) => a.finalScore! <= b.finalScore! ? a : b);
      final trendNote = ai.trendNote;
      return AssistantAnswer(
        text: 'Across your last ${scored.length} recorded nights, your average '
            'score was ${avg.toStringAsFixed(1)}. Your best night was '
            '${best.date} (${best.finalScore!.toStringAsFixed(1)}) and your '
            'lowest was ${worst.date} (${worst.finalScore!.toStringAsFixed(1)}).'
            '${trendNote != null ? '\n\n$trendNote' : ''}',
        sources: ['history', 'ai_content.trend_note'],
      );

    // ── 怎麼改善 ────────────────────────────────────────────────
    case 'improve':
      // 兩個來源都是後端產生的：recommendation 是規則式（有文獻門檻），
      // advice 是 LLM 寫的。兩者都給，並標明哪句是 AI 寫的。
      final bits = <String>[];
      if (s.recommendation != null && s.recommendation!.isNotEmpty) {
        bits.add(s.recommendation!);
      }
      if (ai.advice != null && ai.advice!.isNotEmpty) {
        bits.add(ai.isAiGenerated
            ? 'Your AI coach adds: ${ai.advice}'
            : ai.advice!);
      }
      if (bits.isEmpty) {
        return const AssistantAnswer(
          text: 'No recommendation was generated for last night.',
          sources: ['scoring.recommendation', 'ai_content.advice'],
          answered: false,
        );
      }
      return AssistantAnswer(
        text: bits.join('\n\n'),
        sources: ['scoring.recommendation', 'ai_content.advice'],
      );

    // ── 分數 ────────────────────────────────────────────────────
    case 'score':
      final score = s.finalScore;
      final line = score != null
          ? 'Your sleep score for last night was ${score.toStringAsFixed(1)} '
              'out of 100, rated ${s.finalQuality}.'
          : 'Your sleep was rated ${s.finalQuality} for last night.';
      // ⚠️ modifier_note 會說明 Tier3 為什麼沒生效（冷啟動、或戴錶者不明），
      //    那是誠實揭露量測限制的機制，不能省略。
      final note = s.modifierNote;
      return AssistantAnswer(
        text: '$line'
            '${s.recommendation != null ? '\n\n${s.recommendation}' : ''}'
            '${note != null && note.isNotEmpty ? '\n\n$note' : ''}',
        sources: ['scoring.final_score', 'scoring.final_quality',
                  'scoring.recommendation', 'scoring.modifier_note'],
      );

    // ── 為什麼會累 ──────────────────────────────────────────────
    case 'tired':
      // 只陳述當晚實際量到的數字，不推論因果——
      // 「你累是因為 X」需要因果證據，我們只有相關性。
      final facts = <String>[];
      final dur = _hm(m.sleepDurationMinutes);
      if (dur != null) facts.add('you slept $dur');
      if (m.sleepEfficiency != null) {
        facts.add('your sleep efficiency was '
            '${m.sleepEfficiency!.toStringAsFixed(0)}%');
      }
      if (m.wasoMinutes != null) {
        facts.add('you were awake ${m.wasoMinutes} min during the night');
      }
      return AssistantAnswer(
        text: 'Last night ${facts.join(', ')}, and your sleep was rated '
            '${s.finalQuality}.'
            '${ai.trendNote != null ? '\n\n${ai.trendNote}' : ''}\n\n'
            'These are the measurements from your watch — they show what '
            'happened, not why you feel a certain way.',
        sources: ['metrics.sleep_duration_minutes', 'metrics.sleep_efficiency',
                  'metrics.waso_minutes', 'ai_content.trend_note'],
      );

    // ── 答不出來 ────────────────────────────────────────────────
    default:
      return const AssistantAnswer(
        text: 'I can only answer questions about the sleep data your watch '
            'recorded, so I could not match that question.\n\n'
            '$_capabilities',
        answered: false,
      );
  }
}
