// 2026-11-15 使用者定（grill）：三種每晚的資料放進早晨報告的點開頁，外面的格子不動。
// - Time in bed：躺多久才睡著（按 Start Sleep → 手錶認定睡著）。負數那晚不畫、不寫
// - Phone down：按 Start Sleep 之後又滑多久，圖底下一排小長條。沒按寫「—」不是 0
// - Awake：醒了幾次。0 次寫「×0」、沒資料寫「—」
// 都不判斷好壞、不跟文獻切點比。
import 'package:app/services/night_compare.dart' show NightValue;
import 'package:app/widgets/awake_week_sheet.dart';
import 'package:app/widgets/bed_week_sheet.dart';
import 'package:app/widgets/phone_week_sheet.dart';
import 'package:app/widgets/sleep_week_sheet.dart' show sleepWeek;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime t(String s) => DateTime.parse(s);

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 380, height: 1000, child: child)),
);

String textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  group('Time in bed：躺多久才睡著', () {
    test('按鈕的晚上：Start Sleep 到手錶入睡幾分鐘', () {
      final s = BedSpan(
        t('2026-11-14 03:20'),
        t('2026-11-14 09:00'),
        BedSource.button,
        t('2026-11-14 03:38'),
      );
      expect(s.latencyMinutes, 18);
    });

    test('⚠️ 手錶在按鈕之前就睡著（負數）→ null，不寫成 0', () {
      final s = BedSpan(
        t('2026-11-14 03:20'),
        t('2026-11-14 09:00'),
        BedSource.button,
        t('2026-11-14 03:05'),
      );
      expect(s.latencyMinutes, isNull);
      expect(bedLatencyLine(s.latencyMinutes), isNull);
    });

    test('手錶的晚上、沒有入睡時刻、入睡晚於下床 → null', () {
      expect(
        BedSpan(
          t('2026-11-14 03:38'),
          t('2026-11-14 09:51'),
          BedSource.watch,
          t('2026-11-14 03:38'),
        ).latencyMinutes,
        isNull,
      );
      expect(
        BedSpan(
          t('2026-11-14 03:20'),
          t('2026-11-14 09:00'),
          BedSource.button,
        ).latencyMinutes,
        isNull,
      );
      expect(
        BedSpan(
          t('2026-11-14 03:20'),
          t('2026-11-14 09:00'),
          BedSource.button,
          t('2026-11-14 09:30'),
        ).latencyMinutes,
        isNull,
      );
    });

    test('⚠️ 手錶時刻是 UTC 標記的牆鐘、按鈕是本地時間 → 照牆鐘比，不差 8 小時', () {
      final s = BedSpan(
        DateTime(2026, 11, 14, 3, 20, 14),
        DateTime(2026, 11, 14, 9, 0, 13),
        BedSource.button,
        DateTime.utc(2026, 11, 14, 3, 33),
      );
      expect(s.latencyMinutes, 12);
    });

    test('那一句：0 寫 right after，其餘寫幾分鐘', () {
      expect(bedLatencyLine(null), isNull);
      expect(bedLatencyLine(0), 'Fell asleep right after Start Sleep');
      expect(bedLatencyLine(18), 'Fell asleep 18m after Start Sleep');
      expect(bedLatencyLine(75), 'Fell asleep 1h 15m after Start Sleep');
    });

    test('bedWeek 把手錶的入睡帶給按鈕的晚上（當下按、事後補都一樣算）', () {
      final w = bedWeek(
        endDate: '2026-11-14',
        buttons: {'2026-11-14': (t('2026-11-14 03:20'), t('2026-11-14 09:00'))},
        watch: {'2026-11-14': (t('2026-11-14 03:38'), t('2026-11-14 09:51'))},
      );
      expect(w.nights.last.span!.latencyMinutes, 18);
    });

    testWidgets('畫面：最上面 This night 那一句；膠囊上半段畫淡', (tester) async {
      final w = bedWeek(
        endDate: '2026-11-14',
        buttons: {
          '2026-11-14': (t('2026-11-14 03:20'), t('2026-11-14 09:00')),
          '2026-11-13': (t('2026-11-13 02:00'), t('2026-11-13 08:00')),
        },
        watch: {
          '2026-11-14': (t('2026-11-14 03:38'), t('2026-11-14 09:51')),
          // 手錶比按鈕早睡著（負數）：那晚不畫淡色段
          '2026-11-13': (t('2026-11-13 01:50'), t('2026-11-13 08:00')),
        },
      );
      await tester.pumpWidget(host(BedWeekView(title: 'Time in bed', week: w)));
      expect(
        textOf(tester, 'bed-latency'),
        'Fell asleep 18m after Start Sleep',
      );
      expect(
        textOf(tester, 'bed-last-night-times'),
        'Start Sleep 03:20  →  asleep 03:38',
      );
      final light = tester.getSize(
        find.byKey(const Key('bed-week-latency-2026-11-14')),
      );
      final whole = tester.getSize(
        find.byKey(const Key('bed-week-span-2026-11-14-button')),
      );
      // 18 分 ÷ 340 分（03:20→09:00）
      expect(light.height / whole.height, closeTo(18 / 340, 0.02));
      // 淡色段要撐滿膠囊的寬度（寬 0 的話畫面上只剩一條白線）
      expect(light.width, whole.width);
      expect(
        find.byKey(const Key('bed-week-latency-2026-11-13')),
        findsNothing,
      );
      expect(find.byKey(const Key('bed-week-latency-note')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('⚠️ 這一晚是負數 → 最上面那塊不出現；也不寫 30 分鐘切點', (tester) async {
      final w = bedWeek(
        endDate: '2026-11-14',
        buttons: {'2026-11-14': (t('2026-11-14 03:20'), t('2026-11-14 09:00'))},
        watch: {'2026-11-14': (t('2026-11-14 03:00'), t('2026-11-14 09:51'))},
      );
      await tester.pumpWidget(host(BedWeekView(title: 'Time in bed', week: w)));
      expect(find.byKey(const Key('bed-last-night')), findsNothing);
      expect(find.byKey(const Key('bed-week-latency-note')), findsNothing);
      expect(find.textContaining('30m'), findsNothing);
    });
  });

  group('Phone down：按 Start Sleep 之後又滑多久', () {
    test('數字：沒按（null）、負數 → null；0 是 0m；不到 1 分鐘 <1m', () {
      expect(afterStartValue(null), isNull);
      expect(afterStartValue(-3), isNull);
      expect(afterStartValue(0), '0m');
      expect(afterStartValue(0.4), '<1m');
      expect(afterStartValue(6.7), '7m');
      expect(afterStartValue(95), '1h 35m');
    });

    testWidgets('這一排自己的刻度：滑得久的柱子比較高；沒按寫「—」、0 有柱子', (tester) async {
      final w = phoneWeek(
        endDate: '2026-11-14',
        downs: {
          '2026-11-14': PhoneDown(t('2026-11-14 03:26'), false, 30),
          '2026-11-13': PhoneDown(t('2026-11-13 03:03'), false, 6),
          '2026-11-12': PhoneDown(t('2026-11-12 02:50'), false, 0),
          '2026-11-11': PhoneDown(t('2026-11-11 02:40'), false),
        },
      );
      await tester.pumpWidget(
        host(PhoneWeekView(title: 'Phone down', week: w, target: '03:00')),
      );
      double h(String d) =>
          tester.getSize(find.byKey(Key('phone-after-bar-$d'))).height;
      expect(h('2026-11-14'), greaterThan(h('2026-11-13') * 4));
      expect(textOf(tester, 'phone-after-value-2026-11-12'), '0m');
      expect(
        find.byKey(const Key('phone-after-bar-2026-11-12')),
        findsOneWidget,
      );
      expect(textOf(tester, 'phone-after-value-2026-11-11'), '—');
      expect(find.byKey(const Key('phone-after-bar-2026-11-11')), findsNothing);
      // 一個顏色：每根柱子同一個色相（只有這一晚比較亮）
      final colors = {
        for (final d in ['2026-11-13', '2026-11-12'])
          ((tester
                          .widget<Container>(
                            find.byKey(Key('phone-after-bar-$d')),
                          )
                          .decoration!
                      as BoxDecoration)
                  .color!)
              .withValues(alpha: 1),
      };
      expect(colors.length, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('Awake：醒了幾次', () {
    test('那一句與「×N」', () {
      expect(awakeCountLine(null, 38), isNull);
      expect(awakeCountLine(3, 38), 'Woke up 3 times · 38m in total');
      expect(awakeCountLine(1, 4), 'Woke up 1 time · 4m in total');
      expect(awakeCountLine(0, 0), 'Woke up 0 times · 0m in total');
      expect(awakeCountMark(3), '×3');
      expect(awakeCountMark(0), '×0');
      expect(awakeCountMark(null), '—');
    });

    testWidgets('畫面：最上面那句；每根長條底下 ×N，0 寫 ×0、沒資料寫 —', (tester) async {
      final week = sleepWeek([
        const NightValue('2026-11-14', 38),
        const NightValue('2026-11-13', 0),
        const NightValue('2026-11-12', 12),
      ], '2026-11-14');
      await tester.pumpWidget(
        host(
          AwakeView(
            title: 'Awake',
            totalMinutes: 38,
            count: 3,
            counts: const {'2026-11-14': 3, '2026-11-13': 0},
            week: week,
          ),
        ),
      );
      expect(
        textOf(tester, 'awake-count-line'),
        'Woke up 3 times · 38m in total',
      );
      expect(textOf(tester, 'awake-week-times-2026-11-14'), '×3');
      expect(textOf(tester, 'awake-week-times-2026-11-13'), '×0');
      // 有分鐘、沒有次數（Health Connect 的晚上）→ —，不是 ×0
      expect(textOf(tester, 'awake-week-times-2026-11-12'), '—');
      // ×N 在長條下面、星期上面
      expect(
        tester
            .getRect(find.byKey(const Key('awake-week-times-2026-11-14')))
            .top,
        greaterThan(
          tester
              .getRect(find.byKey(const Key('awake-week-fill-2026-11-14')))
              .bottom,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
