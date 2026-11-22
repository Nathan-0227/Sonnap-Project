// 進場動畫（2026-11-22，widgets/entry_intro.dart）。
//
// 守的是壞掉時不會報錯的地方：
// - 短版鏡頭停下之前寵物一直是睡姿——不先露一張可能是錯的臉（使用者選 B）
// - 長版寵物一直醒著（第一次登入流程裡要看得出選了狗還是貓）
// - 鏡頭還在動時介面看不到；播完一定回到首頁原本的樣子、導覽列可以按
// - 點一下跳過；減少動態效果只淡入、不出現睡姿
// - 測試與沒給 intro 的地方完全不播
import 'package:app/main.dart';
import 'package:app/models/sleep_session.dart';
import 'package:app/screens/home_screen.dart';
import 'package:app/screens/welcome_flow.dart';
import 'package:app/services/alarm.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/sleep_repository.dart';
import 'package:app/widgets/entry_intro.dart';
import 'package:app/widgets/home_pet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'welcome_flow_test.dart' show FakePermissions;

class _ImmediateRepository implements SleepRepository {
  final SleepSession session;
  const _ImmediateRepository(this.session);

  @override
  Future<SleepSession> load() async => session;
}

class _NoAlarm implements AlarmScheduler {
  @override
  Future<void> schedule(DateTime at) async {}
  @override
  Future<void> cancel() async {}
  @override
  Future<bool> canRing() async => true;
  @override
  Future<void> requestPermission() async {}
  @override
  Future<void> openSettings() async {}
}

List<double> _times(double total) => [for (var t = 0.0; t <= total + .2; t += 0.02) t];

void main() {
  group('時間軸（EntryFrame）', () {
    test('【1】短版：鏡頭停下之前介面一直看不到', () {
      final land = EntryFrame.landAt(long: false);
      for (final t in _times(land)) {
        if (t >= land) break;
        final f = EntryFrame.at(t, long: false);
        for (final p in f.ui) {
          expect(p, 0, reason: 't=$t 鏡頭還在動，介面就出現了');
        }
      }
      final start = EntryFrame.at(0, long: false);
      expect(start.camera, 0);
      expect(EntryFrame.at(EntryFrame.shortSeconds, long: false).done, isTrue);
    });

    test('【3】鏡頭只往下、不回頭；播完是首頁原本的樣子', () {
      for (final long in [false, true]) {
        var last = -1.0;
        for (final t in _times(EntryFrame.totalSeconds(long: long))) {
          final c = EntryFrame.at(t, long: long).camera;
          expect(c, greaterThanOrEqualTo(last), reason: 'long=$long t=$t');
          last = c;
        }
        final end = EntryFrame.at(EntryFrame.totalSeconds(long: long), long: long);
        expect(end.camera, 1);
        expect(end.ui, everyElement(1.0));
        expect(end.hop, 0);
      }
    });

    test('【4】兩版都在 2 秒內播完（一天開很多次）', () {
      expect(EntryFrame.shortSeconds, lessThanOrEqualTo(2));
      expect(EntryFrame.longSeconds, lessThanOrEqualTo(2));
    });
  });

  group('首頁', () {
    late SleepSession sample;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      sample = await const AssetSleepRepository().load();
    });

    Future<EntryIntro> pumpHome(WidgetTester tester, {bool reduceMotion = false, bool withIntro = true}) async {
      final intro = EntryIntro();
      addTearDown(intro.dispose);
      if (withIntro) intro.play();
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: const Size(400, 860), disableAnimations: reduceMotion),
          child: Scaffold(
            body: HomeScreen(
              repository: _ImmediateRepository(sample),
              bedMarks: BedMarkStore(InMemoryKeyValueStore()),
              alarmScheduler: _NoAlarm(),
              clock: () => DateTime(2026, 11, 22, 14),
              intro: withIntro ? intro : null,
            ),
          ),
        ),
      ));
      return intro;
    }

    Finder sleepingPet() => find.byWidgetPredicate((w) => w is HomePet && w.mood == 'tired');
    bool moodIsTired(SleepSession s) => s.status.petMood == 'tired';

    testWidgets('【5】冷啟動：先在天空，寵物從頭到尾都是那一晚的心情，播完回到首頁原樣', (tester) async {
      final intro = await pumpHome(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const Key('entry-intro-skip')), findsOneWidget);
      expect(intro.ui.value, 0, reason: '導覽列要等最後才出來');
      await tester.pump(const Duration(milliseconds: 600));
      // 11-22 使用者定：不先畫睡姿，降落途中就是那一晚的心情
      expect(find.byWidgetPredicate((w) => w is HomePet && w.mood == sample.status.petMood),
          findsWidgets, reason: '降落途中要畫那一晚的心情');
      if (!moodIsTired(sample)) expect(sleepingPet(), findsNothing, reason: '降落途中不准出現睡姿');

      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('entry-intro-skip')), findsNothing);
      expect(intro.ui.value, 1);
      expect(intro.pending, isFalse);
      if (!moodIsTired(sample)) expect(sleepingPet(), findsNothing);
      expect(find.byKey(const Key('mood-chip')), findsOneWidget);
    });

    testWidgets('【6】點一下就跳過', (tester) async {
      final intro = await pumpHome(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('entry-intro-skip')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const Key('entry-intro-skip')), findsNothing);
      expect(intro.ui.value, 1);
    });

    testWidgets('【7】減少動態效果：只淡入，不出現睡姿、不擋點擊', (tester) async {
      final intro = await pumpHome(tester, reduceMotion: true);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byKey(const Key('entry-intro-skip')), findsNothing);
        if (!moodIsTired(sample)) expect(sleepingPet(), findsNothing);
      }
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(intro.ui.value, 1);
    });

    testWidgets('【8】沒給 intro 就完全不播', (tester) async {
      await pumpHome(tester, withIntro: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('entry-intro-skip')), findsNothing);
      expect(find.byType(EntrySky), findsNothing);
    });
  });

  test('【9】只有正式的 App 打開：SonnapApp 預設不播', () {
    expect(const SonnapApp().entryAnimation, isFalse);
  });

  group('一張張錯開', () {
    test('【10】最晚那張卡片在播完前就到位（播完那一下不會跳）', () {
      for (final long in [false, true]) {
        final total = EntryFrame.totalSeconds(long: long);
        final f = EntryFrame.at(total - .01, long: long);
        expect(f.done, isFalse);
        expect(f.item(entryCardDelay(99)), greaterThan(.99), reason: 'long=$long');
        for (final p in f.ui) {
          expect(p, greaterThan(.99), reason: 'long=$long');
        }
      }
    });

    test('【11】卡片延遲一張比一張晚、最晚 0.3 秒', () {
      var last = -1.0;
      for (var i = 0; i < 20; i++) {
        expect(entryCardDelay(i), greaterThanOrEqualTo(last));
        last = entryCardDelay(i);
      }
      expect(entryCardDelay(100), .3);
    });
  });

  group('歡迎頁開場', () {
    double start(double Function(WelcomeOpening) pick) {
      for (var t = 0.0; t < WelcomeOpening.seconds; t += .01) {
        if (pick(WelcomeOpening.at(t)) > 0) return t;
      }
      return 99;
    }

    test('【12】星星 → 寵物 → 標題 → 按鈕，播完全部到位', () {
      final s = start((o) => o.stars), pet = start((o) => o.pet);
      final title = start((o) => o.title), button = start((o) => o.button);
      expect(s, lessThan(pet));
      expect(pet, lessThan(title));
      expect(title, lessThan(button));
      final end = WelcomeOpening.at(WelcomeOpening.seconds);
      for (final v in [end.stars, end.topBar, end.pet, end.title, end.subtitle, end.body, end.button]) {
        expect(v, 1);
      }
    });

    Future<void> pumpWelcome(WidgetTester tester, {required bool animate, bool reduce = false}) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: const Size(400, 860), disableAnimations: reduce),
          child: WelcomeFlow(
            initialBedtime: const TimeOfDay(hour: 1, minute: 30),
            initialWake: const TimeOfDay(hour: 9, minute: 30),
            store: InMemoryKeyValueStore(),
            permissions: FakePermissions(),
            animateOpening: animate,
            onFinish: (_) async => null,
            onDone: () {},
          ),
        ),
      ));
    }

    double buttonOpacity(WidgetTester tester) {
      final o = find.ancestor(of: find.byKey(const Key('welcome-start')), matching: find.byType(Opacity));
      return o.evaluate().isEmpty ? 1 : tester.widget<Opacity>(o.first).opacity;
    }

    testWidgets('【13】打開時按鈕最後才出來，1.6 秒後到位', (tester) async {
      await pumpWelcome(tester, animate: true);
      await tester.pump(const Duration(milliseconds: 300));
      expect(buttonOpacity(tester), 0);
      for (var i = 0; i < 18; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(buttonOpacity(tester), 1);
    });

    testWidgets('【14】沒打開或減少動態效果：一開始就在', (tester) async {
      await pumpWelcome(tester, animate: false);
      await tester.pump();
      expect(buttonOpacity(tester), 1);
      await pumpWelcome(tester, animate: true, reduce: true);
      await tester.pump();
      expect(buttonOpacity(tester), 1);
    });
  });
}
