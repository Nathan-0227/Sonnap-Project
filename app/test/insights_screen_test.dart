// Insights 改版（2026-11-19 grill 定案）：頂端 Day／Week／Month／Year，Day＝早晨報告本體。
//
// 守的都是壞掉時不會報錯的地方：
//   1. 期間的切法（日曆週從週一起、月底往前翻夾到最後一天、不翻到未來）
//   2. Day 用的是早晨報告的嵌入模式：沒有經驗條、沒有 Back to home／關閉鈕
//   3. 🔴 Insights 絕不觸發 AI：notes 一律 generate=false
//   4. ⚠️ 舊頁（負責上傳）停在 Day 時也要一直掛著
import 'package:app/models/sleep_session.dart';
import 'package:app/screens/insights_screen.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/morning_rating.dart';
import 'package:app/services/morning_report.dart';
import 'package:app/services/report_loader.dart';
import 'package:app/services/sleep_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ImmediateRepository implements SleepRepository {
  final SleepSession session;
  const _ImmediateRepository(this.session);

  @override
  Future<SleepSession> load() async => session;
}

class _FakeReportSource implements MorningReportSource {
  final List<bool> summaryGenerate = [];
  final List<String> nights = [];

  @override
  Future<Map<String, dynamic>?> fetchNight(String date) async {
    nights.add(date);
    return null;
  }

  @override
  Future<Map<String, dynamic>?> fetchSummary(String date,
      {bool generate = true}) async {
    summaryGenerate.add(generate);
    return null;
  }
}

/// 假的舊頁：記錄有沒有被建起來（真的舊頁 initState 會開始偵測與上傳）。
class _Legacy extends StatefulWidget {
  final List<String> log;
  const _Legacy(this.log);

  @override
  State<_Legacy> createState() => _LegacyState();
}

class _LegacyState extends State<_Legacy> {
  @override
  void initState() {
    super.initState();
    widget.log.add('init');
  }

  @override
  void dispose() {
    widget.log.add('dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('legacy-insights');
}

void main() {
  group('期間的切法', () {
    test('Week 是週一到週日的日曆週', () {
      // 2026-11-18 是星期三
      final r = insightsRange(InsightsPeriod.week, DateTime(2026, 11, 18));
      expect(r.start, DateTime(2026, 11, 16));
      expect(r.end, DateTime(2026, 11, 22));
      // 星期日也算在同一週（不是下一週的開始）
      expect(insightsRange(InsightsPeriod.week, DateTime(2026, 11, 22)).start,
          DateTime(2026, 11, 16));
    });

    test('Month、Year 是日曆月、日曆年', () {
      final m = insightsRange(InsightsPeriod.month, DateTime(2026, 2, 10));
      expect(m.start, DateTime(2026, 2, 1));
      expect(m.end, DateTime(2026, 2, 28));
      final y = insightsRange(InsightsPeriod.year, DateTime(2026, 7, 4));
      expect(y.start, DateTime(2026, 1, 1));
      expect(y.end, DateTime(2026, 12, 31));
    });

    test('月底往前翻一個月夾到那個月的最後一天，不會跳過二月', () {
      expect(insightsShift(InsightsPeriod.month, DateTime(2026, 3, 31), -1),
          DateTime(2026, 2, 28));
    });

    test('跨月的週寫兩個月份', () {
      expect(insightsLabel(InsightsPeriod.week, DateTime(2026, 12, 2)),
          'Nov 30 – Dec 6');
      expect(insightsLabel(InsightsPeriod.week, DateTime(2026, 11, 18)),
          'Nov 16 – 22');
      expect(insightsLabel(InsightsPeriod.day, DateTime(2026, 11, 18)),
          'Wed, Nov 18');
      expect(insightsLabel(InsightsPeriod.month, DateTime(2026, 11, 18)),
          'November 2026');
    });

    test('右箭頭到本期為止，左箭頭到第一筆資料那一期為止', () {
      final today = DateTime(2026, 11, 19);
      expect(insightsCanGoNext(InsightsPeriod.day, today, today), isFalse);
      expect(insightsCanGoNext(InsightsPeriod.day, DateTime(2026, 11, 18), today),
          isTrue);
      expect(insightsCanGoNext(InsightsPeriod.week, DateTime(2026, 11, 17), today),
          isFalse, reason: '同一週還沒過完，不能翻到下一週');
      final first = DateTime(2026, 8, 28);
      expect(insightsCanGoPrev(InsightsPeriod.month, DateTime(2026, 8, 30), first),
          isFalse);
      expect(insightsCanGoPrev(InsightsPeriod.month, DateTime(2026, 9, 1), first),
          isTrue);
      expect(insightsCanGoPrev(InsightsPeriod.day, today, null), isTrue,
          reason: '還不知道第一筆在哪時不擋');
    });
  });

  test('🔴 allowGenerate: false 時，就算報告要求生成也送 false', () async {
    final source = _FakeReportSource();
    final store = BedMarkStore(InMemoryKeyValueStore());
    final loader = ReportLoader(
      clock: () => DateTime(2026, 11, 19),
      bedMarks: store,
      ratings: MorningRatingStore(store.store),
      session: () async => throw StateError('unused'),
      goalMinutes: () async => 480,
      morningReport: source,
    );
    // 報告有分數時會呼叫 summary(generate: true)——畫面測試裡那一晚沒分數，測不到這條
    await loader.notesLoader('2026-11-18', allowGenerate: false)!(generate: true);
    await loader.notesLoader('2026-11-18', allowGenerate: true)!(generate: true);
    expect(source.summaryGenerate, [false, true]);
  });

  group('畫面', () {
    late SleepSession sample;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      sample = await const AssetSleepRepository().load();
    });

    Future<({_FakeReportSource source, List<String> legacyLog})> pump(
        WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final source = _FakeReportSource();
      final log = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: InsightsScreen(
          legacy: _Legacy(log),
          repository: _ImmediateRepository(sample),
          bedMarks: BedMarkStore(InMemoryKeyValueStore()),
          morningReport: source,
          goalMinutes: () async => 480,
          clock: () => DateTime(2026, 11, 19, 10),
        ),
      ));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      return (source: source, legacyLog: log);
    }

    testWidgets('四個分頁，預設 Day＝今天那一晚', (tester) async {
      await pump(tester);
      for (final p in ['day', 'week', 'month', 'year']) {
        expect(find.byKey(Key('insights-tab-$p')), findsOneWidget);
      }
      expect(find.text('Thu, Nov 19'), findsOneWidget);
      expect(find.byKey(const Key('report-list')), findsOneWidget,
          reason: 'Day 就是早晨報告本體');
    });

    testWidgets('Day 是嵌入模式：沒有經驗條、Back to home、關閉鈕', (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('report-xp')), findsNothing);
      expect(find.byKey(const Key('report-done')), findsNothing);
      expect(find.byKey(const Key('report-close')), findsNothing);
      expect(find.byKey(const Key('report-insights')), findsNothing);
    });

    testWidgets('🔴 notes 一律 generate=false（Insights 絕不觸發 AI）', (tester) async {
      final r = await pump(tester);
      expect(r.source.summaryGenerate, isNotEmpty,
          reason: '要真的問過 notes，下面那條才有意義');
      expect(r.source.summaryGenerate, everyElement(isFalse));
    });

    testWidgets('換日期 → 問那一晚', (tester) async {
      final r = await pump(tester);
      await tester.tap(find.byKey(const Key('insights-prev')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Wed, Nov 18'), findsOneWidget);
      expect(r.source.nights, contains('2026-11-18'));
      expect(r.source.summaryGenerate, everyElement(isFalse));
    });

    testWidgets('不能翻到未來', (tester) async {
      await pump(tester);
      final next = tester.widget<IconButton>(find.byKey(const Key('insights-next')));
      expect(next.onPressed, isNull);
    });

    testWidgets('⚠️ 停在 Day 時舊頁也掛著，切分頁不會重建', (tester) async {
      final r = await pump(tester);
      expect(r.legacyLog, ['init'], reason: '舊頁負責偵測就寢與上傳，不能等點到 Week 才開始');
      await tester.tap(find.byKey(const Key('insights-tab-week')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('insights-tab-day')));
      await tester.pump();
      expect(r.legacyLog, ['init'], reason: '切來切去不能讓上傳重跑');
    });
  });
}
