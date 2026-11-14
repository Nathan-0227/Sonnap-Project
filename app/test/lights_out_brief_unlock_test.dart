// 就寢偵測第 4 條規則（2026-11-15 使用者定）：半夜看一下時間的短解鎖（< 30 秒）可以跨過去，
// **只在原本的規則找不到 ≥ 3 小時的安靜期時才用**。跨了幾次跟著上傳（bridged_unlocks），只供分析。
//
// 實例 11-12：05:43 放下手機、07:20 解鎖 4 秒看時間、09:28 起床——97＋128 分鐘，原本整晚偵測不到。
import 'dart:convert';
import 'dart:io';

import 'package:app/services/key_value_store.dart';
import 'package:app/services/lights_out.dart';
import 'package:app/services/nightly_uploader.dart';
import 'package:app/services/pending_nightly.dart';
import 'package:app/services/user_identity.dart';
import 'package:flutter_test/flutter_test.dart';

/// 視窗：11-11 12:00 → 11-12 12:00（同補傳版用的那個視窗）
final DateTime d0 = DateTime(2026, 11, 11);
final DateTime d1 = DateTime(2026, 11, 12);

/// 一次使用：解鎖 → [seconds] 秒後螢幕關 → 0.7 秒後上鎖（實機上一次解鎖就長這樣）。
List<InteractionEvent> use(DateTime start, int seconds) {
  final off = start.add(Duration(seconds: seconds));
  return [
    InteractionEvent(timestamp: start, type: 'keyguard_hidden', packageName: 'x'),
    InteractionEvent(timestamp: off, type: 'screen_off', packageName: 'x'),
    InteractionEvent(
      timestamp: off.add(const Duration(milliseconds: 700)),
      type: 'keyguard_shown',
      packageName: 'x',
    ),
  ];
}

DateTime t(DateTime day, int h, int m, [int s = 0]) =>
    DateTime(day.year, day.month, day.day, h, m, s);

/// 白天到半夜每 2 小時用一次手機（都不到 3 小時，不會被當成就寢）
List<InteractionEvent> evening() => [
  for (final h in [13, 15, 17, 19, 21, 23]) ...use(t(d0, h, 0), 120),
  for (final h in [1, 3]) ...use(t(d1, h, 0), 120),
  ...use(t(d1, 5, 31, 14), 60),
];

LightsOutResult run(List<InteractionEvent> events) => detectLightsOut(
  events,
  windowStart: t(d0, 12, 0),
  windowEnd: t(d1, 12, 0),
);

void main() {
  group('第 4 條規則：跨過半夜的短解鎖', () {
    test('11-12 那一晚：跨過 07:20 那 4 秒 → 05:43 就寢、跨 1 次', () {
      final r = run([
        ...evening(),
        ...use(t(d1, 5, 42, 30), 39), // 睡前最後一次使用，05:43:09 結束
        ...use(t(d1, 7, 20, 11), 4), // 看時間
        ...use(t(d1, 9, 28, 14), 600), // 起床
      ]);
      expect(r.status, LightsOutStatus.ok);
      expect(r.at, t(d1, 5, 43, 9).add(const Duration(milliseconds: 700)));
      expect(
        r.bridgedUnlocks,
        1,
        reason: '一次解鎖在事件流上是 screen_off＋0.7 秒後的 keyguard_shown，要併成一次，不是兩次',
      );
      expect(r.quietMinutes, greaterThanOrEqualTo(kMinQuietMinutes));
    });

    test('⚠️ 只是 fallback：原本就偵測得到的晚上，答案一模一樣、跨 0 次', () {
      // 01:00 放下、03:00 看 4 秒、08:00 起床：03:00→08:00 本來就有 5 小時
      final r = run([
        for (final h in [13, 15, 17, 19, 21, 23]) ...use(t(d0, h, 0), 120),
        ...use(t(d1, 0, 50), 600),
        ...use(t(d1, 3, 0), 4),
        ...use(t(d1, 8, 0), 600),
      ]);
      expect(r.status, LightsOutStatus.ok);
      expect(
        r.at,
        t(d1, 3, 0, 4).add(const Duration(milliseconds: 700)),
        reason: '原本的規則挑 03:00 那段（5 小時）；新規則不能把它改成 01:00',
      );
      expect(r.bridgedUnlocks, 0);
    });

    test('30 秒以上的使用不跨（回訊息不算看一下時間）', () {
      final r = run([
        ...evening(),
        ...use(t(d1, 5, 42, 30), 39),
        ...use(t(d1, 7, 20, 11), 40),
        ...use(t(d1, 9, 28, 14), 600),
      ]);
      expect(r.status, LightsOutStatus.noQuietGap);
      expect(r.bridgedUnlocks, 0);
    });

    test('可以跨好幾次（每次都 < 30 秒）', () {
      final r = run([
        ...evening(),
        ...use(t(d1, 5, 42, 30), 39),
        ...use(t(d1, 6, 30), 5),
        ...use(t(d1, 7, 20), 8),
        ...use(t(d1, 8, 50), 600),
      ]);
      expect(r.status, LightsOutStatus.ok);
      expect(r.bridgedUnlocks, 2);
      expect(r.at!.hour, 5);
      expect(r.at!.minute, 43);
    });

    test('跨完還是不到 3 小時 → 仍然偵測不到，不硬挑', () {
      final r = run([
        ...evening(),
        ...use(t(d1, 5, 42, 30), 39),
        ...use(t(d1, 7, 20, 11), 4),
        ...use(t(d1, 8, 0), 600),
      ]);
      expect(r.status, LightsOutStatus.noQuietGap);
    });

    test('睡前 5 秒看一下鬧鐘不會把就寢時刻往前拉（挑跨最少次的那段）', () {
      final r = run([
        ...evening(),
        ...use(t(d1, 5, 42, 30), 39), // 05:43 放下
        ...use(t(d1, 6, 0), 5), // 06:00 看鬧鐘（睡前最後一次）
        ...use(t(d1, 7, 30), 4), // 半夜看時間
        ...use(t(d1, 9, 10), 600), // 起床
      ]);
      // 05:43 起跨 2 次＝207 分；06:00 起跨 1 次＝190 分，兩段都過 3 小時 → 挑跨 1 次那段
      expect(r.status, LightsOutStatus.ok);
      expect(r.at, t(d1, 6, 0, 5).add(const Duration(milliseconds: 700)));
      expect(r.bridgedUnlocks, 1);
    });

    test('activity 模式（手機不給解鎖事件）不跨', () {
      // 同 11-12，但只有前景切換事件
      List<InteractionEvent> act(DateTime s, int sec) => [
        InteractionEvent(timestamp: s, type: 'resumed', packageName: 'x'),
        InteractionEvent(
          timestamp: s.add(Duration(seconds: sec)),
          type: 'paused',
          packageName: 'x',
        ),
      ];
      final r = run([
        for (final h in [13, 15, 17, 19, 21, 23]) ...act(t(d0, h, 0), 120),
        for (final h in [1, 3]) ...act(t(d1, h, 0), 120),
        ...act(t(d1, 5, 42, 30), 39),
        ...act(t(d1, 7, 20, 11), 4),
        ...act(t(d1, 9, 28, 14), 600),
      ]);
      expect(r.mode, LightsOutMode.activity);
      expect(r.status, LightsOutStatus.noQuietGap);
    });
  });

  group('跨了幾次跟著上傳', () {
    late HttpServer server;
    late List<Map<String, dynamic>> bodies;
    HttpOverrides? saved;
    setUp(() async {
      saved = HttpOverrides.current;
      HttpOverrides.global = null;
      bodies = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final body =
            jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
        bodies.add(body);
        req.response.statusCode = 201;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'date': (body['lights_out_at'] as String).substring(0, 10),
          'adherence_minutes': 103.2,
          'is_late': true,
        }));
        await req.response.close();
      });
    });
    tearDown(() async {
      await server.close(force: true);
      HttpOverrides.global = saved;
    });

    NightlyUploader uploader({PendingNightlyStore? pending}) => NightlyUploader(
      baseUrl: 'http://127.0.0.1:${server.port}',
      identity: const BuildTimeUserIdentity(overrideId: 'stub'),
      pending: pending,
    );

    test('送 bridged_unlocks（1 就是 1，0 就是 0）', () async {
      await uploader().upload(
        LightsOutResult(
          LightsOutStatus.ok,
          at: t(d1, 5, 43, 10),
          bridgedUnlocks: 1,
        ),
      );
      await uploader().upload(
        LightsOutResult(LightsOutStatus.ok, at: t(d1, 3, 3, 22)),
      );
      expect(bodies[0]['bridged_unlocks'], 1);
      expect(bodies[1]['bridged_unlocks'], 0);
    });

    test('佇列裡的舊格式（沒有這個欄位）補送時不帶——後端存 NULL＝不知道，不是 0', () async {
      final store = InMemoryKeyValueStore();
      await PendingNightlyStore(store).save([
        const PendingNight('2026-11-10T02:00:00.000'),
      ]);
      await uploader(pending: PendingNightlyStore(store)).sync(
        const LightsOutResult(LightsOutStatus.noQuietGap),
      );
      expect(bodies.single.containsKey('bridged_unlocks'), isFalse);
    });

    test('佇列存得住、讀得回 bridged_unlocks', () {
      final n = PendingNight('2026-11-12T05:43:10.055', bridgedUnlocks: 1);
      final back = PendingNight.fromJson(jsonDecode(jsonEncode(n.toJson())))!;
      expect(back.bridgedUnlocks, 1);
      expect(
        PendingNight.fromJson({'lights_out_at': '2026-11-12T05:43:10'})!.bridgedUnlocks,
        isNull,
      );
    });
  });
}
