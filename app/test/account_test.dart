// 暱稱制帳號：建立、存下來、之後沿用。
//
// 這一組守四件事，全部都是「壞掉時不會報錯、只會安靜地做錯事」：
//
//   1. **建置參數優先。** demo build 帶了 SONNAP_USER_ID，就不該跳出
//      問暱稱的畫面。順序反過來的話，每次拿 demo build 測試都要先取名字，
//      而且取完之後上傳的是另一個人的資料。
//
//   2. **存下來的要真的被沿用。** 沒存到 / 沒讀到的話，使用者每次開 App
//      都是一個新的人——後端會長出一堆各有一晚資料的帳號，而畫面上完全
//      看不出來。這是這個檔案存在的主因。
//
//   3. **建不了帳號不能擋住 App。** 後端沒開是 demo 的常態。
//      把人卡在一個「連不上伺服器」的畫面前面，是最不該發生的事。
//
//   4. **剛建好的帳號要立刻能上傳。** uploader 若在 App 啟動時就把身分
//      固定住，註冊完的第一次上傳會帶著空的 user_id 出去。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/main.dart';
import 'package:app/screens/assistant_screen.dart';
import 'package:app/screens/home_screen.dart';
import 'package:app/screens/onboarding_screen.dart';
import 'package:app/screens/settings_screen.dart';
import 'package:app/services/account_service.dart';
import 'package:app/services/key_value_store.dart';

const String createdUserId = '11111111-2222-3333-4444-555555555555';

class _FakeBackend {
  late final HttpServer server;
  final List<Map<String, dynamic>> received = [];
  int statusCode = 201;

  Future<String> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      received.add({
        'path': request.uri.path,
        'body': body.isEmpty ? null : jsonDecode(body),
      });
      request.response.statusCode = statusCode;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'user_id': createdUserId,
        'display_name': 'Nathan',
        'target_bedtime': '23:30',
      }));
      await request.response.close();
    });
    return 'http://127.0.0.1:${server.port}';
  }

  Future<void> stop() => server.close(force: true);
}

void main() {
  group('哪一種身分狀態', () {
    test('沒有後端 → noBackend，不問暱稱', () async {
      final service = AccountService(
        baseUrl: '',
        store: InMemoryKeyValueStore(),
      );
      final status = await service.resolve();
      expect(status.state, AccountState.noBackend);
      expect(status.userId, isNull);
    });

    test('有後端、沒存過 → needsOnboarding', () async {
      final service = AccountService(
        baseUrl: 'http://127.0.0.1:1',
        store: InMemoryKeyValueStore(),
      );
      expect((await service.resolve()).state, AccountState.needsOnboarding);
    });

    test('存過就沿用，不再問一次', () async {
      final service = AccountService(
        baseUrl: 'http://127.0.0.1:1',
        store: InMemoryKeyValueStore({
          AccountService.userIdKey: createdUserId,
          AccountService.displayNameKey: 'Nathan',
        }),
      );
      final status = await service.resolve();
      expect(status.state, AccountState.stored);
      expect(status.userId, createdUserId);
      expect(status.displayName, 'Nathan');
    });
  });

  group('建立帳號', () {
    late _FakeBackend backend;
    late String baseUrl;
    late InMemoryKeyValueStore store;

    HttpOverrides? savedOverrides;

    setUp(() async {
      // ⚠️ 這一行不能省，而且找起來很痛。
      //
      // TestWidgetsFlutterBinding 會把全域的 HttpClient 換成一個
      // **一律回 400** 的假實作，用意是防止測試打真的網路。只要同一個
      // 檔案裡有任何一條 testWidgets，整支檔案都會裝上那個 override。
      //
      // 症狀是：連 127.0.0.1:1（根本沒有東西在聽）都會「成功」拿到 400，
      // 而不是丟 SocketException。第一版就是這樣紅在兩條測試上，
      // 而錯誤訊息完全沒有指向 HttpOverrides。
      //
      // 這裡要驗的正是「送出去的 body 長什麼樣」，所以要真的 client。
      savedOverrides = HttpOverrides.current;
      HttpOverrides.global = null;

      backend = _FakeBackend();
      baseUrl = await backend.start();
      store = InMemoryKeyValueStore();
    });
    tearDown(() async {
      await backend.stop();
      HttpOverrides.global = savedOverrides;
    });

    test('POST /users，帶暱稱與目標就寢時間', () async {
      final service = AccountService(baseUrl: baseUrl, store: store);
      final status = await service.createAccount(
        displayName: 'Nathan',
        targetBedtime: '01:00',
      );

      expect(status?.userId, createdUserId);
      final call = backend.received.single;
      expect(call['path'], '/users');
      final body = call['body'] as Map<String, dynamic>;
      expect(body['display_name'], 'Nathan');
      expect(body['target_bedtime'], '01:00');
      expect(body['study_cohort'], 'L0');
    });

    test('⚠️ 建完一定要存下來，否則使用者每天都是新的一個人', () async {
      final service = AccountService(baseUrl: baseUrl, store: store);
      await service.createAccount(displayName: 'Nathan', targetBedtime: '23:30');

      expect(await store.getString(AccountService.userIdKey), createdUserId);

      // 第二次啟動：不該再打後端，也不該再問暱稱。
      final second = AccountService(baseUrl: baseUrl, store: store);
      final status = await second.resolve();
      expect(status.state, AccountState.stored);
      expect(status.userId, createdUserId);
      expect(
        backend.received,
        hasLength(1),
        reason: '第二次啟動又打了一次 /users——後端會長出一堆各有一晚資料的'
            '帳號，而畫面上完全看不出來',
      );
    });

    test('後端回錯就回 null，不存任何東西', () async {
      backend.statusCode = 422;
      final service = AccountService(baseUrl: baseUrl, store: store);
      final status = await service.createAccount(
        displayName: 'Nathan',
        targetBedtime: '23:30',
      );

      expect(status, isNull);
      expect(
        await store.getString(AccountService.userIdKey),
        isNull,
        reason: '存了一個後端不認得的 id，之後每次上傳都會 404',
      );
    });

    test('連不上不會拋例外', () async {
      final service = AccountService(
        baseUrl: 'http://127.0.0.1:1',
        store: InMemoryKeyValueStore(),
        timeout: const Duration(milliseconds: 300),
      );
      expect(
        await service.createAccount(
          displayName: 'Nathan',
          targetBedtime: '23:30',
        ),
        isNull,
      );
    });
  });

  group('⚠️ 建置參數優先於問暱稱', () {
    test('沒設定 SONNAP_USER_ID 時，才會走到 needsOnboarding', () async {
      // 這條測試在**沒有** --dart-define 的環境下跑，所以拿到的是
      // needsOnboarding。它守的是「resolve() 有先問過建置參數」這件事的
      // 另一半：帶了參數的 build 由下面那條 widget 測試守。
      final service = AccountService(
        baseUrl: 'http://127.0.0.1:1',
        store: InMemoryKeyValueStore(),
      );
      expect((await service.resolve()).state, AccountState.needsOnboarding);
    });
  });

  group('App 啟動時的畫面', () {
    testWidgets('沒有後端就直接進 App，不問暱稱', (tester) async {
      // 這是 demo 最常見的狀態：沒給任何 --dart-define。
      await tester.pumpWidget(const SonnapApp());
      await tester.pump();
      await tester.pump();

      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.text('Home'), findsOneWidget);
    });
  });

  group('⚠️ 不得拿任何人的名字當佔位符', () {
    testWidgets('沒有帳號時首頁不得出現隊友的名字', (tester) async {
      // 這三個畫面原本各自寫死 "Jeremy"（隊友的名字）。實機上用「Nathan」
      // 註冊完，首頁還是說「Good morning Jeremy」——一眼就看得出來，
      // 而且是在帳號功能做完之後才變得明顯。
      await tester.pumpWidget(const SonnapApp());
      await tester.pump();
      await tester.pump();

      expect(find.text('Jeremy'), findsNothing);
    });

    test('三個畫面的預設稱呼都是 kFallbackDisplayName', () {
      // ⚠️ 直接驗預設值而不是驗畫面：widget test 的假時間推不動真正的
      //    檔案 I/O，首頁要等 payload 載入才畫得出名字（同一個坑寫在
      //    usage_stats_test.dart 的 setUpAll）。這裡驗的是同一件事的源頭。
      expect(const HomeScreen().displayName, kFallbackDisplayName);
      expect(const SettingsScreen().username, kFallbackDisplayName);
      expect(const AssistantScreen().username, kFallbackDisplayName);

      // 佔位符不可以是人名。這是規則本身，不是實作細節。
      expect(kFallbackDisplayName, isNot('Jeremy'));
    });
  });

  group('⚠️ 建不了帳號不能擋住 App', () {
    testWidgets('連不上時顯示錯誤，但「Skip for now」還能按', (tester) async {
      var skipped = false;
      await tester.pumpWidget(MaterialApp(
        home: OnboardingScreen(
          onCreate: (_) async => false, // 模擬連不上
          onSkip: () => skipped = true,
        ),
      ));

      await tester.enterText(find.byType(TextField), 'Nathan');
      await tester.tap(find.text('Start'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Could not reach the server'), findsOneWidget);
      expect(
        find.textContaining('your sleep reports work offline'),
        findsOneWidget,
        reason: '只說「連不上」會讓人以為整個 App 壞了，但睡眠報告是離線可用的',
      );

      await tester.tap(find.text('Skip for now'));
      await tester.pump();
      expect(skipped, isTrue);
    });

    testWidgets('暱稱空白時擋在本地，不要打一趟 API 才被退回', (tester) async {
      var createCalls = 0;
      await tester.pumpWidget(MaterialApp(
        home: OnboardingScreen(
          onCreate: (_) async {
            createCalls++;
            return true;
          },
          onSkip: () {},
        ),
      ));

      await tester.tap(find.text('Start'));
      await tester.pump();

      expect(createCalls, 0);
      expect(find.textContaining('Pick any name'), findsOneWidget);
    });

    testWidgets('這個畫面不得宣稱安全或加密', (tester) async {
      // 後端是暱稱制免註冊，user_id 本身就是憑證。寫「安全」是謊，
      // 而且會讓同意書與畫面自相矛盾。
      await tester.pumpWidget(MaterialApp(
        home: OnboardingScreen(onCreate: (_) async => true, onSkip: () {}),
      ));

      for (final word in ['secure', 'Secure', 'encrypted', 'private and']) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
      expect(find.textContaining('No email, no password'), findsOneWidget);
    });
  });
}
