// 早晨報告 Movement (camera) 點開（2026-11-15 使用者定）：片段＋手錶階段、動作線上的點、一週跟平常比。
import 'package:app/models/night_curve.dart';
import 'package:app/models/sleep_stages.dart';
import 'package:app/services/camera_insights.dart';
import 'package:app/widgets/movement_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime u(int h, int m) => DateTime.utc(2026, 11, 14, h, m);

/// 曲線是 isUtc 的牆鐘（同 NightCurve.fromJsonOrNull）；03:30 → 04:30 每 5 分鐘
NightCurve curve() => NightCurve(
  points: [
    for (var i = 0; i <= 12; i++)
      NightCurvePoint(u(3, 30).add(Duration(minutes: 5 * i)), i.isEven ? 0.02 : 0.1),
  ],
  avg: 0.06,
  min: 0.02,
  max: 0.1,
);

/// ⚠️ 階段用沒時區的本地時間、片段的 start_at 也沒時區——三種基準混在一起
SleepStages stages() => SleepStages(
  segments: [
    StageSegment('light', DateTime(2026, 11, 14, 3, 30), DateTime(2026, 11, 14, 4, 0)),
    StageSegment('deep', DateTime(2026, 11, 14, 4, 0), DateTime(2026, 11, 14, 4, 30)),
  ],
);

CameraNight night({List<CameraClip>? clips, String? note, double? pct, String date = '2026-11-14'}) =>
    CameraNight(
      date: date,
      clips: clips ?? const [],
      clipsNote: note,
      clipsSupported: true,
      eventsTotal: 105,
      usualLabel: 'SENT-usual',
      usualDeltaPct: pct,
      usualSamePct: 25,
      usualSupported: true,
    );

final clips = [
  CameraClip(url: 'http://x/a.gif', label: '03:42 · moved for 5 s', startAt: DateTime(2026, 11, 14, 3, 42)),
  CameraClip(url: 'http://x/b.gif', label: '04:10 · moved for 9 s', startAt: DateTime(2026, 11, 14, 4, 10)),
  // 起床之後（線的範圍外）
  CameraClip(url: 'http://x/c.gif', label: '07:52 · moved for 8 s', startAt: DateTime(2026, 11, 14, 7, 52)),
];

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 380, height: 1400, child: child)),
);

String textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  group('純函式', () {
    test('片段標籤＝後端那句＋那一刻手錶的階段；三種時間基準混著也對（不差 8 小時）；範圍外不接', () {
      expect(clipLabel(clips[0], stages()), '03:42 · moved for 5 s · Light');
      expect(clipLabel(clips[1], stages()), '04:10 · moved for 9 s · Deep');
      expect(clipLabel(clips[2], stages()), '07:52 · moved for 8 s');
      expect(clipLabel(clips[0], null), '03:42 · moved for 5 s');
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
    testWidgets('有片段：照抄那句話、不寫次數；一段一列（大的時刻＋後半＋手錶階段）；點列或線上的點跳出大的播放；範圍外不標點',
        (tester) async {
      await tester.pumpWidget(
        host(MovementView(night: night(clips: clips), curve: curve(), stages: stages())),
      );
      expect(textOf(tester, 'mv-usual'), 'SENT-usual');
      expect(find.textContaining('per hour'), findsNothing);
      // 11-15 使用者改：寫這一晚的次數（照抄 events_total），但不寫每小時幾次
      expect(textOf(tester, 'mv-count'), '105 movements seen by the camera');
      for (var i = 0; i < 3; i++) {
        expect(find.byKey(Key('mv-clip-row-$i')), findsOneWidget);
      }
      expect(find.descendant(of: find.byKey(const Key('mv-clip-row-0')), matching: find.text('03:42')),
          findsOneWidget);
      expect(
          tester.widget<Text>(find.descendant(
              of: find.byKey(const Key('mv-clip-row-1')),
              matching: find.byKey(const Key('mv-clip-row-text')))).data,
          'moved for 9 s · Deep');

      await tester.tap(find.byKey(const Key('mv-clip-row-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mv-clip-viewer')), findsOneWidget);
      expect(textOf(tester, 'mv-clip-label'), '04:10 · moved for 9 s · Deep');
      // 點影片 → 全螢幕（可以兩指放大）
      await tester.tap(find.byKey(const Key('mv-clip-enlarge')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mv-clip-fullscreen')), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.tap(find.byKey(const Key('mv-clip-fullscreen-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mv-clip-fullscreen')), findsNothing);
      await tester.tap(find.byKey(const Key('mv-clip-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mv-clip-viewer')), findsNothing);

      expect(find.byKey(const Key('mv-marker-0')), findsOneWidget);
      expect(find.byKey(const Key('mv-marker-2')), findsNothing, reason: '07:52 在起床之後');
      await tester.ensureVisible(find.byKey(const Key('mv-marker-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mv-marker-0')));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'mv-clip-label'), '03:42 · moved for 5 s · Light');
      expect(tester.takeException(), isNull);
    });

    testWidgets('沒錄影的晚上：照抄後端的原因，線照畫', (tester) async {
      await tester.pumpWidget(
        host(MovementView(night: night(note: 'SENT-no-video'), curve: curve())),
      );
      expect(textOf(tester, 'mv-clips-note'), 'SENT-no-video');
      expect(find.byKey(const Key('mv-line')), findsOneWidget);
      expect(find.byKey(const Key('mv-clip-row-0')), findsNothing);
    });

    testWidgets('一週：灰帶寬度照抄後端、長條往上（多）往下（少）、單一顏色', (tester) async {
      await tester.pumpWidget(
        host(
          MovementView(
            night: night(clips: clips),
            week: movementWeek([
              night(pct: 40),
              night(pct: -30, date: '2026-11-13'),
            ], '2026-11-14'),
          ),
        ),
      );
      expect(find.byKey(const Key('mv-week-title')), findsOneWidget);
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

  test('片段讀進 start_at；舊版後端沒有 → null', () {
    final c = CameraClip.fromJson({'url': '/camera/clips/a.gif', 'label': 'L', 'start_at': '2026-11-14T03:42:51'}, baseUrl: 'http://h:8000');
    expect(c.url, 'http://h:8000/camera/clips/a.gif');
    expect(c.startAt, DateTime(2026, 11, 14, 3, 42, 51));
    expect(CameraClip.fromJson({'url': '/a.gif', 'label': 'L'}).startAt, isNull);
  });
}
