// 就寢提醒：什麼時候響、開關與目標時間改了有沒有跟著重排。
//
// 守的東西（每一條壞掉都不會報錯，只會「今晚沒提醒」或「關了還在響」）：
//   1. 提醒時刻 = 下一次目標就寢時間 − 30 分鐘；剛好等於現在算已經過了；
//      跨午夜的目標也對（00:15 → 前一晚 23:45）。
//   2. 關掉開關要 cancel，不能只是「不再排新的」——已經排好的那一則
//      還躺在 AlarmManager 裡，關掉之後照樣會響。
//   3. 改了目標就寢時間要重排，否則提醒還停在舊時間。
//   4. 「提前幾分鐘」留在 Dart，不寫進 Kotlin（改了不必重編 APK）。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/main.dart';
import 'package:app/screens/settings_screen.dart';
import 'package:app/services/account_service.dart';
import 'package:app/services/bedtime_reminder.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/user_settings.dart';

class _FakeScheduler implements ReminderScheduler {
  final List<DateTime> scheduled = [];
  final List<String> titles = [];
  int cancels = 0;
  int permissionRequests = 0;

  /// 假裝這支手機有沒有通知權限。
  bool canPost;

  _FakeScheduler({this.canPost = true});

  @override
  Future<bool> schedule(DateTime at, {required String title, required String body}) async {
    scheduled.add(at);
    titles.add(title);
    return canPost;
  }

  @override
  Future<void> cancel() async => cancels++;

  @override
  Future<void> requestPermission() async => permissionRequests++;
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

void main() {
  group('提醒時刻', () {
    const bedtime = TimeOfDay(hour: 23, minute: 30);

    test('還沒到 → 今天 23:00', () {
      expect(nextReminderAt(DateTime(2026, 9, 10, 20, 0), bedtime), DateTime(2026, 9, 10, 23, 0));
    });

    test('已經過了提醒時刻 → 明天 23:00', () {
      expect(nextReminderAt(DateTime(2026, 9, 10, 23, 10), bedtime), DateTime(2026, 9, 11, 23, 0));
    });

    test('剛好等於現在 → 算已經過了，排明天（不然會排出一個立刻又響的鬧鐘）', () {
      expect(nextReminderAt(DateTime(2026, 9, 10, 23, 0), bedtime), DateTime(2026, 9, 11, 23, 0));
    });

    test('跨午夜：目標 00:15 → 前一晚 23:45', () {
      const late = TimeOfDay(hour: 0, minute: 15);
      expect(nextReminderAt(DateTime(2026, 9, 10, 20, 0), late), DateTime(2026, 9, 10, 23, 45));
      expect(nextReminderAt(DateTime(2026, 9, 10, 23, 50), late), DateTime(2026, 9, 11, 23, 45));
    });

    test('提前量跟首頁倒數變紅的門檻一致（30 分）', () {
      expect(kReminderLead, const Duration(minutes: 30));
    });
  });

  group('控制器', () {
    test('開著 → 排在 23:00，標題講提前幾分鐘', () async {
      final s = _FakeScheduler();
      final c = BedtimeReminderController(scheduler: s, clock: () => DateTime(2026, 9, 10, 20, 0));
      await c.sync(on: true, bedtime: const TimeOfDay(hour: 23, minute: 30));
      expect(s.scheduled, [DateTime(2026, 9, 10, 23, 0)]);
      expect(s.titles.single, 'Bedtime in 30 minutes');
      expect(s.cancels, 0);
    });

    test('關掉 → cancel，不是只是不排新的', () async {
      final s = _FakeScheduler();
      final c = BedtimeReminderController(scheduler: s, clock: () => DateTime(2026, 9, 10, 20, 0));
      await c.sync(on: false, bedtime: const TimeOfDay(hour: 23, minute: 30));
      expect(s.cancels, 1, reason: '已經排好的那一則還在 AlarmManager 裡，關掉之後照樣會響');
      expect(s.scheduled, isEmpty);
    });
  });

  group('接上 App', () {
    SettingsScreen settingsOf(WidgetTester tester) =>
        tester.widget<SettingsScreen>(find.byType(SettingsScreen, skipOffstage: false));

    Future<void> open(WidgetTester tester, KeyValueStore store, _FakeScheduler s) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(SonnapApp(store: store, accounts: _NoBackendAccounts(), reminders: s));
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
    }

    testWidgets('開 App 時依存下來的設定排好提醒', (tester) async {
      final store = InMemoryKeyValueStore();
      await UserSettingsStore(store).saveBedtime('01:00');
      final s = _FakeScheduler();
      await open(tester, store, s);
      expect(s.scheduled, isNotEmpty);
      expect((s.scheduled.last.hour, s.scheduled.last.minute), (0, 30),
          reason: '目標 01:00 → 提醒 00:30');
    });

    testWidgets('改了目標就寢時間 → 重排到新的時間', (tester) async {
      final s = _FakeScheduler();
      await open(tester, InMemoryKeyValueStore(), s);
      settingsOf(tester).onBedtimeChanged!(const TimeOfDay(hour: 22, minute: 0));
      await tester.pump();
      expect((s.scheduled.last.hour, s.scheduled.last.minute), (21, 30),
          reason: '沒重排的話，提醒還停在舊的 23:00');
    });

    testWidgets('關掉提醒 → cancel', (tester) async {
      final s = _FakeScheduler();
      await open(tester, InMemoryKeyValueStore(), s);
      final before = s.cancels;
      settingsOf(tester).onReminderChanged!(false);
      await tester.pump();
      expect(s.cancels, before + 1);
    });

    testWidgets('重新打開提醒 → 要權限並排程', (tester) async {
      final store = InMemoryKeyValueStore();
      await UserSettingsStore(store).saveReminder(false);
      final s = _FakeScheduler();
      await open(tester, store, s);
      final scheduledBefore = s.scheduled.length;
      settingsOf(tester).onReminderChanged!(true);
      await tester.pump();
      expect(s.permissionRequests, greaterThanOrEqualTo(1));
      expect(s.scheduled.length, scheduledBefore + 1);
    });

    testWidgets('存下來是關的 → 開 App 時不排，而且把舊的取消', (tester) async {
      final store = InMemoryKeyValueStore();
      await UserSettingsStore(store).saveReminder(false);
      final s = _FakeScheduler();
      await open(tester, store, s);
      expect(s.scheduled, isEmpty);
      expect(s.cancels, greaterThanOrEqualTo(1));
    });

    testWidgets('手機沒有通知權限 → 開 App 時要一次權限', (tester) async {
      // Android 13+ 預設沒有通知權限。提醒開關預設是開的，不在開 App 時要一次的話，
      // 大部分 D2 受測者的提醒永遠不會出現，而開關看起來是開著的。
      final s = _FakeScheduler(canPost: false);
      await open(tester, InMemoryKeyValueStore(), s);
      expect(s.permissionRequests, 1);
    });

    testWidgets('有權限 → 開 App 時不打擾', (tester) async {
      final s = _FakeScheduler(canPost: true);
      await open(tester, InMemoryKeyValueStore(), s);
      expect(s.permissionRequests, 0);
    });
  });

  group('「提前幾分鐘」留在 Dart', () {
    test('Kotlin 端沒有提前量之類的常數', () {
      // 門檻寫進 Kotlin 的話，每次調整都要重編 APK 才驗得了。
      const dir = 'android/app/src/main/kotlin/com/example/app';
      for (final name in ['NotificationService.kt', 'BedtimeReminderReceiver.kt']) {
        final src = File('$dir/$name').readAsStringSync();
        final code = src.split('\n').where((l) => !l.trimLeft().startsWith('*') && !l.trimLeft().startsWith('//')).join('\n');
        // ⚠️ `L?`：Kotlin 的 Long 寫成 1800000L，少了它 \b 對不上而放過去
        //    （B4 的變異測試抓到的，同一個漏洞原本也在這裡）。
        expect(RegExp(r'\b(30|1800|1800000)L?\b').hasMatch(code), isFalse, reason: '$name 裡長出了提前量');
        expect(code.contains('TimeUnit.MINUTES'), isFalse, reason: name);
      }
    });
  });
}
