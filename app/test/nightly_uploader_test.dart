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

import 'package:app/services/bed_marks.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/lights_out.dart';
import 'package:app/services/nightly_uploader.dart';
import 'package:app/services/pending_nightly.dart';
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

  /// 若非 null，回應由它依請求內容產生——補送測試要靠這個分辨
  /// 「這一份結果講的是哪一晚」。
  Map<String, dynamic> Function(Map<String, dynamic> body)? responder;

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
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      request.response.statusCode = statusCode;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(responder?.call(decoded) ?? response));
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

    test('⚠️ 按太晚的「下床」不送，但上床照送', () async {
      // 2026-09-08 實測：08:20 起床、12:11 才想起來按。照送上去，後端會
      // 算出多 3 小時 51 分的臥床時間，而且那段時間的手機使用會被算成
      // 「躺床上滑手機」——效率與臥床時間兩個都錯，而且錯得很合理。
      //
      // ⚠️ 只丟掉 end。start 仍然是有效的自述，丟掉它等於懲罰使用者忘記按。
      final uploader = NightlyUploader(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      );
      await uploader.upload(
        // 安靜期 02:30 起 248 分鐘 → 手機第一次被碰是 06:38
        LightsOutResult(
          LightsOutStatus.ok,
          at: DateTime(2026, 9, 8, 2, 30),
          quietMinutes: 248,
          sourceType: 'keyguard_shown',
          eventCount: 443,
        ),
        marks: BedMarks(
          startAt: DateTime(2026, 9, 8, 1, 53),
          endAt: DateTime(2026, 9, 8, 12, 11),
        ),
      );

      final body = backend.received.single['body'] as Map<String, dynamic>;
      expect(body.containsKey('bed_end_at'), isFalse,
          reason: '算不出效率，好過算出一個錯的效率');
      expect(body['bed_start_at'], isNotNull,
          reason: '上床那一半仍然有效——丟掉它等於懲罰使用者忘記按');
    });

    test('⚠️ 後端丟掉標記時，marksStored 要是 false', () async {
      // 2026-09-10 掉了一次資料的根因：`main.py` 的 same_night 在夜份不符時
      // **靜靜丟掉整組標記，但仍然回 201**。App 看到 201 就清掉本機標記，
      // 而後端一列都沒存——「成功了但什麼都沒做」。
      //
      // 假後端回的固定 body 不含 bed_start_at（等同後端丟掉的情形）。
      final uploader = NightlyUploader(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      );
      final result = await uploader.upload(
        detected(DateTime(2026, 9, 1, 3, 51)),
        marks: BedMarks(
          startAt: DateTime(2026, 9, 1, 2, 0),
          endAt: DateTime(2026, 9, 1, 8, 0),
        ),
      );

      expect(result.status, NightlyUploadStatus.ok);
      expect(result.marksStored, isFalse,
          reason: '回應裡沒有 bed_start_at = 後端沒收下；'
              '這時清掉本機標記就會把那一晚弄丟');
    });

    test('反向對照：按得及時的「下床」照送', () async {
      // 沒有這一條，把 bed_end_at 無條件拿掉也會讓上一條通過。
      final uploader = NightlyUploader(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      );
      await uploader.upload(
        LightsOutResult(
          LightsOutStatus.ok,
          at: DateTime(2026, 9, 8, 2, 30),
          quietMinutes: 248,
          sourceType: 'keyguard_shown',
          eventCount: 443,
        ),
        marks: BedMarks(
          startAt: DateTime(2026, 9, 8, 1, 53),
          endAt: DateTime(2026, 9, 8, 7, 5),   // 手機被碰之後半小時
        ),
      );

      final body = backend.received.single['body'] as Map<String, dynamic>;
      expect(body['bed_end_at'], isNotNull);
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

  // ================================================================
  // 離線上傳佇列（B1.0）
  // ================================================================
  //
  // ⚠️ 這一組守的是一個「壞掉不會報錯」的機制。沒有它的時候，受測者早上
  //    開 App 連不到後端，那一晚就**永久消失**——而畫面上什麼都不會說，
  //    因為就寢時刻明明算出來了、也顯示了。
  //
  //    偵測視窗是往回 24 小時的滑動視窗（lights_out.dart 的
  //    kLightsOutWindow），所以「隔天再開一次 App」救不回來：
  //    隔天的視窗裡已經沒有昨晚那一段了。

  group('離線佇列：失敗要留下來', () {
    test('連不上 → 那一晚存進手機，下次補得回來', () async {
      final store = InMemoryKeyValueStore();
      final uploader = NightlyUploader(
        baseUrl: 'http://127.0.0.1:1',
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
        timeout: const Duration(milliseconds: 300),
        pending: PendingNightlyStore(store),
      );

      final batch = await uploader.sync(detected(DateTime(2026, 9, 1, 3, 51, 16)));

      expect(batch.current.status, NightlyUploadStatus.failed);
      expect(batch.stillPending, 1);
      final saved = await PendingNightlyStore(store).load();
      expect(saved, hasLength(1));
      expect(
        saved.single.lightsOutIso,
        startsWith('2026-09-01T03:51:16'),
        reason: '存的是 lights_out_at 本身。達成度那三個欄位刻意不存——'
            '那是後端算的，存下來就有第二個定義處',
      );
    });

    test('還沒建帳號 → 也要留（跳過註冊之後補得回來）', () async {
      final store = InMemoryKeyValueStore();
      final uploader = NightlyUploader(
        baseUrl: 'http://127.0.0.1:1',
        identity: const BuildTimeUserIdentity(overrideId: ''),
        pending: PendingNightlyStore(store),
      );

      final batch = await uploader.sync(detected(DateTime(2026, 9, 1, 3, 51)));

      expect(batch.current.status, NightlyUploadStatus.noUser);
      expect(
        await PendingNightlyStore(store).load(),
        hasLength(1),
        reason: '跳過註冊刻意不寫進儲存，所以之後一定會再問一次。'
            '那時候這幾晚要補得回來',
      );
    });

    test('那晚偵測不到 → 沒有東西可留，佇列不動', () async {
      final store = InMemoryKeyValueStore();
      final uploader = NightlyUploader(
        baseUrl: 'http://127.0.0.1:1',
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
        timeout: const Duration(milliseconds: 300),
        pending: PendingNightlyStore(store),
      );

      final batch = await uploader.sync(
        const LightsOutResult(LightsOutStatus.noQuietGap, quietMinutes: 147),
      );

      expect(batch.current.status, NightlyUploadStatus.nothingDetected);
      expect(await PendingNightlyStore(store).load(), isEmpty);
    });
  });

  group('離線佇列：成功要清掉', () {
    late _FakeBackend backend;
    late String baseUrl;

    setUp(() async {
      backend = _FakeBackend();
      baseUrl = await backend.start();
    });
    tearDown(() => backend.stop());

    test('補送成功之後佇列要空，不能每天重送', () async {
      final store = InMemoryKeyValueStore();
      await PendingNightlyStore(store).save([
        const PendingNight('2026-08-30T02:10:00.000'),
        const PendingNight('2026-08-31T01:05:00.000'),
      ]);

      final uploader = NightlyUploader(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
        pending: PendingNightlyStore(store),
      );
      final batch = await uploader.sync(detected(DateTime(2026, 9, 1, 3, 51)));

      expect(batch.replayed, hasLength(2));
      expect(batch.current.status, NightlyUploadStatus.ok);
      expect(batch.stillPending, 0);
      expect(
        await PendingNightlyStore(store).load(),
        isEmpty,
        reason: '送成功還留著的話，每天早上都會重送一次同一批',
      );
    });

    test('先補舊的、再送今晚——畫面顯示的要是最新那一份', () async {
      final store = InMemoryKeyValueStore();
      await PendingNightlyStore(store).save([const PendingNight('2026-08-30T02:10:00.000')]);

      backend.responder = (body) => {
            'date': (body['lights_out_at'] as String).substring(0, 10),
            'adherence_minutes': 10.0,
            'is_late': true,
          };

      final uploader = NightlyUploader(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
        pending: PendingNightlyStore(store),
      );
      final batch = await uploader.sync(detected(DateTime(2026, 9, 1, 3, 51)));

      expect(
        backend.received.map((r) => (r['body'] as Map)['lights_out_at']).toList(),
        [startsWith('2026-08-30'), startsWith('2026-09-01')],
        reason: '順序反了的話，畫面上那一行講的會是三天前那一晚',
      );
      expect(batch.current.date, '2026-09-01');
      expect(batch.replayed.single.date, '2026-08-30');
    });

    test('補回來的舊夜晚不混進 current——那才是「不重複計算」', () async {
      final store = InMemoryKeyValueStore();
      await PendingNightlyStore(store).save([
        const PendingNight('2026-08-30T02:10:00.000'),
        const PendingNight('2026-08-31T01:05:00.000'),
      ]);
      backend.responder = (body) => {
            'date': (body['lights_out_at'] as String).substring(0, 10),
            'adherence_minutes': 99.0,
            'is_late': true,
          };

      final uploader = NightlyUploader(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
        pending: PendingNightlyStore(store),
      );
      final batch = await uploader.sync(detected(DateTime(2026, 9, 1, 3, 51)));

      expect(batch.current.date, '2026-09-01');
      expect(
        batch.replayed.map((r) => r.date),
        ['2026-08-30', '2026-08-31'],
        reason: 'current 與 replayed 混在一起的話，使用者早上看到的達成度'
            '會是別天的，而畫面上完全看不出來',
      );
    });
  });

  group('離線佇列：補送不得重複計算', () {
    test('今晚那一筆已經在佇列裡 → 只送一次', () async {
      // 24 小時的視窗連續兩天會算出**同一個時刻**。昨天送失敗存了起來，
      // 今天又偵測到同一筆——不去重的話這一晚會被送兩次、算兩次。
      final backend = _FakeBackend();
      final baseUrl = await backend.start();
      addTearDown(backend.stop);

      final store = InMemoryKeyValueStore();
      final sameNight = DateTime(2026, 9, 1, 3, 51, 16);
      await PendingNightlyStore(store).save([PendingNight(sameNight.toIso8601String())]);

      final uploader = NightlyUploader(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
        pending: PendingNightlyStore(store),
      );
      final batch = await uploader.sync(detected(sameNight));

      expect(backend.received, hasLength(1));
      expect(batch.replayed, isEmpty);
      expect(batch.current.status, NightlyUploadStatus.ok);
    });

    test('同一晚存兩次也只留一筆', () async {
      final store = InMemoryKeyValueStore();
      final queue = PendingNightlyStore(store);
      await queue.save(const [
        PendingNight('2026-09-01T03:51:16.000'),
        PendingNight('2026-09-01T03:51:16.000'),
        PendingNight('2026-08-31T01:05:00.000'),
      ]);
      expect(await queue.load(), hasLength(2));
    });

    test('佇列有上限，不會無限長下去', () async {
      final store = InMemoryKeyValueStore();
      final queue = PendingNightlyStore(store);
      final many = List.generate(
        PendingNightlyStore.maxEntries + 5,
        (i) => PendingNight(
            DateTime(2026, 8, 1).add(Duration(days: i)).toIso8601String()),
      );
      await queue.save(many);

      final saved = await queue.load();
      expect(saved, hasLength(PendingNightlyStore.maxEntries));
      expect(
        saved.last.lightsOutIso,
        many.last.lightsOutIso,
        reason: '滿了要丟最舊的，不是丟最新的——最新那晚才是使用者剛量到的',
      );
    });

    test('儲存壞掉當成空的，不拋例外', () async {
      final store = InMemoryKeyValueStore({
        PendingNightlyStore.storageKey: 'not json at all',
      });
      expect(await PendingNightlyStore(store).load(), isEmpty);
    });
  });

  group('離線佇列：上床標記要跟著一起存', () {
    // ⚠️ 少了這一段，補送回去的夜晚會缺臥床時間與行為版效率——
    //    使用者明明按了按鈕，資料卻在補送的過程中掉了，而畫面上
    //    不會有任何跡象。

    BedMarks marksAt(DateTime start, DateTime end) =>
        BedMarks(startAt: start, endAt: end);

    test('上傳失敗時，標記跟著那一晚一起存進佇列', () async {
      final store = InMemoryKeyValueStore();
      final uploader = NightlyUploader(
        baseUrl: 'http://127.0.0.1:1',
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
        timeout: const Duration(milliseconds: 300),
        pending: PendingNightlyStore(store),
      );

      final batch = await uploader.sync(
        detected(DateTime(2026, 9, 1, 3, 51)),
        marks: marksAt(DateTime(2026, 8, 31, 23, 40), DateTime(2026, 9, 1, 8, 5)),
      );

      expect(batch.currentQueued, isTrue);
      final saved = (await PendingNightlyStore(store).load()).single;
      expect(saved.marks.isComplete, isTrue);
      expect(saved.marks.startIso, startsWith('2026-08-31T23:40'));
      expect(saved.marks.endIso, startsWith('2026-09-01T08:05'));
    });

    test('補送帶的是**那一晚自己的**標記，不是現在手機裡的那一組', () async {
      // 拿今天的標記去補三天前那一晚，算出來的臥床時間是假的。
      final backend = _FakeBackend();
      final baseUrl = await backend.start();
      addTearDown(backend.stop);

      final store = InMemoryKeyValueStore();
      await PendingNightlyStore(store).save([
        PendingNight(
          '2026-08-30T02:10:00.000',
          marks: marksAt(DateTime(2026, 8, 29, 23, 0), DateTime(2026, 8, 30, 7, 0)),
        ),
      ]);

      final uploader = NightlyUploader(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
        pending: PendingNightlyStore(store),
      );
      await uploader.sync(
        detected(DateTime(2026, 9, 1, 3, 51)),
        marks: marksAt(DateTime(2026, 8, 31, 23, 40), DateTime(2026, 9, 1, 8, 5)),
      );

      final bodies = backend.received
          .map((r) => r['body'] as Map<String, dynamic>)
          .toList();
      expect(bodies, hasLength(2));
      expect(
        bodies.first['bed_start_at'],
        startsWith('2026-08-29T23:00'),
        reason: '補送那一筆要用它自己存下來的標記',
      );
      expect(bodies.last['bed_start_at'], startsWith('2026-08-31T23:40'));
    });

    test('沒按按鈕的夜晚照樣進佇列，只是沒有標記', () async {
      final store = InMemoryKeyValueStore();
      final uploader = NightlyUploader(
        baseUrl: 'http://127.0.0.1:1',
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
        timeout: const Duration(milliseconds: 300),
        pending: PendingNightlyStore(store),
      );

      await uploader.sync(detected(DateTime(2026, 9, 1, 3, 51)));

      final saved = (await PendingNightlyStore(store).load()).single;
      expect(saved.lightsOutIso, isNotEmpty);
      expect(
        saved.marks.hasStart,
        isFalse,
        reason: '忘記按按鈕只該少掉臥床時間，不該讓整晚補送不了',
      );
    });

    test('同一晚存兩次，留下**後面**那筆（標記比較新）', () async {
      // 使用者可能在第二次開 App 之前才按下「下床」。
      final store = InMemoryKeyValueStore();
      final queue = PendingNightlyStore(store);
      await queue.save([
        const PendingNight('2026-09-01T03:51:16.000'),
        PendingNight(
          '2026-09-01T03:51:16.000',
          marks: marksAt(DateTime(2026, 8, 31, 23, 40), DateTime(2026, 9, 1, 8, 5)),
        ),
      ]);

      final saved = await queue.load();
      expect(saved, hasLength(1));
      expect(saved.single.marks.isComplete, isTrue);
    });

    test('舊格式（只有一個字串）也讀得回來', () async {
      // 這個佇列存在使用者的手機上，換格式時舊資料還在——
      // 直接丟掉就等於把那幾晚弄丟一次。
      final store = InMemoryKeyValueStore({
        PendingNightlyStore.storageKey:
            '["2026-08-30T02:10:00.000","2026-08-31T01:05:00.000"]',
      });
      final saved = await PendingNightlyStore(store).load();
      expect(saved, hasLength(2));
      expect(saved.first.lightsOutIso, '2026-08-30T02:10:00.000');
      expect(saved.first.marks.hasStart, isFalse);
    });
  });

  group('離線佇列 × 按太晚的下床：濾在存進佇列**之前**', () {
    // ⚠️ 這一組守的是合併兩個功能時才出現的問題。
    //
    //    判準 bedEndIsPlausible() 要 lights_out_at 與 quietMinutes 兩個
    //    輸入，而**佇列裡只存前者**——補送的時候已經沒有材料重算了。
    //    所以濾的動作必須在存進佇列之前做一次，兩邊共用同一組結果。
    //    放在送出那一刻的話，今晚那一筆判得出來、補送那幾筆判不出來，
    //    同一個規則對不同夜晚有不同結果，而且不會有任何錯誤訊息。

    /// 安靜期 08:00 結束（= 手機第一次被碰），寬限兩小時 → 10:00 為界。
    LightsOutResult night() => LightsOutResult(
          LightsOutStatus.ok,
          at: DateTime(2026, 9, 8, 0, 0),
          quietMinutes: 480,
          sourceType: 'keyguard_shown',
          eventCount: 400,
        );

    test('按太晚的 end 不會被存進佇列', () async {
      final store = InMemoryKeyValueStore();
      final uploader = NightlyUploader(
        baseUrl: 'http://127.0.0.1:1',
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
        timeout: const Duration(milliseconds: 300),
        pending: PendingNightlyStore(store),
      );

      await uploader.sync(
        night(),
        marks: BedMarks(
          startAt: DateTime(2026, 9, 7, 23, 40),
          endAt: DateTime(2026, 9, 8, 12, 11), // 08:20 起床、12:11 才想起來按
        ),
      );

      final saved = (await PendingNightlyStore(store).load()).single;
      expect(
        saved.marks.endAt,
        isNull,
        reason: '存進去的話，補送成功時就會算出一個多三個多小時的臥床時間——'
            '而且錯得看起來完全合理',
      );
      expect(
        saved.marks.hasStart,
        isTrue,
        reason: '只丟 end，start 照留。丟掉整組等於懲罰使用者忘記按',
      );
    });

    test('反向對照：按得及時的 end 照樣存進佇列', () async {
      // 沒有這一條的話，「無條件丟掉 end」也會讓上面那條通過。
      final store = InMemoryKeyValueStore();
      final uploader = NightlyUploader(
        baseUrl: 'http://127.0.0.1:1',
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
        timeout: const Duration(milliseconds: 300),
        pending: PendingNightlyStore(store),
      );

      await uploader.sync(
        night(),
        marks: BedMarks(
          startAt: DateTime(2026, 9, 7, 23, 40),
          endAt: DateTime(2026, 9, 8, 8, 25), // 起床後五分鐘按的
        ),
      );

      final saved = (await PendingNightlyStore(store).load()).single;
      expect(saved.marks.isComplete, isTrue);
    });

    test('送出去的與存起來的是同一組', () async {
      // 分兩次算的話，兩者有可能不一樣，而那種不一致只會在補送成功
      // 之後才看得到。
      final backend = _FakeBackend();
      final baseUrl = await backend.start();
      addTearDown(backend.stop);
      backend.statusCode = 500; // 送得出去但失敗 → 會進佇列

      final store = InMemoryKeyValueStore();
      final uploader = NightlyUploader(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
        pending: PendingNightlyStore(store),
      );

      await uploader.sync(
        night(),
        marks: BedMarks(
          startAt: DateTime(2026, 9, 7, 23, 40),
          endAt: DateTime(2026, 9, 8, 12, 11),
        ),
      );

      final sent = backend.received.single['body'] as Map<String, dynamic>;
      final saved = (await PendingNightlyStore(store).load()).single;
      expect(sent.containsKey('bed_end_at'), isFalse);
      expect(saved.marks.endAt, isNull);
      expect(sent['bed_start_at'], startsWith('2026-09-07T23:40'));
      expect(saved.marks.startIso, startsWith('2026-09-07T23:40'));
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
