// 好友頁的即時狀態（2026-11-19 使用者 grill 後定 Q1–Q11）。
//
// 【1】卡片的字：睡著寫睡了多久、其他寫昨晚放下手機；沒資料寫「—」不寫 0；時刻是牆鐘
// 【2】小長條：越晚越高、沒資料是 null（淡點）不是 0
// 【3】問一次：開 App 不問（好友頁在 IndexedStack 裡）、進 Friends 分頁才問；
//      連不到後端不記成問過；按 Share 才送 PATCH；問過不再問
// 【4】送出：Cancel 送 cancel；送不出去（丟例外）不擋睡覺畫面
import 'package:app/screens/friends_screen.dart';
import 'package:app/screens/sleep_mode_screen.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/friends_service.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/live_sleep_status.dart';
import 'package:app/widgets/friend_live_card.dart';
import 'package:app/widgets/friend_live_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FriendSummary friend({
  String? live,
  String? since,
  int? past,
  String? lightsOut = '2026-11-19T01:23:00+08:00',
}) =>
    FriendSummary.fromJson({
      'handle': 'BOB234',
      'display_name': 'Bob',
      'pet_mood': 'happy',
      'last_lights_out_at': lightsOut,
      'recorded_nights': 3,
      'live_state': live,
      'live_since': since,
      'minutes_past_bedtime': past,
    });

final now = DateTime(2026, 11, 20, 1, 12);

class LiveStub implements FriendsService {
  FriendsResult<SharingSettings> sharing;
  final List<Map<String, bool>?> patches = [];
  int sharingCalls = 0;
  bool noFriends = false;
  LiveStub(this.sharing);

  @override
  Future<FriendsResult<FriendsState>> fetch() async => FriendsResult(
        FriendsStatus.ok,
        value: FriendsState.fromJson({
          'my_invite_code': 'K7QM2P',
          'me': {
            'handle': 'ME0001',
            'display_name': 'Nathan',
            'recorded_nights': 1,
            'live_state': 'awake',
          },
          'friends': [
            if (!noFriends) {'handle': 'BOB234', 'display_name': 'Bob', 'recorded_nights': 1},
          ],
          'leaderboard': const [],
          'notes': const {},
        }),
      );

  @override
  Future<FriendsResult<SharingSettings>> fetchSharing() async {
    sharingCalls++;
    return sharing;
  }

  @override
  Future<FriendsResult<SharingSettings>> patchSharing({
    Map<String, bool>? items,
    String? timePrecision,
    String? petSpecies,
    String? scene,
  }) async {
    patches.add(items);
    return sharing;
  }

  @override
  Future<FriendsResult<TownState>> fetchTown() async => const FriendsResult(FriendsStatus.failed);

  @override
  Future<FriendsResult<List<FriendNightCard>>> fetchFeed() async =>
      const FriendsResult(FriendsStatus.failed);

  @override
  Future<FriendsResult<LeaderboardBoard>> fetchLeaderboard(String metric, {String? period}) async =>
      const FriendsResult(FriendsStatus.failed);

  @override
  Future<void> sendSleepStatus(String event, DateTime? at) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

FriendsResult<SharingSettings> sharingWith(bool liveOn) => FriendsResult(
      FriendsStatus.ok,
      value: SharingSettings.fromJson({
        'groups': [
          {
            'id': 'sleep',
            'label': 'Sleep',
            'items': [
              {'key': 'live_status', 'label': 'Live status', 'enabled': liveOn},
            ],
          },
        ],
        'time_precision': 'exact',
        'pet_species': 'dog',
        'never_shared': const [],
      }),
    );

Future<void> pumpFriends(WidgetTester tester, LiveStub stub, KeyValueStore store) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: FriendsScreen(service: stub, store: store, clock: () => now)),
  ));
  await tester.pump();
  await tester.pump();
}

Future<void> openFriendsTab(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('tab-friends')));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('【1】卡片的字', () {
    test('睡著：大字是從按 Start Sleep 到現在', () {
      final f = friend(live: 'asleep', since: '2026-11-19T23:40:00');
      expect(liveBigValue(f, now), ('1h 32m', 'asleep'));
      expect(liveStatusLine(f), 'Asleep since 23:40');
      expect(agoLabel(f, now), '1h 32m ago');
    });

    test('其他人：大字是昨晚放下手機（牆鐘，不是 UTC 的 17:23）', () {
      final f = friend(live: 'awake');
      expect(liveBigValue(f, now), ('01:23', 'phone down, latest night'));
      expect(liveStatusLine(f), 'Awake');
      expect(agoLabel(f, now), isNull);
    });

    test('過了就寢：照抄後端的分鐘數，不寫熬夜', () {
      final f = friend(live: 'past_bedtime', since: '2026-11-19T23:30:00', past: 40);
      expect(liveStatusLine(f), 'No Start Sleep yet · 40m past bedtime');
      expect(agoLabel(f, now), isNull, reason: '時間已經寫在狀態那行');
    });

    test('沒放下手機的資料 → 「—」不是 0', () {
      final f = friend(live: 'awake', lightsOut: null);
      expect(liveBigValue(f, now).$1, '—');
    });

    test('沒分享即時狀態 → 照實說，不猜', () {
      expect(liveStatusLine(friend()), 'Live status not shared');
      expect(liveFilterOf(friend()), isNull);
    });

    test('子分頁：up 不算 still up', () {
      expect(liveFilterOf(friend(live: 'asleep')), 'asleep');
      expect(liveFilterOf(friend(live: 'past_bedtime')), 'still_up');
      expect(liveFilterOf(friend(live: 'awake')), 'still_up');
      expect(liveFilterOf(friend(live: 'up')), isNull);
    });

    test('送給後端的時刻是牆鐘、不帶時區', () {
      expect(wallClockIso(DateTime(2026, 11, 19, 23, 40, 5)), '2026-11-19T23:40:05');
    });
  });

  group('【2】小長條', () {
    test('越晚越高、沒資料是 null', () {
      final hs = lightsOutBarHeights(const [
        LightsOutDay('a', '23:00'),
        LightsOutDay('b', '02:00'),
        LightsOutDay('c', null),
      ]);
      expect(hs[1]!, greaterThan(hs[0]!), reason: '02:00 比 23:00 晚 → 比較高');
      expect(hs[2], isNull);
    });
  });

  group('【3】只問一次', () {
    testWidgets('開好友頁（停在 Town）不問；進 Friends 分頁才問', (tester) async {
      final stub = LiveStub(sharingWith(false));
      await pumpFriends(tester, stub, InMemoryKeyValueStore());
      expect(stub.sharingCalls, 0, reason: '好友頁在 IndexedStack 裡，App 一打開就建好了');
      expect(find.byKey(const Key('live-ask')), findsNothing);
      await openFriendsTab(tester);
      expect(find.byKey(const Key('live-ask')), findsOneWidget);
    });

    testWidgets('按 Share → 送 PATCH、記下來、下次不再問', (tester) async {
      final stub = LiveStub(sharingWith(false));
      final store = InMemoryKeyValueStore();
      await pumpFriends(tester, stub, store);
      await openFriendsTab(tester);
      await tester.tap(find.byKey(const Key('live-ask-yes')));
      await tester.pump();
      await tester.pump();
      expect(stub.patches, [
        {'live_status': true},
      ]);
      expect(await store.getString(FriendsScreenKeys.liveAsked), 'on');
    });

    testWidgets('按 Not now → 不送、記成 off、不再問', (tester) async {
      final stub = LiveStub(sharingWith(false));
      final store = InMemoryKeyValueStore();
      await pumpFriends(tester, stub, store);
      await openFriendsTab(tester);
      await tester.tap(find.byKey(const Key('live-ask-no')));
      await tester.pump();
      await tester.pump();
      expect(stub.patches, isEmpty);
      expect(await store.getString(FriendsScreenKeys.liveAsked), 'off');
    });

    testWidgets('問過了就不再問；You 卡照實說好友看不到、給一顆 Share', (tester) async {
      final stub = LiveStub(sharingWith(false));
      await pumpFriends(tester, stub, InMemoryKeyValueStore({FriendsScreenKeys.liveAsked: 'off'}));
      await openFriendsTab(tester);
      expect(find.byKey(const Key('live-ask')), findsNothing);
      expect(tester.widget<Text>(find.byKey(const Key('you-status'))).data,
          "Friends can't see your live status");
      expect(find.byKey(const Key('you-share')), findsOneWidget);
    });

    testWidgets('打開了：You 卡寫好友看到的狀態，沒有 Share 鈕', (tester) async {
      final stub = LiveStub(sharingWith(true));
      await pumpFriends(tester, stub, InMemoryKeyValueStore());
      await openFriendsTab(tester);
      expect(find.byKey(const Key('you-card')), findsOneWidget);
      expect(find.byKey(const Key('you-share')), findsNothing);
    });

    testWidgets('連不到後端：不問、也不記成問過（下次再問）', (tester) async {
      final stub = LiveStub(const FriendsResult(FriendsStatus.failed));
      final store = InMemoryKeyValueStore();
      await pumpFriends(tester, stub, store);
      await openFriendsTab(tester);
      expect(find.byKey(const Key('live-ask')), findsNothing);
      expect(await store.getString(FriendsScreenKeys.liveAsked), isNull);
    });

    testWidgets('已經打開了：不問，直接記成 on', (tester) async {
      final stub = LiveStub(sharingWith(true));
      final store = InMemoryKeyValueStore();
      await pumpFriends(tester, stub, store);
      await openFriendsTab(tester);
      expect(find.byKey(const Key('live-ask')), findsNothing);
      expect(await store.getString(FriendsScreenKeys.liveAsked), 'on');
    });
  });

  group('【5】點朋友的那一頁（2026-11-19 第二輪 Q6）', () {
    testWidgets('現在的狀態 → 7 晚放下手機（星期＋時刻，沒資料寫「—」）', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final f = FriendSummary.fromJson({
        'handle': 'BOB234',
        'display_name': 'Bob',
        'recorded_nights': 2,
        'live_state': 'asleep',
        'live_since': '2026-11-19T23:40:00',
        'recent_lights_out': [
          {'date': '2026-11-18', 'time': '01:23'},
          {'date': '2026-11-19', 'time': null},
        ],
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: FriendLiveSheet(friend: f, now: now, onRemove: () {})),
      ));
      expect(tester.widget<Text>(find.byKey(const Key('sheet-big'))).data, '1h 32m');
      expect(tester.widget<Text>(find.byKey(const Key('sheet-status'))).data, 'Asleep since 23:40');
      expect(find.byKey(const Key('week-lights-out')), findsOneWidget);
      expect(find.text('Wed'), findsOneWidget, reason: '2026-11-18 是星期三');
      expect(find.text('01:23'), findsOneWidget);
      expect(find.text('—'), findsOneWidget, reason: '沒資料寫「—」不畫成 0');
      expect(find.byKey(const Key('remove-friend')), findsOneWidget);
    });
  });

  group('【6】沒有朋友（Q7）', () {
    testWidgets('大的 Add friend 打開加好友面板（我的邀請碼在裡面）', (tester) async {
      final stub = LiveStub(sharingWith(true))..noFriends = true;
      await pumpFriends(tester, stub, InMemoryKeyValueStore());
      await openFriendsTab(tester);
      expect(find.byKey(const Key('friends-empty')), findsOneWidget);
      await tester.tap(find.byKey(const Key('empty-add-friend')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('add-friend-sheet')), findsOneWidget);
      expect(find.text('K7QM2P'), findsOneWidget);
    });
  });

  group('【4】送出', () {
    Future<void> pumpSleep(WidgetTester tester, SleepStatusSink sink, BedMarkStore store) async {
      tester.view.physicalSize = const Size(1200, 4200);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await store.markStart(DateTime(2026, 11, 19, 23, 40));
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('open'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SleepModeScreen(
                    store: store,
                    startAt: DateTime(2026, 11, 19, 23, 40),
                    clock: () => now,
                    sleepStatus: sink,
                  ),
                )),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('open')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> cancelSleep(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('sleep-cancel')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('sleep-cancel-confirm')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('Cancel 送 cancel', (tester) async {
      final sent = <String>[];
      await pumpSleep(tester, (e, at) async => sent.add(e), BedMarkStore(InMemoryKeyValueStore()));
      await cancelSleep(tester);
      expect(sent, ['cancel']);
      expect(find.byType(SleepModeScreen), findsNothing);
    });

    testWidgets('送不出去（丟例外）照樣關掉睡覺畫面', (tester) async {
      await pumpSleep(
        tester,
        (e, at) async => throw Exception('offline'),
        BedMarkStore(InMemoryKeyValueStore()),
      );
      await cancelSleep(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(SleepModeScreen), findsNothing);
    });
  });
}
