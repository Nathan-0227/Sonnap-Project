// 早晨報告「Yesterday」：前一天的 Garmin 白天資料（2026-11-13 使用者定）。
// 守：全部照抄後端、不判斷（沒有 reached／Good／Normal）；沒資料整塊不畫；
//     單一項沒值那一項不畫（不畫成 0）；手錶睡眠還沒到也照樣畫。
import 'package:app/models/yesterday_activity.dart';
import 'package:app/screens/morning_report_screen.dart';
import 'package:app/services/morning_report.dart';
import 'package:app/widgets/yesterday_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fullJson() => {
      'date': '2026-11-12',
      'steps': 9955,
      'step_goal': 9430,
      'distance_m': 6720,
      'active_kcal': 377,
      'floors_up': 9.4,
      'activity': {
        'highly_active_sec': 1747,
        'active_sec': 9691,
        'sedentary_sec': 62062,
      },
      'stress': {
        'rest_sec': 27660,
        'low_sec': 11340,
        'medium_sec': 14880,
        'high_sec': 2100,
      },
      'body_battery': {'charged': 48, 'drained': 61},
      'vo2max': {'value': 45.7, 'measured_on': '2026-10-09'},
      'move_iq': [
        {'type': 'walking', 'start': '12:58', 'minutes': 10},
        {'type': 'cycling', 'start': '20:55', 'minutes': 31},
      ],
    };

Map<String, dynamic> home(String date, {Object? yesterday, bool scored = false}) => {
      'date': date,
      'behavior': null,
      'metrics': null,
      'scoring': scored ? {'final_score': 70.0, 'final_quality': 'Normal'} : null,
      'yesterday': yesterday,
    };

Future<void> pumpCard(WidgetTester tester, YesterdayActivity y) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.black,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: YesterdayCard(data: y),
      ),
    ),
  ));
}

String? textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data;

void main() {
  group('解析', () {
    test('完整的那一份照抄', () {
      final y = YesterdayActivity.fromJsonOrNull(fullJson())!;
      expect(y.steps, 9955);
      expect(y.stepGoal, 9430);
      expect(y.floorsUp, 9.4);
      expect(y.stressHighSec, 2100);
      expect(y.vo2max, 45.7);
      expect(y.vo2maxMeasuredOn, '2026-10-09');
      expect(y.moveIq!.map((m) => '${m.start} ${m.type} ${m.minutes}'),
          ['12:58 walking 10', '20:55 cycling 31']);
      expect(y.moveIq!.first.startMinuteOfDay, 12 * 60 + 58);
    });

    test('後端是 null 或格式不對 → null', () {
      expect(YesterdayActivity.fromJsonOrNull(null), isNull);
      expect(YesterdayActivity.fromJsonOrNull({'steps': 1}), isNull, reason: '沒有日期');
    });

    test('Move IQ：沒抓到是 null，那天沒有是空的', () {
      expect(YesterdayActivity.fromJsonOrNull({'date': '2026-11-12'})!.moveIq, isNull);
      expect(
          YesterdayActivity.fromJsonOrNull({'date': '2026-11-12', 'move_iq': []})!.moveIq,
          isEmpty);
    });
  });

  group('報告模型', () {
    test('後端有給 → 報告帶著；沒給 → null', () {
      final r = buildMorningReport(
          date: '2026-11-13', home: home('2026-11-13', yesterday: fullJson()));
      expect(r.yesterday?.steps, 9955);
      expect(
          buildMorningReport(date: '2026-11-13', home: home('2026-11-13')).yesterday,
          isNull);
    });

    test('⚠️ 手錶睡眠還沒到（沒分數）也照樣帶著——白天資料跟睡眠分數無關', () {
      final r = buildMorningReport(
          date: '2026-11-13', home: home('2026-11-13', yesterday: fullJson()));
      expect(r.hasScore, isFalse);
      expect(r.yesterday, isNotNull);
    });

    test('後端回的是別晚 → 不採用', () {
      final r = buildMorningReport(
          date: '2026-11-13', home: home('2026-11-12', yesterday: fullJson()));
      expect(r.yesterday, isNull);
    });
  });

  group('畫面', () {
    testWidgets('完整：四張小卡、兩條、Body Battery、Move IQ', (tester) async {
      await pumpCard(tester, YesterdayActivity.fromJsonOrNull(fullJson())!);
      expect(textOf(tester, 'yesterday-steps-value'), '9,955');
      expect(textOf(tester, 'yesterday-steps-sub'), 'goal 9,430');
      expect(textOf(tester, 'yesterday-active-value'), '377 kcal');
      expect(textOf(tester, 'yesterday-active-sub'), '6.7 km');
      expect(textOf(tester, 'yesterday-floors-value'), '9');
      expect(textOf(tester, 'yesterday-vo2-value'), '46');
      expect(textOf(tester, 'yesterday-vo2-sub'), 'measured Oct 9');
      expect(textOf(tester, 'yesterday-stress-high'), 'High 35m');
      expect(textOf(tester, 'yesterday-activity-sedentary'), 'Sedentary 17h 14m');
      expect(textOf(tester, 'yesterday-bb'),
          'Body Battery · +48 charged · −61 drained');
      expect(find.byKey(const Key('yesterday-moveiq')), findsOneWidget);
      expect(find.text('12:58 Walk 10m'), findsOneWidget);
      expect(find.text('20:55 Bike 31m'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '實機大小不溢出');
    });

    testWidgets('⚠️ 只寫事實：沒有達標、等級、警告字眼', (tester) async {
      await pumpCard(tester, YesterdayActivity.fromJsonOrNull(fullJson())!);
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => (t.data ?? '').toLowerCase())
          .join(' | ');
      for (final w in [
        'reached', 'achieved', 'good', 'normal', 'poor', 'great', 'excellent',
        'warning', 'too much', 'high stress',
      ]) {
        expect(texts.contains(w), isFalse, reason: w);
      }
    });

    testWidgets('單一項沒值 → 那一項不畫，不畫成 0', (tester) async {
      await pumpCard(
          tester,
          YesterdayActivity.fromJsonOrNull(
              {'date': '2026-11-12', 'steps': 4210})!);
      expect(textOf(tester, 'yesterday-steps-value'), '4,210');
      expect(find.byKey(const Key('yesterday-steps-sub')), findsNothing,
          reason: '沒有目標就不寫 goal');
      for (final k in [
        'yesterday-active', 'yesterday-floors', 'yesterday-vo2',
        'yesterday-activity', 'yesterday-stress', 'yesterday-bb', 'yesterday-moveiq',
      ]) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
      expect(find.text('0'), findsNothing);
    });

    testWidgets('那天沒有 Move IQ（空的）→ 不畫時間軸', (tester) async {
      await pumpCard(
          tester,
          YesterdayActivity.fromJsonOrNull(
              {...fullJson(), 'move_iq': <Object>[]})!);
      expect(find.byKey(const Key('yesterday-moveiq')), findsNothing);
    });

    testWidgets('報告：有就放在 More details 前面；沒有就整塊不畫', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      final withY = buildMorningReport(
          date: '2026-11-13', home: home('2026-11-13', yesterday: fullJson()));
      await tester.pumpWidget(MaterialApp(home: MorningReportScreen(initial: withY)));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(find.byKey(const Key('yesterday-card')), findsOneWidget);
      expect(tester.takeException(), isNull);

      final without = buildMorningReport(date: '2026-11-13', home: home('2026-11-13'));
      await tester.pumpWidget(MaterialApp(
          home: MorningReportScreen(key: const ValueKey('without'), initial: without)));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(find.byKey(const Key('yesterday-card')), findsNothing);
    });
  });
}
