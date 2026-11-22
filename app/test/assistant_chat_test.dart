// 睡眠助理：答案只來自後端，答不出來就老實講。
//
// 守的東西：
//   1. 沒有後端時講「要連後端」，**不從查表路由器編一段答案出來**——
//      那正是這個畫面最早的問題（寫死的關鍵字對照，回與使用者無關的話）。
//   2. 失敗原因照抄後端的 detail（沒設定金鑰／連不上／沒過驗證講的是不同的事）。
//   3. 逾時要夠長：後端呼叫 Claude 最多等 60 秒還可能重問一次，
//      用其他服務的 3 秒會讓幾乎每一題都被當成連不上。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/content/sleep_basics.dart';
import 'package:app/screens/assistant_screen.dart';
import 'package:app/services/chat_service.dart';
import 'package:app/services/chat_thread.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/user_identity.dart';

const String testUserId = '00000000-5017-4e01-9a30-000000000001';

class _StubChat implements ChatService {
  ChatResult result;
  final List<String> asked = [];
  final List<List<Map<String, String>>> histories = [];

  _StubChat(this.result);

  @override
  Future<ChatResult> ask(String message, {List<Map<String, String>> history = const []}) async {
    asked.add(message);
    histories.add(history);
    return result;
  }

  @override
  String get baseUrl => 'stub';

  @override
  UserIdentity get identity => const BuildTimeUserIdentity(overrideId: 'stub');

  @override
  Duration get timeout => const Duration(seconds: 150);
}

class _FakeBackend {
  late final HttpServer server;
  final List<Map<String, dynamic>> received = [];
  int status = 200;
  Map<String, dynamic> body = {'answer': 'You put the phone down at 02:39.', 'source': 'llm'};

  Future<String> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final raw = await utf8.decoder.bind(request).join();
      received.add({'path': request.uri.path, 'body': jsonDecode(raw)});
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(body));
      await request.response.close();
    });
    return 'http://127.0.0.1:${server.port}';
  }

  Future<void> stop() => server.close(force: true);
}

Future<void> pump(WidgetTester tester, ChatService? chat, {KeyValueStore? store}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AssistantScreen(chat: chat, store: store ?? InMemoryKeyValueStore()))));
  await tester.pump();
}

/// 輸入問題、按送出。
///
/// ⚠️ 要按送出圖示，不是鍵盤的「完成」：ChatInputCard 只有按鈕會觸發 onSend。
///    第一版用 receiveAction(done)，問題根本沒送出去——畫面測試全紅，
///    而變異測試在紅的基準上看起來「都有抓到」，那是不算數的。
Future<void> ask(WidgetTester tester, String question) async {
  await tester.enterText(find.byType(TextField).first, question);
  await tester.tap(find.byIcon(Icons.send_rounded).first);
  await tester.pump();
  await tester.pump();
}

void main() {
  group('服務層', () {
    late _FakeBackend backend;
    late String baseUrl;
    HttpOverrides? saved;

    setUp(() async {
      saved = HttpOverrides.current;
      HttpOverrides.global = null;
      backend = _FakeBackend();
      baseUrl = await backend.start();
    });
    tearDown(() async {
      await backend.stop();
      HttpOverrides.global = saved;
    });

    ChatService service() => ChatService(
          baseUrl: baseUrl,
          identity: const BuildTimeUserIdentity(overrideId: testUserId),
        );

    test('POST /chat，body 帶 user_id 與去掉空白的問題', () async {
      final r = await service().ask('  How late was I?  ');
      expect(r.isOk, isTrue);
      expect(r.answer, 'You put the phone down at 02:39.');
      expect(backend.received.single['path'], '/chat');
      expect(backend.received.single['body'], {'user_id': testUserId, 'message': 'How late was I?'});
    });

    test('503 的原因原樣帶出來', () async {
      backend.status = 503;
      backend.body = {'detail': 'The AI assistant is not configured on this server.'};
      final r = await service().ask('hi');
      expect(r.isOk, isFalse);
      expect(r.httpStatus, 503);
      expect(r.message, 'The AI assistant is not configured on this server.');
    });

    test('逾時至少 60 秒（後端呼叫 Claude 最多等 60 秒）', () {
      expect(service().timeout, greaterThanOrEqualTo(const Duration(seconds: 60)));
    });
  });

  group('畫面', () {
    testWidgets('沒有後端 → 講要連後端，不編答案', (tester) async {
      await pump(tester, null);
      await ask(tester, 'How did I sleep?');
      expect(find.textContaining('needs the Sonnap backend'), findsOneWidget);
    });

    testWidgets('有答案 → 原樣顯示', (tester) async {
      final stub = _StubChat(const ChatResult(ChatStatus.ok, answer: 'You put the phone down at 02:39.'));
      await pump(tester, stub);
      await ask(tester, '  How late was I?  ');
      expect(stub.asked, ['How late was I?']);
      expect(find.text('You put the phone down at 02:39.'), findsOneWidget);
    });

    testWidgets('答不出來 → 照抄後端講的原因', (tester) async {
      final stub = _StubChat(const ChatResult(ChatStatus.failed,
          httpStatus: 503, message: 'The assistant could not give an answer that passed the safety checks.'));
      await pump(tester, stub);
      await ask(tester, 'Am I sick?');
      expect(find.text('The assistant could not give an answer that passed the safety checks.'), findsOneWidget);
    });

    testWidgets('連不上（沒有原因）→ 講連不上', (tester) async {
      await pump(tester, _StubChat(const ChatResult(ChatStatus.failed)));
      await ask(tester, 'hi');
      expect(find.textContaining('cannot be reached'), findsOneWidget);
    });

    testWidgets('空的問題 → 不問', (tester) async {
      final stub = _StubChat(const ChatResult(ChatStatus.ok, answer: 'x'));
      await pump(tester, stub);
      await ask(tester, '   ');
      expect(stub.asked, isEmpty);
    });
  });

  group('對話（2026-11-19 第二版）', () {
    const ok = ChatResult(ChatStatus.ok, answer: 'You slept 6h 12m.');

    test('前文只拿完整的一問一答、跳過答不出來的、最多 5 輪', () {
      final turns = <ChatTurn>[
        for (var i = 0; i < 7; i++) ...[ChatTurn.user('q$i'), ChatTurn.buddy('a$i')],
        const ChatTurn.user('bad'),
        const ChatTurn.buddy('could not answer', failed: true),
      ];
      final ctx = chatContext(turns);
      expect(ctx.length, kChatContextRounds * 2);
      expect(ctx.first, {'role': 'user', 'text': 'q2'});
      expect(ctx.last, {'role': 'assistant', 'text': 'a6'});
      expect(ctx.any((m) => m['text'] == 'could not answer' || m['text'] == 'bad'), isFalse);
    });

    testWidgets('追問時把前面的一問一答一起送', (tester) async {
      final stub = _StubChat(ok);
      await pump(tester, stub);
      await ask(tester, 'How long did I sleep?');
      await ask(tester, 'Why?');
      expect(stub.asked, ['How long did I sleep?', 'Why?']);
      expect(stub.histories.first, isEmpty);
      expect(stub.histories.last, [
        {'role': 'user', 'text': 'How long did I sleep?'},
        {'role': 'assistant', 'text': 'You slept 6h 12m.'},
      ]);
    });

    testWidgets('對話存在手機上，重開還在；✎ 開新對話清掉', (tester) async {
      final store = InMemoryKeyValueStore();
      await pump(tester, _StubChat(ok), store: store);
      await ask(tester, 'How long did I sleep?');
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      await pump(tester, _StubChat(ok), store: store);
      await tester.pump();
      expect(find.text('How long did I sleep?'), findsOneWidget);
      expect(find.text('You slept 6h 12m.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('assistant-new-chat')));
      await tester.pump();
      expect(find.text('You slept 6h 12m.'), findsNothing);
      expect(await ChatThreadStore(store).load(), isEmpty);
    });

    testWidgets('答不出來的那則不存；Try again 用同一題再問、不重複加問題', (tester) async {
      final store = InMemoryKeyValueStore();
      final stub = _StubChat(const ChatResult(ChatStatus.failed));
      await pump(tester, stub, store: store);
      await ask(tester, 'Am I okay?');
      expect(find.textContaining('cannot be reached'), findsOneWidget);

      stub.result = ok;
      await tester.tap(find.byKey(const Key('assistant-retry')));
      await tester.pump();
      await tester.pump();
      expect(stub.asked, ['Am I okay?', 'Am I okay?']);
      expect(find.text('Am I okay?'), findsOneWidget);
      expect(find.textContaining('cannot be reached'), findsNothing);
      final saved = await ChatThreadStore(store).load();
      expect(saved.map((t) => t.text), ['Am I okay?', 'You slept 6h 12m.']);
    });

    testWidgets('答不出來的那一輪連問題也不存（2026-11-20 實機：重開後留下沒回答的問題）', (tester) async {
      final store = InMemoryKeyValueStore();
      final stub = _StubChat(const ChatResult(ChatStatus.failed));
      await pump(tester, stub, store: store);
      await ask(tester, 'hello');
      stub.result = const ChatResult(ChatStatus.ok, answer: 'You slept 6h 12m.');
      await ask(tester, 'How long did I sleep?');
      final saved = await ChatThreadStore(store).load();
      expect(saved.map((t) => t.text), ['How long did I sleep?', 'You slept 6h 12m.']);

      await tester.pumpWidget(const SizedBox());
      await pump(tester, stub, store: store);
      await tester.pump();
      expect(find.text('hello'), findsNothing);
    });

    testWidgets('點建議問題就送出', (tester) async {
      final stub = _StubChat(ok);
      await pump(tester, stub);
      await tester.tap(find.text(kAssistantSuggestions.first));
      await tester.pump();
      expect(stub.asked, [kAssistantSuggestions.first]);
    });

    test('寫死的「What affected your sleep」拿掉了（每個人每天都一樣＝Dart 自己下判斷）', () {
      final src = File('lib/screens/assistant_screen.dart').readAsStringSync();
      expect(src.contains("Late bedtime"), isFalse);
      expect(File('lib/widgets/explain_sleep_card.dart').existsSync(), isFalse);
    });
  });

  group('LLM 是唯一的答案來源', () {
    test('助理畫面沒有偷偷退回查表路由器', () {
      // 計畫檔：查表路由器退場，只有明確用 --dart-define 開旗標時才留成離線退路。
      // 預設就接回去的話，「答不出來」會被一段查表句子蓋掉，而畫面上看不出差別。
      final src = File('lib/screens/assistant_screen.dart').readAsStringSync();
      expect(src.contains('answerQuestion('), isFalse);
      expect(src.contains("assistant_answers.dart'"), isFalse);
    });
  });

  group('Sleep basics（2026-11-22 使用者定 A＋B）', () {
    // 背景一直在動（飄的塗鴉、星星），pumpAndSettle 永遠等不到停，改成等固定時間
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    final first = kSleepBasics.first;
    final last = kSleepBasics.last;

    testWidgets('【B1】點膠囊：寵物回原文＋出處，不經過 AI；那顆膠囊收掉', (tester) async {
      final stub = _StubChat(const ChatResult(ChatStatus.ok, answer: 'unused'));
      await pump(tester, stub);
      expect(find.byKey(Key('assistant-basic-${first.id}')), findsOneWidget);

      await tester.tap(find.byKey(Key('assistant-basic-${first.id}')));
      await settle(tester);
      expect(find.text(first.summary), findsOneWidget);
      expect(find.text(first.source), findsOneWidget);
      expect(stub.asked, isEmpty, reason: '固定原文不呼叫 AI、不花額度');
      expect(find.byKey(Key('assistant-basic-${first.id}')), findsNothing, reason: '看過的那顆不再出現');
    });

    testWidgets('【B2】看過的 basics 不當前文送給 AI；存起來、重開還在', (tester) async {
      final store = InMemoryKeyValueStore();
      final stub = _StubChat(const ChatResult(ChatStatus.ok, answer: 'You put the phone down at 02:39.'));
      await pump(tester, stub, store: store);
      await tester.tap(find.byKey(Key('assistant-basic-${first.id}')));
      await settle(tester);
      await ask(tester, 'How late was I?');
      await ask(tester, 'And the night before?');
      final history = stub.histories.last;
      expect(history.map((m) => m['text']), isNot(contains(first.summary)));
      expect(history.map((m) => m['text']), contains('How late was I?'),
          reason: '反向對照：一般的一問一答照樣當前文');

      final saved = await ChatThreadStore(store).load();
      expect(saved.where((t) => t.basic == first.id), hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await pump(tester, stub, store: store);
      await settle(tester);
      expect(find.text(first.source), findsOneWidget, reason: '重開之後出處還在');
      expect(find.byKey(Key('assistant-basic-${first.id}')), findsNothing);
    });

    testWidgets('【A】📖 面板捲到底，最後一條的出處不被系統導覽列蓋住', (tester) async {
      const nav = 48.0; // 三顆按鈕的導覽列
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(bottom: nav);
      tester.view.viewPadding = const FakeViewPadding(bottom: nav);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: AssistantScreen(store: InMemoryKeyValueStore()))));
      await tester.pump();
      await tester.tap(find.byKey(const Key('assistant-basics')));
      await settle(tester);
      final scroll = find.descendant(
          of: find.byKey(const Key('assistant-basics-sheet')), matching: find.byType(Scrollable));
      await tester.drag(scroll.first, const Offset(0, -3000));
      await settle(tester);
      final src = find.descendant(
          of: find.byKey(const Key('assistant-basics-sheet')), matching: find.text(last.source));
      expect(tester.getRect(src).bottom, lessThanOrEqualTo(2000 - nav));
    });
  });
}
