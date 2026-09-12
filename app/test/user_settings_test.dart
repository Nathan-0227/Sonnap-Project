// 目標就寢時間：存得住，而且會告訴後端。
//
// ═══════════════════════════════════════════════════════════════════
// 這一組守的是一個「壞掉不會報錯」的漂移
// ═══════════════════════════════════════════════════════════════════
//
// 這個設定有兩份：
//
//   這台手機（sonnap/store）  → 首頁的倒數、Settings 頁顯示的值
//   後端 users.target_bedtime → **POST /nightly 算達成度用的就是這一份**
//
// 修正前 App 端只存在記憶體裡，改完就寢時間完全不會告訴後端。症狀是
// 使用者在 Settings 把目標改成 01:00、首頁倒數跟著變，隔天早上卻收到
// 「比目標晚了 90 分鐘」——因為後端還在拿註冊當天填的 23:30 在算，
// 而畫面上沒有任何地方看得出這兩個數字講的不是同一個目標。
//
// ⚠️ 加上持久化之後這件事會變得**更糟**：漂移從「重開就消失」變成
//    「永久存在」。所以存本機與 PATCH 後端一定要一起做。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/main.dart';
import 'package:app/screens/home_screen.dart';
import 'package:app/screens/settings_screen.dart';
import 'package:app/services/account_service.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/user_settings.dart';

/// 記下每一次 PATCH 的假帳號服務。
class _FakeAccounts implements AccountService {
  final String? userId;

  /// PATCH 要不要成功。false 用來測「連不上時本機仍然存下來，下次補送」。
  bool patchSucceeds;

  final List<String> patched = [];

  _FakeAccounts({this.userId = 'user-1', this.patchSucceeds = true});

  @override
  Future<AccountStatus> resolve() async => userId == null
      ? const AccountStatus(AccountState.noBackend)
      : AccountStatus(AccountState.stored, userId: userId, displayName: 'Nathan');

  @override
  Future<AccountStatus?> createAccount({
    required String displayName,
    required String targetBedtime,
  }) async =>
      AccountStatus(AccountState.stored, userId: userId, displayName: displayName);

  @override
  Future<bool> updateTargetBedtime({
    required String userId,
    required String targetBedtime,
  }) async {
    patched.add(targetBedtime);
    return patchSucceeds;
  }

  @override
  String get baseUrl => 'stub';

  @override
  KeyValueStore get store => InMemoryKeyValueStore();

  @override
  Duration get timeout => const Duration(seconds: 1);
}

/// 永遠不回應的儲存。
///
/// 這不是假想的情況：**實測 `PlatformKeyValueStore` 在 widget test 裡
/// 的 MethodChannel 從來不會完成**（非 Android 平台、原生端沒註冊 channel
/// 時也一樣）。讀一個本機偏好設定不該有能力擋住整個 App 啟動。
class _HangingKeyValueStore implements KeyValueStore {
  @override
  Future<String?> getString(String key) => Completer<String?>().future;

  @override
  Future<void> setString(String key, String value) =>
      Completer<void>().future;

  @override
  Future<void> remove(String key) => Completer<void>().future;
}

void main() {
  group('存起來的格式', () {
    test('"HH:MM" 以外的一律拒收', () {
      expect(isValidBedtime('23:30'), isTrue);
      expect(isValidBedtime('00:00'), isTrue);
      expect(isValidBedtime('23:59'), isTrue);
      // 後端的 parse_bedtime() 對這些回 422，而那個錯誤在 App 端只會
      // 表現成「設定沒有生效」——所以要在送出去之前就擋掉。
      expect(isValidBedtime('24:00'), isFalse);
      expect(isValidBedtime('23:60'), isFalse);
      expect(isValidBedtime('1:00'), isFalse);
      expect(isValidBedtime('abc'), isFalse);
      expect(isValidBedtime(null), isFalse);
    });

    test('formatBedtime 補零', () {
      expect(formatBedtime(1, 5), '01:05');
      expect(formatBedtime(23, 30), '23:30');
    });

    test('存壞掉的值會被拒絕，不會污染儲存', () async {
      final store = InMemoryKeyValueStore();
      final settings = UserSettingsStore(store);
      await settings.saveBedtime('25:99');
      expect((await settings.load()).targetBedtime, isNull);
    });

    test('儲存裡的值壞掉時當成沒存過', () async {
      final settings = UserSettingsStore(InMemoryKeyValueStore({
        UserSettingsStore.bedtimeKey: 'garbage',
      }));
      expect((await settings.load()).targetBedtime, isNull);
    });
  });

  group('待同步狀態', () {
    test('從來沒動過 → 不需要同步', () async {
      final settings = UserSettingsStore(InMemoryKeyValueStore());
      expect(
        (await settings.load()).needsSync,
        isFalse,
        reason: '沒動過的話，後端用註冊時填的值是對的，不必白白 PATCH 一次',
      );
    });

    test('存了但還沒同步 → 需要同步', () async {
      final settings = UserSettingsStore(InMemoryKeyValueStore());
      await settings.saveBedtime('01:00');
      expect((await settings.load()).needsSync, isTrue);
    });

    test('同步成功之後就不需要了', () async {
      final settings = UserSettingsStore(InMemoryKeyValueStore());
      await settings.saveBedtime('01:00');
      await settings.markSynced('01:00');
      expect((await settings.load()).needsSync, isFalse);
    });

    test('再改一次又需要同步', () async {
      final settings = UserSettingsStore(InMemoryKeyValueStore());
      await settings.saveBedtime('01:00');
      await settings.markSynced('01:00');
      await settings.saveBedtime('02:00');
      expect((await settings.load()).needsSync, isTrue);
    });
  });

  group('提醒開關', () {
    test('關掉之後存得住——false 不等於「沒存過」', () async {
      final store = InMemoryKeyValueStore();
      final settings = UserSettingsStore(store);
      await settings.saveReminder(false);
      expect(
        (await settings.load()).reminderOn,
        isFalse,
        reason: '把 false 當成 null 的話，呼叫端會退回預設值 true——'
            '使用者關掉的開關每次開 App 都自己打開',
      );
    });

    test('沒存過是 null，不是 false', () async {
      final settings = UserSettingsStore(InMemoryKeyValueStore());
      expect((await settings.load()).reminderOn, isNull);
    });
  });

  group('接上 App：存得住、而且會告訴後端', () {
    Finder findOf<T extends Widget>() => find.byType(T, skipOffstage: false);

    TimeOfDay homeBedtime(WidgetTester tester) =>
        tester.widget<HomeScreen>(findOf<HomeScreen>()).targetBedtime;

    SettingsScreen settingsOf(WidgetTester tester) =>
        tester.widget<SettingsScreen>(findOf<SettingsScreen>());

    /// 模擬「開一次 App」。
    ///
    /// ⚠️ **中間那一次 pumpWidget 不能省。** 直接再 pump 一個
    /// 同型別的 SonnapApp，Flutter 會沿用既有的 State，`initState` 根本
    /// 不會再跑——於是「重開 App 會補送」這種測試會**假性通過**
    /// （什麼都沒發生，而斷言剛好也期待沒發生）。第一版就是這樣：
    /// 「PATCH 成功之後不再重複送」全綠，但它證明的是 State 沒被重建。
    /// 先換成別的 widget 才會真的把 State 丟掉。
    Future<void> open(
      WidgetTester tester,
      KeyValueStore store,
      AccountService accounts,
    ) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(SonnapApp(store: store, accounts: accounts));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
    }

    testWidgets('存過的目標，重開 App 要沿用而不是回到預設值', (tester) async {
      final store = InMemoryKeyValueStore();
      await UserSettingsStore(store).saveBedtime('01:00');
      await UserSettingsStore(store).markSynced('01:00');

      await open(tester, store, _FakeAccounts());

      expect(
        homeBedtime(tester),
        const TimeOfDay(hour: 1, minute: 0),
        reason: '存了卻沒讀回來，使用者每次開 App 都要重設一次',
      );
    });

    testWidgets('改了目標會存下來', (tester) async {
      final store = InMemoryKeyValueStore();
      await open(tester, store, _FakeAccounts());

      settingsOf(tester).onBedtimeChanged!(const TimeOfDay(hour: 2, minute: 15));
      await tester.pump();

      expect((await UserSettingsStore(store).load()).targetBedtime, '02:15');
    });

    testWidgets('改了目標會 PATCH 後端——不然達成度會拿舊目標算', (tester) async {
      final store = InMemoryKeyValueStore();
      final accounts = _FakeAccounts();
      await open(tester, store, accounts);

      settingsOf(tester).onBedtimeChanged!(const TimeOfDay(hour: 1, minute: 0));
      await tester.pump();

      expect(
        accounts.patched,
        ['01:00'],
        reason: '少了這一步，首頁倒數到 01:00 而後端還在拿 23:30 算達成度，'
            '而畫面上完全看不出來',
      );
    });

    testWidgets('PATCH 成功之後不再重複送', (tester) async {
      final store = InMemoryKeyValueStore();
      final accounts = _FakeAccounts();
      await open(tester, store, accounts);

      settingsOf(tester).onBedtimeChanged!(const TimeOfDay(hour: 1, minute: 0));
      await tester.pump();
      expect(accounts.patched, hasLength(1));

      // 再開一次 App。
      await open(tester, store, accounts);
      expect(
        accounts.patched,
        hasLength(1),
        reason: '後端的 update_user 沒有節流，每次開 App 都 PATCH 一次是白費',
      );
    });

    testWidgets('PATCH 失敗 → 本機照樣存，下次開 App 補送', (tester) async {
      final store = InMemoryKeyValueStore();
      final offline = _FakeAccounts(patchSucceeds: false);
      await open(tester, store, offline);

      settingsOf(tester).onBedtimeChanged!(const TimeOfDay(hour: 1, minute: 0));
      await tester.pump();

      expect(offline.patched, ['01:00']);
      expect(
        (await UserSettingsStore(store).load()).needsSync,
        isTrue,
        reason: '沒連上就不能記成已同步，否則那次修改永遠不會到後端',
      );

      // 回到有網路的環境，重開 App。
      final online = _FakeAccounts();
      await open(tester, store, online);
      expect(online.patched, ['01:00']);
      expect((await UserSettingsStore(store).load()).needsSync, isFalse);
    });

    testWidgets('補送的是使用者存的值，不是預設值', (tester) async {
      // 補送讀的是**儲存**而不是記憶體裡的 targetBedtime，所以拿到的
      // 一定是使用者存下來的那個值。這一條把它釘住：改成讀記憶體的話，
      // 開 App 的第一幀那個欄位還是預設的 23:30。
      final store = InMemoryKeyValueStore();
      await UserSettingsStore(store).saveBedtime('01:00'); // 存了但沒同步
      final accounts = _FakeAccounts();

      await open(tester, store, accounts);

      expect(accounts.patched, ['01:00']);
    });

    testWidgets('提醒開關關掉之後，重開 App 仍然是關的', (tester) async {
      final store = InMemoryKeyValueStore();
      await open(tester, store, _FakeAccounts());

      settingsOf(tester).onReminderChanged!(false);
      await tester.pump();

      await open(tester, store, _FakeAccounts());
      expect(settingsOf(tester).initialReminderOn, isFalse);
    });

    testWidgets('補送必須排在帳號解析之後', (tester) async {
      // ⚠️ 補送需要 userId。排在 _resolveAccount() 前面的話 userId 還是
      //    null，補送直接 return——上次沒同步成功的目標**永遠補不回來**，
      //    而畫面上一切正常（錯的是後端在拿舊目標算達成度）。
      final store = InMemoryKeyValueStore();
      await UserSettingsStore(store).saveBedtime('01:00'); // 存了但沒同步
      final accounts = _FakeAccounts();

      await open(tester, store, accounts);

      expect(
        accounts.patched,
        isNotEmpty,
        reason: '帳號還沒解析出來就試著補送，等於這個補送機制不存在',
      );
    });

    testWidgets('儲存沒有回應時，App 照樣開得起來', (tester) async {
      // ⚠️ 把 _restoreSettings() 寫成 await 排在 _resolveAccount() 前面，
      //    這裡就會永遠停在轉圈圈上——而錯誤訊息只會說
      //    「Bad state: No element」，完全不指向「因為讀設定卡住了」。
      await tester.pumpWidget(SonnapApp(
        store: _HangingKeyValueStore(),
        accounts: _FakeAccounts(),
      ));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }

      expect(
        find.byType(HomeScreen, skipOffstage: false),
        findsOneWidget,
        reason: '讀一個本機偏好設定不該有能力擋住整個 App 啟動',
      );
      // ⚠️ 不驗「畫面上沒有轉圈圈」——HomeScreen 自己在等 payload 時也有
      //    一個。要驗的是「啟動的轉圈圈已經讓開」，那就等於 HomeScreen
      //    存在，上面那條就夠了。
    });

    testWidgets('沒有帳號時不 PATCH，但本機照樣存', (tester) async {
      final store = InMemoryKeyValueStore();
      final noAccount = _FakeAccounts(userId: null);
      await open(tester, store, noAccount);

      settingsOf(tester).onBedtimeChanged!(const TimeOfDay(hour: 1, minute: 0));
      await tester.pump();

      expect(noAccount.patched, isEmpty);
      expect((await UserSettingsStore(store).load()).targetBedtime, '01:00');
    });
  });
}
