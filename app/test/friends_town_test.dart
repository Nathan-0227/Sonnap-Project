// 好友小鎮（2026-11-17）。守的事：
// 【1】打開好友頁預設在 Town；我在畫面正中間，朋友照後端順序一右一左往外排
// 【2】只有 glow: true 的人有星星與金光；沒發光的人（晚了、沒資料、沒分享）畫得一模一樣
// 【3】小鎮裡不畫心情：所有寵物都是同一個（中性的 bored），絕不畫 happy
// 【4】點朋友 → 小卡：按鈕的字照抄後端、送出呼叫後端、送過變 Sent ✓ 且不能再送；409 照抄後端的話
// 【5】小卡上：心情只有他分享才有（沒有就不畫 happy）、準時才有 ✨ 那行、有卡才有 See last night
// 【6】今天誰來看過你：訊息照抄後端；沒人來整張不出現
// 【7】沒有朋友 → Invite friends；連不到後端 → 照實說，不畫假朋友
// 【8】減少動態效果時星星不閃
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/screens/friends_screen.dart';
import 'package:app/services/friends_service.dart';
import 'package:app/services/user_identity.dart';
import 'package:app/widgets/friend_night_card.dart' show friendCheckIn;
import 'package:app/services/morning_rating.dart' show restedFaceAsset;
import 'package:app/widgets/friends_town.dart';
import 'package:app/widgets/home_pet.dart';
import 'package:app/widgets/last_night_art.dart';
import 'package:app/widgets/report_tiles.dart';

Map<String, dynamic> person(
  String handle,
  String name, {
  bool mine = false,
  bool glow = false,
  String? sent,
  String? mood,
  bool demo = false,
  Map<String, dynamic>? card,
}) => {
  'handle': handle,
  'display_name': name,
  'mine': mine,
  'demo': demo,
  'pet_species': 'dog',
  'pet_mood': mood,
  'glow': glow,
  'sent': sent,
  'card': card,
};

const kinds = [
  {'key': 'pet', 'label': 'Pet 🐾'},
  {'key': 'good_night', 'label': 'Good night 🌙'},
  {'key': 'sleep_well', 'label': 'Sleep well 💤'},
  {'key': 'proud', 'label': 'PROUD-FROM-BACKEND'},
];

TownState townOf(
  List<Map<String, dynamic>> people, {
  List<Map<String, dynamic>> visits = const [],
}) => TownState.fromJson({
  'night': '2026-09-03',
  'people': people,
  'visits': visits,
  'kinds': kinds,
});

final defaultTown = townOf([
  person('ME0001', 'Nathan', mine: true, glow: true, mood: 'happy'),
  person(
    'EAR111',
    'Early',
    glow: true,
    mood: 'happy',
    card: {
      'date': '2026-09-03',
      'items': {'on_time': true},
    },
  ),
  person('LAT222', 'Late', mood: 'tired'),
  person('BLA333', 'Blank'),
  person('SHY444', 'Shy'),
]);

Map<String, dynamic> stateJson({bool friends = true}) => {
  'my_invite_code': 'ME0001',
  'me': {
    'handle': 'ME0001',
    'display_name': 'Nathan',
    'current_streak': 3,
    'best_streak': 5,
    'recorded_nights': 3,
  },
  'friends': friends
      ? [
          {'handle': 'EAR111', 'display_name': 'Early', 'recorded_nights': 1},
        ]
      : [],
  'leaderboard': [],
  'notes': {},
};

class TownStub implements FriendsService {
  FriendsResult<TownState> town;
  FriendsResult<FriendsState> state;
  FriendsResult<String> visitResult = const FriendsResult(
    FriendsStatus.ok,
    value: 'pet',
  );
  final List<(String, String)> visitCalls = [];
  int townCalls = 0;

  TownStub({FriendsResult<TownState>? town, Map<String, dynamic>? state})
    : town = town ?? FriendsResult(FriendsStatus.ok, value: defaultTown),
      state = FriendsResult(
        FriendsStatus.ok,
        value: FriendsState.fromJson(state ?? stateJson()),
      );

  @override
  Future<FriendsResult<TownState>> fetchTown() async {
    townCalls++;
    return town;
  }

  @override
  Future<FriendsResult<String>> visit(String handle, String kind) async {
    visitCalls.add((handle, kind));
    return visitResult;
  }

  @override
  Future<FriendsResult<FriendsState>> fetch() async => state;

  @override
  Future<FriendsResult<List<FriendNightCard>>> fetchFeed() async =>
      const FriendsResult(FriendsStatus.ok, value: []);

  @override
  Future<FriendsResult<LeaderboardBoard>> fetchLeaderboard(
    String metric, {
    String? period,
  }) async => const FriendsResult(FriendsStatus.failed);

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
  Future<FriendsResult<FriendSummary>> add(String inviteCode) async =>
      const FriendsResult(FriendsStatus.failed);

  @override
  Future<FriendsResult<String>> remove(String handle) async =>
      const FriendsResult(FriendsStatus.failed);

  @override
  String get baseUrl => 'stub';

  @override
  UserIdentity get identity => const BuildTimeUserIdentity(overrideId: 'stub');

  @override
  Duration get timeout => const Duration(seconds: 1);
}

Future<void> pump(
  WidgetTester tester,
  TownStub stub, {
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = const Size(411, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(411, 900),
          disableAnimations: reduceMotion,
        ),
        child: Scaffold(
          body: FriendsScreen(key: UniqueKey(), service: stub),
        ),
      ),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder townie(String handle) => find.byKey(Key('town-$handle'));

/// 先把地圖滑到那個人（離你家遠的房子一打開時在畫面外），再點他。
Future<void> tapTownie(WidgetTester tester, String handle) async {
  final at = tester.getCenter(townie(handle));
  await tester.drag(
    find.byKey(const Key('town-map')),
    const Offset(411 / 2, 450) - at,
  );
  await settle(tester);
  await tester.tap(townie(handle));
  await settle(tester);
}

void main() {
  testWidgets('【1】預設在 Town、整個畫面是地圖；一打開你家在看得到的那塊正中間，朋友住離你家近的房子', (tester) async {
    await pump(tester, TownStub());
    expect(find.byKey(const Key('town-map')), findsOneWidget);
    final me = tester.getCenter(townie('ME0001'));
    expect((me.dx - 411 / 2).abs(), lessThan(2));
    // 第 1 個朋友住右上那間、第 2 個住右下那間（kTownLots 照離你家的距離排）
    final first = tester.getCenter(townie('EAR111'));
    final second = tester.getCenter(townie('LAT222'));
    expect(first.dx > me.dx && first.dy < me.dy, isTrue);
    expect(second.dx > me.dx && second.dy > me.dy, isTrue);
    // 上下左右都滑得動
    await tester.drag(
      find.byKey(const Key('town-map')),
      const Offset(120, 120),
    );
    await settle(tester);
    final moved = tester.getCenter(townie('ME0001'));
    expect(moved.dx, greaterThan(me.dx));
    expect(moved.dy, greaterThan(me.dy));
  });

  testWidgets('地圖住滿（9 個朋友）→ 第 10 個不畫、也沒有 Invite', (tester) async {
    final many = [for (var i = 0; i < 10; i++) person('F$i', 'Friend $i')];
    final stub = TownStub(
      town: FriendsResult(
        FriendsStatus.ok,
        value: townOf([person('ME0001', 'Nathan', mine: true), ...many]),
      ),
    );
    await pump(tester, stub);
    expect(kTownLots, hasLength(kTownMaxFriends + 1));
    expect(find.byKey(const Key('town-F8')), findsOneWidget);
    expect(find.byKey(const Key('town-F9')), findsNothing);
    expect(find.byKey(const Key('town-invite')), findsNothing);
  });

  testWidgets('【2】只有發光的人有星星與金光；沒發光的三個人畫得一模一樣', (tester) async {
    await pump(tester, TownStub());
    expect(find.byKey(const Key('town-glow-ME0001')), findsOneWidget);
    expect(find.byKey(const Key('town-glow-EAR111')), findsOneWidget);
    for (final h in ['LAT222', 'BLA333', 'SHY444']) {
      expect(
        find.descendant(of: townie(h), matching: find.byType(TownStar)),
        findsNothing,
      );
    }
    // 三個人底下的元件種類完全相同（名字不算）：Late 的心情是 tired，也不能讓它長得不一樣
    List<Type> shape(String h) => [
      for (final e
          in find
              .descendant(
                of: townie(h),
                matching: find.byWidgetPredicate((_) => true),
              )
              .evaluate())
        if (e.widget is! Text && e.widget is! RichText) e.widget.runtimeType,
    ];
    expect(shape('LAT222'), shape('BLA333'));
    expect(shape('BLA333'), shape('SHY444'));
    // ✨ 的說明收在左下的小圓鈕裡，點了才出現
    expect(find.byKey(const Key('town-legend')), findsNothing);
    await tester.tap(find.byKey(const Key('town-legend-button')));
    await settle(tester);
    expect(find.byKey(const Key('town-legend')), findsOneWidget);
  });

  testWidgets('【3】小鎮裡不畫心情：每一隻都是 bored，連 happy 的人也一樣', (tester) async {
    await pump(tester, TownStub());
    final moods = [
      for (final h in ['ME0001', 'EAR111', 'LAT222', 'BLA333'])
        for (final e
            in find
                .descendant(of: townie(h), matching: find.byType(HomePet))
                .evaluate())
          (e.widget as HomePet).mood,
    ];
    expect(moods, isNotEmpty);
    expect(moods.toSet(), {'bored'});
  });

  testWidgets('【4】點朋友 → 按鈕照抄後端；送出呼叫後端、變 Sent ✓、不能再送', (tester) async {
    final stub = TownStub();
    await pump(tester, stub);
    await tapTownie(tester, 'EAR111');
    expect(find.text('PROUD-FROM-BACKEND'), findsOneWidget);
    await tester.tap(find.byKey(const Key('town-visit-pet')));
    await settle(tester);
    expect(stub.visitCalls, [('EAR111', 'pet')]);
    // 11-19 起按鈕是一排圓圈：送過的那一顆變金色，下面一行照抄後端的字＋sent
    expect(find.text('Pet 🐾 sent · You can visit again tomorrow.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('town-visit-good_night')));
    await settle(tester);
    expect(stub.visitCalls, hasLength(1));
    expect(
      stub.townCalls,
      greaterThanOrEqualTo(2),
      reason: '送出後要重抓小鎮，Sent 才留得住',
    );
  });

  testWidgets('【4】今天已經送過（後端給 sent）→ 小卡一打開就是 Sent ✓', (tester) async {
    final stub = TownStub(
      town: FriendsResult(
        FriendsStatus.ok,
        value: townOf([
          person('ME0001', 'Nathan', mine: true),
          person('EAR111', 'Early', sent: 'sleep_well'),
        ]),
      ),
    );
    await pump(tester, stub);
    await tapTownie(tester, 'EAR111');
    expect(find.text('Sleep well 💤 sent · You can visit again tomorrow.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('town-visit-pet')));
    await settle(tester);
    expect(stub.visitCalls, isEmpty);
  });

  testWidgets('【4】409 → 照抄後端那句', (tester) async {
    final stub = TownStub()
      ..visitResult = const FriendsResult(
        FriendsStatus.failed,
        httpStatus: 409,
        message: 'ALREADY-FROM-BACKEND',
      );
    await pump(tester, stub);
    await tapTownie(tester, 'LAT222');
    await tester.tap(find.byKey(const Key('town-visit-proud')));
    await settle(tester);
    expect(find.text('ALREADY-FROM-BACKEND'), findsOneWidget);
    expect(find.byKey(const Key('town-sheet-sent')), findsNothing);
  });

  testWidgets('【5】小卡：心情只有分享才有；準時才有 ✨；有卡才有 See last night', (tester) async {
    await pump(tester, TownStub());
    await tapTownie(tester, 'EAR111');
    expect(find.byKey(const Key('town-sheet-glow')), findsOneWidget);
    expect(find.byKey(const Key('town-see-night')), findsOneWidget);
    HomePet sheetPet() => tester.widget<HomePet>(
      find.descendant(
        of: find.byKey(const Key('town-sheet')),
        matching: find.byType(HomePet),
      ),
    );
    expect(sheetPet().mood, 'happy');
    Navigator.of(tester.element(find.byKey(const Key('town-sheet')))).pop();
    await settle(tester);

    await tapTownie(tester, 'BLA333');
    expect(find.byKey(const Key('town-sheet-glow')), findsNothing);
    expect(find.byKey(const Key('town-see-night')), findsNothing);
    expect(
      sheetPet().mood,
      isNull,
      reason: '沒分享心情 → null → HomePet 畫 bored，不畫 happy',
    );
    expect(
      petMoodFromBackend(sheetPet().mood),
      isNot(petMoodFromBackend('happy')),
    );
  });

  group('【10】資訊面板（2026-11-19 使用者定，照參考圖）', () {
    Map<String, dynamic> richCard({bool times = true}) => {
      'date': '2026-09-03',
      'items': {
        'sleep_duration': 412,
        'phone_down_time': '23:22',
        'on_time': false,
        'score': {'score': 84.2},
        'steps': {'steps': 10230, 'goal': 9540},
        'sleeping_hr': {
          'avg': 56,
          'curve': [
            {'m': 0, 'v': 58},
            {'m': 5, 'v': 55},
            {'m': 10, 'v': 57},
          ],
        },
        'camera_moves': 18.4,
        'camera_timeline': {
          'points': [
            {'m': 0, 'v': 0.1},
            {'m': 5, 'v': 0.4},
          ],
        },
        'stages': {
          if (times) 'start': '23:40',
          if (times) 'end': '06:52',
          'rem_measured': true,
          'segments': [
            {'stage': 'light', 'from': 0, 'to': 30},
            {'stage': 'deep', 'from': 30, 'to': 92},
          ],
        },
      },
    };

    Map<String, dynamic> stateWithEarly() {
      final st = stateJson();
      st['friends'] = [
        {
          'handle': 'EAR111',
          'display_name': 'Early',
          'recorded_nights': 7,
          'current_streak': 5,
          'best_streak': 8,
          'streak_week': [
            for (var i = 0; i < 7; i++)
              {'date': '2026-09-0${i + 1}', 'status': i < 3 ? 'on_time' : 'future'},
          ],
        },
      ];
      return st;
    }

    TownStub stubWith(Map<String, dynamic> card, {List<Map<String, dynamic>> visits = const []}) => TownStub(
      town: FriendsResult(
        FriendsStatus.ok,
        value: townOf([
          person('ME0001', 'Nathan', mine: true, card: card),
          person('EAR111', 'Early', glow: true, card: card),
        ], visits: visits),
      ),
      state: stateWithEarly(),
    );

    testWidgets('點朋友：地圖把他移到面板上面那塊；這週、連續晚數、他分享的格子；不寫 Late', (tester) async {
      await pump(tester, stubWith(richCard()));
      await tester.tap(townie('EAR111'));
      await settle(tester);
      expect(find.byKey(const Key('town-sheet')), findsOneWidget);
      // 地圖移過去了：他在面板（佔下面 60%）上面那塊裡
      final at = tester.getCenter(townie('EAR111'));
      expect(at.dy, lessThan(900 * (1 - kTownSheetSize)));
      expect(at.dy, greaterThan(120));
      // 左右：他住地圖最右邊那間，地圖到邊緣就停（不露出空白），所以只要求在畫面內
      expect(at.dx, inInclusiveRange(0, 411));
      expect(find.byKey(const Key('town-sheet-week')), findsOneWidget);
      expect(find.textContaining('5 nights in a row', findRichText: true), findsOneWidget);
      // 面板往上拉、再往下捲到底（ListView 沒捲到的格子不會建出來）
      await tester.drag(find.byKey(const Key('town-sheet')), const Offset(0, -400));
      await settle(tester);
      await tester.drag(find.byKey(const Key('town-sheet')), const Offset(0, -900));
      await settle(tester);
      // 上面 4 格照順序補位（他沒分享起床自評 → Steps 補上），Movement 一定在最下面
      for (final k in ['sleep_duration', 'phone_down_time', 'score', 'steps', 'camera_moves']) {
        expect(find.byKey(Key('town-sheet-tile-$k'), skipOffstage: false), findsOneWidget, reason: k);
      }
      // 有時刻 → 光柱底下照標整點（不是兩端那種）
      final bars = tester
          .widgetList<CustomPaint>(find.descendant(
            of: find.byKey(const Key('town-sheet-tile-camera_moves')),
            matching: find.byWidgetPredicate((w) => w is CustomPaint && w.painter is CameraBarsPainter),
          ))
          .first
          .painter as CameraBarsPainter;
      expect(bars.endLabels, isNull);
      // 心率是健康資料，不放在第一眼（留在 See last night）
      expect(find.byKey(const Key('town-sheet-tile-sleeping_hr'), skipOffstage: false), findsNothing);
      // Movement 獨佔一整列、寫明不進分數
      expect(
        tester.getSize(find.byKey(const Key('town-sheet-tile-camera_moves'))).width,
        greaterThan(tester.getSize(find.byKey(const Key('town-sheet-tile-score'), skipOffstage: false)).width * 1.8),
      );
      expect(find.text('Camera · not part of the score'), findsOneWidget);
      // 小鎮上沒發光的原因不能從面板看出來：準時／晚了不做成格子
      expect(find.byKey(const Key('town-sheet-tile-on_time'), skipOffstage: false), findsNothing);
      expect(find.text('Late', skipOffstage: false), findsNothing);
      // 步數：圓弧＋Goal（千分位）
      expect(find.text('Goal 9,540', skipOffstage: false), findsOneWidget);
      // 拜訪按鈕還在最下面
      expect(find.byKey(const Key('town-visit-pet')), findsOneWidget);
    });

    testWidgets('小圖只畫他有分享的：沒有時刻（只寫準時與否）→ 光柱照畫但不標鐘點；沒有目標時間 → 不畫半圓鐘', (tester) async {
      await pump(tester, stubWith(richCard(times: false)));
      await tester.tap(townie('EAR111'));
      await settle(tester);
      bool hasPainter<T>(String key) => find
          .descendant(
            of: find.byKey(Key('town-sheet-tile-$key'), skipOffstage: false),
            matching: find.byWidgetPredicate((w) => w is CustomPaint && w.painter is T, skipOffstage: false),
            skipOffstage: false,
          )
          .evaluate()
          .isNotEmpty;
      await tester.drag(find.byKey(const Key('town-sheet')), const Offset(0, -400));
      await settle(tester);
      await tester.drag(find.byKey(const Key('town-sheet')), const Offset(0, -900));
      await settle(tester);
      // 那一格本身在（不然「沒有光柱」會是因為整格沒建出來而假性通過）
      expect(find.byKey(const Key('town-sheet-tile-camera_moves')), findsOneWidget);
      expect(hasPainter<CameraBarsPainter>('camera_moves'), isTrue);
      final bars = tester
          .widgetList<CustomPaint>(find.descendant(
            of: find.byKey(const Key('town-sheet-tile-camera_moves')),
            matching: find.byWidgetPredicate((w) => w is CustomPaint && w.painter is CameraBarsPainter),
          ))
          .first
          .painter as CameraBarsPainter;
      expect(bars.endLabels, ('Fell asleep', 'Woke up'), reason: '沒有時刻 → 不標整點，只寫兩端');
      expect(find.byKey(const Key('town-sheet-tile-phone_down_time'), skipOffstage: false), findsOneWidget);
      expect(hasPainter<ClockArcPainter>('phone_down_time'), isFalse);
      // 反向對照：有資料的照畫
      expect(hasPainter<RingPainter>('score'), isTrue);
    });

    testWidgets('格子第二版：每格一樣高（有圖、沒圖都一樣）；拜訪按鈕一排，後端的字拆成圓圈裡的符號＋底下的名字', (tester) async {
      final card = richCard();
      (card['items'] as Map)['awake'] = {'count': 2, 'minutes': 9};
      await pump(tester, stubWith(card));
      await tester.tap(townie('EAR111'));
      await settle(tester);
      await tester.drag(find.byKey(const Key('town-sheet')), const Offset(0, -400));
      await settle(tester);
      double h(String k) => tester.getSize(find.byKey(Key('town-sheet-tile-$k'))).height;
      expect(h('sleep_duration'), kTownTileHeight);
      expect(h('phone_down_time'), kTownTileHeight);
      expect(h('score'), kTownTileHeight);
      expect(h('steps'), kTownTileHeight);
      // 拜訪按鈕：一排（四顆的上緣一樣高）
      final tops = {
        for (final k in ['pet', 'good_night', 'sleep_well', 'proud'])
          tester.getTopLeft(find.byKey(Key('town-visit-$k'))).dy,
      };
      expect(tops, hasLength(1));
      expect(find.descendant(of: find.byKey(const Key('town-visit-good_night')), matching: find.text('🌙')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('town-visit-good_night')), matching: find.text('Good night')), findsOneWidget);
      // 沒有符號的字（PROUD-FROM-BACKEND）整串照寫
      expect(find.descendant(of: find.byKey(const Key('town-visit-proud')), matching: find.text('PROUD-FROM-BACKEND')), findsOneWidget);
    });

    testWidgets('上面的格子一律雙數（只分享 3 項 → 放 2 格）；Movement 照樣在；起床自評排在步數前面', (tester) async {
      await pump(
        tester,
        stubWith({
          'date': '2026-09-03',
          'items': {
            'sleep_duration': 400,
            'phone_down_time': '23:10',
            'morning_rating': {'rested': 4, 'label': 'Rested'},
            'camera_moves': 12.0,
          },
        }),
      );
      await tester.tap(townie('EAR111'));
      await settle(tester);
      await tester.drag(find.byKey(const Key('town-sheet')), const Offset(0, -400));
      await settle(tester);
      expect(find.byKey(const Key('town-sheet-tile-sleep_duration')), findsOneWidget);
      expect(find.byKey(const Key('town-sheet-tile-phone_down_time')), findsOneWidget);
      expect(find.byKey(const Key('town-sheet-tile-morning_rating')), findsNothing, reason: '第 3 格單出來 → 不放');
      expect(find.byKey(const Key('town-sheet-tile-camera_moves')), findsOneWidget);
    });

    testWidgets('Total sleep 是各階段比例的圓環；沒分享 Sleep stages 就不畫', (tester) async {
      Finder ring() => find.descendant(
        of: find.byKey(const Key('town-sheet-tile-sleep_duration')),
        matching: find.byKey(const Key('stages-ring')),
      );
      await pump(
        tester,
        stubWith({
          'date': '2026-09-03',
          'items': {
            'sleep_duration': 400,
            'morning_rating': {'rested': 4, 'label': 'Rested'},
            'stages': {
              'segments': [
                {'stage': 'light', 'from': 0, 'to': 200},
                {'stage': 'deep', 'from': 200, 'to': 280},
                {'stage': 'rem', 'from': 280, 'to': 400},
              ],
            },
          },
        }),
      );
      await tester.tap(townie('EAR111'));
      await settle(tester);
      expect(find.byKey(const Key('town-sheet-tile-sleep_duration')), findsOneWidget);
      expect(ring(), findsOneWidget);
    });

    testWidgets('Total sleep 沒有 stages → 沒有圓環', (tester) async {
      await pump(
        tester,
        stubWith({
          'date': '2026-09-03',
          'items': {
            'sleep_duration': 400,
            'morning_rating': {'rested': 4, 'label': 'Rested'},
          },
        }),
      );
      await tester.tap(townie('EAR111'));
      await settle(tester);
      expect(find.byKey(const Key('town-sheet-tile-sleep_duration')), findsOneWidget);
      expect(find.byKey(const Key('stages-ring')), findsNothing);
    });

    testWidgets('Felt 那格畫他早上選的那張臉（跟起床自評卡同一組圖）', (tester) async {
      await pump(
        tester,
        stubWith({
          'date': '2026-09-03',
          'items': {
            'sleep_duration': 400,
            'morning_rating': {'rested': 4, 'label': 'Rested'},
          },
        }),
      );
      await tester.tap(townie('EAR111'));
      await settle(tester);
      final face = find.descendant(
        of: find.byKey(const Key('town-sheet-tile-morning_rating')),
        matching: find.byKey(const Key('town-sheet-felt-4')),
      );
      expect(face, findsOneWidget);
      expect(((tester.widget<Image>(face)).image as AssetImage).assetName, restedFaceAsset(4));
    });

    test('格子的補位順序：起床自評在步數前面、最多 4 格、雙數', () {
      List<String> keys(Map<String, dynamic> items) => [for (final t in friendCheckIn(items)) t.$1];
      expect(
        keys({
          'sleep_duration': 400,
          'phone_down_time': '23:10',
          'score': {'score': 80},
          'morning_rating': {'label': 'Rested'},
          'steps': {'steps': 9000},
          'sleeping_hr': {'avg': 55},
          'on_time': true,
        }),
        ['sleep_duration', 'phone_down_time', 'score', 'morning_rating'],
      );
      expect(keys({'score': {'score': 80}, 'steps': {'steps': 9000}, 'awake': {'count': 2}}), ['score', 'steps']);
      expect(keys({'on_time': false, 'sleeping_hr': {'avg': 55}}), isEmpty, reason: '準時與否、心率都不進這幾格');
    });

    testWidgets('點自己：同一個面板（What friends see），最下面是今天誰來看過你，沒有拜訪按鈕', (tester) async {
      await pump(
        tester,
        stubWith(richCard(), visits: [
          {'display_name': 'Early', 'kind': 'pet', 'message': 'VISIT-FROM-BACKEND'},
        ]),
      );
      await tester.tap(townie('ME0001'));
      await settle(tester);
      expect(find.byKey(const Key('town-sheet')), findsOneWidget);
      expect(find.text('What friends see'), findsOneWidget);
      expect(find.byKey(const Key('town-sheet-visitors')), findsOneWidget);
      expect(find.text('VISIT-FROM-BACKEND'), findsOneWidget);
      expect(find.byKey(const Key('town-visit-pet')), findsNothing);
    });
  });

  testWidgets('【6】今天誰來看過你：右下小圓鈕，有人來才有紅點；點開照抄後端', (tester) async {
    await pump(tester, TownStub());
    expect(
      find.descendant(
        of: find.byKey(const Key('town-visits-button')),
        matching: find.text('1'),
      ),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('town-visits-button')));
    await settle(tester);
    expect(find.byKey(const Key('town-no-visits')), findsOneWidget);
  });

  testWidgets('【6】有人來看過你 → 紅點寫人數、點開是後端那句', (tester) async {
    final stub = TownStub(
      town: FriendsResult(
        FriendsStatus.ok,
        value: townOf(
          [person('ME0001', 'Nathan', mine: true), person('EAR111', 'Early')],
          visits: [
            {
              'display_name': 'Early',
              'kind': 'pet',
              'message': 'MESSAGE-FROM-BACKEND',
            },
          ],
        ),
      ),
    );
    await pump(tester, stub);
    expect(
      find.descendant(
        of: find.byKey(const Key('town-visits-button')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('town-visits-button')));
    await settle(tester);
    expect(find.text('Stopped by today'), findsOneWidget);
    expect(find.text('MESSAGE-FROM-BACKEND'), findsOneWidget);
  });

  testWidgets('連續晚數：左下小圓鈕寫幾晚，點了打開這週的大卡', (tester) async {
    await pump(tester, TownStub());
    expect(
      find.descendant(
        of: find.byKey(const Key('town-streak')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('town-streak')));
    await settle(tester);
    expect(find.byKey(const Key('my-week-sheet')), findsOneWidget);
  });

  testWidgets('【7】下一間空房子門口有 ＋ Invite，按了切到 Friends 分頁', (tester) async {
    final stub = TownStub(
      town: FriendsResult(
        FriendsStatus.ok,
        value: townOf([person('ME0001', 'Nathan', mine: true)]),
      ),
      state: stateJson(friends: false),
    );
    await pump(tester, stub);
    await tester.tap(find.byKey(const Key('town-invite')));
    await settle(tester);
    expect(find.byKey(const Key('my-invite-code')), findsOneWidget);
  });

  testWidgets('內容比螢幕短時，標題仍在最上面（不被垂直置中）', (tester) async {
    await pump(
      tester,
      TownStub(town: const FriendsResult(FriendsStatus.failed)),
    );
    expect(tester.getTopLeft(find.text('Friends ✨')).dy, lessThan(40));
  });

  testWidgets('【7】連不到後端 → 照實說，小鎮裡一個人都沒有', (tester) async {
    await pump(
      tester,
      TownStub(town: const FriendsResult(FriendsStatus.failed)),
    );
    expect(find.byKey(const Key('town-unreachable')), findsOneWidget);
    expect(find.byType(TownMap), findsNothing);
  });

  testWidgets('【2b】金色外框只畫在發光的人身上', (tester) async {
    await pump(tester, TownStub());
    expect(find.byKey(const Key('town-outline-ME0001')), findsOneWidget);
    expect(find.byKey(const Key('town-outline-EAR111')), findsOneWidget);
    for (final h in ['LAT222', 'BLA333', 'SHY444']) {
      expect(
        find.descendant(of: townie(h), matching: find.byType(TownOutlineGlow)),
        findsNothing,
      );
    }
  });

  testWidgets('【9】兩指縮放：最小＝地圖的寬塞進螢幕、最大 2.5 倍；點兩下空地回到原本大小與你家', (tester) async {
    await pump(tester, TownStub());
    double scale() => tester
        .widget<InteractiveViewer>(find.byKey(const Key('town-map')))
        .transformationController!
        .value
        .getMaxScaleOnAxis();
    final home = tester.getCenter(townie('ME0001'));
    expect(scale(), 1);

    Future<void> pinch(double from, double to) async {
      const c = Offset(205, 450);
      final a = await tester.startGesture(c - Offset(from, 0));
      final b = await tester.startGesture(c + Offset(from, 0), pointer: 2);
      for (var i = 1; i <= 10; i++) {
        final d = from + (to - from) * i / 10;
        await a.moveTo(c - Offset(d, 0));
        await b.moveTo(c + Offset(d, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await a.up();
      await b.up();
      await settle(tester);
    }

    // 縮到不能再縮：地圖的寬剛好等於畫面寬
    await pinch(180, 10);
    final mapW = math.max(411 * 1.5, 900 * (1086 / 1448) * 1.08);
    expect(scale(), closeTo(411 / mapW, 0.01));
    final board = tester.getRect(find.byKey(const Key('town-board')));
    expect(board.width, closeTo(411, 1));
    expect(board.height, greaterThanOrEqualTo(900 - 1), reason: '縮到最小也不露出空白');

    // 放到不能再放：2.5 倍
    await pinch(10, 200);
    await pinch(10, 200);
    await pinch(10, 200);
    expect(scale(), closeTo(2.5, 0.01));

    // 點兩下空地（最左邊沒有房子）→ 回到 1 倍、你家回到原位
    await pinch(180, 10);
    final spot = Offset(board.left + 8, 450);
    await tester.tapAt(spot);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(spot);
    await settle(tester);
    expect(scale(), closeTo(1, 0.001));
    final back = tester.getCenter(townie('ME0001'));
    expect((back - home).distance, lessThan(1));
  });

  testWidgets('【8】減少動態效果：星星不閃', (tester) async {
    await pump(tester, TownStub(), reduceMotion: true);
    double opacity() => tester
        .widget<Opacity>(
          find.descendant(
            of: find.byKey(const Key('town-glow-EAR111')),
            matching: find.byType(Opacity),
          ),
        )
        .opacity;
    final a = opacity();
    await tester.pump(const Duration(milliseconds: 700));
    expect(opacity(), a);

    await pump(tester, TownStub());
    final b = opacity();
    await tester.pump(const Duration(milliseconds: 700));
    expect(opacity(), isNot(b), reason: '反向對照：沒開減少動態效果時會閃');
  });
}
