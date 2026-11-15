// 早晨報告 Stress（2026-11-15 使用者定，參考圖 Stress 卡）。
// 守：圓頂各段面積＝各程度比例；紫色系不用紅黃；大字不加 %、不寫 Elevated；
//     壓力線量不到斷開、泡泡吸到真讀數（超過 3 分鐘寫 no reading）、程度照 Garmin 的分法；
//     一週沒資料寫 —、高在最下面；不提分數、不給建議。
import 'package:app/models/night_curve.dart';
import 'package:app/models/yesterday_activity.dart';
import 'package:app/widgets/stress_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 10-31 → 11-13：前 7 天平均 30；後 7 天 20+i；11-10（i=10）沒戴錶（各程度都 0）。
List<ActivityHistoryDay> twoWeeks() => [
  for (var i = 0; i < 14; i++)
    ActivityHistoryDay(
      date: iso(DateTime(2026, 10, 31).add(Duration(days: i))),
      stressMinutes: i == 10
          ? const {'rest': 0, 'low': 0, 'medium': 0, 'high': 0}
          : const {'rest': 600, 'low': 300, 'medium': 200, 'high': 40},
      stressAvg: i == 10 ? null : (i < 7 ? 30 : 20 + i),
    ),
];

NightCurvePoint pt(int minute, double v) =>
    NightCurvePoint(DateTime.utc(2026, 11, 13, minute ~/ 60, minute % 60), v);

/// 00:00 起每 3 分鐘；09:00–10:00 量不到（在動）；14:21 是 62。
NightCurve curve() => NightCurve(
  points: [
    for (var m = 0; m < 1440; m += 3)
      if (m < 540 || m >= 600) pt(m, m == 861 ? 62 : (m < 420 ? 12 : 30)),
  ],
  avg: 25,
  min: 2,
  max: 96,
);

YesterdayActivity day({NightCurve? c, int? notMeasured = 22440}) =>
    YesterdayActivity(
      date: '2026-11-13',
      stressRestSec: 27660,
      stressLowSec: 11340,
      stressMediumSec: 14880,
      stressHighSec: 2100,
      stressNotMeasuredSec: notMeasured,
      stressCurve: c,
      history: twoWeeks(),
      activityQuarters: [
        for (var i = 0; i < 96; i++)
          i < 28
              ? const ActivityQuarter('sleep', 0)
              : const ActivityQuarter('still', 5),
      ],
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
  group('圓頂', () {
    test('由上往下 高 → 中 → 低 → 休息；每一段面積＝那段的比例（直接積分驗算）', () {
      const aspect = 1.1;
      final p = stressParts(day())!;
      final b = stressDomeBands(p, aspect);
      expect(b.map((e) => e.$1), ['high', 'medium', 'low', 'rest']);
      double area(double y0, double y1) {
        const n = 4000;
        var s = 0.0;
        for (var i = 0; i < n; i++) {
          s += stressDomeWidth(y0 + (y1 - y0) * (i + 0.5) / n, aspect);
        }
        return s * (y1 - y0) / n;
      }

      final whole = area(0, 1);
      for (final (level, y0, y1) in b) {
        expect(
          area(y0, y1) / whole,
          closeTo(p.of(level) / p.total, 0.003),
          reason: level,
        );
      }
    });

    test('整個半圓露出來：平的一邊貼底，左、右、上都沒被格子切掉', () {
      for (final aspect in [0.8, 1.0, 1.1, 1.6]) {
        final c = stressDomeCircle(aspect);
        expect(c.cy, 1.0, reason: '圓心在底邊');
        expect(c.cx - c.r, greaterThanOrEqualTo(0), reason: '左邊沒被切');
        expect(c.cx + c.r, lessThanOrEqualTo(aspect), reason: '右邊沒被切');
        expect(c.cy - c.r, greaterThanOrEqualTo(0), reason: '頂端沒被切');
        expect(
          stressDomeWidth(0.9999, aspect),
          closeTo(2 * c.r, 0.01),
          reason: '貼底那一邊是整條直徑',
        );
      }
    });

    test('紫色系：沒有紅、黃、橘', () {
      for (final l in stressLevels) {
        final c = stressLevelColor(l);
        expect(
          (c.b * 255).round(),
          greaterThan((c.g * 255).round()),
          reason: '$l 要偏紫藍，不是紅黃',
        );
      }
    });

    test('Garmin 的四個程度：0–25 休息、26–50 低、51–75 中、76–100 高', () {
      expect([0, 25, 26, 50, 51, 75, 76, 100].map(stressLevelOf), [
        'rest',
        'rest',
        'low',
        'low',
        'medium',
        'medium',
        'high',
        'high',
      ]);
    });
  });

  group('純函式', () {
    test('泡泡吸到最近的真讀數；離讀數超過 3 分鐘 → no reading（不內插）', () {
      final pts = curve().points;
      expect(stressProbeText(pts, 861), '14:21 · 62 · Medium');
      expect(stressProbeText(pts, 862), '14:21 · 62 · Medium');
      expect(stressProbeText(pts, 570), '09:30 · no reading');
      expect(stressProbeText(pts, 60), '01:00 · 12 · Rest');
    });

    test('平均：有壓力線用線的；沒有就用一週資料裡那天的', () {
      expect(stressAvgOf(day(c: curve())), 25);
      expect(stressAvgOf(day()), 33);
    });

    test('一週：沒戴錶＝沒資料、不算中間值；比前一週只寫方向', () {
      final w = stressWeek(twoWeeks(), '2026-11-13');
      expect(w.days.map((d) => d.avg), [27, 28, 29, null, 31, 32, 33]);
      expect(w.days[3].minutes, isNull);
      expect(w.usual, 30);
      expect(stressUsualLine(w), 'Usually avg 30');
      expect(stressCountLine(w), '6 of 7 days with data');
      expect(stressChangeLine(w), '= same as the week before');
    });

    test('解析：not_measured_sec、stress_curve、history 的各程度分鐘與平均', () {
      final y = YesterdayActivity.fromJsonOrNull({
        'date': '2026-11-13',
        'stress': {'rest_sec': 60, 'not_measured_sec': 22440},
        'stress_curve': {
          'points': [
            {'t': '2026-11-13T00:00:00+08:00', 'value': 12},
            {'t': '2026-11-13T00:03:00+08:00', 'value': 14},
          ],
          'avg': 13,
          'min': 12,
          'max': 14,
        },
        'history': [
          {
            'date': '2026-11-13',
            'stress_minutes': {
              'rest': 461,
              'low': 189,
              'medium': 248,
              'high': 35,
            },
            'stress_avg': 25,
          },
        ],
      })!;
      expect(y.stressNotMeasuredSec, 22440);
      expect(y.stressCurve!.points.first.time.hour, 0, reason: '牆鐘，不換 UTC');
      expect(y.history.single.stressMinutes!['high'], 35);
      expect(y.history.single.stressAvg, 25);
    });
  });

  group('畫面', () {
    testWidgets('那一天：圓環＋四行＋平均；Not measured；寫明是讀數的平均', (tester) async {
      await big(tester);
      await tester.pumpWidget(host(StressView(day: day(c: curve()))));
      expect(find.byKey(const Key('stress-ring')), findsOneWidget);
      expect(textOf(tester, 'stress-avg'), '25');
      for (final (k, v) in [
        ('stress-high', '35m'),
        ('stress-medium', '4h 8m'),
        ('stress-low', '3h 9m'),
        ('stress-rest', '7h 41m'),
      ]) {
        expect(
          find.descendant(of: find.byKey(Key(k)), matching: find.text(v)),
          findsOneWidget,
          reason: k,
        );
      }
      expect(
        textOf(tester, 'stress-not-measured'),
        'Not measured 6h 14m (moving or watch off)',
      );
      expect(
        textOf(tester, 'stress-note'),
        contains('average is of the readings'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('壓力線：點 14:21 出泡泡；點在量不到的時段寫 no reading', (tester) async {
      await big(tester);
      await tester.pumpWidget(host(StressView(day: day(c: curve()))));
      final r = tester.getRect(find.byKey(const Key('stress-day-line')));
      await tester.tapAt(Offset(r.left + r.width * 861 / 1440, r.center.dy));
      await tester.pump();
      expect(textOf(tester, 'chart-probe-text'), '14:21 · 62 · Medium');
      await tester.tapAt(Offset(r.left + r.width * 570 / 1440, r.center.dy));
      await tester.pump();
      expect(textOf(tester, 'chart-probe-text'), '09:30 · no reading');
    });

    testWidgets('一週：高在最下面、沒資料寫 —', (tester) async {
      await big(tester);
      await tester.pumpWidget(host(StressView(day: day(c: curve()))));
      expect(textOf(tester, 'stress-week-usual'), 'Usually avg 30');
      final high = tester.getRect(find.byKey(const Key('stress-week-high-6')));
      final rest = tester.getRect(find.byKey(const Key('stress-week-rest-6')));
      expect(high.top, greaterThan(rest.top), reason: '高在最下面');
      expect(
        find.descendant(
          of: find.byKey(const Key('stress-week-3')),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('沒有壓力線（舊資料）→ 那一段不出現；舊日子沒存量不到的時間 → 那一行不出現', (tester) async {
      await big(tester);
      await tester.pumpWidget(host(StressView(day: day(notMeasured: null))));
      expect(find.text('Through the day'), findsNothing);
      expect(find.byKey(const Key('stress-not-measured')), findsNothing);
      expect(find.byKey(const Key('stress-ring')), findsOneWidget);
    });

    testWidgets('⚠️ 不寫 Elevated、%、建議、分數', (tester) async {
      await big(tester);
      await tester.pumpWidget(host(StressView(day: day(c: curve()))));
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => (t.data ?? '').toLowerCase())
          .join('|');
      expect(texts, contains('avg stress'), reason: '反向對照：真的讀到字');
      for (final w in [
        'elevated',
        '%',
        'breath',
        'relax',
        'score you',
        'sleep score',
        'too high',
        'good',
      ]) {
        expect(texts.contains(w), isFalse, reason: w);
      }
    });
  });
}
