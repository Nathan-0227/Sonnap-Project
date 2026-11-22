// 換分頁左右滑＋視差（widgets/tab_switcher.dart）。
//
// 守的是壞掉時不會報錯的地方：
// - 方向照導覽列順序；舊頁只退 0.3（視差），新頁走滿
// - 換分頁不能讓頁面狀態掉（原本 IndexedStack 保住的）——換順序畫新頁在上面時最容易掉
// - 滑完只剩一頁在畫面上；沒顯示的頁 finder 找不到（同 IndexedStack）
// - 沒打開（測試預設）或減少動態效果：直接換
import 'package:app/widgets/tab_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Counter extends StatefulWidget {
  final String name;
  const _Counter(this.name);

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;

  @override
  Widget build(BuildContext context) => Center(
        child: TextButton(
          key: Key('${widget.name}-button'),
          onPressed: () => setState(() => n++),
          child: Text('${widget.name} $n'),
        ),
      );
}

Widget _app(int index, {bool animate = true, bool reduce = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: const Size(400, 800), disableAnimations: reduce),
        child: Scaffold(
          body: TabSwitcher(
            index: index,
            animate: animate,
            children: const [_Counter('A'), _Counter('B'), _Counter('C')],
          ),
        ),
      ),
    );

/// 測試畫面設成 400 寬（預設是 800），中間＝200。
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  test('【1】往右：新頁從右邊滑進來、舊頁往左只退 0.3；往左相反', () {
    expect(tabSlideOffsets(0, forward: true), (0.0, 1.0));
    final (out, inn) = tabSlideOffsets(1, forward: true);
    expect(out, closeTo(-kTabParallax, 1e-9));
    expect(inn, 0);
    expect(tabSlideOffsets(0, forward: false), (0.0, -1.0));
    expect(tabSlideOffsets(1, forward: false).$1, closeTo(kTabParallax, 1e-9));
  });

  testWidgets('【2】滑的時候兩頁都在、新頁在右邊；滑完只剩新頁', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(0));
    await tester.pumpWidget(_app(2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('A 0'), findsOneWidget);
    expect(find.text('C 0'), findsOneWidget);
    expect(tester.getCenter(find.text('C 0')).dx, greaterThan(200), reason: '往右邊的分頁，新頁從右邊來');
    expect(tester.getCenter(find.text('A 0')).dx, lessThan(200), reason: '舊頁往左退');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('A 0'), findsNothing);
    expect(tester.getCenter(find.text('C 0')).dx, 200);
  });

  testWidgets('【3】往左邊的分頁：新頁從左邊來、畫在最上面', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(2));
    await tester.pumpWidget(_app(0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getCenter(find.text('A 0')).dx, lessThan(200));
    expect(tester.getCenter(find.text('C 0')).dx, greaterThan(200));
    // 新頁在最上面：點兩頁重疊的地方，點到的是新頁
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('A-button')));
    await tester.pump();
    expect(find.text('A 1'), findsOneWidget);
  });

  testWidgets('【4】換來換去狀態不會掉（原本 IndexedStack 保住的）', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(0));
    await tester.tap(find.byKey(const Key('A-button')));
    await tester.tap(find.byKey(const Key('A-button')));
    await tester.pump();
    expect(find.text('A 2'), findsOneWidget);
    // 每一頁都要是自己的狀態：沒有固定的 key 時，換順序會把 A 的「2」換到別頁身上
    for (final (i, shown) in [(2, 'C 0'), (1, 'B 0'), (0, 'A 2')]) {
      await tester.pumpWidget(_app(i));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(shown), findsOneWidget, reason: '換到第 $i 頁：換順序畫新頁在上面時最容易掉狀態');
    }
  });

  testWidgets('【5】滑的時候點不到（不會點到正在離開的那一頁）', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(0));
    await tester.pumpWidget(_app(1));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('A-button')), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(_app(0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('A 0'), findsOneWidget);
  });

  testWidgets('【6】沒打開、或減少動態效果：直接換', (tester) async {
    _phone(tester);
    for (final (animate, reduce) in [(false, false), (true, true)]) {
      await tester.pumpWidget(_app(0, animate: animate, reduce: reduce));
      await tester.pumpWidget(_app(2, animate: animate, reduce: reduce));
      await tester.pump();
      expect(find.text('A 0'), findsNothing, reason: 'animate=$animate reduce=$reduce');
      expect(tester.getCenter(find.text('C 0')).dx, 200);
    }
  });
}
