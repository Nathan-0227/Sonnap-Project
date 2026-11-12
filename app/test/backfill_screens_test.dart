// 事後補時間的兩個入口（2026-11-12 定案）。
// - 睡覺畫面「I already got up」：月亮鎖住、只撥太陽，存成 recalled，並停鬧鐘
// - 首頁「Forgot to tap last night? Add times」：存完連結消失；
//   上面那句「不按也沒關係」照留（bed_mark_buttons_test 守著它存在）
import 'package:app/models/sleep_session.dart';
import 'package:app/screens/home_screen.dart';
import 'package:app/screens/sleep_mode_screen.dart';
import 'package:app/services/alarm.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/sleep_repository.dart';
import 'package:app/services/sleep_sounds.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Alarm implements AlarmScheduler {
  int cancels = 0;
  @override
  Future<void> schedule(DateTime at) async {}
  @override
  Future<void> cancel() async => cancels++;
  @override
  Future<bool> canRing() async => true;
  @override
  Future<void> requestPermission() async {}
  @override
  Future<void> openSettings() async {}
}

class _Repo implements SleepRepository {
  final SleepSession session;
  _Repo(this.session);
  @override
  Future<SleepSession> load() async => session;
}

DateTime at(int day, int h, [int m = 0]) => DateTime(2026, 11, day, h, m);

Future<void> big(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 4200);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('睡覺畫面 I already got up', () {
    Future<(BedMarkStore, _Alarm)> pump(WidgetTester tester, DateTime now) async {
      await big(tester);
      final store = BedMarkStore(InMemoryKeyValueStore());
      await store.markStart(at(11, 23, 40));
      final alarm = _Alarm();
      await tester.pumpWidget(
        MaterialApp(
          home: SleepModeScreen(
            store: store,
            startAt: at(11, 23, 40),
            clock: () => now,
            alarm: AlarmController(
              settings: AlarmSettingsStore(store.store),
              scheduler: alarm,
            ),
          ),
        ),
      );
      await settle(tester);
      return (store, alarm);
    }

    testWidgets('月亮鎖在上床時刻；存成 recalled、停鬧鐘', (tester) async {
      final (store, alarm) = await pump(tester, at(12, 9));
      await tester.tap(find.byKey(const Key('sleep-already-up')));
      await settle(tester);
      expect(find.text('When did you get up?'), findsOneWidget);
      expect(find.byKey(const Key('alarm-switch')), findsNothing,
          reason: '補時間不需要 Alarm 開關');
      expect(
        tester.widget<Text>(find.byKey(const Key('dial-bedtime'))).data,
        '23:40',
      );
      await tester.tap(find.byKey(const Key('schedule-save')));
      await settle(tester);
      final m = await store.read(now: at(12, 9));
      // 沒排鬧鐘 → 太陽預設在目標就寢＋8 小時（這裡是上床時刻 23:40 → 07:40）
      expect(m.endAt, at(12, 7, 40));
      expect(m.endKind, 'recalled');
      expect(alarm.cancels, 1);
      expect(find.byType(SleepModeScreen), findsNothing, reason: '存完離開睡覺畫面');
    });

    testWidgets('⚠️ 6.4 吋手機（1080×2340）放得下：鬧鐘、聲音、Out of bed、兩個文字鈕', (tester) async {
      // 2026-11-12 實機：加了 I already got up 之後底部溢出 21 像素。
      // 溢出時 Flutter 會丟 overflow 例外，這條就會紅。
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.625;
      tester.view.padding = const FakeViewPadding(top: 100, bottom: 130);
      addTearDown(tester.view.reset);
      final store = BedMarkStore(InMemoryKeyValueStore());
      await tester.pumpWidget(
        MaterialApp(
          home: SleepModeScreen(
            store: store,
            startAt: at(11, 23, 40),
            clock: () => at(12, 1),
            alarm: AlarmController(
              settings: AlarmSettingsStore(store.store),
              scheduler: _Alarm(),
            ),
            sounds: SleepSoundsController(
              settings: SleepSoundSettings(store.store),
              player: const PlatformSleepSoundPlayer(),
            ),
          ),
        ),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('sleep-already-up')), findsOneWidget);
      expect(find.byKey(const Key('sleep-cancel')), findsOneWidget);
    });

    testWidgets('⚠️ 起床時間晚於現在 → 不存、留在睡覺畫面', (tester) async {
      final (store, _) = await pump(tester, at(12, 6));
      await tester.tap(find.byKey(const Key('sleep-already-up')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('schedule-save')));
      await settle(tester);
      expect((await store.read(now: at(12, 6))).endAt, isNull);
      expect(find.text("That's later than now."), findsOneWidget);
    });
  });

  group('首頁補昨晚', () {
    late SleepSession session;
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      session = await const AssetSleepRepository().load();
    });

    Future<BedMarkStore> pumpHome(WidgetTester tester, DateTime now,
        {Future<void> Function(BedMarkStore)? before}) async {
      await big(tester);
      final store = BedMarkStore(InMemoryKeyValueStore());
      if (before != null) await before(store);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeScreen(
              repository: _Repo(session),
              bedMarks: store,
              alarmScheduler: _Alarm(),
              clock: () => now,
            ),
          ),
        ),
      );
      await settle(tester);
      return store;
    }

    testWidgets('昨晚沒按 → 出現連結；存完消失，兩個都是 recalled', (tester) async {
      final store = await pumpHome(tester, at(12, 9));
      expect(find.byKey(const Key('optional-note')), findsOneWidget,
          reason: '「不按也沒關係」要照留');
      await tester.ensureVisible(find.byKey(const Key('backfill-last-night')));
      await tester.tap(find.byKey(const Key('backfill-last-night')));
      await settle(tester);
      expect(find.text('Last night'), findsOneWidget);
      await tester.tap(find.byKey(const Key('schedule-save')));
      await settle(tester);
      final m = await store.read(now: at(12, 9));
      // 預設：目標 23:30、起床 = 目標 + 8 小時 = 07:30
      expect(m.startAt, at(11, 23, 30));
      expect(m.endAt, at(12, 7, 30));
      expect(m.startKind, 'recalled');
      expect(m.endKind, 'recalled');
      expect(find.byKey(const Key('backfill-last-night')), findsNothing);
    });

    testWidgets('昨晚按齊 → 不出現連結', (tester) async {
      await pumpHome(tester, at(12, 9), before: (s) async {
        await s.markStart(at(11, 23, 40));
        await s.markEnd(at(12, 7, 10));
      });
      expect(find.byKey(const Key('backfill-last-night')), findsNothing);
    });
  });
}
