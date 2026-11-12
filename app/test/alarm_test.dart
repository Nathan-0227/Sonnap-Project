// 轉盤＋鬧鐘（2026-11-12 定案）。
//
// 守的是壞掉時不會報錯的地方：
// - 只有按了 Start Sleep 才排；鬧鐘關著就不排；超過 14 小時不排
// - 下床、取消、「只關今晚」都要真的取消
// - 鬧鐘響了不會自動按下床（那是原生端，這裡守「下床才取消」的方向）
// - 轉盤的角度 ↔ 時間、跨午夜的睡眠長度
import 'package:app/models/sleep_session.dart';
import 'package:app/screens/home_screen.dart';
import 'package:app/screens/sleep_mode_screen.dart';
import 'package:app/services/alarm.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/sleep_repository.dart';
import 'package:app/widgets/sleep_dial.dart';
import 'package:app/widgets/sleep_schedule_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAlarm implements AlarmScheduler {
  final List<DateTime> scheduled = [];
  int cancels = 0;
  bool allowed;
  int requests = 0;
  FakeAlarm({this.allowed = true});

  @override
  Future<void> schedule(DateTime at) async => scheduled.add(at);
  @override
  Future<void> cancel() async => cancels++;
  @override
  Future<bool> canRing() async => allowed;
  @override
  Future<void> requestPermission() async => requests++;
  @override
  Future<void> openSettings() async {}
}

DateTime at(int day, int h, [int m = 0]) => DateTime(2026, 11, day, h, m);
const bed = TimeOfDay(hour: 23, minute: 30);

void main() {
  group('起床時間與下一次鬧鐘', () {
    test('預設 = 目標就寢 + 8 小時（04:00 → 12:00、23:30 → 07:30）', () {
      expect(
        defaultWakeTime(const TimeOfDay(hour: 4, minute: 0)),
        const TimeOfDay(hour: 12, minute: 0),
      );
      expect(defaultWakeTime(bed), const TimeOfDay(hour: 7, minute: 30));
    });

    test('排在下一個起床時刻（跨午夜）', () {
      expect(
        nextAlarmTime(at(12, 23, 40), const TimeOfDay(hour: 7, minute: 30)),
        at(13, 7, 30),
      );
      expect(
        nextAlarmTime(at(13, 2, 0), const TimeOfDay(hour: 7, minute: 30)),
        at(13, 7, 30),
      );
    });

    test('⚠️ 超過 14 小時不排', () {
      // 08:00 按開始睡、起床設 07:30 → 23.5 小時後，不排
      expect(
        nextAlarmTime(at(12, 8, 0), const TimeOfDay(hour: 7, minute: 30)),
        isNull,
      );
    });
  });

  group('AlarmController', () {
    late InMemoryKeyValueStore kv;
    late FakeAlarm fake;
    late AlarmController ctrl;
    setUp(() {
      kv = InMemoryKeyValueStore();
      fake = FakeAlarm();
      ctrl = AlarmController(settings: AlarmSettingsStore(kv), scheduler: fake);
    });

    test('鬧鐘預設開：按 Start Sleep 就排，並記下今晚幾點', () async {
      final got = await ctrl.onStartSleep(at(12, 23, 40), bed);
      expect(got, at(13, 7, 30));
      expect(fake.scheduled, [at(13, 7, 30)]);
      expect(await AlarmSettingsStore(kv).tonight(), at(13, 7, 30));
    });

    test('鬧鐘關著 → 不排', () async {
      await AlarmSettingsStore(
        kv,
      ).save(wake: const TimeOfDay(hour: 7, minute: 0), enabled: false);
      expect(await ctrl.onStartSleep(at(12, 23, 40), bed), isNull);
      expect(fake.scheduled, isEmpty);
    });

    test('只關今晚：取消，但轉盤上的設定不變', () async {
      await AlarmSettingsStore(
        kv,
      ).save(wake: const TimeOfDay(hour: 7, minute: 0), enabled: true);
      await ctrl.onStartSleep(at(12, 23, 40), bed);
      await ctrl.cancelTonight();
      expect(fake.cancels, 1);
      expect(await AlarmSettingsStore(kv).tonight(), isNull);
      expect(await AlarmSettingsStore(kv).enabled(), isTrue);
      expect(
        await AlarmSettingsStore(kv).wakeTime(bed),
        const TimeOfDay(hour: 7, minute: 0),
      );
    });
  });

  group('睡覺畫面上改今晚的鬧鐘', () {
    test('改今晚：重排並記下新時間，轉盤上的起床時間不變', () async {
      final kv = InMemoryKeyValueStore();
      final fake = FakeAlarm();
      final ctrl = AlarmController(
        settings: AlarmSettingsStore(kv),
        scheduler: fake,
      );
      await AlarmSettingsStore(
        kv,
      ).save(wake: const TimeOfDay(hour: 7, minute: 30), enabled: true);
      await ctrl.onStartSleep(at(12, 23, 40), bed);
      final got = await ctrl.setTonightAt(
        at(13, 2, 0),
        const TimeOfDay(hour: 6, minute: 0),
      );
      expect(got, at(13, 6, 0));
      expect(fake.scheduled.last, at(13, 6, 0));
      expect(await AlarmSettingsStore(kv).tonight(), at(13, 6, 0));
      expect(
        await AlarmSettingsStore(kv).wakeTime(bed),
        const TimeOfDay(hour: 7, minute: 30),
      );
    });

    test('⚠️ 改成超過 14 小時後 → 不動原本的鬧鐘', () async {
      final kv = InMemoryKeyValueStore();
      final fake = FakeAlarm();
      final ctrl = AlarmController(
        settings: AlarmSettingsStore(kv),
        scheduler: fake,
      );
      await ctrl.onStartSleep(at(12, 23, 40), bed);
      // 02:00 改成 01:55 → 隔天 01:55，快 24 小時後
      expect(
        await ctrl.setTonightAt(
          at(13, 2, 0),
          const TimeOfDay(hour: 1, minute: 55),
        ),
        isNull,
      );
      expect(fake.scheduled, [at(13, 7, 30)]);
      expect(await AlarmSettingsStore(kv).tonight(), at(13, 7, 30));
    });
  });

  group('轉盤的數學', () {
    test('正上方 00:00、右 06:00、下 12:00、左 18:00', () {
      expect(minutesForOffset(const Offset(0, -100)), 0);
      expect(minutesForOffset(const Offset(100, 0)), 6 * 60);
      expect(minutesForOffset(const Offset(0, 100)), 12 * 60);
      expect(minutesForOffset(const Offset(-100, 0)), 18 * 60);
    });

    test('每 5 分鐘一格', () {
      for (var dx = -100.0; dx <= 100; dx += 7) {
        expect(minutesForOffset(Offset(dx, -60)) % kDialStepMinutes, 0);
      }
    });

    test('睡眠長度跨午夜', () {
      expect(
        sleepSpan(bed, const TimeOfDay(hour: 7, minute: 0)),
        const Duration(hours: 7, minutes: 30),
      );
      expect(formatSpan(const Duration(hours: 8)), '8h');
      expect(formatSpan(const Duration(hours: 7, minutes: 30)), '7h 30m');
    });
  });

  group('面板與首頁', () {
    // ⚠️ 資料檔在 setUpAll 讀：testWidgets 裡的時鐘是假的，真的讀檔會永遠等不到。
    late SleepSession session;
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      session = await const AssetSleepRepository().load();
    });

    Future<void> big(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 4200);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('打開鬧鐘但沒權限 → 先問一次，還是不行就顯示說明', (tester) async {
      await big(tester);
      final fake = FakeAlarm(allowed: false);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SleepScheduleSheet(
              bedtime: bed,
              wake: const TimeOfDay(hour: 7, minute: 30),
              alarmEnabled: false,
              scheduler: fake,
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('alarm-permission-note')), findsNothing);
      await tester.tap(find.byKey(const Key('alarm-switch')));
      await tester.pump();
      await tester.pump();
      expect(fake.requests, 1, reason: '打開開關時才問（Q12）');
      expect(find.byKey(const Key('alarm-permission-note')), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);
    });

    testWidgets('轉盤中間只顯示數字，不判斷好壞', (tester) async {
      await big(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SleepScheduleSheet(
              bedtime: const TimeOfDay(hour: 4, minute: 0),
              wake: const TimeOfDay(hour: 7, minute: 0),
              alarmEnabled: true,
              scheduler: FakeAlarm(),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('3h'), findsOneWidget);
      for (final word in ['ecommend', 'oo short', 'nough']) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
    });

    testWidgets('轉盤下面有就寢／鬧鐘雙欄卡；鬧鐘關掉時右欄改叫 Wake up', (tester) async {
      await big(tester);
      Future<void> show(bool alarmOn) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SleepScheduleSheet(
              key: ValueKey(alarmOn),
              bedtime: bed,
              wake: const TimeOfDay(hour: 8, minute: 15),
              alarmEnabled: alarmOn,
              scheduler: FakeAlarm(),
            ),
          ),
        ),
      );
      await show(true);
      await tester.pump();
      expect(find.text('Bed time'), findsOneWidget);
      expect(find.text('Alarm'), findsWidgets);
      final bedText = tester.widget<Text>(find.byKey(const Key('dial-bedtime')));
      final wakeText = tester.widget<Text>(find.byKey(const Key('dial-wake')));
      expect(bedText.data, '23:30');
      expect(wakeText.data, '08:15');
      await show(false);
      await tester.pump();
      expect(find.text('Wake up'), findsOneWidget);
    });

    testWidgets('⚠️ 睡覺畫面的轉盤：月亮拖不動，太陽拖得動', (tester) async {
      await big(tester);
      TimeOfDay? bedSeen;
      TimeOfDay? wakeSeen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SleepDial(
                bedtime: const TimeOfDay(hour: 0, minute: 0),
                wake: const TimeOfDay(hour: 12, minute: 0),
                onBedtimeChanged: (t) => bedSeen = t,
                onWakeChanged: (t) => wakeSeen = t,
                bedLocked: true,
              ),
            ),
          ),
        ),
      );
      final box = tester.getRect(find.byKey(const Key('sleep-dial')));
      // 月亮在正上方、太陽在正下方，各往右拖
      await tester.dragFrom(box.topCenter + const Offset(0, 19), const Offset(120, 60));
      await tester.dragFrom(box.bottomCenter - const Offset(0, 19), const Offset(-120, -60));
      expect(bedSeen, isNull, reason: '已經上床了，就寢時刻不能改');
      expect(wakeSeen, isNotNull);
    });

    testWidgets('點首頁時鐘卡 → 滑出轉盤', (tester) async {
      await big(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeScreen(
              repository: _Repo(session),
              bedMarks: BedMarkStore(InMemoryKeyValueStore()),
              alarmScheduler: FakeAlarm(),
              clock: () => at(12, 9),
            ),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(find.byKey(const Key('bedtime-row')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('sleep-dial')), findsOneWidget);
    });

    testWidgets('按 Start Sleep → 排鬧鐘；睡覺畫面顯示時間；按下床 → 取消', (tester) async {
      await big(tester);
      final kv = InMemoryKeyValueStore();
      final fake = FakeAlarm();
      var now = at(12, 23, 40);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeScreen(
              repository: _Repo(session),
              bedMarks: BedMarkStore(kv),
              alarmScheduler: fake,
              clock: () => now,
            ),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(find.byKey(const Key('start-sleep')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(fake.scheduled, [at(13, 7, 30)], reason: '目標 23:30 → 預設起床 07:30');
      expect(find.byType(SleepModeScreen), findsOneWidget);
      expect(find.textContaining('07:30'), findsWidgets);

      // 點鬧鐘列 → 跳出跟外面一樣的轉盤，月亮鎖在上床時刻 → 關掉 Alarm → Save
      await tester.tap(find.byKey(const Key('sleep-alarm')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('sleep-dial')), findsOneWidget);
      expect(find.text("Tonight's alarm"), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('dial-bedtime'))).data,
        '23:40',
        reason: '月亮固定在按 Start Sleep 的時刻',
      );
      await tester.tap(find.byKey(const Key('alarm-switch')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('schedule-save')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(fake.cancels, 1, reason: '只關今晚要真的取消');
      expect(
        tester.widget<Text>(find.byKey(const Key('sleep-alarm-time'))).data,
        'Off',
      );

      now = at(13, 7, 10);
      await tester.tap(find.byKey(const Key('sleep-out-of-bed')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(fake.cancels, 2, reason: '下床要取消鬧鐘');
    });
  });
}

class _Repo implements SleepRepository {
  final SleepSession session;
  _Repo(this.session);
  @override
  Future<SleepSession> load() async => session;
}
