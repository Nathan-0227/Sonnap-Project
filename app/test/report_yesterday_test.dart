// 早晨報告「Yesterday」：前一天的 Garmin 白天資料（2026-11-13 使用者定；2026-11-14 改成圖形格子）。
// 守：全部照抄後端、不判斷（沒有 reached／Good／Normal）；沒資料整段不畫；
//     單一項沒值那一格不畫（不畫成 0）；手錶睡眠還沒到也照樣畫；VO2 max 不放（同首頁）；
//     圖形真的畫出來（實機抓到過：橫條 0 高、看不見）。
import 'package:app/models/yesterday_activity.dart';
import 'package:app/screens/morning_report_screen.dart';
import 'package:app/services/morning_report.dart';
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

Future<void> pumpReport(WidgetTester tester, Map<String, dynamic>? yesterday,
    {String key = 'r'}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  final r = buildMorningReport(
      date: '2026-11-13', home: home('2026-11-13', yesterday: yesterday));
  await tester.pumpWidget(
      MaterialApp(home: MorningReportScreen(key: ValueKey(key), initial: r)));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// 捲到「Yesterday」那一段的最後一格（清單是懶建的，畫面外的還沒建出來）。
Future<void> scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 300,
      scrollable: find.byType(Scrollable).first);
  await tester.pump();
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

  group('畫面（圖形格子）', () {
    testWidgets('完整：步數、活動時間、壓力、Body Battery、整天心率、Move IQ', (tester) async {
      await pumpReport(tester, fullJson());
      await scrollTo(tester, find.byKey(const Key('report-yesterday')));
      expect(find.text('Yesterday · Thu, Nov 12'), findsOneWidget);
      await scrollTo(tester, find.byKey(const Key('report-steps')));
      expect(textOf(tester, 'report-steps-value'), '9,955');
      expect(find.text('goal 9,430'), findsOneWidget);
      expect(find.text('6.7 km · 9 floors up'), findsOneWidget);
      await scrollTo(tester, find.byKey(const Key('report-moveiq')));
      expect(find.text('3h 11m'), findsOneWidget, reason: '活動時間＝高強度＋活動');
      expect(find.text('Rest 7h 41m · Low 3h 9m · Medium 4h 8m · High 35m'),
          findsOneWidget);
      expect(find.text('+48 / −61'), findsOneWidget);
      expect(find.text('1 walk · 1 ride'), findsOneWidget);
      expect(find.byKey(const Key('report-vo2')), findsNothing, reason: '同首頁拿掉 VO2 max');
      expect(find.textContaining('45.7'), findsNothing);
      expect(tester.takeException(), isNull, reason: '實機大小不溢出');
    });

    testWidgets('⚠️ 圖形真的畫出來（實機截圖抓到過：整條 0 高、看不見）', (tester) async {
      await pumpReport(tester, fullJson());
      await scrollTo(tester, find.byKey(const Key('report-moveiq')));
      for (final k in [
        'report-active-bar',
        'report-stress-gauge',
        'report-body-battery-bars',
        'report-moveiq-timeline',
      ]) {
        final size = tester.getSize(find.byKey(Key(k)));
        expect(size.height, greaterThan(8), reason: k);
        expect(size.width, greaterThan(40), reason: k);
      }
    });

    testWidgets('⚠️ 只寫事實：沒有達標、等級、警告字眼', (tester) async {
      await pumpReport(tester, fullJson());
      await scrollTo(tester, find.byKey(const Key('report-moveiq')));
      final texts = [
        for (final k in [
          'report-steps', 'report-active', 'report-stress',
          'report-body-battery', 'report-moveiq',
        ])
          ...tester
              .widgetList<Text>(find.descendant(
                  of: find.byKey(Key(k)), matching: find.byType(Text)))
              .map((t) => (t.data ?? '').toLowerCase()),
      ].join(' | ');
      expect(texts, contains('9,955'), reason: '反向對照：真的讀到字');
      for (final w in [
        'reached', 'achieved', 'good', 'normal', 'poor', 'great', 'excellent',
        'warning', 'too much', 'high stress', 'elevated', 'perfect',
      ]) {
        expect(texts.contains(w), isFalse, reason: w);
      }
    });

    testWidgets('單一項沒值 → 那一格不畫，不畫成 0', (tester) async {
      await pumpReport(tester, {'date': '2026-11-12', 'steps': 4210});
      await scrollTo(tester, find.byKey(const Key('report-steps')));
      expect(textOf(tester, 'report-steps-value'), '4,210');
      expect(find.textContaining('goal'), findsNothing, reason: '沒有目標就不寫 goal');
      for (final k in [
        'report-active', 'report-stress', 'report-body-battery',
        'report-day-hr', 'report-moveiq',
      ]) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
      expect(find.text('0'), findsNothing);
    });

    testWidgets('那天沒有 Move IQ（空的）→ 不畫那一格', (tester) async {
      await pumpReport(tester, {...fullJson(), 'move_iq': <Object>[]});
      await scrollTo(tester, find.byKey(const Key('report-body-battery')));
      expect(find.byKey(const Key('report-moveiq')), findsNothing);
    });

    testWidgets('沒有白天資料 → 整段「Yesterday」不畫', (tester) async {
      await pumpReport(tester, null, key: 'none');
      await scrollTo(tester, find.byKey(const Key('report-done')));
      expect(find.byKey(const Key('report-yesterday')), findsNothing);
      expect(find.byKey(const Key('report-steps')), findsNothing);
    });
  });
}
