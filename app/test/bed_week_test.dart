// 一週上床／起床時刻（2026-11-14 使用者定）：按鈕優先、沒按退回手錶；左邊是時鐘。
import 'dart:convert';
import 'dart:io';

import 'package:app/services/camera_insights.dart';
import 'package:app/services/user_identity.dart';
import 'package:app/widgets/bed_week_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime t(String s) => DateTime.parse(s);

void main() {
  group('bedWeek()', () {
    test('按鈕上床、下床兩個都有才用按鈕；不然退回手錶；都沒有空著', () {
      final w = bedWeek(
        endDate: '2026-11-14',
        buttons: {
          '2026-11-14': (t('2026-11-14 03:20'), t('2026-11-14 09:00')),
          '2026-11-13': (t('2026-11-13 02:00'), null), // 只按了上床
        },
        watch: {
          '2026-11-13': (t('2026-11-13 02:30'), t('2026-11-13 08:00')),
          '2026-11-14': (t('2026-11-14 03:33'), t('2026-11-14 09:51')),
        },
      );
      expect(w.nights.length, 7);
      expect(w.nights.last.span!.source, BedSource.button);
      expect(w.nights[5].span!.source, BedSource.watch);
      expect(w.nights[5].span!.start, t('2026-11-13 02:30'));
      expect(w.nights.take(5).every((n) => n.span == null), isTrue);
      expect(w.watchNights, 1);
    });

    test('⚠️ 跨午夜的中間值：23:30、01:30、02:30 → 01:30（不是中午）', () {
      final w = bedWeek(
        endDate: '2026-11-14',
        buttons: {
          '2026-11-12': (t('2026-11-11 23:30'), t('2026-11-12 07:30')),
          '2026-11-13': (t('2026-11-13 01:30'), t('2026-11-13 09:30')),
          '2026-11-14': (t('2026-11-14 02:30'), t('2026-11-14 08:00')),
        },
      );
      expect(clockOf(w.medianStart!), '01:30');
      expect(clockOf(w.medianEnd!), '08:00');
      expect(w.averageMinutes, 430);
      expect(w.middleBand, isNull, reason: '不到 4 晚不畫帶子');
    });

    test('淡色帶：去掉最早、最晚各四分之一（無條件捨去），照實數晚數', () {
      BedWeek withStarts(List<String> hhmm) => bedWeek(
        endDate: '2026-11-14',
        buttons: {
          for (var i = 0; i < hhmm.length; i++)
            '2026-11-${(14 - i).toString().padLeft(2, '0')}': (
              t('2026-11-${(14 - i).toString().padLeft(2, '0')} ${hhmm[i]}'),
              t('2026-11-${(14 - i).toString().padLeft(2, '0')} 10:00'),
            ),
        },
      );
      // 7 晚：去掉最早 1、最晚 1 → 5 晚
      final w7 = withStarts([
        '01:00',
        '02:00',
        '03:00',
        '03:20',
        '03:30',
        '04:00',
        '05:30',
      ]);
      final b7 = w7.middleBand!;
      expect(
        (clockOf(b7.from), clockOf(b7.to), b7.count),
        ('02:00', '04:00', 5),
      );
      expect(clockOf(w7.medianStart!), '03:20');
      // 6 晚 → 4 晚、4 晚 → 2 晚
      expect(
        withStarts([
          '01:00',
          '02:00',
          '03:00',
          '04:00',
          '05:00',
          '06:00',
        ]).middleBand!.count,
        4,
      );
      expect(
        withStarts(['01:00', '02:00', '03:00', '04:00']).middleBand!.count,
        2,
      );
      // 偶數晚的中間值＝中間兩晚的平均
      expect(
        clockOf(withStarts(['01:00', '02:00', '03:00', '04:00']).medianStart!),
        '02:30',
      );
    });

    test('不合理的時間不收：下床早於上床、超過 14 小時', () {
      final w = bedWeek(
        endDate: '2026-11-14',
        buttons: {
          '2026-11-14': (t('2026-11-14 09:00'), t('2026-11-14 03:00')),
          '2026-11-13': (t('2026-11-12 18:00'), t('2026-11-13 12:30')),
        },
      );
      expect(w.nightsWithData, 0);
      expect(w.medianStart, isNull);
    });
  });

  group('畫面', () {
    Future<void> pump(WidgetTester tester, BedWeek w, {String? target}) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BedWeekView(
                title: 'Time in bed',
                week: w,
                targetBedtime: target,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('平均上床→起床、平均臥床、上床範圍；手錶的晚上空心並說明；目標虛線', (tester) async {
      final w = bedWeek(
        endDate: '2026-11-14',
        buttons: {
          '2026-11-14': (t('2026-11-14 03:20'), t('2026-11-14 09:00')),
          '2026-11-12': (t('2026-11-12 02:20'), t('2026-11-12 08:00')),
        },
        watch: {'2026-11-13': (t('2026-11-13 02:50'), t('2026-11-13 09:30'))},
      );
      await pump(tester, w, target: '03:00');
      expect(find.text('02:50 → 09:00'), findsOneWidget, reason: '上床、起床各自的中間值');
      expect(find.text('Average 6h in bed · 3 of 7 nights'), findsOneWidget);
      expect(find.byKey(const Key('bed-week-median')), findsOneWidget);
      expect(find.text('usual 02:50'), findsOneWidget);
      expect(
        find.byKey(const Key('bed-week-band')),
        findsNothing,
        reason: '3 晚不畫帶子',
      );
      expect(find.byKey(const Key('bed-week-band-text')), findsNothing);
      expect(
        find.byKey(const Key('bed-week-span-2026-11-13-watch')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('bed-week-span-2026-11-14-button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('bed-week-watch-legend')), findsOneWidget);
      expect(find.byKey(const Key('bed-week-watch-note')), findsOneWidget);
      // 目標是刻度旁的小月亮，不是一條線
      final moon = tester.getRect(find.byKey(const Key('bed-week-target')));
      final firstBar = tester.getRect(
        find.byKey(const Key('bed-week-bar-2026-11-08')),
      );
      expect(
        moon.right,
        lessThanOrEqualTo(firstBar.left),
        reason: '月亮在長條左邊的刻度區',
      );
      expect(find.text('03:00 target'), findsOneWidget);
      // 標題跟外面那張卡一樣
      expect(find.byIcon(Icons.bed_rounded), findsOneWidget);
      expect(find.textContaining('half'), findsNothing, reason: '晚數照實寫');
      // 不判斷規律好壞
      for (final word in [
        'regular',
        'consistent',
        'improved',
        'good',
        'bad',
        'great',
      ]) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('7 晚 → 畫淡色帶，照實寫幾晚落在裡面', (tester) async {
      final w = bedWeek(
        endDate: '2026-11-14',
        buttons: {
          for (final (d, h) in [
            ('08', '01:00'),
            ('09', '02:00'),
            ('10', '03:00'),
            ('11', '03:20'),
            ('12', '03:30'),
            ('13', '04:00'),
            ('14', '05:30'),
          ])
            '2026-11-$d': (t('2026-11-$d $h'), t('2026-11-$d 10:00')),
        },
      );
      await pump(tester, w);
      expect(find.byKey(const Key('bed-week-band')), findsOneWidget);
      expect(find.text('5 of 7 bedtimes fell in 02:00–04:00'), findsOneWidget);
      expect(find.text('03:20 → 10:00'), findsOneWidget);
      expect(
        find.byKey(const Key('bed-week-target')),
        findsNothing,
        reason: '沒給目標就沒有月亮',
      );
    });

    testWidgets('全是按鈕 → 沒有手錶的圖例與說明；一晚都沒有 → 說沒資料', (tester) async {
      await pump(
        tester,
        bedWeek(
          endDate: '2026-11-14',
          buttons: {
            '2026-11-14': (t('2026-11-14 03:20'), t('2026-11-14 09:00')),
          },
        ),
      );
      expect(find.byKey(const Key('bed-week-watch-legend')), findsNothing);
      expect(find.byKey(const Key('bed-week-watch-note')), findsNothing);
      await pump(tester, bedWeek(endDate: '2026-11-14'));
      expect(find.byKey(const Key('bed-week-empty')), findsOneWidget);
    });
  });

  group('/insights 順便帶回按鈕時間', () {
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
            'behavior': {
              'history': [
                {
                  'date': '2026-11-14',
                  'bed_start_at': '2026-11-14T03:20:00',
                  'bed_end_at': '2026-11-14T09:00:00',
                },
                {
                  'date': '2026-11-13',
                  'bed_start_at': null,
                  'bed_end_at': null,
                },
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

    test('沒有攝影機也照樣收下按鈕；兩個都沒按的晚上不收', () async {
      final r = await CameraInsightsService(
        baseUrl: 'http://127.0.0.1:${server.port}',
        identity: const BuildTimeUserIdentity(overrideId: 'stub'),
      ).load();
      expect(r.status, CameraInsightsStatus.ok);
      expect(r.bedButtons.keys, ['2026-11-14']);
      expect(r.bedButtons['2026-11-14']!.$1!.hour, 3, reason: '牆鐘時間，不是 UTC');
    });
  });
}
