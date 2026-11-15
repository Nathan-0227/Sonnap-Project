// 早晨報告 Active kcal 點開＝Calories 頁（2026-11-15 使用者定，參考圖 My Diary）。
// 守：圓環＝靜止＋活動、中間總消耗照抄；舊日子沒有靜止代謝就不畫圓環；
//     不做 Eaten／kcal left／目標／達標；一週 0＝沒資料（—、不算中間值）；比前一週只寫方向。
import 'package:app/models/yesterday_activity.dart';
import 'package:app/widgets/kcal_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 10-31 → 11-13：前 7 天 200；後 7 天 300+i；11-10（i=10）0＝沒戴錶。
List<ActivityHistoryDay> twoWeeks() => [
  for (var i = 0; i < 14; i++)
    ActivityHistoryDay(
      date: iso(DateTime(2026, 10, 31).add(Duration(days: i))),
      activeKcal: i == 10 ? 0 : (i < 7 ? 200 : 300 + i),
    ),
];

YesterdayActivity day({int? resting = 1927, int? total = 2150}) =>
    YesterdayActivity(
      date: '2026-11-13',
      activeKcal: 223,
      restingKcal: resting,
      totalKcal: total,
      history: twoWeeks(),
    );

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 390, height: 1400, child: child)),
);

Future<void> big(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

String textOf(WidgetTester t, String k) =>
    t.widget<Text>(find.byKey(Key(k))).data!;

void main() {
  test('一週：日曆上 7 天；0＝沒資料、不算中間值；前一週比只寫方向', () {
    final w = kcalWeek(twoWeeks(), '2026-11-13');
    expect(w.days.map((d) => d.active), [307, 308, 309, null, 311, 312, 313]);
    expect(w.usual, 310);
    expect(kcalUsualLine(w), 'Usually 310 active kcal');
    expect(kcalCountLine(w), '6 of 7 days with data');
    expect(kcalChangeLine(w), '↑ 110 kcal vs the week before');
  });

  test('圓環三個數字都要有才畫', () {
    expect(kcalHasRing(day()), isTrue);
    expect(kcalHasRing(day(resting: null)), isFalse);
    expect(kcalHasRing(day(total: null)), isFalse);
  });

  testWidgets('那一天：圓環＋Resting／Active，中間總消耗照抄；寫明是 Garmin 估的', (tester) async {
    await big(tester);
    await tester.pumpWidget(host(KcalView(day: day())));
    expect(find.byKey(const Key('kcal-ring')), findsOneWidget);
    expect(textOf(tester, 'kcal-total'), '2,150');
    expect(
      find.descendant(
        of: find.byKey(const Key('kcal-resting')),
        matching: find.text('1,927'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('kcal-active')),
        matching: find.text('223'),
      ),
      findsOneWidget,
    );
    expect(textOf(tester, 'kcal-note'), contains('Estimated by Garmin'));
    expect(textOf(tester, 'kcal-week-usual'), 'Usually 310 active kcal');
    expect(
      find.descendant(
        of: find.byKey(const Key('kcal-week-3')),
        matching: find.text('—'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('舊日子沒有靜止代謝 → 不畫圓環，只畫活動的大數字（不畫成 0）', (tester) async {
    await big(tester);
    await tester.pumpWidget(
      host(KcalView(day: day(resting: null, total: null))),
    );
    expect(find.byKey(const Key('kcal-ring')), findsNothing);
    expect(textOf(tester, 'kcal-active-big'), '223');
    expect(find.text('0'), findsNothing);
  });

  testWidgets('⚠️ 不做 Eaten／kcal left／目標／達標', (tester) async {
    await big(tester);
    await tester.pumpWidget(host(KcalView(day: day())));
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => (t.data ?? '').toLowerCase())
        .join('|');
    expect(texts, contains('2,150'), reason: '反向對照：真的讀到字');
    for (final w in [
      'eaten',
      'left',
      'goal',
      'remaining',
      'reached',
      'deficit',
      'good',
    ]) {
      expect(texts.contains(w), isFalse, reason: w);
    }
  });

  test('解析：resting_kcal／total_kcal 照抄', () {
    final y = YesterdayActivity.fromJsonOrNull({
      'date': '2026-11-13',
      'active_kcal': 223,
      'resting_kcal': 1927,
      'total_kcal': 2150,
    })!;
    expect((y.restingKcal, y.totalKcal), (1927, 2150));
  });
}
