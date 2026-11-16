// 好友畫面：服務層與畫面。
//
// 守的東西：
//   1. 沒有後端時老實講，**而且原本那四個假朋友（Katy、Andrew…）一個都不出現**。
//      不要拿任何人的名字當佔位符——首頁曾經對 Nathan 說「Good morning Jeremy」。
//   2. 「幾點放下手機」走 parseWallClock()。`DateTime.tryParse("...+08:00")`
//      回的是 UTC，23:05 會顯示成 15:05，而且沒有任何錯誤訊息。
//   3. 排行照後端的順序，Dart 不重排（同分怎麼排是後端的規則）。
//   4. 篩選列沒有「Sick」——朋友之間只分享行為版心情，那個選項永遠篩不出人。
//   5. 加好友失敗時照抄後端的話（404／409／422 講的是不同的事）。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/screens/friends_screen.dart';
import 'package:app/services/friends_service.dart';
import 'package:app/services/user_identity.dart';
import 'package:app/widgets/friend_night_card.dart' show FriendNightPage;
import 'package:app/widgets/mood_filter_bar.dart';
import 'package:app/widgets/top_streak_card.dart';

const String testUserId = '00000000-5017-4e01-9a30-000000000001';

Map<String, dynamic> friendJson(
  String handle,
  String name, {
  String? mood = 'happy',
  String? lightsOut = '2026-09-02T23:05:00+08:00',
  bool? late = false,
  int streak = 2,
  int best = 3,
  List<String>? week,
}) =>
    {
      'handle': handle,
      'display_name': name,
      'pet_mood': mood,
      'last_night_date': '2026-09-03',
      'last_lights_out_at': lightsOut,
      'last_night_late': late,
      'current_streak': streak,
      'best_streak': best,
      'late_night_ratio': 0.25,
      'late_nights': 1,
      'recorded_nights': 4,
      if (week != null)
        'streak_week': [
          for (final (i, st) in week.indexed)
            {'date': '2026-09-${(i + 1).toString().padLeft(2, '0')}', 'status': st},
        ],
    };

Map<String, dynamic> stateJson({List<Map<String, dynamic>>? friends, List<Map<String, dynamic>>? board}) => {
      'my_invite_code': 'K7QM2P',
      'friends': friends ??
          [
            friendJson('BOB234', 'Bob'),
            friendJson('CAR567', 'Carol', mood: 'tired', lightsOut: '2026-09-03T02:30:00+08:00', late: true, streak: 0, best: 1),
          ],
      'leaderboard': board ??
          const [
            {'rank': 1, 'handle': 'BOB234', 'display_name': 'Bob', 'current_streak': 2, 'best_streak': 3},
            {'rank': 2, 'handle': 'CAR567', 'display_name': 'Carol', 'current_streak': 0, 'best_streak': 1},
          ],
      'notes': const {'what_is_shared': 'Friends only see behaviour.'},
    };

class _StubFriends implements FriendsService {
  FriendsResult<FriendsState> result;
  FriendsResult<FriendSummary> addResult;
  final List<String> addCalls = [];
  final List<String> removeCalls = [];
  List<FriendNightCard> feed = const [];

  _StubFriends({FriendsResult<FriendsState>? result, FriendsResult<FriendSummary>? addResult})
      : result = result ?? FriendsResult(FriendsStatus.ok, value: FriendsState.fromJson(stateJson())),
        addResult = addResult ??
            FriendsResult(FriendsStatus.ok, value: FriendSummary.fromJson(friendJson('DAV890', 'Dave')));

  @override
  Future<FriendsResult<FriendsState>> fetch() async => result;

  @override
  Future<FriendsResult<FriendSummary>> add(String inviteCode) async {
    addCalls.add(inviteCode);
    return addResult;
  }

  @override
  Future<FriendsResult<String>> remove(String handle) async {
    removeCalls.add(handle);
    return FriendsResult(FriendsStatus.ok, value: handle);
  }

  // 2026-11-15：分享設定與動態卡。這幾支畫面測試不看它們，回空的就好
  @override
  Future<FriendsResult<List<FriendNightCard>>> fetchFeed() async =>
      FriendsResult(FriendsStatus.ok, value: feed);

  @override
  Future<FriendsResult<(FriendSummary, FriendNightCard?)>> fetchFriend(String handle) async =>
      const FriendsResult(FriendsStatus.failed);

  @override
  Future<FriendsResult<SharingSettings>> fetchSharing() async =>
      const FriendsResult(FriendsStatus.failed);

  @override
  Future<FriendsResult<SharingSettings>> patchSharing(
          {Map<String, bool>? items, String? timePrecision, String? petSpecies, String? scene}) async =>
      const FriendsResult(FriendsStatus.failed);

  @override
  Future<FriendsResult<(FriendSummary, FriendNightCard?)>> fetchPreview() async =>
      const FriendsResult(FriendsStatus.failed);

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
  int addStatus = 201;
  Map<String, dynamic> addBody = {'friend': friendJson('BOB234', 'Bob')};
  Duration feedDelay = Duration.zero;

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
      if (request.method == 'GET' && request.uri.path == '/friends/feed') {
        await Future<void>.delayed(feedDelay);
        request.response.write(jsonEncode({
          'cards': [
            {'handle': 'BOB234', 'display_name': 'Bob', 'date': '2026-09-03', 'scene': 'lake',
             'items': {'on_time': true}},
          ],
        }));
      } else if (request.method == 'GET') {
        request.response.write(jsonEncode(stateJson()));
      } else if (request.method == 'POST') {
        request.response.statusCode = addStatus;
        request.response.write(jsonEncode(addBody));
      } else {
        request.response.write(jsonEncode({'removed': 'BOB234'}));
      }
      await request.response.close();
    });
    return 'http://127.0.0.1:${server.port}';
  }

  Future<void> stop() => server.close(force: true);
}

/// 打開好友頁。2026-11-16 起預設在 Feed 分頁；名單、邀請碼、排行在 Friends 分頁，
/// 所以預設切過去（要看 Feed 的測試傳 friendsTab: false）。
Future<void> pump(WidgetTester tester, FriendsService? service, {bool friendsTab = true}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: FriendsScreen(service: service))));
  await tester.pump();
  await tester.pump();
  final tab = find.byKey(const Key('tab-friends'));
  if (friendsTab && tab.evaluate().isNotEmpty) {
    await tester.tap(tab);
    await tester.pump();
  }
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

    FriendsService service() => FriendsService(
          baseUrl: baseUrl,
          identity: const BuildTimeUserIdentity(overrideId: testUserId),
        );

    test('GET /friends 帶 user_id，解析得出來', () async {
      final r = await service().fetch();
      expect(r.isOk, isTrue);
      expect(backend.received.single['query'], {'user_id': testUserId});
      expect(r.value!.myInviteCode, 'K7QM2P');
      expect(r.value!.friends.map((f) => f.displayName), ['Bob', 'Carol']);
    });

    test('動態牆比一般逾時慢也等得到（2026-11-16 實機：後端 6.3 秒、App 3 秒就放棄，畫面說沒有動態）', () async {
      backend.feedDelay = const Duration(milliseconds: 1500);
      final quick = FriendsService(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
        timeout: const Duration(seconds: 1),
      );
      final r = await quick.fetchFeed();
      expect(r.isOk, isTrue);
      expect(r.value!.single.scene, 'lake');
      expect(FriendsService.feedTimeout, greaterThanOrEqualTo(const Duration(seconds: 10)));
    });

    test('加好友：body 帶 user_id 與去掉空白的邀請碼', () async {
      await service().add('  bob234  ');
      expect(backend.received.single['body'], {'user_id': testUserId, 'invite_code': 'bob234'});
    });

    test('加好友被拒：後端的話原樣帶出來', () async {
      backend.addStatus = 409;
      backend.addBody = {'detail': 'You are already friends.'};
      final r = await service().add('BOB234');
      expect(r.isOk, isFalse);
      expect(r.httpStatus, 409);
      expect(r.message, 'You are already friends.');
    });

    test('解除好友：DELETE /friends/{邀請碼}?user_id=...', () async {
      await service().remove('BOB234');
      final call = backend.received.single;
      expect(call['method'], 'DELETE');
      expect(call['path'], '/friends/BOB234');
      expect(call['query'], {'user_id': testUserId});
    });
  });

  group('畫面', () {
    testWidgets('沒有後端 → 老實講，而且原本的假朋友一個都不出現', (tester) async {
      await pump(tester, null);
      expect(find.byKey(const Key('friends-no-backend')), findsOneWidget);
      for (final fake in ['Katy', 'Andrew', 'Emil', 'Heidi', 'Jamie', 'Mochi', 'Coco', 'Nala', 'Dango']) {
        expect(find.textContaining(fake), findsNothing, reason: '不要拿任何人的名字當佔位符');
      }
    });

    testWidgets('有後端 → 邀請碼、朋友名字都是後端給的', (tester) async {
      await pump(tester, _StubFriends());
      expect(find.text('K7QM2P'), findsOneWidget);
      expect(find.text('Bob'), findsWidgets);
      expect(find.text('Carol'), findsWidgets);
    });

    testWidgets('放下手機的時刻是牆鐘時間，不是 UTC', (tester) async {
      await pump(tester, _StubFriends());
      expect(find.textContaining('Phone down 23:05'), findsOneWidget);
      expect(find.textContaining('15:05'), findsNothing,
          reason: 'DateTime.tryParse("...+08:00") 回 UTC，.hour 會早 8 小時');
    });

    testWidgets('準時／熬夜人數照後端的 last_night_late', (tester) async {
      await pump(tester, _StubFriends());
      expect(tester.widget<Text>(find.byKey(const Key('circle-on-time'))).data, '1');
      expect(tester.widget<Text>(find.byKey(const Key('circle-late'))).data, '1');
    });

    testWidgets('排行照後端的順序，Dart 不重排', (tester) async {
      // 後端把連續 0 晚的 Carol 排第一——就算看起來不合理也照抄。
      // Dart 自己依 streak 重排的話，同分規則就有第二個定義處。
      await pump(tester, _StubFriends(result: FriendsResult(FriendsStatus.ok,
          value: FriendsState.fromJson(stateJson(board: const [
            {'rank': 1, 'handle': 'CAR567', 'display_name': 'Carol', 'current_streak': 0, 'best_streak': 1},
            {'rank': 2, 'handle': 'BOB234', 'display_name': 'Bob', 'current_streak': 2, 'best_streak': 3},
          ])))));
      final card = tester.widget<TopStreakCard>(find.byType(TopStreakCard));
      expect(card.users.map((u) => u.name), ['Carol', 'Bob']);
    });

    testWidgets('篩選列沒有「Sick」', (tester) async {
      await pump(tester, _StubFriends());
      final bar = tester.widget<MoodFilterBar>(find.byType(MoodFilterBar));
      expect(bar.options!.map((m) => m['label']), isNot(contains('Sick')));
    });

    testWidgets('篩 Tired 只剩熬夜的那位', (tester) async {
      await pump(tester, _StubFriends());
      await tester.tap(find.textContaining('Tired').first);
      await tester.pump();
      expect(find.byKey(const Key('friend-CAR567')), findsOneWidget);
      expect(find.byKey(const Key('friend-BOB234')), findsNothing);
    });

    testWidgets('加好友：輸入邀請碼 → 呼叫後端', (tester) async {
      final stub = _StubFriends();
      await pump(tester, stub);
      await tester.tap(find.byKey(const Key('add-friend')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('invite-field')), 'dav890');
      await tester.tap(find.byKey(const Key('invite-submit')));
      await tester.pumpAndSettle();
      expect(stub.addCalls, ['dav890']);
      expect(find.text('Added Dave.'), findsOneWidget);
    });

    testWidgets('加好友被拒：照抄後端的話', (tester) async {
      final stub = _StubFriends(
          addResult: const FriendsResult(FriendsStatus.failed, httpStatus: 422, message: 'That is your own invite code.'));
      await pump(tester, stub);
      await tester.tap(find.byKey(const Key('add-friend')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('invite-field')), 'K7QM2P');
      await tester.tap(find.byKey(const Key('invite-submit')));
      await tester.pumpAndSettle();
      expect(find.text('That is your own invite code.'), findsOneWidget);
    });

    testWidgets('點朋友 → 可以解除好友', (tester) async {
      final stub = _StubFriends();
      await pump(tester, stub);
      await tester.tap(find.byKey(const Key('friend-BOB234')));
      // 彈出來的卡上有會動的寵物與火，pumpAndSettle 等不到停——一格一格推到滑上來
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.ensureVisible(find.byKey(const Key('remove-friend')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('remove-friend')));
      await tester.pump(const Duration(seconds: 1));
      expect(stub.removeCalls, ['BOB234']);
    });

    testWidgets('打開預設在 Feed；沒有動態時講清楚，名單在另一個分頁', (tester) async {
      await pump(tester, _StubFriends(), friendsTab: false);
      expect(find.byKey(const Key('feed-empty')), findsOneWidget);
      expect(find.text('K7QM2P'), findsNothing);
      await tester.tap(find.byKey(const Key('tab-friends')));
      await tester.pump();
      expect(find.text('K7QM2P'), findsOneWidget);
      expect(find.byKey(const Key('feed-empty')), findsNothing);
    });

    testWidgets('Feed：每張卡是他選的場景；連續天數的橫幅只在他最近那一晚、3 晚以上才出現', (tester) async {
      final stub = _StubFriends(result: FriendsResult(FriendsStatus.ok,
          value: FriendsState.fromJson(stateJson(friends: [
        friendJson('BOB234', 'Bob', streak: 4,
            week: ['late', 'on_time', 'on_time', 'on_time', 'on_time', 'future', 'future']),
        friendJson('CAR567', 'Carol', streak: 2),
      ]))));
      stub.feed = const [
        // 項目多到資訊卡要捲（才驗得到最底下那一排有沒有被系統按鍵列蓋住）
        FriendNightCard(handle: 'BOB234', displayName: 'Bob', date: '2026-09-03', scene: 'lake',
            items: {'sleep_duration': 412, 'on_time': true, 'awake': {'count': 2},
              'sleeping_hr': {'avg': 56}, 'stress': {'high': 1980}, 'steps': {'steps': 8000},
              'calories': {'active': 420}, 'level': {'level': 4}, 'outfit': {'badges': 3},
              'phone_down_time': '23:10', 'time_in_bed': 440, 'resting_hr': 55}),
        FriendNightCard(handle: 'CAR567', displayName: 'Carol', date: '2026-09-03', items: {'on_time': false}),
        FriendNightCard(handle: 'BOB234', displayName: 'Bob', date: '2026-09-02', scene: 'lake',
            items: {'on_time': true}),
      ];
      await pump(tester, stub, friendsTab: false);
      // 手機大小（內容要長到會捲）＋底部的系統按鍵列
      tester.view.physicalSize = const Size(400, 560);
      tester.view.padding = const FakeViewPadding(bottom: 48);
      await tester.pump();
      expect(find.byKey(const Key('feed-card-BOB234-2026-09-03')), findsOneWidget);
      final scenes = tester.widgetList<Image>(find.byKey(const Key('card-scene')))
          .map((i) => (i.image as AssetImage).assetName).toList();
      expect(scenes, [
        'assets/backgrounds/scene_lake.jpg',
        'assets/backgrounds/scene_campfire.jpg', // 沒選 → 預設
        'assets/backgrounds/scene_lake.jpg',
      ]);
      // 換一天才插分隔線：兩條（9/3、9/2），同一天的兩張卡之間沒有
      expect(find.text('Thu, Sep 3'), findsOneWidget);
      expect(find.text('Wed, Sep 2'), findsOneWidget);
      expect(find.byKey(const Key('feed-day-0')), findsOneWidget);
      expect(find.byKey(const Key('feed-day-1')), findsNothing);
      expect(find.byKey(const Key('feed-day-2')), findsOneWidget);
      expect(find.byKey(const Key('card-streak')), findsOneWidget);
      expect(find.text('Bob reached a 4-night streak'), findsOneWidget);
      expect(find.textContaining('Carol reached'), findsNothing); // 只有 2 晚
      // 火焰在場景裡寵物後面：Bob 4 晚＝大火、Carol 2 晚＝小火，只在各自最近那一晚的卡上
      expect(find.byKey(const Key('streak-flames-2')), findsOneWidget);
      expect(find.byKey(const Key('streak-flames-1')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('feed-card-BOB234-2026-09-03')),
          matching: find.byKey(const Key('streak-flames-2')),
        ),
        findsOneWidget,
      );
      // 這週的軌道也在外面的卡上（只有 Bob 有給、只在最近那一晚）
      expect(find.byKey(const Key('card-week')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('feed-card-BOB234-2026-09-03')),
          matching: find.byKey(const Key('card-week')),
        ),
        findsOneWidget,
      );

      // 點卡片＝See all：同一張卡的完整版
      await tester.tap(find.byKey(const Key('feed-card-BOB234-2026-09-03')));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('night-detail')), findsOneWidget);
      // 火和這週的軌道都在完整頁的卡上，不再另外放一張 Streak 卡
      expect(
        find.descendant(
          of: find.byKey(const Key('night-detail')),
          matching: find.byKey(const Key('card-week')),
        ),
        findsOneWidget,
      );
      // Strava 式（2026-11-16 使用者定）：上面是場景＋寵物（火在後面），下面一張資訊卡
      final page = find.byType(FriendNightPage);
      expect(find.descendant(of: page, matching: find.byKey(const Key('night-scene'))), findsOneWidget);
      expect(find.descendant(of: page, matching: find.byKey(const Key('streak-flames-2'))), findsOneWidget);
      expect(find.byKey(const Key('night-streak')), findsNothing);
      // 不連到好友頁
      expect(find.byKey(const Key('night-open-friend')), findsNothing);
      expect(find.text('Friend settings'), findsNothing);
      // 一開始資訊卡停在寵物腳下：場景（寵物）沒被蓋住
      final sheetTop0 = tester.getTopLeft(find.byKey(const Key('night-detail'))).dy;
      final pet = tester.getRect(find.descendant(of: page, matching: find.byKey(const Key('streak-flames-2'))));
      expect(pet.bottom, lessThanOrEqualTo(sheetTop0 + 1));
      // 往上拉到底：卡最多拉到返回鍵下面（名字不被蓋住），最後一格不被系統按鍵列蓋住
      for (var k = 0; k < 3; k++) {
        await tester.drag(find.byKey(const Key('night-detail')), const Offset(0, -3000));
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      final back = tester.getRect(find.byKey(const Key('night-back')));
      // 拉到最上面時，資訊卡上緣仍在返回鍵下面（名字不會被它蓋住、不頂到狀態列）
      final sheetTop = tester.getTopLeft(find.byKey(const Key('night-detail'))).dy;
      expect(sheetTop, greaterThanOrEqualTo(back.bottom));
      final screenH = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final navBar = tester.view.padding.bottom / tester.view.devicePixelRatio;
      // 最底下那一格（照順序最後一個是 outfit）
      final last = tester.getRect(find.byKey(const Key('card-tile-outfit')));
      expect(last.bottom, lessThanOrEqualTo(screenH - navBar));
    });

    testWidgets('自己的卡也在動態牆上：寫 You、用自己的連續天數，點開最下面是分享設定；睡眠圖有標題與圖例', (tester) async {
      final json = stateJson(friends: [friendJson('BOB234', 'Bob', streak: 4)]);
      json['me'] = friendJson('K7QM2P', 'Nathan', streak: 5,
          week: ['on_time', 'on_time', 'on_time', 'on_time', 'on_time', 'future', 'future']);
      final stub = _StubFriends(result: FriendsResult(FriendsStatus.ok, value: FriendsState.fromJson(json)));
      stub.feed = const [
        FriendNightCard(handle: 'K7QM2P', displayName: 'Nathan', date: '2026-09-03', mine: true,
            items: {
              'on_time': true,
              'stages': {
                'rem_measured': false,
                'segments': [
                  {'stage': 'light', 'from': 0, 'to': 40},
                  {'stage': 'deep', 'from': 40, 'to': 90},
                ],
              },
            }),
        FriendNightCard(handle: 'BOB234', displayName: 'Bob', date: '2026-09-03', items: {'on_time': true}),
      ];
      await pump(tester, stub, friendsTab: false);
      final mine = find.byKey(const Key('feed-card-K7QM2P-2026-09-03'));
      expect(mine, findsOneWidget);
      expect(find.descendant(of: mine, matching: find.text('You')), findsOneWidget);
      expect(find.descendant(of: mine, matching: find.text('Nathan')), findsNothing);
      // 自己的卡要一眼認得：紫框＋「What friends see」；朋友的卡沒有
      expect(find.byKey(const Key('card-mine-glow')), findsOneWidget);
      expect(find.descendant(of: mine, matching: find.text('What friends see')), findsOneWidget);
      expect(find.text('What friends see'), findsOneWidget);
      expect(find.text('You reached a 5-night streak'), findsOneWidget);
      expect(find.descendant(of: mine, matching: find.byKey(const Key('card-week'))), findsOneWidget);
      // 睡眠圖：標題＋圖例；沒量到 REM 照實寫
      expect(find.descendant(of: mine, matching: find.text('Sleep stages')), findsOneWidget);
      expect(find.descendant(of: mine, matching: find.text('Deep')), findsOneWidget);
      expect(find.descendant(of: mine, matching: find.text('REM not measured')), findsOneWidget);

      await tester.tap(mine);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.drag(find.byKey(const Key('night-detail')), const Offset(0, -3000));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // 完整頁一樣寫 You＋What friends see；不放任何設定按鈕（使用者定：不連到別處）
      expect(find.descendant(of: find.byKey(const Key('night-detail')), matching: find.text('You')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('night-detail')), matching: find.text('What friends see')),
          findsOneWidget);
      expect(find.text('Sharing settings'), findsNothing);
      expect(find.text('Friend settings'), findsNothing);
    });

    testWidgets('還沒有朋友 → 講清楚怎麼加', (tester) async {
      await pump(tester, _StubFriends(result: FriendsResult(FriendsStatus.ok,
          value: FriendsState.fromJson(stateJson(friends: const [], board: const [])))));
      expect(find.byKey(const Key('friends-empty')), findsOneWidget);
    });
  });
}
