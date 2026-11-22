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
import 'package:app/services/alarm.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/sleep_repository.dart';
import 'package:app/widgets/entry_intro.dart';
import 'package:app/widgets/home_pet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
    test('【1】短版：鏡頭停下之前寵物一直睡著、介面一直看不到', () {
      final land = EntryFrame.landAt(long: false);
      for (final t in _times(land)) {
        if (t >= land) break;
        final f = EntryFrame.at(t, long: false);
        expect(f.awake, 0, reason: 't=$t 還在降落就醒了：會先露出心情的臉');
        for (final p in f.ui) {
          expect(p, 0, reason: 't=$t 鏡頭還在動，介面就出現了');
        }
      }
      final start = EntryFrame.at(0, long: false);
      expect(start.camera, 0);
      expect(EntryFrame.at(EntryFrame.shortSeconds, long: false).done, isTrue);
    });

    test('【2】長版：寵物一直醒著', () {
      for (final t in _times(EntryFrame.longSeconds)) {
        expect(EntryFrame.at(t, long: true).awake, 1, reason: 't=$t');
      }
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
        expect(end.awake, 1);
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

    testWidgets('【5】冷啟動：先在天空、寵物睡著，播完回到首頁原樣', (tester) async {
      final intro = await pumpHome(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const Key('entry-intro-skip')), findsOneWidget);
      expect(intro.ui.value, 0, reason: '導覽列要等最後才出來');
      await tester.pump(const Duration(milliseconds: 600));
      expect(sleepingPet(), findsWidgets, reason: '鏡頭還沒停，寵物要是睡姿');

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
}
