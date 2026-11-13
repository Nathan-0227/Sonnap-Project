// 底部導覽列（2026-11-13 使用者定，照參考圖）：只有圖示、中間一顆月亮＝開始睡覺。
// 守：左右各兩個、月亮在正中間而且凸出導覽列、選中的有小點、沒有文字但朗讀念得出名稱。
import 'package:app/widgets/moon_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int tapped;
  late int moon;

  Future<void> pump(WidgetTester tester, {int index = 0}) async {
    tapped = -1;
    moon = 0;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: MoonNavBar(
          currentIndex: index,
          onTab: (i) => tapped = i,
          onMoon: () => moon++,
        ),
      ),
    ));
  }

  testWidgets('左右各兩個、月亮在正中間而且凸出導覽列上緣', (tester) async {
    await pump(tester);
    final screenW = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final m = tester.getRect(find.byKey(const Key('start-sleep')));
    expect((m.center.dx - screenW / 2).abs(), lessThan(1));
    final home = tester.getRect(find.byKey(const Key('nav-home')));
    final friends = tester.getRect(find.byKey(const Key('nav-friends')));
    final insights = tester.getRect(find.byKey(const Key('nav-insights')));
    final assistant = tester.getRect(find.byKey(const Key('nav-assistant')));
    expect(friends.right, lessThanOrEqualTo(m.left));
    expect(insights.left, greaterThanOrEqualTo(m.right));
    expect(home.left, lessThan(friends.left));
    expect(assistant.left, greaterThan(insights.left));
    expect(m.top, lessThan(home.top), reason: '月亮凸出導覽列');
  });

  testWidgets('點分頁 → 切分頁；點月亮 → 開始睡覺', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('nav-insights')));
    expect(tapped, 2);
    await tester.tap(find.byKey(const Key('nav-assistant')));
    expect(tapped, 3);
    await tester.tap(find.byKey(const Key('start-sleep')));
    expect(moon, 1);
    expect(find.byKey(const Key('start-sleep-dog')), findsOneWidget, reason: '中間畫狗頭表情');
  });

  testWidgets('沒有文字，但朗讀念得出名稱；選中的那個標成 selected', (tester) async {
    await pump(tester, index: 1);
    expect(find.byType(Text), findsNothing, reason: '參考圖只有圖示');
    final handle = tester.ensureSemantics();
    for (final label in ['Home', 'Friends', 'Insights', 'Assistant', 'Start sleep']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    expect(
      tester.getSemantics(find.byKey(const Key('nav-friends'))),
      isSemantics(label: 'Friends', isButton: true, isSelected: true, hasTapAction: true),
      reason: '朗讀模式下念得出名稱、點得到、知道是目前這頁',
    );
    expect(
      tester.getSemantics(find.byKey(const Key('nav-home'))),
      isSemantics(label: 'Home', isSelected: false),
    );
    handle.dispose();
  });
}
