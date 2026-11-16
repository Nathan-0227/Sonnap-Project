// 好友分享（2026-11-15 使用者定，grill）：每個人自己選公開什麼、Streak 大卡、動態卡。
//
// 守的東西：
//   1. 沒公開的（null）不畫、不寫成 0——連續天數、晚幾晚、那一週都一樣
//   2. 晚了是空心圈：**不打叉、不用紅色**
//   3. 火：0 晚沒有、1–2 晚小、3 晚以上大；減少動態效果時不動
//   4. 動態卡只畫後端給的項目；這裡一格都不算
//   5. 設定頁只送改了的那幾項；總開關送整組；寵物跟後端不一樣就送一次
import 'package:app/screens/friend_sharing_screen.dart';
import 'package:app/services/friends_service.dart';
import 'package:app/services/pet_choice.dart';
import 'package:app/services/user_identity.dart';
import 'package:app/widgets/friend_night_card.dart';
import 'package:app/widgets/streak_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> summaryJson({
  int? streak = 3,
  int? best = 5,
  List<String>? week = const [
    'on_time',
    'late',
    'none',
    'on_time',
    'future',
    'future',
    'future',
  ],
  String? species = 'dog',
}) => {
  'handle': 'BOB234',
  'display_name': 'Bob',
  'pet_mood': 'happy',
  'last_night_date': '2026-11-13',
  'last_lights_out_at': null,
  'last_night_late': false,
  'current_streak': streak,
  'best_streak': best,
  'late_night_ratio': null,
  'late_nights': null,
  'recorded_nights': 4,
  'pet_species': species,
  'streak_week': week == null
      ? null
      : [
          for (var i = 0; i < week.length; i++)
            {
              'date': '2026-11-${(10 + i).toString().padLeft(2, '0')}',
              'status': week[i],
            },
        ],
};

Widget host(Widget child, {bool reduce = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(
      disableAnimations: reduce,
      size: const Size(420, 2000),
    ),
    child: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

class _Stub implements FriendsService {
  final List<Map<String, dynamic>> patches = [];
  String species;
  String scene = 'campfire';
  final Map<String, bool> items = {
    'phone_down_time': true,
    'on_time': true,
    'streak': true,
    'score': false,
    'sleep_duration': false,
  };

  _Stub({this.species = 'dog'});

  SharingSettings get _settings => SharingSettings(
    groups: [
      SharingGroup('sleep', 'Sleep', [
        for (final e in items.entries) SharingItem(e.key, e.key, e.value),
      ]),
    ],
    timePrecision: 'exact',
    petSpecies: species,
    neverShared: const ['Camera clips (video of your bedroom)'],
    scene: scene,
    scenes: const ['campfire', 'rooftop', 'lake', 'treehouse'],
  );

  @override
  Future<FriendsResult<SharingSettings>> fetchSharing() async =>
      FriendsResult(FriendsStatus.ok, value: _settings);

  @override
  Future<FriendsResult<SharingSettings>> patchSharing({
    Map<String, bool>? items,
    String? timePrecision,
    String? petSpecies,
    String? scene,
  }) async {
    patches.add({
      'items': ?items,
      'time_precision': ?timePrecision,
      'pet_species': ?petSpecies,
      'scene': ?scene,
    });
    this.items.addAll(items ?? const {});
    if (petSpecies != null) species = petSpecies;
    if (scene != null) this.scene = scene;
    return FriendsResult(FriendsStatus.ok, value: _settings);
  }

  @override
  Future<FriendsResult<(FriendSummary, FriendNightCard?)>>
  fetchPreview() async => FriendsResult(
    FriendsStatus.ok,
    value: (
      FriendSummary.fromJson(summaryJson()),
      const FriendNightCard(
        handle: 'ME',
        displayName: 'Me',
        date: '2026-11-14',
        items: {'on_time': true},
      ),
    ),
  );

  @override
  Future<FriendsResult<FriendsState>> fetch() async =>
      const FriendsResult(FriendsStatus.failed);
  @override
  Future<FriendsResult<List<FriendNightCard>>> fetchFeed() async =>
      const FriendsResult(FriendsStatus.ok, value: []);
  @override
  Future<FriendsResult<(FriendSummary, FriendNightCard?)>> fetchFriend(
    String handle,
  ) async => const FriendsResult(FriendsStatus.failed);
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

void main() {
  group('Streak 卡', () {
    test('分隔線：今天的日期＝Last night，其他寫星期＋日期', () {
      final now = DateTime(2026, 11, 16, 9);
      expect(feedDayLabel('2026-11-16', now: now), 'Last night');
      expect(feedDayLabel('2026-11-15', now: now), 'Sun, Nov 15');
      expect(feedDayLabel('2026-11-09', now: now), 'Mon, Nov 9');
    });

    test('火：0 晚沒有、1–2 小、3 以上大；字', () {
      expect([null, 0, 1, 2, 3, 12].map(flameLevel), [0, 0, 1, 1, 2, 2]);
      expect(streakTitle(1), '1 Day Streak');
      expect(streakTitle(4), '4 Days Streak');
    });

    test('⚠️ 沒公開的是 null，不是 0', () {
      final f = FriendSummary.fromJson(
        summaryJson(streak: null, best: null, week: null),
      );
      expect(f.currentStreak, isNull);
      expect(f.bestStreak, isNull);
      expect(f.lateNights, isNull);
      expect(f.streakWeek, isNull);
    });

    testWidgets('一週：準時打勾、晚了空心圈不打叉、沒資料「—」、還沒到只寫日期', (tester) async {
      await tester.pumpWidget(
        host(StreakCard(summary: FriendSummary.fromJson(summaryJson()))),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('3 Days Streak'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.bySemanticsLabel('late'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('14'), findsOneWidget); // 還沒到的那天只寫日期
      expect(find.text('2 of 7 nights on time this week'), findsOneWidget);
      expect(find.byKey(const Key('streak-flames-2')), findsOneWidget);
      // 晚了那一格不用紅色
      final late = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const Key('streak-day-2026-11-11')),
          matching: find.byType(Container),
        ),
      );
      final border = (late.decoration as BoxDecoration).border as Border;
      expect(
        border.top.color.r > 0.9 &&
            border.top.color.g < 0.3 &&
            border.top.color.b < 0.3,
        isFalse,
      );
    });

    testWidgets('連續 0 晚沒有火；沒公開連續天數就不寫大字、沒公開準時就不畫那一排', (tester) async {
      await tester.pumpWidget(
        host(
          StreakCard(summary: FriendSummary.fromJson(summaryJson(streak: 0))),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('streak-flames-1')), findsNothing);
      expect(find.byKey(const Key('streak-flames-2')), findsNothing);
      await tester.pumpWidget(
        host(
          StreakCard(
            summary: FriendSummary.fromJson(
              summaryJson(streak: null, best: null, week: null),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('streak-title')), findsNothing);
      expect(find.byKey(const Key('streak-week-line')), findsNothing);
    });

    testWidgets('減少動態效果：火不動', (tester) async {
      await tester.pumpWidget(
        host(
          StreakCard(summary: FriendSummary.fromJson(summaryJson())),
          reduce: true,
        ),
      );
      await tester.pump();
      FlamePainter painter() => tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byKey(const Key('streak-flames-2')),
              matching: find.byType(CustomPaint),
            ),
          )
          .map((c) => c.painter)
          .whereType<FlamePainter>()
          .first;
      final t0 = painter().t;
      await tester.pump(const Duration(milliseconds: 500));
      expect(painter().t, t0);
    });

    testWidgets('會動的時候火真的在動（反向對照）', (tester) async {
      await tester.pumpWidget(
        host(StreakCard(summary: FriendSummary.fromJson(summaryJson()))),
      );
      await tester.pump();
      FlamePainter painter() => tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byKey(const Key('streak-flames-2')),
              matching: find.byType(CustomPaint),
            ),
          )
          .map((c) => c.painter)
          .whereType<FlamePainter>()
          .first;
      final t0 = painter().t;
      await tester.pump(const Duration(milliseconds: 500));
      expect(painter().t, isNot(t0));
    });
  });

  group('動態卡', () {
    test('一項一行；沒值、形狀不對不畫', () {
      expect(friendItemLine('on_time', false), 'Late');
      expect(
        friendItemLine('score', {'score': 78.6, 'quality': 'Normal'}),
        'Score 79 · Normal',
      );
      expect(
        friendItemLine('awake', {'count': 1, 'minutes': 4}),
        'Woke up 1 time · 4m awake',
      );
      expect(
        friendItemLine('steps', {
          'steps': 8847,
          'distance_m': 6043,
          'floors': 12.1,
        }),
        '8,847 steps · 6.0 km · 12 floors',
      );
      expect(
        friendItemLine('efficiency', {'value': 96.2, 'label': 'Sleep button'}),
        'Efficiency 96.2% (Sleep button)',
      );
      expect(friendItemLine('score', null), isNull);
      expect(
        friendItemLine('challenges', [
          {'title': 'Steady bedtime', 'completed': false},
          {'title': "Phone down once you're in bed", 'completed': true},
        ]),
        "Done: Phone down once you're in bed · 1 in progress",
      );
      expect(friendItemLine('morning_rating', {'rested': 3}), isNull);
    });

    testWidgets('三個大數字都沒公開 → 退回放下手機＋準時；其他不畫在卡上', (tester) async {
      await tester.pumpWidget(
        host(
          const FriendNightCardView(
            card: FriendNightCard(
              handle: 'BOB234',
              displayName: 'Bob',
              date: '2026-11-14',
              items: {
                'phone_down_time': '01:12',
                'on_time': false,
                'steps': {'steps': 1200},
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Phone down'), findsOneWidget);
      expect(find.text('01:12'), findsOneWidget);
      expect(find.text('Late'), findsOneWidget);
      // 步數不畫在卡上，完整頁也不放（白天的資料跟睡眠無關）→ 不算進 +N more
      expect(find.text('1,200'), findsNothing);
      expect(find.byKey(const Key('card-more')), findsNothing);
      // 動態牆上有分隔線寫日期，卡上不再寫
      expect(find.text('Night of Nov 14'), findsNothing);
      // 沒給的不出現，也不寫 0
      expect(find.textContaining('Score'), findsNothing);
      expect(find.byKey(const Key('card-stages')), findsNothing);
    });

    const stages = {
      'deep': 62,
      'light': 250,
      'rem': 100,
      'rem_measured': true,
      'segments': [
        {'stage': 'light', 'from': 0, 'to': 30},
        {'stage': 'deep', 'from': 30, 'to': 92},
        {'stage': 'rem', 'from': 92, 'to': 192},
        {'stage': 'awake', 'from': 192, 'to': 200},
        {'stage': 'light', 'from': 200, 'to': 420},
      ],
    };

    testWidgets('卡上只有三個大數字：睡多久、每小時動幾次、分數（2026-11-16 使用者定）；其他算進 +N more', (tester) async {
      await tester.pumpWidget(
        host(
          const FriendNightCardView(
            card: FriendNightCard(
              handle: 'B',
              displayName: 'Bob',
              date: '2026-11-14',
              items: {
                'score': {'score': 84.2},
                'camera_moves': 18.4,
                'sleep_duration': 412,
                'efficiency': {'value': 91.4},
                'steps': {'steps': 8432},
                'phone_down_time': '23:42',
                'on_time': true,
                'pet_mood': 'happy',
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      List<String> keysStarting(String prefix) => tester
          .widgetList(
            find.byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key as ValueKey<String>).value.startsWith(prefix),
            ),
          )
          .map((w) => (w.key as ValueKey<String>).value)
          .toList();
      expect(keysStarting('card-stat-'), [
        'card-stat-sleep_duration',
        'card-stat-camera_moves',
        'card-stat-score',
      ]);
      expect(find.text('6h 52m'), findsOneWidget);
      expect(find.text('Moves/hr'), findsOneWidget);
      expect(find.text('18'), findsOneWidget);
      expect(find.text('84'), findsOneWidget);
      // 效率太擠拿掉了；卡上沒有小格
      expect(find.text('Efficiency'), findsNothing);
      expect(keysStarting('card-tile-'), isEmpty);
      // 剩下效率、放下手機、準時（pet_mood 畫成寵物、步數完整頁不放，都不算）
      expect(find.text('+3 more'), findsOneWidget);
    });

    testWidgets('全部都畫在卡上了就沒有 See all', (tester) async {
      await tester.pumpWidget(
        host(
          const FriendNightCardView(
            card: FriendNightCard(
              handle: 'B',
              displayName: 'Bob',
              date: '2026-11-14',
              items: {
                'phone_down_time': '23:42',
                'on_time': true,
                'pet_mood': 'happy',
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('card-more')), findsNothing);
    });

    testWidgets('See all：一整頁、同一張卡的樣子（場景＋寵物），每一項都是小格、不收起來', (tester) async {
      // 夠高的畫面，資訊卡裡的小格一次全部排得出來
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const card = FriendNightCard(
        handle: 'B',
        displayName: 'Bob',
        date: '2026-11-14',
        items: {
          'sleep_duration': 412,
          'time_in_bed': 435,
          'phone_down_time': '23:42',
          'on_time': true,
          'awake': {'count': 2, 'minutes': 10},
          'sleeping_hr': {'avg': 56, 'min': 49},
          'steps': {'steps': 8432},
          'stress': {'high': 1980},
          'level': {'level': 4, 'xp_total': 1260},
          'outfit': {'badges': 3},
        },
      );
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => openFriendNight(context, card),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('night-detail')), findsOneWidget);
      expect(find.byKey(const Key('night-scene')), findsOneWidget); // 上面是場景（像 Strava 的地圖）
      // 三個大數字之外的 7 項全部是小格（卡片上只會有 3 格）
      // Strava 式的區塊（2026-11-16 使用者定）：他有公開的才出現
      for (final k in ['stages', 'hr', 'bedtime', 'game']) {
        expect(find.byKey(Key('section-$k')), findsOneWidget, reason: k);
      }
      expect(find.byKey(const Key('stage-row-awake')), findsOneWidget);
      expect(find.text('2 times · 10m'), findsOneWidget);
      expect(find.text('56 bpm'), findsOneWidget);
      expect(find.text('Lv 4'), findsOneWidget);
      // 沒公開的整段不出現、不畫成 0
      expect(find.byKey(const Key('section-camera')), findsNothing);
      expect(find.byKey(const Key('section-morning')), findsNothing);
      expect(find.byKey(const Key('hr-chart')), findsNothing); // 沒有整晚的線就只有數字
      // 白天的資料（步數、壓力）跟睡眠無關，完整頁不放（使用者定）
      expect(find.text('8,432'), findsNothing);
      expect(find.textContaining('stress'), findsNothing);
      // 不再有小格
      expect(find.byKey(const Key('card-tile-on_time')), findsNothing);
      expect(find.byKey(const Key('card-more')), findsNothing);
    });

    testWidgets('完整頁的區塊：階段表、心率線、攝影機光柱、就寢時間軸照時間排、早上、遊戲', (tester) async {
      tester.view.physicalSize = const Size(400, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final card = FriendNightCard(handle: 'B', displayName: 'Bob', date: '2026-11-14', items: {
        'stages': {
          'deep': 60, 'light': 240, 'rem': 0, 'rem_measured': false, 'start': '23:28', 'end': '07:41',
          'segments': [{'stage': 'light', 'from': 0, 'to': 60}, {'stage': 'deep', 'from': 60, 'to': 120}],
        },
        'awake': {'count': 1, 'minutes': 6},
        'sleeping_hr': {'avg': 56, 'min': 48, 'curve': [for (var i = 0; i < 20; i++) {'m': i * 5, 'v': 50 + i % 7}]},
        'resting_hr': 54,
        'camera_moves': 14,
        'camera_timeline': {'points': [for (var i = 0; i < 20; i++) {'m': i * 5, 'v': i % 3 == 0 ? 0.2 : 0.0}],
          'total': 105, 'moving_sec': 1500, 'usual': 'About the same as usual'},
        'target_bedtime': '23:30', 'phone_down_time': '23:12', 'on_time': true,
        'bed_times': {'start': '23:16', 'end': '07:52'}, 'fell_asleep': 12,
        'efficiency': {'value': 93.4, 'label': 'Sleep button'},
        'morning_rating': {'rested': 4, 'label': 'Rested'},
        'challenges': [{'title': 'Steady bedtime', 'completed': true}],
        'devices': [
          {'kind': 'watch', 'name': 'Garmin Vivoactive 3'},
          {'kind': 'camera', 'name': 'Camera'},
          {'kind': 'phone', 'name': 'Phone'},
        ],
      });
      await tester.pumpWidget(MaterialApp(home: FriendNightPage(card: card)));
      // 用了哪些設備（像 Strava 的鞋子與手錶），照後端給的寫
      for (final d in ['Garmin Vivoactive 3', 'Camera', 'Phone']) {
        expect(find.descendant(of: find.byKey(const Key('night-devices')), matching: find.text(d)),
            findsOneWidget, reason: d);
      }
      await tester.pump(const Duration(milliseconds: 100));
      for (final k in ['stages', 'hr', 'camera', 'bedtime', 'morning', 'game']) {
        expect(find.byKey(Key('section-$k')), findsOneWidget, reason: k);
      }
      // 階段表：比例照抄分鐘數；沒量到 REM 寫 not measured、不畫成 0%
      expect(find.text('20%'), findsOneWidget); // 60 / 300
      expect(find.text('80%'), findsOneWidget);
      expect(find.text('not measured'), findsOneWidget);
      expect(find.text('0%'), findsNothing);
      // 心率：有線就畫圖；不寫 Normal／High
      expect(find.byKey(const Key('hr-chart')), findsOneWidget);
      expect(find.text('48 bpm'), findsOneWidget);
      expect(find.textContaining('Normal'), findsNothing);
      expect(find.textContaining('High'), findsNothing);
      // 攝影機：光柱、跟平常比照抄、不進分數
      expect(find.byKey(const Key('camera-chart')), findsOneWidget);
      expect(find.text('About the same as usual'), findsOneWidget);
      expect(find.text('25m'), findsOneWidget);
      expect(find.textContaining('Not part of the sleep score'), findsOneWidget);
      // 就寢時間軸照時間排（目標 23:30 排在睡著 23:28 之後；過了午夜的排最後）
      final labels = [
        for (var i = 0; i < 6; i++)
          (tester.widget<Text>(find.descendant(
            of: find.byKey(Key('bed-step-$i')),
            matching: find.byType(Text),
          ).at(1))).data,
      ];
      expect(labels, [
        'Phone down · On time',
        'Start Sleep',
        'Fell asleep · 12m after Start Sleep',
        'Target bedtime',
        'Woke up',
        'Out of bed',
      ]);
      expect(find.text('93%'), findsOneWidget);
      expect(find.text('Sleep button'), findsOneWidget);
      expect(find.text('Rested'), findsOneWidget);
      expect(find.text('Steady bedtime'), findsOneWidget);
    });

    testWidgets('See all：有睡眠圖時，深睡／淺睡／REM 各一格（卡片上不放）', (tester) async {
      const card = FriendNightCard(handle: 'B', displayName: 'Bob', date: '2026-11-14', items: {
        'stages': {'deep': 82, 'light': 215, 'rem': 103, 'rem_measured': true,
          'segments': [{'stage': 'light', 'from': 0, 'to': 60}, {'stage': 'deep', 'from': 60, 'to': 120}]},
      });
      await tester.pumpWidget(host(const FriendNightCardView(card: card)));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('card-tile-stages-deep')), findsNothing);
      await tester.pumpWidget(host(const FriendNightCardView(card: card, expanded: true)));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('1h 22m'), findsOneWidget);
      expect(find.text('3h 35m'), findsOneWidget);
      expect(find.text('1h 43m'), findsOneWidget);
    });

    testWidgets('Sleep Stages：準確時刻的人兩端寫時刻', (tester) async {
      await tester.pumpWidget(
        host(
          const FriendNightCardView(
            card: FriendNightCard(
              handle: 'B',
              displayName: 'Bob',
              date: '2026-11-14',
              items: {
                'stages': {...stages, 'start': '00:31', 'end': '07:38'},
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('card-stages')), findsOneWidget);
      expect(find.text('00:31'), findsOneWidget);
      expect(find.text('07:38'), findsOneWidget);
      // 圖例拿掉了（B 版）；分鐘數在 See all 裡
      expect(find.text('Deep 1h 2m'), findsNothing);
      // 有圖時分鐘數不再重複寫成一行小字
      expect(find.byKey(const Key('card-item-stages')), findsNothing);
    });

    testWidgets('Sleep Stages：只寫準時與否的人（後端沒給時刻）兩端只寫 Fell asleep／Woke up', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const FriendNightCardView(
            card: FriendNightCard(
              handle: 'B',
              displayName: 'Bob',
              date: '2026-11-14',
              items: {'stages': stages},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Fell asleep'), findsOneWidget);
      expect(find.text('Woke up'), findsOneWidget);
      expect(find.textContaining(RegExp(r'\d\d:\d\d')), findsNothing);
    });
  });

  group('What friends can see', () {
    setUp(() => PetChoice.current.value = PetSpecies.dog);

    Future<void> open(WidgetTester tester, _Stub stub) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: FriendSharingScreen(service: stub)),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('點開一組、切一項 → 只送那一項', (tester) async {
      final stub = _Stub();
      await open(tester, stub);
      await tester.tap(find.byKey(const Key('sharing-group-sleep')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const Key('sharing-item-score')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(stub.patches.last, {
        'items': {'score': true},
      });
      expect(find.byKey(const Key('sharing-never')), findsOneWidget);
      expect(find.byKey(const Key('sharing-preview')), findsOneWidget);
    });

    testWidgets('選場景：點一張 → 只送 scene；選中的那張有框', (tester) async {
      final stub = _Stub();
      await open(tester, stub);
      expect(find.byKey(const Key('sharing-scenes')), findsOneWidget);
      // 清單照後端給的
      for (final id in ['campfire', 'rooftop', 'lake', 'treehouse']) {
        expect(find.byKey(Key('sharing-scene-$id')), findsOneWidget);
      }
      await tester.tap(find.byKey(const Key('sharing-scene-lake')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(stub.patches.last, {'scene': 'lake'});
      expect(stub.scene, 'lake');
      // 點已經選中的那張不再送
      final n = stub.patches.length;
      await tester.tap(find.byKey(const Key('sharing-scene-lake')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(stub.patches.length, n);
    });

    testWidgets('總開關 → 整組一起送', (tester) async {
      final stub = _Stub();
      await open(tester, stub);
      await tester.tap(find.byKey(const Key('sharing-group-switch-sleep')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(stub.patches.last['items'], {
        'phone_down_time': true,
        'on_time': true,
        'streak': true,
        'score': true,
        'sleep_duration': true,
      });
    });

    testWidgets('只寫準時與否 → 送 time_precision', (tester) async {
      final stub = _Stub();
      await open(tester, stub);
      await tester.tap(find.text('On time or late only'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(stub.patches.last, {'time_precision': 'on_time_only'});
    });

    testWidgets('寵物跟後端不一樣 → 送一次；一樣就不送', (tester) async {
      PetChoice.current.value = PetSpecies.cat;
      final stub = _Stub(species: 'dog');
      await open(tester, stub);
      expect(stub.patches, [
        {'pet_species': 'cat'},
      ]);
      PetChoice.current.value = PetSpecies.dog;
      final same = _Stub(species: 'dog');
      await open(tester, same);
      expect(same.patches, isEmpty);
    });
  });
}
