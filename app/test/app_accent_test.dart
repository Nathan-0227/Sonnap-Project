// 主題色＋App 內的減少動態效果（2026-11-22 grill Q5：A＋C）。
// 守：存在手機上、不認得的值當紫色、換了導覽列跟著換、App 內開關疊在系統設定上、
// 圖表裡有意思的顏色（睡著的淡紫）不跟著換。
import 'package:app/screens/settings_screen.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/theme/app_accent.dart';
import 'package:app/widgets/moon_nav_bar.dart';
import 'package:app/widgets/night_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settle(WidgetTester tester, [int n = 5]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  tearDown(() {
    AppLook.accent.value = AccentTheme.purple;
    AppLook.reduceMotion.value = false;
  });

  test('讀回上次的選擇；沒存過是紫色、跟著系統；不認得的值當紫色', () async {
    final store = InMemoryKeyValueStore();
    await AppLook.load(store);
    expect(AppLook.accent.value, AccentTheme.purple);
    expect(AppLook.reduceMotion.value, isFalse);

    await AppLook.chooseAccent(store, AccentTheme.green);
    await AppLook.setReduceMotion(store, true);
    AppLook.accent.value = AccentTheme.purple;
    AppLook.reduceMotion.value = false;
    await AppLook.load(store);
    expect(AppLook.accent.value, AccentTheme.green);
    expect(AppLook.reduceMotion.value, isTrue);

    await store.setString(AppLook.accentKey, 'neon');
    await AppLook.load(store);
    expect(AppLook.accent.value, AccentTheme.purple);
  });

  test('四種主題色各不相同；Theme 的主色就是它', () {
    final accents = kAccentPalettes.values.map((p) => p.accent).toSet();
    expect(accents.length, 4);
    for (final t in AccentTheme.values) {
      expect(sonnapTheme(t).colorScheme.primary, kAccentPalettes[t]!.accent, reason: t.name);
    }
  });

  testWidgets('設定頁點藍色 → 換成藍色並存進手機；Reduce motion 開關也存', (tester) async {
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final store = InMemoryKeyValueStore();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SettingsScreen(store: store))));
    await settle(tester);

    await tester.ensureVisible(find.byKey(const Key('settings-accent-blue')));
    await tester.tap(find.byKey(const Key('settings-accent-blue')));
    await settle(tester);
    expect(AppLook.accent.value, AccentTheme.blue);
    expect(await store.getString(AppLook.accentKey), 'blue');

    await tester.ensureVisible(find.byKey(const Key('settings-reduce-motion-switch')));
    await tester.tap(find.byKey(const Key('settings-reduce-motion-switch')));
    await settle(tester);
    expect(AppLook.reduceMotion.value, isTrue);
    expect(await store.getString(AppLook.reduceMotionKey), '1');
  });

  testWidgets('App 內的減少動態效果：開了就算系統沒開也靜止；關了跟著系統', (tester) async {
    late bool seen;
    Widget app() => MaterialApp(
          builder: applyReduceMotion,
          home: Builder(builder: (context) {
            seen = MediaQuery.of(context).disableAnimations;
            return const SizedBox();
          }),
        );
    await tester.pumpWidget(app());
    expect(seen, isFalse);
    AppLook.reduceMotion.value = true;
    await tester.pump();
    expect(seen, isTrue, reason: '整個 App 的動畫都看 MediaQuery.disableAnimations');
  });

  testWidgets('導覽列中間那顆跟著主題色換', (tester) async {
    Color centerColor() {
      final box = tester.widget<Container>(find.byKey(const Key('start-sleep-calm')));
      final g = (box.decoration as BoxDecoration).gradient as LinearGradient;
      return g.colors.last;
    }

    Widget bar(AccentTheme t) => MaterialApp(
          theme: sonnapTheme(t),
          home: Scaffold(bottomNavigationBar: MoonNavBar(currentIndex: 0, onTab: (_) {}, onMoon: () {})),
        );
    await tester.pumpWidget(bar(AccentTheme.purple));
    expect(centerColor(), kAccentPalettes[AccentTheme.purple]!.accent);
    await tester.pumpWidget(bar(AccentTheme.green));
    await tester.pump(const Duration(milliseconds: 400)); // MaterialApp 換主題會淡入約 200 毫秒
    expect(centerColor(), kAccentPalettes[AccentTheme.green]!.accent);
  });

  test('⚠️ 圖表裡「睡著」的淡紫不跟著主題色換（同一個顏色＝同一件事）', () {
    expect(NightSheets.asleepColor, const Color(0xFFB9A6FF));
  });
}
