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
      if (request.method == 'GET') {
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

Future<void> pump(WidgetTester tester, FriendsService? service) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: FriendsScreen(service: service))));
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
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('remove-friend')));
      await tester.pumpAndSettle();
      expect(stub.removeCalls, ['BOB234']);
    });

    testWidgets('還沒有朋友 → 講清楚怎麼加', (tester) async {
      await pump(tester, _StubFriends(result: FriendsResult(FriendsStatus.ok,
          value: FriendsState.fromJson(stateJson(friends: const [], board: const [])))));
      expect(find.byKey(const Key('friends-empty')), findsOneWidget);
    });
  });
}
