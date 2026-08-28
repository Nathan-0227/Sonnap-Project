// 睡眠助理回答引擎的驗收測試。
//
// 這支守的是一件會安靜壞掉的事：**回答退化回與資料無關的寫死字串**。
//
// 修改前的版本就是那樣——不管使用者睡幾小時，問「deep sleep」永遠回
// 同一句「Your deep sleep may be affected by short sleep duration, stress...」。
// 那種字串不會讓任何測試變紅，也不會讓 analyze 報錯，但它對使用者是假的。
//
// 所以下面每一條的驗證方式都是「**換一份資料，答案要跟著換**」，
// 而不是比對某個固定字串。

import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/sleep_session.dart';
import 'package:app/services/assistant_answers.dart';

/// 造一份可控的 payload。只填測試會用到的欄位，其餘走 fromJson 的預設值。
SleepSession _session({
  double? finalScore = 82.2,
  String finalQuality = 'Good',
  int? durationMinutes = 384,
  int? deepMinutes = 258,
  int? remMinutes = 0,
  int? wasoMinutes = 0,
  double? efficiency = 100.0,
  double? avgHr = 79.06,
  int? restingHr = 69,
  String? recommendation = 'Sleep quality was good. Keep your current routine.',
  String? advice = 'Try adding a little more time in bed tonight.',
  String? dream = 'I dreamt I was lying on moss thick as a mattress.',
  String? trendNote = 'Your heart rate has been higher over the last seven nights.',
  String petMood = 'happy',
  int streakDays = 3,
  int completedDays = 4,
  List<Map<String, dynamic>> history = const [],
}) {
  return SleepSession.fromJson({
    'schema_version': 1,
    'session_id': '20260823_001',
    'status': {
      'pet_mood': petMood,
      'energy_level': 82,
      'mood_reason': 'final_quality=$finalQuality',
    },
    'metrics': {
      'sleep_duration_minutes': durationMinutes,
      'deep_minutes': deepMinutes,
      'rem_minutes': remMinutes,
      'waso_minutes': wasoMinutes,
      'sleep_efficiency': efficiency,
      'avg_heart_rate': avgHr,
      'resting_heart_rate': restingHr,
      'sleep_start_time': '2026-08-22T22:32:00+08:00',
      'wake_time': '2026-08-23T04:56:00+08:00',
    },
    'ai_content': {
      'advice': advice,
      'dream_summary': dream,
      'trend_note': trendNote,
      'is_ai_generated': true,
    },
    'scoring': {
      'final_score': finalScore,
      'final_quality': finalQuality,
      'recommendation': recommendation,
      'modifier_note': 'Personalized modifiers are disabled for this period.',
    },
    'display': {
      'lang': 'en',
      'score_message': 'Great job!',
      'mood_description': 'Your buddy is feeling great!',
      'header_message': 'Keep it going',
      'pet_message': 'Sweet dreams',
      'streak_encouragement': 'Build a streak',
      'score_color': '#9AD36A',
    },
    'streak': {
      'streak_days': streakDays,
      'completed_days': completedDays,
      'definition': 'streak_days = consecutive nights with a sleep record.',
    },
    'history': history,
    'data_sources': ['garmin'],
    'disclaimer': 'Sleep scores are computed from Garmin watch data.',
  });
}

void main() {
  group('回答必須來自資料，不是寫死的字串', () {
    test('睡眠時數改變時，答案裡的數字要跟著改', () {
      final a = answerQuestion('how long did I sleep', _session(durationMinutes: 384));
      final b = answerQuestion('how long did I sleep', _session(durationMinutes: 120));

      expect(a.text, contains('6 h 24 min'));
      expect(b.text, contains('2 h'));
      expect(a.text, isNot(b.text),
          reason: '不同的睡眠時數給出相同答案，代表回答沒有讀資料');
    });

    test('深睡分鐘數與百分比都來自資料', () {
      final a = answerQuestion('deep sleep',
          _session(deepMinutes: 258, durationMinutes: 384));
      expect(a.text, contains('4 h 18 min'));
      expect(a.text, contains('67%'));

      final b = answerQuestion('deep sleep',
          _session(deepMinutes: 60, durationMinutes: 384));
      expect(b.text, contains('1 h'));
      expect(b.text, isNot(contains('67%')));
    });

    test('分數改變時答案跟著改', () {
      final a = answerQuestion('what is my sleep score', _session(finalScore: 82.2));
      final b = answerQuestion('what is my sleep score',
          _session(finalScore: 41.0, finalQuality: 'Bad'));
      expect(a.text, contains('82.2'));
      expect(b.text, contains('41.0'));
      expect(b.text, contains('Bad'));
    });

    test('每個成功的回答都要標明用了哪些 payload 欄位', () {
      for (final q in [
        'sleep score', 'deep sleep', 'how long', 'heart rate',
        'what time did I wake', 'my streak', 'my pet', 'my dream',
      ]) {
        final a = answerQuestion(q, _session());
        expect(a.sources, isNotEmpty,
            reason: '「$q」沒有標明資料來源，可能是寫死的回答');
      }
    });
  });

  group('誠實揭露量測限制', () {
    test('REM = 0 要說成「沒測到」，不能說成「你沒有 REM」', () {
      final a = answerQuestion('how much REM did I get', _session(remMinutes: 0));

      // 關鍵：不能出現「0 分鐘 REM」這種把量測限制講成生理事實的說法
      expect(a.text.toLowerCase(), contains('did not record'));
      expect(a.text, isNot(contains('0 min')));
      expect(a.text.toLowerCase(), contains('not a sign'),
          reason: '必須明講這是裝置限制而不是真的沒有 REM 睡眠');
    });

    test('REM 有值時照實回報', () {
      final a = answerQuestion('REM', _session(remMinutes: 95));
      expect(a.text, contains('1 h 35 min'));
    });

    test('入睡時刻要講成 fell asleep，不能講成上床', () {
      final a = answerQuestion('what time did I go to bed', _session());
      expect(a.text, contains('fell asleep'));
      // sleep_start_time 是生理上的「睡著」，不是行為上的「上床」。
      // 講錯會讓使用者以為系統知道他幾點放下手機。
      expect(a.text.toLowerCase(), contains('later than the moment you got into bed'));
    });

    test('夢境一定要附上 disclaimer 且說明是寵物的夢', () {
      final a = answerQuestion('tell me my dream', _session());
      expect(a.text, contains("buddy's dream"),
          reason: 'Garmin 沒有量測夢境內容，寫成「你的夢」就是誤述資料範圍');
      expect(a.text, contains('Sleep scores are computed from Garmin watch data'));
    });

    test('分數回答要帶上 modifier_note（Tier3 為什麼沒生效）', () {
      final a = answerQuestion('my sleep score', _session());
      expect(a.text, contains('Personalized modifiers are disabled'));
    });
  });

  group('答不出來就說答不出來', () {
    test('無關的問題不得編造答案', () {
      final a = answerQuestion('what is the capital of France', _session());
      expect(a.answered, isFalse);
      // 不能再出現那句承諾未來會變好的話
      expect(a.text, isNot(contains('after the backend is connected')));
      // 要告訴使用者實際答得出什麼
      expect(a.text, contains('sleep score'));
    });

    test('空問題', () {
      final a = answerQuestion('   ', _session());
      expect(a.answered, isFalse);
    });

    test('資料還沒載入時要講清楚，不能假裝有答案', () {
      final a = answerQuestion('my sleep score', null);
      expect(a.answered, isFalse);
      expect(a.text.toLowerCase(), contains('not loaded'));
    });

    test('欄位缺值時回報缺值，不填 0 或猜測', () {
      final a = answerQuestion('deep sleep', _session(deepMinutes: null));
      expect(a.answered, isFalse);
      expect(a.text.toLowerCase(), contains('not measured'));
    });
  });

  group('趨勢只做算術彙總，不下新判斷', () {
    test('用 history 算平均、最好、最差', () {
      final a = answerQuestion('how has my sleep been recently', _session(history: [
        {'date': '2026-08-20', 'final_score': 60.0, 'final_quality': 'Poor'},
        {'date': '2026-08-21', 'final_score': 90.0, 'final_quality': 'Good'},
        {'date': '2026-08-22', 'final_score': 75.0, 'final_quality': 'Normal'},
      ]));
      expect(a.text, contains('75.0'));       // 平均
      expect(a.text, contains('2026-08-21')); // 最好
      expect(a.text, contains('2026-08-20')); // 最差
    });

    test('history 太少時不硬算', () {
      final a = answerQuestion('trend', _session(history: []));
      expect(a.answered, isFalse);
      expect(a.text.toLowerCase(), contains('not enough history'));
    });
  });

  group('建議只轉述後端算好的內容', () {
    test('recommendation 與 ai advice 兩個來源都要出現', () {
      final a = answerQuestion('how can I improve', _session(
        recommendation: 'RULE_BASED_TEXT',
        advice: 'LLM_TEXT',
      ));
      expect(a.text, contains('RULE_BASED_TEXT'));
      expect(a.text, contains('LLM_TEXT'));
      // LLM 寫的要標明出處，使用者才分得出哪句有文獻依據
      expect(a.text, contains('AI coach'));
    });

    test('兩個來源都沒有時，不得自己生一句建議', () {
      final a = answerQuestion('give me tips',
          _session(recommendation: null, advice: null));
      expect(a.answered, isFalse);
      expect(a.text.toLowerCase(), contains('no recommendation'));
    });
  });
}
