// 把偵測到的就寢時刻送去後端 POST /nightly。
//
// 這一組守三件事：
//
//   1. **每一種「沒上傳」的原因都要分得開。** 沒設定後端／沒設定身分／
//      那晚偵測不到——三者在畫面上要講不同的話，解法也完全不同。
//      混成一個 false 的話，demo 當場沒人知道要去修哪裡。
//
//   2. **達成度不是 Dart 算的。** 回應裡的 adherence_minutes 原樣帶出來，
//      這裡不做任何換算。跨午夜正規化在 behavior/adherence.py。
//
//   3. **送出去的 body 不含 target_bedtime。** 那個欄位是後端留給
//      「補填歷史夜晚」的：當晚的目標可能與現在不同，nightly_behavior
//      存的是當晚的快照。從 App 每天傳等於天天覆寫那個快照。
//
// 用一個真的 HttpServer 起在 127.0.0.1，因為要驗的正是「送出去的東西
// 長什麼樣」——用假的 client 就等於在測自己寫的假物件。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/lights_out.dart';
import 'package:app/services/nightly_uploader.dart';
import 'package:app/services/user_identity.dart';

const String testUserId = '00000000-5017-4e01-9a30-000000000001';

LightsOutResult detected(DateTime at) => LightsOutResult(
      LightsOutStatus.ok,
      at: at,
      quietMinutes: 248,
      sourceType: 'keyguard_shown',
      eventCount: 443,
    );

/// 收下請求、記錄下來、回一個固定的回應。
class _FakeBackend {
  late final HttpServer server;
  final List<Map<String, dynamic>> received = [];
  int statusCode = 201;
  Map<String, dynamic> response = const {
    'date': '2026-09-01',
    'target_bedtime': '23:30',
    'lights_out_at': '2026-09-01T03:51:16',
    'adherence_minutes': 261.0,
    'is_late': true,
    'source': 'phone',
  };

  Future<String> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      received.add({
        'path': request.uri.path,
        'method': request.method,
        'body': jsonDecode(body),
      });
      request.response.statusCode = statusCode;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    return 'http://127.0.0.1:${server.port}';
  }

  Future<void> stop() => server.close(force: true);
}

void main() {
  group('不上傳的三種原因要分得開', () {
    test('沒設定後端 → noBackend', () async {
      const uploader = NightlyUploader(
        baseUrl: '',
        identity: BuildTimeUserIdentity(overrideId: testUserId),
      );
      final result = await uploader.upload(detected(DateTime(2026, 9, 1, 3, 51)));
      expect(result.status, NightlyUploadStatus.noBackend);
    });

    test('沒設定身分 → noUser（而不是安靜地不做事）', () async {
      const uploader = NightlyUploader(
        baseUrl: 'http://127.0.0.1:1',
        identity: BuildTimeUserIdentity(overrideId: ''),
      );
      final result = await uploader.upload(detected(DateTime(2026, 9, 1, 3, 51)));
      expect(
        result.status,
        NightlyUploadStatus.noUser,
        reason: '這支 build 少了 --dart-define=SONNAP_USER_ID，要講得出來才修得掉',
      );
    });

    test('那晚偵測不到 → nothingDetected，而且不會發出請求', () async {
      final backend = _FakeBackend();
      final baseUrl = await backend.start();
      addTearDown(backend.stop);

      final uploader = NightlyUploader(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      );
      final result = await uploader.upload(
        const LightsOutResult(LightsOutStatus.noQuietGap, quietMinutes: 147),
      );

      expect(result.status, NightlyUploadStatus.nothingDetected);
      expect(
        backend.received,
        isEmpty,
        reason: '絕對不能補一個預設時刻送出去。後端對空的 lights_out_at '
            '明確回 400——「沒量到」與「準時」是兩件事',
      );
    });
  });

  group('送出去的內容', () {
    late _FakeBackend backend;
    late String baseUrl;

    setUp(() async {
      backend = _FakeBackend();
      baseUrl = await backend.start();
    });
    tearDown(() => backend.stop());

    test('POST /nightly，帶 user_id 與 ISO8601 的 lights_out_at', () async {
      final uploader = NightlyUploader(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      );
      await uploader.upload(detected(DateTime(2026, 9, 1, 3, 51, 16)));

      expect(backend.received, hasLength(1));
      final call = backend.received.single;
      expect(call['method'], 'POST');
      expect(call['path'], '/nightly');

      final body = call['body'] as Map<String, dynamic>;
      expect(body['user_id'], testUserId);
      expect(body['source'], 'phone');
      expect(body['lights_out_at'], startsWith('2026-09-01T03:51:16'));
    });

    test('不得帶 target_bedtime', () async {
      final uploader = NightlyUploader(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      );
      await uploader.upload(detected(DateTime(2026, 9, 1, 3, 51)));

      final body = backend.received.single['body'] as Map<String, dynamic>;
      expect(
        body.containsKey('target_bedtime'),
        isFalse,
        reason: 'nightly_behavior 存的是當晚的快照——使用者改目標不該追溯性地'
            '改寫歷史達成度。那個欄位是留給補填歷史夜晚的',
      );
    });

    test('送出去的時刻不是 UTC', () async {
      // behavior/adherence.py 拿牆鐘時間跟 "23:30" 這種本地目標比。
      // 送 UTC 過去，就寢達成度會整整差掉一個時區。
      final uploader = NightlyUploader(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      );
      await uploader.upload(detected(DateTime(2026, 9, 1, 3, 51)));

      final body = backend.received.single['body'] as Map<String, dynamic>;
      expect((body['lights_out_at'] as String).endsWith('Z'), isFalse);
    });
  });

  group('回應原樣帶出來，不在 Dart 重算', () {
    test('adherence_minutes / is_late / date 照抄', () async {
      final backend = _FakeBackend();
      final baseUrl = await backend.start();
      addTearDown(backend.stop);

      final uploader = NightlyUploader(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      );
      final result = await uploader.upload(detected(DateTime(2026, 9, 1, 3, 51)));

      expect(result.status, NightlyUploadStatus.ok);
      expect(result.date, '2026-09-01');
      expect(result.isLate, isTrue);
      expect(
        result.adherenceMinutes,
        261,
        reason: '261 是後端算的（目標 23:30 → 實際 03:51，跨午夜）。'
            'Dart 若自己相減會得到 −1179，也就是「提早 19 小時」',
      );
    });

    test('後端回錯就是 failed，不假裝成功', () async {
      final backend = _FakeBackend();
      final baseUrl = await backend.start();
      addTearDown(backend.stop);
      backend.statusCode = 404; // user_id 不存在

      final uploader = NightlyUploader(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      );
      final result = await uploader.upload(detected(DateTime(2026, 9, 1, 3, 51)));

      expect(result.status, NightlyUploadStatus.failed);
      expect(result.error, contains('404'));
      expect(result.adherenceMinutes, isNull);
    });

    test('連不上不會拋例外，只回 failed', () async {
      // 上傳失敗不該讓整頁掛掉——就寢時刻已經算出來了。
      const uploader = NightlyUploader(
        baseUrl: 'http://127.0.0.1:1',
        identity: BuildTimeUserIdentity(overrideId: testUserId),
        timeout: Duration(milliseconds: 300),
      );
      final result = await uploader.upload(detected(DateTime(2026, 9, 1, 3, 51)));
      expect(result.status, NightlyUploadStatus.failed);
    });
  });

  group('建置參數', () {
    test('沒給 API base 就不建 uploader', () {
      expect(buildNightlyUploader(baseUrlOverride: ''), isNull);
    });

    test('有 API base、沒有 user id 也要建得出來', () {
      // 「後端沒開」與「這支 build 沒設定身分」是兩個不同的問題。
      // 這裡回 null 的話，第二種永遠不會被講出來。
      final uploader = buildNightlyUploader(
        baseUrlOverride: 'http://127.0.0.1:8000',
        userIdOverride: '',
      );
      expect(uploader, isNotNull);
    });
  });
}
