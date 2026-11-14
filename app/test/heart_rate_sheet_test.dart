// 早晨報告 Sleeping heart rate 點開（2026-11-15 使用者定）：這一晚依階段上色＋各階段平均＋最低那一刻＋一週。
import 'dart:convert';
import 'dart:io';

import 'package:app/models/night_curve.dart';
import 'package:app/models/sleep_stages.dart';
import 'package:app/services/camera_insights.dart';
import 'package:app/services/user_identity.dart';
import 'package:app/widgets/heart_rate_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 曲線的時間是 isUtc 的牆鐘（同 NightCurve.fromJsonOrNull）。
DateTime u(int h, int m) => DateTime.utc(2026, 11, 14, h, m);

NightCurve curve({DateTime? minAt}) => NightCurve(
  points: [
    NightCurvePoint(u(3, 30), 60), // light
    NightCurvePoint(u(3, 35), 56), // light
    NightCurvePoint(u(3, 40), 50), // deep
    NightCurvePoint(u(3, 45), 48), // deep
    NightCurvePoint(u(3, 50), 58), // rem
    NightCurvePoint(u(3, 55), 66), // awake
  ],
  avg: 55,
  min: 46,
  max: 69,
  minAt: minAt,
);

/// ⚠️ 階段故意用**沒時區的本地時間**（parseWallClock 對沒標記的字串就是這樣）：混著比會差 8 小時
SleepStages stages({bool rem = true}) => SleepStages(
  segments: [
    StageSegment('light', DateTime(2026, 11, 14, 3, 30), DateTime(2026, 11, 14, 3, 40)),
    StageSegment('deep', DateTime(2026, 11, 14, 3, 40), DateTime(2026, 11, 14, 3, 50)),
    StageSegment('rem', DateTime(2026, 11, 14, 3, 50), DateTime(2026, 11, 14, 3, 55)),
    StageSegment('awake', DateTime(2026, 11, 14, 3, 55), DateTime(2026, 11, 14, 4, 0)),
  ],
  remMeasured: rem,
);

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 380, height: 1200, child: child)),
);

String textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  group('純函式', () {
    test('各階段平均：照那一刻的階段分組；兩種時間基準混著也對得上（不差 8 小時）', () {
      expect(stageHeartRates(curve(), stages()), [
        ('deep', 49.0),
        ('light', 58.0),
        ('rem', 58.0),
        ('awake', 66.0),
      ]);
    });

    test('沒量到 REM 的晚上不給 REM；沒有階段 → 空', () {
      expect(
        stageHeartRates(curve(), stages(rem: false)).map((e) => e.$1),
        ['deep', 'light', 'awake'],
      );
      expect(stageHeartRates(curve(), null), isEmpty);
    });

    test('最低那一行：原始讀數的值與時刻＋入睡後多久；舊版後端沒有時刻就只寫值', () {
      expect(
        lowestLine(curve(minAt: u(3, 48))),
        'Lowest 46 at 03:48 · 18m after falling asleep',
      );
      expect(lowestLine(curve()), 'Lowest 46');
    });

    test('一週：日曆上的 7 晚、Usually＝平均的中間值、跟前一週比只代表方向', () {
      final w = heartRateWeek({
        '2026-11-14': const SleepHeartRate(55, 46),
        '2026-11-13': const SleepHeartRate(57, 51),
        '2026-11-12': const SleepHeartRate(59, 52),
        '2026-11-10': const SleepHeartRate(54, 48),
        // 前一週
        '2026-11-07': const SleepHeartRate(53, 47),
        '2026-11-06': const SleepHeartRate(54, 47),
      }, '2026-11-14');
      expect(w.nights.map((n) => n.date).first, '2026-11-08');
      expect(w.nights.last.date, '2026-11-14');
      expect(w.usual, 56); // (55+57)/2
      expect(heartRateUsualLine(w), 'Usually 56 bpm');
      expect(heartRateCountLine(w), '4 of 7 nights with data');
      expect(heartRateChangeLine(w), '↑ 3 bpm vs the week before'); // 56 − 53.5 = 2.5 → 3
    });

    test('前一週沒資料 → 不比', () {
      final w = heartRateWeek({'2026-11-14': const SleepHeartRate(55, 46)}, '2026-11-14');
      expect(heartRateChangeLine(w), isNull);
    });
  });

  group('畫面', () {
    testWidgets('這一晚：平均、最低那一行、靜止心率、各階段平均；不寫 Normal／High／最高', (tester) async {
      await tester.pumpWidget(
        host(
          HeartRateView(
            curve: curve(minAt: u(3, 48)),
            stages: stages(),
            restingHeartRate: 55,
          ),
        ),
      );
      expect(textOf(tester, 'hr-title'), 'Sleeping heart rate');
      expect(textOf(tester, 'hr-avg'), '55');
      expect(textOf(tester, 'hr-lowest'), 'Lowest 46 at 03:48 · 18m after falling asleep');
      expect(textOf(tester, 'hr-resting'), 'Resting 55 (all day)');
      expect(textOf(tester, 'hr-stage-deep'), '49 bpm');
      expect(textOf(tester, 'hr-stage-awake'), '66 bpm');
      expect(find.byKey(const Key('hr-lowest-label')), findsOneWidget);
      for (final w in ['Normal', 'High', 'Highest', '69', 'zone']) {
        expect(find.textContaining(w), findsNothing, reason: w);
      }
      // 沒有一週資料 → 下半不出現
      expect(find.byKey(const Key('hr-week-usual')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('沒有階段（Health Connect）→ 線照畫、不畫各階段那幾列', (tester) async {
      await tester.pumpWidget(host(HeartRateView(curve: curve())));
      expect(find.byKey(const Key('hr-chart')), findsOneWidget);
      expect(find.byKey(const Key('hr-stages')), findsNothing);
      expect(find.byKey(const Key('hr-resting')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('點線 → 泡泡寫那一刻的心率與階段', (tester) async {
      await tester.pumpWidget(host(HeartRateView(curve: curve(), stages: stages())));
      final chart = tester.getRect(find.byKey(const Key('hr-chart')));
      // 圖寬扣掉右邊刻度 30；03:40 在 10/25 的位置
      await tester.tapAt(Offset(chart.left + (chart.width - 30) * 10 / 25, chart.center.dy));
      await tester.pump();
      expect(textOf(tester, 'chart-probe-text'), '03:40 · 50 bpm · Deep');
    });

    testWidgets('一週：平均實心點＋最低空心點、數字照抄、沒資料寫 —、最右是這一晚', (tester) async {
      await tester.pumpWidget(
        host(
          HeartRateView(
            curve: curve(),
            week: heartRateWeek({
              '2026-11-14': const SleepHeartRate(55, 46),
              '2026-11-13': const SleepHeartRate(57, 51),
            }, '2026-11-14'),
          ),
        ),
      );
      expect(textOf(tester, 'hr-week-usual'), 'Usually 56 bpm');
      expect(textOf(tester, 'hr-week-value-2026-11-13'), '57');
      expect(textOf(tester, 'hr-week-value-2026-11-12'), '—');
      expect(find.byKey(const Key('hr-week-avg-2026-11-14')), findsOneWidget);
      expect(find.byKey(const Key('hr-week-min-2026-11-14')), findsOneWidget);
      expect(find.byKey(const Key('hr-week-legend')), findsOneWidget);
      // 最低的點在平均下面
      final a = tester.getCenter(find.byKey(const Key('hr-week-avg-2026-11-14')));
      final m = tester.getCenter(find.byKey(const Key('hr-week-min-2026-11-14')));
      expect(m.dy, greaterThan(a.dy));
      expect(tester.takeException(), isNull);
    });
  });

  group('/insights → 每晚睡著心率', () {
    late HttpServer server;
    HttpOverrides? saved;
    setUp(() async {
      saved = HttpOverrides.current;
      HttpOverrides.global = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          jsonEncode({
            'wearable': {
              'history': [
                {
                  'date': '2026-11-14',
                  'sleep_heart_rate': {'avg': 55, 'min': 46},
                },
                {'date': '2026-11-13', 'sleep_heart_rate': null},
              ],
            },
            'camera': null,
          }),
        );
        req.response.close();
      });
    });
    tearDown(() async {
      await server.close(force: true);
      HttpOverrides.global = saved;
    });

    test('照抄後端的平均與最低；null 的晚上不收（不當成 0）', () async {
      final r = await CameraInsightsService(
        baseUrl: 'http://127.0.0.1:${server.port}',
        identity: const BuildTimeUserIdentity(overrideId: 'stub'),
      ).load();
      final n = r.sleepHeartRates['2026-11-14']!;
      expect((n.avg, n.min), (55.0, 46.0));
      expect(r.sleepHeartRates.containsKey('2026-11-13'), isFalse);
    });
  });

  test('NightCurve 讀進最低那一刻（同點的時間基準）', () {
    final c = NightCurve.fromJsonOrNull({
      'points': [
        {'t': '2026-11-14T03:30:00+08:00', 'value': 60},
        {'t': '2026-11-14T03:35:00+08:00', 'value': 50},
      ],
      'avg': 55,
      'min': 46,
      'max': 60,
      'min_at': '2026-11-14T03:48:00+08:00',
    })!;
    expect(c.minAt, DateTime.utc(2026, 11, 14, 3, 48));
    expect(c.minAt!.isUtc, c.points.first.time.isUtc);
  });
}
