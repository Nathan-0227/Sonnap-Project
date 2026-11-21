import 'package:app/models/night_curve.dart';
import 'package:app/models/sleep_stages.dart';
import 'package:app/services/camera_insights.dart';
import 'package:app/services/morning_report.dart';
import 'package:app/widgets/deep_sheet.dart';
import 'package:app/widgets/night_sheets.dart';
import 'package:app/widgets/night_week.dart';
import 'package:app/widgets/score_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 分數頁、深睡頁＋首頁與報告共用的 NightSheets（2026-11-21）。
/// 守的都是**壞掉時不會報錯**的地方：
/// - 沒資料的晚上算進中間值（當 0）→ Usually 被拉低、看起來正常
/// - 一週長條的顏色不照抄後端 score_color → Dart 多一份等級顏色表
/// - 分數頁出現各項得分 → 分數組成上了 App（11-19 定不上）
/// - REM 沒量到寫 0m／「—」→ 被讀成整晚沒有 REM／沒資料
/// - 深睡時的心率混進醒著的讀數

const _night = '2026-11-21';

// 11-21 那一晚的真實段落（後端 /home?date=2026-11-21 的 sleep_stages，節錄）
SleepStages _stages() => SleepStages.fromJsonOrNull({
      'segments': [
        for (final s in [
          ['2026-11-20T21:00:00+08:00', '2026-11-20T21:10:00+08:00', 'deep'],
          ['2026-11-20T21:10:00+08:00', '2026-11-20T22:17:00+08:00', 'light'],
          ['2026-11-20T22:17:00+08:00', '2026-11-20T22:34:00+08:00', 'deep'],
          ['2026-11-20T22:34:00+08:00', '2026-11-21T03:44:00+08:00', 'light'],
          ['2026-11-21T03:44:00+08:00', '2026-11-21T03:46:00+08:00', 'awake'],
        ])
          {'start': s[0], 'end': s[1], 'stage': s[2]},
      ],
      'minutes': {'awake': 5, 'rem': 0, 'light': 303, 'deep': 98},
      'rem_measured': false,
    })!;

NightCurve _hr() => NightCurve.fromJsonOrNull({
      'avg': 59,
      'min': 48,
      'max': 79,
      'points': [
        {'t': '2026-11-20T21:00:00+08:00', 'value': 50}, // deep
        {'t': '2026-11-20T21:05:00+08:00', 'value': 52}, // deep
        {'t': '2026-11-20T21:30:00+08:00', 'value': 60}, // light
        {'t': '2026-11-21T03:45:00+08:00', 'value': 99}, // awake：不能混進深睡、也不列
      ],
    })!;

MorningReport _report({bool remMeasured = false, double? waso = 5}) => MorningReport(
      date: _night,
      score: 91.7,
      quality: 'Good',
      qualityColor: '#9AD36A',
      sleepMinutes: 401,
      deepMinutes: 98,
      remMinutes: remMeasured ? 60 : 0,
      remMeasured: remMeasured,
      wasoMinutes: waso,
      efficiency: 98.77,
      efficiencyLabel: 'Watch only',
      stages: _stages(),
      heartRate: _hr(),
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

/// 按下去開詳細頁的按鈕（呼叫端給 NightSheets 的哪一個方法）。
Widget _opener(String key, Future<void> Function(BuildContext) open) => Builder(
      builder: (context) => TextButton(
        key: Key(key),
        onPressed: () => open(context),
        child: const Text('open'),
      ),
    );

Future<void> _open(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('一週：中間值與跟前一週比（純函式）', () {
    test('⚠️ 沒資料的晚上不算進中間值、寫 null 不是 0', () {
      final w = medianWeek({
        '2026-11-16': 71.6,
        '2026-11-17': 74.4,
        '2026-11-18': 10.5,
        '2026-11-19': 72.8,
        '2026-11-20': 77.6,
        '2026-11-21': 91.7,
      }, _night);
      expect(w.nights.length, 7);
      expect(w.nights.first, ('2026-11-15', null));
      expect(w.nightsWithData, 6);
      // 中間值＝(72.8 + 74.4) / 2；把 11-15 當 0 的話會變成 72.8
      expect(w.usual, closeTo(73.6, 1e-9));
      expect(medianWeekCountLine(w), '6 of 7 nights with data');
    });

    test('跟再往前 7 晚的中間值比；那一週沒資料就不比', () {
      final w = medianWeek({
        '2026-11-10': 70,
        '2026-11-21': 80,
      }, _night);
      expect(w.change, 10);
      expect(scoreChangeLine(w), '↑ 10 vs the week before');
      final alone = medianWeek({'2026-11-21': 80}, _night);
      expect(alone.change, isNull);
      expect(scoreChangeLine(alone), isNull);
    });

    test('深睡的比較寫成時長、只代表方向', () {
      final w = medianWeek({'2026-11-10': 35, '2026-11-21': 33}, _night);
      expect(deepChangeLine(w), '↓ 2m vs the week before');
    });
  });

  group('深睡頁', () {
    test('佔總睡眠幾成＝深睡 ÷ 手錶總睡眠，加上幾段', () {
      expect(deepShareLine(98, 401, 5), '24% of your sleep · 5 stretches');
      expect(deepShareLine(98, null, 1), '1 stretch');
      expect(deepShareLine(98, null, 0), isNull);
    });

    testWidgets('段落照 Sleep Stages 那一份；心率只列深睡與淺睡（沒量到 REM 不列、醒著不混）',
        (tester) async {
      await _pump(
        tester,
        DeepView(
          dateTitle: 'Sat, Nov 21',
          deepMinutes: 98,
          sleepMinutes: 401,
          stages: _stages(),
          heartRate: _hr(),
        ),
      );
      expect(find.byKey(const Key('deep-timeline')), findsOneWidget);
      expect(find.text('21:00 · 10m'), findsOneWidget);
      expect(find.text('22:17 · 17m'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('deep-hr-deep'))).data,
        '51',
        reason: '深睡那兩點的平均；混進醒著的 99 就不是 51',
      );
      expect(find.byKey(const Key('deep-hr-light')), findsOneWidget);
      expect(find.byKey(const Key('deep-hr-rem')), findsNothing);
      expect(find.byKey(const Key('deep-hr-awake')), findsNothing);
    });

    testWidgets('沒有一週資料（連不到後端）→ 下半整段不出現', (tester) async {
      await _pump(
        tester,
        const DeepView(dateTitle: 'Sat, Nov 21', deepMinutes: 98),
      );
      expect(find.byKey(const Key('deep-total')), findsOneWidget);
      expect(find.text('This week'), findsNothing);
    });
  });

  group('分數頁', () {
    testWidgets('⚠️ REM 沒量到寫 N/A（不是 0m、不是「—」）；沒資料的量寫「—」', (tester) async {
      await _pump(
        tester,
        _opener('go', (c) => NightSheets(_report(waso: null)).score(c)),
      );
      await _open(tester, 'go');
      expect(find.byKey(const Key('score-sheet')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('score-row-rem'))).data, 'N/A');
      expect(tester.widget<Text>(find.byKey(const Key('score-row-awake'))).data, '—');
      expect(tester.widget<Text>(find.byKey(const Key('score-row-sleep'))).data, '6h 41m');
      expect(tester.widget<Text>(find.byKey(const Key('score-row-efficiency'))).data, '98.77%');
      // REM 沒有詳細頁、醒著沒資料 → 都不能點
      expect(find.byKey(const Key('score-open-rem')), findsNothing);
      expect(find.byKey(const Key('score-open-awake')), findsNothing);
      expect(find.byKey(const Key('score-open-efficiency')), findsOneWidget);
    });

    testWidgets('一週長條的顏色照抄後端每晚的 score_color（Dart 沒有等級顏色表）', (tester) async {
      Future<Map<String, WearableNight>?> nights() async => {
            '2026-11-18': const WearableNight(score: 10.5, quality: 'Bad', scoreColor: '#FF4F63'),
            '2026-11-20': const WearableNight(score: 77.6, quality: 'Normal', scoreColor: '#123456'),
          };
      await _pump(
        tester,
        _opener('go', (c) => NightSheets(_report(), loadWearableNights: nights).score(c)),
      );
      await _open(tester, 'go');
      Color barColor(String date) {
        final boxes = find.descendant(
          of: find.byKey(Key('week-bar-$date')),
          matching: find.byType(Container),
        );
        final colors = [
          for (final e in boxes.evaluate())
            ((e.widget as Container).decoration as BoxDecoration?)?.color,
        ].whereType<Color>().where((c) => c.a > 0.5).toList();
        return colors.single.withValues(alpha: 1);
      }

      // 一個故意不屬於任何等級的顏色：Dart 自己有一張表的話畫不出它
      expect(barColor('2026-11-20'), const Color(0xFF123456));
      expect(barColor('2026-11-18'), const Color(0xFFFF4F63));
      // 這一晚用報告上的那一個
      expect(barColor(_night), const Color(0xFF9AD36A));
      expect(find.byKey(const Key('week-bar-2026-11-15')), findsOneWidget);
    });

    testWidgets('不出現各項得分（分數組成不上 App，11-19 定）', (tester) async {
      await _pump(tester, _opener('go', (c) => NightSheets(_report()).score(c)));
      await _open(tester, 'go');
      for (final s in [' pts', 'points', '/ 30', '/ 25', 'weight']) {
        expect(find.textContaining(s), findsNothing, reason: s);
      }
    });

    testWidgets('點效率那一列 → 收掉分數頁、開效率頁（不一層疊一層）', (tester) async {
      await _pump(tester, _opener('go', (c) => NightSheets(_report()).score(c)));
      await _open(tester, 'go');
      await _open(tester, 'score-open-efficiency');
      expect(find.byKey(const Key('eff-sheet')), findsOneWidget);
      expect(find.byKey(const Key('score-sheet')), findsNothing);
    });

    testWidgets('點深睡那一列 → 深睡頁', (tester) async {
      await _pump(tester, _opener('go', (c) => NightSheets(_report()).score(c)));
      await _open(tester, 'go');
      await _open(tester, 'score-open-deep');
      expect(find.byKey(const Key('deep-sheet')), findsOneWidget);
    });

    test('後端 /insights 的 score_color 讀得進來；舊版後端沒有是 null', () {
      expect(
        WearableNight.fromJson({'final_score': 80, 'score_color': '#9AD36A'}).scoreColor,
        '#9AD36A',
      );
      expect(WearableNight.fromJson({'final_score': 80}).scoreColor, isNull);
    });
  });

  group('沒有分數（手錶還沒到）', () {
    testWidgets('三頁都不開，不畫 0 分', (tester) async {
      const r = MorningReport(date: _night);
      await _pump(
        tester,
        Column(children: [
          _opener('score', (c) => NightSheets(r).score(c)),
          _opener('deep', (c) => NightSheets(r).deep(c)),
          _opener('eff', (c) => NightSheets(r).efficiency(c)),
        ]),
      );
      for (final k in ['score', 'deep', 'eff']) {
        await _open(tester, k);
      }
      expect(find.byKey(const Key('score-sheet')), findsNothing);
      expect(find.byKey(const Key('deep-sheet')), findsNothing);
      expect(find.byKey(const Key('eff-sheet')), findsNothing);
    });
  });
}
