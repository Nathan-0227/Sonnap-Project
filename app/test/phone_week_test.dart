// 一週放下手機（2026-11-15 使用者定）：一晚一列、橫的時間軸；晚不晚只照抄後端 is_late。
import 'dart:convert';
import 'dart:io';

import 'package:app/services/camera_insights.dart';
import 'package:app/services/user_identity.dart';
import 'package:app/widgets/bed_week_sheet.dart' show clockOf;
import 'package:app/widgets/phone_week_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime t(String s) => DateTime.parse(s);

Widget host(Widget child) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(child: SizedBox(width: 380, child: child)),
  ),
);

void main() {
  group('phoneWeek()', () {
    test('固定 7 晚、舊的在前；沒資料的晚上是 null', () {
      final w = phoneWeek(
        endDate: '2026-11-14',
        downs: {'2026-11-14': PhoneDown(t('2026-11-14 03:10'), true)},
      );
      expect(w.nights.length, 7);
      expect(w.nights.first.date, '2026-11-08');
      expect(w.nights.last.down, isNotNull);
      expect(w.nightsWithData, 1);
    });

    test('⚠️ 跨午夜的中間值：23:40、01:10、02:30 → 01:10（不是中午）', () {
      final w = phoneWeek(
        endDate: '2026-11-14',
        downs: {
          '2026-11-12': PhoneDown(t('2026-11-11 23:40'), false),
          '2026-11-13': PhoneDown(t('2026-11-13 01:10'), false),
          '2026-11-14': PhoneDown(t('2026-11-14 02:30'), true),
        },
      );
      expect(clockOf(w.median!), '01:10');
    });

    test('晚不晚只數後端的 is_late；後端沒判的晚上不進分母', () {
      final w = phoneWeek(
        endDate: '2026-11-14',
        downs: {
          '2026-11-12': PhoneDown(t('2026-11-12 04:00'), true),
          '2026-11-13': PhoneDown(t('2026-11-13 02:00'), false),
          // 時刻比目標晚很多，但後端沒判 → 不算（Dart 不自己比）
          '2026-11-14': PhoneDown(t('2026-11-14 05:00'), null),
        },
      );
      expect(w.lateNights, 1);
      expect(w.judgedNights, 2);
      expect(
        phoneLateLine(w, '03:00'),
        '1 of 2 nights later than your 03:00 target',
      );
      expect(phoneLateLine(w, null), isNull);
    });

    test('targetFromEvening：格式不對 → null', () {
      expect(clockOf(targetFromEvening('03:00')!), '03:00');
      expect(targetFromEvening('3'), isNull);
      expect(targetFromEvening('25:00'), isNull);
    });
  });

  group('PhoneWeekView', () {
    testWidgets('最上面中間值＋晚幾晚；一晚一列；沒資料寫 no data；目標一條線', (tester) async {
      final w = phoneWeek(
        endDate: '2026-11-14',
        downs: {
          '2026-11-12': PhoneDown(t('2026-11-12 04:00'), true),
          '2026-11-13': PhoneDown(t('2026-11-13 02:00'), false),
          '2026-11-14': PhoneDown(t('2026-11-14 03:41'), true),
        },
      );
      await tester.pumpWidget(
        host(PhoneWeekView(title: 'Phone down', week: w, target: '03:00')),
      );
      expect(find.text('Phone down'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('phone-week-usual'))).data,
        '03:41',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('phone-week-late'))).data,
        '2 of 3 nights later than your 03:00 target',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('phone-week-time-2026-11-14')))
            .data,
        '03:41',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('phone-week-time-2026-11-10')))
            .data,
        '— no data',
      );
      expect(find.byKey(const Key('phone-week-dot-2026-11-10')), findsNothing);
      expect(find.byKey(const Key('phone-week-target')), findsOneWidget);
      // 舊的在上、這一晚在最下面
      final top = tester
          .getTopLeft(find.byKey(const Key('phone-week-row-2026-11-08')))
          .dy;
      final bottom = tester
          .getTopLeft(find.byKey(const Key('phone-week-row-2026-11-14')))
          .dy;
      expect(bottom, greaterThan(top));
      // 點的位置照時刻：04:00 在 02:00 右邊
      final x4 = tester
          .getCenter(find.byKey(const Key('phone-week-dot-2026-11-12')))
          .dx;
      final x2 = tester
          .getCenter(find.byKey(const Key('phone-week-dot-2026-11-13')))
          .dx;
      expect(x4, greaterThan(x2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('⚠️ 點都是同一個顏色（不分紅綠，好壞只有後端判斷）', (tester) async {
      final w = phoneWeek(
        endDate: '2026-11-14',
        downs: {
          '2026-11-12': PhoneDown(t('2026-11-12 04:00'), true),
          '2026-11-13': PhoneDown(t('2026-11-13 02:00'), false),
        },
      );
      await tester.pumpWidget(
        host(PhoneWeekView(title: 'Phone down', week: w)),
      );
      Color colorOf(String date) =>
          ((tester
                      .widget<DecoratedBox>(
                        find.descendant(
                          of: find.byKey(Key('phone-week-dot-$date')),
                          matching: find.byType(DecoratedBox),
                        ),
                      )
                      .decoration)
                  as BoxDecoration)
              .color!;
      expect(colorOf('2026-11-12'), colorOf('2026-11-13'));
    });

    testWidgets('一晚都沒有 → 寫沒有資料，不畫圖', (tester) async {
      await tester.pumpWidget(
        host(
          PhoneWeekView(
            title: 'Phone down',
            week: phoneWeek(endDate: '2026-11-14'),
          ),
        ),
      );
      expect(find.byKey(const Key('phone-week-empty')), findsOneWidget);
      expect(find.byKey(const Key('phone-week-row-2026-11-14')), findsNothing);
    });

    testWidgets('沒有目標 → 不畫線、不寫晚幾晚', (tester) async {
      final w = phoneWeek(
        endDate: '2026-11-14',
        downs: {'2026-11-14': PhoneDown(t('2026-11-14 03:41'), true)},
      );
      await tester.pumpWidget(
        host(PhoneWeekView(title: 'Phone down', week: w)),
      );
      expect(find.byKey(const Key('phone-week-target')), findsNothing);
      expect(find.byKey(const Key('phone-week-late')), findsNothing);
    });
  });

  group('/insights 順便帶回放下手機的時刻', () {
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
                  'lights_out_at': '2026-11-14T03:41:00',
                  'is_late': true,
                },
                {
                  'date': '2026-11-13',
                  'lights_out_at': '2026-11-13T02:00:00',
                  'is_late': null,
                },
                {'date': '2026-11-12', 'lights_out_at': null, 'is_late': null},
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

    test('照抄 is_late；沒有時刻的晚上不收；牆鐘時間不是 UTC', () async {
      final r = await CameraInsightsService(
        baseUrl: 'http://127.0.0.1:${server.port}',
        identity: const BuildTimeUserIdentity(overrideId: 'stub'),
      ).load();
      expect(r.phoneDowns.keys.toSet(), {'2026-11-14', '2026-11-13'});
      expect(r.phoneDowns['2026-11-14']!.isLate, isTrue);
      expect(r.phoneDowns['2026-11-13']!.isLate, isNull);
      expect(r.phoneDowns['2026-11-14']!.at.hour, 3);
    });
  });
}
