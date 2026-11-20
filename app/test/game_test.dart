// 遊戲化層的 App 端：服務層、等級卡、衣櫃、獎勵、寵物身上的衣服。
//
// 這一組守的是**「Dart 一格都不算」**這條紀律在遊戲層的版本——每一條
// 違反了都不會報錯，只會讓畫面跟後端講的不一樣：
//
//   1. 等級與進度條照抄後端。從 xp_total 自己反推等級，或自己除出進度，
//      升級那一刻就會跟後端不同步（後端規則日後調整時更是如此）。
//   2. 衣服解鎖與否照抄後端。Dart 用 level >= unlockLevel 自己判斷的話，
//      會把「曾經穿過、等級後來掉了」的那件收回——後端刻意不收回。
//   3. 領獎失敗的訊息照抄後端的 detail。409（這個窗格領過了）與
//      422（還沒完成）講的是不同的事，寫成一句通用的「失敗」就分不開。
//   4. 沒有後端時要老實講「要連上後端」，不是「以後才有」。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/pet2d/pet_catalog.dart' show accessories, cat01, dog01;
import 'package:app/pet2d/pet_models.dart' show AccessorySlot, PetMood;

import 'package:app/models/sleep_session.dart';
import 'package:app/screens/closet_screen.dart';
import 'package:app/screens/home_screen.dart';
import 'package:app/screens/rewards_screen.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/game_service.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/sleep_repository.dart';
import 'package:app/services/user_identity.dart';
import 'package:app/widgets/game_level_card.dart';
import 'package:app/widgets/home_pet.dart';

const String testUserId = '00000000-5017-4e01-9a30-000000000001';

Map<String, dynamic> gameJson({
  int level = 2,
  int xpTotal = 150,
  int? xpForNext = 100,
  double progress = 0.333,
  bool maxLevel = false,
  String stage = 'baby',
  List<Map<String, dynamic>> claimable = const [],
  List<Map<String, dynamic>>? badges,
}) =>
    {
      'user_id': testUserId,
      'level': level,
      'xp_total': xpTotal,
      'xp_into_level': 50,
      'xp_for_next': xpForNext,
      'progress': progress,
      'max_level': maxLevel,
      'growth_stage': stage,
      'xp_sources': {'behaviour': 90, 'sleep_quality': 60, 'challenge_rewards': 0},
      'recent_nights': const [],
      'claimable': claimable,
      'badges': badges ??
          const [
            {'badge_id': 'first_on_time', 'title': 'First on-time night', 'description': 'd', 'earned': true},
            {'badge_id': 'good_sleep', 'title': 'A good night', 'description': 'd', 'earned': false},
          ],
      'as_of': '2026-09-04',
      'notes': const {
        'rewards_follow_quality':
            'A late night with poor sleep earns 0 XP; having a record alone earns nothing.',
      },
    };

Map<String, dynamic> closetJson({int level = 2, String? equipped, bool crownOwned = false}) => {
      'user_id': testUserId,
      'level': level,
      'equipped_item_id': equipped,
      'items': [
        {'item_id': 'scarf', 'name': 'Cosy scarf', 'emoji': '🧣', 'unlock_level': 2,
         'unlocked': true, 'equipped': equipped == 'scarf'},
        {'item_id': 'crown', 'name': 'Crown', 'emoji': '👑', 'unlock_level': 8,
         'unlocked': crownOwned, 'equipped': equipped == 'crown'},
      ],
    };

GameState state(Map<String, dynamic> json) => GameState.fromJson(json);
ClosetState closet(Map<String, dynamic> json) => ClosetState.fromJson(json);

/// 直接回固定結果、記下呼叫的假服務。widget test 要驗的是「拿到之後怎麼畫」。
class _StubGame implements GameService {
  GameResult<GameState> game;
  GameResult<ClosetState> closetResult;
  GameResult<ClaimOutcome> claimResult;
  final List<String?> equipCalls = [];
  final List<String> claimCalls = [];

  _StubGame({
    GameResult<GameState>? game,
    GameResult<ClosetState>? closetResult,
    GameResult<ClaimOutcome>? claimResult,
  })  : game = game ?? GameResult(GameStatus.ok, value: state(gameJson())),
        closetResult = closetResult ?? GameResult(GameStatus.ok, value: closet(closetJson())),
        claimResult = claimResult ??
            const GameResult(GameStatus.ok,
                value: ClaimOutcome(xpAwarded: 40, level: 3, leveledUp: true));

  @override
  Future<GameResult<GameState>> fetchGame() async => game;

  @override
  Future<GameResult<ClosetState>> fetchCloset() async => closetResult;

  @override
  Future<GameResult<ClaimOutcome>> claim(String challengeId) async {
    claimCalls.add(challengeId);
    return claimResult;
  }

  @override
  Future<GameResult<String?>> equip(String? itemId) async {
    equipCalls.add(itemId);
    return GameResult(GameStatus.ok, value: itemId);
  }

  @override
  String get baseUrl => 'stub';

  @override
  UserIdentity get identity => const BuildTimeUserIdentity(overrideId: 'stub');

  @override
  Duration get timeout => const Duration(seconds: 1);
}

class _FakeBackend {
  late final HttpServer server;
  final List<Map<String, dynamic>> received = [];
  int claimStatus = 201;
  Map<String, dynamic> claimBody = const {
    'claimed': {'xp': 40},
    'level': 3,
    'leveled_up': true,
  };

  Future<String> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      received.add({
        'method': request.method,
        'path': request.uri.path,
        'query': request.uri.queryParameters,
        'body': body.isEmpty ? null : jsonDecode(body),
      });
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/game') {
        request.response.write(jsonEncode(gameJson()));
      } else if (request.uri.path == '/game/claim') {
        request.response.statusCode = claimStatus;
        request.response.write(jsonEncode(claimBody));
      } else {
        request.response.statusCode = 404;
        request.response.write(jsonEncode({'detail': 'nope'}));
      }
      await request.response.close();
    });
    return 'http://127.0.0.1:${server.port}';
  }

  Future<void> stop() => server.close(force: true);
}

class _ImmediateRepository implements SleepRepository {
  final SleepSession session;
  const _ImmediateRepository(this.session);

  @override
  Future<SleepSession> load() async => session;
}

/// 衣櫃預覽裡那隻寵物。試穿要看得到，所以直接讀 `HomePet` 拿到的衣服。
HomePet petIn(WidgetTester tester) =>
    tester.widget<HomePet>(find.byType(HomePet));

Future<void> pumpScreen(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('服務層', () {
    late _FakeBackend backend;
    late String baseUrl;
    HttpOverrides? saved;

    setUp(() async {
      // ⚠️ 同一個檔案裡有 testWidgets，TestWidgetsFlutterBinding 會把全域
      //    HttpClient 換成「一律回 400」的假實作。見 account_test.dart。
      saved = HttpOverrides.current;
      HttpOverrides.global = null;
      backend = _FakeBackend();
      baseUrl = await backend.start();
    });
    tearDown(() async {
      await backend.stop();
      HttpOverrides.global = saved;
    });

    test('GET /game 帶 user_id，等級與進度照抄', () async {
      final service = GameService(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      );
      final r = await service.fetchGame();
      expect(r.isOk, isTrue);
      expect(backend.received.single['query'], {'user_id': testUserId});
      expect(r.value!.level, 2);
      expect(r.value!.progress, 0.333);
      expect(r.value!.sources.behaviour, 90);
    });

    test('POST /game/claim 的 body 帶 user_id 與 challenge_id', () async {
      final service = GameService(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      );
      final r = await service.claim('streak_nights');
      expect(r.isOk, isTrue);
      expect(r.value!.xpAwarded, 40);
      expect(backend.received.single['body'],
          {'user_id': testUserId, 'challenge_id': 'streak_nights'});
    });

    test('領獎被拒時，後端的 detail 原樣帶出來（409 與 422 講的不是同一件事）', () async {
      backend.claimStatus = 409;
      backend.claimBody = {'detail': 'Already claimed for this window. Come back in the next one.'};
      final service = GameService(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      );
      final r = await service.claim('streak_nights');
      expect(r.isOk, isFalse);
      expect(r.httpStatus, 409);
      expect(r.message, 'Already claimed for this window. Come back in the next one.');
    });

    test('沒有後端 / 沒有帳號 → 分得開', () async {
      expect((await const GameService(
                  baseUrl: '', identity: BuildTimeUserIdentity(overrideId: testUserId))
              .fetchGame())
          .status, GameStatus.noBackend);
      expect((await const GameService(
                  baseUrl: 'http://127.0.0.1:1', identity: BuildTimeUserIdentity(overrideId: ''))
              .fetchGame())
          .status, GameStatus.noUser);
    });
  });

  group('等級卡：一格都不在 Dart 算', () {
    testWidgets('等級照抄後端，就算跟 XP 對不上也照抄', (tester) async {
      // 後端說第 7 級、進度 90%，但 xp_total 只有 10。
      // Dart 自己從 xp_total 反推的話會畫成第 1 級——這一條就是要擋那件事。
      await pumpScreen(
        tester,
        Scaffold(body: GameLevelCard(state: state(gameJson(level: 7, xpTotal: 10, progress: 0.9)))),
      );
      expect(find.text('Level 7'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(find.byKey(const Key('game-progress')));
      expect(bar.value, 0.9);
    });

    testWidgets('XP 的來源拆開列（行為是大宗要看得到）', (tester) async {
      await pumpScreen(tester, Scaffold(body: GameLevelCard(state: state(gameJson()))));
      expect(find.text('Behaviour 90 · Sleep 60 · Rewards 0 XP'), findsOneWidget);
    });

    testWidgets('最高級時不寫「0 XP to the next level」', (tester) async {
      await pumpScreen(tester,
          Scaffold(body: GameLevelCard(state: state(gameJson(maxLevel: true, xpForNext: null, progress: 1)))));
      expect(find.text('Max level reached'), findsOneWidget);
      expect(find.textContaining('to the next level'), findsNothing);
    });

    testWidgets('有獎勵可以領才提示', (tester) async {
      await pumpScreen(tester, Scaffold(body: GameLevelCard(state: state(gameJson(claimable: [
        {'challenge_id': 'streak_nights', 'title': 'Three nights in a row', 'xp': 40},
      ])))));
      expect(find.text('1 reward ready to claim'), findsOneWidget);
    });
  });

  group('衣櫃', () {
    testWidgets('沒解鎖的點下去不試穿也不發請求，直接講幾級解鎖', (tester) async {
      final stub = _StubGame();
      await pumpScreen(tester, ClosetScreen(service: stub));
      await tester.tap(find.byKey(const Key('closet-crown')));
      await tester.pump();
      expect(stub.equipCalls, isEmpty);
      expect(find.text('Crown unlocks at level 8.'), findsOneWidget);
      // 連試穿都不行：寵物身上不能變成皇冠。
      expect(petIn(tester).equippedItemId, isNull);
    });

    testWidgets('點一下只是試穿，Confirm 才送後端', (tester) async {
      // ⚠️ 這是 2026-11-18 改版的核心：壞掉的話會變成「點到就直接存進後端」，
      //    而畫面照樣顯示得好好的——試穿的意義整個消失。
      final stub = _StubGame();
      await pumpScreen(tester, ClosetScreen(service: stub));
      await tester.tap(find.byKey(const Key('closet-scarf')));
      await tester.pump();
      expect(stub.equipCalls, isEmpty, reason: '試穿不可以送後端');
      // 但預覽要立刻換上去。
      expect(petIn(tester).equippedItemId, 'scarf');
      expect(find.text('Trying it on · not saved yet'), findsOneWidget);

      await tester.tap(find.byKey(const Key('closet-confirm')));
      await tester.pump();
      expect(stub.equipCalls, ['scarf']);
    });

    testWidgets('點 None 再 Confirm = 脫掉（送 null）', (tester) async {
      final stub = _StubGame(
          closetResult: GameResult(GameStatus.ok, value: closet(closetJson(equipped: 'scarf'))));
      await pumpScreen(tester, ClosetScreen(service: stub));
      expect(petIn(tester).equippedItemId, 'scarf');
      await tester.tap(find.byKey(const Key('closet-none')));
      await tester.pump();
      expect(petIn(tester).equippedItemId, isNull);
      await tester.tap(find.byKey(const Key('closet-confirm')));
      await tester.pump();
      expect(stub.equipCalls, [null]);
    });

    testWidgets('沒改就按 Confirm 不發請求', (tester) async {
      final stub = _StubGame(
          closetResult: GameResult(GameStatus.ok, value: closet(closetJson(equipped: 'scarf'))));
      await pumpScreen(tester, ClosetScreen(service: stub));
      await tester.tap(find.byKey(const Key('closet-confirm')));
      await tester.pump();
      expect(stub.equipCalls, isEmpty);
    });

    testWidgets('左上 ‹ 是不存直接離開：試穿過也不送後端', (tester) async {
      final stub = _StubGame();
      await pumpScreen(tester, ClosetScreen(service: stub));
      await tester.tap(find.byKey(const Key('closet-scarf')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('closet-back')));
      await tester.pump();
      expect(stub.equipCalls, isEmpty);
    });

    testWidgets('最上面大字是暱稱（寵物沒有名字），底下 Lv', (tester) async {
      final stub = _StubGame();
      await pumpScreen(tester, ClosetScreen(service: stub, displayName: 'Nathan'));
      expect(find.text('Nathan'), findsOneWidget);
      expect(find.text('Lv. 2'), findsOneWidget);
    });

    testWidgets('解鎖與否照抄後端：等級不夠但穿過的，照樣能穿', (tester) async {
      // 後端刻意「穿過就不收回」。Dart 用 level >= unlockLevel 自己判斷的話，
      // 第 2 級的人點皇冠會被擋下來——而後端說他可以穿。
      final stub = _StubGame(
          closetResult: GameResult(GameStatus.ok, value: closet(closetJson(crownOwned: true))));
      await pumpScreen(tester, ClosetScreen(service: stub));
      await tester.tap(find.byKey(const Key('closet-crown')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('closet-confirm')));
      await tester.pump();
      expect(stub.equipCalls, ['crown']);
    });

    testWidgets('沒有真圖的衣服照樣分得到類（不會點了分類就消失）', (tester) async {
      // ⚠️ 皇冠沒有 PNG。分類若是看「有沒有真圖」來判斷插槽，它在 Head 裡會整件不見，
      //    而畫面不會報錯——使用者只會覺得衣櫃漏了一件。
      final stub = _StubGame(
          closetResult: GameResult(GameStatus.ok, value: closet(closetJson(crownOwned: true))));
      await pumpScreen(tester, ClosetScreen(service: stub));
      await tester.tap(find.byKey(const Key('closet-filter-head')));
      await tester.pump();
      expect(find.byKey(const Key('closet-crown')), findsOneWidget);
      expect(find.byKey(const Key('closet-scarf')), findsNothing);
      // None 不屬於任何插槽，但任何分類下都必須在——不然沒辦法脫衣服。
      expect(find.byKey(const Key('closet-none')), findsOneWidget);
    });

    testWidgets('連不上後端要講清楚，不畫一個空衣櫃', (tester) async {
      final stub = _StubGame(closetResult: const GameResult(GameStatus.failed));
      await pumpScreen(tester, ClosetScreen(service: stub));
      expect(find.textContaining('cannot be reached'), findsOneWidget);
    });
  });

  group('獎勵', () {
    testWidgets('按領取 → 呼叫後端、顯示拿到幾 XP', (tester) async {
      final stub = _StubGame(game: GameResult(GameStatus.ok, value: state(gameJson(claimable: [
        {'challenge_id': 'streak_nights', 'title': 'Three nights in a row', 'xp': 40},
      ]))));
      await pumpScreen(tester, RewardsScreen(service: stub));
      await tester.tap(find.byKey(const Key('claim-streak_nights')));
      await tester.pump();
      expect(stub.claimCalls, ['streak_nights']);
      // 按鈕上本來就寫著「Claim +40 XP」，所以驗升級提示那一句，不驗「+40 XP」。
      expect(find.textContaining('level up! You are now level 3'), findsOneWidget);
    });

    testWidgets('被拒時照抄後端的話（409 領過了 ≠ 422 還沒完成）', (tester) async {
      final stub = _StubGame(
        game: GameResult(GameStatus.ok, value: state(gameJson(claimable: [
          {'challenge_id': 'streak_nights', 'title': 'Three nights in a row', 'xp': 40},
        ]))),
        claimResult: const GameResult(GameStatus.failed,
            httpStatus: 409, message: 'Already claimed for this window. Come back in the next one.'),
      );
      await pumpScreen(tester, RewardsScreen(service: stub));
      await tester.tap(find.byKey(const Key('claim-streak_nights')));
      await tester.pump();
      expect(find.text('Already claimed for this window. Come back in the next one.'), findsOneWidget);
    });

    testWidgets('沒有東西可以領時，講清楚怎樣才會有', (tester) async {
      await pumpScreen(tester, RewardsScreen(service: _StubGame()));
      expect(find.byKey(const Key('rewards-empty')), findsOneWidget);
    });

    testWidgets('徽章拿到的與沒拿到的看得出差別', (tester) async {
      await pumpScreen(tester, RewardsScreen(service: _StubGame()));
      final earned = find.descendant(
          of: find.byKey(const Key('badge-first_on_time')), matching: find.byIcon(Icons.verified_rounded));
      final locked = find.descendant(
          of: find.byKey(const Key('badge-good_sleep')), matching: find.byIcon(Icons.lock_outline_rounded));
      expect(earned, findsOneWidget);
      expect(locked, findsOneWidget);
    });
  });

  group('寵物身上的衣服', () {
    // 帽子、眼鏡、圍巾有隊友畫的真圖；蝴蝶結、高帽、皇冠沒有，疊 emoji。
    testWidgets('有真圖的那件 → 畫真圖，不疊 emoji', (tester) async {
      await pumpScreen(tester, const Scaffold(
        body: HomePet(mood: 'happy', equippedItemId: 'scarf', accessoryEmoji: '🧣'),
      ));
      expect(find.byKey(const Key('pet-accessory')), findsOneWidget);
      expect(find.text('🧣'), findsNothing, reason: '真圖與 emoji 不能同時出現');
    });

    testWidgets('沒有圖的那件 → 疊 emoji（看得到比好看重要）', (tester) async {
      // 2026-11-19 起後端 6 件都有真圖；這裡用一件「後端之後新增、還沒有圖」的假衣服守退路。
      await pumpScreen(tester, const Scaffold(
        body: HomePet(mood: 'happy', equippedItemId: 'party_hat', accessoryEmoji: '🥳'),
      ));
      expect(find.byKey(const Key('pet-accessory')), findsOneWidget);
      expect(find.text('🥳'), findsOneWidget);
    });

    testWidgets('沒穿就什麼都不畫', (tester) async {
      await pumpScreen(tester, const Scaffold(body: HomePet(mood: 'happy')));
      expect(find.byKey(const Key('pet-accessory')), findsNothing);
    });

    test('禮帽、皇冠縮小坐進兩耳之間；其他衣服照錨點原尺寸', () {
      // 2026-11-19 使用者：硬帽子照睡帽的錨點放會蓋住耳朵。只動這兩頂，
      // 錨點（隊友在預覽工具裡對好的）一個都不改。
      for (final a in accessories) {
        final hard = a.id == 'star_top_hat' || a.id == 'moon_crown';
        expect(a.fit < 1, hard, reason: a.id);
        if (!hard) {
          expect(a.drop, 0, reason: a.id);
          expect(a.poseFits, isEmpty, reason: a.id);
        }
      }
    });

    test('禮帽、皇冠：小狗與貓的四種心情各有使用者挑的戴法', () {
      // 漏一個姿勢的話那個姿勢會退回預設大小，畫面不會報錯
      for (final id in ['star_top_hat', 'moon_crown']) {
        final a = accessories.firstWhere((x) => x.id == id);
        for (final pet in ['dog01', 'cat01']) {
          for (final mood in PetMood.values) {
            expect(a.poseFits.containsKey('$pet.${mood.name}'), isTrue, reason: '$id $pet.${mood.name}');
          }
        }
      }
    });

    test('衣櫃 item_id 對得上八件圖', () {
      expect(layeredAccessoryFor('cap')?.id, 'sleep_hat');
      expect(layeredAccessoryFor('glasses')?.id, 'round_glasses');
      expect(layeredAccessoryFor('scarf')?.id, 'night_scarf');
      // 2026-11-20 粉紅的換成紅的（隊友 v4.6.48）
      expect(layeredAccessoryFor('bow')?.id, 'bow_red');
      // 2026-11-19 使用者生成的兩頂
      expect(layeredAccessoryFor('top_hat')?.id, 'star_top_hat');
      expect(layeredAccessoryFor('crown')?.id, 'moon_crown');
      // 2026-11-20 隊友 v4.6.48 新增
      expect(layeredAccessoryFor('beret')?.id, 'beret_leaf');
      expect(layeredAccessoryFor('sunglasses')?.id, 'sunglasses_round');
      // ⚠️ 反面：沒有圖的必須回 null（會改疊 emoji）。
      //    少了這一條，哪天隨便對應一個不存在的 id 也不會被抓到。
      for (final none in ['party_hat', null]) {
        expect(layeredAccessoryFor(none), isNull, reason: '$none');
      }
      // 每一個對應得到的 id 都必須真的在 accessories 裡（打錯字就會回 null）。
      for (final itemId in kLayeredAccessoryFor.keys) {
        expect(layeredAccessoryFor(itemId), isNotNull, reason: itemId);
      }
    });

    test('後端每一件衣服都有圖、都有分類（讀 game/inventory.py）', () {
      // 後端加了一件、這邊忘了接：不報錯，只會疊 emoji、點分類整件消失。
      final src = File('../game/inventory.py').readAsStringSync();
      final ids = RegExp(r'"item_id":\s*"(\w+)"')
          .allMatches(src)
          .map((m) => m.group(1)!)
          .toList();
      expect(ids, isNotEmpty);
      for (final id in ids) {
        expect(layeredAccessoryFor(id), isNotNull, reason: '$id 沒有圖');
        expect(kClosetSlotFor.containsKey(id), isTrue, reason: '$id 沒有分類');
      }
    });

    test('貝雷帽、紅蝴蝶結每個姿勢都用自己的定位點', () {
      // 漏一格會悄悄退回插槽錨點（那是照睡帽、圍巾對的），不報錯。
      for (final pet in [dog01, cat01]) {
        for (final id in ['beret_leaf', 'bow_red']) {
          for (final mood in PetMood.values) {
            final own = pet.accessoryAnchors[id]?[mood];
            expect(own, isNotNull, reason: '${pet.id}.${mood.name} $id');
            final slot = id == 'beret_leaf' ? AccessorySlot.head : AccessorySlot.neck;
            final used = pet.anchorFor(mood, slot, accessoryId: id);
            expect(used.position, own!.position, reason: '${pet.id}.${mood.name} $id');
          }
        }
        // 反面：沒有自己定位點的（墨鏡）照用插槽的
        expect(
          pet.anchorFor(PetMood.happy, AccessorySlot.face, accessoryId: 'sunglasses_round').position,
          pet.anchorFor(PetMood.happy, AccessorySlot.face).position,
        );
      }
    });
  });

  group('接上首頁', () {
    late SleepSession sample;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      sample = await const AssetSleepRepository().load();
    });

    Future<void> pumpHome(WidgetTester tester, GameService? game) async {
      // ⚠️ 真的 App 裡首頁外面包著 MainPage 的 Scaffold。少了它，
      //    header_card 的 InkWell 會丟「No Material widget found」。
      await pumpScreen(
        tester,
        Scaffold(
          body: HomeScreen(
            repository: _ImmediateRepository(sample),
            bedMarks: BedMarkStore(InMemoryKeyValueStore()),
            game: game,
            // 早上：等級卡、衣櫃在白天版
            clock: () => DateTime(2026, 11, 12, 9),
          ),
        ),
      );
    }

    testWidgets('有後端 → 等級徽章出現、寵物穿著衣櫃裡那一件', (tester) async {
      final stub = _StubGame(
          closetResult: GameResult(GameStatus.ok, value: closet(closetJson(equipped: 'scarf'))));
      await pumpHome(tester, stub);
      expect(find.byKey(const Key('level-badge')), findsOneWidget);
      expect(find.byKey(const Key('pet-accessory')), findsOneWidget);
      // 2026-11-13 使用者定：等級在寵物上面，不在標題旁邊
      final badge = tester.getRect(find.byKey(const Key('level-badge')));
      final pet = tester.getRect(find.byKey(const Key('home-pet')));
      final title = tester.getRect(find.byKey(const Key('day-title')));
      expect(badge.bottom, lessThanOrEqualTo(pet.top));
      expect(badge.center.dx, closeTo(pet.center.dx, 2));
      expect(badge.top, greaterThan(title.bottom));
      // Hi 上方加留白之後，時鐘卡曾經壓到這個徽章（實機截圖抓到）
      final clock = tester.getRect(find.byKey(const Key('bedtime-countdown')));
      expect(badge.top, greaterThanOrEqualTo(clock.bottom));
    });

    testWidgets('點衣櫃 → 打開衣櫃畫面', (tester) async {
      await pumpHome(tester, _StubGame());
      await tester.tap(find.byKey(const Key('open-closet')));
      // ⚠️ 不用 pumpAndSettle：寵物的 Lottie 動畫永遠在動，會等到逾時。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ClosetScreen), findsOneWidget);
    });

    testWidgets('沒有後端 → 沒有等級徽章，點衣櫃老實講要連後端', (tester) async {
      await pumpHome(tester, null);
      expect(find.byKey(const Key('level-badge')), findsNothing);
      await tester.tap(find.byKey(const Key('open-closet')));
      await tester.pump();
      expect(find.textContaining('needs the Sonnap backend'), findsOneWidget);
      expect(find.textContaining('available later'), findsNothing,
          reason: '功能已經做好了，缺的是連線；講成「以後才有」會讓人以為沒做');
    });
  });
}
