// 偵測就寢＋上傳＋問挑戰（NightlySync）是 App 層在跑，不是哪一頁（2026-11-19 從舊 Insights 頁搬出來）。
//
// 守的是壞掉時不會報錯的那件事：有人改 main.dart 時拿掉觸發，App 照樣開得起來、
// 畫面一切正常，只是昨晚沒上傳、熬夜與挑戰少一晚。2026-11-20 已在實機看到
// 設定頁 Data 寫「Last night sent」，這支測試把「會觸發」釘住。
//
//   1. 打開 App（帳號解析完之後）跑一次
//   2. 每次回到前景再跑一次
//   3. 帳號還沒解析完（畫面還在轉圈圈）就回到前景，不跑——那時候傳不出去
import 'dart:async';

import 'package:app/main.dart';
import 'package:app/services/account_service.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/bedtime_reminder.dart';
import 'package:app/services/challenges_service.dart';
import 'package:app/services/home_service.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/nightly_sync.dart';
import 'package:app/services/nightly_uploader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 只數被叫了幾次，不真的去讀手機事件、不上傳。
class _CountingSync extends NightlySync {
  _CountingSync() : super(bedMarks: BedMarkStore(InMemoryKeyValueStore()));

  int runs = 0;

  @override
  Future<void> run({
    NightlyUploader? uploader,
    ChallengesService? challengesService,
    HomeService? homeService,
  }) async {
    runs++;
  }
}

class _QuietScheduler implements ReminderScheduler {
  @override
  Future<bool> schedule(DateTime at, {required String title, required String body}) async => true;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> requestPermission() async {}
}

/// 帳號解析要多久由測試決定：[gate] 完成之前，App 停在轉圈圈。
class _GatedAccounts implements AccountService {
  final Future<void> gate;
  _GatedAccounts([Future<void>? gate]) : gate = gate ?? Future<void>.value();

  @override
  Future<AccountStatus> resolve() async {
    await gate;
    return const AccountStatus(AccountState.noBackend);
  }

  @override
  Future<AccountStatus?> createAccount(
          {required String displayName, required String targetBedtime}) async =>
      null;

  @override
  Future<bool> updateTargetBedtime(
          {required String userId, required String targetBedtime}) async =>
      false;

  @override
  Future<bool> updateTargetWake({required String userId, required String targetWake}) async =>
      false;

  @override
  String get baseUrl => '';

  @override
  KeyValueStore get store => InMemoryKeyValueStore();

  @override
  Duration get timeout => const Duration(seconds: 1);
}

void main() {
  Future<_CountingSync> open(WidgetTester tester, {Future<void>? gate}) async {
    final sync = _CountingSync();
    addTearDown(sync.dispose);
    await tester.pumpWidget(SonnapApp(
      store: InMemoryKeyValueStore(),
      accounts: _GatedAccounts(gate),
      reminders: _QuietScheduler(),
      nightly: sync,
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    return sync;
  }

  Future<void> resume(WidgetTester tester) async {
    // Flutter 只准一步一步切：resumed → inactive → hidden → paused，回來反過來
    for (final s in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
  }

  testWidgets('打開 App 就跑一次上傳', (tester) async {
    final sync = await open(tester);
    expect(sync.runs, 1, reason: '拿掉 _start() 裡那一行，App 照樣開得起來，只是昨晚沒上傳');
  });

  testWidgets('每次回到前景再跑一次', (tester) async {
    final sync = await open(tester);
    await resume(tester);
    expect(sync.runs, 2, reason: '隔天早上從背景切回來，昨晚要能上傳');
    await resume(tester);
    expect(sync.runs, 3);
  });

  testWidgets('帳號還沒解析完就回到前景：不跑（傳不出去），解析完才跑', (tester) async {
    final gate = Completer<void>();
    final sync = await open(tester, gate: gate.future);
    expect(sync.runs, 0, reason: '還在轉圈圈');
    await resume(tester);
    expect(sync.runs, 0, reason: '沒有帳號時跑了也送不出去');
    gate.complete();
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(sync.runs, 1);
  });
}
