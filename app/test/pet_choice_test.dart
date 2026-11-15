// 選寵物（2026-11-15 使用者定：設定頁選小狗或貓，存在手機上、預設小狗）。
// 守：起床／等報告／睡覺三個畫面的 GIF 只有小狗版——選貓時**不能出現小狗 GIF**，
//     要走程式版退路、畫的是貓；設定頁選了要存下來、開 App 讀得回來。
import 'package:app/screens/report_loading_screen.dart';
import 'package:app/screens/settings_screen.dart';
import 'package:app/screens/wake_up_screen.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/morning_report.dart';
import 'package:app/services/pet_choice.dart';
import 'package:app/widgets/home_pet.dart';
import 'package:app/widgets/sleepy_pet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

List<String> drawn(WidgetTester tester) => tester
    .widgetList<Image>(find.byType(Image))
    .map((i) => i.image)
    .whereType<AssetImage>()
    .map((a) => a.assetName)
    .toList();

void main() {
  tearDown(() => PetChoice.current.value = PetSpecies.dog);

  testWidgets('選貓：起床不播小狗 GIF，改走程式版，畫的是貓', (tester) async {
    PetChoice.current.value = PetSpecies.cat;
    await tester.pumpWidget(
      const MaterialApp(home: WakeUpScreen(mood: 'happy')),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settle(tester, 8);
    expect(find.byKey(const Key('wake-up-gif')), findsNothing);
    expect(find.byType(HomePet), findsWidgets);
    final paths = drawn(tester);
    expect(paths.where((p) => p.contains('/cat01/')), isNotEmpty);
    expect(paths.where((p) => p.contains('dog01')), isEmpty);
  });

  testWidgets('選貓：等報告不用小狗 GIF，改星空＋貓', (tester) async {
    PetChoice.current.value = PetSpecies.cat;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final r = buildMorningReport(date: '2026-11-12');
    await tester.pumpWidget(
      MaterialApp(
        home: ReportLoadingScreen(
          report: Future.value(r),
          fallback: r,
          onView: (_) {},
          onClose: () {},
          mood: 'tired',
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await settle(tester, 5);
    expect(find.byKey(const Key('report-wait-gif')), findsNothing);
    expect(find.byType(HomePet), findsOneWidget);
    expect(drawn(tester).where((p) => p.contains('dog01')), isEmpty);
  });

  testWidgets('對照：選小狗時等報告照樣播小狗 GIF（不是把 GIF 拿掉了）', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final r = buildMorningReport(date: '2026-11-12');
    await tester.pumpWidget(
      MaterialApp(
        home: ReportLoadingScreen(
          report: Future.value(r),
          fallback: r,
          onView: (_) {},
          onClose: () {},
          mood: 'tired',
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await settle(tester, 5);
    expect(find.byKey(const Key('report-wait-gif')), findsOneWidget);
  });

  testWidgets('選貓：睡覺畫面的寵物是 tired 的貓，不是小狗的睡姿圖', (tester) async {
    PetChoice.current.value = PetSpecies.cat;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: SleepingPet(size: 240))),
      ),
    );
    await settle(tester, 3);
    expect(find.byKey(const Key('sleeping-pet-cat')), findsOneWidget);
    final paths = drawn(tester);
    expect(paths.where((p) => p.contains('/cat01/tired/')), isNotEmpty);
    expect(paths.where((p) => p.contains('dog01')), isEmpty);
  });

  testWidgets('設定頁：Pet 那一列寫目前的寵物；選 Cat 會存進手機', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final store = InMemoryKeyValueStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SettingsScreen(store: store)),
      ),
    );
    await settle(tester, 3);
    final dog = find.text('Dog');
    await tester.ensureVisible(dog);
    expect(dog, findsOneWidget);
    expect(find.text('Golden Retriever'), findsNothing, reason: '不再寫死');
    await tester.tap(dog);
    await settle(tester, 5);
    await tester.tap(find.byKey(const Key('pet-choice-cat')));
    await settle(tester, 5);
    expect(PetChoice.current.value, PetSpecies.cat);
    expect(await store.getString(PetChoice.storeKey), 'cat');
    expect(find.text('Cat'), findsOneWidget);
  });

  test('開 App 讀回上次的選擇；沒存過是小狗', () async {
    final store = InMemoryKeyValueStore();
    await PetChoice.load(store);
    expect(PetChoice.current.value, PetSpecies.dog);
    await store.setString(PetChoice.storeKey, 'cat');
    await PetChoice.load(store);
    expect(PetChoice.current.value, PetSpecies.cat);
  });
}
