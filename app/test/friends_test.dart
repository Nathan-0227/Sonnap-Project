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
  String? live,
  String? liveSince,
  int? pastBedtime,
  List<String?>? recent,
}) => {
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
  'live_state': ?live,
  'live_since': ?liveSince,
  'minutes_past_bedtime': ?pastBedtime,
  if (recent != null)
    'recent_lights_out': [
      for (final (i, t) in recent.indexed)
        {'date': '2026-09-${(i + 1).toString().padLeft(2, '0')}', 'time': t},
    ],
  if (week != null)
    'streak_week': [
      for (final (i, st) in week.indexed)
        {'date': '2026-09-${(i + 1).toString().padLeft(2, '0')}', 'status': st},
    ],
};

Map<String, dynamic> stateJson({
  List<Map<String, dynamic>>? friends,
  List<Map<String, dynamic>>? board,
}) => {
  'my_invite_code': 'K7QM2P',
  'friends':
      friends ??
      [
        friendJson('BOB234', 'Bob'),
        friendJson(
          'CAR567',
          'Carol',
          mood: 'tired',
          lightsOut: '2026-09-03T02:30:00+08:00',
          late: true,
          streak: 0,
          best: 1,
        ),
      ],
  'leaderboard':
      board ??
      const [
        {
          'rank': 1,
          'handle': 'BOB234',
          'display_name': 'Bob',
          'current_streak': 2,
          'best_streak': 3,
        },
        {
          'rank': 2,
          'handle': 'CAR567',
          'display_name': 'Carol',
          'current_streak': 0,
          'best_streak': 1,
        },
      ],
  'notes': const {'what_is_shared': 'Friends only see behaviour.'},
};

class _StubFriends implements FriendsService {
  @override
  Future<void> sendSleepStatus(String event, DateTime? at) async {}

  LeaderboardBoard? board;
  final List<(String, String?)> boardCalls = [];
  @override
  Future<FriendsResult<LeaderboardBoard>> fetchLeaderboard(
    String metric, {
    String? period,
  }) async {
    boardCalls.add((metric, period));
    return board == null
        ? const FriendsResult(FriendsStatus.failed)
        : FriendsResult(FriendsStatus.ok, value: board);
  }

  FriendsResult<FriendsState> result;
  FriendsResult<FriendSummary> addResult;
  final List<String> addCalls = [];
  final List<String> removeCalls = [];
  List<FriendNightCard> feed = const [];
  FriendsResult<TownState> town = const FriendsResult(FriendsStatus.failed);
  final List<(String, String)> visitCalls = [];
  FriendsResult<String> visitResult = const FriendsResult(
    FriendsStatus.ok,
    value: 'pet',
  );

  @override
  Future<FriendsResult<TownState>> fetchTown() async => town;

  @override
  Future<FriendsResult<String>> visit(String handle, String kind) async {
    visitCalls.add((handle, kind));
    return visitResult;
  }

  _StubFriends({
    FriendsResult<FriendsState>? result,
    FriendsResult<FriendSummary>? addResult,
  }) : result =
           result ??
           FriendsResult(
             FriendsStatus.ok,
             value: FriendsState.fromJson(stateJson()),
           ),
       addResult =
           addResult ??
           FriendsResult(
             FriendsStatus.ok,
             value: FriendSummary.fromJson(friendJson('DAV890', 'Dave')),
           );

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
  Future<FriendsResult<(FriendSummary, FriendNightCard?)>> fetchFriend(
    String handle,
  ) async => const FriendsResult(FriendsStatus.failed);

  @override
  Future<FriendsResult<SharingSettings>> fetchSharing() async =>
      const FriendsResult(FriendsStatus.failed);

  @override
  Future<FriendsResult<SharingSettings>> patchSharing({
    Map<String, bool>? items,
    String? timePrecision,
    String? petSpecies,
    String? scene,
  }) async => const FriendsResult(FriendsStatus.failed);

  @override
  Future<FriendsResult<(FriendSummary, FriendNightCard?)>>
  fetchPreview() async => const FriendsResult(FriendsStatus.failed);

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
        request.response.write(
          jsonEncode({
            'cards': [
              {
                'handle': 'BOB234',
                'display_name': 'Bob',
                'date': '2026-09-03',
                'scene': 'lake',
                'items': {'on_time': true},
              },
            ],
          }),
        );
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

/// 打開好友頁。2026-11-17 起預設在 Town 分頁；名單、邀請碼、排行在 Friends 分頁，
/// 所以預設切過去（要看 Feed 的傳 tab: 'feed'，要看小鎮的傳 tab: 'town'）。
Future<void> pump(
  WidgetTester tester,
  FriendsService? service, {
  String tab = 'friends',
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: FriendsScreen(service: service)),
    ),
  );
  await tester.pump();
  await tester.pump();
  final button = find.byKey(Key('tab-$tab'));
  if (tab != 'town' && button.evaluate().isNotEmpty) {
    await tester.tap(button);
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
      expect(
        FriendsService.feedTimeout,
        greaterThanOrEqualTo(const Duration(seconds: 10)),
      );
    });

    test('加好友：body 帶 user_id 與去掉空白的邀請碼', () async {
      await service().add('  bob234  ');
      expect(backend.received.single['body'], {
        'user_id': testUserId,
        'invite_code': 'bob234',
      });
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
      for (final fake in [
        'Katy',
        'Andrew',
        'Emil',
        'Heidi',
        'Jamie',
        'Mochi',
        'Coco',
        'Nala',
        'Dango',
      ]) {
        expect(
          find.textContaining(fake),
          findsNothing,
          reason: '不要拿任何人的名字當佔位符',
        );
      }
    });

    testWidgets('有後端 → 邀請碼、朋友名字都是後端給的', (tester) async {
      await pump(tester, _StubFriends());
      // 2026-11-19 起邀請碼在標題右邊的「人＋」面板裡
      expect(find.text('K7QM2P'), findsNothing);
      await tester.tap(find.byKey(const Key('add-friend')));
      await tester.pumpAndSettle();
      expect(find.text('K7QM2P'), findsOneWidget);
      Navigator.of(tester.element(find.byKey(const Key('add-friend-sheet')))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Bob'), findsWidgets);
      expect(find.text('Carol'), findsWidgets);
    });

    testWidgets('放下手機的時刻是牆鐘時間，不是 UTC', (tester) async {
      await pump(tester, _StubFriends());
      // 2026-11-19 起卡片上的大字就是放下手機的時刻
      expect(find.text('23:05'), findsOneWidget);
      expect(
        find.textContaining('15:05'),
        findsNothing,
        reason: 'DateTime.tryParse("...+08:00") 回 UTC，.hour 會早 8 小時',
      );
    });

    testWidgets('子分頁上的人數照後端的狀態算（Sleep Circle 2026-11-19 拿掉）', (tester) async {
      final stub = _StubFriends(
        result: FriendsResult(
          FriendsStatus.ok,
          value: FriendsState.fromJson(stateJson(friends: [
            friendJson('BOB234', 'Bob', live: 'asleep', liveSince: '2026-09-03T23:40:00'),
            friendJson('CAR567', 'Carol', live: 'past_bedtime', pastBedtime: 40),
            friendJson('DAV890', 'Dave', live: 'up'),
          ])),
        ),
      );
      await pump(tester, stub);
      String count(String tab) =>
          tester.widget<Text>(find.byKey(Key('live-count-$tab'))).textSpan!.toPlainText();
      expect(count('all'), 'All  3');
      expect(count('asleep'), 'Asleep  1');
      expect(count('stillUp'), 'Still up  1', reason: '起床了不算 still up');
      expect(find.byKey(const Key('circle-on-time')), findsNothing);
    });

    testWidgets('排序：睡著的在最上面（睡最久的先）→ 過了就寢 → 起床了 → 沒分享', (tester) async {
      final stub = _StubFriends(
        result: FriendsResult(
          FriendsStatus.ok,
          value: FriendsState.fromJson(stateJson(friends: [
            friendJson('EVE111', 'Eve'),
            friendJson('DAV890', 'Dave', live: 'up'),
            friendJson('CAR567', 'Carol', live: 'past_bedtime', pastBedtime: 40),
            friendJson('BOB234', 'Bob', live: 'asleep', liveSince: '2026-09-03T23:40:00'),
            friendJson('ANN000', 'Ann', live: 'asleep', liveSince: '2026-09-03T22:10:00'),
          ])),
        ),
      );
      await pump(tester, stub);
      double y(String h) => tester.getTopLeft(find.byKey(Key('friend-$h'))).dy;
      final order = ['ANN000', 'BOB234', 'CAR567', 'DAV890', 'EVE111'];
      for (var i = 1; i < order.length; i++) {
        expect(y(order[i]), greaterThan(y(order[i - 1])), reason: '${order[i - 1]} 要在 ${order[i]} 上面');
      }
    });

    testWidgets('Friends 分頁有七個排行榜那一塊（舊的只有連續天數），照後端的順序', (tester) async {
      final stub = _StubFriends();
      stub.board = LeaderboardBoard.fromJson({
        'metric': 'on_time',
        'period': 'week',
        'label': 'On time',
        'title': 'Phone-down champ',
        'need': 3,
        'metrics': [
          {'key': 'on_time', 'label': 'On time'},
        ],
        'periods': [
          {'key': 'week', 'label': 'Week'},
        ],
        // 後端把 0/3 的 Carol 排第一——看起來不合理也照抄
        'entries': [
          {
            'handle': 'CAR567',
            'display_name': 'Carol',
            'rank': 1,
            'display': '0 / 3 nights',
          },
          {
            'handle': 'BOB234',
            'display_name': 'Bob',
            'rank': 2,
            'display': '3 / 3 nights',
          },
        ],
        'below': [],
        'me': {'status': 'not_sharing', 'share_label': 'On time or late'},
      });
      await pump(tester, stub);
      // 2026-11-19 起排行榜是最上面的 Ranks 分頁
      await tester.tap(find.byKey(const Key('tab-ranks')));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(stub.boardCalls.first, ('on_time', null));
      expect(find.byKey(const Key('leaderboard')), findsOneWidget);
      final carol = tester
          .getCenter(find.byKey(const Key('lb-podium-CAR567')))
          .dx;
      final bob = tester
          .getCenter(find.byKey(const Key('lb-podium-BOB234')))
          .dx;
      expect(carol, greaterThan(bob)); // 後端的第一名站中間
    });

    testWidgets('四個子分頁：Asleep 只剩按了 Start Sleep 的、Still up 是過了就寢與醒著的', (tester) async {
      final stub = _StubFriends(
        result: FriendsResult(
          FriendsStatus.ok,
          value: FriendsState.fromJson(stateJson(friends: [
            friendJson('BOB234', 'Bob', live: 'asleep', liveSince: '2026-09-03T23:40:00'),
            friendJson('CAR567', 'Carol', live: 'past_bedtime',
                liveSince: '2026-09-03T23:30:00', pastBedtime: 40),
            friendJson('DAV890', 'Dave', live: 'up', liveSince: '2026-09-04T07:30:00'),
            friendJson('EVE111', 'Eve'), // 沒分享即時狀態
          ])),
        ),
      );
      await pump(tester, stub);
      expect(find.byKey(const Key('live-tab-all')), findsOneWidget);
      expect(find.byKey(const Key('live-tab-stillUp')), findsOneWidget);
      for (final h in ['BOB234', 'CAR567', 'DAV890', 'EVE111']) {
        expect(find.byKey(Key('friend-$h')), findsOneWidget, reason: 'All 有每一個人');
      }
      await tester.tap(find.byKey(const Key('live-tab-asleep')));
      await tester.pump();
      expect(find.byKey(const Key('friend-BOB234')), findsOneWidget);
      expect(find.byKey(const Key('friend-CAR567')), findsNothing);
      await tester.tap(find.byKey(const Key('live-tab-stillUp')));
      await tester.pump();
      expect(find.byKey(const Key('friend-CAR567')), findsOneWidget);
      expect(find.byKey(const Key('friend-BOB234')), findsNothing);
      expect(find.byKey(const Key('friend-DAV890')), findsNothing, reason: '起床了不是 still up');
      expect(find.byKey(const Key('friend-EVE111')), findsNothing, reason: '沒分享的不猜');
    });

    testWidgets('過了就寢沒按：寫事實不寫熬夜；狀態照抄後端的分鐘數', (tester) async {
      final stub = _StubFriends(
        result: FriendsResult(
          FriendsStatus.ok,
          value: FriendsState.fromJson(stateJson(friends: [
            friendJson('CAR567', 'Carol', live: 'past_bedtime',
                liveSince: '2026-09-03T23:30:00', pastBedtime: 95),
          ])),
        ),
      );
      await pump(tester, stub);
      final line = tester.widget<Text>(find.byKey(const Key('friend-status-CAR567'))).data!;
      expect(line, 'No Start Sleep yet · 1h 35m past bedtime');
      expect(find.textContaining(RegExp('staying up|up late', caseSensitive: false)), findsNothing);
    });

    testWidgets('沒有後端的即時欄位（舊版後端）：不出現狀態圖示的分鐘數、照常畫放下手機', (tester) async {
      await pump(tester, _StubFriends());
      expect(
        tester.widget<Text>(find.byKey(const Key('friend-status-BOB234'))).data,
        'Live status not shared',
      );
      expect(find.byKey(const Key('friend-ago-BOB234')), findsNothing);
      expect(find.byKey(const Key('friend-bars-BOB234')), findsNothing, reason: '沒給 7 晚就不畫');
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
        addResult: const FriendsResult(
          FriendsStatus.failed,
          httpStatus: 422,
          message: 'That is your own invite code.',
        ),
      );
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

    testWidgets('Feed：沒有動態時講清楚，名單在另一個分頁', (tester) async {
      await pump(tester, _StubFriends(), tab: 'feed');
      expect(find.byKey(const Key('feed-empty')), findsOneWidget);
      expect(find.text('K7QM2P'), findsNothing);
      await tester.tap(find.byKey(const Key('tab-friends')));
      await tester.pump();
      expect(find.byKey(const Key('friend-BOB234')), findsOneWidget);
      expect(find.byKey(const Key('feed-empty')), findsNothing);
    });

    testWidgets('Feed：每張卡是他選的場景；連續天數的橫幅只在他最近那一晚、3 晚以上才出現', (tester) async {
      final stub = _StubFriends(
        result: FriendsResult(
          FriendsStatus.ok,
          value: FriendsState.fromJson(
            stateJson(
              friends: [
                friendJson(
                  'BOB234',
                  'Bob',
                  streak: 4,
                  week: [
                    'late',
                    'on_time',
                    'on_time',
                    'on_time',
                    'on_time',
                    'future',
                    'future',
                  ],
                ),
                friendJson('CAR567', 'Carol', streak: 2),
              ],
            ),
          ),
        ),
      );
      stub.feed = const [
        // 項目多到資訊卡要捲（才驗得到最底下那一排有沒有被系統按鍵列蓋住）
        FriendNightCard(
          handle: 'BOB234',
          displayName: 'Bob',
          date: '2026-09-03',
          scene: 'lake',
          items: {
            'sleep_duration': 412,
            'on_time': true,
            'awake': {'count': 2},
            'sleeping_hr': {'avg': 56},
            'stress': {'high': 1980},
            'steps': {'steps': 8000},
            'calories': {'active': 420},
            'level': {'level': 4},
            'outfit': {'badges': 3},
            'phone_down_time': '23:10',
            'time_in_bed': 440,
            'resting_hr': 55,
          },
        ),
        FriendNightCard(
          handle: 'CAR567',
          displayName: 'Carol',
          date: '2026-09-03',
          items: {'on_time': false},
        ),
        FriendNightCard(
          handle: 'BOB234',
          displayName: 'Bob',
          date: '2026-09-02',
          scene: 'lake',
          items: {'on_time': true},
        ),
      ];
      await pump(tester, stub, tab: 'feed');
      // 手機大小（內容要長到會捲）＋底部的系統按鍵列
      tester.view.physicalSize = const Size(400, 560);
      tester.view.padding = const FakeViewPadding(bottom: 48);
      await tester.pump();
      expect(
        find.byKey(const Key('feed-card-BOB234-2026-09-03')),
        findsOneWidget,
      );
      final scenes = tester
          .widgetList<Image>(find.byKey(const Key('card-scene')))
          .map((i) => (i.image as AssetImage).assetName)
          .toList();
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
      // 這週的軌道不在外面的卡上（11-19 Feed 精簡：火焰已經在講連續幾晚），點進去才有
      expect(find.byKey(const Key('card-week')), findsNothing);

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
      expect(
        find.descendant(
          of: page,
          matching: find.byKey(const Key('night-scene')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: page,
          matching: find.byKey(const Key('streak-flames-2')),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('night-streak')), findsNothing);
      // 不連到好友頁
      expect(find.byKey(const Key('night-open-friend')), findsNothing);
      expect(find.text('Friend settings'), findsNothing);
      // 一開始資訊卡停在寵物腳下：場景（寵物）沒被蓋住
      final sheetTop0 = tester
          .getTopLeft(find.byKey(const Key('night-detail')))
          .dy;
      final pet = tester.getRect(
        find.descendant(
          of: page,
          matching: find.byKey(const Key('streak-flames-2')),
        ),
      );
      expect(pet.bottom, lessThanOrEqualTo(sheetTop0 + 1));
      // 往上拉到底（同 Strava）：資訊卡佔滿整個畫面、上面不留場景，頂端換成深色列寫名字
      expect(
        tester
            .widget<Opacity>(
              find.descendant(
                of: find.byKey(const Key('night-topbar')),
                matching: find.byType(Opacity),
              ),
            )
            .opacity,
        0,
      );
      await tester.drag(
        find.byKey(const Key('night-detail')),
        const Offset(0, -560),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        tester.getTopLeft(find.byKey(const Key('night-detail'))).dy,
        lessThanOrEqualTo(0.5),
      );
      expect(
        tester
            .widget<Opacity>(
              find.descendant(
                of: find.byKey(const Key('night-topbar')),
                matching: find.byType(Opacity),
              ),
            )
            .opacity,
        1,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('night-topbar')),
          matching: find.text('Bob'),
        ),
        findsOneWidget,
      );
      // 名字在頂端列下面，沒被它蓋住
      final barBottom = tester
          .getBottomLeft(find.byKey(const Key('night-topbar')))
          .dy;
      final nameTop = tester
          .getTopLeft(
            find.descendant(
              of: find.byKey(const Key('night-detail')),
              matching: find.text('Bob'),
            ),
          )
          .dy;
      expect(nameTop, greaterThanOrEqualTo(barBottom));
      for (var k = 0; k < 3; k++) {
        await tester.drag(
          find.byKey(const Key('night-detail')),
          const Offset(0, -3000),
        );
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      final screenH =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final navBar = tester.view.padding.bottom / tester.view.devicePixelRatio;
      // 最底下那一段（Game）
      final last = tester.getRect(find.byKey(const Key('section-game')));
      expect(last.bottom, lessThanOrEqualTo(screenH - navBar));
    });

    testWidgets('🐾（2026-11-19）：數字照抄後端；只有能按的那張有按鈕；按了＝拜訪（摸摸），重拿一次變 Sent', (
      tester,
    ) async {
      FriendNightCard bob({
        required String date,
        int paws = 0,
        bool canPaw = false,
        bool sent = false,
      }) => FriendNightCard(
        handle: 'BOB234',
        displayName: 'Bob',
        date: date,
        items: const {'on_time': true},
        paws: paws,
        canPaw: canPaw,
        pawSent: sent,
      );
      final stub = _StubFriends()
        ..feed = [
          bob(date: '2026-09-03', paws: 3, canPaw: true),
          bob(date: '2026-09-02', paws: 0),
          bob(date: '2026-09-01', paws: 1),
        ];
      await pump(tester, stub, tab: 'feed');
      final today = find.byKey(const Key('feed-card-BOB234-2026-09-03'));
      expect(
        find.descendant(of: today, matching: find.text('3 paws')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('card-paw-button')),
        findsOneWidget,
        reason: '舊的卡不能按',
      );
      expect(
        find.descendant(
          of: today,
          matching: find.byKey(const Key('card-paw-button')),
        ),
        findsOneWidget,
      );
      expect(find.text('1 paw'), findsOneWidget, reason: '舊的卡照樣寫數字（單數）');
      expect(
        find.descendant(
          of: find.byKey(const Key('feed-card-BOB234-2026-09-02')),
          matching: find.textContaining('paw'),
        ),
        findsNothing,
        reason: '0 個不寫',
      );
      // 朋友的卡看不到是誰
      expect(find.byKey(const Key('card-paws-who')), findsNothing);

      stub.feed = [
        bob(date: '2026-09-03', paws: 4, canPaw: true, sent: true),
        bob(date: '2026-09-02'),
        bob(date: '2026-09-01', paws: 1),
      ];
      await tester.tap(find.byKey(const Key('card-paw-button')));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(stub.visitCalls, [('BOB234', 'pet')]);
      expect(find.text('4 paws'), findsOneWidget);
      expect(find.text('Sent'), findsOneWidget);
      // Sent 之後再按不會再送
      await tester.tap(find.byKey(const Key('card-paw-button')));
      await tester.pump();
      expect(stub.visitCalls, hasLength(1));
    });

    testWidgets('🐾 連按：只送一次，按下當下就是 Sent（11-19 實機：一次 201 後面跟三次 409）；送失敗才變回 Paw', (tester) async {
      FriendNightCard bob() => const FriendNightCard(
        handle: 'BOB234',
        displayName: 'Bob',
        date: '2026-09-03',
        items: {'on_time': true},
        paws: 1,
        canPaw: true,
      );
      // 後端重拿還是舊的（還沒 Sent）也一樣：只靠 App 自己記得按過
      final stub = _StubFriends()..feed = [bob()];
      await pump(tester, stub, tab: 'feed');
      final button = find.byKey(const Key('card-paw-button'));
      await tester.tap(button);
      await tester.tap(button);
      await tester.tap(button);
      await tester.pump();
      expect(stub.visitCalls, hasLength(1));
      expect(find.text('Sent'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Sent'), findsOneWidget);
    });

    testWidgets('🐾 送失敗（連不上）：變回 Paw、照實說', (tester) async {
      FriendNightCard bob() => const FriendNightCard(
        handle: 'BOB234',
        displayName: 'Bob',
        date: '2026-09-03',
        items: {'on_time': true},
        paws: 1,
        canPaw: true,
      );
      final failing = _StubFriends()
        ..feed = [bob()]
        ..visitResult = const FriendsResult(FriendsStatus.failed, message: 'Could not reach the backend.');
      await pump(tester, failing, tab: 'feed');
      await tester.tap(find.byKey(const Key('card-paw-button')));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Paw'), findsOneWidget);
      expect(find.text('Could not reach the backend.'), findsOneWidget);
    });

    testWidgets('🐾：自己的卡沒有按鈕，點數字看是誰（名單只有自己的卡有）', (tester) async {
      final stub = _StubFriends()
        ..feed = const [
          FriendNightCard(
            handle: 'K7QM2P',
            displayName: 'Nathan',
            date: '2026-09-03',
            mine: true,
            items: {'on_time': true},
            paws: 2,
            pawFrom: ['Bob', 'Carol'],
          ),
        ];
      await pump(tester, stub, tab: 'feed');
      expect(find.byKey(const Key('card-paw-button')), findsNothing);
      expect(find.text('2 paws'), findsOneWidget);
      await tester.tap(find.byKey(const Key('card-paws-who')));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final sheet = find.byKey(const Key('paw-from-sheet'));
      expect(
        find.descendant(of: sheet, matching: find.text('Bob')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Carol')),
        findsOneWidget,
      );
    });

    test('🐾：卡片照抄後端的 paws／can_paw／paw_sent／paw_from，沒給就是 0／不能按', () {
      final c = FriendNightCard.fromJson({
        'handle': 'B',
        'display_name': 'Bob',
        'date': '2026-09-03',
        'items': <String, dynamic>{},
        'paws': 2,
        'can_paw': true,
        'paw_sent': true,
        'paw_from': ['Bob', 7],
      });
      expect((c.paws, c.canPaw, c.pawSent), (2, true, true));
      expect(c.pawFrom, ['Bob']);
      final old = FriendNightCard.fromJson({
        'handle': 'B',
        'date': '2026-09-03',
        'items': <String, dynamic>{},
      });
      expect((old.paws, old.canPaw, old.pawSent), (0, false, false));
      expect(old.pawFrom, isEmpty);
    });

    testWidgets('自己的卡也在動態牆上：寫 You、用自己的連續天數，點開最下面是分享設定；睡眠圖在卡上是細長條', (
      tester,
    ) async {
      final json = stateJson(friends: [friendJson('BOB234', 'Bob', streak: 4)]);
      json['me'] = friendJson(
        'K7QM2P',
        'Nathan',
        streak: 5,
        week: [
          'on_time',
          'on_time',
          'on_time',
          'on_time',
          'on_time',
          'future',
          'future',
        ],
      );
      final stub = _StubFriends(
        result: FriendsResult(
          FriendsStatus.ok,
          value: FriendsState.fromJson(json),
        ),
      );
      stub.feed = const [
        FriendNightCard(
          handle: 'K7QM2P',
          displayName: 'Nathan',
          date: '2026-09-03',
          mine: true,
          items: {
            'on_time': true,
            'stages': {
              'rem_measured': false,
              'segments': [
                {'stage': 'light', 'from': 0, 'to': 40},
                {'stage': 'deep', 'from': 40, 'to': 90},
              ],
            },
          },
        ),
        FriendNightCard(
          handle: 'BOB234',
          displayName: 'Bob',
          date: '2026-09-03',
          items: {'on_time': true},
        ),
      ];
      await pump(tester, stub, tab: 'feed');
      final mine = find.byKey(const Key('feed-card-K7QM2P-2026-09-03'));
      expect(mine, findsOneWidget);
      expect(
        find.descendant(of: mine, matching: find.text('You')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: mine, matching: find.text('Nathan')),
        findsNothing,
      );
      // 自己的卡要一眼認得：紫框＋「What friends see」；朋友的卡沒有
      expect(find.byKey(const Key('card-mine-glow')), findsOneWidget);
      expect(
        find.descendant(of: mine, matching: find.text('What friends see')),
        findsOneWidget,
      );
      expect(find.text('What friends see'), findsOneWidget);
      expect(find.text('You reached a 5-night streak'), findsOneWidget);
      // 11-19 Feed 精簡：卡上沒有這週的軌道、睡眠圖只剩一條細長條（標題、圖例在點進去的頁面）
      expect(
        find.descendant(of: mine, matching: find.byKey(const Key('card-week'))),
        findsNothing,
      );
      expect(
        find.descendant(
          of: mine,
          matching: find.byKey(const Key('card-stages-strip')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: mine, matching: find.text('Sleep stages')),
        findsNothing,
      );
      expect(
        find.descendant(of: mine, matching: find.text('REM not measured')),
        findsNothing,
      );

      await tester.tap(mine);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.drag(
        find.byKey(const Key('night-detail')),
        const Offset(0, -3000),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // 完整頁一樣寫 You＋What friends see；不放任何設定按鈕（使用者定：不連到別處）
      expect(
        find.descendant(
          of: find.byKey(const Key('night-detail')),
          matching: find.text('You'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('night-detail')),
          matching: find.text('What friends see'),
        ),
        findsOneWidget,
      );
      expect(find.text('Sharing settings'), findsNothing);
      expect(find.text('Friend settings'), findsNothing);
    });

    testWidgets('還沒有朋友 → 講清楚怎麼加', (tester) async {
      await pump(
        tester,
        _StubFriends(
          result: FriendsResult(
            FriendsStatus.ok,
            value: FriendsState.fromJson(
              stateJson(friends: const [], board: const []),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('friends-empty')), findsOneWidget);
    });
  });
}
