// 好友頁「用了哪些設備」的手機名字（2026-11-16 使用者定）：
// 型號代碼換成好讀的名字；表裡沒有的照寫代碼；上傳時帶上、讀不到就不送。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/lights_out.dart';
import 'package:app/services/nightly_uploader.dart';
import 'package:app/services/phone_model.dart';
import 'package:app/services/user_identity.dart';

void main() {
  group('型號代碼 → 名字', () {
    test('三星：看前 7 碼（後面是地區版本）', () {
      expect(phoneModelName('samsung', 'SM-S9260'), 'Samsung Galaxy S24+');
      expect(phoneModelName('samsung', 'SM-S928B'), 'Samsung Galaxy S24 Ultra');
    });
    test('表裡沒有的照寫代碼，前面接廠商', () {
      expect(phoneModelName('samsung', 'SM-X999'), 'Samsung SM-X999');
      expect(phoneModelName('Xiaomi', '23127PN0CG'), 'Xiaomi 23127PN0CG');
    });
    test('型號本身就是名字的不重複接廠商', () {
      expect(phoneModelName('Google', 'Pixel 8'), 'Google Pixel 8');
      expect(phoneModelName('OnePlus', 'OnePlus 12'), 'OnePlus 12');
    });
    test('沒有型號 → 空字串（不送）', () {
      expect(phoneModelName('samsung', null), '');
      expect(phoneModelName(null, ''), '');
    });
  });

  group('上傳時帶上手機型號', () {
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
            jsonDecode(await utf8.decoder.bind(req).join())
                as Map<String, dynamic>;
        bodies.add(body);
        req.response.statusCode = 201;
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          jsonEncode({
            'date': (body['lights_out_at'] as String).substring(0, 10),
            'adherence_minutes': 0,
            'is_late': false,
          }),
        );
        await req.response.close();
      });
    });
    tearDown(() async {
      await server.close(force: true);
      HttpOverrides.global = saved;
    });

    NightlyUploader uploader(Future<String?> Function()? model) =>
        NightlyUploader(
          baseUrl: 'http://127.0.0.1:${server.port}',
          identity: const BuildTimeUserIdentity(overrideId: 'stub'),
          phoneModel: model,
        );
    final night = LightsOutResult(
      LightsOutStatus.ok,
      at: DateTime(2026, 11, 16, 0, 49),
    );

    test('讀得到 → 送 phone_model', () async {
      await uploader(() async => 'Samsung Galaxy S24+').upload(night);
      expect(bodies.single['phone_model'], 'Samsung Galaxy S24+');
    });
    test('讀不到 → 不送這個欄位（後端留著之前的，不洗成空的）', () async {
      await uploader(() async => null).upload(night);
      await uploader(null).upload(night);
      expect(bodies.every((b) => !b.containsKey('phone_model')), isTrue);
    });
  });
}
