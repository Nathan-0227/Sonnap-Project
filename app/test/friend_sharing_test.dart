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
  );

  @override
  Future<FriendsResult<SharingSettings>> fetchSharing() async =>
      FriendsResult(FriendsStatus.ok, value: _settings);

  @override
  Future<FriendsResult<SharingSettings>> patchSharing({
    Map<String, bool>? items,
    String? timePrecision,
    String? petSpecies,
  }) async {
    patches.add({
      'items': ?items,
      'time_precision': ?timePrecision,
      'pet_species': ?petSpecies,
    });
    this.items.addAll(items ?? const {});
    if (petSpecies != null) species = petSpecies;
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

    testWidgets('只畫後端給的項目', (tester) async {
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
      expect(find.text('Phone down 01:12'), findsOneWidget);
      expect(find.text('Late'), findsOneWidget);
      expect(find.text('1,200 steps'), findsOneWidget);
      expect(find.text('Night of Nov 14'), findsOneWidget);
      // 沒給的不出現，也不寫 0
      expect(find.byKey(const Key('card-item-score')), findsNothing);
      expect(find.textContaining('Score'), findsNothing);
      expect(find.text('Game'), findsNothing);
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
