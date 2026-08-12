// Sonnap 的基本 smoke test。
//
// ⚠️ 這個檔案原本是 `flutter create` 產生的計數器範本測試（找 Icons.add、
//    找文字 '0'），對 SonnapApp 一定失敗——那是樣板殘留，不是有人寫壞的。
//    換成真的測試：確認 App 起得來、五個分頁都在、首頁會顯示 payload 裡的
//    真實數值，以及讀不到資料時顯示錯誤狀態而不是崩潰或白畫面。
//
// 兩個寫測試時踩到的坑，留著避免之後有人改回去：
//
// 1. **不要用 pumpAndSettle()**。PetCard 用 Lottie.asset 播動畫，預設是無限
//    循環，pumpAndSettle 會一直等動畫停下來、最後逾時失敗。用固定次數的
//    pump() 就好。
// 2. **分數要用 findRichText**。SleepScoreCard 是用 Text.rich 把 "46" 和
//    "/100" 併成一個 RichText，普通的 find.text('46') 抓不到。

import 'package:app/main.dart';
import 'package:app/models/sleep_session.dart';
import 'package:app/screens/home_screen.dart';
import 'package:app/services/sleep_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 測試用的假 repository，這樣測試不依賴 asset 檔存不存在。
class _FakeRepository implements SleepRepository {
  final SleepSession? session;
  final Object? error;

  const _FakeRepository({this.session, this.error});

  @override
  Future<SleepSession> load() async {
    if (error != null) throw error!;
    return session!;
  }
}

SleepSession _sampleSession() {
  return SleepSession.fromJson(const {
    'schema_version': 1,
    'session_id': '20260809_001',
    'status': {'pet_mood': 'anxious', 'energy_level': 46},
    'metrics': {'sleep_duration_minutes': 321},
    'ai_content': {'advice': 'Get to bed earlier.', 'is_ai_generated': false},
    'scoring': {'final_score': 45.8, 'final_quality': 'Bad'},
    'display': {
      'score_message': 'Tough night.',
      'mood_description': 'Your buddy is worn out.',
      'header_message': "Let's take it easy tonight.",
      'pet_message': 'I could use a longer nap.',
      'streak_encouragement': "Let's build a streak!",
      'score_color': '#FF4F63',
    },
    'streak': {'streak_days': 1, 'completed_days': 2},
    'history': [],
    'data_sources': ['garmin'],
  });
}

/// 讓 FutureBuilder 解析完成，但不等 Lottie 的無限動畫。
///
/// 不能用 pumpAndSettle()——PetCard 的 Lottie 是無限循環動畫，
/// pumpAndSettle 會一直等它停下來然後逾時。
/// 真實 asset 的讀取是非同步的，兩次 pump 不夠，所以多跑幾輪。
Future<void> _settleWithoutAnimations(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('App boots and shows all five tabs', (tester) async {
    await tester.pumpWidget(const SonnapApp());
    await _settleWithoutAnimations(tester);

    for (final label in [
      'Home',
      'Friends',
      'Insights',
      'Assistants',
      'Settings',
    ]) {
      expect(find.text(label), findsOneWidget, reason: 'missing tab: $label');
    }
  });

  testWidgets('HomeScreen renders real values from the payload',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeScreen(
          repository: _FakeRepository(session: _sampleSession()),
        ),
      ),
    ));
    await _settleWithoutAnimations(tester);

    // 分數是 Text.rich（"46" + "/100"），所以要 findRichText
    expect(find.textContaining('46', findRichText: true), findsWidgets);
    expect(find.text('Anxious'), findsOneWidget);
    expect(find.text('Tough night.'), findsOneWidget);

    // 確認不再是寫死的那組值
    expect(find.textContaining('82', findRichText: true), findsNothing);
    expect(find.text('Happy'), findsNothing);
  });

  // 讀真實 asset 的測試在 test/sleep_repository_test.dart，刻意分開放——
  // 那個測試要用 runAsync，跟這裡的 widget 測試放同一個檔案會互相卡住。

  testWidgets('HomeScreen shows an error state when data is missing',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: HomeScreen(
          repository: _FakeRepository(error: 'asset not found'),
        ),
      ),
    ));
    await _settleWithoutAnimations(tester);

    expect(find.text('No sleep data yet'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
