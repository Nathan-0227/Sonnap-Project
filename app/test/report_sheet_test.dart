// 報告的詳細頁（2026-11-15 使用者實機發現）：內容一長就撐滿整個螢幕、標題頂到狀態列，
// 而且頁裡的捲動吃掉往下拉的手勢、關不掉。守：上面永遠留一截；捲到頂再往下拉會關。
import 'package:app/models/yesterday_activity.dart';
import 'package:app/widgets/report_sheet.dart';
import 'package:app/widgets/steps_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

YesterdayActivity tall() => YesterdayActivity(
  date: '2026-11-13',
  steps: 5347,
  stepGoal: 9540,
  distanceM: 3668,
  activeKcal: 223,
  floorsUp: 10,
  stepsHourly: [for (var h = 0; h < 24; h++) h * 40],
  history: [
    for (var i = 0; i < 14; i++)
      ActivityHistoryDay(
        date: '2026-11-${(i + 1).toString().padLeft(2, '0')}',
        steps: 4000 + i,
        stepGoal: 9000,
      ),
  ],
);

Future<void> openSteps(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 700 * 3); // 矮螢幕：內容一定比螢幕高
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 24 * 3);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () =>
                  showStepsSheet(context, day: tall(), color: Colors.orange),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('內容比螢幕高：頁面最高 88%，上面留一截、不頂到狀態列；有拉桿', (tester) async {
    await openSteps(tester);
    final sheet = tester.getRect(find.byKey(const Key('steps-sheet')));
    expect(sheet.bottom, closeTo(700, 1));
    expect(sheet.height, lessThanOrEqualTo(700 * kReportSheetMaxHeight + 0.5));
    expect(sheet.top, greaterThan(24 + 40), reason: '狀態列下面還看得到一截報告');
    expect(find.byKey(const Key('report-sheet-handle')), findsOneWidget);
  });

  testWidgets('⚠️ 捲到最上面再往下拉 → 關掉（原本被頁裡的捲動吃掉、關不掉）', (tester) async {
    await openSteps(tester);
    final sheet = tester.getRect(find.byKey(const Key('steps-sheet')));
    // 從頁面中間往下拉（不是拉桿那一截）
    await tester.dragFrom(
      Offset(sheet.center.dx, sheet.top + 200),
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('steps-sheet')), findsNothing);
  });

  testWidgets('往上捲照常捲、不會關；捲下去再往下拉只是捲回來', (tester) async {
    await openSteps(tester);
    final sheet = tester.getRect(find.byKey(const Key('steps-sheet')));
    final from = Offset(sheet.center.dx, sheet.top + 300);
    await tester.dragFrom(from, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('steps-sheet')), findsOneWidget);
    await tester.dragFrom(from, const Offset(0, 120)); // 捲回去一部分，還沒到頂
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('steps-sheet')), findsOneWidget);
  });
}
