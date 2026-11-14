// 早晨報告 Awake 點開（2026-11-15 使用者定）：這一晚什麼時候醒＋一週清醒分鐘。
import 'dart:convert';
import 'dart:io';

import 'package:app/models/sleep_stages.dart';
import 'package:app/services/camera_insights.dart';
import 'package:app/services/night_compare.dart';
import 'package:app/services/user_identity.dart';
import 'package:app/widgets/awake_week_sheet.dart';
import 'package:app/widgets/sleep_week_sheet.dart' show sleepWeek;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime t(String s) => DateTime.parse(s);

SleepStages night() => SleepStages(
  segments: [
    StageSegment('light', t('2026-11-14 03:30'), t('2026-11-14 04:10')),
    StageSegment('awake', t('2026-11-14 04:10'), t('2026-11-14 04:16')),
    StageSegment('deep', t('2026-11-14 04:16'), t('2026-11-14 06:00')),
    StageSegment('awake', t('2026-11-14 06:00'), t('2026-11-14 06:00:30')),
    StageSegment('rem', t('2026-11-14 06:00:30'), t('2026-11-14 08:00')),
    StageSegment('awake', t('2026-11-14 08:00'), t('2026-11-14 08:02')),
    StageSegment('light', t('2026-11-14 08:02'), t('2026-11-14 09:00')),
  ],
  awakeMinutes: 9,
);

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 380, height: 900, child: child)),
);

String textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  group('純函式', () {
    test('清醒段落照時間排；不到 1 分鐘寫 <1m（不寫 0m）', () {
      final s = awakeSpans(night());
      expect(s.map(awakeSpanLabel).toList(), [
        '04:10 · 6m',
        '06:00 · <1m',
        '08:00 · 2m',
      ]);
      expect(awakeSpans(null), isEmpty);
    });

    test('一週：0 分鐘是真的值，算進平均；沒資料不算', () {
      final w = sleepWeek([
        const NightValue('2026-11-14', 9),
        const NightValue('2026-11-13', 0),
        const NightValue('2026-11-12', 15),
      ], '2026-11-14');
      expect(w.nightsWithData, 3);
      expect(awakeAverageLine(w), 'Average 8m awake');
    });
  });

  group('畫面', () {
    testWidgets('這一晚：總數照手錶、時間軸、每段一個標籤；不寫醒了幾次', (tester) async {
      await tester.pumpWidget(
        host(AwakeView(title: 'Awake', totalMinutes: 9, stages: night())),
      );
      expect(textOf(tester, 'awake-total'), '9m');
      expect(find.byKey(const Key('awake-strip')), findsOneWidget);
      expect(textOf(tester, 'awake-strip-start'), '03:30');
      expect(textOf(tester, 'awake-strip-end'), '09:00');
      expect(find.text('04:10 · 6m'), findsOneWidget);
      expect(find.text('06:00 · <1m'), findsOneWidget);
      // 段落在時間軸上照時間由左到右
      final x0 = tester
          .getTopLeft(find.byKey(const Key('awake-strip-span-0')))
          .dx;
      final x2 = tester
          .getTopLeft(find.byKey(const Key('awake-strip-span-2')))
          .dx;
      expect(x2, greaterThan(x0));
      // 不寫次數
      expect(find.textContaining('times'), findsNothing);
      // 沒有一週資料 → 下半整段不出現
      expect(find.byKey(const Key('awake-week-average')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('⚠️ 總數用手錶的，不是把段落加起來', (tester) async {
      // 段落加起來約 8.5 分，手錶說 12 → 寫 12m
      await tester.pumpWidget(
        host(AwakeView(title: 'Awake', totalMinutes: 12, stages: night())),
      );
      expect(textOf(tester, 'awake-total'), '12m');
    });

    testWidgets('沒有時間軸的晚上：只寫總數＋說明，不編段落', (tester) async {
      await tester.pumpWidget(
        host(const AwakeView(title: 'Awake', totalMinutes: 14)),
      );
      expect(textOf(tester, 'awake-total'), '14m');
      expect(find.byKey(const Key('awake-no-timeline')), findsOneWidget);
      expect(find.byKey(const Key('awake-strip')), findsNothing);
    });

    testWidgets('一週：0 寫 0m 不畫條、沒資料寫 —、跟前一週比只代表方向', (tester) async {
      final w = sleepWeek([
        const NightValue('2026-11-14', 9),
        const NightValue('2026-11-13', 0),
        const NightValue('2026-11-12', 15),
        const NightValue('2026-11-06', 2), // 前一週
      ], '2026-11-14');
      await tester.pumpWidget(
        host(
          AwakeView(title: 'Awake', totalMinutes: 9, stages: night(), week: w),
        ),
      );
      expect(textOf(tester, 'awake-week-average'), 'Average 8m awake');
      expect(textOf(tester, 'awake-week-count'), '3 of 7 nights with data');
      expect(textOf(tester, 'awake-week-value-2026-11-13'), '0m');
      expect(find.byKey(const Key('awake-week-fill-2026-11-13')), findsNothing);
      expect(textOf(tester, 'awake-week-value-2026-11-10'), '—');
      expect(
        find.byKey(const Key('awake-week-fill-2026-11-14')),
        findsOneWidget,
      );
      final change = tester.widget<Text>(
        find.byKey(const Key('awake-week-change')),
      );
      expect(change.data, '↑ 6m vs the week before');
      expect(change.style!.color, kDeltaUp);
      // 15 分那晚的條比 9 分那晚高
      final h15 = tester
          .getSize(find.byKey(const Key('awake-week-fill-2026-11-12')))
          .height;
      final h9 = tester
          .getSize(find.byKey(const Key('awake-week-fill-2026-11-14')))
          .height;
      expect(h15, greaterThan(h9));
      expect(tester.takeException(), isNull);
    });
  });

  group('/insights 順便帶回每晚清醒分鐘', () {
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
                {'date': '2026-11-14', 'waso_minutes': 9.0},
                {'date': '2026-11-13', 'waso_minutes': 0},
                {'date': '2026-11-12', 'waso_minutes': null},
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

    test('0 照收（真的值）；null 不收', () async {
      final r = await CameraInsightsService(
        baseUrl: 'http://127.0.0.1:${server.port}',
        identity: const BuildTimeUserIdentity(overrideId: 'stub'),
      ).load();
      expect(r.awakeMinutes, {'2026-11-14': 9.0, '2026-11-13': 0.0});
    });
  });
}
