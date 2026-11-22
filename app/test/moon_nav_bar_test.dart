// 底部導覽列（2026-11-13 使用者定，照參考圖）：只有圖示、中間一顆月亮＝開始睡覺。
// 守：左右各兩個、月亮在正中間而且凸出導覽列、選中的有小點、分頁沒有文字但朗讀念得出名稱；
// 中間那顆是月亮＋Sleep、快到就寢時呼吸（2026-11-22）。
import 'package:app/widgets/moon_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int tapped;
  late int moon;

  Future<void> pump(
    WidgetTester tester, {
    int index = 0,
    TimeOfDay? bedtime,
    DateTime? now,
    bool reduceMotion = false,
  }) async {
    tapped = -1;
    moon = 0;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: Scaffold(
        bottomNavigationBar: MoonNavBar(
          currentIndex: index,
          onTab: (i) => tapped = i,
          onMoon: () => moon++,
          bedtime: bedtime,
          clock: () => now ?? DateTime(2026, 11, 22, 15),
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
    expect(find.byKey(const Key('start-sleep-moon')), findsOneWidget, reason: '中間畫月亮');
  });

  testWidgets('中間那顆一看就是開始睡覺：月亮＋Sleep，不畫寵物頭（2026-11-22 使用者定）', (tester) async {
    await pump(tester);
    final btn = find.byKey(const Key('start-sleep'));
    expect(find.descendant(of: btn, matching: find.byKey(const Key('start-sleep-moon'))), findsOneWidget);
    expect(find.descendant(of: btn, matching: find.text('Sleep')), findsOneWidget);
    expect(find.descendant(of: btn, matching: find.byType(Image)), findsNothing,
        reason: '寵物頭看不出是開始睡覺');
  });

  test('發亮的時間＝守門那一窗：目標前 30 分 → 目標後 6 小時，跨午夜也對', () {
    const bed = TimeOfDay(hour: 1, minute: 30);
    bool near(int d, int h, int m) => MoonNavBar.bedtimeNear(DateTime(2026, 11, d, h, m), bed);
    expect(near(22, 0, 59), isFalse);
    expect(near(22, 1, 0), isTrue, reason: '前 30 分開始');
    expect(near(22, 7, 29), isTrue);
    expect(near(22, 7, 30), isFalse, reason: '後 6 小時結束');
    expect(near(22, 15, 0), isFalse);
    const late = TimeOfDay(hour: 23, minute: 30);
    expect(MoonNavBar.bedtimeNear(DateTime(2026, 11, 22, 23, 0), late), isTrue);
    expect(MoonNavBar.bedtimeNear(DateTime(2026, 11, 23, 2, 0), late), isTrue, reason: '過午夜還在那一窗');
    expect(MoonNavBar.bedtimeNear(DateTime(2026, 11, 22, 1, 0), null), isFalse, reason: '不知道目標就不提醒');
  });

  testWidgets('快到就寢：光暈在呼吸；平常不動', (tester) async {
    const bed = TimeOfDay(hour: 1, minute: 30);
    await pump(tester, bedtime: bed, now: DateTime(2026, 11, 22, 15));
    expect(find.byKey(const Key('start-sleep-calm')), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse, reason: '平常不動');
    await pump(tester, bedtime: bed, now: DateTime(2026, 11, 22, 1, 10));
    expect(find.byKey(const Key('start-sleep-near')), findsOneWidget);
    expect(tester.hasRunningAnimations, isTrue, reason: '快到就寢要呼吸');
  });

  testWidgets('減少動態效果：快到就寢只變亮、不動', (tester) async {
    await pump(tester,
        bedtime: const TimeOfDay(hour: 1, minute: 30),
        now: DateTime(2026, 11, 22, 1, 10),
        reduceMotion: true);
    expect(find.byKey(const Key('start-sleep-near')), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('沒有文字，但朗讀念得出名稱；選中的那個標成 selected', (tester) async {
    await pump(tester, index: 1);
    expect(find.byType(Text), findsOneWidget, reason: '四個分頁只有圖示，字只在中間那顆');
    expect(find.text('Sleep'), findsOneWidget);
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
