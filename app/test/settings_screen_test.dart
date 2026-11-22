// 設定頁（2026-11-22 grill 定案：A 分組＋B 名片）。
// 守：按了沒反應的東西一個都不留、名片照抄後端（等級、邀請碼）、寵物心情沒有就是 bored、
// 改暱稱走後端、Data 退回打包檔時照實寫 Bundled。
import 'package:app/screens/settings_screen.dart';
import 'package:app/services/game_service.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/pet_choice.dart';
import 'package:app/widgets/settings_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settle(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> pump(WidgetTester tester, SettingsScreen screen) async {
  tester.view.physicalSize = const Size(1080, 3600);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  // 每次一個新的 App：不然上一次留下的提示會排在前面
  await tester.pumpWidget(MaterialApp(key: UniqueKey(), home: Scaffold(body: screen)));
  await settle(tester);
}

String drawnFace(WidgetTester tester) {
  final img = tester.widget<Image>(find.descendant(
    of: find.byKey(const Key('settings-profile')),
    matching: find.byType(Image),
  ).first);
  return (img.image as AssetImage).assetName;
}

void main() {
  tearDown(() => PetChoice.current.value = PetSpecies.dog);

  testWidgets('🔴 不放按了沒反應的東西：Appearance、Log out、email、隊友的名字都不在', (tester) async {
    await pump(tester, SettingsScreen(store: InMemoryKeyValueStore()));
    for (final gone in ['Appearance', 'Log Out', 'Log out', 'jeremy@email.com', 'Golden Retriever', 'Dark Mode']) {
      expect(find.textContaining(gone), findsNothing, reason: gone);
    }
    // 每一列都點一次：不得冒出「以後才有」
    for (final key in ['settings-sleep-schedule', 'settings-language', 'settings-about']) {
      final f = find.byKey(Key(key));
      await tester.ensureVisible(f);
      await tester.tap(f);
      await settle(tester);
      expect(find.textContaining('available later'), findsNothing, reason: key);
      await tester.tapAt(const Offset(5, 5)); // 關掉剛開的面板
      await settle(tester);
    }
  });

  testWidgets('點開的面板有底色，不是透明的（2026-11-22 實機：Language 整片透明）', (tester) async {
    await pump(tester, SettingsScreen(store: InMemoryKeyValueStore(), dataSection: const Text('DATA-BLOCK')));
    for (final (row, sheet) in [('settings-language', 'language-sheet'), ('settings-data', 'data-sheet')]) {
      await tester.ensureVisible(find.byKey(Key(row)));
      await tester.tap(find.byKey(Key(row)));
      await settle(tester);
      final box = tester.widget<Container>(find.byKey(Key(sheet)));
      expect((box.decoration as BoxDecoration).color, kSettingsSheetColor, reason: sheet);
      await tester.tapAt(const Offset(5, 5));
      await settle(tester);
    }
  });

  testWidgets('四組照定案的順序：Sleep → Friends → Data & devices → App', (tester) async {
    await pump(tester, SettingsScreen(store: InMemoryKeyValueStore(), dataSection: const Text('DATA-BLOCK')));
    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(y('SLEEP'), lessThan(y('FRIENDS')));
    expect(y('FRIENDS'), lessThan(y('DATA & DEVICES')));
    expect(y('DATA & DEVICES'), lessThan(y('APP')));
    expect(tester.getTopLeft(find.byKey(const Key('settings-profile'))).dy, lessThan(y('SLEEP')),
        reason: '名片在最上面');
  });

  testWidgets('名片的寵物頭：照首頁的心情；沒有心情是 bored，絕不是 happy', (tester) async {
    await pump(tester, SettingsScreen(store: InMemoryKeyValueStore(), petMood: () async => 'tired'));
    expect(drawnFace(tester), 'assets/moods/dog_tired.png');

    await pump(tester, SettingsScreen(key: UniqueKey(), store: InMemoryKeyValueStore(), petMood: () async => null));
    expect(drawnFace(tester), 'assets/moods/dog_bored.png');

    PetChoice.current.value = PetSpecies.cat;
    await settle(tester);
    expect(drawnFace(tester), 'assets/moods/cat_bored.png', reason: '跟著選的寵物換');
  });

  testWidgets('Lv 與邀請碼照抄後端；沒有後端就不畫', (tester) async {
    await pump(tester, SettingsScreen(store: InMemoryKeyValueStore()));
    expect(find.byKey(const Key('settings-level')), findsNothing);
    expect(find.byKey(const Key('settings-invite')), findsNothing);

    var rewards = 0;
    await pump(
      tester,
      SettingsScreen(
        key: UniqueKey(),
        store: InMemoryKeyValueStore(),
        loadGame: () async => GameState.fromJson({'level': 7}),
        loadInviteCode: () async => 'ME0001',
        onOpenRewards: () => rewards++,
      ),
    );
    expect(find.text('Lv 7'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-level')));
    expect(rewards, 1, reason: '點 Lv 開獎勵頁');

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.tap(find.byKey(const Key('settings-invite')));
    await settle(tester);
    expect(copied, 'ME0001');
    expect(find.text('Invite code copied.'), findsOneWidget);
  });

  testWidgets('Edit name：送出新名字；空白不能存；沒有後端照實說', (tester) async {
    final sent = <String>[];
    await pump(
      tester,
      SettingsScreen(
        username: 'Nathan',
        store: InMemoryKeyValueStore(),
        onRename: (n) async {
          sent.add(n);
          return null;
        },
      ),
    );
    await tester.tap(find.byKey(const Key('settings-edit-name')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('edit-name-field')), '   ');
    await settle(tester, 2);
    expect(tester.widget<TextButton>(find.byKey(const Key('edit-name-save'))).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('edit-name-field')), ' Nate ');
    await settle(tester, 2);
    await tester.tap(find.byKey(const Key('edit-name-save')));
    await settle(tester);
    expect(sent, ['Nate']);
    expect(find.text('Name updated.'), findsOneWidget);

    await pump(tester, SettingsScreen(key: UniqueKey(), store: InMemoryKeyValueStore()));
    await tester.tap(find.byKey(const Key('settings-edit-name')));
    await settle(tester);
    expect(find.byKey(const Key('edit-name-dialog')), findsNothing);
    expect(find.textContaining("needs Sonnap's server"), findsOneWidget);
  });

  testWidgets('Data：退回打包檔時照實寫 Bundled；點開是原本那一整塊', (tester) async {
    await pump(
      tester,
      SettingsScreen(store: InMemoryKeyValueStore(), dataSection: const Text('DATA-BLOCK'), dataLive: () => false),
    );
    expect(find.byKey(const Key('data-badge-bundled')), findsOneWidget);
    expect(find.text('Bundled'), findsOneWidget);
    expect(find.text('DATA-BLOCK'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('settings-data')));
    await tester.tap(find.byKey(const Key('settings-data')));
    await settle(tester);
    expect(find.text('DATA-BLOCK'), findsOneWidget);

    await pump(
      tester,
      SettingsScreen(key: UniqueKey(), store: InMemoryKeyValueStore(), dataSection: const Text('X'), dataLive: () => true),
    );
    expect(find.text('Live'), findsOneWidget);
  });

  testWidgets('Sleep schedule 寫就寢 → 起床', (tester) async {
    await pump(
      tester,
      SettingsScreen(
        store: InMemoryKeyValueStore(),
        initialTargetBedtime: const TimeOfDay(hour: 1, minute: 30),
      ),
    );
    expect(find.text('01:30 → 09:30'), findsOneWidget, reason: '沒存過起床＝就寢＋8 小時');
  });

  testWidgets('返回鈕回首頁；沒給就不畫', (tester) async {
    var back = 0;
    await pump(tester, SettingsScreen(store: InMemoryKeyValueStore(), onBack: () => back++));
    await tester.tap(find.byKey(const Key('settings-back')));
    expect(back, 1);
    await pump(tester, SettingsScreen(key: UniqueKey(), store: InMemoryKeyValueStore()));
    expect(find.byKey(const Key('settings-back')), findsNothing);
  });
}
