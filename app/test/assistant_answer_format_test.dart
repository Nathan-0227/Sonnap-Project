// 助理的分段回答（2026-11-22，參考 Oura／WHOOP，使用者 grill 定）。
//
// 守的東西（每一條都放回錯誤驗證過會紅）：
//   1. 照抄後端的四格；舊版後端（沒有 headline）照一段文字顯示
//   2. 對得上睡眠計畫的建議才有「+ Add "…" to my plan」；加進去的是清單那一整句，不是 AI 的字
//   3. Why 那一行照抄後端那句
//   4. 追問膠囊不出現這段對話已經問過的題目
//   5. 舊版存下來的對話（v1）照樣讀得到、照一段顯示
//   6. 每條計畫建議都有短名字（漏了那一行就悄悄不出現）

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/screens/assistant_screen.dart';
import 'package:app/services/chat_service.dart';
import 'package:app/services/chat_thread.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/night_sheet_link.dart';
import 'package:app/services/sleep_plan.dart';
import 'package:app/services/user_identity.dart';

class _StubChat implements ChatService {
  ChatResult result;
  final List<String> asked = [];
  _StubChat(this.result);

  @override
  Future<ChatResult> ask(String message, {List<Map<String, String>> history = const []}) async {
    asked.add(message);
    return result;
  }

  @override
  String get baseUrl => 'stub';
  @override
  UserIdentity get identity => const BuildTimeUserIdentity(overrideId: 'stub');
  @override
  Duration get timeout => const Duration(seconds: 150);
}

const _backendBody = {
  'answer': 'You slept 5h 40m. Late caffeine might make it harder to fall asleep.',
  'source': 'llm',
  'headline': 'You slept 5h 40m.',
  'why': 'Late caffeine might make it harder to fall asleep.',
  'tips': [
    {'id': 'T3', 'why': 'You noted late caffeine last night.'},
    {'id': 'T9', 'why': null}, // 說明那幾句：對不到計畫，不出現按鈕
  ],
  'link': {'key': 'total_sleep', 'date': '2026-11-21'},
};

ChatResult _ok() => ChatResult(ChatStatus.ok,
    answer: _backendBody['answer'] as String, reply: replyFromJson(_backendBody));

Future<void> _pump(WidgetTester tester, ChatService chat, {KeyValueStore? store}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AssistantScreen(chat: chat, store: store ?? InMemoryKeyValueStore()))));
  await tester.pump();
}

/// 日期膠囊（key 是 assistant-period-<第幾則>）。
final _periodChip = find.byWidgetPredicate(
    (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('assistant-period-'));

Future<void> _ask(WidgetTester tester, String q) async {
  await tester.enterText(find.byType(TextField).first, q);
  await tester.tap(find.byIcon(Icons.send_rounded).first);
  await tester.pump();
  await tester.pump();
}

void main() {
  tearDown(() {
    PlanStore.shared = null;
    NightSheetLinks.shared = null;
  });

  group('解析', () {
    test('照抄後端的四格', () {
      final t = replyFromJson(_backendBody);
      expect(t.structured, isTrue);
      expect(t.headline, 'You slept 5h 40m.');
      expect(t.why, 'Late caffeine might make it harder to fall asleep.');
      expect(t.tips.map((x) => x.id), ['T3', 'T9']);
      expect(t.tips.first.why, 'You noted late caffeine last night.');
      expect(t.tips.last.why, isNull);
      expect(t.link?.key, 'total_sleep');
      expect(t.link?.date, '2026-11-21');
      expect(t.text, _backendBody['answer'], reason: '前文送回後端的仍是合起來那一段');
    });

    test('舊版後端（只有 answer）→ 一段文字', () {
      final t = replyFromJson({'answer': 'You slept 6h.', 'source': 'llm'});
      expect(t.structured, isFalse);
      expect(t.text, 'You slept 6h.');
    });

    test('存起來再讀回來，四格都在', () async {
      final store = InMemoryKeyValueStore();
      await ChatThreadStore(store).save([const ChatTurn.user('q'), replyFromJson(_backendBody)]);
      final back = (await ChatThreadStore(store).load()).last;
      expect(back.headline, 'You slept 5h 40m.');
      expect(back.tips.first.why, 'You noted late caffeine last night.');
      expect(back.link?.key, 'total_sleep');
    });

    test('舊版存的對話（v1）讀得到，只有文字', () async {
      final store = InMemoryKeyValueStore();
      await store.setString(ChatThreadStore.legacyKey,
          '[{"role":"user","text":"old q"},{"role":"assistant","text":"old answer"}]');
      final turns = await ChatThreadStore(store).load();
      expect(turns.map((t) => t.text), ['old q', 'old answer']);
      expect(turns.last.structured, isFalse);
    });
  });

  group('畫面', () {
    testWidgets('粗體一句＋為什麼；輸入框上方有小字', (tester) async {
      await _pump(tester, _StubChat(_ok()));
      await _ask(tester, 'Why am I tired today?');
      expect(find.byKey(const Key('assistant-headline')), findsOneWidget);
      expect(find.text('You slept 5h 40m.'), findsOneWidget);
      expect(find.text('Late caffeine might make it harder to fall asleep.'), findsOneWidget);
      expect(find.text(kAssistantDisclaimer), findsOneWidget);
    });

    testWidgets('對得上計畫的建議才有按鈕；加進去的是清單那一整句', (tester) async {
      final plan = PlanStore(InMemoryKeyValueStore());
      PlanStore.shared = plan;
      await _pump(tester, _StubChat(_ok()));
      await _ask(tester, 'Why am I tired today?');
      await tester.pump();

      expect(find.text('Add "caffeine earlier" to my plan'), findsOneWidget);
      expect(find.text('You noted late caffeine last night.'), findsOneWidget, reason: 'Why 照抄後端');
      expect(find.byKey(const Key('assistant-add-late_caffeine')), findsOneWidget);
      expect(find.textContaining('to my plan'), findsOneWidget, reason: 'T9 對不到計畫，不出現');

      await tester.tap(find.byKey(const Key('assistant-add-late_caffeine')));
      await tester.pump();
      await tester.pump();
      expect(plan.items.map((i) => i.text), [suggestionById('late_caffeine')!.text]);
      expect(find.text('"caffeine earlier" is in your plan'), findsOneWidget);
    });

    testWidgets('沒有計畫（PlanStore.shared 是 null）→ 不出現按鈕', (tester) async {
      await _pump(tester, _StubChat(_ok()));
      await _ask(tester, 'Why am I tired today?');
      expect(find.textContaining('to my plan'), findsNothing);
    });

    testWidgets('連結：首頁登記了才出現，點了照後端的日期與頁開', (tester) async {
      final opened = <String>[];
      NightSheetLinks.shared = (context, date, key) async => opened.add('$date $key');
      await _pump(tester, _StubChat(_ok()));
      await _ask(tester, 'Why am I tired today?');
      await tester.tap(find.byKey(const Key('assistant-link-total_sleep')));
      await tester.pump();
      expect(opened, ['2026-11-21 total_sleep']);
      expect(find.text('See Total sleep for this night ›'), findsOneWidget);
    });

    testWidgets('追問：兩顆、不出現已經問過的', (tester) async {
      final stub = _StubChat(_ok());
      await _pump(tester, stub);
      await tester.tap(find.text(kAssistantSuggestions[0]));
      await tester.pump();
      await tester.pump();
      final chips = find.descendant(
          of: find.byKey(const Key('assistant-follow-ups')), matching: find.byType(InkWell));
      expect(chips, findsNWidgets(kFollowUpCount));
      expect(find.descendant(of: find.byKey(const Key('assistant-follow-ups')),
          matching: find.text(kAssistantSuggestions[0])), findsNothing);

      await tester.tap(find.descendant(
          of: find.byKey(const Key('assistant-follow-ups')), matching: find.text(kAssistantSuggestions[1])));
      await tester.pump();
      await tester.pump();
      expect(stub.asked, [kAssistantSuggestions[0], kAssistantSuggestions[1]]);
    });

    testWidgets('舊的訊息照一段文字顯示', (tester) async {
      final store = InMemoryKeyValueStore();
      await store.setString(ChatThreadStore.legacyKey,
          '[{"role":"user","text":"old q"},{"role":"assistant","text":"old answer"}]');
      await _pump(tester, _StubChat(_ok()), store: store);
      await tester.pump();
      expect(find.text('old answer'), findsOneWidget);
      expect(find.byKey(const Key('assistant-headline')), findsNothing);
    });
  });

  test('追問只從固定清單挑、不重複問過的', () {
    final turns = [ChatTurn.user(kAssistantSuggestions[1]), const ChatTurn.buddy('a')];
    expect(followUpQuestions(turns), [kAssistantSuggestions[0], kAssistantSuggestions[2]]);
  });

  test('每條計畫建議都有短名字（漏了那一行就悄悄不出現）', () {
    expect(kPlanShortNames.keys.toSet(), {for (final s in kPlanSuggestions) s.id});
    for (final id in kTipToPlan.values) {
      expect(kPlanShortNames[id], isNotNull, reason: id);
    }
  });

  group('哪一晚／哪一段（2026-11-22）', () {
    test('小字：一晚同早晨報告的標題、一段寫起訖（都是起床日、照抄後端）', () {
      expect(chatPeriodLabel(const ChatPeriod.night('2026-11-19')), 'Thursday, Nov 19');
      expect(chatPeriodLabel(const ChatPeriod.range('2026-11-17', '2026-11-23')), 'Nov 17 – Nov 23');
      expect(chatPeriodLabel(const ChatPeriod.range('2026-12-29', '2027-01-04')), 'Dec 29 – Jan 4');
    });

    test('解析與存回：period 跟著回答走；壞掉的不收', () async {
      final t = replyFromJson({..._backendBody, 'period': {'kind': 'night', 'date': '2026-11-19'}});
      expect(t.period?.date, '2026-11-19');
      final store = InMemoryKeyValueStore();
      await ChatThreadStore(store).save([const ChatTurn.user('q'), t]);
      expect((await ChatThreadStore(store).load()).last.period?.date, '2026-11-19');
      expect(ChatPeriod.fromJson({'kind': 'night', 'date': 'soon'}), isNull);
      expect(ChatPeriod.fromJson({'kind': 'range', 'start': '2026-11-17'}), isNull);
    });

    testWidgets('小字畫在粗體那句上面；後端沒給就不畫', (tester) async {
      final withPeriod = replyFromJson({
        ..._backendBody,
        'period': {'kind': 'range', 'start': '2026-11-17', 'end': '2026-11-23'},
      });
      await _pump(tester, _StubChat(ChatResult(ChatStatus.ok, answer: 'x', reply: withPeriod)));
      await _ask(tester, 'How was last week?');
      expect(find.text('Nov 17 – Nov 23'), findsOneWidget);
      final label = tester.getTopLeft(_periodChip);
      final head = tester.getTopLeft(find.byKey(const Key('assistant-headline')));
      expect(label.dy, lessThan(head.dy));

      await tester.pumpWidget(const SizedBox());
      await _pump(tester, _StubChat(_ok()));
      await _ask(tester, 'hi');
      expect(_periodChip, findsNothing);
    });

    // 11-22 實機：問了幾個不同的晚上之後整片對話變紅畫面
    // （'_elements.contains(element)' is not true）。原因：每顆日期膠囊都用同一個 key，
    // 列表重建時用 key 找新位置，兩顆被對到同一格、其中一個元素被弄丟。
    testWidgets('問好幾個不同的晚上、上下捲動：日期膠囊不會讓對話壞掉', (tester) async {
      ChatResult night(String date) => ChatResult(ChatStatus.ok,
          answer: 'x', reply: replyFromJson({..._backendBody, 'period': {'kind': 'night', 'date': date}}));
      final chat = _StubChat(night('2026-11-19'));
      await _pump(tester, chat);
      tester.view.physicalSize = const Size(412, 900); // 手機大小：上面幾則捲出畫面外
      await tester.pump();
      final list = find.byWidgetPredicate((w) => w is ListView && w.scrollDirection == Axis.vertical);
      final dates = ['2026-11-19', '2026-11-18', '2026-11-19', '2026-11-17', '2026-11-18', '2026-11-16'];
      for (final d in dates) {
        chat.result = night(d);
        await _ask(tester, 'How was $d?');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.drag(list, const Offset(0, 600));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.drag(list, const Offset(0, -1200));
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull, reason: d);
      }
      expect(find.text('Monday, Nov 16'), findsOneWidget);
    });
  });
}
