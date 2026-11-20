// 睡覺畫面的攝影機那一行（2026-11-21 grill Q9）。
//
// - 只有**確定在錄**（recording／already_recording）才寫一行；還在接、沒開成、沒回應一律不寫
//   （手機分不出是後端沒開還是網路慢，寫「Camera off」可能是錯的）
// - 沒插電要說出來（09-20 那晚就是用電池、筆電待機，錄影斷掉）
// - 後端回應裡的 camera 真的會被放進告示板；按 Start Sleep 先清掉，不顯示上一晚的
import 'dart:convert';
import 'dart:io';

import 'package:app/screens/sleep_mode_screen.dart';
import 'package:app/services/account_service.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/friends_service.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/live_sleep_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('【1】那一行寫什麼', () {
    test('在錄 → Camera recording', () {
      expect(cameraStatusLine(const CameraStatus('recording', onBattery: false)), 'Camera recording');
      expect(cameraStatusLine(const CameraStatus('already_recording')), 'Camera recording');
    });

    test('沒插電要說出來', () {
      expect(cameraStatusLine(const CameraStatus('recording', onBattery: true)),
          'Camera recording · laptop on battery');
    });

    test('不確定在錄的一律不寫', () {
      for (final s in ['starting', 'not_started', 'stopping', 'cancelling', 'idle']) {
        expect(cameraStatusLine(CameraStatus(s, onBattery: true)), isNull, reason: s);
      }
      expect(cameraStatusLine(null), isNull);
    });

    test('解析後端回應；格式不對當作沒有', () {
      final s = CameraStatus.fromJson({'state': 'recording', 'on_battery': true})!;
      expect(s.state, 'recording');
      expect(s.onBattery, isTrue);
      expect(CameraStatus.fromJson({'state': 'recording', 'on_battery': 'yes'})!.onBattery, isNull);
      expect(CameraStatus.fromJson(null), isNull);
      expect(CameraStatus.fromJson({'on_battery': true}), isNull);
      expect(CameraStatus.fromJson('recording'), isNull);
    });
  });

  group('【2】睡覺畫面', () {
    Future<void> pump(WidgetTester tester, ValueNotifier<CameraStatus?> board) async {
      tester.view.physicalSize = const Size(1200, 4200);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: SleepModeScreen(
          store: BedMarkStore(InMemoryKeyValueStore()),
          startAt: DateTime(2026, 11, 21, 1, 0),
          clock: () => DateTime(2026, 11, 21, 1, 5),
          camera: board,
        ),
      ));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('沒有回報 → 不寫', (tester) async {
      await pump(tester, ValueNotifier(null));
      expect(find.byKey(const Key('sleep-camera')), findsNothing);
      expect(find.text('Sleeping… your watch is tracking'), findsOneWidget, reason: '原本那句照留');
    });

    testWidgets('回報在錄 → 寫一行；之後變了跟著變', (tester) async {
      final board = ValueNotifier<CameraStatus?>(const CameraStatus('recording', onBattery: false));
      await pump(tester, board);
      expect(find.text('Camera recording'), findsOneWidget);
      board.value = const CameraStatus('recording', onBattery: true);
      await tester.pump();
      expect(find.text('Camera recording · laptop on battery'), findsOneWidget);
      board.value = const CameraStatus('not_started');
      await tester.pump();
      expect(find.byKey(const Key('sleep-camera')), findsNothing);
    });
  });

  group('【3】後端回應放進告示板', () {
    late HttpServer server;
    late Map<String, dynamic> reply;
    final bodies = <Map<String, dynamic>>[];

    setUp(() async {
      // TestWidgetsFlutterBinding 會把 HttpClient 換成一律回 400 的假的，要打真的本機 server 先拿掉
      HttpOverrides.global = null;
      bodies.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        bodies.add(jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>);
        req.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(reply));
        await req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    FriendsService service() => FriendsService(
          baseUrl: 'http://127.0.0.1:${server.port}',
          identity: const ResolvedUserIdentity('u1'),
        );

    tearDown(() => cameraStatusBoard.value = null);

    test('start 回 recording → 告示板是 recording', () async {
      reply = {'ok': true, 'camera': {'state': 'recording', 'on_battery': false}};
      cameraStatusBoard.value = null;
      await service().sendSleepStatus('start', DateTime(2026, 11, 21, 1, 0));
      expect(cameraStatusBoard.value?.state, 'recording');
      expect(bodies.single['event'], 'start');
    });

    test('沒有 camera（不是手機帳號、外面來的）→ 告示板清空，不留上一晚的', () async {
      reply = {'ok': true};
      cameraStatusBoard.value = const CameraStatus('recording');
      await service().sendSleepStatus('start', DateTime(2026, 11, 21, 1, 0));
      expect(cameraStatusBoard.value, isNull);
    });

    test('後端連不到 → 告示板清空', () async {
      cameraStatusBoard.value = const CameraStatus('recording');
      await FriendsService(baseUrl: 'http://127.0.0.1:1', identity: const ResolvedUserIdentity('u1'))
          .sendSleepStatus('start', DateTime(2026, 11, 21, 1, 0));
      expect(cameraStatusBoard.value, isNull);
    });
  });
}
