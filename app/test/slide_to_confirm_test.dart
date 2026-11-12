// Out of bed 用滑的結束（2026-11-12 使用者要求）。
// ⚠️ 守的是「點一下、滑一半都不算」：半夜手機被碰到就記成下床，
//    會寫進一個錯的下床時刻，而那是攝影機驗證的標準答案。
import 'package:app/services/bed_marks.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/screens/sleep_mode_screen.dart';
import 'package:app/widgets/slide_to_confirm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<int Function()> pump(WidgetTester tester) async {
    var hits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: SlideToConfirm(
                label: 'Slide to get up',
                onConfirmed: () => hits++,
              ),
            ),
          ),
        ),
      ),
    );
    return () => hits;
  }

  testWidgets('⚠️ 點一下不算', (tester) async {
    final hits = await pump(tester);
    await tester.tap(find.byKey(const Key('slide-knob')));
    await tester.tap(find.text('Slide to get up'));
    await tester.pumpAndSettle();
    expect(hits(), 0);
  });

  testWidgets('⚠️ 滑一半放手 → 不算，而且彈回去', (tester) async {
    final hits = await pump(tester);
    final start = tester.getTopLeft(find.byKey(const Key('slide-knob')));
    await tester.drag(find.byKey(const Key('slide-knob')), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(hits(), 0);
    expect(tester.getTopLeft(find.byKey(const Key('slide-knob'))), start);
  });

  testWidgets('滑到底 → 算一次', (tester) async {
    final hits = await pump(tester);
    await tester.drag(find.byKey(const Key('slide-knob')), const Offset(1000, 0));
    await tester.pumpAndSettle();
    expect(hits(), 1);
    // 已經算過了，再拖也不會算第二次
    await tester.drag(find.byKey(const Key('slide-knob')), const Offset(1000, 0));
    await tester.pumpAndSettle();
    expect(hits(), 1);
  });

  testWidgets('睡覺畫面：點 Out of bed 那一列不會記下床', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final store = BedMarkStore(InMemoryKeyValueStore());
    final start = DateTime(2026, 11, 11, 23, 40);
    await store.markStart(start);
    await tester.pumpWidget(
      MaterialApp(
        home: SleepModeScreen(
          store: store,
          startAt: start,
          clock: () => DateTime(2026, 11, 12, 7),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('sleep-out-of-bed')));
    // 睡覺畫面的小狗一直在呼吸，pumpAndSettle 等不到停，改成推幾格
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect((await store.read(now: DateTime(2026, 11, 12, 7))).endAt, isNull);
    expect(find.byType(SleepModeScreen), findsOneWidget);
  });
}
