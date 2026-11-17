// 好友排行榜（第二批）。守的事：
// - 名次、門檻、並列都照抄後端（Dart 不重排、不算平均）
// - 名次變化只代表方向：往上紅、往下綠；上個時段沒上榜就不畫
// - 換指標時用那個指標預設的時段（送 period: null）；換時段送那個時段
// - 「你」的卡三種狀態都講清楚；示範帳號標 Demo
// - 不到門檻的人沒有名次，寫「N nights so far」
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/friends_service.dart';
import 'package:app/widgets/leaderboard_section.dart';

class FakeLeaderboardService implements FriendsService {
  @override
  Future<FriendsResult<TownState>> fetchTown() async => const FriendsResult(FriendsStatus.failed);

  @override
  Future<FriendsResult<String>> visit(String handle, String kind) async => const FriendsResult(FriendsStatus.failed);

  final List<(String, String?)> calls = [];
  Map<String, dynamic> Function(String metric, String? period) reply;
  FakeLeaderboardService(this.reply);

  @override
  Future<FriendsResult<LeaderboardBoard>> fetchLeaderboard(
    String metric, {
    String? period,
  }) async {
    calls.add((metric, period));
    return FriendsResult(
      FriendsStatus.ok,
      value: LeaderboardBoard.fromJson(reply(metric, period)),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> person(
  String name, {
  int? rank,
  String? display,
  int nights = 3,
  int? change,
  bool mine = false,
  bool demo = false,
}) => {
  'handle': name.toUpperCase(),
  'display_name': demo ? '$name (demo)' : name,
  'mine': mine,
  'demo': demo,
  'pet_species': 'dog',
  'rank': rank,
  'display': display,
  'nights': nights,
  'change': change,
};

Map<String, dynamic> boardJson({
  String metric = 'on_time',
  String period = 'week',
  List<Map<String, dynamic>> entries = const [],
  List<Map<String, dynamic>> below = const [],
  Map<String, dynamic> me = const {
    'status': 'not_sharing',
    'share_label': 'On time or late',
  },
  int need = 3,
  String? unit,
}) => {
  'unit': ?unit,
  'metric': metric,
  'period': period,
  'label': 'On time',
  'title': 'Phone-down champ',
  'need': need,
  'metrics': [
    {'key': 'on_time', 'label': 'On time'},
    {'key': 'streak', 'label': 'Streak'},
    {'key': 'sleep', 'label': 'Sleep'},
  ],
  'periods': [
    {'key': 'week', 'label': '7 days'},
    {'key': 'month', 'label': '30 days'},
  ],
  'entries': entries,
  'below': below,
  'me': me,
};

Future<void> pump(WidgetTester tester, FakeLeaderboardService svc) async {
  tester.view.physicalSize = const Size(400, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: LeaderboardSection(service: svc)),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('照後端的順序畫、並列照抄、第一名有稱號；Dart 不重排', (tester) async {
    // 後端把 0/3 的 Carol 排第一——看起來不合理也照抄（同分規則只有一個定義處）
    final svc = FakeLeaderboardService(
      (m, p) => boardJson(
        entries: [
          person('Carol', rank: 1, display: '0 / 3 nights'),
          person('Bob', rank: 1, display: '3 / 3 nights'),
          person('Ann', rank: 3, display: '2 / 3 nights'),
          person('Dee', rank: 4, display: '1 / 3 nights'),
        ],
      ),
    );
    await pump(tester, svc);
    expect(svc.calls, [('on_time', null)]); // 預設停在 On time、時段給後端決定
    final carol = tester.getCenter(find.byKey(const Key('lb-podium-CAROL'))).dx;
    final bob = tester.getCenter(find.byKey(const Key('lb-podium-BOB'))).dx;
    expect(carol, greaterThan(bob)); // 第一個（後端排第一）站中間、第二個站左邊
    expect(find.text('Phone-down champ'), findsOneWidget);
    expect(find.byKey(const Key('lb-row-DEE')), findsOneWidget);
  });

  testWidgets('名次變化：往上紅、往下綠；0 是橫線；上個時段沒上榜不畫', (tester) async {
    final svc = FakeLeaderboardService(
      (m, p) => boardJson(
        entries: [
          person('A', rank: 1, display: 'x', change: 2),
          person('B', rank: 2, display: 'x', change: -1),
          person('C', rank: 3, display: 'x', change: null),
          person('D', rank: 4, display: 'x', change: 0),
        ],
      ),
    );
    await pump(tester, svc);
    Color? arrow(String handle, IconData icon) => tester
        .widget<Icon>(
          find.descendant(
            of: find.byKey(Key(handle)),
            matching: find.byIcon(icon),
          ),
        )
        .color;
    expect(
      arrow('lb-podium-A', Icons.arrow_drop_up_rounded),
      const Color(0xFFFF6B6B),
    );
    expect(
      arrow('lb-podium-B', Icons.arrow_drop_down_rounded),
      const Color(0xFF4CD08A),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('lb-podium-C')),
        matching: find.byType(Icon),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('lb-row-D')),
        matching: find.text('–'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('換指標送 period: null（用那個指標預設的時段）；換時段送那個時段', (tester) async {
    final svc = FakeLeaderboardService(
      (m, p) => boardJson(metric: m, period: p ?? 'week'),
    );
    await pump(tester, svc);
    await tester.tap(find.byKey(const Key('lb-period-month')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const Key('lb-metric-sleep')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(svc.calls, [
      ('on_time', null),
      ('on_time', 'month'),
      ('sleep', null),
    ]);
  });

  testWidgets('不到門檻：沒有名次、寫幾晚了；示範帳號標 Demo；「你」的卡講還差幾晚', (tester) async {
    final svc = FakeLeaderboardService(
      (m, p) => boardJson(
        entries: [person('Mia', rank: 1, display: '3 / 3 nights', demo: true)],
        below: [person('Me', nights: 1, mine: true)],
        me: {'status': 'below', ...person('Me', nights: 1, mine: true)},
      ),
    );
    await pump(tester, svc);
    expect(find.text('Mia'), findsOneWidget); // 名字不重複寫 (demo)
    expect(find.text('Demo'), findsOneWidget);
    expect(find.text('Not ranked yet · needs 3 nights'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('lb-below-ME')),
        matching: find.text('1 night so far'),
      ),
      findsOneWidget,
    );
    expect(
      find.text('You have 1 of 3 nights — 2 more to be ranked'),
      findsOneWidget,
    );
  });

  testWidgets('「你」的卡：有名次寫名次；沒公開寫要打開哪一項（照抄後端的名字）', (tester) async {
    var me = <String, dynamic>{
      'status': 'ranked',
      ...person('Me', rank: 2, display: '7h 10m', mine: true),
    };
    final svc = FakeLeaderboardService(
      (m, p) => boardJson(
        entries: [
          person('Ann', rank: 1, display: '8h'),
          person('Me', rank: 2, display: '7h 10m', mine: true),
        ],
        me: me,
      ),
    );
    await pump(tester, svc);
    expect(find.text('You · #2 · 7h 10m'), findsOneWidget);
    me = {'status': 'not_sharing', 'share_label': 'Time asleep'};
    await tester.tap(find.byKey(const Key('lb-metric-sleep')));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Share “Time asleep” to join this board'), findsOneWidget);
  });

  testWidgets('手機字放大（1.3 倍）時，最矮那一階的名次＋箭頭不溢出', (tester) async {
    // 2026-11-17 實機：第三名那一階 BOTTOM OVERFLOWED BY 1.00 PIXELS
    final svc = FakeLeaderboardService(
      (m, p) => boardJson(
        entries: [
          person('A', rank: 1, display: '7 / 7 nights', change: 0),
          person('B', rank: 2, display: '5 / 7 nights', change: 2),
          person('C', rank: 3, display: '0 / 5 nights', change: -1),
        ],
      ),
    );
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester, svc);
    expect(find.byKey(const Key('lb-podium-C')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('步數、壓力的榜數「天」：不寫成 nights（照抄後端的 unit）', (tester) async {
    // 2026-11-17 實機：Chill 單日榜寫「You have 0 of 1 nights」
    final svc = FakeLeaderboardService(
      (m, p) => boardJson(
        unit: 'day',
        entries: [person('Ann', rank: 1, display: '34 avg')],
        below: [person('Me', nights: 2, mine: true), person('Bo', nights: 1)],
        me: {'status': 'below', ...person('Me', nights: 2, mine: true)},
      ),
    );
    await pump(tester, svc);
    expect(find.text('Not ranked yet · needs 3 days'), findsOneWidget);
    expect(find.text('2 days so far'), findsOneWidget);
    expect(find.text('1 day so far'), findsOneWidget);
    expect(
      find.text('You have 2 of 3 days — 1 more to be ranked'),
      findsOneWidget,
    );
    expect(find.textContaining('night'), findsNothing);
  });

  testWidgets('門檻只有 1（單晚／單日）：不寫「0 of 1」', (tester) async {
    final svc = FakeLeaderboardService(
      (m, p) => boardJson(
        unit: 'day',
        need: 1,
        entries: [person('Ann', rank: 1, display: '34 avg')],
        below: [person('Me', nights: 0, mine: true)],
        me: {'status': 'below', ...person('Me', nights: 0, mine: true)},
      ),
    );
    await pump(tester, svc);
    expect(find.text('No day recorded for you yet'), findsOneWidget);
    expect(find.textContaining('0 of 1'), findsNothing);
  });

  testWidgets('沒有人上榜：講清楚還要幾晚，不畫空的頒獎台', (tester) async {
    final svc = FakeLeaderboardService(
      (m, p) => boardJson(below: [person('Ann', nights: 2)]),
    );
    await pump(tester, svc);
    expect(
      find.text('No one has 3 nights in the last 7 days yet.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('lb-title')), findsNothing);
  });
}
