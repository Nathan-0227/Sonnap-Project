import 'dart:io';

import 'package:app/screens/plan_screen.dart';
import 'package:app/services/alarm.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/challenges_service.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/nightly_sync.dart';
import 'package:app/services/pet_notes.dart';
import 'package:app/services/plan_reminders.dart';
import 'package:app/services/sleep_plan.dart';
import 'package:app/widgets/home_pet.dart';
import 'package:app/widgets/pet_notes_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 睡眠計畫（2026-11-19）。守的都是**壞掉時不會報錯**的地方：
/// 措辭漂離研究文件、id 跟起床自評對不上、一天切錯、提醒排到就寢提醒的位置、
/// 「沒量到」畫成「沒做到」、後端那句被改寫。

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
  final scheduled = <int, DateTime>{};
  final cancelled = <int>[];
  @override
  Future<bool> schedule(int slot, DateTime at, {required String body, required int days}) async {
    scheduled[slot] = at;
    return true;
  }

  @override
  Future<void> cancel(int slot) async => cancelled.add(slot);
}

const _bed = TimeOfDay(hour: 0, minute: 30);
const _wake = TimeOfDay(hour: 9, minute: 0);

Future<(PlanStore, _FakeReminders)> Function(WidgetTester,
    {ChallengesResult? challenges, bool reduceMotion, String? mood})? _pumpPlan;

Future<PlanStore> pumpPlanForFeedback(WidgetTester tester, {bool reduceMotion = false, String? mood}) async {
  final (plan, _) = await _pumpPlan!(tester, reduceMotion: reduceMotion, mood: mood);
  return plan;
}

void main() {
  group('措辭與 id', () {
    test('建議清單逐字照抄研究文件（改措辭要先改文件、使用者審過）', () {
      final doc = File('../Research-Background/睡眠計畫.md').readAsStringSync();
      final rows = RegExp(r'^\| H\w+ \| `(\w+)` \| (.+?) \|', multiLine: true)
          .allMatches(doc)
          .map((m) => (m.group(1)!, m.group(2)!.trim()))
          .toList();
      expect(rows, isNotEmpty);
      expect(
        [for (final s in kPlanSuggestions) (s.id, s.text)],
        rows,
        reason: '畫面上的句子跟審過的那份不一樣時，不會有任何錯誤訊息',
      );
    });

    test('對得上起床自評的 id 跟 morning_tips.TAGS 的鍵一樣（之後才比得起來）', () {
      final py = File('../behavior/morning_tips.py').readAsStringSync();
      final tags = RegExp(r'^\s+"(\w+)": "[^"]+",$', multiLine: true)
          .allMatches(py.substring(py.indexOf('TAGS = {'), py.indexOf('}', py.indexOf('TAGS = {'))))
          .map((m) => m.group(1)!)
          .toSet();
      for (final id in ['late_caffeine', 'alcohol', 'napped', 'temperature', 'noise', 'exercise']) {
        expect(tags, contains(id));
        expect(suggestionById(id), isNotNull);
      }
    });

    test('notes 的建議 → Plan：每個 tip id 都在後端清單裡、每個目標都在建議清單裡', () {
      final py = File('../behavior/morning_tips.py').readAsStringSync();
      for (final e in kTipToPlan.entries) {
        expect(py, contains('"${e.key}": ('), reason: '後端沒有 ${e.key}');
        expect(suggestionById(e.value), isNotNull);
      }
      // 「說明」那幾句不叫人做事，不能出現「Add to my plan」
      for (final note in ['T9', 'T10', 'T11', 'P4', 'P5', 'P8']) {
        expect(kTipToPlan.containsKey(note), isFalse);
      }
    });
  });

  group('時間', () {
    test('一天從起床前 3 小時開始：凌晨三點還沒睡算前一天', () {
      expect(planDayOf(DateTime(2026, 11, 20, 3, 0), _wake), DateTime(2026, 11, 19));
      expect(planDayOf(DateTime(2026, 11, 20, 5, 59), _wake), DateTime(2026, 11, 19));
      expect(planDayOf(DateTime(2026, 11, 20, 6, 0), _wake), DateTime(2026, 11, 20));
      expect(planDayOf(DateTime(2026, 11, 20, 23, 50), _wake), DateTime(2026, 11, 20));
    });

    test('時間跟著作息走；挑時刻存成相對、取較短那一段（跨午夜）', () {
      const item = PlanItem(id: 'x', text: 'x', anchor: PlanAnchor.bedtime, offsetMinutes: -360);
      expect(itemTime(item, bedtime: _bed, wake: _wake), const TimeOfDay(hour: 18, minute: 30));
      expect(itemTime(item, bedtime: const TimeOfDay(hour: 23, minute: 0), wake: _wake),
          const TimeOfDay(hour: 17, minute: 0));
      expect(offsetFor(const TimeOfDay(hour: 23, minute: 30), PlanAnchor.bedtime, bedtime: _bed, wake: _wake),
          -60);
      expect(relativeLabel(item), '6h before bedtime');
    });

    test('提醒只排在要做的星期幾', () {
      // 2026-11-20 是星期五；只勾星期一
      const item = PlanItem(
          id: 'x', text: 'x', anchor: PlanAnchor.wake, offsetMinutes: 0, notify: true, days: 0x01);
      final at = nextReminderAt(item, DateTime(2026, 11, 20, 12), bedtime: _bed, wake: _wake)!;
      expect(at.weekday, DateTime.monday);
      expect(at, DateTime(2026, 11, 23, 9, 0));
    });
  });

  group('清單與打勾', () {
    test('存起來重開讀得回來；重複加不會變兩條；拿掉時打勾紀錄一起清', () async {
      final kv = InMemoryKeyValueStore();
      final plan = PlanStore(kv);
      await plan.load();
      final day = DateTime(2026, 11, 20);
      expect(await plan.add(PlanItem.fromSuggestion(kPlanSuggestions.first)), isTrue);
      expect(await plan.add(PlanItem.fromSuggestion(kPlanSuggestions.first)), isFalse);
      await plan.setChecked(kPlanSuggestions.first.id, day, true);

      final again = PlanStore(kv);
      await again.load();
      expect(again.items.map((i) => i.id), [kPlanSuggestions.first.id]);
      expect(again.isChecked(kPlanSuggestions.first.id, day), isTrue);

      await again.remove(kPlanSuggestions.first.id);
      await again.add(PlanItem.fromSuggestion(kPlanSuggestions.first));
      expect(again.isChecked(kPlanSuggestions.first.id, day), isFalse,
          reason: '拿掉再加回來要從 0 開始');
    });

    test('連續天數：今天還沒勾不算斷、不用做的日子跳過', () async {
      final plan = PlanStore(InMemoryKeyValueStore());
      await plan.load();
      // 只有平日
      await plan.add(const PlanItem(id: 'w', text: 'w', anchor: PlanAnchor.bedtime, offsetMinutes: 0, days: 0x1F));
      // 星期四、五（11-19、11-20）勾了；星期一（11-23）還沒勾
      await plan.setChecked('w', DateTime(2026, 11, 19), true);
      await plan.setChecked('w', DateTime(2026, 11, 20), true);
      expect(plan.streak('w', DateTime(2026, 11, 23)), 2, reason: '週末不用做、今天還沒過完，都不算斷');
      await plan.setChecked('w', DateTime(2026, 11, 23), true);
      expect(plan.streak('w', DateTime(2026, 11, 23)), 3);
    });
  });

  group('提醒', () {
    test('全部取消再排；永遠不碰 slot 0（就寢提醒）；只排開了提醒的', () async {
      final r = _FakeReminders();
      await syncPlanReminders(
        r,
        const [
          PlanItem(id: 'a', text: 'a', anchor: PlanAnchor.bedtime, offsetMinutes: -60),
          PlanItem(id: 'b', text: 'b', anchor: PlanAnchor.bedtime, offsetMinutes: -60, notify: true),
        ],
        now: DateTime(2026, 11, 20, 12),
        bedtime: _bed,
        wake: _wake,
      );
      expect(r.cancelled, [for (var i = 1; i <= kMaxPlanItems; i++) i]);
      expect(r.cancelled, isNot(contains(0)));
      expect(r.scheduled.keys, [2]);
      expect(r.scheduled[2], DateTime(2026, 11, 20, 23, 30));
    });
  });

  group('Plan 頁', () {
    ChallengeProgress ch(String id, ChallengeState state, String detail) => ChallengeProgress(
          challengeId: id,
          kind: 'time',
          title: 'TITLE-$id',
          description: '',
          detail: detail,
          state: state,
          progress: state == ChallengeState.insufficientData ? null : 1,
          recordedNights: 1,
          windowDays: 1,
          lowerIsBetter: false,
        );

    Future<(PlanStore, _FakeReminders)> pumpPlan(WidgetTester tester,
        {ChallengesResult? challenges, bool reduceMotion = false, String? mood}) async {
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final kv = InMemoryKeyValueStore();
      final plan = PlanStore(kv);
      await plan.load();
      await plan.add(PlanItem.fromSuggestion(suggestionById('late_caffeine')!));
      final nightly = NightlySync(bedMarks: BedMarkStore(kv))..challenges = challenges;
      final reminders = _FakeReminders();
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: PlanScreen(
          petMood: mood == null ? null : () async => mood,
          plan: plan,
          nightly: nightly,
          bedtime: _bed,
          alarmSettings: AlarmSettingsStore(kv),
          alarmScheduler: _FakeAlarm(),
          reminders: reminders,
          clock: () => DateTime(2026, 11, 20, 12),
        ),
      ));
      await tester.pump();
      await tester.pump();
      return (plan, reminders);
    }
    _pumpPlan = pumpPlan;

    testWidgets('量測那幾列：整句照抄後端；沒量到寫「—」不是空圈', (tester) async {
      await pumpPlan(
        tester,
        challenges: ChallengesResult(ChallengesStatus.ok, challenges: [
          ch('on_time_tonight', ChallengeState.completed, 'SENTINEL-A'),
          ch('phone_in_bed_tonight', ChallengeState.inProgress, 'SENTINEL-B'),
          ch('up_on_time', ChallengeState.insufficientData, 'SENTINEL-C'),
        ]),
      );
      for (final s in ['SENTINEL-A', 'SENTINEL-B', 'SENTINEL-C']) {
        expect(find.text(s), findsOneWidget);
      }
      final nodata = find.descendant(
          of: find.byKey(const Key('plan-measured-up_on_time')),
          matching: find.byKey(const Key('plan-measured-nodata')));
      expect(nodata, findsOneWidget, reason: '「沒量到」畫成空圈會被讀成「沒做到」');
    });

    testWidgets('沒有後端：照實說，不畫成沒做到', (tester) async {
      await pumpPlan(tester);
      expect(find.byKey(const Key('plan-measured-unavailable')), findsOneWidget);
    });

    testWidgets('勾一條：存下來；畫面上沒有 XP、沒有分數', (tester) async {
      final (plan, _) = await pumpPlan(tester);
      await tester.tap(find.byKey(const Key('plan-check-late_caffeine')));
      await tester.pump();
      expect(plan.isChecked('late_caffeine', DateTime(2026, 11, 20)), isTrue);
      expect(find.textContaining('XP'), findsNothing, reason: '自己勾的不給 XP（紅線 5）');
    });

    testWidgets('作息卡顯示轉盤上的起床（沒設過＝就寢 + 8 小時）', (tester) async {
      await pumpPlan(tester);
      expect(find.text('00:30'), findsWidgets);
      expect(find.text('08:30'), findsOneWidget);
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    testWidgets('加一條：先開設定頁，按了 Add to my plan 才加進去；關掉就不加', (tester) async {
      final (plan, _) = await pumpPlan(tester);
      await tester.tap(find.byKey(const Key('plan-add')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('plan-suggest-dim_screen')));
      await settle(tester);
      expect(find.text('New habit'), findsOneWidget);
      expect(plan.contains('dim_screen'), isFalse, reason: '選了建議還沒按 Add，不該先加進去');
      await tester.tap(find.byKey(const Key('plan-editor-close')));
      await settle(tester);
      expect(plan.contains('dim_screen'), isFalse);

      await tester.tap(find.byKey(const Key('plan-add')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('plan-suggest-dim_screen')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('plan-editor-save')));
      await settle(tester);
      expect(plan.contains('dim_screen'), isTrue);
    });

    testWidgets('自己寫一條：沒寫字不能加', (tester) async {
      final (plan, _) = await pumpPlan(tester);
      await tester.tap(find.byKey(const Key('plan-add')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('plan-custom-add')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('plan-editor-save')));
      await settle(tester);
      expect(plan.items.where((i) => i.isCustom), isEmpty);
      await tester.enterText(find.byKey(const Key('plan-editor-text')), 'Stretch for 5 minutes');
      await tester.pump();
      await tester.tap(find.byKey(const Key('plan-editor-save')));
      await settle(tester);
      expect(plan.items.where((i) => i.isCustom).single.text, 'Stretch for 5 minutes');
    });

    testWidgets('清單從寵物腳下開始，捲動不會蓋到寵物', (tester) async {
      await pumpPlan(tester);
      final pet = tester.getRect(find.byKey(const Key('plan-pet')));
      final list = tester.getRect(find.byKey(const Key('plan-list')));
      expect(list.top, greaterThanOrEqualTo(pet.bottom));
    });
  });

  group('勾下去的回饋（Q36、Q40–Q46：只有當下，不累積）', () {
    testWidgets('勾下去：Nice! 出現、一會兒就消失；寵物跳起來；沒有任何點數', (tester) async {
      await pumpPlanForFeedback(tester);
      final rest = tester.getRect(find.descendant(of: find.byKey(const Key('plan-pet-body')), matching: find.byType(HomePet))).top;
      await tester.tap(find.byKey(const Key('plan-check-late_caffeine')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('plan-nice')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 280));
      expect(tester.getRect(find.descendant(of: find.byKey(const Key('plan-pet-body')), matching: find.byType(HomePet))).top, lessThan(rest - 10),
          reason: '寵物跳一下');
      expect(find.byIcon(Icons.auto_awesome), findsNothing, reason: '不冒星星：回饋只在方格那邊演');
      expect(find.textContaining('XP'), findsNothing);
      expect(find.textContaining('+'), findsNothing, reason: '不累積：沒有 +1、+5 這種數字');
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('plan-nice')), findsNothing, reason: '回饋只在當下，不留著');
    });

    testWidgets('取消勾選：什麼都沒有', (tester) async {
      final plan = await pumpPlanForFeedback(tester);
      await plan.setChecked('late_caffeine', DateTime(2026, 11, 20), true);
      await tester.pump();
      await tester.tap(find.byKey(const Key('plan-check-late_caffeine')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(plan.isChecked('late_caffeine', DateTime(2026, 11, 20)), isFalse);
      expect(find.byKey(const Key('plan-nice')), findsNothing);
      expect(find.byIcon(Icons.auto_awesome), findsNothing);
    });

    test('跳的每一格都接得上（不會一格突然變形）、最後回到原狀', () {
      var prev = petJumpPose(0);
      for (var i = 1; i <= 400; i++) {
        final j = petJumpPose(i / 400);
        expect((j.scaleX - prev.scaleX).abs(), lessThan(0.01), reason: 't=${i / 400}');
        expect((j.scaleY - prev.scaleY).abs(), lessThan(0.01), reason: 't=${i / 400}');
        expect((j.lift - prev.lift).abs(), lessThan(0.02), reason: 't=${i / 400}');
        prev = j;
      }
      expect(petJumpPose(1), (lift: 0.0, scaleX: 1.0, scaleY: 1.0));
      expect(petJumpPose(0.1).lift, 0, reason: '先蹲、還沒離地');
      expect(petJumpPose(0.1).scaleY, lessThan(1), reason: '蹲＝壓扁');
    });

    testWidgets('寵物的臉維持後端的心情，勾了也不換成開心', (tester) async {
      await pumpPlanForFeedback(tester, mood: 'anxious');
      await tester.tap(find.byKey(const Key('plan-check-late_caffeine')));
      await tester.pump(const Duration(milliseconds: 100));
      final pets = tester.widgetList<HomePet>(find.byType(HomePet));
      expect(pets.map((p) => p.mood).toSet(), {'anxious'},
          reason: '臉是後端判的心情；勾一下就畫開心＝沒有根據的心情（同紅線 5）');
    });

    testWidgets('減少動態效果：不跳、不冒星星，但 Nice! 文字照樣出現', (tester) async {
      await pumpPlanForFeedback(tester, reduceMotion: true);
      await tester.tap(find.byKey(const Key('plan-check-late_caffeine')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('plan-nice')), findsOneWidget);
      final rest = tester.getRect(find.descendant(of: find.byKey(const Key('plan-pet-body')), matching: find.byType(HomePet))).top;
      await tester.pump(const Duration(milliseconds: 280));
      expect(tester.getRect(find.descendant(of: find.byKey(const Key('plan-pet-body')), matching: find.byType(HomePet))).top, rest, reason: '寵物不動');
      await tester.pump(const Duration(seconds: 1));
    });

  });

  group('寵物 notes 的「Add to my plan」', () {
    PetNotes notes() => PetNotes.fromJson({
          'date': '2026-11-20',
          'status': 'ok',
          'source': 'llm',
          'summary': 'A summary.',
          'version': 'v1',
          'tips': [
            {'id': 'T3', 'kind': 'tip', 'text': 'Woof, coffee.', 'original': 'orig'},
            {'id': 'T9', 'kind': 'note', 'text': 'Rest.', 'original': 'orig'},
          ],
        }, date: '2026-11-20')!;

    testWidgets('對得上的建議有按鈕；按了加的是清單那句、不是 AI 改寫的', (tester) async {
      final plan = PlanStore(InMemoryKeyValueStore());
      await plan.load();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PetNotesView(notes: notes(), plan: plan))));
      await tester.pump();
      expect(find.byKey(const Key('pet-notes-add-alcohol')), findsNothing);
      expect(find.byKey(const Key('pet-notes-add-late_caffeine')), findsOneWidget);
      await tester.tap(find.byKey(const Key('pet-notes-add-late_caffeine')));
      await tester.pump();
      expect(plan.items.single.text, suggestionById('late_caffeine')!.text);
      expect(find.byKey(const Key('pet-notes-in-plan')), findsOneWidget);
    });

    testWidgets('沒有計畫（測試、舊畫面）→ 不出現按鈕', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PetNotesView(notes: notes()))));
      await tester.pump();
      expect(find.textContaining('Add to my plan'), findsNothing);
    });
  });
}
