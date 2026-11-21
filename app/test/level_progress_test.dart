import 'package:app/screens/plan_screen.dart';
import 'package:app/screens/rewards_screen.dart';
import 'package:app/services/alarm.dart';
import 'package:app/services/game_service.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/plan_reminders.dart';
import 'package:app/services/sleep_plan.dart';
import 'package:app/services/user_identity.dart';
import 'package:app/widgets/level_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 寵物頭上的等級條（2026-11-21，首頁與睡眠計畫頁共用）。
/// 守的是壞掉時不會報錯的地方：
/// - 條填多少、還差幾 XP **照抄後端**（Dart 自己從 xpTotal 算的話，換升級曲線時會悄悄對不上）
/// - 最高級寫 Max level，不寫「0 XP to Lv 11」
/// - 計畫頁也要有、在寵物頭上、點了開獎勵頁

GameState _state({int level = 6, int? xpForNext = 185, double progress = 0.4, bool max = false}) =>
    GameState.fromJson({
      'level': level,
      // 故意跟 progress／xp_for_next 對不起來：Dart 只能照抄那兩個欄位
      'xp_total': 99999,
      'xp_into_level': 1,
      'xp_for_next': xpForNext,
      'progress': progress,
      'max_level': max,
      'growth_stage': 'young',
      'xp_sources': {'behaviour': 0, 'sleep_quality': 0, 'challenge_rewards': 0},
      'claimable': const [],
      'badges': const [],
      'notes': const {},
    });

class _StubGame implements GameService {
  final GameState state;
  _StubGame(this.state);
  @override
  Future<GameResult<GameState>> fetchGame() async => GameResult(GameStatus.ok, value: state);
  @override
  Future<GameResult<ClosetState>> fetchCloset() async => const GameResult(GameStatus.failed);
  @override
  Future<GameResult<ClaimOutcome>> claim(String challengeId) async => const GameResult(GameStatus.failed);
  @override
  Future<GameResult<String?>> equip(String? itemId) async => const GameResult(GameStatus.failed);
  @override
  String get baseUrl => 'stub';
  @override
  UserIdentity get identity => const BuildTimeUserIdentity(overrideId: 'stub');
  @override
  Duration get timeout => const Duration(seconds: 1);
}

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

Future<void> _pumpBar(WidgetTester tester, GameState s) => tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: LevelProgress(game: s))),
    ));

void main() {
  group('等級條本身', () {
    testWidgets('寫還差幾 XP、到下一級（照抄 xp_for_next）', (tester) async {
      await _pumpBar(tester, _state());
      expect(find.text('Lv 6'), findsOneWidget);
      expect(find.text('185 XP to Lv 7'), findsOneWidget);
    });

    testWidgets('條填多少照抄 progress，不從 xp_total 自己算', (tester) async {
      await _pumpBar(tester, _state(progress: 0.4));
      final fill = tester.getSize(find.byKey(const Key('level-bar-fill'))).width;
      expect(fill, closeTo(LevelProgress.barWidth * 0.4, 0.5));
    });

    testWidgets('⚠️ 最高級：條滿、寫 Max level，不寫「0 XP to」', (tester) async {
      await _pumpBar(tester, _state(level: 10, xpForNext: null, progress: 0.2, max: true));
      expect(find.text('Max level'), findsOneWidget);
      expect(find.textContaining('XP to'), findsNothing);
      final fill = tester.getSize(find.byKey(const Key('level-bar-fill'))).width;
      expect(fill, closeTo(LevelProgress.barWidth, 0.5));
    });
  });

  group('睡眠計畫頁', () {
    Future<void> pumpPlan(WidgetTester tester, {GameService? game}) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      final kv = InMemoryKeyValueStore();
      final plan = PlanStore(kv);
      await plan.load();
      await tester.pumpWidget(MaterialApp(
        home: PlanScreen(
          plan: plan,
          bedtime: const TimeOfDay(hour: 0, minute: 30),
          alarmSettings: AlarmSettingsStore(kv),
          alarmScheduler: _FakeAlarm(),
          reminders: _NoReminders(),
          game: game,
          clock: () => DateTime(2026, 11, 21, 12),
        ),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('寵物頭上有等級條，不跟標題列疊在一起', (tester) async {
      await pumpPlan(tester, game: _StubGame(_state()));
      expect(find.text('185 XP to Lv 7'), findsOneWidget);
      final bar = tester.getRect(find.byKey(const Key('level-progress')));
      final pet = tester.getRect(find.byKey(const Key('plan-pet-body')));
      expect(bar.bottom, lessThanOrEqualTo(pet.top + pet.height * 0.25),
          reason: '在寵物頭上（寵物圖上緣有一點留白）');
      expect(bar.center.dx, closeTo(pet.center.dx, 2));
      final back = find.byTooltip('Back');
      if (back.evaluate().isNotEmpty) {
        expect(bar.overlaps(tester.getRect(back.first)), isFalse);
      }
    });

    testWidgets('點等級條 → 開獎勵頁', (tester) async {
      await pumpPlan(tester, game: _StubGame(_state()));
      await tester.tap(find.byKey(const Key('level-progress')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(RewardsScreen), findsOneWidget);
    });

    testWidgets('沒有後端 → 不畫等級條', (tester) async {
      await pumpPlan(tester);
      expect(find.byKey(const Key('level-progress')), findsNothing);
    });
  });
}
