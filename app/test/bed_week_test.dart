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
    });

    test('偶數晚的中間值＝中間兩晚的平均；一個特別早的晚上拉不走中間值', () {
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
      expect(
        clockOf(withStarts(['01:00', '02:00', '03:00', '04:00']).medianStart!),
        '02:30',
      );
      // 其他晚都 03:00 左右、一晚 21:00（前一天晚上）→ 仍是 03:20
      final w = bedWeek(
        endDate: '2026-11-14',
        buttons: {
          '2026-11-08': (t('2026-11-07 21:00'), t('2026-11-08 05:00')),
          for (final (d, h) in [
            ('09', '03:00'),
            ('10', '03:20'),
            ('11', '03:30'),
            ('12', '03:10'),
          ])
            '2026-11-$d': (t('2026-11-$d $h'), t('2026-11-$d 09:00')),
        },
      );
      expect(clockOf(w.medianStart!), '03:10');
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
    Future<void> pump(WidgetTester tester, BedWeek w) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BedWeekView(title: 'Time in bed', week: w),
            ),
          ),
        ),
      );
    }

    final threeNights = bedWeek(
      endDate: '2026-11-14',
      buttons: {
        '2026-11-14': (t('2026-11-14 03:20'), t('2026-11-14 09:00')),
        '2026-11-12': (t('2026-11-12 02:20'), t('2026-11-12 08:00')),
      },
      watch: {'2026-11-13': (t('2026-11-13 02:50'), t('2026-11-13 09:30'))},
    );

    testWidgets('數字在最上面、圖在下面；圖上兩條虛線就是那兩個數字', (tester) async {
      await pump(tester, threeNights);
      expect(find.text('02:50 → 09:00'), findsOneWidget, reason: '上床、起床各自的中間值');
      expect(find.text('Average 6h in bed · 3 of 7 nights'), findsOneWidget);
      // 數字在圖的上面
      final usual = tester.getRect(find.byKey(const Key('bed-week-usual')));
      final bar = tester.getRect(
        find.byKey(const Key('bed-week-bar-2026-11-14')),
      );
      expect(usual.bottom, lessThan(bar.top));
      // 兩條線的字跟上面的數字一樣
      String tag(String k) => tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(Key('bed-week-median-$k-label')),
              matching: find.byType(Text),
            ),
          )
          .map((x) => x.data)
          .join(' ');
      expect(tag('bed'), '02:50');
      expect(tag('wake'), '09:00');
      // 時刻在圖裡、線的左端；刻度照常全部顯示
      final firstBar = tester.getRect(
        find.byKey(const Key('bed-week-bar-2026-11-08')),
      );
      expect(
        tester.getRect(find.byKey(const Key('bed-week-median-bed-label'))).left,
        greaterThanOrEqualTo(firstBar.left - 8),
      );
      expect(find.text('08:00'), findsWidgets, reason: '刻度不讓位');
      // 起床那條在上床那條下面（上早下晚）
      final bedLine = tester.getRect(
        find.byKey(const Key('bed-week-median-bed')),
      );
      final wakeLine = tester.getRect(
        find.byKey(const Key('bed-week-median-wake')),
      );
      expect(wakeLine.top, greaterThan(bedLine.top));
      // 手錶的晚上空心，一行小字說明
      expect(
        find.byKey(const Key('bed-week-span-2026-11-13-watch')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('bed-week-span-2026-11-14-button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('bed-week-watch-note')), findsOneWidget);
      // 標題跟外面那張卡一樣
      expect(find.byIcon(Icons.bed_rounded), findsOneWidget);
      // 簡化過：沒有淡色帶、月亮、目標
      expect(find.textContaining('target'), findsNothing);
      expect(find.byIcon(Icons.nightlight_round), findsNothing);
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

    testWidgets('不到 3 晚 → 不畫虛線，數字照樣寫', (tester) async {
      await pump(
        tester,
        bedWeek(
          endDate: '2026-11-14',
          buttons: {
            '2026-11-14': (t('2026-11-14 03:20'), t('2026-11-14 09:00')),
            '2026-11-13': (t('2026-11-13 02:20'), t('2026-11-13 08:00')),
          },
        ),
      );
      expect(find.byKey(const Key('bed-week-median-bed')), findsNothing);
      expect(find.byKey(const Key('bed-week-median-wake')), findsNothing);
      expect(find.byKey(const Key('bed-week-usual')), findsOneWidget);
    });

    testWidgets('全是按鈕 → 沒有空心的說明；一晚都沒有 → 說沒資料', (tester) async {
      await pump(
        tester,
        bedWeek(
          endDate: '2026-11-14',
          buttons: {
            '2026-11-14': (t('2026-11-14 03:20'), t('2026-11-14 09:00')),
          },
        ),
      );
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
