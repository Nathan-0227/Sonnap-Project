// 第一次登入的流程（2026-11-22 grill Q9–Q14）。守的事：
// 【1】走完：歡迎 → 暱稱 → 寵物 → 作息 → 想改善什麼 → 權限 → 完成，最後才一次交出結果（Q12）
// 【2】暱稱空白／太長擋在本地，不往下走、不送出
// 【3】每一頁都能跳過；跳過暱稱＝不建帳號（name 是 null），跳過作息＝原本的值
// 【4】⚠️ 建不了帳號不能擋住 App：送不出去時完成頁照實說，Let's go 照樣能按
// 【5】不得宣稱安全或加密（暱稱制免註冊，user_id 本身就是憑證）
// 【6】手機使用權限：從系統設定回來（resumed）自動重查、打勾；通知只寫 Asked（拿不到使用者按了什麼）
// 【7】Journey 進行中：作息那一頁轉不動、照實說
// 【8】App 層：新使用者看到這個流程；**走完按 Let's go 才建帳號並進首頁**；已經有帳號的人不會看到；
//      Replay welcome 不建帳號、改名走 rename
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/main.dart';
import 'package:app/screens/welcome_flow.dart';
import 'package:app/services/account_service.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/pet_choice.dart';
import 'package:app/services/plan_goals.dart';
import 'package:app/services/sleep_plan.dart';
import 'package:app/widgets/sleep_dial.dart';

class FakePermissions implements WelcomePermissions {
  bool usage = false;
  bool grantOnOpen = true;
  int opened = 0;
  int notified = 0;

  @override
  Future<bool> hasUsageAccess() async => usage;

  @override
  Future<void> openUsageSettings() async {
    opened++;
    if (grantOnOpen) usage = true;
  }

  @override
  Future<void> requestNotifications() async => notified++;
}

const bed = TimeOfDay(hour: 1, minute: 30);
const wake = TimeOfDay(hour: 9, minute: 30);

Future<({List<WelcomeResult> results, List<int> done, FakePermissions perms, KeyValueStore store})> pumpFlow(
  WidgetTester tester, {
  String? problem,
  bool locked = false,
}) async {
  tester.view.physicalSize = const Size(400, 860);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  PetChoice.current.value = PetSpecies.dog;
  final results = <WelcomeResult>[];
  final done = <int>[];
  final perms = FakePermissions();
  final store = InMemoryKeyValueStore();
  await tester.pumpWidget(MaterialApp(
    home: WelcomeFlow(
      initialBedtime: bed,
      initialWake: wake,
      scheduleLocked: locked,
      store: store,
      permissions: perms,
      onFinish: (r) async {
        results.add(r);
        return problem;
      },
      onDone: () => done.add(1),
    ),
  ));
  await tester.pump();
  return (results: results, done: done, perms: perms, store: store);
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  // 換頁有淡入淡出：等它跑完，舊的那一頁拿掉了才找下一顆
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('【1】走完：最後才交出結果，Let\'s go 進 App', (tester) async {
    final f = await pumpFlow(tester);
    await tapKey(tester, 'welcome-start');
    await tester.enterText(find.byKey(const Key('welcome-name')), '  Nathan ');
    await tapKey(tester, 'welcome-next');
    expect(f.results, isEmpty, reason: '暱稱那一步不送出（Q12：最後才一次送）');
    await tapKey(tester, 'welcome-pet-cat');
    expect(PetChoice.current.value, PetSpecies.cat);
    expect(await f.store.getString(PetChoice.storeKey), 'cat', reason: '跟設定頁存在同一個地方');
    await tapKey(tester, 'welcome-next');
    expect(find.byType(SleepDial), findsOneWidget);
    expect(find.text('01:30'), findsOneWidget);
    expect(find.text('09:30'), findsOneWidget);
    await tapKey(tester, 'welcome-next');
    // 想改善什麼：選兩個 → 推薦頁取消一條 → Add 2 habits
    await tapKey(tester, 'goal-earlier');
    await tapKey(tester, 'goal-sound');
    await tapKey(tester, 'goal-next');
    expect(find.text('Add 3 habits'), findsOneWidget);
    await tapKey(tester, 'goal-rec-temperature');
    await tapKey(tester, 'goal-add');
    await tapKey(tester, 'welcome-next'); // 權限頁：Continue
    expect(f.results, hasLength(1));
    expect(f.results.single.goals, ['earlier', 'sound']);
    expect(f.results.single.habits, ['morning_light', 'dim_screen'], reason: '交錯取、取消的那條不加');
    expect(f.results.single.name, 'Nathan');
    expect(f.results.single.bedtime, bed);
    expect(f.results.single.wake, wake);
    expect(find.textContaining("okay if you forget"), findsOneWidget);
    expect(f.done, isEmpty);
    await tapKey(tester, 'welcome-done');
    expect(f.done, [1]);
  });

  testWidgets('【1】返回鍵回上一頁', (tester) async {
    await pumpFlow(tester);
    await tapKey(tester, 'welcome-start');
    expect(find.byKey(const Key('welcome-name')), findsOneWidget);
    await tapKey(tester, 'welcome-back');
    expect(find.byKey(const Key('welcome-start')), findsOneWidget);
  });

  testWidgets('【2】暱稱空白、太長都擋在本地', (tester) async {
    final f = await pumpFlow(tester);
    await tapKey(tester, 'welcome-start');
    await tapKey(tester, 'welcome-next');
    expect(find.textContaining('Pick any name'), findsOneWidget);
    expect(find.byKey(const Key('welcome-name')), findsOneWidget, reason: '還停在暱稱');
    expect(nicknameProblem('x' * 41), 'Keep it under 40 characters.');
    expect(nicknameProblem('   '), 'Pick any name you like.');
    expect(nicknameProblem('Mia'), isNull);
    expect(f.results, isEmpty);
  });

  testWidgets('【3】每一頁都能跳過：不建帳號、作息用原本的值', (tester) async {
    final f = await pumpFlow(tester);
    await tapKey(tester, 'welcome-start');
    await tester.enterText(find.byKey(const Key('welcome-name')), 'Nathan');
    for (var i = 0; i < 5; i++) {
      await tapKey(tester, 'welcome-skip'); // 暱稱、寵物、作息、想改善什麼、權限
    }
    expect(f.results.single.name, isNull, reason: '跳過暱稱＝不建帳號，打了字也一樣');
    expect(f.results.single.goals, isEmpty);
    expect(f.results.single.habits, isEmpty);
    expect(f.results.single.bedtime, bed);
    expect(f.results.single.wake, wake);
    expect(PetChoice.current.value, PetSpecies.dog);
    expect(f.perms.opened + f.perms.notified, 0, reason: '跳過權限頁一個都不問');
  });

  testWidgets('【4】送不出去：完成頁照實說，Let\'s go 照樣能按', (tester) async {
    final f = await pumpFlow(tester, problem: 'COULD-NOT-REACH');
    await tapKey(tester, 'welcome-start');
    await tester.enterText(find.byKey(const Key('welcome-name')), 'Nathan');
    await tapKey(tester, 'welcome-next');
    await tapKey(tester, 'welcome-next'); // 寵物
    await tapKey(tester, 'welcome-next'); // 作息
    await tapKey(tester, 'goal-skip'); // 想改善什麼：Not sure — skip
    await tapKey(tester, 'welcome-next'); // 權限
    expect(find.text('COULD-NOT-REACH'), findsOneWidget);
    await tapKey(tester, 'welcome-done');
    expect(f.done, [1]);
  });

  testWidgets('【5】每一頁都不得宣稱安全或加密；暱稱頁寫 No email, no password', (tester) async {
    await pumpFlow(tester);
    void noClaims(String page) {
      for (final word in ['secure', 'Secure', 'encrypted', 'private and', 'safe']) {
        expect(find.textContaining(word), findsNothing, reason: '$page: $word');
      }
    }

    noClaims('welcome');
    await tapKey(tester, 'welcome-start');
    expect(find.textContaining('No email, no password'), findsOneWidget);
    noClaims('name');
    for (final page in ['pet', 'schedule', 'goals', 'permissions', 'done']) {
      await tapKey(tester, 'welcome-skip');
      noClaims(page);
      if (page == 'permissions') {
        // 權限說明照實寫：只有時間與手機型號送出去、App 名字留在手機上
        expect(find.textContaining('Only times and your phone model are sent'), findsOneWidget);
        expect(find.textContaining('that list stays on your phone'), findsOneWidget);
      }
      if (page == 'done') break;
    }
  });

  testWidgets('【6】手機使用權限：回到 App 自動打勾；通知只寫 Asked', (tester) async {
    final f = await pumpFlow(tester);
    await tapKey(tester, 'welcome-start');
    for (var i = 0; i < 4; i++) {
      await tapKey(tester, 'welcome-skip');
    }
    expect(find.byKey(const Key('welcome-usage-action')), findsOneWidget);
    await tapKey(tester, 'welcome-usage-action');
    expect(f.perms.opened, 1);
    expect(find.byKey(const Key('welcome-usage-done')), findsNothing, reason: '還沒回到 App');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('welcome-usage-done')), findsOneWidget);

    await tapKey(tester, 'welcome-notify-action');
    expect(f.perms.notified, 1);
    expect(find.descendant(of: find.byKey(const Key('welcome-notify-done')), matching: find.text('Asked')),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('welcome-notify')), matching: find.text('On')), findsNothing,
        reason: '系統視窗按了什麼拿不到，不能寫成已開啟');
  });

  testWidgets('【7】Journey 進行中：作息轉不動、照實說', (tester) async {
    await pumpFlow(tester, locked: true);
    await tapKey(tester, 'welcome-start');
    await tapKey(tester, 'welcome-skip');
    await tapKey(tester, 'welcome-skip');
    expect(find.textContaining('Your Journey is setting your schedule'), findsOneWidget);
    expect(
      find.ancestor(of: find.byType(SleepDial), matching: find.byWidgetPredicate((w) => w is IgnorePointer && w.ignoring)),
      findsOneWidget,
    );
  });

  group('【8】App 層', () {
    testWidgets('新使用者：先看到流程；走完按 Let\'s go 才建帳號並進首頁', (tester) async {
      tester.view.physicalSize = const Size(400, 860);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final accounts = _Accounts(AccountState.needsOnboarding);
      await tester.pumpWidget(SonnapApp(
        store: _kv,
        accounts: accounts,
        welcomePermissions: FakePermissions(),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.byType(WelcomeFlow), findsOneWidget);
      await tapKey(tester, 'welcome-start');
      await tester.enterText(find.byKey(const Key('welcome-name')), 'Nathan');
      await tapKey(tester, 'welcome-next');
      await tapKey(tester, 'welcome-next'); // 寵物
      await tapKey(tester, 'welcome-next'); // 作息
      await tapKey(tester, 'goal-rested');
      await tapKey(tester, 'goal-next');
      await tapKey(tester, 'goal-add'); // 3 條全加
      await tapKey(tester, 'welcome-next'); // 權限
      await tester.pump();
      expect(accounts.created, ['Nathan']);
      expect(PlanStore.shared?.items.map((i) => i.id).toList(), ['late_caffeine', 'alcohol', 'dim_screen'],
          reason: '勾著的加進計畫，照推薦的順序');
      expect(PlanStore.shared?.items.every((i) => !i.notify), isTrue, reason: '提醒預設關');
      expect(await PlanGoalsStore(_kv).goals(), ['rested']);
      expect(find.byType(WelcomeFlow), findsOneWidget, reason: '建好了也先停在完成頁');
      // 首頁有一直在動的動畫（星星、流星），pumpAndSettle 等不完 → 點了只往前推幾格
      await tester.tap(find.byKey(const Key('welcome-done')));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(WelcomeFlow), findsNothing);
      expect(find.byKey(const Key('nav-home')), findsOneWidget);
    });

    testWidgets('已經有帳號：不會看到流程', (tester) async {
      await tester.pumpWidget(SonnapApp(
        store: InMemoryKeyValueStore(),
        accounts: _Accounts(AccountState.stored),
        welcomePermissions: FakePermissions(),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.byType(WelcomeFlow), findsNothing);
    });
  });
}

final _kv = InMemoryKeyValueStore();

class _Accounts implements AccountService {
  final AccountState state;
  final List<String> created = [];
  _Accounts(this.state);

  @override
  Future<AccountStatus> resolve() async => state == AccountState.needsOnboarding
      ? const AccountStatus(AccountState.needsOnboarding)
      : AccountStatus(state, userId: 'u1', displayName: 'Nathan');

  @override
  Future<AccountStatus?> createAccount({required String displayName, required String targetBedtime}) async {
    created.add(displayName);
    return AccountStatus(AccountState.stored, userId: 'u1', displayName: displayName);
  }

  @override
  Future<bool> updateTargetBedtime({required String userId, required String targetBedtime}) async => true;
  @override
  Future<bool> updateTargetWake({required String userId, required String targetWake}) async => true;
  @override
  Future<AccountStatus> refreshBuildTimeName(AccountStatus status) async => status;
  @override
  Future<AccountStatus?> rename(AccountStatus status, String displayName) async => null;
  @override
  String? get buildTimeUserIdOverride => null;
  @override
  String get baseUrl => 'stub';
  @override
  KeyValueStore get store => InMemoryKeyValueStore();
  @override
  Duration get timeout => const Duration(seconds: 1);
}
