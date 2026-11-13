// 早晨報告的 Heart rate 卡（2026-11-13 使用者定：照參考圖改成線條）。
// 守：照抄後端（平均是睡著期間的）、不寫 Normal、曲線不衝出實際最高最低、
//     時間是牆鐘不是 UTC、有卡時 More details 不再寫一次心率、沒曲線整張不畫。
import 'package:app/models/heart_rate_curve.dart';
import 'package:app/screens/morning_report_screen.dart';
import 'package:app/services/morning_report.dart';
import 'package:app/widgets/heart_rate_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> curveJson() => {
      'points': [
        for (var i = 0; i < 24; i++)
          {
            't': '${DateTime(2026, 11, 12, 1, 0).add(Duration(minutes: 5 * i)).toIso8601String().replaceFirst('.000', '')}+08:00',
            // 有起有伏、有急轉：一般平滑曲線會在這種地方衝過頭
            'bpm': [60, 52, 48, 70, 50, 49, 66, 54][i % 8],
          }
      ],
      'avg': 56,
      'min': 48,
      'max': 70,
      'bucket_minutes': 5,
    };

Map<String, dynamic> home({Object? curve, double? avgHr = 80}) => {
      'date': '2026-11-13',
      'behavior': null,
      'metrics': {
        'sleep_duration_minutes': 300,
        'avg_heart_rate': avgHr,
        'resting_heart_rate': 52,
        'heart_rate_curve': curve,
      },
      'scoring': {'final_score': 70.0, 'final_quality': 'Normal'},
    };

Future<void> pumpReport(WidgetTester tester, MorningReport r, String key) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      home: MorningReportScreen(key: ValueKey(key), initial: r)));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  test('解析：照抄平均／最低／最高；時間照字串的牆鐘，不換成 UTC', () {
    final c = HeartRateCurve.fromJsonOrNull(curveJson())!;
    expect((c.avg, c.min, c.max), (56, 48, 70));
    expect(c.points.first.time.hour, 1, reason: '+08:00 的 01:00 不能變成 17:00');
    expect(HeartRateCurve.fromJsonOrNull(null), isNull);
    expect(HeartRateCurve.fromJsonOrNull({'points': [], 'avg': 1, 'min': 1, 'max': 1}),
        isNull);
  });

  test('⚠️ 曲線不衝出實際最高最低（平滑曲線最容易在急轉處畫出沒發生的值）', () {
    final ys = <double>[60, 52, 48, 70, 50, 49, 66, 54, 60, 52, 48, 70];
    final xs = [for (var i = 0; i < ys.length; i++) i * 20.0];
    final path = monotonePath(xs, ys);
    final lo = ys.reduce((a, b) => a < b ? a : b);
    final hi = ys.reduce((a, b) => a > b ? a : b);
    for (final m in path.computeMetrics()) {
      for (double d = 0; d <= m.length; d += 0.5) {
        final p = m.getTangentForOffset(d)!.position;
        expect(p.dy, inInclusiveRange(lo - 0.01, hi + 0.01), reason: 'x=${p.dx}');
      }
    }
  });

  testWidgets('卡片：大字是睡著期間的平均，照實寫最低與靜止；不寫 Normal', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HeartRateCard(
          curve: HeartRateCurve.fromJsonOrNull(curveJson())!,
          restingHeartRate: 52,
        ),
      ),
    ));
    expect(tester.widget<Text>(find.byKey(const Key('heart-rate-avg'))).data, '56');
    expect(tester.widget<Text>(find.byKey(const Key('heart-rate-facts'))).data,
        'lowest 48 · resting 52');
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => (t.data ?? '').toLowerCase())
        .join(' ');
    for (final w in ['normal', 'high', 'good', 'elevated', 'poor']) {
      expect(texts.contains(w), isFalse, reason: w);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('報告：有曲線 → 卡片出現，More details 不再寫一次心率', (tester) async {
    final r = buildMorningReport(date: '2026-11-13', home: home(curve: curveJson()));
    await pumpReport(tester, r, 'with');
    expect(find.byKey(const Key('heart-rate-card')), findsOneWidget);
    final toggle = find.byKey(const Key('report-details-toggle'));
    if (toggle.evaluate().isNotEmpty) {
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byKey(const Key('report-hr')), findsNothing,
        reason: 'avg_heart_rate 混了清醒時段，不能跟卡上的平均並列');
    expect(find.textContaining('80 bpm'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('報告：沒有曲線 → 沒有卡片，More details 照舊寫心率', (tester) async {
    final r = buildMorningReport(date: '2026-11-13', home: home());
    await pumpReport(tester, r, 'without');
    expect(find.byKey(const Key('heart-rate-card')), findsNothing);
    final toggle = find.byKey(const Key('report-details-toggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('report-hr')), findsOneWidget);
  });
}
