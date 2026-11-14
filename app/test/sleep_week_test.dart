// 一週睡眠圖（2026-11-14 使用者定）：這一晚往回 7 晚、沒資料的晚上跳過、目標虛線不變色。
import 'package:app/services/night_compare.dart';
import 'package:app/widgets/sleep_week_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sleepWeek()', () {
    test('這一晚往回共 7 個日曆晚上，跨月也對', () {
      final w = sleepWeek(const [], '2026-12-02');
      expect(w.nights.map((n) => n.date).toList(), [
        '2026-11-26',
        '2026-11-27',
        '2026-11-28',
        '2026-11-29',
        '2026-11-30',
        '2026-12-01',
        '2026-12-02',
      ]);
    });

    test('⚠️ 沒資料的晚上跳過：平均只算有資料的，不當成 0', () {
      final w = sleepWeek(const [
        NightValue('2026-11-10', 300),
        NightValue('2026-11-12', 420),
        NightValue('2026-11-14', 360),
        NightValue('2026-11-01', 999), // 一週以外的不算
        NightValue('2026-11-15', 999), // 這一晚之後的不算
      ], '2026-11-14');
      expect(w.nightsWithData, 3);
      expect(w.averageMinutes, 360);
      expect(w.nights.where((n) => n.minutes == null).length, 4);
      expect(sleepWeekCountLine(w), '3 of 7 nights with data');
    });

    test('一晚都沒有 → 平均是 null（不寫 0）', () {
      final w = sleepWeek(const [NightValue('2026-10-01', 400)], '2026-11-14');
      expect(w.averageMinutes, isNull);
      expect(w.nightsWithData, 0);
    });

    test('七晚都有 → 寫 all 7 nights', () {
      final w = sleepWeek([
        for (var d = 8; d <= 14; d++)
          NightValue('2026-11-${d.toString().padLeft(2, '0')}', 400),
      ], '2026-11-14');
      expect(sleepWeekCountLine(w), 'all 7 nights');
    });
  });

  group('畫面', () {
    Future<void> pump(WidgetTester tester, SleepWeek w, {int? goal}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: const Color(0xFF1B2350),
            body: SleepWeekView(
              title: 'Time asleep',
              week: w,
              goalMinutes: goal,
            ),
          ),
        ),
      );
    }

    testWidgets('平均、幾晚、目標虛線；沒資料的那晚寫「—」', (tester) async {
      final w = sleepWeek(const [
        NightValue('2026-11-12', 300),
        NightValue('2026-11-14', 420),
      ], '2026-11-14');
      await pump(tester, w, goal: 480);
      expect(
        tester.widget<Text>(find.byKey(const Key('sleep-week-average'))).data,
        '6h',
      );
      expect(find.text('2 of 7 nights with data'), findsOneWidget);
      expect(find.byKey(const Key('sleep-week-goal')), findsOneWidget);
      expect(find.text('8h goal'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('⚠️ 長條不依達標變色：達標與沒達標的晚上同一個顏色', (tester) async {
      final w = sleepWeek(const [
        NightValue('2026-11-12', 300), // 沒達標
        NightValue('2026-11-13', 540), // 達標
        NightValue('2026-11-14', 420),
      ], '2026-11-14');
      await pump(tester, w, goal: 480);
      Color colorOf(String date) {
        final box = tester.widget<Container>(
          find
              .descendant(
                of: find.byKey(Key('sleep-week-bar-$date')),
                matching: find.byWidgetPredicate(
                  (wd) => wd is Container && wd.decoration is BoxDecoration,
                ),
              )
              .first,
        );
        return (box.decoration as BoxDecoration).color!;
      }

      expect(colorOf('2026-11-12'), colorOf('2026-11-13'));
      for (final word in ['reached', 'Great', 'short', 'below']) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
    });

    testWidgets('沒有目標 → 不畫虛線；一晚都沒有 → 說沒資料，不寫 0', (tester) async {
      await pump(tester, sleepWeek(const [], '2026-11-14'));
      expect(find.byKey(const Key('sleep-week-goal')), findsNothing);
      expect(find.byKey(const Key('sleep-week-average')), findsNothing);
      expect(find.byKey(const Key('sleep-week-empty')), findsOneWidget);
      expect(find.textContaining('0m'), findsNothing);
    });
  });
}
