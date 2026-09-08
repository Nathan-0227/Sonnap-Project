import 'package:app/services/bed_marks.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/widgets/bed_mark_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 守的是首頁那兩個按鈕。
///
/// ⚠️ 最重要的一條是**「不按也沒關係」那句話要在畫面上**：
/// 少了它，忘記按的人會以為那一晚白過了 —— 而事實上 `lights_out_at`
/// 照樣偵測得到。那句話不是文案裝飾，是這個設計唯一對使用者可見的部分。

Future<void> pump(WidgetTester tester, BedMarkStore store) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: BedMarkButtons(store: store)),
  ));
  // initState 裡有一個 await（讀本機儲存），要多 pump 幾次。
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

void main() {
  late InMemoryKeyValueStore kv;
  late BedMarkStore store;

  setUp(() {
    kv = InMemoryKeyValueStore();
    store = BedMarkStore(kv);
  });

  testWidgets('⚠️ 畫面上一定要寫「不按也沒關係」', (tester) async {
    await pump(tester, store);
    expect(
      find.textContaining('Optional'),
      findsOneWidget,
      reason: '這是加分項不是取代品，使用者必須看得到這件事',
    );
    expect(find.textContaining('detected anyway'), findsOneWidget);
  });

  testWidgets('按了開始睡覺 → 存進本機，而且按鈕換成時刻', (tester) async {
    await pump(tester, store);
    expect(find.text('Start sleep'), findsOneWidget);

    await tester.tap(find.text('Start sleep'));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }

    expect(find.text('Start sleep'), findsNothing);
    expect(find.textContaining('In bed since'), findsOneWidget);
    expect(
      await kv.getString(kBedStartKey),
      isNotNull,
      reason: '只改畫面不存檔的話，關掉 App 就沒了',
    );
  });

  testWidgets('沒按開始之前，「下床」是停用的', (tester) async {
    await pump(tester, store);
    final btn = tester.widget<OutlinedButton>(find.ancestor(
      of: find.text('Out of bed'),
      matching: find.byType(OutlinedButton),
    ));
    expect(btn.onPressed, isNull, reason: '沒有起點的結束算不出任何東西');
  });

  testWidgets('反向對照：按過開始之後「下床」就啟用了', (tester) async {
    // 沒有這一條，把 onPressed 寫死成 null 也會讓上一條通過。
    await store.markStart(DateTime.now());
    await pump(tester, store);
    final btn = tester.widget<OutlinedButton>(find.ancestor(
      of: find.text('Out of bed'),
      matching: find.byType(OutlinedButton),
    ));
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('已經有標記時，一進畫面就顯示時刻（不是等使用者再按一次）',
      (tester) async {
    await store.markStart(DateTime(2026, 9, 6, 23, 5));
    await pump(tester, store);
    expect(find.text('In bed since 23:05'), findsOneWidget);
  });

  testWidgets('過期的標記不顯示 —— 上禮拜按的不算今晚', (tester) async {
    await store.markStart(
        DateTime.now().subtract(kBedMarkMaxAge + const Duration(hours: 1)));
    await pump(tester, store);
    expect(find.text('Start sleep'), findsOneWidget, reason: '過期就當作沒按過');
  });

  testWidgets('⚠️ 按下下床之後，畫面一定要看得出來變了', (tester) async {
    // 第一版沒有這一段：按完 started 仍然是 true，卡片長得**一模一樣**，
    // 使用者按了以為沒反應（2026-09-07 實機回報）。
    // 沒有回饋的按鈕，使用者會一直按或以為壞了。
    await store.markStart(DateTime(2026, 9, 7, 3, 20));
    await pump(tester, store);
    expect(find.textContaining('Saved'), findsNothing, reason: '還沒按下床');

    await tester.tap(find.text('Out of bed'));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }

    expect(find.text('Out of bed'), findsNothing, reason: '按鈕文字要換掉');
    expect(find.textContaining('Up at'), findsOneWidget);
    expect(find.textContaining('Saved'), findsOneWidget,
        reason: '說明文字也要換 —— 那是「有記到」唯一的證據');
  });

  testWidgets('按下下床之後，兩個時刻都在本機', (tester) async {
    await store.markStart(DateTime.now().subtract(const Duration(hours: 8)));
    await pump(tester, store);

    await tester.tap(find.text('Out of bed'));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }

    expect(await kv.getString(kBedStartKey), isNotNull);
    expect(await kv.getString(kBedEndKey), isNotNull);
  });
}
