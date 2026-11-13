// Sleep Stages 卡的疊線（2026-11-13 使用者定，照 Garmin Connect）：
// 點 Heart rate／Movement 才疊線，再點一次回到只有階梯，一次只能選一個。
// 守：照抄後端、不寫 Normal／High、曲線不衝出實際範圍、時間照牆鐘、
//     那一條沒有就不給那顆、有心率曲線時 More details 不再寫一次心率。
import 'package:app/models/night_curve.dart';
import 'package:app/models/sleep_stages.dart';
import 'package:app/screens/morning_report_screen.dart';
import 'package:app/services/morning_report.dart';
import 'package:app/widgets/curve_path.dart';
import 'package:app/widgets/sleep_stages_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> stagesJson() => {
      'segments': [
        {
          'stage': 'light',
          'start': '2026-11-08T02:48:00+08:00',
          'end': '2026-11-08T04:00:00+08:00',
        },
        {
          'stage': 'deep',
          'start': '2026-11-08T04:00:00+08:00',
          'end': '2026-11-08T04:40:00+08:00',
        },
        {
          'stage': 'light',
          'start': '2026-11-08T04:40:00+08:00',
          'end': '2026-11-08T06:40:00+08:00',
        },
      ],
      'minutes': {'awake': 0, 'rem': 67, 'light': 138, 'deep': 30},
      'rem_measured': true,
    };

Map<String, dynamic> curveJson({required bool hr}) => {
      'points': [
        for (var i = 0; i < 46; i++)
          {
            't': '${DateTime(2026, 11, 8, 2, 50).add(Duration(minutes: 5 * i)).toIso8601String().replaceFirst('.000', '')}+08:00',
            'value': hr
                ? [60, 52, 48, 70, 50, 49, 66, 54][i % 8]
                : [0.0, 0.4, 3.9, 1.2][i % 4],
          }
      ],
      'avg': hr ? 53 : 1.1,
      'min': hr ? 47 : 0.0,
      'max': hr ? 74 : 3.9,
      'bucket_minutes': 5,
    };

Future<void> pumpCard(WidgetTester tester,
    {bool hr = true, bool move = true, bool camera = false, double? resting = 53}) async {
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
          heartRate: hr ? NightCurve.fromJsonOrNull(curveJson(hr: true)) : null,
          movement: move ? NightCurve.fromJsonOrNull(curveJson(hr: false)) : null,
          camera: camera ? NightCurve.fromJsonOrNull(curveJson(hr: false)) : null,
          restingHeartRate: resting,
        ),
      ),
    ),
  ));
}

String? textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data;

void main() {
  test('解析：點的值叫 value；時間照字串的牆鐘，不換成 UTC', () {
    final c = NightCurve.fromJsonOrNull(curveJson(hr: true))!;
    expect((c.avg, c.min, c.max), (53.0, 47.0, 74.0));
    expect(c.points.first.time.hour, 2, reason: '+08:00 的 02:50 不能變成 18:50');
    expect(NightCurve.fromJsonOrNull(null), isNull);
    expect(
        NightCurve.fromJsonOrNull({'points': [], 'avg': 1, 'min': 1, 'max': 1}),
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

  testWidgets('預設只有階梯；兩顆都在', (tester) async {
    await pumpCard(tester);
    expect(find.byKey(const Key('stages-chip-hr')), findsOneWidget);
    expect(find.byKey(const Key('stages-chip-move')), findsOneWidget);
    expect(find.byKey(const Key('stages-overlay-heartRate')), findsNothing);
    expect(find.byKey(const Key('stages-overlay-info')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('點 Heart rate → 疊心率線；下面照抄平均、最低、靜止；右邊寫 bpm', (tester) async {
    await pumpCard(tester);
    await tester.tap(find.byKey(const Key('stages-chip-hr')));
    await tester.pump();
    expect(find.byKey(const Key('stages-overlay-heartRate')), findsOneWidget);
    expect(textOf(tester, 'stages-overlay-info'),
        '53 bpm avg while asleep · lowest 47 · resting 53');
    final axis = find.descendant(
        of: find.byKey(const Key('stages-overlay-axis')),
        matching: find.byType(Text));
    expect(tester.widgetList<Text>(axis).map((t) => t.data), ['80', '40']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('再點一次 → 回到只有階梯', (tester) async {
    await pumpCard(tester);
    await tester.tap(find.byKey(const Key('stages-chip-hr')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('stages-chip-hr')));
    await tester.pump();
    expect(find.byKey(const Key('stages-overlay-heartRate')), findsNothing);
    expect(find.byKey(const Key('stages-overlay-info')), findsNothing);
  });

  testWidgets('一次只能選一個；Movement 是手錶的、軸只寫 More／Less', (tester) async {
    await pumpCard(tester);
    await tester.tap(find.byKey(const Key('stages-chip-hr')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('stages-chip-move')));
    await tester.pump();
    expect(find.byKey(const Key('stages-overlay-heartRate')), findsNothing);
    expect(find.byKey(const Key('stages-overlay-movement')), findsOneWidget);
    expect(textOf(tester, 'stages-overlay-info'), 'Movement from your watch');
    final axis = find.descendant(
        of: find.byKey(const Key('stages-overlay-axis')),
        matching: find.byType(Text));
    expect(tester.widgetList<Text>(axis).map((t) => t.data), ['More', 'Less']);
  });

  testWidgets('Camera：攝影機的動作，跟手錶的 Movement 分開；軸 More／Less', (tester) async {
    await pumpCard(tester, camera: true);
    expect(find.byKey(const Key('stages-chip-camera')), findsOneWidget);
    expect(find.byKey(const Key('stages-chip-move')), findsOneWidget,
        reason: '兩個是不同的量，各一顆');
    await tester.tap(find.byKey(const Key('stages-chip-camera')));
    await tester.pump();
    expect(find.byKey(const Key('stages-overlay-camera')), findsOneWidget);
    expect(textOf(tester, 'stages-overlay-info'), 'Movement seen by the camera');
    final axis = find.descendant(
        of: find.byKey(const Key('stages-overlay-axis')),
        matching: find.byType(Text));
    expect(tester.widgetList<Text>(axis).map((t) => t.data), ['More', 'Less']);
    // 一次只選一個：換到心率，攝影機那條收掉
    await tester.tap(find.byKey(const Key('stages-chip-hr')));
    await tester.pump();
    expect(find.byKey(const Key('stages-overlay-camera')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('沒有錄影的晚上 → 沒有 Camera 那顆', (tester) async {
    await pumpCard(tester);
    expect(find.byKey(const Key('stages-chip-camera')), findsNothing);
  });

  testWidgets('⚠️ 不寫 Normal／High 之類的判斷', (tester) async {
    await pumpCard(tester, camera: true);
    for (final chip in ['stages-chip-hr', 'stages-chip-move', 'stages-chip-camera']) {
      await tester.tap(find.byKey(Key(chip)));
      await tester.pump();
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => (t.data ?? '').toLowerCase())
          .join(' | ');
      for (final w in ['normal', 'high', 'good', 'elevated', 'poor']) {
        expect(texts.contains(w), isFalse, reason: '$chip: $w');
      }
    }
  });

  testWidgets('那一條沒有 → 那顆不出現；兩條都沒有 → 原本的卡', (tester) async {
    await pumpCard(tester, move: false);
    expect(find.byKey(const Key('stages-chip-hr')), findsOneWidget);
    expect(find.byKey(const Key('stages-chip-move')), findsNothing);
    await pumpCard(tester, hr: false, move: false);
    expect(find.byKey(const Key('stages-chip-hr')), findsNothing);
    expect(find.byKey(const Key('stages-chip-move')), findsNothing);
  });

  Map<String, dynamic> home({bool curves = true}) => {
        'date': '2026-11-08',
        'behavior': null,
        'metrics': {
          'sleep_duration_minutes': 235,
          'avg_heart_rate': 80,
          'waso_minutes': 12,
          'resting_heart_rate': 53,
          'sleep_stages': stagesJson(),
          'heart_rate_curve': curves ? curveJson(hr: true) : null,
          'movement_curve': curves ? curveJson(hr: false) : null,
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

  // 報告是可捲動的清單，畫面外的還沒建出來：先捲到 More details 再點開
  Future<void> openDetails(WidgetTester tester) async {
    final toggle = find.byKey(const Key('report-details-toggle'));
    await tester.scrollUntilVisible(toggle, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(toggle);
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('報告：Sleep Stages 卡有兩顆；More details 不再寫一次心率', (tester) async {
    final r = buildMorningReport(date: '2026-11-08', home: home());
    await pumpReport(tester, r, 'with');
    expect(find.byKey(const Key('stages-chip-hr')), findsOneWidget);
    expect(find.byKey(const Key('stages-chip-move')), findsOneWidget);
    await openDetails(tester);
    expect(find.byKey(const Key('report-hr')), findsNothing,
        reason: 'avg_heart_rate 混了清醒時段，不能跟睡著期間的平均並列');
    expect(tester.takeException(), isNull);
  });

  testWidgets('報告：沒有曲線 → 沒有那兩顆，More details 照舊寫心率', (tester) async {
    final r = buildMorningReport(date: '2026-11-08', home: home(curves: false));
    await pumpReport(tester, r, 'without');
    expect(find.byKey(const Key('stages-chip-hr')), findsNothing);
    await openDetails(tester);
    expect(find.byKey(const Key('report-hr')), findsOneWidget);
  });
}
