// 早晨報告 Movement (camera) 點開（2026-11-15 使用者定，照參考圖）：
// 時間軸（每段動作一顆膠囊）→ 每個鐘頭動幾次 → 播放器（⏮ ⏭、全螢幕）→ 片段列表 → 一週跟平常比。
import 'package:app/models/night_curve.dart';
import 'package:app/models/sleep_stages.dart';
import 'package:app/services/camera_insights.dart';
import 'package:app/widgets/movement_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime l(int h, int m, [int s = 0]) => DateTime(2026, 11, 14, h, m, s);

/// ⚠️ 階段用 isUtc 的牆鐘（Sleep Stages 帶時區的字串會這樣解），片段與動作沒時區——混在一起
SleepStages stages() => SleepStages(
  segments: [
    StageSegment('light', DateTime.utc(2026, 11, 14, 3, 30), DateTime.utc(2026, 11, 14, 4, 0)),
    StageSegment('deep', DateTime.utc(2026, 11, 14, 4, 0), DateTime.utc(2026, 11, 14, 4, 30)),
  ],
);

// 03:20 開始錄影、05:10 結束；四段動作，其中兩段有片段
final episodes = [
  CameraEpisode(l(3, 42), 5, '03:42 · moved for 5 s'),
  CameraEpisode(l(3, 50), 8, '03:50 · moved for 8 s'),
  CameraEpisode(l(4, 10), 9, '04:10 · moved for 9 s'),
  CameraEpisode(l(5, 1), 30, '05:01 · moved for 30 s'),
];
// 後端照「動作大小」排：04:10 最大
final clips = [
  CameraClip(url: 'http://x/b.gif', label: '04:10 · moved for 9 s', startAt: l(4, 10)),
  CameraClip(url: 'http://x/a.gif', label: '03:42 · moved for 5 s', startAt: l(3, 42)),
];

CameraNight night({
  List<CameraClip>? clipList,
  List<CameraEpisode>? eps,
  String? note,
  double? pct,
  String date = '2026-11-14',
}) => CameraNight(
  date: date,
  bedStartAt: '2026-11-14T03:20:00',
  bedEndAt: '2026-11-14T05:10:00',
  eventsTotal: 4,
  episodes: eps,
  clips: clipList ?? const [],
  clipsNote: note,
  clipsSupported: true,
  usualLabel: 'SENT-usual',
  usualDeltaPct: pct,
  usualSamePct: 25,
  usualSupported: true,
);

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 380, height: 1800, child: child)),
);

String textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

Future<void> big(WidgetTester tester) async {
  tester.view.physicalSize = const Size(380 * 3, 1800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  group('純函式', () {
    test('標籤＝後端那句＋那一刻手錶的階段；兩種時間基準混著也對（不差 8 小時）；範圍外不接', () {
      expect(clipLabel(clips[0], stages()), '04:10 · moved for 9 s · Deep');
      expect(withStage('05:01 · moved for 30 s', l(5, 1), stages()), '05:01 · moved for 30 s');
      expect(clipLabel(clips[1], null), '03:42 · moved for 5 s');
    });

    test('次數那一行：照抄 events_total＋每段秒數加起來；沒有每段資料就只寫次數；不寫每小時', () {
      expect(movementCountLine(4, episodes), '4 movements · 52 s moving in total');
      expect(
        movementCountLine(105, [CameraEpisode(l(3, 0), 1530, '')]),
        '105 movements · 26m moving in total',
      );
      expect(movementCountLine(105, null), '105 movements seen by the camera');
      expect(movementCountLine(1, null), '1 movement seen by the camera');
      expect(movementCountLine(4, episodes).contains('hour'), isFalse);
    });

    test('每個鐘頭：照鐘點分、頭尾記涵蓋幾分鐘', () {
      final h = hourlyCounts(episodes, l(3, 20), l(5, 10));
      expect([for (final x in h) (x.$1.hour, x.$2, x.$3)], [(3, 2, 40), (4, 1, 60), (5, 1, 10)]);
    });

    test('一週：日曆上 7 晚；值照抄後端 delta_pct；沒錄影或基線不夠寫 —', () {
      final w = movementWeek([
        night(pct: 12.4),
        night(pct: -27.0, date: '2026-11-13'),
        night(pct: null, date: '2026-11-12'),
      ], '2026-11-14');
      expect(w.first.$1, '2026-11-08');
      expect(movementWeekValue(w[6].$2), '+12%');
      expect(movementWeekValue(w[5].$2), '−27%');
      expect(movementWeekValue(w[4].$2), '—');
      expect(movementWeekValue(w[0].$2), '—');
    });
  });

  group('畫面', () {
    testWidgets('一打開播動作最大的那段；列表照時間排；⏮ ⏭ 跳片段；點列表換；點畫面全螢幕', (tester) async {
      await big(tester);
      await tester.pumpWidget(
        host(MovementView(night: night(clipList: clips, eps: episodes), stages: stages())),
      );
      expect(textOf(tester, 'mv-usual'), 'SENT-usual');
      expect(textOf(tester, 'mv-count'), '4 movements · 52 s moving in total');
      expect(textOf(tester, 'mv-clip-label'), '04:10 · moved for 9 s · Deep', reason: '後端第一段＝最大');
      expect(find.byKey(const Key('mv-playhead')), findsOneWidget);

      // 列表照時間：第一列是 03:42
      expect(find.descendant(of: find.byKey(const Key('mv-clip-row-0')), matching: find.text('03:42')),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('mv-prev')));
      await tester.pump();
      expect(textOf(tester, 'mv-clip-label'), '03:42 · moved for 5 s · Light');
      await tester.tap(find.byKey(const Key('mv-next')));
      await tester.pump();
      expect(textOf(tester, 'mv-clip-label'), '04:10 · moved for 9 s · Deep');
      await tester.tap(find.byKey(const Key('mv-next')));
      await tester.pump();
      expect(textOf(tester, 'mv-clip-label'), '03:42 · moved for 5 s · Light', reason: '最後一段再往後繞回第一段');

      await tester.tap(find.byKey(const Key('mv-clip-row-1')));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'mv-clip-label'), '04:10 · moved for 9 s · Deep');

      // 暫停：GIF 停住、畫面寫 Paused；再按繼續；換一段就從頭播
      bool playing() => tester.widget<TickerMode>(find.byKey(const Key('mv-clip-ticker'))).enabled;
      expect(playing(), isTrue);
      await tester.tap(find.byKey(const Key('mv-pause')));
      await tester.pump();
      expect(playing(), isFalse);
      expect(find.byKey(const Key('mv-paused')), findsOneWidget);
      await tester.tap(find.byKey(const Key('mv-pause')));
      await tester.pump();
      expect(playing(), isTrue);
      await tester.tap(find.byKey(const Key('mv-pause')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('mv-next')));
      await tester.pump();
      expect(playing(), isTrue, reason: '換一段就從頭播');
      expect(find.byKey(const Key('mv-paused')), findsNothing);
      await tester.tap(find.byKey(const Key('mv-prev')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('mv-clip-enlarge')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mv-clip-fullscreen')), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.tap(find.byKey(const Key('mv-clip-fullscreen-close')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('點時間軸上沒有片段的那段 → 「No clip for this movement」＋那段的時間與長度（不跳去播別段）',
        (tester) async {
      await big(tester);
      await tester.pumpWidget(
        host(MovementView(night: night(clipList: clips, eps: episodes), stages: stages())),
      );
      final r = tester.getRect(find.byKey(const Key('mv-timeline')));
      // 05:01 在 03:20–05:10（110 分）裡的第 101 分
      await tester.tapAt(Offset(r.left + r.width * 101 / 110 + 2, r.center.dy));
      await tester.pump();
      expect(find.byKey(const Key('mv-no-clip')), findsOneWidget);
      expect(find.byKey(const Key('mv-clip-player')), findsNothing);
      expect(textOf(tester, 'mv-clip-label'), '05:01 · moved for 30 s');
    });

    testWidgets('有動作線時最上面畫線（不畫膠囊）；點片段的點播那段、點線上沒有片段的動作寫 No clip；段落之間有細線',
        (tester) async {
      await big(tester);
      // 線：03:30 → 05:10 每 5 分鐘（isUtc 的牆鐘，同 NightCurve.fromJsonOrNull）
      final curve = NightCurve(
        points: [
          for (var i = 0; i <= 20; i++)
            NightCurvePoint(DateTime.utc(2026, 11, 14, 3, 30).add(Duration(minutes: 5 * i)), i.isEven ? 0.02 : 0.1),
        ],
        avg: 0.06,
        min: 0.02,
        max: 0.1,
      );
      await tester.pumpWidget(host(MovementView(
          night: night(clipList: clips, eps: episodes), curve: curve, stages: stages())));
      expect(find.byKey(const Key('mv-line')), findsOneWidget);
      expect(find.byKey(const Key('mv-timeline')), findsNothing);
      expect(find.byKey(const Key('mv-playhead')), findsOneWidget);
      // 片段的點畫在線上那一刻（不是貼在底線）：03:42 線上的值約 0.052、最高 0.1 → 圖高的一半附近
      final lr = tester.getRect(find.byKey(const Key('mv-line')));
      final my = tester.getCenter(find.byKey(const Key('mv-marker-0'))).dy;
      expect(my, inInclusiveRange(lr.top + lr.height * 0.35, lr.top + lr.height * 0.65));
      // 按住滑 → 泡泡跟著走，寫那一刻的讀數（04:30 那點是 0.02 → 6 秒）
      await tester.dragFrom(Offset(lr.left + lr.width * 0.5, lr.top + 10), Offset(lr.width * 0.1, 0));
      await tester.pump();
      expect(textOf(tester, 'chart-probe-text'), '04:30 · moving 6 sec');
      expect(textOf(tester, 'mv-clip-label'), '04:10 · moved for 9 s · Deep', reason: '附近 3 分鐘沒有動作 → 不換片段');
      // 滑到 03:42 那段附近 → 泡泡吸到那段（寫那段動作，不是 5 分鐘讀數），影片跟著換（11-15 使用者）
      await tester.dragFrom(Offset(lr.left + lr.width * 0.5, lr.top + 10), Offset(-lr.width * 0.375, 0));
      await tester.pump();
      expect(textOf(tester, 'mv-clip-label'), '03:42 · moved for 5 s · Light');
      expect(textOf(tester, 'chart-probe-text'), '03:42 · moved for 5 s · Light', reason: '泡泡與播放器是同一個點');
      // 再滑回 04:10 → 影片跟著換回來
      await tester.dragFrom(Offset(lr.left + lr.width * 0.12, lr.top + 10), Offset(lr.width * 0.28, 0));
      await tester.pump();
      expect(textOf(tester, 'mv-clip-label'), '04:10 · moved for 9 s · Deep');
      expect(find.byKey(const Key('mv-viewfinder')), findsOneWidget, reason: '影片有觀景窗框');
      expect(find.byKey(const Key('mv-controls')), findsOneWidget);
      // 片段照時間排：marker-0 是 03:42
      await tester.tap(find.byKey(const Key('mv-marker-0')));
      await tester.pump();
      expect(textOf(tester, 'mv-clip-label'), '03:42 · moved for 5 s · Light');
      // 05:01 那段沒有片段：線上 03:30 → 05:10（100 分）的第 91 分
      final r = tester.getRect(find.byKey(const Key('mv-line')));
      await tester.tapAt(Offset(r.left + r.width * 91 / 100, r.top + 10));
      await tester.pump();
      expect(find.byKey(const Key('mv-no-clip')), findsOneWidget);
      expect(textOf(tester, 'mv-clip-label'), '05:01 · moved for 30 s');
      // 段落之間的細線（摘要／線／每小時／播放器／列表）
      final dividers = find.byWidgetPredicate((w) =>
          w is Container && w.constraints?.maxHeight == 1 && w.color == const Color(0x1FFFFFFF));
      expect(dividers.evaluate().length, greaterThanOrEqualTo(4));
      expect(tester.takeException(), isNull);
    });

    testWidgets('順序（11-15 使用者定）：摘要 → 播放器 → 動作線 → 每小時 → 一週 → 片段列表；線用整段錄影那條', (tester) async {
      await big(tester);
      NightCurve mk(int h, int m, int n) => NightCurve(
            points: [
              for (var i = 0; i < n; i++)
                NightCurvePoint(DateTime.utc(2026, 11, 14, h, m).add(Duration(minutes: 5 * i)), 0.05),
            ],
            avg: 0.05,
            min: 0.05,
            max: 0.05,
          );
      final full = CameraNight(
        date: '2026-11-14',
        bedStartAt: '2026-11-14T03:20:00',
        bedEndAt: '2026-11-14T05:10:00',
        eventsTotal: 4,
        motionCurve: mk(3, 20, 23), // 整段錄影 03:20 →
        episodes: episodes,
        clips: clips,
        clipsSupported: true,
        usualLabel: 'SENT-usual',
        usualDeltaPct: 5,
        usualSamePct: 25,
        usualSupported: true,
      );
      await tester.pumpWidget(host(MovementView(
        night: full,
        curve: mk(3, 40, 10), // 報告傳進來的是睡著那段 03:40 →
        stages: stages(),
        week: movementWeek([full], '2026-11-14'),
      )));
      expect(find.text('03:20'), findsWidgets, reason: '線的起點是開始錄影，不是入睡');
      expect(find.text('03:40'), findsNothing);
      double y(String k) => tester.getTopLeft(find.byKey(Key(k))).dy;
      expect(y('mv-usual') < y('mv-clip-player'), isTrue);
      expect(y('mv-clip-player') < y('mv-line'), isTrue);
      expect(y('mv-line') < y('mv-hour-3'), isTrue);
      expect(y('mv-hour-3') < y('mv-week-title'), isTrue);
      expect(y('mv-week-title') < y('mv-clip-row-0'), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('每個鐘頭：數字照數、頭尾不滿一小時的寫幾分鐘', (tester) async {
      await big(tester);
      await tester.pumpWidget(host(MovementView(night: night(clipList: clips, eps: episodes))));
      expect(textOf(tester, 'mv-hour-count-3'), '2');
      expect(textOf(tester, 'mv-hour-count-4'), '1');
      expect(textOf(tester, 'mv-hour-partial-3'), '40m');
      expect(find.byKey(const Key('mv-hour-partial-4')), findsNothing);
      expect(textOf(tester, 'mv-hour-partial-5'), '10m');
    });

    testWidgets('舊夜晚沒有每段資料 → 不畫時間軸與每小時，次數照寫', (tester) async {
      await big(tester);
      await tester.pumpWidget(host(MovementView(night: night(clipList: clips))));
      expect(find.byKey(const Key('mv-timeline')), findsNothing);
      expect(find.byKey(const Key('mv-hour-3')), findsNothing);
      expect(textOf(tester, 'mv-count'), '4 movements seen by the camera');
    });

    testWidgets('沒錄影的晚上：照抄後端的原因，時間軸照畫、沒有播放器', (tester) async {
      await big(tester);
      await tester.pumpWidget(host(MovementView(night: night(note: 'SENT-no-video', eps: episodes))));
      expect(textOf(tester, 'mv-clips-note'), 'SENT-no-video');
      expect(find.byKey(const Key('mv-timeline')), findsOneWidget);
      expect(find.byKey(const Key('mv-prev')), findsNothing);
    });

    testWidgets('一週：灰帶寬度照抄後端、長條往上（多）往下（少）、單一顏色', (tester) async {
      await big(tester);
      await tester.pumpWidget(
        host(
          MovementView(
            night: night(clipList: clips),
            week: movementWeek([
              night(pct: 40),
              night(pct: -30, date: '2026-11-13'),
            ], '2026-11-14'),
          ),
        ),
      );
      expect(find.byKey(const Key('mv-week-band')), findsOneWidget);
      expect(textOf(tester, 'mv-week-value-2026-11-14'), '+40%');
      expect(textOf(tester, 'mv-week-value-2026-11-12'), '—');
      final up = tester.getRect(find.byKey(const Key('mv-week-bar-2026-11-14')));
      final down = tester.getRect(find.byKey(const Key('mv-week-bar-2026-11-13')));
      expect(up.bottom, closeTo(down.top, 1), reason: '兩條都從中線出發，一上一下');
      Color colorOf(String k) => ((tester.widget<DecoratedBox>(find.descendant(
                  of: find.byKey(Key(k)), matching: find.byType(DecoratedBox)))
              .decoration) as BoxDecoration)
          .color!;
      expect(colorOf('mv-week-bar-2026-11-13').toARGB32() & 0xFFFFFF,
          colorOf('mv-week-bar-2026-11-14').toARGB32() & 0xFFFFFF,
          reason: '多或少不換顏色（不判斷好壞）');
      expect(tester.takeException(), isNull);
    });

    testWidgets('舊版後端沒有灰帶寬度 → 不畫灰帶（Dart 不自己寫 25）', (tester) async {
      await big(tester);
      await tester.pumpWidget(
        host(
          MovementView(
            night: night(),
            week: movementWeek([
              const CameraNight(date: '2026-11-14', usualDeltaPct: 10, usualSupported: true),
            ], '2026-11-14'),
          ),
        ),
      );
      expect(find.byKey(const Key('mv-week-band')), findsNothing);
      expect(find.byKey(const Key('mv-week-bar-2026-11-14')), findsOneWidget);
    });
  });

  test('片段讀進 start_at；每段動作讀進來；舊版後端沒有 episodes → null（不是空的）', () {
    final c = CameraClip.fromJson(
        {'url': '/camera/clips/a.gif', 'label': 'L', 'start_at': '2026-11-14T03:42:51'},
        baseUrl: 'http://h:8000');
    expect(c.url, 'http://h:8000/camera/clips/a.gif');
    expect(c.startAt, DateTime(2026, 11, 14, 3, 42, 51));
    final n = CameraNight.fromJson({
      'date': '2026-11-14',
      'episodes': [
        {'start_at': '2026-11-14T03:42:51', 'seconds': 5.1, 'label': '03:42 · moved for 5 s'},
        {'start_at': 'broken'},
      ],
    });
    expect(n.episodes!.length, 1);
    expect(n.episodes!.first.start, c.startAt, reason: '片段與動作的時刻可以直接比');
    expect(CameraNight.fromJson({'date': '2026-11-14'}).episodes, isNull);
  });
}
