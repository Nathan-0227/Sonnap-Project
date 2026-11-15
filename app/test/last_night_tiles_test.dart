// 早晨報告 Last night 的圖形格子（2026-11-15 使用者定 Q1–Q7）。
// 守：Efficiency 的水面會動、減少動態效果時靜止（使用者：喜歡但有點靜態）；
//     沒按上床時夜空弧不畫上床點也不報錯；填滿的高度照舊＝效率。
import 'package:app/widgets/last_night_art.dart';
import 'package:app/widgets/report_tiles.dart';
import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpFill(WidgetTester tester, {required bool reduce}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 800),
          disableAnimations: reduce,
        ),
        child: Scaffold(
          body: SizedBox(
            width: 180,
            child: ReportFillTile(
              icon: Icons.speed_rounded,
              color: const Color(0xFF7EC8FF),
              title: 'Efficiency',
              value: '88',
              unit: '%',
              fraction: 0.88,
              caption: 'Bed buttons',
            ),
          ),
        ),
      ),
    ),
  );
}

double tOf(WidgetTester tester) =>
    (tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byKey(const Key('report-fill-liquid')),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter
            as LiquidFillPainter)
        .t;

void main() {
  testWidgets('Efficiency：水面會動', (tester) async {
    await pumpFill(tester, reduce: false);
    final seen = <double>{};
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      seen.add(tOf(tester));
    }
    expect(seen.length, greaterThan(5));
  });

  testWidgets('Efficiency：減少動態效果時靜止', (tester) async {
    await pumpFill(tester, reduce: true);
    final seen = <double>{};
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      seen.add(tOf(tester));
    }
    expect(seen, {0.0});
  });

  testWidgets('Efficiency：填滿的高度照舊＝效率（190 高的格子填 88%）', (tester) async {
    await pumpFill(tester, reduce: true);
    expect(tester.getSize(find.byType(ReportFillTile)).height, 190);
    expect(
      tester.getSize(find.byKey(const Key('report-fill'))).height,
      closeTo((190 - 2) * 0.88, 0.5), // 卡片上下各 1 像素邊框,
    );
  });

  test('沒資料、超過 12 小時都不報錯（鐘面最多畫滿一圈）', () {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    BedClockPainter(
      null,
      null,
      null,
      Colors.blue,
    ).paint(canvas, const Size(170, 190));
    BedClockPainter(
      (23, 40),
      (7, 15),
      815,
      Colors.blue,
    ).paint(canvas, const Size(170, 190));
    PhoneDialPainter(
      null,
      400,
      Colors.teal,
    ).paint(canvas, const Size(170, 190));
    AuroraFillPainter(null, Colors.purple).paint(canvas, const Size(170, 190));
    StarRiverPainter(null, Colors.amber).paint(canvas, const Size(170, 190));
    SleepHrWavePainter(
      const [],
      Colors.indigo,
    ).paint(canvas, const Size(170, 190));
    CameraBarsPainter(const []).paint(canvas, const Size(350, 210));
    final t0 = DateTime(2026, 11, 14, 3, 15);
    CameraBarsPainter([
      for (var i = 0; i < 60; i++)
        (t0.add(Duration(minutes: 5 * i)), i % 7 == 0 ? 0.4 : 0.0),
    ]).paint(canvas, const Size(350, 210));
    CameraBarsPainter([
      for (var i = 0; i < 10; i++) (t0.add(Duration(minutes: 5 * i)), 0.0),
    ]).paint(canvas, const Size(350, 210));
    recorder.endRecording();
  });

  test('鐘面角度：12 點在正上方、順時針，下午與上午同一個位置', () {
    expect(bedClockAngle(0, 0), closeTo(-1.5707963, 1e-6));
    expect(bedClockAngle(3, 0), closeTo(0, 1e-9));
    expect(bedClockAngle(15, 0), closeTo(bedClockAngle(3, 0), 1e-9));
    expect(bedClockAngle(23, 30), closeTo(bedClockAngle(11, 30), 1e-9));
  });
}
