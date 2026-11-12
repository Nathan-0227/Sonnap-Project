// 早晨報告（2026-11-12 定案；11-13 依示意圖重做）。
// ⚠️ 守的是「壞掉時不會報錯」的幾件事：
//   - 沒有手錶資料時不得出現任何分數或睡眠長度（畫 0 或上一晚的數字都是編造）
//   - 心情、那句話、AI 那段、小建議、效率警語只照抄後端
//   - 跟上一晚比只代表方向（上升紅、下降綠），不判斷好壞
//   - 沒有後端回應時不得出現任何達成度措辭
//   - 手機上別晚的按鈕不得被當成這一晚的
//   - 起床自評在報告之前出現，Skip 不擋報告
import 'package:app/models/sleep_session.dart';
import 'package:app/screens/home_screen.dart';
import 'package:app/screens/morning_report_screen.dart';
import 'package:app/screens/rested_screen.dart';
import 'package:app/screens/sleep_mode_screen.dart';
import 'package:app/services/alarm.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/camera_insights.dart';
import 'package:app/services/game_service.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/morning_rating.dart';
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
      'behavior': <String, dynamic>{
        'target_bedtime': '23:30',
        'lights_out_at': '2026-11-11T23:42:00',
        'adherence_minutes': 12.0,
        'bed_start_at': '2026-11-11T23:40:00',
        'bed_end_at': '2026-11-12T07:10:00',
        'time_in_bed_minutes': 450.0,
        'measured_efficiency': 98.9,
        'measured_efficiency_basis': 'SENTINEL-basis-measured',
        'watch_wake_efficiency': 97.0,
        'watch_wake_efficiency_basis': 'SENTINEL-basis-watch-wake',
      },
      'metrics': <String, dynamic>{
        'sleep_duration_minutes': 445.0,
        'light_minutes': 265.0,
        'deep_minutes': 60.0,
        'rem_minutes': 120.0,
        'waso_minutes': 14.0,
        'avg_heart_rate': 56.4,
        'resting_heart_rate': 51.0,
        'sleep_efficiency': 99.5,
        'sleep_start_time': '2026-11-11T23:55:00+08:00',
        'wake_time': '2026-11-12T07:00:00+08:00',
      },
      'scoring': <String, dynamic>{
        'final_score': 61.6,
        'final_quality': 'Poor',
        'rem_measured': true,
        'composition': <String, dynamic>{
          'efficiency_basis': 'SENTINEL-basis-measured',
          'caveats': [
            {'component': 'deep', 'caveat': 'deep caveat'},
            {'component': 'efficiency', 'caveat': 'SENTINEL-eff-caveat'},
          ],
        },
      },
      'previous_night': <String, dynamic>{
        'time_in_bed_minutes': 400.0,
        'sleep_duration_minutes': 500.0,
      },
      'morning_rating': null,
    };

/// 手錶資料還沒到：只有行為那一層（後端照樣給行為驅動的心情）。
Map<String, dynamic> homeWaiting(String date) => {
      'date': date,
      'status': {'pet_mood': 'happy', 'mood_reason': 'on time'},
      'display': {'mood_description': 'Your buddy slept right on time!'},
      'behavior': {
        'target_bedtime': '23:30',
        'lights_out_at': '2026-11-11T23:31:00',
        'adherence_minutes': 1.0,
        'bed_start_at': '2026-11-11T23:40:00',
        'bed_end_at': '2026-11-12T07:10:00',
        'time_in_bed_minutes': 450.0,
      },
      'metrics': null,
      'scoring': null,
    };

Map<String, dynamic> summaryOk(String date, {String kind = 'tip'}) => {
      'date': date,
      'status': 'ok',
      'text': 'SENTINEL-summary',
      'source': 'llm',
      'tip': {'id': 'T1', 'kind': kind, 'text': 'SENTINEL-tip'},
    };

class _Source implements MorningReportSource {
  final Map<String, dynamic>? json;
  final Map<String, dynamic>? summary;
  final List<String> asked = [];
  final List<String> askedSummary = [];
  _Source(this.json, {this.summary});
  @override
  Future<Map<String, dynamic>?> fetchNight(String date) async {
    asked.add(date);
    return json;
  }

  @override
  Future<Map<String, dynamic>?> fetchSummary(String date) async {
    askedSummary.add(date);
    return summary;
  }
}

class _Sender implements RestedSender {
  final List<MorningRating> sent = [];
  @override
  Future<RestedSendResult> send(MorningRating rating) async {
    sent.add(rating);
    return RestedSendResult.sent;
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

bool hasText(WidgetTester tester, Finder under, String text) => find
    .descendant(of: under, matching: find.text(text))
    .evaluate()
    .isNotEmpty;

void main() {
  late SleepSession session;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    session = await const AssetSleepRepository().load();
  });

  group('合併規則 buildMorningReport', () {
    final marks = BedMarks(startAt: at(11, 23, 40), endAt: at(12, 7, 10));

    test('只有手機：上床→起床與臥床時間有，分數、心情、睡眠長度一律沒有', () {
      final r = buildMorningReport(date: '2026-11-12', marks: marks);
      expect(r.source, ReportSource.phoneOnly);
      expect(r.bedStart, at(11, 23, 40));
      expect(r.bedEnd, at(12, 7, 10));
      expect(r.timeInBedMinutes, 450);
      expect(r.hasScore, isFalse);
      expect(r.mood, isNull);
      expect(r.sleepMinutes, isNull);
      expect(r.lightsOutAt, isNull);
      expect(r.adherenceMinutes, isNull);
    });

    test('⚠️ 手機上的按鈕是別晚的 → 不採用', () {
      final r = buildMorningReport(date: '2026-11-08', marks: marks);
      expect(r.bedStart, isNull);
      expect(r.bedEnd, isNull);
      expect(r.timeInBedMinutes, isNull);
    });

    test('有分數：分數、等級、心情、兩句話、More details 都照抄後端', () {
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
      expect(r.wasoMinutes, 14);
      expect(r.avgHeartRate, 56.4);
      expect(r.restingHeartRate, 51);
      expect(r.efficiencyCaveat, 'SENTINEL-eff-caveat',
          reason: '只拿 efficiency 那一條，不拿別項的警語');
    });

    test('⚠️ 效率：拿「進分數的那一個」，依 basis 對上，不寫死 basis 字串', () {
      final measured = buildMorningReport(
          date: '2026-11-12', home: homeWithScore('2026-11-12'));
      expect(measured.efficiency, 98.9);
      expect(measured.efficiencyBasis, 'SENTINEL-basis-measured');

      final json = homeWithScore('2026-11-12');
      ((json['scoring'] as Map)['composition'] as Map)['efficiency_basis'] =
          'SENTINEL-basis-watch-wake';
      expect(buildMorningReport(date: '2026-11-12', home: json).efficiency, 97);

      // 三段式的 ③：behavior 兩個都對不上 → 手錶自己的
      ((json['scoring'] as Map)['composition'] as Map)['efficiency_basis'] =
          'watch_only';
      expect(buildMorningReport(date: '2026-11-12', home: json).efficiency,
          99.5);

      // 那晚效率沒進分數 → 不顯示任何效率
      ((json['scoring'] as Map)['composition'] as Map)['efficiency_basis'] = null;
      expect(buildMorningReport(date: '2026-11-12', home: json).efficiency,
          isNull);
    });

    test('跟上一晚比：照抄後端給的上一晚原始數字，方向只看大小', () {
      final r = buildMorningReport(
          date: '2026-11-12', home: homeWithScore('2026-11-12'));
      expect(changeOf(r.timeInBedMinutes, r.previousTimeInBed),
          ChangeDirection.up);
      expect(changeOf(r.sleepMinutes, r.previousSleepMinutes),
          ChangeDirection.down);
      expect(changeOf(445, 445.4), ChangeDirection.same);
      expect(changeOf(445, null), isNull, reason: '沒有上一晚就不比');
    });

    test('⚠️ 還沒有分數：後端給了行為心情也不用（使用者定：等資料時畫睡姿）', () {
      final r = buildMorningReport(
        date: '2026-11-12',
        home: homeWaiting('2026-11-12'),
      );
      expect(r.hasScore, isFalse);
      expect(r.mood, isNull);
      expect(r.moodDescription, isNull);
      expect(r.wasoMinutes, isNull);
      expect(r.efficiency, isNull);
      // 手機上沒有按鈕時，上床→起床改用後端存的那一對
      expect(r.bedStart, at(11, 23, 40));
      expect(r.bedEnd, at(12, 7, 10));
      // 行為那層不必等手錶
      expect(r.lightsOutAt, at(11, 23, 31));
      expect(r.adherenceMinutes, 1);
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

    test('Sleep phases：後端每一晚都給，舊的晚上也畫得出曲線', () {
      final json = homeWithScore('2026-11-05');
      (json['metrics'] as Map)['sleep_stages'] = {
        'segments': [
          {
            'stage': 'light',
            'start': '2026-11-04T23:55:00+08:00',
            'end': '2026-11-05T01:00:00+08:00',
          },
          {
            'stage': 'deep',
            'start': '2026-11-05T01:00:00+08:00',
            'end': '2026-11-05T02:00:00+08:00',
          },
        ],
        'minutes': {'awake': 14, 'rem': 120, 'light': 265, 'deep': 60},
        'rem_measured': true,
      };
      final r = buildMorningReport(date: '2026-11-05', home: json);
      expect(r.stages, isNotNull);
      expect(r.stages!.segments, hasLength(2));
    });

    test('⚠️ 自評：後端的優先，後端沒有才用手機上存的；別晚的不用', () {
      const local = MorningRating(date: '2026-11-12', rested: 2);
      final json = homeWithScore('2026-11-12');
      json['morning_rating'] = {
        'rested': 4,
        'label': 'SENTINEL-rested-label',
        'tags': [],
      };
      final fromBackend = buildMorningReport(date: '2026-11-12', home: json)
          .withExtras(localRating: local);
      expect(fromBackend.rating!.rested, 4);
      expect(fromBackend.ratingLabel, 'SENTINEL-rested-label');

      final fromPhone = buildMorningReport(
              date: '2026-11-12', home: homeWithScore('2026-11-12'))
          .withExtras(localRating: local);
      expect(fromPhone.rating!.rested, 2);
      expect(fromPhone.ratingLabel, 'Slightly rested');

      final otherNight = buildMorningReport(date: '2026-11-13')
          .withExtras(localRating: local);
      expect(otherNight.rating, isNull);
    });

    test('⚠️ /night-summary：只收 status ok 而且是同一晚的', () {
      final base = buildMorningReport(
          date: '2026-11-12', home: homeWithScore('2026-11-12'));
      final ok = base.withSummary(summaryOk('2026-11-12'));
      expect(ok.summaryText, 'SENTINEL-summary');
      expect(ok.tip!.text, 'SENTINEL-tip');
      expect(ok.tip!.isNote, isFalse);
      expect(base.withSummary(summaryOk('2026-11-11')).summaryText, isNull);
      expect(
        base.withSummary({
          'date': '2026-11-12',
          'status': 'waiting',
          'text': null,
          'tip': null,
        }).summaryText,
        isNull,
      );
      expect(base.withSummary(null).summaryText, isNull);
      // 之後再接 extras 不會把 AI 那段弄丟
      expect(ok.withExtras(goalMinutes: 480).summaryText, 'SENTINEL-summary');
    });

    test('達成度那一行只照抄後端的分鐘數', () {
      expect(adherenceLine(null), isNull);
      expect(adherenceLine(-5), 'On time');
      expect(adherenceLine(0), 'On time');
      expect(adherenceLine(132), '2h 12m after your target');
    });

    test('日期標題是英文，不跟手機語言走', () {
      expect(reportDateTitle(DateTime(2026, 11, 13)), 'Friday, Nov 13');
      expect(reportDateTitle(DateTime(2026, 11, 12)), 'Thursday, Nov 12');
    });
  });

  group('報告畫面', () {
    Future<NavigatorObserver> pumpReport(WidgetTester tester, MorningReport r,
        {Size size = const Size(1200, 5000),
        bool pending = true,
        bool canOpenInsights = false}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = size.width > 1100 ? 3.0 : 2.625;
      addTearDown(tester.view.reset);
      final observer = NavigatorObserver();
      await tester.pumpWidget(
        // 同一條測試畫兩次時，key 不同才不會沿用上一次的狀態
        MaterialApp(
          navigatorObservers: [observer],
          home: MorningReportScreen(
            key: ObjectKey(r),
            initial: r,
            pending: pending,
            canOpenInsights: canOpenInsights,
          ),
        ),
      );
      await settle(tester);
      return observer;
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
      expect(textOf(tester, 'report-duration'), '—',
          reason: 'Time asleep 那格只能是破折號，不能畫 0 或上一晚的');
      expect(find.byKey(const Key('report-duration-change-up')), findsNothing);
      expect(find.byKey(const Key('report-duration-change-down')), findsNothing);
      expect(find.byKey(const Key('report-split')), findsNothing);
      expect(find.byKey(const Key('report-buddy')), findsNothing);
      expect(find.byKey(const Key('report-pet-asleep')), findsOneWidget);
      expect(textOf(tester, 'report-in-bed-value'), '7h 30m');
      expect(textOf(tester, 'report-times'), '23:40 → 07:10');
      expect(find.byKey(const Key('report-goal-line')), findsNothing,
          reason: '沒分數時不放睡眠目標');
      expect(find.byKey(const Key('report-waiting-hint')), findsOneWidget);
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
      expect(textOf(tester, 'report-quality'), 'Poor · SENTINEL-score-message');
      expect(textOf(tester, 'report-duration'), '7h 25m');
      expect(textOf(tester, 'report-in-bed-value'), '7h 30m');
      expect(textOf(tester, 'report-times'), '23:40 → 07:10');
      expect(textOf(tester, 'report-split-light'), '60%');
      expect(textOf(tester, 'report-split-deep'), '13%');
      expect(textOf(tester, 'report-split-rem'), '27%');
      expect(find.text('SENTINEL-mood-description'), findsOneWidget);
      expect(find.byKey(const Key('report-pet-awake')), findsOneWidget);
      expect(find.byKey(const Key('report-waiting-hint')), findsNothing);
    });

    testWidgets('⚠️ 跟上一晚比：上升紅、下降綠，只畫方向', (tester) async {
      await pumpReport(
        tester,
        buildMorningReport(
            date: '2026-11-12', home: homeWithScore('2026-11-12')),
      );
      // 臥床 450 > 上一晚 400 → 上；睡眠 445 < 上一晚 500 → 下
      final up = find.byKey(const Key('report-in-bed-change-up'));
      final down = find.byKey(const Key('report-duration-change-down'));
      expect(up, findsOneWidget);
      expect(down, findsOneWidget);
      Color colorOf(Finder f) =>
          tester.widget<Icon>(find.descendant(of: f, matching: find.byType(Icon))).color!;
      expect(colorOf(up), const Color(0xFFFF7B7B), reason: '上升是紅');
      expect(colorOf(down), const Color(0xFF4FE0A0), reason: '下降是綠');
      expect(find.textContaining('better'), findsNothing);
      expect(find.textContaining('worse'), findsNothing);
    });

    testWidgets('沒有上一晚 → 不畫箭頭', (tester) async {
      final json = homeWithScore('2026-11-12');
      json['previous_night'] = {
        'time_in_bed_minutes': null,
        'sleep_duration_minutes': null,
      };
      await pumpReport(tester, buildMorningReport(date: '2026-11-12', home: json));
      expect(find.byKey(const Key('report-in-bed-change-up')), findsNothing);
      expect(find.byKey(const Key('report-duration-change-down')), findsNothing);
    });

    testWidgets('From your buddy：AI 那段與小建議逐字照抄；note 用不同圖示',
        (tester) async {
      final base = buildMorningReport(
          date: '2026-11-12', home: homeWithScore('2026-11-12'));
      await pumpReport(tester, base.withSummary(summaryOk('2026-11-12')));
      expect(textOf(tester, 'report-summary'), 'SENTINEL-summary');
      expect(find.text('SENTINEL-tip'), findsOneWidget);
      expect(find.byKey(const Key('report-tip-tip')), findsOneWidget);

      await pumpReport(
          tester, base.withSummary(summaryOk('2026-11-12', kind: 'note')));
      expect(find.byKey(const Key('report-tip-note')), findsOneWidget);
      expect(find.byKey(const Key('report-tip-tip')), findsNothing);
    });

    testWidgets('⚠️ 放下手機：有後端時照抄達成度；沒有後端時不出現任何達成度措辭',
        (tester) async {
      final json = homeWithScore('2026-11-12');
      (json['behavior'] as Map)['adherence_minutes'] = 132.0;
      await pumpReport(tester, buildMorningReport(date: '2026-11-12', home: json));
      expect(textOf(tester, 'report-phone-down-at'), '23:42');
      expect(textOf(tester, 'report-target'), '23:30');
      expect(textOf(tester, 'report-adherence'), '2h 12m after your target');

      await pumpReport(
        tester,
        buildMorningReport(
          date: '2026-11-12',
          marks: BedMarks(startAt: at(11, 23, 40), endAt: at(12, 7, 10)),
        ),
      );
      expect(find.byKey(const Key('report-phone-down')), findsNothing);
      expect(find.textContaining('after your target'), findsNothing);
      expect(find.text('On time'), findsNothing);
    });

    testWidgets('More details 預設收著；打開後照抄 WASO、心率、效率＋警語＋basis、攝影機',
        (tester) async {
      const camera = CameraNight(
        date: '2026-11-12',
        usualLabel: 'SENTINEL-camera-usual',
        usualSupported: true,
      );
      await pumpReport(
        tester,
        buildMorningReport(date: '2026-11-12', home: homeWithScore('2026-11-12'))
            .withExtras(camera: camera),
      );
      expect(find.byKey(const Key('report-waso')), findsNothing,
          reason: '使用者定：收成 More details，點了才展開');
      await tester.ensureVisible(find.byKey(const Key('report-details-toggle')));
      await tester.tap(find.byKey(const Key('report-details-toggle')));
      await settle(tester);
      expect(textOf(tester, 'report-waso'), '14m');
      expect(textOf(tester, 'report-hr'), '56 bpm avg · 51 resting');
      expect(textOf(tester, 'report-efficiency'), '98.9%',
          reason: '照抄，不四捨五入掉小數');
      expect(find.text('SENTINEL-eff-caveat'), findsOneWidget);
      expect(find.text('Basis: SENTINEL-basis-measured'), findsOneWidget,
          reason: 'App 裡有好幾個「效率」，只有 basis 分得開');
      expect(textOf(tester, 'report-camera'), 'SENTINEL-camera-usual');
      expect(find.text('Camera data is not part of your score.'), findsOneWidget);
    });

    testWidgets('別晚的攝影機不放進這一晚', (tester) async {
      const camera = CameraNight(
        date: '2026-11-11',
        usualLabel: 'SENTINEL-camera-usual',
        usualSupported: true,
      );
      final r = buildMorningReport(date: '2026-11-12', home: homeWithScore('2026-11-12'))
          .withExtras(camera: camera);
      expect(r.camera, isNull);
    });

    testWidgets('自評小標籤：照抄後端的字', (tester) async {
      final json = homeWithScore('2026-11-12');
      json['morning_rating'] = {
        'rested': 4,
        'label': 'SENTINEL-rested-label',
        'tags': [],
      };
      await pumpReport(tester, buildMorningReport(date: '2026-11-12', home: json));
      expect(textOf(tester, 'report-rating-label'), 'SENTINEL-rested-label');
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
      expect(textOf(tester, 'report-split-partial'), 'Deep 1h · REM 2h');
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
          'Deep 1h · REM not measured');
    });

    testWidgets('沒按按鈕：臥床時間寫破折號，不拿手錶的入睡冒充上床', (tester) async {
      final json = homeWithScore('2026-11-12');
      json['behavior'] = null;
      await pumpReport(
        tester,
        buildMorningReport(date: '2026-11-12', home: json),
      );
      expect(textOf(tester, 'report-in-bed-value'), '—');
      expect(textOf(tester, 'report-times'), 'No bedtime recorded');
      expect(find.text('23:55 → 07:00'), findsNothing);
    });

    GameState game(List<Map<String, dynamic>> nights) => GameState.fromJson({
          'level': 6,
          'xp_total': 2000,
          'xp_into_level': 830,
          'xp_for_next': 389,
          'progress': 830 / 1219,
          'recent_nights': nights,
        });

    testWidgets('等級與 XP 條照抄 /game；+N XP 是那一晚的數字', (tester) async {
      await pumpReport(
        tester,
        buildMorningReport(date: '2026-11-12', home: homeWithScore('2026-11-12'))
            .withExtras(game: game([
          {'date': '2026-11-11', 'total': 50, 'final_quality': 'Good'},
          {'date': '2026-11-12', 'behaviour_xp': 30, 'quality_xp': 0,
           'total': 30, 'final_quality': 'Poor'},
        ])),
      );
      expect(textOf(tester, 'report-level'), 'Lv6');
      expect(textOf(tester, 'report-xp-text'), '830 / 1,219 XP');
      expect(textOf(tester, 'report-xp-to-next'), '389 to Lv7');
      final pill = find.byKey(const Key('report-night-xp'));
      expect(hasText(tester, pill, '+30 XP'), isTrue,
          reason: '是那一晚的 30，不是前一晚的 50');
      expect(find.byKey(const Key('report-night-xp-so-far')), findsNothing);
    });

    testWidgets('⚠️ 差的晚上照實寫 +0 XP，不藏（紅線 5）', (tester) async {
      await pumpReport(
        tester,
        buildMorningReport(date: '2026-11-12', home: homeWithScore('2026-11-12'))
            .withExtras(game: game([
          {'date': '2026-11-12', 'total': 0, 'final_quality': 'Bad'},
        ])),
      );
      expect(
          hasText(tester, find.byKey(const Key('report-night-xp')), '+0 XP'),
          isTrue);
    });

    testWidgets('手錶資料還沒到 → +N XP so far；後端還沒有這晚 → 不畫 +N',
        (tester) async {
      await pumpReport(
        tester,
        buildMorningReport(date: '2026-11-12').withExtras(game: game([
          {'date': '2026-11-12', 'behaviour_xp': 30, 'total': 30},
        ])),
      );
      expect(
          hasText(tester, find.byKey(const Key('report-night-xp')), '+30 XP'),
          isTrue);
      expect(find.byKey(const Key('report-night-xp-so-far')), findsOneWidget);

      await pumpReport(
        tester,
        buildMorningReport(date: '2026-11-13')
            .withExtras(game: game([{'date': '2026-11-12', 'total': 30}])),
      );
      expect(find.byKey(const Key('report-night-xp')), findsNothing);
      expect(find.byKey(const Key('report-level')), findsOneWidget);
    });

    testWidgets('沒有後端（沒有 /game）→ 整塊等級不畫', (tester) async {
      await pumpReport(tester, buildMorningReport(date: '2026-11-12'));
      expect(find.byKey(const Key('report-xp')), findsNothing);
    });

    testWidgets('⚠️ 睡眠目標只寫事實：不寫 reached、不寫 missed', (tester) async {
      await pumpReport(
        tester,
        buildMorningReport(date: '2026-11-12', home: homeWithScore('2026-11-12'))
            .withExtras(goalMinutes: 480),
      );
      expect(textOf(tester, 'report-goal-line'), 'of your 8h goal');
      expect(find.textContaining('reached'), findsNothing);
      expect(find.textContaining('missed'), findsNothing);
      expect(find.textContaining('Great'), findsNothing);
    });

    testWidgets('View sleep insights：首頁有給才放；按了回傳 insights', (tester) async {
      final r = buildMorningReport(date: '2026-11-12');
      await pumpReport(tester, r);
      expect(find.byKey(const Key('report-insights')), findsNothing);

      String? popped;
      tester.view.physicalSize = const Size(1200, 5000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              popped = await Navigator.of(context).push<String>(
                MaterialPageRoute(
                  builder: (_) =>
                      MorningReportScreen(initial: r, canOpenInsights: true),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('report-insights')));
      await tester.tap(find.byKey(const Key('report-insights')));
      await settle(tester);
      expect(popped, kReportOpenInsights);
    });

    testWidgets('報告畫面用 Nunito', (tester) async {
      await pumpReport(
        tester,
        buildMorningReport(
            date: '2026-11-12', home: homeWithScore('2026-11-12')),
      );
      final ctx = tester.element(find.byKey(const Key('report-score')));
      expect(DefaultTextStyle.of(ctx).style.fontFamily, 'Nunito');
    });

    for (final waiting in [false, true]) {
      testWidgets(
          '⚠️ 6.4 吋手機（1080×2340）不溢出：${waiting ? '等待中' : '完整版'}',
          (tester) async {
        final date = session.history.last.date;
        final home = waiting ? homeWaiting(date) : homeWithScore(date);
        var r = buildMorningReport(date: date, home: home, session: session)
            .withExtras(
          goalMinutes: 480,
          localRating: MorningRating(date: date, rested: 5),
          game: game([
            {'date': date, 'total': 30},
          ]),
        );
        if (!waiting) r = r.withSummary(summaryOk(date));
        await pumpReport(tester, r,
            size: const Size(1080, 2340), canOpenInsights: true);
        expect(tester.takeException(), isNull);
        // 展開 More details 也不溢出
        final toggle = find.byKey(const Key('report-details-toggle'));
        if (toggle.evaluate().isNotEmpty) {
          await tester.ensureVisible(toggle);
          await tester.tap(toggle);
          await settle(tester);
          expect(tester.takeException(), isNull);
        }
      });
    }
  });

  group('入口', () {
    Future<BedMarkStore> pumpHome(
      WidgetTester tester,
      DateTime now,
      _Source source, {
      Future<void> Function(BedMarkStore)? before,
      RestedSender? rested,
      Size size = const Size(1200, 4200),
    }) async {
      tester.view.physicalSize = size;
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
              rested: rested,
              clock: () => now,
            ),
          ),
        ),
      );
      await settle(tester);
      return store;
    }

    Future<void> slideUp(WidgetTester tester) async {
      expect(find.byType(SleepModeScreen), findsOneWidget);
      await tester.drag(
          find.byKey(const Key('slide-knob')), const Offset(1000, 0));
      await settle(tester, 15);
    }

    testWidgets('⚠️ 滑完 Slide to get up → 先問睡得怎樣（還沒問後端），Skip 之後才出現報告',
        (tester) async {
      final source = _Source(homeWaiting('2026-11-12'));
      final sender = _Sender();
      await pumpHome(tester, at(12, 7, 10), source,
          rested: sender, before: (s) => s.markStart(at(11, 23, 40)));
      await slideUp(tester);
      expect(find.byType(RestedScreen), findsOneWidget);
      expect(find.byType(MorningReportScreen), findsNothing);
      expect(source.asked, isEmpty, reason: '看到分數之前先問，所以還沒讀報告');
      expect(find.byKey(const Key('report-score')), findsNothing);

      await tester.tap(find.byKey(const Key('rested-skip')));
      await settle(tester, 15);
      expect(find.byType(MorningReportScreen), findsOneWidget);
      expect(source.asked, ['2026-11-12'], reason: '問的是起床日那一晚');
      expect(sender.sent, isEmpty, reason: 'Skip 不送任何東西');
      expect(find.text(kWaitingForWatch), findsOneWidget);
      expect(textOf(tester, 'report-times'), '23:40 → 07:10');
      await tester.ensureVisible(find.byKey(const Key('report-done')));
      await tester.tap(find.byKey(const Key('report-done')));
      await settle(tester);
      expect(find.byType(MorningReportScreen), findsNothing);
    });

    testWidgets('填了自評 → 送出那一晚、起床後幾分鐘；報告出現「You felt」',
        (tester) async {
      final source = _Source(homeWaiting('2026-11-12'));
      final sender = _Sender();
      await pumpHome(tester, at(12, 7, 10), source,
          rested: sender, before: (s) => s.markStart(at(11, 23, 40)));
      await slideUp(tester);
      await tester.tap(find.byKey(const Key('rested-face-4')));
      await tester.ensureVisible(find.byKey(const Key('rested-tag-exercise')));
      await tester.tap(find.byKey(const Key('rested-tag-exercise')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('rested-save')));
      await tester.tap(find.byKey(const Key('rested-save')));
      await settle(tester, 15);
      expect(sender.sent, hasLength(1));
      expect(sender.sent.single.date, '2026-11-12');
      expect(sender.sent.single.rested, 4);
      expect(sender.sent.single.tags, ['exercise']);
      expect(sender.sent.single.minutesAfterWake, 0);
      expect(find.byType(MorningReportScreen), findsOneWidget);
      expect(textOf(tester, 'report-rating-label'), 'Well-rested');
    });

    testWidgets('⚠️ 首頁補填小卡：Skip 之後起床 6 小時內出現，填完就消失',
        (tester) async {
      final source = _Source(homeWaiting('2026-11-12'));
      final store = await pumpHome(tester, at(12, 9), source,
          before: (s) async {
        await s.markStart(at(11, 23, 40));
        await s.markEnd(at(12, 7, 10));
      });
      final card = find.byKey(const Key('rested-make-up'));
      expect(card, findsOneWidget);
      await tester.ensureVisible(card);
      await tester.tap(card);
      await settle(tester, 15);
      expect(find.byType(RestedScreen), findsOneWidget);
      await tester.tap(find.byKey(const Key('rested-face-3')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('rested-save')));
      await tester.tap(find.byKey(const Key('rested-save')));
      await settle(tester, 15);
      // 填完直接看那一晚的報告
      expect(find.byType(MorningReportScreen), findsOneWidget);
      final saved = await MorningRatingStore(store.store).read('2026-11-12');
      expect(saved!.rested, 3);
      expect(saved.minutesAfterWake, 110, reason: '07:10 起床、09:00 才填');
      await tester.ensureVisible(find.byKey(const Key('report-done')));
      await tester.tap(find.byKey(const Key('report-done')));
      await settle(tester, 15);
      expect(card, findsNothing);
    });

    testWidgets('起床超過 6 小時 → 不出現補填小卡', (tester) async {
      await pumpHome(tester, at(12, 13, 20), _Source(null), before: (s) async {
        await s.markStart(at(11, 23, 40));
        await s.markEnd(at(12, 7, 10));
      });
      expect(find.byKey(const Key('rested-make-up')), findsNothing);
    });

    testWidgets('⚠️ 按 Cancel 不出現自評也不出現報告', (tester) async {
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
      expect(find.byType(RestedScreen), findsNothing);
      expect(find.byType(MorningReportScreen), findsNothing);
      expect(source.asked, isEmpty);
    });

    // 2026-11-12 使用者定（問題 2 選 B）：分數可能比打包檔早到，
    // 所以心情列要畫到今天、沒心情的那天也要點得到。
    testWidgets('⚠️ 打包檔停在舊日期 → 心情列仍畫到今天；點今天那格說在等資料',
        (tester) async {
      final latest = DateTime.parse(session.history.last.date);
      final today = latest.add(const Duration(days: 3));
      final key = reportDateKey(today);
      final source = _Source(homeWaiting(key));
      await pumpHome(tester, DateTime(today.year, today.month, today.day, 9),
          source);
      final cell = find.byKey(Key('week-day-${today.day}'));
      expect(cell, findsOneWidget, reason: '今天那格一定要在');
      await tester.ensureVisible(cell);
      await tester.tap(cell);
      await settle(tester, 15);
      expect(source.asked, [key]);
      expect(find.text(kWaitingForWatch), findsOneWidget);
      expect(source.askedSummary, isEmpty, reason: '還在等手錶就不問 AI');
    });

    testWidgets('⚠️ 點更早的空日子 → 說沒有資料，不說在等', (tester) async {
      final latest = DateTime.parse(session.history.last.date);
      final today = latest.add(const Duration(days: 3));
      final older = latest.add(const Duration(days: 1));
      final source = _Source(null);
      await pumpHome(tester, DateTime(today.year, today.month, today.day, 9),
          source);
      final cell = find.byKey(Key('week-day-${older.day}'));
      await tester.ensureVisible(cell);
      await tester.tap(cell);
      await settle(tester, 15);
      expect(source.asked, [reportDateKey(older)]);
      expect(find.text(kNoWatchData), findsOneWidget);
      expect(find.text(kWaitingForWatch), findsNothing);
    });

    testWidgets('一週心情列點最新那天 → 打開那一晚的報告，再接上 AI 那段',
        (tester) async {
      final latest = session.history.last;
      final source = _Source(homeWithScore(latest.date),
          summary: summaryOk(latest.date));
      await pumpHome(tester, at(12, 15), source);
      final day = DateTime.parse(latest.date).day;
      await tester.ensureVisible(find.byKey(Key('week-day-$day')));
      await tester.tap(find.byKey(Key('week-day-$day')));
      await settle(tester, 15);
      expect(find.byType(MorningReportScreen), findsOneWidget);
      expect(source.asked, [latest.date]);
      expect(source.askedSummary, [latest.date]);
      expect(textOf(tester, 'report-score'), '62');
      expect(textOf(tester, 'report-summary'), 'SENTINEL-summary');
    });
  });
}
