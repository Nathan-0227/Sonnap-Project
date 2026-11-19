// Insights PR 3：W/M/Y 的格子點開的詳細頁（widgets/period_detail_sheet.dart）。
//   1. 開在同一個期間；頁裡切 D/W/M/Y、‹ › 翻期間（不翻到未來、不翻到第一筆之前）
//   2. 切到 Day 停在那段期間最後一個有資料的晚上，跟「上一個有資料的晚上」比
//   3. 沒資料寫「—」不寫 0；方向箭頭上升紅、下降綠（分數也一樣）
//   4. 沒有後端：Month／Year 照實說，不拿 30 晚冒充
//   5. 分數頁不呈現組成、攝影機頁不放常模
import 'package:app/services/camera_insights.dart';
import 'package:app/services/insights_periods.dart';
import 'package:app/theme/report_style.dart';
import 'package:app/widgets/insights_period_view.dart';
import 'package:app/widgets/period_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final wed = DateTime(2026, 11, 18);
  final today = DateTime(2026, 11, 19);

  const bands = [
    QualityBand(80, 'Good'),
    QualityBand(65, 'Normal'),
    QualityBand(50, 'Poor'),
    QualityBand(0, 'Bad'),
  ];

  const series = PeriodSeries(
    score: {'2026-11-10': 70, '2026-11-16': 82, '2026-11-17': 84, '2026-11-18': 80},
    mood: {'2026-11-16': 'happy', '2026-11-17': 'tired'},
    sleep: {
      '2026-10-20': 300,
      '2026-11-10': 400,
      '2026-11-16': 380,
      '2026-11-17': 420,
      '2026-11-18': 400,
    },
    cameraPerHour: {'2026-11-17': 18},
    qualityBands: bands,
  );

  Future<void> pumpView(WidgetTester tester,
      {InsightsPeriod period = InsightsPeriod.week, bool online = true}) async {
    tester.view.physicalSize = const Size(1200, 4800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InsightsPeriodView(
          series: series,
          period: period,
          anchor: wed,
          today: today,
          online: online,
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> open(WidgetTester tester, String tile) async {
    await tester.tap(find.byKey(Key(tile)));
    await settle(tester);
  }

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  testWidgets('點 Week 的格子 → 詳細頁開在同一週', (tester) async {
    await pumpView(tester);
    await open(tester, 'period-tile-sleep');
    expect(find.byKey(const Key('period-detail-sleep')), findsOneWidget);
    expect(text(tester, 'period-detail-label'), 'Nov 16 – 22');
    expect(text(tester, 'period-detail-big'), '6h 40m', reason: '380/420/400 的中位數');
    expect(text(tester, 'period-detail-count'), contains('3 of 4 nights'),
        reason: '分母只算到今天，未來的日子不算「沒資料」');
  });

  testWidgets('點 Month 的格子 → 開在同一個月；頁裡切 Year、Day', (tester) async {
    await pumpView(tester, period: InsightsPeriod.month);
    await open(tester, 'period-tile-sleep');
    expect(text(tester, 'period-detail-label'), 'November 2026');

    await tester.tap(find.byKey(const Key('period-detail-tab-year')));
    await tester.pump();
    expect(text(tester, 'period-detail-label'), '2026');

    await tester.tap(find.byKey(const Key('period-detail-tab-day')));
    await tester.pump();
    expect(text(tester, 'period-detail-label'), 'Wed, Nov 18',
        reason: '停在最後一個有資料的晚上，不是今天（今天那晚還沒有資料）');
    expect(text(tester, 'period-detail-big'), '6h 40m');
    // 上一個有資料的晚上 11-17 是 420 → 少 20 分 → 下降綠
    final delta = tester.widget<Text>(find.byKey(const Key('period-detail-delta')));
    expect(delta.data, '↓ 20m');
    expect(delta.style?.color, ReportColors.down);
  });

  testWidgets('分數上升也是紅（只代表方向）；分數頁不呈現組成', (tester) async {
    await pumpView(tester);
    await open(tester, 'period-mood-card');
    expect(find.byKey(const Key('period-detail-score')), findsOneWidget);
    final delta = tester.widget<Text>(find.byKey(const Key('period-detail-delta')));
    expect(delta.data, '↑ 12', reason: '82 vs 上週 70');
    expect(delta.style?.color, ReportColors.up);
    expect(text(tester, 'period-detail-note'), 'Usually Good');
    for (final w in ['Duration', 'WASO', 'weight', 'composition', 'caveat']) {
      expect(find.textContaining(w, findRichText: true), findsNothing,
          reason: '11-19 使用者定：分數詳細頁不呈現組成、不放警語');
    }
  });

  testWidgets('不能翻到未來；翻到第一筆資料那一期就停', (tester) async {
    await pumpView(tester);
    await open(tester, 'period-tile-sleep');
    IconButton btn(String k) => tester.widget<IconButton>(find.byKey(Key(k)));
    expect(btn('period-detail-next').onPressed, isNull);

    await tester.tap(find.byKey(const Key('period-detail-tab-month')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('period-detail-prev')));
    await tester.pump();
    expect(text(tester, 'period-detail-label'), 'October 2026');
    expect(btn('period-detail-prev').onPressed, isNull,
        reason: '第一筆在 10-20（sleep 那一項）');
    expect(btn('period-detail-next').onPressed, isNotNull);
  });

  testWidgets('沒資料的一期寫「—」不寫 0', (tester) async {
    await pumpView(tester);
    await open(tester, 'period-tile-awake');
    expect(text(tester, 'period-detail-big'), '—');
    expect(find.byKey(const Key('period-detail-delta')), findsNothing);
    expect(find.text('0m'), findsNothing);
  });

  testWidgets('點長條 → 寫那一天的數字；沒資料的那天寫 no data', (tester) async {
    await pumpView(tester);
    await open(tester, 'period-tile-sleep');
    await tester.tap(find.byKey(const Key('period-detail-bar-1')));
    await tester.pump();
    expect(text(tester, 'period-detail-readout'), 'Tue, Nov 17 · 7h');
    await tester.tap(find.byKey(const Key('period-detail-bar-0')));
    await tester.pump();
    expect(text(tester, 'period-detail-readout'), 'Mon, Nov 16 · 6h 20m');
    // 11-19（週四）是今天、還沒資料
    await tester.tap(find.byKey(const Key('period-detail-bar-3')));
    await tester.pump();
    expect(text(tester, 'period-detail-readout'), 'Thu, Nov 19 · no data');
  });

  testWidgets('攝影機頁不放常模、照寫不進分數', (tester) async {
    await pumpView(tester);
    await open(tester, 'period-tile-camera');
    expect(text(tester, 'period-detail-big'), '18 moves / hour');
    expect(text(tester, 'period-detail-note'), 'Not part of your score');
    expect(find.textContaining('11'), findsNothing,
        reason: 'Montini 11 次／小時不得並列');
  });

  testWidgets('沒有後端：頁裡切到 Month 照實說要後端', (tester) async {
    await pumpView(tester, online: false);
    await open(tester, 'period-tile-sleep');
    await tester.tap(find.byKey(const Key('period-detail-tab-month')));
    await tester.pump();
    expect(find.byKey(const Key('period-detail-needs-backend')), findsOneWidget);
    expect(find.byKey(const Key('period-detail-big')), findsNothing);
  });

  group('純函式', () {
    test('切到 Day：期間裡最後一個有資料的日子，不晚於今天', () {
      const v = {'2026-11-16': 1.0, '2026-11-18': 2.0};
      expect(dayAnchorFor(v, InsightsPeriod.week, wed, today), DateTime(2026, 11, 18));
      expect(dayAnchorFor(const {}, InsightsPeriod.week, wed, today), DateTime(2026, 11, 19),
          reason: '都沒有就停在今天（這週還沒過完）');
      expect(dayAnchorFor(const {}, InsightsPeriod.month, DateTime(2026, 10, 3), today),
          DateTime(2026, 10, 31));
    });

    test('上一個有資料的晚上：跳過空的日子、不拿自己或之後的', () {
      const v = {'2026-11-10': 1.0, '2026-11-18': 3.0, '2026-11-20': 4.0};
      expect(previousWithData(v, '2026-11-18'), 1.0);
      expect(previousWithData(v, '2026-11-10'), isNull);
    });

    test('每一個格子都有對應的詳細頁', () {
      for (final id in ['score', 'sleep', 'bed', 'phone', 'awake', 'eff', 'hr',
        'phases', 'camera', 'steps', 'kcal', 'active', 'stress']) {
        expect(PeriodMetric.byId(id).id, id);
      }
    });
  });
}
