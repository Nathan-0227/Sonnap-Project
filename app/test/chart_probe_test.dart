// 點圖上的線看那一刻（2026-11-13 使用者定，照參考圖：白點＋小泡泡）。
// 守：吸到最近的真實讀數（不內插）、附近沒讀數寫 no reading（不寫 0、不吸到遠處）、
//     手錶動作只寫 Moving／Still、攝影機寫那 5 分鐘幾成在動、不寫 Normal／High、
//     點圖外面收起來、Sleep Stages 卡與整天心率圖都有。
import 'package:app/models/night_curve.dart';
import 'package:app/models/sleep_stages.dart';
import 'package:app/widgets/chart_probe.dart';
import 'package:app/widgets/day_heart_rate_chart.dart';
import 'package:app/widgets/sleep_stages_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sleep_stages_overlay_test.dart' show curveJson, stagesJson;

String ts(int h, int m) =>
    '2026-11-08T${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:00+08:00';

NightCurve gappyHr() => NightCurve.fromJsonOrNull({
      'points': [
        {'t': ts(2, 50), 'value': 60},
        {'t': ts(2, 55), 'value': 58},
        {'t': ts(6, 0), 'value': 55},
        {'t': ts(6, 5), 'value': 54},
      ],
      'avg': 57, 'min': 54, 'max': 60,
    })!;

Future<void> pumpCard(WidgetTester tester, {NightCurve? hr}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SleepStagesCard(
          stages: SleepStages.fromJsonOrNull(stagesJson())!,
          totalSleepMinutes: 235,
          heartRate: hr ?? NightCurve.fromJsonOrNull(curveJson(hr: true)),
          movement: NightCurve.fromJsonOrNull(curveJson(hr: false)),
        ),
      ),
    ),
  ));
}

/// 點 Sleep Stages 圖上的某個牆鐘時刻（階段 02:48 → 06:40，共 232 分鐘）
Future<void> tapAtTime(WidgetTester tester, int h, int m) async {
  final r = tester.getRect(find.byKey(const Key('stages-chart')));
  final minutes = (h * 60 + m) - (2 * 60 + 48);
  await tester.tapAt(Offset(r.left + r.width * minutes / 232, r.center.dy));
  await tester.pump();
}

String probe(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('chart-probe-text'))).data!;

void main() {
  group('文字', () {
    final p = NightCurvePoint(DateTime.utc(2026, 11, 8, 2, 41), 58.4);
    test('心率：時間 · bpm · 階段', () {
      expect(
          probeText(time: p.time, kind: ProbeKind.heartRate, point: p, stage: 'deep'),
          '02:41 · 58 bpm · Deep');
    });
    test('沒選線：時間 · 階段', () {
      expect(probeText(time: p.time, stage: 'rem'), '02:41 · REM');
    });
    test('手錶動作沒有單位：只寫 Moving／Still（0 是真的沒動）', () {
      expect(probeValue(ProbeKind.watchMovement, NightCurvePoint(p.time, 0)), 'Still');
      expect(probeValue(ProbeKind.watchMovement, NightCurvePoint(p.time, 0.4)), 'Moving');
    });
    test('攝影機：那 5 分鐘幾成時間在動', () {
      expect(probeValue(ProbeKind.camera, NightCurvePoint(p.time, 0.4)),
          'moving 40% of 5 min');
    });
    test('沒有讀數 → no reading，不寫 0', () {
      for (final k in ProbeKind.values) {
        expect(probeValue(k, null), 'no reading');
      }
    });
    test('吸到最近的真實讀數；最近的也超過取樣間隔 → 沒有', () {
      final pts = [
        NightCurvePoint(DateTime.utc(2026, 1, 1, 2, 50), 1),
        NightCurvePoint(DateTime.utc(2026, 1, 1, 2, 55), 2),
      ];
      expect(nearestPoint(pts, DateTime.utc(2026, 1, 1, 2, 53))!.value, 2);
      expect(nearestPoint(pts, DateTime.utc(2026, 1, 1, 3, 10)), isNull);
      expect(nearestPoint(pts, DateTime.utc(2026, 1, 1, 3, 20),
              maxGap: const Duration(minutes: 30))!.value, 2);
    });
  });

  group('Sleep Stages 卡', () {
    testWidgets('沒選線：點一下 → 那一刻的階段；點圖外面 → 收起來', (tester) async {
      await pumpCard(tester);
      expect(find.byKey(const Key('chart-probe')), findsNothing);
      await tapAtTime(tester, 4, 20);
      expect(probe(tester), allOf(startsWith('04:'), endsWith(' · Deep')));
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      expect(find.byKey(const Key('chart-probe')), findsNothing);
    });

    testWidgets('選心率：吸到最近的讀數（04:20 那一點 48），加上階段', (tester) async {
      await pumpCard(tester);
      await tester.tap(find.byKey(const Key('stages-chip-hr')));
      await tester.pump();
      await tapAtTime(tester, 4, 20);
      expect(probe(tester), '04:20 · 48 bpm · Deep');
      final all = probe(tester).toLowerCase();
      for (final w in ['normal', 'high', 'low ']) {
        expect(all.contains(w), isFalse, reason: w);
      }
    });

    testWidgets('泡泡留著時切換疊線，字跟著換；按住滑，泡泡跟著走', (tester) async {
      await pumpCard(tester);
      await tapAtTime(tester, 4, 20);
      await tester.tap(find.byKey(const Key('stages-chip-move')));
      await tester.pump();
      expect(probe(tester), '04:20 · Moving · Deep', reason: '04:20 那點是 3.9');

      final r = tester.getRect(find.byKey(const Key('stages-chart')));
      final g = await tester.startGesture(Offset(r.left + r.width * 82 / 232, r.center.dy));
      await g.moveBy(const Offset(-20, 0));
      await g.moveTo(Offset(r.left + r.width * 82 / 232, r.center.dy)); // 04:10
      await tester.pump();
      expect(probe(tester), '04:10 · Still · Deep', reason: '04:10 那點是 0');
      await g.up();
      await tester.pump();
      expect(find.byKey(const Key('chart-probe')), findsOneWidget, reason: '放開後留著');
    });

    testWidgets('⚠️ 那一刻附近沒有讀數 → no reading（不吸到幾個小時外的點）', (tester) async {
      await pumpCard(tester, hr: gappyHr());
      await tester.tap(find.byKey(const Key('stages-chip-hr')));
      await tester.pump();
      await tapAtTime(tester, 4, 20);
      expect(probe(tester), allOf(contains('no reading'), endsWith(' · Deep')));
    });
  });

  testWidgets('整天心率圖：點一下 → 時間 · bpm', (tester) async {
    final c = NightCurve.fromJsonOrNull({
      'points': [
        for (var i = 0; i < 144; i++)
          {
            't': '${DateTime(2026, 11, 12).add(Duration(minutes: 10 * i)).toIso8601String().replaceFirst('.000', '')}+08:00',
            'value': 60 + (i % 6) * 5,
          }
      ],
      'avg': 70, 'min': 60, 'max': 85,
    })!;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 330, height: 160, child: DayHeartRateChart(c)),
        ),
      ),
    ));
    final r = tester.getRect(find.byKey(const Key('day-hr-chart')));
    // 寬 330，右邊 30 是刻度 → 畫線的寬 300；正中間 = 12:00
    await tester.tapAt(Offset(r.left + 150, r.center.dy));
    await tester.pump();
    // 12:00 是第 72 點：60 + (72 % 6) * 5 = 60
    expect(probe(tester), '12:00 · 60 bpm');
  });
}
