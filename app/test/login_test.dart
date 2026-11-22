// email＋密碼登入（2026-11-22 grill：A' 不寄信、後台重設）。守：
// 【1】設定頁：沒設＝Set up login 一列；拿不到登入狀態整組不畫（不放按了才說連不上的）
// 【2】設定登入：兩次不一樣、太短擋在本地（不送）；後端的話照抄；成功換成 Email／Change password／Log out
// 【3】改密碼：本地擋；後端的話照抄；成功關掉
// 【4】登出：建置參數那支照實寫原因、點了沒反應；能登出的要先確認
// 【5】第一次登入流程：暱稱後多一步、可跳過；跳過暱稱就沒有這一步；Replay 沒有；不宣稱安全
// 【6】App：I already have an account → 登入 → 進首頁；**採用後端的目標就寢**並記成已同步（不被新手機的預設值蓋掉）
// 【7】AccountStorage：存成手機的帳號；登出清掉帳號與助理對話，習慣留著
import 'package:app/main.dart';
import 'package:app/screens/log_in_screen.dart';
import 'package:app/screens/settings_screen.dart';
import 'package:app/screens/welcome_flow.dart';
import 'package:app/services/account_service.dart';
import 'package:app/services/chat_thread.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/login_service.dart';
import 'package:app/services/pet_choice.dart';
import 'package:app/services/user_settings.dart';
import 'package:app/widgets/settings_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settle(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> pumpSettings(WidgetTester tester, SettingsScreen screen) async {
  tester.view.physicalSize = const Size(1080, 3600);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(key: UniqueKey(), home: Scaffold(body: screen)));
  await settle(tester);
}

Future<void> tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)).last);
  await tester.tap(find.byKey(Key(key)).last);
  await settle(tester);
}

Future<void> type(WidgetTester tester, String key, String text) =>
    tester.enterText(find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField)), text);

void main() {
  group('【1】設定頁的 Account', () {
    testWidgets('沒設：一列 Set up login', (tester) async {
      await pumpSettings(tester, SettingsScreen(
        store: InMemoryKeyValueStore(),
        loadLogin: () async => const LoginInfo(hasLogin: false),
        onSetUpLogin: (_, _) async => null,
      ));
      expect(find.byKey(const Key('settings-setup-login')), findsOneWidget);
      expect(find.byKey(const Key('settings-log-out')), findsNothing, reason: '沒設登入不能登出');
    });

    testWidgets('拿不到登入狀態（連不到、舊版後端）：整組不畫', (tester) async {
      await pumpSettings(tester, SettingsScreen(
        store: InMemoryKeyValueStore(),
        loadLogin: () async => null,
      ));
      expect(find.text('ACCOUNT'), findsNothing);
      expect(find.byKey(const Key('settings-setup-login')), findsNothing);
    });
  });

  testWidgets('【2】設定登入：本地擋、後端照抄、成功換成三列', (tester) async {
    final sent = <(String, String)>[];
    String? answer = 'That email is already used by another account.';
    await pumpSettings(tester, SettingsScreen(
      store: InMemoryKeyValueStore(),
      loadLogin: () async => const LoginInfo(hasLogin: false),
      onSetUpLogin: (e, p) async {
        sent.add((e, p));
        return answer;
      },
      onLogOut: () async {},
    ));
    await tap(tester, 'settings-setup-login');
    final sheet = tester.widget<Container>(find.byKey(const Key('setup-login-sheet')));
    expect((sheet.decoration as BoxDecoration).color, kSettingsSheetColor, reason: '面板要自己畫底色');

    await type(tester, 'login-email', 'Me@Example.com');
    await type(tester, 'login-password', 'moonlight42');
    await type(tester, 'login-password-again', 'moonlight43');
    await tap(tester, 'login-save');
    expect(find.text("The two passwords don't match."), findsOneWidget);
    await type(tester, 'login-password', 'short');
    await type(tester, 'login-password-again', 'short');
    await tap(tester, 'login-save');
    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    expect(sent, isEmpty, reason: '明顯不用問伺服器的不送');

    await type(tester, 'login-password', 'moonlight42');
    await type(tester, 'login-password-again', 'moonlight42');
    await tap(tester, 'login-save');
    expect(sent, [('Me@Example.com', 'moonlight42')]);
    expect(find.text('That email is already used by another account.'), findsOneWidget, reason: '後端的話照抄');

    answer = null;
    await tap(tester, 'login-save');
    expect(find.byKey(const Key('setup-login-sheet')), findsNothing, reason: '成功就關掉');
    expect(find.byKey(const Key('settings-setup-login')), findsNothing);
    expect(find.text('me@example.com'), findsOneWidget);
    expect(find.byKey(const Key('settings-change-password')), findsOneWidget);
    expect(find.byKey(const Key('settings-log-out')), findsOneWidget);
  });

  testWidgets('【3】改密碼：本地擋、後端照抄、成功關掉', (tester) async {
    final sent = <(String, String)>[];
    String? answer = 'Current password is wrong.';
    await pumpSettings(tester, SettingsScreen(
      store: InMemoryKeyValueStore(),
      loadLogin: () async => const LoginInfo(hasLogin: true, email: 'me@example.com'),
      onChangePassword: (o, n) async {
        sent.add((o, n));
        return answer;
      },
    ));
    await tap(tester, 'settings-change-password');
    await tap(tester, 'password-save');
    expect(find.text('Enter your current password.'), findsOneWidget);
    await type(tester, 'password-old', 'old-password');
    await type(tester, 'password-new', 'new-password-1');
    await type(tester, 'password-new-again', 'new-password-2');
    await tap(tester, 'password-save');
    expect(sent, isEmpty);
    await type(tester, 'password-new-again', 'new-password-1');
    await tap(tester, 'password-save');
    expect(sent, [('old-password', 'new-password-1')]);
    expect(find.text('Current password is wrong.'), findsOneWidget);
    expect(find.textContaining('Ask the Sonnap team to reset it'), findsOneWidget, reason: '沒有忘記密碼，照實說找誰');
    answer = null;
    await tap(tester, 'password-save');
    expect(find.byKey(const Key('change-password-sheet')), findsNothing);
  });

  group('【4】登出', () {
    testWidgets('建置參數那支：照實寫原因，點了沒反應', (tester) async {
      await pumpSettings(tester, SettingsScreen(
        store: InMemoryKeyValueStore(),
        loadLogin: () async => const LoginInfo(hasLogin: true, email: 'me@example.com'),
        logOutBlockedReason: 'BLOCKED-REASON',
      ));
      expect(find.text('BLOCKED-REASON'), findsOneWidget);
      await tap(tester, 'settings-log-out');
      expect(find.byKey(const Key('log-out-dialog')), findsNothing);
    });

    testWidgets('能登出：先確認，Cancel 不登出、Log out 才登出', (tester) async {
      var out = 0;
      await pumpSettings(tester, SettingsScreen(
        store: InMemoryKeyValueStore(),
        loadLogin: () async => const LoginInfo(hasLogin: true, email: 'me@example.com'),
        onLogOut: () async => out++,
      ));
      await tap(tester, 'settings-log-out');
      expect(find.textContaining('Log in with me@example.com'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(out, 0);
      await tap(tester, 'settings-log-out');
      await tap(tester, 'log-out-confirm');
      expect(out, 1);
    });
  });

  group('【5】第一次登入流程的設登入', () {
    Future<List<WelcomeResult>> flow(WidgetTester tester, {bool offer = true, bool replay = false}) async {
      tester.view.physicalSize = const Size(400, 860);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      PetChoice.current.value = PetSpecies.dog;
      final results = <WelcomeResult>[];
      await tester.pumpWidget(MaterialApp(
        key: UniqueKey(), // 同一條測試裡 pump 第二次時要是新的流程
        home: WelcomeFlow(
          initialBedtime: const TimeOfDay(hour: 1, minute: 30),
          initialWake: const TimeOfDay(hour: 9, minute: 30),
          store: InMemoryKeyValueStore(),
          permissions: _Perms(),
          offerLogin: offer,
          replay: replay,
          initialName: replay ? 'Nathan' : null,
          onHaveAccount: replay ? null : () {},
          onFinish: (r) async {
            results.add(r);
            return null;
          },
          onDone: () {},
        ),
      ));
      await tester.pump();
      return results;
    }

    Future<void> go(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    testWidgets('填了：結果帶 email 與密碼；本地先擋兩次不一樣', (tester) async {
      final results = await flow(tester);
      expect(find.byKey(const Key('welcome-have-account')), findsOneWidget);
      await go(tester, 'welcome-start');
      await tester.enterText(find.byKey(const Key('welcome-name')), 'Nathan');
      await go(tester, 'welcome-next');
      expect(find.text('Want to log in on another phone?'), findsOneWidget);
      for (final w in ['secure', 'Secure', 'encrypted', 'safe']) {
        expect(find.textContaining(w), findsNothing, reason: w);
      }
      await type(tester, 'welcome-login-email', 'me@example.com');
      await type(tester, 'welcome-login-password', 'moonlight42');
      await type(tester, 'welcome-login-password-again', 'nope');
      await go(tester, 'welcome-next');
      expect(find.text("The two passwords don't match."), findsOneWidget);
      await type(tester, 'welcome-login-password-again', 'moonlight42');
      await go(tester, 'welcome-next'); // → 寵物
      for (var i = 0; i < 4; i++) {
        await go(tester, 'welcome-skip'); // 寵物、作息、想改善什麼、權限
      }
      expect(results.single.email, 'me@example.com');
      expect(results.single.password, 'moonlight42');
    });

    testWidgets('跳過這一步：沒有 email；跳過暱稱：根本沒有這一步、返回也跳過它', (tester) async {
      var results = await flow(tester);
      await go(tester, 'welcome-start');
      await tester.enterText(find.byKey(const Key('welcome-name')), 'Nathan');
      await go(tester, 'welcome-next');
      await type(tester, 'welcome-login-email', 'me@example.com');
      for (var i = 0; i < 5; i++) {
        await go(tester, 'welcome-skip'); // 登入、寵物、作息、想改善什麼、權限
      }
      expect(results.single.name, 'Nathan');
      expect(results.single.email, isNull, reason: '跳過就不送，打了字也一樣');

      results = await flow(tester);
      await go(tester, 'welcome-start');
      await go(tester, 'welcome-skip'); // 暱稱
      expect(find.text('Pick your buddy'), findsOneWidget, reason: '沒有帳號就沒有登入可以設');
      await go(tester, 'welcome-back');
      expect(find.byKey(const Key('welcome-name')), findsOneWidget);
    });

    testWidgets('Replay 與沒有後端：沒有這一步、也沒有 I already have an account', (tester) async {
      await flow(tester, replay: true);
      expect(find.byKey(const Key('welcome-have-account')), findsNothing);
      await go(tester, 'welcome-start');
      await go(tester, 'welcome-next');
      expect(find.text('Pick your buddy'), findsOneWidget);

      await flow(tester, offer: false);
      await go(tester, 'welcome-start');
      expect(find.textContaining('No email, no password'), findsOneWidget);
    });
  });

  testWidgets('【6】App：I already have an account → 進首頁，採用後端的目標就寢', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final store = InMemoryKeyValueStore();
    final api = _FakeLogin();
    await tester.pumpWidget(SonnapApp(
      store: store,
      accounts: _Accounts(),
      loginApi: api,
      welcomePermissions: _Perms(),
    ));
    await settle(tester);
    await tap(tester, 'welcome-have-account');
    expect(find.byType(LogInScreen), findsOneWidget);
    await type(tester, 'login-email', 'me@example.com');
    await type(tester, 'login-password', 'wrong-one');
    await tap(tester, 'login-submit');
    expect(find.text('Email or password is wrong.'), findsOneWidget, reason: '後端的話照抄');
    await type(tester, 'login-password', 'moonlight42');
    await tap(tester, 'login-submit');
    expect(find.byType(LogInScreen), findsNothing);
    expect(find.byType(WelcomeFlow), findsNothing);
    expect(find.byKey(const Key('nav-home')), findsOneWidget);
    expect(await store.getString(AccountService.userIdKey), 'u-original', reason: '拿回原本的 id');
    final s = await UserSettingsStore(store).load();
    expect(s.targetBedtime, '02:15', reason: '採用後端的目標');
    expect(s.needsSync, isFalse, reason: '記成已同步：不會把新手機的預設值 PATCH 回去');
    expect(await UserSettingsStore(store).syncedWake(), '10:00');
  });

  test('【7】AccountStorage：存帳號；登出清掉帳號與對話、習慣留著', () async {
    final store = InMemoryKeyValueStore();
    final s = await AccountStorage(InMemoryKeyValueStore()).adopt(
        const LoggedIn(userId: 'u1', displayName: 'Mia'));
    expect((s.state, s.userId, s.displayName), (AccountState.stored, 'u1', 'Mia'));
    await AccountStorage(store).adopt(const LoggedIn(userId: 'u1', displayName: 'Mia'));
    await store.setString(ChatThreadStore.key, '[]');
    await store.setString('sleep_plan_v1', 'HABITS');
    await AccountStorage(store).forget();
    expect(await store.getString(AccountService.userIdKey), isNull);
    expect(await store.getString(AccountService.displayNameKey), isNull);
    expect(await store.getString(ChatThreadStore.key), isNull);
    expect(await store.getString('sleep_plan_v1'), 'HABITS');
    expect(newPasswordProblem('1234567', '1234567'), 'Use at least 8 characters.');
    expect(newPasswordProblem('12345678', '12345678'), isNull);
  });
}

class _Perms implements WelcomePermissions {
  @override
  Future<bool> hasUsageAccess() async => false;
  @override
  Future<void> openUsageSettings() async {}
  @override
  Future<void> requestNotifications() async {}
}

class _FakeLogin implements LoginApi {
  @override
  Future<LoginInfo?> fetch(String userId) async => const LoginInfo(hasLogin: true, email: 'me@example.com');
  @override
  Future<LoginOutcome<LoginInfo>> setUp(String userId, String email, String password) async =>
      LoginOutcome.ok(LoginInfo(hasLogin: true, email: email));
  @override
  Future<LoginOutcome<LoggedIn>> logIn(String email, String password) async => password == 'moonlight42'
      ? const LoginOutcome.ok(LoggedIn(
          userId: 'u-original', displayName: 'Nathan', targetBedtime: '02:15', targetWake: '10:00'))
      : const LoginOutcome.fail('Email or password is wrong.');
  @override
  Future<LoginOutcome<LoginInfo>> changePassword(String userId, String o, String n) async =>
      const LoginOutcome.ok(LoginInfo(hasLogin: true, email: 'me@example.com'));
}

class _Accounts implements AccountService {
  @override
  Future<AccountStatus> resolve() async => const AccountStatus(AccountState.needsOnboarding);
  @override
  Future<AccountStatus?> createAccount({required String displayName, required String targetBedtime}) async => null;
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
