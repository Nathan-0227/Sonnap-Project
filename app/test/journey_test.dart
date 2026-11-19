import 'dart:io';

import 'package:app/screens/plan_screen.dart';
import 'package:app/services/alarm.dart';
import 'package:app/services/journey_service.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/plan_reminders.dart';
import 'package:app/services/sleep_plan.dart';
import 'package:app/widgets/journey_section.dart';
import 'package:app/widgets/sleep_schedule_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 睡眠計畫的 Journey（2026-11-19）。守的都是**壞掉時不會報錯**的地方：
/// 轉盤沒鎖（可以把 Journey 的目標轉掉）、提示一直不收／新的一站不再提示、
/// 在 Dart 自己算站或判「已經到了」、作息條沒跟著這一站換、畫面上冒出 XP。

class _FakeAlarm implements AlarmScheduler {
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

class _FakeReminders implements PlanReminderScheduler {
  @override
  Future<bool> schedule(int slot, DateTime at, {required String body, required int days}) async => true;
  @override
  Future<void> cancel(int slot) async {}
}

Map<String, Object?> _state({String status = 'active', int idx = 0, int streak = 0}) {
  const stops = [
    {'wake': '10:30', 'bedtime': '03:30'},
    {'wake': '10:00', 'bedtime': '03:00'},
    {'wake': '09:50', 'bedtime': '02:50'},
  ];
  return {
    'status': status,
    'start_wake': '11:00',
    'end_wake': '09:50',
    'sleep_minutes': 420,
    'first_night': '2026-11-20',
    'stops': stops,
    'stop_index': idx,
    'on_time_streak': streak,
    'on_time_needed': 3,
    'current': stops[idx],
  };
}

JourneyInfo _info(Map<String, Object?>? j, {String? suggested}) => JourneyInfo.fromJson({
      'journey': j,
      'suggested_start': suggested,
      'min_sleep_minutes': 420,
      'step_minutes': 30,
    });

class _FakeApi implements JourneyApi {
  JourneyInfo? next;
  JourneyStartOutcome startOutcome = JourneyStartOutcome.started;
  Map<String, Object?>? lastStart;
  int stops = 0;
  _FakeApi(this.next);

  @override
  Future<JourneyInfo?> fetch() async => next;

  @override
  Future<(JourneyStartOutcome, JourneyState?)> start({
    required TimeOfDay startWake,
    required TimeOfDay endWake,
    required int sleepMinutes,
  }) async {
    lastStart = {'start': journeyHhmm(startWake), 'end': journeyHhmm(endWake), 'sleep': sleepMinutes};
    if (startOutcome == JourneyStartOutcome.started) next = _info(_state());
    return (startOutcome, next?.journey);
  }

  @override
  Future<JourneyState?> stop() async {
    stops++;
    next = _info(_state(status: 'stopped'));
    return next!.journey;
  }
}

/// 計畫頁的寵物一直在動，pumpAndSettle 等不到停。
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  group('解析與提示', () {
    test('照抄後端：站、這一站、連續天數', () {
      final j = JourneyState.fromJson(_state(idx: 1, streak: 2))!;
      expect(j.stops.length, 3);
      expect(j.current!.wake, const TimeOfDay(hour: 10, minute: 0));
      expect(j.current!.bedtime, const TimeOfDay(hour: 3, minute: 0));
      expect(j.onTimeStreak, 2);
      expect(JourneyState.fromJson({'status': 'weird'}), isNull);
    });

    test('第 1 站不提示；前進之後提示一次、看過就收；新的一站再提示；停掉不提示', () async {
      final kv = InMemoryKeyValueStore();
      final api = _FakeApi(_info(_state()));
      final c = JourneyController(store: kv, api: api);
      await c.refresh();
      expect(c.showNotice, isFalse, reason: '第 1 站是自己剛按的');
      api.next = _info(_state(idx: 1));
      await c.refresh();
      expect(c.showNotice, isTrue);
      expect(journeyNoticeText(c.journey!), 'Next stop from tonight: bed 03:00 · up 10:00');
      await c.markSeen();
      await c.refresh();
      expect(c.showNotice, isFalse, reason: '看過就收起來（重新問後端也一樣）');
      api.next = _info(_state(idx: 2));
      await c.refresh();
      expect(c.showNotice, isTrue, reason: '新的一站要再提示');
      api.next = _info(_state(status: 'done', idx: 2));
      await c.refresh();
      expect(journeyNoticeText(c.journey!), 'You reached your goal schedule');
      expect(c.showNotice, isTrue);
      api.next = _info(_state(status: 'stopped', idx: 1));
      await c.refresh();
      expect(c.showNotice, isFalse);
    });

    test('連不到後端：留著上一份，不拿失敗蓋掉', () async {
      final api = _FakeApi(_info(_state(idx: 1)));
      final c = JourneyController(store: InMemoryKeyValueStore(), api: api);
      await c.refresh();
      api.next = null;
      await c.refresh();
      expect(c.journey?.stopIndex, 1);
    });

    test('Dart 不自己算站、不判「已經到了」（都在 behavior/journey.py）', () {
      final src = [
        File('lib/services/journey_service.dart').readAsStringSync(),
        File('lib/widgets/journey_section.dart').readAsStringSync(),
      ].join();
      // 站是 stops 陣列照抄；跨午夜的判斷、30 分鐘的步伐不得在 Dart 出現
      expect(src.contains('% 1440'), isFalse);
      expect(src.contains('% (24 * 60)'), isFalse);
      expect(src.contains('advance_minutes'), isFalse);
    });
  });

  group('轉盤鎖住（Q14）', () {
    Future<void> openSheet(WidgetTester tester, KeyValueStore kv) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSleepScheduleSheet(context,
                bedtime: const TimeOfDay(hour: 3, minute: 30),
                alarmSettings: AlarmSettingsStore(kv),
                scheduler: _FakeAlarm()),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('Journey 進行中：寫 Following your journey、轉盤拖不動', (tester) async {
      final kv = InMemoryKeyValueStore();
      final c = JourneyController(store: kv, api: _FakeApi(_info(_state())));
      await c.refresh();
      await openSheet(tester, kv);
      expect(find.byKey(const Key('schedule-journey-lock')), findsOneWidget);
      final ignore = tester.widget<IgnorePointer>(find.ancestor(
          of: find.byKey(const Key('sleep-dial')), matching: find.byType(IgnorePointer)).first);
      expect(ignore.ignoring, isTrue);
    });

    testWidgets('停掉之後：不鎖', (tester) async {
      final kv = InMemoryKeyValueStore();
      final api = _FakeApi(_info(_state()));
      final c = JourneyController(store: kv, api: api);
      await c.refresh();
      await c.stop();
      await openSheet(tester, kv);
      expect(find.byKey(const Key('schedule-journey-lock')), findsNothing);
    });
  });

  group('計畫頁', () {
    Future<(JourneyController, _FakeApi)> pump(WidgetTester tester, JourneyInfo? info,
        {bool noBackend = false}) async {
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final kv = InMemoryKeyValueStore();
      final plan = PlanStore(kv);
      await plan.load();
      final api = _FakeApi(info);
      final c = JourneyController(store: kv, api: noBackend ? null : api);
      await c.refresh();
      await tester.pumpWidget(MaterialApp(
        home: PlanScreen(
          plan: plan,
          bedtime: const TimeOfDay(hour: 4, minute: 0),
          alarmSettings: AlarmSettingsStore(kv),
          alarmScheduler: _FakeAlarm(),
          reminders: _FakeReminders(),
          clock: () => DateTime(2026, 11, 20, 12),
          journey: c,
        ),
      ));
      await tester.pump();
      await tester.pump();
      return (c, api);
    }

    testWidgets('進行中：第幾站、連續幾天照抄後端；作息條是這一站；沒有 XP', (tester) async {
      await pump(tester, _info(_state(idx: 1, streak: 2)));
      expect(find.text('Journey · stop 2 of 3'), findsOneWidget);
      expect(find.text('2 of 3 on-time mornings'), findsOneWidget);
      expect(find.byKey(const Key('journey-dot-1')), findsOneWidget);
      expect(find.byKey(const Key('journey-goal')), findsOneWidget);
      expect(find.byKey(const Key('journey-notice')), findsOneWidget, reason: '剛前進到第 2 站');
      expect(tester.widget<Text>(find.byKey(const Key('plan-bedtime'))).data, '03:00',
          reason: '這一站就是目標');
      expect(tester.widget<Text>(find.byKey(const Key('plan-wake'))).data, '10:00');
      expect(find.textContaining('XP'), findsNothing);
    });

    testWidgets('沒有 Journey：Start a journey；沒有後端寫 Needs the backend', (tester) async {
      await pump(tester, _info(null));
      expect(find.byKey(const Key('journey-start')), findsOneWidget);
      await pump(tester, null, noBackend: true);
      expect(find.byKey(const Key('journey-no-backend')), findsOneWidget);
    });

    testWidgets('有後端但連不上：照實說＋Try again，連上之後出現 Start', (tester) async {
      final (_, api) = await pump(tester, null);
      expect(find.byKey(const Key('journey-unreachable')), findsOneWidget,
          reason: '不能只是一顆灰掉的按鈕');
      expect(find.byKey(const Key('journey-start')), findsNothing);
      api.next = _info(null);
      await tester.tap(find.byKey(const Key('journey-retry')));
      await settle(tester);
      expect(find.byKey(const Key('journey-start')), findsOneWidget);
    });

    testWidgets('開始：起點用後端的建議；不選終點按不了；睡不到 7 小時照 7 小時送', (tester) async {
      final (_, api) = await pump(tester, _info(null, suggested: '11:05'));
      await tester.tap(find.byKey(const Key('journey-start')));
      await settle(tester);
      expect(find.text('11:05'), findsOneWidget, reason: '起點＝最近 7 晚中間值（後端算的）');
      expect(find.text('Middle of your last 7 nights'), findsOneWidget);
      expect(find.text('At least 7h is recommended'), findsOneWidget);
      final go = find.byKey(const Key('journey-setup-go'));
      expect(tester.widget<FilledButton>(go).onPressed, isNull, reason: '終點要自己選');
      // 轉盤 04:00 → 起床 12:00（預設 +8 小時）＝8 小時；減到底只能到 7 小時
      for (var i = 0; i < 8; i++) {
        final less = find.byKey(const Key('journey-setup-less'));
        if (tester.widget<IconButton>(less).onPressed == null) break;
        await tester.tap(less);
        await tester.pump();
      }
      expect(find.text('7h'), findsOneWidget);
      await tester.tap(find.byKey(const Key('journey-setup-goal')));
      await settle(tester);
      await tester.tap(find.text('OK'));
      await settle(tester);
      await tester.tap(go);
      await settle(tester);
      expect(api.lastStart?['sleep'], 420);
      expect(find.text('Journey · stop 1 of 3'), findsOneWidget);
    });

    testWidgets('終點不比起點早：照後端說 already there，不開始', (tester) async {
      final (c, api) = await pump(tester, _info(null, suggested: '06:00'));
      api.startOutcome = JourneyStartOutcome.alreadyThere;
      await tester.tap(find.byKey(const Key('journey-start')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('journey-setup-goal')));
      await settle(tester);
      await tester.tap(find.text('OK'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('journey-setup-go')));
      await settle(tester);
      expect(find.byKey(const Key('journey-setup-error')), findsOneWidget);
      expect(c.journey, isNull);
    });

    testWidgets('Stop：問一次才停；停了之後回到 Start a journey', (tester) async {
      final (_, api) = await pump(tester, _info(_state()));
      await tester.tap(find.byKey(const Key('journey-stop')));
      await settle(tester);
      expect(api.stops, 0, reason: '先問一次');
      await tester.tap(find.byKey(const Key('journey-stop-confirm')));
      await settle(tester);
      expect(api.stops, 1);
      expect(find.byKey(const Key('journey-start')), findsOneWidget);
    });
  });
}
