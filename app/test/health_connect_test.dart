// Health Connect（B8）：送哪幾段、送出去長什麼樣、失敗了會不會再送。
//
// 守的東西（每一條壞掉都不會報錯）：
//   1. 同一個起床日只送最長的那一段——午覺照順序送會蓋掉那一晚
//      （後端以起床日 upsert、照樣回 201）。
//   2. 起床日照字串上的牆鐘時間：07:30+08:00 在 UTC 是前一天。
//   3. 送出去的欄位名稱跟 adapter 讀的一致（漂移時只會變成 422）。
//   4. 連不上的那一段下次要再送；後端 422 的不再送（送幾次都一樣）。
//   5. 沒有後端的 build 不碰 Health Connect（開 App 不會跳授權）。
//   6. 開 App 時的自動同步不問授權，只有設定頁的按鈕問。
//   7. 只要睡眠權限；授權畫面需要的隱私頁兩個入口都在。
//   8. 往回讀幾天留在 Dart。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/main.dart';
import 'package:app/screens/health_connect_screen.dart';
import 'package:app/screens/settings_screen.dart';
import 'package:app/services/account_service.dart';
import 'package:app/services/bedtime_reminder.dart';
import 'package:app/services/health_connect.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/user_identity.dart';

class _FakeHealth implements HealthPlatform {
  HealthAvailability status;
  bool granted;
  final bool grantOnRequest;
  List<Map<Object?, Object?>> sessions;
  int availabilityCalls = 0;
  int requests = 0;
  int reads = 0;
  int storeOpens = 0;
  DateTime? readStart;
  DateTime? readEnd;

  _FakeHealth({
    this.status = HealthAvailability.available,
    this.granted = true,
    this.grantOnRequest = true,
    this.sessions = const [],
  });

  @override
  Future<HealthAvailability> availability() async {
    availabilityCalls++;
    return status;
  }

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<bool> requestPermission() async {
    requests++;
    granted = grantOnRequest;
    return granted;
  }

  @override
  Future<void> openProviderStore() async => storeOpens++;

  @override
  Future<List<Map<Object?, Object?>>> readSleepSessions(DateTime start, DateTime end) async {
    reads++;
    readStart = start;
    readEnd = end;
    return sessions;
  }
}

class _FakeUploader implements WearableUploader {
  final List<HealthSession> sent = [];
  final WearableUploadStatus Function(HealthSession) respond;

  _FakeUploader([WearableUploadStatus Function(HealthSession)? respond])
      : respond = respond ?? ((_) => WearableUploadStatus.ok);

  @override
  String get baseUrl => 'http://unused';

  @override
  UserIdentity get identity => ResolvedUserIdentity('u1');

  @override
  Duration get timeout => const Duration(seconds: 1);

  @override
  Future<WearableUploadResult> upload(HealthSession session) async {
    sent.add(session);
    final status = respond(session);
    return WearableUploadResult(
      status,
      date: session.wakeDate,
      baseQuality: status == WearableUploadStatus.ok ? 'Good' : null,
    );
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

Map<Object?, Object?> _raw(String start, String end) => {
      'startTime': start,
      'endTime': end,
      'stages': [
        {'startTime': start, 'endTime': end, 'stage': 4},
      ],
      'origin': 'com.sec.android.app.shealth',
    };

final _night11 = _raw('2026-09-10T23:10:00+08:00', '2026-09-11T07:30:00+08:00');
final _nap11 = _raw('2026-09-11T14:00:00+08:00', '2026-09-11T14:40:00+08:00');
final _night10 = _raw('2026-09-09T23:40:00+08:00', '2026-09-10T07:00:00+08:00');

HealthSession _s(Map<Object?, Object?> raw) => HealthSession.tryParse(raw)!;

void main() {
  group('挑哪幾段', () {
    test('午覺不能蓋掉那一晚：同一個起床日只送最長的（順序不影響）', () {
      for (final order in [
        [_night11, _nap11],
        [_nap11, _night11],
      ]) {
        final todo = sessionsToUpload(order.map(_s), {});
        expect(todo.map((s) => s.key), [_s(_night11).key]);
      }
    });

    test('兩個起床日 → 兩段都送，舊的先送', () {
      final todo = sessionsToUpload([_s(_night11), _s(_night10)], {});
      expect(todo.map((s) => s.key), [_s(_night10).key, _s(_night11).key]);
    });

    test('送過的不再送', () {
      expect(sessionsToUpload([_s(_night11)], {_s(_night11).key}), isEmpty);
    });

    test('同一天後來出現更長的一段 → 送新的，讓後端覆寫', () {
      final partial = _s(_raw('2026-09-10T23:10:00+08:00', '2026-09-11T03:00:00+08:00'));
      final todo = sessionsToUpload([partial, _s(_night11)], {partial.key});
      expect(todo.map((s) => s.key), [_s(_night11).key]);
    });

    test('起床日照字串上的牆鐘時間，不是 UTC', () {
      // 07:30+08:00 在 UTC 是 09-10 23:30。
      expect(_s(_night11).wakeDate, '2026-09-11');
      expect(_s(_raw('2026-09-10T22:00:00+08:00', '2026-09-11T00:30:00+08:00')).wakeDate, '2026-09-11');
    });

    test('時間壞掉的 session 不收；分期照原樣留給後端判斷', () {
      expect(HealthSession.tryParse({'startTime': '2026-09-10T23:10:00+08:00'}), isNull);
      expect(HealthSession.tryParse({'startTime': 'yesterday', 'endTime': 'today'}), isNull);
      final noStages = HealthSession.tryParse({
        'startTime': '2026-09-10T23:10:00+08:00',
        'endTime': '2026-09-11T07:30:00+08:00',
      });
      expect(noStages, isNotNull, reason: '沒有分期的由後端回 422 並說明原因，在這裡擋掉使用者就看不到原因');
      expect(_s(_night11).stages.single['stage'], 4);
    });
  });

  group('送出去的格式', () {
    test('session 只帶 adapter 要的三個欄位', () {
      final payload = _s(_night11).toPayload();
      expect(payload.keys.toSet(), {'startTime', 'endTime', 'stages'});
      expect((payload['stages'] as List).single.keys.toSet(), {'startTime', 'endTime', 'stage'});
    });

    test('adapter 讀的就是這幾個欄位名稱（兩邊漂移只會變成 422）', () {
      final adapter = File('../wearable/healthconnect_adapter.py').readAsStringSync();
      for (final read in [
        'session.get("startTime")',
        'session.get("endTime")',
        'session.get("stages")',
        's.get("startTime")',
        's.get("endTime")',
        's.get("stage")',
      ]) {
        expect(adapter, contains(read));
      }
      // Kotlin 端傳的是 Health Connect 原生的整數代碼
      expect(adapter, contains('4: "light", 5: "deep", 6: "rem"'));
    });
  });

  group('POST /wearable', () {
    late HttpServer server;
    late List<Map<String, dynamic>> received;
    late String baseUrl;
    var status = 201;
    HttpOverrides? saved;

    setUp(() async {
      saved = HttpOverrides.current;
      HttpOverrides.global = null;
      received = [];
      status = 201;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        received.add({'path': request.uri.path, 'body': jsonDecode(body)});
        request.response.statusCode = status;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(status == 201
            ? {'date': '2026-09-11', 'base_quality': 'Good', 'final_score': 81.5}
            : {'detail': 'Session has no stages.'}));
        await request.response.close();
      });
      baseUrl = 'http://127.0.0.1:${server.port}';
    });

    tearDown(() async {
      await server.close(force: true);
      HttpOverrides.global = saved;
    });

    test('201 → 照抄後端的日期與等級', () async {
      final r = await WearableUploader(baseUrl: baseUrl, identity: ResolvedUserIdentity('u1'))
          .upload(_s(_night11));
      expect(r.status, WearableUploadStatus.ok);
      expect((r.date, r.baseQuality, r.finalScore), ('2026-09-11', 'Good', 81.5));
      expect(received.single['path'], '/wearable');
      final body = received.single['body'] as Map<String, dynamic>;
      expect(body['user_id'], 'u1');
      expect((body['session'] as Map)['endTime'], '2026-09-11T07:30:00+08:00');
    });

    test('422 → rejected（不重送）', () async {
      status = 422;
      final r = await WearableUploader(baseUrl: baseUrl, identity: ResolvedUserIdentity('u1'))
          .upload(_s(_night11));
      expect(r.status, WearableUploadStatus.rejected);
    });

    test('500 → failed（下次再送）', () async {
      status = 500;
      final r = await WearableUploader(baseUrl: baseUrl, identity: ResolvedUserIdentity('u1'))
          .upload(_s(_night11));
      expect(r.status, WearableUploadStatus.failed);
    });

    test('沒有帳號 → 不發請求', () async {
      final r = await WearableUploader(baseUrl: baseUrl, identity: ResolvedUserIdentity(null))
          .upload(_s(_night11));
      expect(r.status, WearableUploadStatus.noUser);
      expect(received, isEmpty);
    });
  });

  group('同步', () {
    HealthSyncController controller(_FakeHealth health, {WearableUploader? uploader, KeyValueStore? store}) =>
        HealthSyncController(
          platform: health,
          store: store ?? InMemoryKeyValueStore(),
          uploader: uploader,
          clock: () => DateTime(2026, 9, 11, 9, 0),
        );

    test('沒有後端 → 連 Health Connect 都不碰', () async {
      final health = _FakeHealth(granted: false);
      final r = await controller(health).sync(askPermission: true);
      expect(r.status, HealthSyncStatus.noBackend);
      expect(health.availabilityCalls, 0);
      expect(health.requests, 0);
    });

    test('手機沒有 Health Connect → 不問授權', () async {
      final health = _FakeHealth(status: HealthAvailability.unavailable, granted: false);
      final r = await controller(health, uploader: _FakeUploader()).sync(askPermission: true);
      expect(r.status, HealthSyncStatus.unavailable);
      expect(health.requests, 0);
    });

    test('Health Connect 要更新 → 回報，不讀', () async {
      final health = _FakeHealth(status: HealthAvailability.needsUpdate);
      final r = await controller(health, uploader: _FakeUploader()).sync();
      expect(r.status, HealthSyncStatus.needsUpdate);
      expect(health.reads, 0);
    });

    test('沒授權、開 App 自動同步 → 不問、不讀', () async {
      final health = _FakeHealth(granted: false);
      final r = await controller(health, uploader: _FakeUploader()).sync();
      expect(r.status, HealthSyncStatus.noPermission);
      expect(health.requests, 0, reason: '使用者沒按任何東西就跳系統授權畫面很突兀');
      expect(health.reads, 0);
    });

    test('沒授權、按了按鈕 → 問一次，給了就送', () async {
      final health = _FakeHealth(granted: false, sessions: [_night11]);
      final uploader = _FakeUploader();
      final r = await controller(health, uploader: uploader).sync(askPermission: true);
      expect(health.requests, 1);
      expect(r.status, HealthSyncStatus.done);
      expect(uploader.sent.single.key, _s(_night11).key);
    });

    test('授權畫面上按了拒絕 → 不讀、不送', () async {
      final health = _FakeHealth(granted: false, grantOnRequest: false, sessions: [_night11]);
      final uploader = _FakeUploader();
      final r = await controller(health, uploader: uploader).sync(askPermission: true);
      expect(r.status, HealthSyncStatus.noPermission);
      expect(health.reads, 0);
      expect(uploader.sent, isEmpty);
    });

    test('往回讀 3 天', () async {
      final health = _FakeHealth();
      await controller(health, uploader: _FakeUploader()).sync();
      expect(health.readEnd, DateTime(2026, 9, 11, 9, 0));
      expect(health.readStart, DateTime(2026, 9, 8, 9, 0));
    });

    test('送成功的不再送', () async {
      final health = _FakeHealth(sessions: [_night10, _night11]);
      final store = InMemoryKeyValueStore();
      await controller(health, uploader: _FakeUploader(), store: store).sync();
      final second = _FakeUploader();
      await controller(health, uploader: second, store: store).sync();
      expect(second.sent, isEmpty);
    });

    test('連不上的下次再送；後端 422 的不再送', () async {
      final health = _FakeHealth(sessions: [_night10, _night11]);
      final store = InMemoryKeyValueStore();
      final first = _FakeUploader((s) => s.key == _s(_night10).key
          ? WearableUploadStatus.failed
          : WearableUploadStatus.rejected);
      await controller(health, uploader: first, store: store).sync();
      expect(first.sent.length, 2);

      final second = _FakeUploader();
      await controller(health, uploader: second, store: store).sync();
      expect(second.sent.map((s) => s.key), [_s(_night10).key],
          reason: '連不上的那晚要補送；422 的送幾次都一樣');
    });

    test('送過的清單存壞了 → 當作沒送過（最壞是重送一次，後端是 upsert）', () async {
      final health = _FakeHealth(sessions: [_night11]);
      final store = InMemoryKeyValueStore({HealthSyncController.uploadedKey: '{bad'});
      final uploader = _FakeUploader();
      await controller(health, uploader: uploader, store: store).sync();
      expect(uploader.sent.length, 1);
    });
  });

  group('畫面上的那一句', () {
    test('成功 → 照抄後端的等級', () {
      final text = describeHealthSync(const HealthSyncResult(HealthSyncStatus.done, found: 2, uploads: [
        WearableUploadResult(WearableUploadStatus.ok, date: '2026-09-10', baseQuality: 'Normal'),
        WearableUploadResult(WearableUploadStatus.ok, date: '2026-09-11', baseQuality: 'Good'),
      ]));
      expect(text, contains('Sent 2 nights'));
      expect(text, contains('2026-09-11, rated Good by the backend'));
    });

    test('失敗的會說下次再送', () {
      final text = describeHealthSync(const HealthSyncResult(HealthSyncStatus.done, found: 1, uploads: [
        WearableUploadResult(WearableUploadStatus.failed),
      ]));
      expect(text, contains('will be retried'));
    });

    test('找不到任何 session → 講明往回看幾天', () {
      expect(describeHealthSync(const HealthSyncResult(HealthSyncStatus.done)), contains('last 3 days'));
    });
  });

  group('設定頁', () {
    Future<_FakeHealth> show(WidgetTester tester, _FakeHealth health) async {
      await tester.pumpWidget(MaterialApp(
        home: HealthConnectScreen(
          controller: HealthSyncController(platform: health, store: InMemoryKeyValueStore()),
        ),
      ));
      await tester.pump();
      await tester.pump();
      return health;
    }

    testWidgets('手機沒有 Health Connect → 說明，沒有同步按鈕', (tester) async {
      await show(tester, _FakeHealth(status: HealthAvailability.unavailable));
      expect(find.text('Health Connect is not available on this phone.'), findsOneWidget);
      expect(find.byKey(const Key('health-sync')), findsNothing);
    });

    testWidgets('要更新 → 帶去商店', (tester) async {
      final health = await show(tester, _FakeHealth(status: HealthAvailability.needsUpdate));
      await tester.tap(find.byKey(const Key('health-install')));
      expect(health.storeOpens, 1);
    });

    testWidgets('沒有後端 → 按了也不問授權，並說明原因', (tester) async {
      final health = await show(tester, _FakeHealth(granted: false));
      expect(find.text('Not connected yet.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('health-sync')));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('needs the Sonnap backend'), findsOneWidget);
      expect(health.requests, 0);
    });
  });

  group('接上 App', () {
    SettingsScreen settingsOf(WidgetTester tester) =>
        tester.widget<SettingsScreen>(find.byType(SettingsScreen, skipOffstage: false));

    Future<void> open(WidgetTester tester, _FakeHealth health) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(SonnapApp(
        store: InMemoryKeyValueStore(),
        accounts: _NoBackendAccounts(),
        reminders: _QuietScheduler(),
        health: health,
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
    }

    testWidgets('沒有後端的 build 開起來不碰 Health Connect', (tester) async {
      final health = _FakeHealth(granted: false);
      await open(tester, health);
      expect(health.availabilityCalls, 0, reason: 'demo build 不該碰 Health Connect');
      expect(health.requests, 0);
    });

    testWidgets('Settings 的 Health Connect 打得開', (tester) async {
      final health = _FakeHealth();
      await open(tester, health);
      expect(settingsOf(tester).onHealthConnectTap, isNotNull,
          reason: '沒接上的話，按下去只會跳「之後才有」');
      settingsOf(tester).onHealthConnectTap!();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(HealthConnectScreen), findsOneWidget);
    });
  });

  group('原生端', () {
    const dir = 'android/app/src/main';

    test('只要睡眠這一個權限', () {
      final manifest = File('$dir/AndroidManifest.xml').readAsStringSync();
      final asked = RegExp(r'android\.permission\.health\.[A-Z_]+')
          .allMatches(manifest)
          .map((m) => m.group(0))
          .toSet();
      expect(asked, {'android.permission.health.READ_SLEEP'},
          reason: '多要的權限會一起出現在授權畫面上，受測者可能整組拒絕');
    });

    test('授權畫面需要的隱私頁：兩個入口都在（少了它授權畫面不出現，也不報錯）', () {
      final manifest = File('$dir/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE'));
      expect(manifest, contains('android.intent.action.VIEW_PERMISSION_USAGE'));
      expect(manifest, contains('android.intent.category.HEALTH_PERMISSIONS'));
      expect(manifest, contains('<package android:name="com.google.android.apps.healthdata"'));
    });

    test('往回讀幾天不寫在 Kotlin', () {
      final src = File('$dir/kotlin/com/example/app/HealthConnectService.kt').readAsStringSync();
      final code = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('*') && !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(RegExp(r'minusDays|minusHours|plusDays|Duration\.of|TimeUnit|ChronoUnit').hasMatch(code), isFalse);
      expect(RegExp(r'\b(72|4320|259200000)L?\b').hasMatch(code), isFalse);
    });
  });
}
