// 早晨報告（2026-11-12 定案）。
// ⚠️ 守的是「壞掉時不會報錯」的幾件事：
//   - 沒有手錶資料時不得出現任何分數或睡眠長度（畫 0 或上一晚的數字都是編造）
//   - 心情與那句話只照抄後端，而且只在有分數時用
//   - 手機上別晚的按鈕不得被當成這一晚的
//   - Sleep Stages 與夢境只在打包檔最新那一晚就是這一晚時才用
import 'package:app/models/sleep_session.dart';
import 'package:app/screens/home_screen.dart';
import 'package:app/screens/morning_report_screen.dart';
import 'package:app/screens/sleep_mode_screen.dart';
import 'package:app/services/alarm.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/morning_report.dart';
import 'package:app/services/sleep_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime at(int day, int h, [int m = 0]) => DateTime(2026, 11, day, h, m);

/// 有手錶資料的 /home 回應（欄名照 main.py）。
Map<String, dynamic> homeWithScore(String date) => <String, dynamic>{
      'date': date,
      'status': {'pet_mood': 'tired', 'mood_reason': 'final_quality=Poor'},
      'display': {
        'score_color': '#FF8A65',
        'score_message': 'SENTINEL-score-message',
        'mood_description': 'SENTINEL-mood-description',
      },
      'behavior': {
        'bed_start_at': '2026-11-11T23:40:00',
        'bed_end_at': '2026-11-12T07:10:00',
      },
      'metrics': <String, dynamic>{
        'sleep_duration_minutes': 445.0,
        'light_minutes': 265.0,
        'deep_minutes': 60.0,
        'rem_minutes': 120.0,
        'sleep_start_time': '2026-11-11T23:55:00+08:00',
        'wake_time': '2026-11-12T07:00:00+08:00',
      },
      'scoring': <String, dynamic>{
        'final_score': 61.6,
        'final_quality': 'Poor',
        'rem_measured': true,
      },
    };

/// 手錶資料還沒到：只有行為那一層（後端照樣給行為驅動的心情）。
Map<String, dynamic> homeWaiting(String date) => {
      'date': date,
      'status': {'pet_mood': 'happy', 'mood_reason': 'on time'},
      'display': {'mood_description': 'Your buddy slept right on time!'},
      'behavior': {
        'bed_start_at': '2026-11-11T23:40:00',
        'bed_end_at': '2026-11-12T07:10:00',
      },
      'metrics': null,
      'scoring': null,
    };

class _Source implements MorningReportSource {
  final Map<String, dynamic>? json;
  final List<String> asked = [];
  _Source(this.json);
  @override
  Future<Map<String, dynamic>?> fetchNight(String date) async {
    asked.add(date);
    return json;
  }
}

class _Alarm implements AlarmScheduler {
  @override
  Future<void> schedule(DateTime at) async {}
  @override
  Future<void> cancel() async {}
  @override
  Future<bool> canRing() async => true;
  @override
  Future<void> requestPermission() async {}
  @override
  Future<void> openSettings() async {}
}

class _Repo implements SleepRepository {
  final SleepSession session;
  _Repo(this.session);
  @override
  Future<SleepSession> load() async => session;
}

Future<void> settle(WidgetTester tester, [int frames = 10]) async {
  // 小狗一直在動，pumpAndSettle 等不到停
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

String? textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data;

void main() {
  late SleepSession session;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    session = await const AssetSleepRepository().load();
  });

  group('合併規則 buildMorningReport', () {
    final marks = BedMarks(startAt: at(11, 23, 40), endAt: at(12, 7, 10));

    test('只有手機：上床→起床有，分數、心情、睡眠長度一律沒有', () {
      final r = buildMorningReport(date: '2026-11-12', marks: marks);
      expect(r.source, ReportSource.phoneOnly);
      expect(r.bedStart, at(11, 23, 40));
      expect(r.bedEnd, at(12, 7, 10));
      expect(r.hasScore, isFalse);
      expect(r.mood, isNull);
      expect(r.sleepMinutes, isNull);
    });

    test('⚠️ 手機上的按鈕是別晚的 → 不採用', () {
      final r = buildMorningReport(date: '2026-11-08', marks: marks);
      expect(r.bedStart, isNull);
      expect(r.bedEnd, isNull);
    });

    test('有分數：分數、等級、心情、兩句話都照抄後端', () {
      final r = buildMorningReport(
        date: '2026-11-12',
        marks: marks,
        home: homeWithScore('2026-11-12'),
      );
      expect(r.source, ReportSource.backend);
      expect(r.score, 61.6);
      expect(r.quality, 'Poor');
      expect(r.mood, 'tired');
      expect(r.scoreMessage, 'SENTINEL-score-message');
      expect(r.moodDescription, 'SENTINEL-mood-description');
      expect(r.sleepMinutes, 445);
      expect(r.lightMinutes, 265);
      expect(r.hasStageSplit, isTrue);
    });

    test('⚠️ 還沒有分數：後端給了行為心情也不用（使用者定：等資料時畫睡姿）', () {
      final r = buildMorningReport(
        date: '2026-11-12',
        home: homeWaiting('2026-11-12'),
      );
      expect(r.hasScore, isFalse);
      expect(r.mood, isNull);
      expect(r.moodDescription, isNull);
      // 手機上沒有按鈕時，上床→起床改用後端存的那一對
      expect(r.bedStart, at(11, 23, 40));
      expect(r.bedEnd, at(12, 7, 10));
    });

    test('後端回的是別晚（date 對不上）→ 不採用', () {
      final r = buildMorningReport(
        date: '2026-11-12',
        home: homeWithScore('2026-11-10'),
      );
      expect(r.hasScore, isFalse);
    });

    test('連不到後端 → 用打包檔那一晚；只有最新那晚才有夢境', () {
      final latest = session.history.last;
      final r = buildMorningReport(date: latest.date, session: session);
      expect(r.source, ReportSource.bundled);
      expect(r.score, latest.finalScore);
      expect(r.mood, latest.petMood, reason: '心情照抄 history，不從分數推');
      expect(r.dream, session.aiContent.dreamSummary);

      final older = session.history[session.history.length - 2];
      final o = buildMorningReport(date: older.date, session: session);
      expect(o.dream, isNull, reason: '打包檔的夢境只屬於最新那一晚');
      expect(o.stages, isNull);
      expect(o.moodDescription, isNull,
          reason: '打包檔的那句話只屬於最新那一晚，舊夜晚不能借用');
    });

    test('日期標題是英文，不跟手機語言走', () {
      expect(reportDateTitle(DateTime(2026, 11, 13)), 'Friday, Nov 13');
      expect(reportDateTitle(DateTime(2026, 11, 12)), 'Thursday, Nov 12');
    });
  });

  group('報告畫面', () {
    Future<void> pumpReport(WidgetTester tester, MorningReport r,
        {Size size = const Size(1200, 4000)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = size.width > 1100 ? 3.0 : 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: MorningReportScreen(initial: r)),
      );
      await settle(tester);
    }

    testWidgets('⚠️ 等資料：寫 Waiting…，沒有任何分數或睡眠長度，畫睡姿小狗',
        (tester) async {
      await pumpReport(
        tester,
        buildMorningReport(
          date: '2026-11-12',
          marks: BedMarks(startAt: at(11, 23, 40), endAt: at(12, 7, 10)),
        ),
      );
      expect(find.text(kWaitingForWatch), findsOneWidget);
      expect(find.byKey(const Key('report-score')), findsNothing);
      expect(find.byKey(const Key('report-duration')), findsNothing);
      expect(find.byKey(const Key('report-split')), findsNothing);
      expect(find.byKey(const Key('report-pet-asleep')), findsOneWidget);
      expect(textOf(tester, 'report-times'), 'In bed 23:40 – 07:10');
      expect(textOf(tester, 'report-date'), 'Thursday, Nov 12');
      expect(find.textContaining('Great'), findsNothing,
          reason: '不放固定鼓勵句（紅線 5）');
    });

    testWidgets('有分數：分數、等級、長度、比例、那句話，醒著的小狗', (tester) async {
      await pumpReport(
        tester,
        buildMorningReport(
          date: '2026-11-12',
          home: homeWithScore('2026-11-12'),
        ),
      );
      expect(find.text(kWaitingForWatch), findsNothing);
      expect(textOf(tester, 'report-score'), '62');
      expect(textOf(tester, 'report-quality'), 'Poor sleep');
      expect(textOf(tester, 'report-duration'), '7h 25m');
      expect(textOf(tester, 'report-times'), 'In bed 23:40 – 07:10');
      expect(textOf(tester, 'report-split-light'), '60%');
      expect(textOf(tester, 'report-split-deep'), '13%');
      expect(textOf(tester, 'report-split-rem'), '27%');
      expect(find.text('SENTINEL-mood-description'), findsOneWidget);
      expect(find.byKey(const Key('report-pet-awake')), findsOneWidget);
    });

    testWidgets('⚠️ 後端是舊版（沒給淺睡）但 REM 有量到 → 不得寫 not measured',
        (tester) async {
      final json = homeWithScore('2026-11-12');
      (json['metrics'] as Map).remove('light_minutes');
      await pumpReport(
        tester,
        buildMorningReport(date: '2026-11-12', home: json),
      );
      expect(find.byKey(const Key('report-split')), findsNothing);
      expect(textOf(tester, 'report-split-partial'), 'Deep 1h 0m · REM 2h 0m');
    });

    testWidgets('沒量到 REM：不畫比例條，寫 REM not measured', (tester) async {
      final json = homeWithScore('2026-11-12');
      (json['metrics'] as Map)['light_minutes'] = null;
      (json['metrics'] as Map)['rem_minutes'] = null;
      (json['scoring'] as Map)['rem_measured'] = false;
      await pumpReport(
        tester,
        buildMorningReport(date: '2026-11-12', home: json),
      );
      expect(find.byKey(const Key('report-split')), findsNothing);
      expect(textOf(tester, 'report-split-partial'),
          'Deep 1h 0m · REM not measured');
    });

    testWidgets('沒按按鈕：改顯示手錶的 Asleep，不冒充上床時間', (tester) async {
      final json = homeWithScore('2026-11-12');
      json['behavior'] = null;
      await pumpReport(
        tester,
        buildMorningReport(date: '2026-11-12', home: json),
      );
      expect(textOf(tester, 'report-times'), 'Asleep 23:55 – 07:00');
    });

    testWidgets('⚠️ 6.4 吋手機（1080×2340）不溢出', (tester) async {
      await pumpReport(
        tester,
        buildMorningReport(
          date: session.history.last.date,
          home: homeWithScore(session.history.last.date),
          session: session,
        ),
        size: const Size(1080, 2340),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('入口', () {
    Future<BedMarkStore> pumpHome(
      WidgetTester tester,
      DateTime now,
      _Source source, {
      Future<void> Function(BedMarkStore)? before,
    }) async {
      tester.view.physicalSize = const Size(1200, 4200);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final store = BedMarkStore(InMemoryKeyValueStore());
      if (before != null) await before(store);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeScreen(
              repository: _Repo(session),
              bedMarks: store,
              alarmScheduler: _Alarm(),
              morningReport: source,
              clock: () => now,
            ),
          ),
        ),
      );
      await settle(tester);
      return store;
    }

    testWidgets('滑完 Slide to get up → 立刻出現昨晚的報告', (tester) async {
      final source = _Source(homeWaiting('2026-11-12'));
      await pumpHome(tester, at(12, 7, 10), source,
          before: (s) => s.markStart(at(11, 23, 40)));
      expect(find.byType(SleepModeScreen), findsOneWidget);
      await tester.drag(
          find.byKey(const Key('slide-knob')), const Offset(1000, 0));
      await settle(tester, 15);
      expect(find.byType(MorningReportScreen), findsOneWidget);
      expect(source.asked, ['2026-11-12'], reason: '問的是起床日那一晚');
      expect(find.text(kWaitingForWatch), findsOneWidget);
      expect(textOf(tester, 'report-times'), 'In bed 23:40 – 07:10');
      await tester.tap(find.byKey(const Key('report-done')));
      await settle(tester);
      expect(find.byType(MorningReportScreen), findsNothing);
    });

    testWidgets('⚠️ 按 Cancel 不出現報告', (tester) async {
      final source = _Source(null);
      await pumpHome(tester, at(12, 1), source,
          before: (s) => s.markStart(at(11, 23, 40)));
      await tester.tap(find.byKey(const Key('sleep-cancel')));
      await settle(tester);
      final yes = find.widgetWithText(TextButton, 'Yes, cancel');
      if (yes.evaluate().isNotEmpty) {
        await tester.tap(yes);
      } else {
        // 確認鈕的字可能不同：點對話框裡最後一顆按鈕
        await tester.tap(find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextButton)).last);
      }
      await settle(tester, 15);
      expect(find.byType(SleepModeScreen), findsNothing);
      expect(find.byType(MorningReportScreen), findsNothing);
      expect(source.asked, isEmpty);
    });

    testWidgets('一週心情列點最新那天 → 打開那一晚的報告', (tester) async {
      final latest = session.history.last;
      final source = _Source(homeWithScore(latest.date));
      await pumpHome(tester, at(12, 15), source);
      final day = DateTime.parse(latest.date).day;
      await tester.ensureVisible(find.byKey(Key('week-day-$day')));
      await tester.tap(find.byKey(Key('week-day-$day')));
      await settle(tester, 15);
      expect(find.byType(MorningReportScreen), findsOneWidget);
      expect(source.asked, [latest.date]);
      expect(textOf(tester, 'report-score'), '62');
    });
  });
}
