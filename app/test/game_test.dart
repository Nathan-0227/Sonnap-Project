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
import 'package:app/widgets/pet_card.dart';

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
    testWidgets('沒解鎖的點下去不發請求，直接講幾級解鎖', (tester) async {
      final stub = _StubGame();
      await pumpScreen(tester, ClosetScreen(service: stub));
      await tester.tap(find.byKey(const Key('closet-crown')));
      await tester.pump();
      expect(stub.equipCalls, isEmpty);
      expect(find.text('Crown unlocks at level 8.'), findsOneWidget);
    });

    testWidgets('解鎖的點下去就穿、穿著的再點一次就脫', (tester) async {
      final stub = _StubGame();
      await pumpScreen(tester, ClosetScreen(service: stub));
      // ⚠️ 要在點下去**之前**把假後端改成「穿著圍巾」：畫面在換裝完成的
      //    那一刻就會重讀衣櫃，點完才改的話它讀到的還是舊的。
      stub.closetResult = GameResult(GameStatus.ok, value: closet(closetJson(equipped: 'scarf')));
      await tester.tap(find.byKey(const Key('closet-scarf')));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const Key('closet-scarf')));
      await tester.pump();
      expect(stub.equipCalls, ['scarf', null]);
    });

    testWidgets('解鎖與否照抄後端：等級不夠但穿過的，照樣能穿', (tester) async {
      // 後端刻意「穿過就不收回」。Dart 用 level >= unlockLevel 自己判斷的話，
      // 第 2 級的人點皇冠會被擋下來——而後端說他可以穿。
      final stub = _StubGame(
          closetResult: GameResult(GameStatus.ok, value: closet(closetJson(crownOwned: true))));
      await pumpScreen(tester, ClosetScreen(service: stub));
      await tester.tap(find.byKey(const Key('closet-crown')));
      await tester.pump();
      expect(stub.equipCalls, ['crown']);
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
    testWidgets('穿了就畫在寵物身上', (tester) async {
      await pumpScreen(tester, const Scaffold(
        body: PetCard(message: 'hi', animationPath: 'missing.json', accessoryEmoji: '🧣'),
      ));
      expect(find.byKey(const Key('pet-accessory')), findsOneWidget);
      expect(find.text('🧣'), findsOneWidget);
    });

    testWidgets('沒穿就什麼都不畫', (tester) async {
      await pumpScreen(tester, const Scaffold(
        body: PetCard(message: 'hi', animationPath: 'missing.json'),
      ));
      expect(find.byKey(const Key('pet-accessory')), findsNothing);
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
          ),
        ),
      );
    }

    testWidgets('有後端 → 等級卡出現、寵物穿著衣櫃裡那一件', (tester) async {
      final stub = _StubGame(
          closetResult: GameResult(GameStatus.ok, value: closet(closetJson(equipped: 'scarf'))));
      await pumpHome(tester, stub);
      expect(find.byKey(const Key('game-level')), findsOneWidget);
      expect(find.byKey(const Key('pet-accessory')), findsOneWidget);
    });

    testWidgets('點衣櫃 → 打開衣櫃畫面', (tester) async {
      await pumpHome(tester, _StubGame());
      await tester.ensureVisible(find.text('Closet'));
      await tester.tap(find.text('Closet'));
      // ⚠️ 不用 pumpAndSettle：寵物的 Lottie 動畫永遠在動，會等到逾時。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ClosetScreen), findsOneWidget);
    });

    testWidgets('沒有後端 → 沒有等級卡，點衣櫃老實講要連後端', (tester) async {
      await pumpHome(tester, null);
      expect(find.byKey(const Key('game-level')), findsNothing);
      await tester.ensureVisible(find.text('Closet'));
      await tester.tap(find.text('Closet'));
      await tester.pump();
      expect(find.textContaining('needs the Sonnap backend'), findsOneWidget);
      expect(find.textContaining('available later'), findsNothing,
          reason: '功能已經做好了，缺的是連線；講成「以後才有」會讓人以為沒做');
    });
  });
}
