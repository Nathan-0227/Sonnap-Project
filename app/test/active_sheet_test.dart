// 早晨報告 Active time（2026-11-15 使用者定，參考圖 Activity 那座山）。
// 守：山照「面積」切（不是高度）；圓環四段＝24 小時；睡著標 this day；時間軸沒戴錶空著、
//     泡泡照抄程度與步數；一週 0＝沒資料、高強度疊在下面；不寫 Perfect／goal／150／坐太久。
import 'dart:math' as math;

import 'package:app/models/yesterday_activity.dart';
import 'package:app/widgets/active_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 10-31 → 11-13：前 7 天 60 分；後 7 天 80+i 分（高強度 10）；11-10（i=10）0＝沒戴錶。
List<ActivityHistoryDay> twoWeeks() => [
  for (var i = 0; i < 14; i++)
    ActivityHistoryDay(
      date: iso(DateTime(2026, 10, 31).add(Duration(days: i))),
      activeMinutes: i == 10 ? 0 : (i < 7 ? 60 : 80 + i),
      highlyActiveMinutes: i < 7 ? 5 : 10,
    ),
];

/// 11-14 的真實數字：高強度 690、活動 4212、久坐 58818、睡 22680（加起來 86400）。
List<ActivityQuarter?> quarters() => [
  for (var i = 0; i < 96; i++)
    i < 28
        ? const ActivityQuarter('sleep', 0)
        : i == 35
        ? const ActivityQuarter('high', 852)
        : i == 36
        ? const ActivityQuarter('active', 736)
        : i == 40
        ? null
        : i == 41
        ? const ActivityQuarter('other', 50)
        : const ActivityQuarter('still', 12),
];

YesterdayActivity day({int? sleeping = 22680, bool withQuarters = true}) =>
    YesterdayActivity(
      date: '2026-11-13',
      highlyActiveSec: 690,
      activeSec: 4212,
      sedentarySec: 58818,
      sleepingSec: sleeping,
      history: twoWeeks(),
      activityQuarters: withQuarters ? quarters() : null,
      moveIq: const [MoveIqEvent(type: 'Walk', start: '08:40', minutes: 25)],
    );

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 390, height: 1500, child: child)),
);

Future<void> big(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 1500 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

String textOf(WidgetTester t, String k) =>
    t.widget<Text>(find.byKey(Key(k))).data!;

void main() {
  group('山', () {
    test('照面積切：每一段在（不規則的）山裡佔的面積＝那段的比例；順序高強度 → 活動 → 坐 → 睡', () {
      final b = mountainBands(activeParts(day())!);
      expect(b.map((e) => e.$1), ['high', 'active', 'still', 'sleep']);
      expect(b.first.$2, 0);
      expect(b.last.$3, closeTo(1, 1e-9));
      // 直接對輪廓積分驗算（不重用程式裡那張表）
      double area(double t0, double t1) {
        const n = 2000;
        var sum = 0.0;
        for (var i = 0; i < n; i++) {
          sum += mountainWidth(t0 + (t1 - t0) * (i + 0.5) / n);
        }
        return sum * (t1 - t0) / n;
      }

      final whole = area(0, 1);
      const shares = {
        'high': 690,
        'active': 4212,
        'still': 58818,
        'sleep': 22680,
      };
      for (final (level, top, bottom) in b) {
        expect(
          area(top, bottom) / whole,
          closeTo(shares[level]! / 86400, 0.002),
          reason: level,
        );
      }
      // 照高度切只會是 0.057；山胖之後（11-15 第五輪）山頂變寬，同樣面積佔的高度變矮，約 0.18
      expect(b[1].$3, greaterThan(0.15), reason: '6% 的活動要看得到，不是山尖一個點');
    });

    test('輪廓不規則：兩邊不是直線（但每個高度只有一段）', () {
      final mids = [
        for (final t in [0.25, 0.5, 0.75]) mountainWidth(t) / t,
      ];
      expect(
        mids.reduce(math.max) - mids.reduce(math.min),
        greaterThan(0.05),
        reason: '直邊三角形的話寬度÷高度是常數',
      );
      var prev = 0.0;
      for (var i = 1; i <= 100; i++) {
        final w = mountainWidth(i / 100);
        expect(w, greaterThanOrEqualTo(prev), reason: '往下只會變寬');
        prev = w;
      }
    });

    test('佔 0 的段不畫；三種有缺 → 沒有山；睡著沒有當 0', () {
      final p = activeParts(
        const YesterdayActivity(
          date: 'x',
          highlyActiveSec: 0,
          activeSec: 600,
          sedentarySec: 600,
        ),
      )!;
      expect(mountainBands(p).map((e) => e.$1), ['active', 'still']);
      expect(
        activeParts(const YesterdayActivity(date: 'x', activeSec: 1)),
        isNull,
      );
    });

    test('小字只寫事實', () {
      expect(activeTileLine(activeParts(day())!), 'high 12m · still 16h 20m');
    });
  });

  group('純函式', () {
    test('時間軸泡泡', () {
      expect(
        activeQuarterText(36, const ActivityQuarter('active', 736)),
        '09:00–09:15 · Active · 736 steps',
      );
      expect(activeQuarterText(40, null), '10:00–10:15 · no data');
      expect(
        activeQuarterText(95, const ActivityQuarter('sleep', 0)),
        '23:45–24:00 · Asleep · 0 steps',
      );
      expect(
        activeQuarterText(41, const ActivityQuarter('other', 50)),
        '10:15–10:30 · Unlabeled · 50 steps',
      );
    });

    test('一週：0＝沒資料、不算中間值；前一週比只寫方向', () {
      final w = activeWeek(twoWeeks(), '2026-11-13');
      expect(w.days.map((d) => d.minutes), [87, 88, 89, null, 91, 92, 93]);
      expect(w.days.last.highMinutes, 10);
      expect(w.usual, 90);
      expect(activeUsualLine(w), 'Usually 1h 30m active');
      expect(activeCountLine(w), '6 of 7 days with data');
      expect(activeChangeLine(w), '↑ 30m vs the week before');
    });

    test('解析：activity_quarters 96 格、不認得的程度當沒資料；sleeping_sec；高強度分鐘', () {
      final y = YesterdayActivity.fromJsonOrNull({
        'date': '2026-11-13',
        'activity': {'sleeping_sec': 22680},
        'activity_quarters': [
          for (var i = 0; i < 96; i++)
            i == 3
                ? ['high', 852]
                : i == 4
                ? ['weird', 1]
                : i == 5
                ? null
                : ['still', 0],
        ],
        'history': [
          {'date': '2026-11-13', 'highly_active_minutes': 11},
        ],
      })!;
      expect(y.sleepingSec, 22680);
      expect(y.activityQuarters![3]!.level, 'high');
      expect(y.activityQuarters![4], isNull);
      expect(y.activityQuarters![5], isNull);
      expect(y.history.single.highlyActiveMinutes, 11);
      expect(
        YesterdayActivity.fromJsonOrNull({
          'date': 'x',
          'activity_quarters': [
            ['still', 0],
          ],
        })!.activityQuarters,
        isNull,
      );
    });
  });

  group('畫面', () {
    testWidgets('那一天：圓環＋四行；睡著標 this day；中間活動時間', (tester) async {
      await big(tester);
      await tester.pumpWidget(host(ActiveView(day: day())));
      expect(find.byKey(const Key('active-ring')), findsOneWidget);
      expect(textOf(tester, 'active-total'), '1h 22m');
      for (final (k, v) in [
        ('active-high', '12m'),
        ('active-active', '1h 10m'),
        ('active-still', '16h 20m'),
        ('active-sleep', '6h 18m'),
      ]) {
        expect(
          find.descendant(of: find.byKey(Key(k)), matching: find.text(v)),
          findsOneWidget,
          reason: k,
        );
      }
      expect(find.text('Asleep (this day)'), findsOneWidget);
      expect(textOf(tester, 'active-note'), contains('calendar day'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('時間軸：沒戴錶那格是空的；點一下出泡泡；Move IQ 標在上面', (tester) async {
      await big(tester);
      await tester.pumpWidget(host(ActiveView(day: day())));
      final empty = tester.widget<Container>(
        find.byKey(const Key('active-q-40')),
      );
      expect(empty.color, const Color(0x0FFFFFFF));
      final r = tester.getRect(find.byKey(const Key('active-timeline')));
      await tester.tapAt(Offset(r.left + r.width * 36.5 / 96, r.center.dy));
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('chart-probe-text'))).data,
        '09:00–09:15 · Active · 736 steps',
      );
      final mv = tester.getRect(find.byKey(const Key('active-moveiq-0')));
      expect(mv.left, closeTo(r.left + r.width * (8 * 60 + 40) / 1440, 0.5));
      expect(mv.bottom, lessThan(r.top), reason: '在時間軸上面');
      expect(find.text('Unlabeled'), findsOneWidget, reason: '有 other 才列圖例');
    });

    testWidgets('一週：高強度疊在下面、0 寫 —', (tester) async {
      await big(tester);
      await tester.pumpWidget(host(ActiveView(day: day())));
      expect(textOf(tester, 'active-week-usual'), 'Usually 1h 30m active');
      final hi = tester.getRect(find.byKey(const Key('active-week-high-6')));
      final act = tester.getRect(find.byKey(const Key('active-week-bar-6')));
      expect(hi.top, closeTo(act.bottom, 0.01), reason: '高強度在下面');
      expect(
        find.descendant(
          of: find.byKey(const Key('active-week-3')),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('沒有每 15 分鐘的資料（舊版後端）→ 時間軸那段不出現', (tester) async {
      await big(tester);
      await tester.pumpWidget(host(ActiveView(day: day(withQuarters: false))));
      expect(find.text('Through the day'), findsNothing);
      expect(find.byKey(const Key('active-ring')), findsOneWidget);
    });

    testWidgets('⚠️ 不寫 perfect／goal／150／intensity／坐太久', (tester) async {
      await big(tester);
      await tester.pumpWidget(host(ActiveView(day: day())));
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => (t.data ?? '').toLowerCase())
          .join('|');
      expect(texts, contains('1h 22m'), reason: '反向對照：真的讀到字');
      for (final w in [
        'perfect',
        'goal',
        '150',
        'intensity',
        'too long',
        'sitting too',
        'good',
        'great',
      ]) {
        expect(texts.contains(w), isFalse, reason: w);
      }
    });
  });
}
