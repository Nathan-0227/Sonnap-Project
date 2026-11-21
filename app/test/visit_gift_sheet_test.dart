// 送禮頁（2026-11-22，照 Finch；共識摘要 Q1–Q15）。守的事：
// 【1】3×3：9 種排成 3 列、每列 3 個，順序照後端
// 【2】泡泡那句照抄後端、只把 {friend} 換成名字；換一格就換一句；舊版後端沒給退回中性的一句
// 【3】預設選哪一格只看手機時間：晚上 good_night、早上 good_morning、其他第一格；後端沒有那一種退回第一格
// 【4】圖示讀不到 → 退回按鈕字裡的 emoji（不會空一格）
// 【5】送出去：寵物跳、圖示飛過去；減少動態效果時都不動、只換字
// 【6】按鈕上的字拆成 emoji＋名字；沒有 emoji 的整串照寫
// 【7】兩隻寵物穿各自的衣服（朋友的要他有分享，後端判斷；App 照畫）
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/friends_service.dart';
import 'package:app/widgets/home_pet.dart';
import 'package:app/widgets/visit_gift_sheet.dart';

const nine = [
  ('pet', 'Pet 🐾'),
  ('good_night', 'Good night 🌙'),
  ('sleep_well', 'Sleep well 💤'),
  ('proud', 'Proud of you ⭐'),
  ('good_morning', 'Good morning ☀️'),
  ('hugs', 'Hugs 🤗'),
  ('you_got_this', 'You got this 💪'),
  ('thanks', 'Thanks 💛'),
  ('outfit', 'Nice outfit 👕'),
];

const invites = {
  'pet': 'PAT {friend}!',
  'good_night': 'NIGHT {friend}!',
  'hugs': 'HUG {friend}!',
};

Future<List<String>> pumpSheet(
  WidgetTester tester, {
  DateTime? now,
  bool reduceMotion = false,
  List<(String, String)> kinds = nine,
}) async {
  tester.view.physicalSize = const Size(411, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final calls = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: const Size(411, 900), disableAnimations: reduceMotion),
        child: Scaffold(
          body: VisitGiftSheet(
            friend: const TownPerson(handle: 'MIA111', displayName: 'Mia (demo)', petSpecies: 'cat', equippedItemId: 'crown'),
            me: const TownPerson(handle: 'ME0001', displayName: 'Me', mine: true, petMood: 'happy', equippedItemId: 'top_hat'),
            kinds: kinds,
            invites: invites,
            clock: () => now ?? DateTime(2026, 11, 22, 14),
            onSend: (k) async {
              calls.add(k);
              return null;
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  return calls;
}

void main() {
  testWidgets('【1】9 種排成 3×3，順序照後端', (tester) async {
    await pumpSheet(tester);
    final rows = <double, List<String>>{};
    for (final (k, _) in nine) {
      final at = tester.getCenter(find.byKey(Key('visit-kind-$k')));
      rows.putIfAbsent(at.dy.roundToDouble(), () => []).add(k);
    }
    expect(rows.values.toList(), [
      ['pet', 'good_night', 'sleep_well'],
      ['proud', 'good_morning', 'hugs'],
      ['you_got_this', 'thanks', 'outfit'],
    ]);
  });

  testWidgets('【2】泡泡照抄後端、{friend} 換成名字（不寫 (demo)）；換一格就換一句', (tester) async {
    await pumpSheet(tester); // 14:00 → 第一格 pet
    expect(find.text('PAT Mia!'), findsOneWidget);
    await tester.tap(find.byKey(const Key('visit-kind-hugs')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('HUG Mia!'), findsOneWidget);
    expect(find.text('Send Hugs'), findsOneWidget);
    // 後端沒給那一種的句子 → 中性的一句，不自己編那一種的話
    await tester.tap(find.byKey(const Key('visit-kind-thanks')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("Let's send Mia something nice!"), findsOneWidget);
  });

  test('【3】預設那一格只看手機時間', () {
    final keys = [for (final (k, _) in nine) k];
    expect(defaultVisitKind(DateTime(2026, 11, 22, 21), keys), 'good_night');
    expect(defaultVisitKind(DateTime(2026, 11, 22, 2), keys), 'good_night');
    expect(defaultVisitKind(DateTime(2026, 11, 22, 8), keys), 'good_morning');
    expect(defaultVisitKind(DateTime(2026, 11, 22, 14), keys), 'pet');
    // 舊版後端只有 4 種（沒有 good_morning）→ 第一格
    expect(defaultVisitKind(DateTime(2026, 11, 22, 8), ['pet', 'good_night']), 'pet');
    expect(defaultVisitKind(DateTime(2026, 11, 22, 8), []), isNull);
  });

  testWidgets('【3】晚上打開，預設選中 Good night', (tester) async {
    await pumpSheet(tester, now: DateTime(2026, 11, 22, 22, 30));
    expect(find.text('NIGHT Mia!'), findsOneWidget);
    expect(find.text('Send Good night'), findsOneWidget);
  });

  testWidgets('【4】讀不到圖示 → 退回 emoji', (tester) async {
    await pumpSheet(tester, kinds: const [('zz_no_icon', 'Mystery 🦄')]);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('visit-emoji-zz_no_icon')), findsOneWidget);
    expect(find.text('🦄'), findsOneWidget);
  });

  testWidgets('【5】送出去：圖示飛過去、寵物跳一下', (tester) async {
    final calls = await pumpSheet(tester);
    await tester.tap(find.byKey(const Key('visit-gift-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, ['pet']);
    expect(find.byKey(const Key('visit-gift-flying')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600)); // 飛完，開始跳
    await tester.pump(const Duration(milliseconds: 200));
    final pet = find.byKey(const Key('visit-gift-friend-pet'));
    final y = tester.getTopLeft(pet).dy;
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getTopLeft(pet).dy, greaterThan(y), reason: '跳的時候比落地高');
    expect(find.text('Sent! Mia will see it next time they open Sonnap.'), findsOneWidget);
  });

  testWidgets('【5】減少動態效果：不飛、不跳，只換字', (tester) async {
    await pumpSheet(tester, reduceMotion: true);
    final pet = find.byKey(const Key('visit-gift-friend-pet'));
    final y = tester.getTopLeft(pet).dy;
    await tester.tap(find.byKey(const Key('visit-gift-send')));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('visit-gift-flying')), findsNothing);
      expect(tester.getTopLeft(pet).dy, y);
    }
    expect(find.text('Sent! Mia will see it next time they open Sonnap.'), findsOneWidget);
  });

  test('【6】按鈕上的字拆成 emoji＋名字', () {
    expect(splitVisitLabel('Good night 🌙'), ('🌙', 'Good night'));
    expect(splitVisitLabel('Good morning ☀️'), ('☀️', 'Good morning'));
    expect(splitVisitLabel('PROUD-FROM-BACKEND'), ('P', 'PROUD-FROM-BACKEND'));
    expect(visitInvite('Hi {friend}!', 'Mia'), 'Hi Mia!');
  });

  testWidgets('【7】兩隻寵物穿各自的衣服', (tester) async {
    await pumpSheet(tester);
    final friend = tester.widget<HomePet>(find.byKey(const Key('visit-gift-friend-pet')));
    expect(friend.equippedItemId, 'crown');
    final mine = tester.widget<HomePet>(
      find.descendant(of: find.byKey(const Key('visit-gift-my-pet')), matching: find.byType(HomePet)),
    );
    expect(mine.equippedItemId, 'top_hat');
  });
}
