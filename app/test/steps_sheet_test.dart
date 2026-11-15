// 早晨報告 Steps（2026-11-15 使用者定，照參考圖 Step Counter）。
// 守：超過目標滿圈但不寫 reached；每小時沒戴錶的鐘頭空著（不畫成 0）、有戴 0 步畫細線；
//     不寫每小時加總；一週 0 步＝沒資料（—、不算中間值）；每天自己的目標；只代表方向。
import 'package:app/models/yesterday_activity.dart';
import 'package:app/widgets/steps_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<int?> hours() => [
  for (var h = 0; h < 24; h++)
    h == 9 ? null : (h < 7 ? 0 : (h == 14 ? 1230 : 40)),
];

YesterdayActivity day({
  List<int?>? hourly,
  List<ActivityHistoryDay>? history,
}) => YesterdayActivity(
  date: '2026-11-13',
  steps: 5347,
  stepGoal: 9540,
  distanceM: 3668,
  activeKcal: 223,
  highlyActiveSec: 995,
  activeSec: 3891,
  floorsUp: 10,
  stepsHourly: hourly,
  history: history ?? const [],
);

String iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 10-31 → 11-13 共 14 天：前 7 天 4000 步；後 7 天 6000+i；11-10（i=10）0 步＝沒戴錶。
List<ActivityHistoryDay> twoWeeks() => [
  for (var i = 0; i < 14; i++)
    ActivityHistoryDay(
      date: iso(DateTime(2026, 10, 31).add(Duration(days: i))),
      steps: i == 10 ? 0 : (i < 7 ? 4000 : 6000 + i),
      stepGoal: 9000 + i,
    ),
];

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 390, height: 1600, child: child)),
);

Future<void> big(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  group('純函式', () {
    test('弧線：步數÷目標；超過就是 1（滿圈）；沒有目標 null', () {
      expect(stepsFraction(5347, 9540), closeTo(0.5605, 0.001));
      expect(stepsFraction(12000, 9540), 1.0);
      expect(stepsFraction(5347, null), isNull);
    });

    test('底下那行：km · floors；沒值不寫', () {
      expect(stepsStatsLine(3668, 10.4), '3.7 km · 10 floors');
      expect(stepsStatsLine(null, 3), '3 floors');
      expect(stepsStatsLine(null, null), isNull);
    });

    test('每小時泡泡；沒戴錶寫 no data（不寫 0）', () {
      expect(stepsHourText(14, 1230), '14:00 · 1,230 steps');
      expect(stepsHourText(9, null), '09:00 · no data');
      expect(stepsHourText(3, 0), '03:00 · 0 steps');
    });

    test('一週：日曆上 7 天；0 步＝沒資料、不算中間值；前一週比只寫方向', () {
      final w = stepsWeek(twoWeeks(), '2026-11-13');
      expect(w.days.length, 7);
      expect(w.days.last.date, '2026-11-13');
      expect(w.days.map((d) => d.steps), [
        6007,
        6008,
        6009,
        null,
        6011,
        6012,
        6013,
      ]);
      expect(w.days.last.goal, 9013, reason: '每天自己的目標');
      expect(w.usual, 6010);
      expect(stepsUsualLine(w), 'Usually 6,010 steps');
      expect(stepsCountLine(w), '6 of 7 days with data');
      expect(stepsChangeLine(w), '↑ 2,010 steps vs the week before');
    });
  });

  group('畫面', () {
    testWidgets('那一天：圓弧、Goal、Garmin 自己調目標、四項', (tester) async {
      await big(tester);
      await tester.pumpWidget(
        host(
          StepsView(
            day: day(hourly: hours(), history: twoWeeks()),
          ),
        ),
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('steps-value'))).data,
        '5,347',
      );
      expect(find.text('Goal 9,540'), findsOneWidget);
      expect(find.text('Goal set by Garmin, changes daily'), findsOneWidget);
      for (final t in [
        '3.7',
        'km',
        '223',
        'active kcal',
        '1h 21m',
        '10',
        'floors',
      ]) {
        expect(
          find.descendant(
            of: find.byKey(const Key('steps-stats')),
            matching: find.text(t),
          ),
          findsOneWidget,
          reason: t,
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('每小時：沒戴錶不畫、0 步畫細線；點一下出泡泡；不寫加總', (tester) async {
      await big(tester);
      await tester.pumpWidget(host(StepsView(day: day(hourly: hours()))));
      expect(
        find.byKey(const Key('steps-hour-9')),
        findsNothing,
        reason: '沒戴錶空著',
      );
      expect(
        tester.getSize(find.byKey(const Key('steps-hour-3'))).height,
        2,
        reason: '0 步是細線',
      );
      expect(
        tester.getSize(find.byKey(const Key('steps-hour-14'))).height,
        greaterThan(
          tester.getSize(find.byKey(const Key('steps-hour-20'))).height,
        ),
      );
      final r = tester.getRect(find.byKey(const Key('steps-hours')));
      await tester.tapAt(Offset(r.left + r.width * 14.5 / 24, r.center.dy));
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('chart-probe-text'))).data,
        '14:00 · 1,230 steps',
      );
      await tester.dragFrom(
        Offset(r.left + r.width * 14.5 / 24, r.center.dy),
        Offset(-r.width * 5 / 24, 0),
      );
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('chart-probe-text'))).data,
        '09:00 · no data',
      );
      expect(
        find.textContaining('total'),
        findsNothing,
        reason: '不寫加總（大數字已是官方總數）',
      );
    });

    testWidgets('沒有每小時資料（舊版後端）→ 那一段不出現；沒有一週資料也不畫', (tester) async {
      await big(tester);
      await tester.pumpWidget(host(StepsView(day: day())));
      expect(find.text('Steps each hour'), findsNothing);
      expect(find.byKey(const Key('steps-week-usual')), findsNothing);
    });

    testWidgets('一週：7 根、每天自己的目標線、0 步寫 —、比前一週只寫方向', (tester) async {
      await big(tester);
      await tester.pumpWidget(host(StepsView(day: day(history: twoWeeks()))));
      expect(
        tester.widget<Text>(find.byKey(const Key('steps-week-usual'))).data,
        'Usually 6,010 steps',
      );
      // 目標＝淡色空長條（不是一條線）；走了多少從底下填，沒走到目標就比空條矮
      final goal = tester.getRect(find.byKey(const Key('steps-week-goal-6')));
      final bar = tester.getRect(find.byKey(const Key('steps-week-bar-6')));
      expect(goal.height, greaterThan(20), reason: '是一根長條，不是 2 px 的線');
      expect(bar.height, lessThan(goal.height));
      expect(bar.bottom, goal.bottom, reason: '從同一條底線往上');
      expect(
        find.byKey(const Key('steps-week-goal-3')),
        findsOneWidget,
        reason: '沒資料的那天也有空條，不會空一格',
      );
      expect(find.byKey(const Key('steps-week-bar-3')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('steps-week-3')),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('steps-week-change')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('⚠️ 超過目標：滿圈，但不寫 reached／achieved／goal met', (tester) async {
      await big(tester);
      final over = YesterdayActivity(
        date: '2026-11-13',
        steps: 12000,
        stepGoal: 9540,
        history: twoWeeks(),
      );
      await tester.pumpWidget(host(StepsView(day: over)));
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => (t.data ?? '').toLowerCase())
          .join('|');
      expect(texts, contains('12,000'), reason: '反向對照：真的讀到字');
      for (final w in [
        'reached',
        'achieved',
        'goal met',
        'great',
        'well done',
        'good',
      ]) {
        expect(texts.contains(w), isFalse, reason: w);
      }
    });
  });

  test('解析：steps_hourly 24 格（null 留著）；history 帶目標與距離；格式不對就 null', () {
    final y = YesterdayActivity.fromJsonOrNull({
      'date': '2026-11-13',
      'steps_hourly': [for (var h = 0; h < 24; h++) h == 9 ? null : h],
      'history': [
        {
          'date': '2026-11-13',
          'steps': 5,
          'step_goal': 9540,
          'distance_m': 3668,
        },
      ],
    })!;
    expect(y.stepsHourly![9], isNull);
    expect(y.stepsHourly![14], 14);
    expect(y.history.single.stepGoal, 9540);
    expect(y.history.single.distanceM, 3668);
    expect(
      YesterdayActivity.fromJsonOrNull({
        'date': 'x',
        'steps_hourly': [1, 2],
      })!.stepsHourly,
      isNull,
    );
  });
}
