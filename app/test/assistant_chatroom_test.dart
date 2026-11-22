// 助理頁的聊天室外觀（2026-11-22 使用者 grill 定，設計稿 D）。
//
// 守的東西（每一條都放回錯誤驗證過會紅）：
//   1. 打招呼：有手錶／只有手機／都沒有或不是昨晚 → 各說對的話，數字照抄 /home
//   2. 頭像跟著心情；不認得的心情退回 bored（絕不 happy）；沒有生成的頭像就用裁切版、不漫出圓框
//   3. 狀態列四種心情的字；想答案時是 thinking…
//   4. 日期膠囊只在換晚上或換一段時出現
//   5. 切到別的分頁、開「減少動態效果」時，背景動畫停止

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/screens/assistant_screen.dart';
import 'package:app/services/chat_service.dart';
import 'package:app/services/chat_thread.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/pet_choice.dart';
import 'package:app/services/user_identity.dart';
import 'package:app/widgets/assistant_chrome.dart';
import 'package:app/widgets/home_pet.dart';

class _StubChat implements ChatService {
  Completer<ChatResult>? pending;
  ChatResult result = const ChatResult(ChatStatus.ok, answer: 'ok');

  @override
  Future<ChatResult> ask(String message, {List<Map<String, String>> history = const []}) =>
      pending?.future ?? Future.value(result);

  @override
  String get baseUrl => 'stub';
  @override
  UserIdentity get identity => const BuildTimeUserIdentity(overrideId: 'stub');
  @override
  Duration get timeout => const Duration(seconds: 150);
}

final _morning = DateTime(2026, 11, 22, 9, 30);

/// 模擬「頭像圖讀不到」：assets/avatars/ 底下一律丟錯，其他照常（2026-11-22 起資料夾裡真的有 8 張圖，
/// 不能再靠「資料夾裡沒有圖」測退路）。
class _MissingAvatarsBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key.startsWith('assets/avatars/')) throw FlutterError('missing avatar: $key');
    return rootBundle.load(key);
  }
}

Map<String, dynamic> _night({String date = '2026-11-22', num? score, num? minutes, String? lightsOut}) => {
      'date': date,
      'scoring': {'final_score': score},
      'metrics': {'sleep_duration_minutes': minutes},
      'behavior': {'lights_out_at': lightsOut},
    };

Future<void> _pump(WidgetTester tester,
    {ChatService? chat,
    bool visible = true,
    bool reduceMotion = false,
    Map<String, dynamic>? night,
    AssetBundle? bundle}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  Widget app = MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(
        body: AssistantScreen(
          chat: chat,
          username: 'Nathan',
          store: InMemoryKeyValueStore(),
          visible: visible,
          clock: () => _morning,
          greetingNight: night == null ? null : (_) async => night,
        ),
      ),
    ),
  );
  if (bundle != null) app = DefaultAssetBundle(bundle: bundle, child: app);
  await tester.pumpWidget(app);
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() => PetChoice.current.value = PetSpecies.dog);

  group('打招呼（App 用固定句型組，不呼叫 AI）', () {
    test('有手錶：照抄睡多久與分數（四捨五入）', () {
      expect(buildGreeting(name: 'Nathan', now: _morning, night: _night(score: 91.7, minutes: 401)),
          'Morning, Nathan! You slept 6h 41m last night, and your sleep score was 92. '
          'Want to look at it together?');
    });

    test('只有手機：照抄放下手機的牆鐘時刻（不是 UTC）', () {
      expect(
          buildGreeting(
              name: 'Nathan', now: _morning, night: _night(lightsOut: '2026-11-22T01:52:00+08:00')),
          'Morning, Nathan! You put your phone down at 01:52 last night. Want to look at it together?');
    });

    test('都沒有、或不是昨晚、或拿不到 → 只打招呼，不講舊的晚上', () {
      const hello = 'Morning, Nathan! Ask me anything about your sleep.';
      expect(buildGreeting(name: 'Nathan', now: _morning, night: _night()), hello);
      expect(buildGreeting(name: 'Nathan', now: _morning, night: _night(date: '2026-11-19', score: 80, minutes: 400)),
          hello);
      expect(buildGreeting(name: 'Nathan', now: _morning), hello);
    });

    test('時段：05–12 Morning、12–18 Afternoon、其他 Evening', () {
      expect(greetingWord(DateTime(2026, 1, 1, 4, 59)), 'Evening');
      expect(greetingWord(DateTime(2026, 1, 1, 5)), 'Morning');
      expect(greetingWord(DateTime(2026, 1, 1, 12)), 'Afternoon');
      expect(greetingWord(DateTime(2026, 1, 1, 18)), 'Evening');
    });

    testWidgets('畫面：最上面「Today」＋打招呼那一則', (tester) async {
      await _pump(tester, night: _night(score: 91.7, minutes: 401));
      expect(find.byKey(const Key('assistant-chip-today')), findsOneWidget);
      expect(find.textContaining('You slept 6h 41m last night'), findsOneWidget);
    });
  });

  group('頭像與狀態', () {
    test('心情對到圖檔；不認得的退回 bored（絕不 happy）', () {
      expect(buddyAvatarAsset(PetSpecies.cat, 'tired'), 'assets/avatars/cat_tired.png');
      expect(buddyAvatarAsset(PetSpecies.dog, 'whatever'), 'assets/avatars/dog_bored.png');
      expect(buddyAvatarAsset(PetSpecies.dog, null), 'assets/avatars/dog_bored.png');
    });

    test('狀態列：四種心情＋想答案時', () {
      expect(buddyStatus('happy'), 'Feeling happy');
      expect(buddyStatus('bored'), 'Feeling a bit bored');
      expect(buddyStatus('tired'), 'Feeling sleepy');
      expect(buddyStatus('anxious'), 'Feeling a little uneasy');
      expect(buddyStatus('??'), 'Feeling a bit bored');
      expect(buddyStatus('happy', thinking: true), 'thinking…');
    });

    testWidgets('有生成的頭像 → 用那張圖，不走裁切版（反向對照）', (tester) async {
      await _pump(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      expect(find.byKey(const Key('buddy-avatar-image')), findsOneWidget);
      expect(find.byKey(const Key('buddy-avatar-fallback')), findsNothing);
    });

    testWidgets('頭像圖讀不到 → 用裁切版，而且整個在圓框裡（不漫出來）', (tester) async {
      await _pump(tester, bundle: _MissingAvatarsBundle());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 50));
      final circle = tester.getRect(find.byKey(const Key('buddy-avatar')));
      expect(circle.width, 44);
      expect(find.byKey(const Key('buddy-avatar-fallback')), findsOneWidget);
      // ⚠️ 量**寵物實際畫出來**的範圍（含縮放），不是外框：外框永遠跟圓一樣大，量它抓不到漫出來
      final pet = find.descendant(
          of: find.byKey(const Key('buddy-avatar-fallback')), matching: find.byType(HomePet));
      final r = tester.getRect(pet);
      expect(r.left >= circle.left && r.right <= circle.right && r.top >= circle.top && r.bottom <= circle.bottom,
          isTrue, reason: 'pet $r 必須在圓框 $circle 裡');
    });

    testWidgets('想答案時：狀態列寫 thinking…；答完回到心情', (tester) async {
      final stub = _StubChat()..pending = Completer();
      await _pump(tester, chat: stub);
      await tester.enterText(find.byType(TextField).first, 'hi');
      await tester.tap(find.byIcon(Icons.send_rounded).first);
      await tester.pump();
      expect(find.text('thinking…'), findsOneWidget);
      stub.pending!.complete(const ChatResult(ChatStatus.ok, answer: 'ok'));
      await tester.pump();
      await tester.pump();
      expect(find.text('thinking…'), findsNothing);
      expect(find.text('Feeling a bit bored'), findsOneWidget);
    });
  });

  group('日期膠囊', () {
    const night = ChatPeriod.night('2026-11-18');
    const week = ChatPeriod.range('2026-11-09', '2026-11-15');
    ChatTurn a(ChatPeriod p) => ChatTurn.buddy('x', headline: 'x', period: p);

    test('同一晚連問兩題只出一次；換一段才再出', () {
      final turns = [
        const ChatTurn.user('q1'), a(night),
        const ChatTurn.user('q2'), a(night),
        const ChatTurn.user('q3'), a(week),
        const ChatTurn.user('q4'), a(week),
        const ChatTurn.user('q5'), a(night),
      ];
      expect(periodChipsAt(turns), {1, 5, 9});
    });

    test('沒有 period（舊訊息、答不出來）不出膠囊、也不打斷', () {
      final turns = [a(night), const ChatTurn.buddy('old'), a(night)];
      expect(periodChipsAt(turns), {0});
    });
  });

  group('背景動畫什麼時候要停', () {
    testWidgets('在畫面上 → 有在動（反向對照）', (tester) async {
      await _pump(tester);
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('切到別的分頁（visible: false）→ 全停', (tester) async {
      await _pump(tester, visible: false);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('系統開「減少動態效果」→ 全停', (tester) async {
      await _pump(tester, reduceMotion: true);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
