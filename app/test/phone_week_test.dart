// 一週放下手機（2026-11-15 使用者定）：一晚一列、橫的時間軸；晚不晚只照抄後端 is_late。
import 'dart:convert';
import 'dart:io';

import 'package:app/services/camera_insights.dart';
import 'package:app/services/night_compare.dart' show kDeltaUp;
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
        '1 of 2 nights over 30m past your 03:00 target',
      );
      expect(phoneLateLine(w, null), isNull);
    });

    test('⚠️ 那句話裡的 30m 跟後端的熬夜門檻是同一個數字', () {
      final py = File('../behavior/adherence.py').readAsStringSync();
      final m = RegExp(
        r'^LATE_THRESHOLD_MINUTES\s*=\s*(\d+)',
        multiLine: true,
      ).firstMatch(py);
      expect(m, isNotNull, reason: 'adherence.py 找不到 LATE_THRESHOLD_MINUTES');
      expect(int.parse(m!.group(1)!), kLateThresholdMinutes);
    });

    test('12:00–18:00 的放下手機不算（10-05 偵測成 14:07）：當作沒資料、不算晚', () {
      final w = phoneWeek(
        endDate: '2026-10-05',
        downs: {
          '2026-10-05': PhoneDown(t('2026-10-05 14:07'), true),
          '2026-10-04': PhoneDown(t('2026-10-04 04:42'), true),
          '2026-10-03': PhoneDown(t('2026-10-03 11:59'), true), // 中午前還算
          '2026-10-02': PhoneDown(t('2026-10-02 18:00'), false), // 18:00 起算
        },
      );
      expect(w.nights.last.down, isNull);
      expect(w.nightsWithData, 3);
      expect(w.lateNights, 2);
      expect(w.judgedNights, 3);
    });

    test('C：這週中間值 vs 前 7 晚中間值，只代表方向；前一週沒資料就沒有', () {
      final w = phoneWeek(
        endDate: '2026-11-14',
        downs: {
          '2026-11-14': PhoneDown(t('2026-11-14 03:30'), null),
          '2026-11-13': PhoneDown(t('2026-11-13 03:00'), null),
          '2026-11-12': PhoneDown(t('2026-11-12 04:00'), null),
          // 前一週（11-01 ~ 11-07）
          '2026-11-07': PhoneDown(t('2026-11-07 02:00'), null),
          '2026-11-06': PhoneDown(t('2026-11-06 03:07'), null),
          '2026-11-05': PhoneDown(t('2026-11-04 23:50'), null),
          // 前一週的白天時刻一樣不算
          '2026-11-04': PhoneDown(t('2026-11-04 14:00'), null),
          // 再更早一天不算進前一週
          '2026-10-31': PhoneDown(t('2026-10-31 09:00'), null),
        },
      );
      expect(clockOf(w.median!), '03:30');
      expect(clockOf(w.previousMedian!), '02:00');
      expect(w.change, 90);
      expect(phoneWeekChangeLine(w), '↑ 1h 30m later than the week before');

      final earlier = phoneWeek(
        endDate: '2026-11-14',
        downs: {
          '2026-11-14': PhoneDown(t('2026-11-14 01:00'), null),
          '2026-11-07': PhoneDown(t('2026-11-07 01:20'), null),
        },
      );
      expect(
        phoneWeekChangeLine(earlier),
        '↓ 20m earlier than the week before',
      );

      final none = phoneWeek(
        endDate: '2026-11-14',
        downs: {'2026-11-14': PhoneDown(t('2026-11-14 01:00'), null)},
      );
      expect(phoneWeekChangeLine(none), isNull);
    });

    test('A：+Nm in bed 照抄後端；沒有就不寫（不寫 0）', () {
      expect(inBedLabel(null), isNull);
      expect(inBedLabel(6.7), '+7m in bed');
      expect(inBedLabel(0.1), '+<1m in bed');
      expect(inBedLabel(158.1), '+2h 38m in bed');
    });

    test('targetFromEvening：格式不對 → null', () {
      expect(clockOf(targetFromEvening('03:00')!), '03:00');
      expect(targetFromEvening('3'), isNull);
      expect(targetFromEvening('25:00'), isNull);
    });
  });

  group('PhoneWeekView', () {
    testWidgets('最上面中間值＋晚幾晚；7 欄；沒資料寫 —；目標一條線', (tester) async {
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
        '2 of 3 nights over 30m past your 03:00 target',
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
        '—',
      );
      expect(find.byKey(const Key('phone-week-dot-2026-11-10')), findsNothing);
      expect(find.byKey(const Key('phone-week-target')), findsOneWidget);
      // 舊的在左、這一晚在最右邊
      final left = tester
          .getTopLeft(find.byKey(const Key('phone-week-col-2026-11-08')))
          .dx;
      final right = tester
          .getTopLeft(find.byKey(const Key('phone-week-col-2026-11-14')))
          .dx;
      expect(right, greaterThan(left));
      // 點的高度照時刻：04:00 在 02:00 下面（上早下晚）
      Rect dotOf(String date) => tester.getRect(
        find.descendant(
          of: find.byKey(Key('phone-week-dot-$date')),
          matching: find.byType(Container),
        ),
      );
      expect(
        dotOf('2026-11-12').center.dy,
        greaterThan(dotOf('2026-11-13').center.dy),
      );
      // 點到目標有一根細棒；目標的時刻寫在刻度上
      expect(
        find.byKey(const Key('phone-week-stick-2026-11-12')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('phone-week-target-label')), findsOneWidget);
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
                      .widget<Container>(
                        find.descendant(
                          of: find.byKey(Key('phone-week-dot-$date')),
                          matching: find.byType(Container),
                        ),
                      )
                      .decoration)
                  as BoxDecoration)
              .color!;
      expect(colorOf('2026-11-12'), colorOf('2026-11-13'));
    });

    testWidgets('A＋C 畫在畫面上：圖底下一排小長條（按 Start Sleep 之後多久）；晚了是紅色', (tester) async {
      final w = phoneWeek(
        endDate: '2026-11-14',
        downs: {
          '2026-11-14': PhoneDown(t('2026-11-14 03:26'), false, 6.7),
          '2026-11-13': PhoneDown(t('2026-11-13 03:03'), false),
          '2026-11-07': PhoneDown(t('2026-11-07 02:00'), null),
        },
      );
      await tester.pumpWidget(
        host(PhoneWeekView(title: 'Phone down', week: w, target: '03:00')),
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('phone-after-value-2026-11-14')))
            .data,
        '7m',
      );
      // 在圖的下面，不在圖上
      expect(
        tester.getRect(find.byKey(const Key('phone-after-bar-2026-11-14'))).top,
        greaterThan(
          tester
              .getRect(find.byKey(const Key('phone-week-dot-2026-11-14')))
              .bottom,
        ),
      );
      // 沒按 Start Sleep 的晚上寫「—」、不畫柱子（不是 0）
      expect(
        tester
            .widget<Text>(find.byKey(const Key('phone-after-value-2026-11-13')))
            .data,
        '—',
      );
      expect(find.byKey(const Key('phone-after-bar-2026-11-13')), findsNothing);
      expect(find.byKey(const Key('phone-after-title')), findsOneWidget);
      // 舊的「+7m」小字拿掉了
      expect(find.textContaining('+7m'), findsNothing);
      final change = tester.widget<Text>(
        find.byKey(const Key('phone-week-change')),
      );
      expect(change.data, startsWith('↑'));
      expect(change.style!.color, kDeltaUp);
      expect(tester.takeException(), isNull);
    });

    testWidgets('沒有任何一晚按了上床 → 不出現那一排小長條', (tester) async {
      final w = phoneWeek(
        endDate: '2026-11-14',
        downs: {'2026-11-14': PhoneDown(t('2026-11-14 03:26'), false)},
      );
      await tester.pumpWidget(
        host(PhoneWeekView(title: 'Phone down', week: w)),
      );
      expect(find.byKey(const Key('phone-after-bars')), findsNothing);
      expect(find.byKey(const Key('phone-week-change')), findsNothing);
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
      expect(find.byKey(const Key('phone-week-col-2026-11-14')), findsNothing);
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
                  'phone_in_bed_minutes': 6.7,
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
      expect(r.phoneDowns['2026-11-14']!.inBedMinutes, 6.7);
      expect(r.phoneDowns['2026-11-13']!.inBedMinutes, isNull);
    });
  });
}
