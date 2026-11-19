// Insights W/M/Y 畫面（widgets/insights_period_view.dart）。
//   1. 大字是中位數、沒資料寫「—」不寫 0
//   2. 箭頭只代表方向：上升紅、下降綠（分數也一樣）
//   3. 熬夜照抄後端 is_late
//   4. 星星照後端切點；舊版後端沒切點就不畫星星
//   5. 沒有後端：Month／Year 照實說，不拿 30 晚冒充
//   6. 攝影機那格不放常模（不出現 11 / hour 這種文獻數字）
import 'package:app/services/camera_insights.dart';
import 'package:app/services/insights_periods.dart';
import 'package:app/theme/report_style.dart';
import 'package:app/widgets/insights_period_view.dart';
import 'package:app/widgets/phone_week_sheet.dart' show PhoneDown;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final wed = DateTime(2026, 11, 18);
  final today = DateTime(2026, 11, 19);

  const bands = [QualityBand(80, 'Good'), QualityBand(65, 'Normal'),
    QualityBand(50, 'Poor'), QualityBand(0, 'Bad')];

  PeriodSeries series({List<QualityBand> qualityBands = bands}) => PeriodSeries(
        score: const {'2026-11-10': 70, '2026-11-16': 82, '2026-11-17': 84, '2026-11-18': 80},
        mood: const {'2026-11-16': 'happy', '2026-11-17': 'tired'},
        sleep: const {'2026-11-10': 400, '2026-11-16': 380, '2026-11-17': 420, '2026-11-18': 400},
        phoneDowns: {
          '2026-11-16': PhoneDown(DateTime(2026, 11, 16, 3, 40), true),
          '2026-11-17': PhoneDown(DateTime(2026, 11, 17, 2, 50), false),
        },
        cameraPerHour: const {'2026-11-17': 18},
        qualityBands: qualityBands,
      );

  Future<void> pump(WidgetTester tester, Widget w) async {
    tester.view.physicalSize = const Size(1200, 4800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
    await tester.pump();
  }

  Text textIn(WidgetTester tester, Key tile, Pattern p) => tester.widget<Text>(find.descendant(
        of: find.byKey(tile),
        matching: find.byWidgetPredicate((w) => w is Text && (w.data ?? '').contains(p)),
      ));

  testWidgets('Week：中位數、方向箭頭、熬夜照抄、星星照切點', (tester) async {
    await pump(tester, InsightsPeriodView(
        series: series(), period: InsightsPeriod.week, anchor: wed, today: today));

    expect(find.descendant(of: find.byKey(const Key('period-tile-sleep')), matching: find.text('6h 40m')),
        findsOneWidget, reason: '380/420/400 的中位數 400 分');
    // 上一週只有 11-10 的 400 → 這週 400 一樣 → 不畫箭頭
    expect(find.descendant(of: find.byKey(const Key('period-tile-sleep')),
        matching: find.textContaining('↑')), findsNothing);

    // 分數 82 vs 上週 70：上升 → 紅（分數也不例外）
    final up = textIn(tester, const Key('period-mood-card'), '↑');
    expect(up.style?.color, ReportColors.up);
    expect(find.byKey(const Key('period-stars')), findsOneWidget);
    expect(find.text('★★★★ '), findsOneWidget, reason: '中位 82 → Good → 4 顆');

    expect(find.descendant(of: find.byKey(const Key('period-tile-phone')),
        matching: find.text('1 of 2 nights late')), findsOneWidget);

    // 沒資料的格子寫 —，不寫 0
    expect(find.descendant(of: find.byKey(const Key('period-tile-steps')), matching: find.text('—')),
        findsOneWidget);
    expect(find.byKey(const Key('period-mood-week')), findsOneWidget);
  });

  testWidgets('舊版後端沒有切點 → 不畫星星（Dart 不自己訂）', (tester) async {
    await pump(tester, InsightsPeriodView(
        series: series(qualityBands: const []), period: InsightsPeriod.week,
        anchor: wed, today: today));
    expect(find.byKey(const Key('period-stars')), findsNothing);
  });

  testWidgets('攝影機只寫一小時幾次與 not part of your score，不放常模', (tester) async {
    await pump(tester, InsightsPeriodView(
        series: series(), period: InsightsPeriod.week, anchor: wed, today: today));
    final cam = find.byKey(const Key('period-tile-camera'));
    expect(find.descendant(of: cam, matching: find.text('18 moves / hour')), findsOneWidget);
    expect(find.descendant(of: cam, matching: find.textContaining('not part of your score')),
        findsOneWidget);
    expect(find.descendant(of: cam, matching: find.textContaining('11')), findsNothing);
  });

  testWidgets('Month 是月曆、Year 是熱圖', (tester) async {
    await pump(tester, InsightsPeriodView(
        series: series(), period: InsightsPeriod.month, anchor: wed, today: today));
    expect(find.byKey(const Key('period-mood-month')), findsOneWidget);
    await pump(tester, InsightsPeriodView(
        series: series(), period: InsightsPeriod.year, anchor: wed, today: today));
    expect(find.byKey(const Key('period-mood-year')), findsOneWidget);
  });

  testWidgets('沒有後端：Month／Year 照實說，Week 照畫', (tester) async {
    for (final p in [InsightsPeriod.month, InsightsPeriod.year]) {
      await pump(tester, InsightsPeriodView(
          series: series(), period: p, anchor: wed, today: today, online: false));
      expect(find.byKey(const Key('insights-needs-backend')), findsOneWidget);
    }
    await pump(tester, InsightsPeriodView(
        series: series(), period: InsightsPeriod.week, anchor: wed, today: today, online: false));
    expect(find.byKey(const Key('insights-needs-backend')), findsNothing);
  });
}
