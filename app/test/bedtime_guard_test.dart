// 就寢守門（B4）：什麼時候守、守誰、做什麼，以及設定有沒有真的推到原生端。
//
// 守的東西（每一條壞掉都不會報錯，只會「該擋的沒擋」或「不該擋的被擋」）：
//   1. 時間窗 = 目標前 30 分 → 目標後 6 小時；半夜正在滑手機時，守的是
//      「昨晚開始的那一窗」，不是今晚那一窗。
//   2. 原生端的行為規格（actionFor）：模式、時間窗、名單三個條件缺一不可，
//      block 與 reminder 不能對調。
//   3. 改了目標就寢時間要重推，否則原生端還在守舊的時間窗。
//   4. 設定頁改了模式或名單要推到原生端，不能只存在本機。
//   5. 從系統設定回來要重查權限（openSettings 送出 intent 就返回了）。
//   6. 對使用者的隱私承諾：服務不讀畫面內容（canRetrieveWindowContent=false）。
//   7. 門檻留在 Dart，不寫進 Kotlin。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/main.dart';
import 'package:app/screens/bedtime_guard_screen.dart';
import 'package:app/screens/settings_screen.dart';
import 'package:app/services/account_service.dart';
import 'package:app/services/bedtime_guard.dart';
import 'package:app/services/bedtime_reminder.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/widgets/bedtime_urgency.dart';

class _FakeGuard implements GuardPlatform {
  final List<GuardConfig> configs = [];
  bool enabled;
  int opens = 0;
  final List<LaunchableApp> apps;

  _FakeGuard({this.enabled = false, this.apps = const []});

  @override
  Future<void> configure(GuardConfig config) async => configs.add(config);

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> openSettings() async => opens++;

  @override
  Future<List<LaunchableApp>> listApps() async => apps;
}

class _QuietScheduler implements ReminderScheduler {
  @override
  Future<bool> schedule(DateTime at, {required String title, required String body}) async => true;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> requestPermission() async {}
}

class _NoBackendAccounts implements AccountService {
  @override
  Future<AccountStatus> resolve() async => const AccountStatus(AccountState.noBackend);

  @override
  Future<AccountStatus?> createAccount({required String displayName, required String targetBedtime}) async => null;

  @override
  Future<bool> updateTargetBedtime({required String userId, required String targetBedtime}) async => false;

  @override
  String get baseUrl => '';

  @override
  KeyValueStore get store => InMemoryKeyValueStore();

  @override
  Duration get timeout => const Duration(seconds: 1);
}

const _insta = 'com.instagram.android';
const _tiktok = 'com.zhiliaoapp.musically';

GuardConfig _config(GuardMode mode) => GuardConfig(
      mode: mode,
      window: GuardWindow(DateTime(2026, 9, 10, 23, 0), DateTime(2026, 9, 11, 5, 30)),
      packages: const {_insta},
      title: 't',
      body: 'b',
    );

void main() {
  group('時間窗', () {
    const bedtime = TimeOfDay(hour: 23, minute: 30);

    test('晚上 8 點 → 今晚 23:00 到明早 05:30', () {
      final w = guardWindow(DateTime(2026, 9, 10, 20, 0), bedtime);
      expect((w.start, w.end), (DateTime(2026, 9, 10, 23, 0), DateTime(2026, 9, 11, 5, 30)));
    });

    test('半夜 1 點 → 守的是昨晚開始的那一窗，不是今晚那一窗', () {
      // 只看「今天的目標時刻」的話會跳到今晚 23:00，半夜正在滑手機時反而不守。
      final now = DateTime(2026, 9, 11, 1, 0);
      final w = guardWindow(now, bedtime);
      expect((w.start, w.end), (DateTime(2026, 9, 10, 23, 0), DateTime(2026, 9, 11, 5, 30)));
      expect(w.contains(now), isTrue);
    });

    test('終點不算在內：05:30 整已經換成今晚那一窗', () {
      final w = guardWindow(DateTime(2026, 9, 11, 5, 30), bedtime);
      expect(w.start, DateTime(2026, 9, 11, 23, 0));
      final last = GuardWindow(DateTime(2026, 9, 10, 23, 0), DateTime(2026, 9, 11, 5, 30));
      expect(last.contains(DateTime(2026, 9, 11, 5, 29, 59)), isTrue);
      expect(last.contains(DateTime(2026, 9, 11, 5, 30)), isFalse);
    });

    test('起點算在內：22:59 不守、23:00 開始守', () {
      final w = guardWindow(DateTime(2026, 9, 10, 20, 0), bedtime);
      expect(w.contains(DateTime(2026, 9, 10, 22, 59)), isFalse);
      expect(w.contains(DateTime(2026, 9, 10, 23, 0)), isTrue);
    });

    test('跨午夜的目標：00:15、現在 23:50 → 已經在守（23:45 起）', () {
      final now = DateTime(2026, 9, 10, 23, 50);
      final w = guardWindow(now, const TimeOfDay(hour: 0, minute: 15));
      expect((w.start, w.end), (DateTime(2026, 9, 10, 23, 45), DateTime(2026, 9, 11, 6, 15)));
      expect(w.contains(now), isTrue);
    });

    test('提前量與就寢提醒、首頁倒數變紅一致（30 分）', () {
      // 不一致的話：通知說「還有 30 分」、倒數還是綠的、App 卻已經被擋了。
      expect(kGuardLeadIn, kReminderLead);
      expect(kGuardLeadIn, kImminentThreshold);
    });
  });

  group('原生端的行為規格（actionFor）', () {
    final inWindow = DateTime(2026, 9, 11, 0, 30);

    test('send-home 模式、在窗裡、在名單上 → 回桌面', () {
      expect(_config(GuardMode.block).actionFor(inWindow, _insta), GuardAction.sendHome);
    });

    test('提醒模式 → 只提醒，不關掉 App', () {
      expect(_config(GuardMode.reminder).actionFor(inWindow, _insta), GuardAction.remind);
    });

    test('關掉 → 什麼都不做', () {
      expect(_config(GuardMode.off).actionFor(inWindow, _insta), GuardAction.none);
    });

    test('時間窗外 → 什麼都不做（早上查公車不能被擋）', () {
      final c = _config(GuardMode.block);
      expect(c.actionFor(DateTime(2026, 9, 10, 22, 59), _insta), GuardAction.none);
      expect(c.actionFor(DateTime(2026, 9, 11, 5, 30), _insta), GuardAction.none);
      expect(c.actionFor(DateTime(2026, 9, 11, 12, 0), _insta), GuardAction.none);
    });

    test('不在名單上 → 什麼都不做', () {
      final c = _config(GuardMode.block);
      expect(c.actionFor(inWindow, _tiktok), GuardAction.none);
      expect(c.actionFor(inWindow, null), GuardAction.none);
    });

    test('推給原生端的欄位', () {
      final m = GuardConfig(
        mode: GuardMode.reminder,
        window: GuardWindow(DateTime(2026, 9, 10, 23, 0), DateTime(2026, 9, 11, 5, 30)),
        packages: const {_tiktok, _insta},
        title: 't',
        body: 'b',
      ).toMap();
      expect(m['mode'], 'reminder');
      expect(m['startMillis'], DateTime(2026, 9, 10, 23, 0).millisecondsSinceEpoch);
      expect(m['endMillis'], DateTime(2026, 9, 11, 5, 30).millisecondsSinceEpoch);
      expect(m['packages'], [_insta, _tiktok]);
      expect(m['cooldownMillis'], const Duration(minutes: 10).inMilliseconds);
    });
  });

  group('控制器', () {
    test('沒存過 → 關閉、名單空的', () async {
      final c = BedtimeGuardController(platform: _FakeGuard(), store: InMemoryKeyValueStore());
      final s = await c.load();
      expect(s.mode, GuardMode.off);
      expect(s.packages, isEmpty);
    });

    test('存了讀得回來', () async {
      final c = BedtimeGuardController(platform: _FakeGuard(), store: InMemoryKeyValueStore());
      await c.save(const GuardSettings(mode: GuardMode.block, packages: {_insta, _tiktok}));
      final s = await c.load();
      expect(s.mode, GuardMode.block);
      expect(s.packages, {_insta, _tiktok});
    });

    test('名單存壞了 → 當作沒選，模式照舊', () async {
      final store = InMemoryKeyValueStore({
        BedtimeGuardController.modeKey: 'reminder',
        BedtimeGuardController.packagesKey: '{not json',
      });
      final s = await BedtimeGuardController(platform: _FakeGuard(), store: store).load();
      expect(s.mode, GuardMode.reminder);
      expect(s.packages, isEmpty);
    });

    test('push → 依時鐘與目標算出時間窗，連同名單推出去', () async {
      final guard = _FakeGuard();
      final c = BedtimeGuardController(
        platform: guard,
        store: InMemoryKeyValueStore(),
        clock: () => DateTime(2026, 9, 10, 20, 0),
      );
      await c.save(const GuardSettings(mode: GuardMode.block, packages: {_insta}));
      await c.push(const TimeOfDay(hour: 23, minute: 30));
      final sent = guard.configs.single;
      expect(sent.mode, GuardMode.block);
      expect(sent.packages, {_insta});
      expect((sent.window.start, sent.window.end),
          (DateTime(2026, 9, 10, 23, 0), DateTime(2026, 9, 11, 5, 30)));
      expect(sent.body, contains('23:30'));
    });
  });

  group('接上 App', () {
    SettingsScreen settingsOf(WidgetTester tester) =>
        tester.widget<SettingsScreen>(find.byType(SettingsScreen, skipOffstage: false));

    Future<void> open(WidgetTester tester, _FakeGuard guard) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(SonnapApp(
        store: InMemoryKeyValueStore(),
        accounts: _NoBackendAccounts(),
        reminders: _QuietScheduler(),
        guard: guard,
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
    }

    testWidgets('開 App 時推一次（預設 23:30 → 23:00 起守）', (tester) async {
      final guard = _FakeGuard();
      await open(tester, guard);
      expect(guard.configs, isNotEmpty);
      final start = guard.configs.last.window.start;
      expect((start.hour, start.minute), (23, 0));
    });

    testWidgets('改了目標就寢時間 → 重推新的時間窗', (tester) async {
      final guard = _FakeGuard();
      await open(tester, guard);
      final before = guard.configs.length;
      settingsOf(tester).onBedtimeChanged!(const TimeOfDay(hour: 22, minute: 0));
      await tester.pump();
      await tester.pump();
      expect(guard.configs.length, greaterThan(before),
          reason: '沒重推的話，原生端還在守舊的 23:00 → 05:30');
      final start = guard.configs.last.window.start;
      expect((start.hour, start.minute), (21, 30));
    });

    testWidgets('設定頁的 Bedtime Guard 打得開', (tester) async {
      final guard = _FakeGuard();
      await open(tester, guard);
      expect(settingsOf(tester).onBedtimeGuardTap, isNotNull,
          reason: '沒接上的話，按下去只會跳「之後才有」');
      settingsOf(tester).onBedtimeGuardTap!();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(BedtimeGuardScreen), findsOneWidget);
    });
  });

  group('設定頁', () {
    Future<(_FakeGuard, InMemoryKeyValueStore)> show(WidgetTester tester, {bool enabled = false}) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final guard = _FakeGuard(enabled: enabled, apps: const [
        LaunchableApp(_insta, 'Instagram'),
        LaunchableApp(_tiktok, 'TikTok'),
      ]);
      final store = InMemoryKeyValueStore();
      final controller = BedtimeGuardController(
        platform: guard,
        store: store,
        clock: () => DateTime(2026, 9, 10, 20, 0),
      );
      await tester.pumpWidget(MaterialApp(
        home: BedtimeGuardScreen(controller: controller, bedtime: const TimeOfDay(hour: 23, minute: 30)),
      ));
      await tester.pump();
      await tester.pump();
      return (guard, store);
    }

    testWidgets('預設關閉 → 不提權限', (tester) async {
      await show(tester);
      expect(find.byKey(const Key('guard-permission')), findsNothing);
    });

    testWidgets('選 send-home → 存下來、推到原生端、提示要開權限', (tester) async {
      final (guard, store) = await show(tester);
      await tester.tap(find.byKey(const Key('guard-mode-block')));
      await tester.pump();
      await tester.pump();
      expect(await store.getString(BedtimeGuardController.modeKey), 'block');
      expect(guard.configs.last.mode, GuardMode.block,
          reason: '只存在本機的話，原生端永遠不知道使用者選了什麼');
      expect(find.text('Accessibility access is off.'), findsOneWidget);
      expect(find.byKey(const Key('guard-restricted-hint')), findsOneWidget);
      await tester.tap(find.byKey(const Key('guard-open-settings')));
      expect(guard.opens, 1);
    });

    testWidgets('勾選 App → 名單推到原生端；取消勾選 → 移除', (tester) async {
      final (guard, _) = await show(tester);
      await tester.tap(find.byKey(const Key('guard-app-$_insta')));
      await tester.pump();
      await tester.pump();
      expect(guard.configs.last.packages, {_insta});
      await tester.tap(find.byKey(const Key('guard-app-$_insta')));
      await tester.pump();
      await tester.pump();
      expect(guard.configs.last.packages, isEmpty);
    });

    testWidgets('從系統設定回來 → 重查權限', (tester) async {
      final (guard, _) = await show(tester);
      await tester.tap(find.byKey(const Key('guard-mode-reminder')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Accessibility access is off.'), findsOneWidget);

      guard.enabled = true; // 使用者在系統設定裡打開了
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(find.text('Accessibility access is on.'), findsOneWidget);
      expect(find.byKey(const Key('guard-open-settings')), findsNothing);
    });
  });

  group('原生端', () {
    const dir = 'android/app/src/main';

    test('不讀畫面內容（設定頁上對使用者的承諾）', () {
      final xml = File('$dir/res/xml/bedtime_guard_config.xml').readAsStringSync();
      expect(xml, contains('android:canRetrieveWindowContent="false"'));
      expect(xml, isNot(contains('android:canRetrieveWindowContent="true"')));
    });

    test('服務只有系統叫得動', () {
      final manifest = File('$dir/AndroidManifest.xml').readAsStringSync();
      final service = RegExp(r'<service[^>]*BedtimeGuardService[^>]*>', dotAll: true).firstMatch(manifest);
      expect(service, isNotNull);
      expect(service!.group(0), contains('android.permission.BIND_ACCESSIBILITY_SERVICE'));
    });

    test('Kotlin 端沒有時間門檻', () {
      // 門檻寫進 Kotlin 的話，每次調整都要重編 APK 才驗得了。
      for (final name in ['BedtimeGuardService.kt', 'GuardConfigStore.kt', 'BedtimeGuardBridge.kt']) {
        final src = File('$dir/kotlin/com/example/app/$name').readAsStringSync();
        final code = src
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('*') && !l.trimLeft().startsWith('//'))
            .join('\n');
        // ⚠️ `L?`：Kotlin 的 Long 寫成 1800000L，少了它 \b 對不上，
        //    變異測試（放一行 `val leadMs = 1800000L`）實測是綠的。
        expect(RegExp(r'\b(30|360|1800000|21600000|600000)L?\b').hasMatch(code), isFalse,
            reason: '$name 裡長出了時間門檻');
        expect(code.contains('TimeUnit'), isFalse, reason: name);
      }
    });
  });
}
