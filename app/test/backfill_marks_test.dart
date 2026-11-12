// 事後補的上床／下床時間（2026-11-12 定案）——儲存、換算、上傳。
//
// 守的是壞掉時不會報錯的地方：
// - 補的時間要標成 recalled，一路帶到後端；當下按的照舊是 tap
// - 換到下一晚時 kind 要跟著那一對搬進 pending，不能掉
// - 補的下床**不過**「比手機第一次被碰晚 2 小時」那條（使用者定），當下按的照過
// - 只補缺的那一個：昨晚當下按的上床不能被回想的蓋掉
// - 首頁的連結：早上 6 點前不出現；昨晚按齊就不出現
//
// ⚠️ 這個檔案刻意**沒有** testWidgets：只要有一條，全域 HttpClient 會被換成
//    一律回 400 的假實作，下面的假後端就收不到東西（見 CLAUDE.md）。
import 'dart:convert';
import 'dart:io';

import 'package:app/services/bed_marks.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/lights_out.dart';
import 'package:app/services/nightly_uploader.dart';
import 'package:app/services/pending_nightly.dart';
import 'package:app/services/user_identity.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime at(int day, int h, [int m = 0]) => DateTime(2026, 11, day, h, m);

class _Backend {
  late final HttpServer server;
  final List<Map<String, dynamic>> bodies = [];

  Future<String> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      bodies.add(body as Map<String, dynamic>);
      request.response.statusCode = 201;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'date': '2026-11-12'}));
      await request.response.close();
    });
    return 'http://127.0.0.1:${server.port}';
  }

  Future<void> stop() => server.close(force: true);
}

void main() {
  group('儲存', () {
    late InMemoryKeyValueStore kv;
    late BedMarkStore store;
    setUp(() {
      kv = InMemoryKeyValueStore();
      store = BedMarkStore(kv);
    });

    test('當下按的是 tap；I already got up 補的下床是 recalled', () async {
      await store.markStart(at(11, 23, 40));
      await store.markEnd(at(12, 7, 10), recalled: true);
      final m = await store.read(now: at(12, 9));
      expect(m.startKind, 'tap');
      expect(m.endKind, 'recalled');
    });

    test('⚠️ 換到下一晚：那一對連同 kind 搬進 pending', () async {
      await store.markStart(at(11, 23, 40));
      await store.markEnd(at(12, 7, 10), recalled: true);
      await store.markStart(at(12, 23, 50));
      final p = await store.readPending(now: at(13, 0));
      expect(p.endRecalled, isTrue);
      expect(p.startRecalled, isFalse);
      final cur = await store.read(now: at(13, 0));
      expect(cur.startRecalled, isFalse, reason: '今晚是當下按的');
    });

    test('上傳後清掉時 kind 一起清，免得下一晚被誤標成 recalled', () async {
      await store.markStart(at(11, 23, 40));
      await store.markEnd(at(12, 7, 10), recalled: true);
      await store.clear();
      await store.markStart(at(12, 23, 50));
      await store.markEnd(at(13, 7, 0));
      expect((await store.read(now: at(13, 9))).endKind, 'tap');
    });
  });

  group('首頁要不要出現「補昨晚」', () {
    late BedMarkStore store;
    setUp(() => store = BedMarkStore(InMemoryKeyValueStore()));

    test('從沒按過 → 出現；早上 6 點前 → 不出現', () async {
      expect(await store.needsBackfill(at(12, 9)), isTrue);
      expect(await store.needsBackfill(at(12, 5, 59)), isFalse);
    });

    test('昨晚只按了上床 → 出現；按齊 → 不出現', () async {
      await store.markStart(at(11, 23, 40));
      expect(await store.needsBackfill(at(12, 13)), isTrue);
      await store.markEnd(at(12, 7, 10));
      expect(await store.needsBackfill(at(12, 13)), isFalse);
    });

    test('⚠️ 上傳後槽被清掉，仍然記得昨晚按齊了', () async {
      await store.markStart(at(11, 23, 40));
      await store.markEnd(at(12, 7, 10));
      await store.clear();
      expect(await store.needsBackfill(at(12, 13)), isFalse);
    });

    test('紀錄是前天晚上的 → 當作昨晚沒按', () async {
      await store.markStart(at(10, 23, 40));
      await store.markEnd(at(11, 7, 10));
      expect(await store.needsBackfill(at(12, 9)), isTrue);
    });

    test('Cancel 掉的那次不算按過', () async {
      await store.markStart(at(11, 23, 40));
      await store.cancelStart();
      expect((await store.lastNight(at(12, 9))).startAt, isNull);
    });
  });

  group('補昨晚：只補缺的那一個', () {
    late BedMarkStore store;
    setUp(() => store = BedMarkStore(InMemoryKeyValueStore()));

    test('⚠️ 昨晚有按上床 → 上床照用當下按的（tap），只有下床是 recalled', () async {
      await store.markStart(at(11, 23, 40));
      await store.backfillLastNight(
        at(12, 13),
        start: at(11, 22, 0), // 轉盤上鎖住了，這個值不該被採用
        end: at(12, 7, 30),
      );
      final m = await store.read(now: at(12, 13));
      expect(m.startAt, at(11, 23, 40));
      expect(m.startKind, 'tap');
      expect(m.endKind, 'recalled');
      expect(await store.needsBackfill(at(12, 13)), isFalse);
    });

    test('昨晚都沒按 → 兩個都是 recalled', () async {
      await store.backfillLastNight(
        at(12, 13),
        start: at(11, 23, 30),
        end: at(12, 7, 30),
      );
      final m = await store.read(now: at(12, 13));
      expect(m.startKind, 'recalled');
      expect(m.endKind, 'recalled');
    });
  });

  group('換算與檢查', () {
    test('起床時刻跨午夜', () {
      expect(wakeAfter(at(11, 23, 40), 7, 10), at(12, 7, 10));
      expect(wakeAfter(at(12, 1, 0), 7, 0), at(12, 7, 0));
    });

    test('晚於現在、超過 14 小時、早於上床都擋', () {
      expect(recalledTimesProblem(at(11, 23), at(12, 7), at(12, 9)), isNull);
      expect(recalledTimesProblem(at(11, 23), at(12, 10), at(12, 9)), isNotNull);
      expect(recalledTimesProblem(at(11, 16), at(12, 7), at(12, 9)), isNotNull);
      expect(recalledTimesProblem(at(12, 7), at(12, 7), at(12, 9)), isNotNull);
    });
  });

  group('離線佇列', () {
    test('kind 存得進去、讀得回來；舊格式沒有 kind = tap', () {
      final n = PendingNight(
        '2026-11-12T00:10:00',
        marks: BedMarks(
          startAt: at(11, 23, 40),
          endAt: at(12, 7),
          endRecalled: true,
        ),
      );
      final back = PendingNight.fromJson(jsonDecode(jsonEncode(n.toJson())))!;
      expect(back.marks.endRecalled, isTrue);
      expect(back.marks.startRecalled, isFalse);
      final old = PendingNight.fromJson({
        'lights_out_at': '2026-11-12T00:10:00',
        'bed_start_at': at(11, 23, 40).toIso8601String(),
      })!;
      expect(old.marks.startKind, 'tap');
    });
  });

  group('上傳', () {
    late _Backend backend;
    late NightlyUploader uploader;
    setUp(() async {
      backend = _Backend();
      uploader = NightlyUploader(
        baseUrl: await backend.start(),
        identity: const BuildTimeUserIdentity(overrideId: 'test-user'),
      );
    });
    tearDown(() => backend.stop());

    // 00:10 放下手機、安靜 360 分鐘 → 06:10 第一次碰手機，寬限到 08:10。
    final lightsOut = LightsOutResult(
      LightsOutStatus.ok,
      at: at(12, 0, 10),
      quietMinutes: 360,
      sourceType: 'keyguard_shown',
      eventCount: 100,
    );

    test('送出 kind', () async {
      await uploader.upload(
        lightsOut,
        marks: BedMarks(startAt: at(11, 23, 40), endAt: at(12, 7, 0), endRecalled: true),
      );
      expect(backend.bodies.single['bed_start_kind'], 'tap');
      expect(backend.bodies.single['bed_end_kind'], 'recalled');
    });

    test('⚠️ 補的下床很晚也照送（不過 2 小時那條）', () async {
      await uploader.upload(
        lightsOut,
        marks: BedMarks(startAt: at(11, 23, 40), endAt: at(12, 11, 0), endRecalled: true),
      );
      expect(backend.bodies.single['bed_end_at'], isNotNull);
    });

    test('當下按的下床很晚 → 照舊不送下床（反面對照）', () async {
      await uploader.upload(
        lightsOut,
        marks: BedMarks(startAt: at(11, 23, 40), endAt: at(12, 11, 0)),
      );
      expect(backend.bodies.single.containsKey('bed_end_at'), isFalse);
      expect(backend.bodies.single['bed_start_kind'], 'tap');
    });
  });
}
