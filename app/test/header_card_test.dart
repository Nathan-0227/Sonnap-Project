import 'package:app/widgets/header_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 守的是 HeaderCard 裡兩段**只在某些機器、某些時刻**才壞的版面。
///
/// ⚠️ 這種 bug 在測試裡不會自己出現：預設的測試畫布是 800×600（比手機寬），
///    字級縮放是 1.0（比很多人的手機小）。用預設值跑，壞掉的版面照樣全綠。
///    所以每一條都必須**明確指定寬度與字級縮放**。
///
/// ⚠️ 大時鐘是 `DateFormat('HH:mm')`，內容隨執行時刻改變，不能用 find.text()
///    去抓。改用字級 52 這個特徵——同一張卡片裡沒有第二個 52。

/// 在指定寬度與字級縮放下渲染一張 HeaderCard。
Future<void> pumpAt(
  WidgetTester tester, {
  required double width,
  required double textScale,
}) async {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: const Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: HeaderCard(
              username: 'Nathan',
              message: 'You slept 6h 20m last night.',
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// 這段文字實際被排成幾行。
///
/// 這個 Flutter 版本的 `RenderParagraph` 沒有 `computeLineMetrics()`，
/// 改成量每個字元的方塊有幾種不同的 top —— 同一行的 top 相同。
int lineCount(WidgetTester tester, Finder f) {
  final p = tester.renderObject<RenderParagraph>(f);
  final boxes = p.getBoxesForSelection(TextSelection(
    baseOffset: 0,
    extentOffset: p.text.toPlainText().length,
  ));
  return boxes.map((b) => b.top.round()).toSet().length;
}

final clock = find.byWidgetPredicate(
  (w) => w is Text && w.style?.fontSize == 52,
  description: '大時鐘（字級 52）',
);

void main() {
  testWidgets('大時鐘在 360dp 的手機上只有一行', (tester) async {
    await pumpAt(tester, width: 360, textScale: 1.0);
    expect(lineCount(tester, clock), 1);
  });

  testWidgets('⚠️ 使用者把系統字級調大時，大時鐘仍然只有一行', (tester) async {
    // 這是實機看到「02:18」折成兩行的那個情境。
    await pumpAt(tester, width: 360, textScale: 1.3);
    expect(lineCount(tester, clock), 1,
        reason: '折行會把 52px 的字疊成兩層，整張卡片被撐高、時間讀不出來');
  });

  testWidgets('很窄的機器（320dp）也不折', (tester) async {
    await pumpAt(tester, width: 320, textScale: 1.3);
    expect(lineCount(tester, clock), 1);
  });

  testWidgets('反向對照：正常寬度下時鐘沒有被縮到看不見', (tester) async {
    // 沒有這一條，把字級改成 1 也會讓上面三條通過。
    await pumpAt(tester, width: 411, textScale: 1.0);
    expect(tester.getSize(clock).height, greaterThan(40),
        reason: '它是這張卡片的主角，不能為了不折行就縮成小字');
  });

  testWidgets('「Target bedtime」那一行也不折', (tester) async {
    await pumpAt(tester, width: 360, textScale: 1.3);
    expect(lineCount(tester, find.textContaining('Target bedtime')), 1);
  });

  testWidgets('沒有版面溢位（黃黑斜線）', (tester) async {
    await pumpAt(tester, width: 320, textScale: 1.3);
    expect(tester.takeException(), isNull);
  });
}
