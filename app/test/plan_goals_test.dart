// 想改善什麼（2026-11-22 grill Q1–Q8，對應表 11-22 使用者審過）。守的事：
// 【1】目標、推薦的順序、畫面上的字**逐字等於**研究文件「目標 → 建議」那一節（改文件不改程式會紅，反過來也是）
// 【2】推薦：兩個目標交錯取、重複只算一次、已經在計畫裡的跳過、最多 3 條
// 【3】選目標那一頁：最多 2 個、沒選不能 Next、Not sure — skip 交出空的
// 【4】推薦頁：預設全勾、取消的不加；Journey 那一行只在 earlier 而且沒有進行中的 Journey；量測列提醒只在 less_phone
// 【5】計畫頁：清單空的、沒問過 → 自己跳出來一次（一跳出來就記成問過）；問過了或已經有習慣就不跳
// 【6】Help me pick：從 Add a habit 進去，勾著的加進計畫、提醒預設關
import 'dart:io';

import 'package:app/screens/plan_screen.dart';
import 'package:app/services/alarm.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/plan_goals.dart';
import 'package:app/services/plan_reminders.dart';
import 'package:app/services/sleep_plan.dart';
import 'package:app/widgets/plan_goal_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

class _NoReminders implements PlanReminderScheduler {
  @override
  Future<bool> schedule(int slot, DateTime at, {required String body, required int days}) async => true;
  @override
  Future<void> cancel(int slot) async {}
}

/// 研究文件「目標 → 建議」那一節。
String _section() {
  final doc = File('../Research-Background/睡眠計畫.md').readAsStringSync();
  final start = doc.indexOf('## 目標 → 建議');
  expect(start, greaterThanOrEqualTo(0), reason: '文件裡要有「目標 → 建議」那一節');
  final next = doc.indexOf('\n## ', start + 5);
  return doc.substring(start, next < 0 ? doc.length : next);
}

Future<List<(List<String>, List<String>)>> _pumpPicker(WidgetTester tester,
    {Set<String> already = const {}, bool journeyActive = false}) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final done = <(List<String>, List<String>)>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: PlanGoalPicker(
          key: UniqueKey(), // 同一個測試裡再 pump 一次時從頭開始，不沿用上一次停在哪一頁
          alreadyInPlan: already,
          journeyActive: journeyActive,
          onDone: (g, h) => done.add((g, h)),
        ),
      ),
    ),
  ));
  return done;
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
}

void main() {
  group('【1】跟研究文件逐字一致', () {
    test('四個目標：id、畫面上的字、推薦的順序', () {
      final sec = _section();
      for (final g in kPlanGoals) {
        final row = sec.split('\n').firstWhere((l) => l.startsWith('| `${g.id}` |'),
            orElse: () => fail('文件的對應表裡找不到 ${g.id}'));
        final cells = row.split('|').map((c) => c.trim()).toList();
        expect(cells[2], g.label, reason: g.id);
        final habits = RegExp(r'[①②③④⑤]\s*`(\w+)`').allMatches(cells[3]).map((m) => m.group(1)).toList();
        expect(habits, g.habits, reason: '${g.id} 推薦的順序');
      }
      expect(RegExp(r'^\| `\w+` \| ', multiLine: true).allMatches(sec.split('### 每一條對應的依據').first).length,
          kPlanGoals.length,
          reason: '文件與程式的目標一樣多');
    });

    test('畫面上的字', () {
      final sec = _section();
      for (final s in [
        kGoalQuestion,
        kGoalSubtitle,
        kGoalSkip,
        kGoalRecTitle,
        kGoalRecSubtitle,
        kGoalJourneyLine,
        kGoalTrackedLine,
      ]) {
        expect(sec.contains(s), isTrue, reason: s);
      }
      expect(sec.contains('Add N habits'), isTrue);
      expect(goalAddLabel(2), 'Add 2 habits');
      expect(goalAddLabel(1), 'Add 1 habit');
      expect(goalAddLabel(0), 'Skip');
    });

    test('推薦的每一條都在建議清單裡（句子照抄那一整句）', () {
      for (final g in kPlanGoals) {
        for (final h in g.habits) {
          expect(suggestionById(h), isNotNull, reason: h);
        }
      }
    });
  });

  group('【2】推薦', () {
    test('單一目標照順序、最多 3 條', () {
      expect(recommendHabits(['sound']), ['temperature', 'noise', 'alcohol']);
      expect(recommendHabits(['earlier']), ['morning_light', 'dim_screen']);
    });
    test('兩個目標交錯取、重複只算一次', () {
      expect(recommendHabits(['earlier', 'sound']), ['morning_light', 'temperature', 'dim_screen']);
      expect(recommendHabits(['earlier', 'rested']), ['morning_light', 'late_caffeine', 'dim_screen']);
      expect(recommendHabits(['less_phone', 'earlier']), ['dim_screen', 'morning_light']);
    });
    test('已經在計畫裡的跳過，往後補', () {
      expect(recommendHabits(['sound'], already: {'temperature'}), ['noise', 'alcohol', 'exercise']);
      expect(recommendHabits(['less_phone'], already: {'dim_screen'}), isEmpty);
    });
    test('不認得的目標不會壞', () {
      expect(recommendHabits(['nope', 'earlier']), ['morning_light', 'dim_screen']);
    });
  });

  group('【3】【4】選目標與推薦頁', () {
    testWidgets('最多 2 個；沒選不能 Next；Not sure — skip 交出空的', (tester) async {
      final done = await _pumpPicker(tester);
      expect(tester.widget<FilledButton>(find.byKey(const Key('goal-next'))).onPressed, isNull);
      await _tap(tester, 'goal-earlier');
      await _tap(tester, 'goal-sound');
      await _tap(tester, 'goal-rested'); // 第三個點不下去
      await _tap(tester, 'goal-next');
      expect(find.byKey(const Key('goal-rec-late_caffeine')), findsNothing, reason: '第三個沒被選進去');
      expect(find.byKey(const Key('goal-recs')), findsOneWidget);

      final skipped = await _pumpPicker(tester);
      await _tap(tester, 'goal-skip');
      expect(skipped.single.$1, isEmpty);
      expect(skipped.single.$2, isEmpty);
      expect(done, isEmpty);
    });

    testWidgets('預設全勾；取消的不加；Journey 那一行在 earlier 才有', (tester) async {
      final done = await _pumpPicker(tester);
      await _tap(tester, 'goal-earlier');
      await _tap(tester, 'goal-next');
      expect(find.text(suggestionById('morning_light')!.text), findsOneWidget, reason: '整句照抄');
      expect(find.text('Add 2 habits'), findsOneWidget);
      expect(find.byKey(const Key('goal-journey')), findsOneWidget);
      expect(find.byKey(const Key('goal-tracked')), findsNothing);
      await _tap(tester, 'goal-rec-dim_screen');
      expect(find.text('Add 1 habit'), findsOneWidget);
      await _tap(tester, 'goal-add');
      expect(done.single.$1, ['earlier']);
      expect(done.single.$2, ['morning_light']);
    });

    testWidgets('Journey 進行中就不提 Journey；less_phone 提量測列', (tester) async {
      await _pumpPicker(tester, journeyActive: true);
      await _tap(tester, 'goal-earlier');
      await _tap(tester, 'goal-less_phone');
      await _tap(tester, 'goal-next');
      expect(find.byKey(const Key('goal-journey')), findsNothing);
      expect(find.text(kGoalTrackedLine), findsOneWidget);
    });

    testWidgets('畫面上不寫「會讓你…」這類保證', (tester) async {
      await _pumpPicker(tester);
      await _tap(tester, 'goal-sound');
      await _tap(tester, 'goal-rested');
      await _tap(tester, 'goal-next');
      for (final w in ['will help', 'will make', 'guarantee', 'fix your', 'improve your sleep']) {
        expect(find.textContaining(w), findsNothing, reason: w);
      }
    });
  });

  group('【5】【6】計畫頁', () {
    Future<(KeyValueStore, PlanStore)> pumpPlan(WidgetTester tester,
        {Map<String, String> initial = const {}, List<String> items = const []}) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      final kv = InMemoryKeyValueStore(initial);
      final plan = PlanStore(kv);
      await plan.load();
      for (final id in items) {
        await plan.add(PlanItem.fromSuggestion(suggestionById(id)!));
      }
      await tester.pumpWidget(MaterialApp(
        home: PlanScreen(
          plan: plan,
          bedtime: const TimeOfDay(hour: 0, minute: 30),
          alarmSettings: AlarmSettingsStore(kv),
          alarmScheduler: _FakeAlarm(),
          reminders: _NoReminders(),
          clock: () => DateTime(2026, 11, 21, 12),
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return (kv, plan);
    }

    testWidgets('清單空的、沒問過 → 跳出來一次，而且一跳出來就記成問過', (tester) async {
      final (kv, _) = await pumpPlan(tester);
      expect(find.byKey(const Key('plan-goal-sheet')), findsOneWidget);
      expect(await PlanGoalsStore(kv).asked(), isTrue);
    });

    testWidgets('問過了（例如第一次登入流程裡跳過）→ 不跳', (tester) async {
      await pumpPlan(tester, initial: {PlanGoalsStore.askedKey: '1'});
      expect(find.byKey(const Key('plan-goal-sheet')), findsNothing);
    });

    testWidgets('已經有習慣 → 不跳', (tester) async {
      await pumpPlan(tester, items: ['noise']);
      expect(find.byKey(const Key('plan-goal-sheet')), findsNothing);
    });

    testWidgets('Help me pick：勾著的加進計畫、已經有的不重複、提醒預設關', (tester) async {
      final (kv, plan) = await pumpPlan(tester, initial: {PlanGoalsStore.askedKey: '1'}, items: ['temperature']);
      await tester.tap(find.byKey(const Key('plan-add')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.byKey(const Key('plan-help-me-pick')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('plan-goal-sheet')), findsOneWidget);
      await tester.tap(find.byKey(const Key('goal-sound')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('goal-next')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('goal-add')));
      await tester.tap(find.byKey(const Key('goal-add')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(plan.items.map((i) => i.id).toList(), ['temperature', 'noise', 'alcohol', 'exercise']);
      expect(plan.items.every((i) => !i.notify), isTrue);
      expect(await PlanGoalsStore(kv).goals(), ['sound']);
    });
  });
}
