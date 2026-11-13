// 首頁（一頁全放）與睡覺畫面（2026-11-12 定案）。
//
// 守的都是「壞掉時不會報錯」的地方：
// - 「不按也沒關係」那句話要在 Start sleep 旁邊（原本在 bed_mark_buttons_test）
// - 凌晨兩點不顯示倒數數字（會算成「距離明天還有 21 小時」）
// - 警語平常不顯示，但點卡片要看得到，而且文字照抄後端
// - 取消不能刪掉上一晚還沒上傳的那一對；下床要真的存進本機
// - 睡覺畫面不寫 measuring/tracking、返回鍵離不開
import 'dart:convert';

import 'package:app/models/sleep_session.dart';
import 'package:app/screens/home_screen.dart';
import 'package:app/screens/sleep_mode_screen.dart';
import 'package:app/services/alarm.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/camera_insights.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/sleep_repository.dart';
import 'package:app/services/start_sleep_requests.dart';
import 'package:app/widgets/countdown_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _ImmediateRepository implements SleepRepository {
  final SleepSession session;
  const _ImmediateRepository(this.session);

  @override
  Future<SleepSession> load() async => session;
}

DateTime at(int day, int h, [int m = 0]) => DateTime(2026, 11, day, h, m);

/// 什麼都不做的鬧鐘。⚠️ 測試環境裡真的 channel 沒有人回應，用真的會讓 Start sleep 卡住。
class _NoAlarm implements AlarmScheduler {
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

class _FailedCamera implements CameraInsightsSource {
  const _FailedCamera();

  @override
  Future<CameraInsightsResult> load() async =>
      const CameraInsightsResult(CameraInsightsStatus.failed);
}

void main() {
  late SleepSession sample;
  // 原始 JSON 在 setUpAll 讀：testWidgets 裡的時鐘是假的，真的讀檔會永遠等不到。
  late String rawPayload;
  late InMemoryKeyValueStore kv;
  late BedMarkStore store;
  // 導覽列中間的月亮（2026-11-13 起 Start Sleep 在那裡，不在首頁）
  late StartSleepRequests moon;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sample = await const AssetSleepRepository().load();
    rawPayload = await rootBundle.loadString(AssetSleepRepository.assetPath);
  });

  setUp(() {
    kv = InMemoryKeyValueStore();
    store = BedMarkStore(kv);
    moon = StartSleepRequests();
  });

  /// 按導覽列中間的月亮（＝原本首頁的 Start Sleep）
  Future<void> pressMoon(WidgetTester tester) async {
    moon.request();
    // 先滑出 Sleep schedule，按底下的 Start Sleep 才開始睡覺
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const Key('schedule-save')));
    await tester.pump();
  }

  /// [now] 是可變的：測試可以「讓時間過去」。
  Future<void> pumpHome(WidgetTester tester, DateTime Function() now) async {
    // 一支長手機的大小：整個首頁不用捲動就畫得完，tap 才點得到。
    tester.view.physicalSize = const Size(1200, 4200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            repository: _ImmediateRepository(sample),
            bedMarks: store,
          alarmScheduler: _NoAlarm(),
            startSleepRequests: moon,
            clock: now,
          ),
        ),
      ),
    );
    // ⚠️ 不用 pumpAndSettle：寵物的 Lottie 永遠在動。
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('一頁全放（2026-11-12 定案）', () {
    testWidgets('問候、心情標籤、分數、Start sleep、四張卡都在同一頁', (tester) async {
      await pumpHome(tester, () => at(12, 9));
      expect(find.text('Welcome to Sonnap'), findsOneWidget);
      expect(
        find.text('Hi, Sleeper!'),
        findsOneWidget,
        reason: '沒有帳號時用 Sleeper，不能是人名',
      );
      for (final k in [
        'mood-chip',
        'week-strip',
        'mood-legend',
        'night-sky-effects',
        'home-pet',
        'optional-note',
        'bedtime-countdown',
        'tile-duration',
        'tile-efficiency',
        'tile-deep',
        'tile-camera',
      ]) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
    });

    testWidgets('問候不分早午晚（使用者定）', (tester) async {
      await pumpHome(tester, () => at(12, 14));
      expect(find.text('Hi, Sleeper!'), findsOneWidget);
      expect(find.text('Welcome to Sonnap'), findsOneWidget);
      expect(find.textContaining('Good afternoon'), findsNothing);
    });

    testWidgets('「不按也沒關係」那句話在按鈕旁邊', (tester) async {
      await pumpHome(tester, () => at(12, 23, 10));
      expect(
        find.textContaining('fine if you forget'),
        findsOneWidget,
        reason: '這是加分項不是取代品，使用者必須看得到',
      );
      expect(find.textContaining('detected anyway'), findsOneWidget);
    });

    testWidgets('時鐘卡：23:10 → 還剩 20m，光條變紅', (tester) async {
      await pumpHome(tester, () => at(12, 23, 10));
      expect(find.text('23:10'), findsOneWidget);
      expect(find.text('Target 23:30'), findsOneWidget);
      final t = tester.widget<Text>(find.byKey(const Key('bedtime-countdown')));
      expect(t.data, '20m left');
      final b = tester.widget<CountdownBorder>(
        find.byKey(const Key('countdown-border')),
      );
      expect(
        b.color,
        const Color(0xFFFF6B6B),
        reason: '剩 30 分鐘內要紅，與提醒、守門同一個 30 分鐘',
      );
    });

    testWidgets('早上還很久：光條是綠的、幾乎整圈', (tester) async {
      await pumpHome(tester, () => at(12, 9));
      final b = tester.widget<CountdownBorder>(
        find.byKey(const Key('countdown-border')),
      );
      expect(b.color, const Color(0xFF7ED957));
      expect(b.progress, greaterThan(0.5));
    });

    testWidgets('⚠️ 凌晨兩點：不顯示倒數數字，改成一句話', (tester) async {
      await pumpHome(tester, () => at(13, 2));
      expect(find.byKey(const Key('late-evening')), findsOneWidget);
      expect(find.textContaining('Bedtime was 23:30'), findsOneWidget);
      expect(
        find.byKey(const Key('bedtime-countdown')),
        findsNothing,
        reason: '倒數會算成「距離明天還有 21 小時」',
      );
      expect(find.byKey(const Key('optional-note')), findsOneWidget);
    });

    testWidgets('首頁沒有自己的 Start Sleep 鈕（搬到導覽列中間的月亮）', (tester) async {
      await pumpHome(tester, () => at(12, 23, 10));
      expect(find.byKey(const Key('start-sleep')), findsNothing);
      expect(find.text('Start Sleep'), findsNothing);
    });

    testWidgets('首頁沒有下床鈕（下床在睡覺畫面裡按）', (tester) async {
      await pumpHome(tester, () => at(12, 9));
      expect(find.text('Out of bed'), findsNothing);
    });

    testWidgets('分數卡照抄後端：分數、等級、那句話', (tester) async {
      await pumpHome(tester, () => at(12, 9));
      expect(
        tester.widget<Text>(find.byKey(const Key('score-number'))).data,
        '${sample.scoring.scoreAsInt}',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('score-quality'))).data,
        '${sample.scoring.finalQuality} sleep',
      );
      expect(find.text(sample.display.scoreMessage), findsOneWidget);
    });

    testWidgets('點效率卡 → 跳出後端的警語原文（畫面上平常不放）', (tester) async {
      await pumpHome(tester, () => at(12, 9));
      final caveat = sample.scoring.composition!.caveats.firstWhere(
        (c) => c.component == 'efficiency',
      );
      expect(find.text(caveat.text), findsNothing, reason: '平常不顯示');
      await tester.tap(find.byKey(const Key('tile-efficiency')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text(caveat.text),
        findsOneWidget,
        reason: '文字只能照抄 score_claim.py，Dart 不產生',
      );
    });

    testWidgets('睡眠長度卡底下有「跟上一晚比」，點了開最近 7 晚的長條圖', (tester) async {
      await pumpHome(tester, () => at(12, 9));
      final line = find.descendant(
        of: find.byKey(const Key('tile-duration')),
        matching: find.byKey(const Key('tile-compare')),
      );
      expect(line, findsOneWidget);
      expect(tester.widget<Text>(line).data, contains(' vs '));
      await tester.tap(find.byKey(const Key('tile-duration')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('metric-sheet-duration')), findsOneWidget);
    });

    testWidgets('點分數卡 → 最近 7 晚的分數長條圖', (tester) async {
      await pumpHome(tester, () => at(12, 9));
      await tester.tap(find.byKey(const Key('score-card')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('metric-sheet-score')), findsOneWidget);
    });

    testWidgets('⚠️ 歷史沒有效率資料（舊版後端）→ 不畫比較，不編數字', (tester) async {
      final hasEff = sample.history.any((e) => e.sleepEfficiency != null);
      await pumpHome(tester, () => at(12, 9));
      final line = find.descendant(
        of: find.byKey(const Key('tile-efficiency')),
        matching: find.byKey(const Key('tile-compare')),
      );
      expect(line, hasEff ? findsOneWidget : findsNothing);
    });

    testWidgets('沒有後端 → 攝影機卡說需要後端，不畫數字', (tester) async {
      await pumpHome(tester, () => at(12, 9));
      expect(
        find.descendant(
          of: find.byKey(const Key('tile-camera')),
          matching: find.text('Needs backend'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('⚠️ 後端連不到 → 攝影機卡不能說成「那晚沒錄影」', (tester) async {
      tester.view.physicalSize = const Size(1200, 4200);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeScreen(
              repository: _ImmediateRepository(sample),
              bedMarks: store,
          alarmScheduler: _NoAlarm(),
              cameraInsights: const _FailedCamera(),
              clock: () => at(12, 9),
            ),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final tile = find.byKey(const Key('tile-camera'));
      expect(
        find.descendant(of: tile, matching: find.text('Backend unreachable')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile, matching: find.text('No camera this night')),
        findsNothing,
      );
    });

    testWidgets('⚠️ 沒戴錶那晚：顯示「—」，不畫成 0', (tester) async {
      final raw = jsonDecode(rawPayload) as Map<String, dynamic>;
      final metrics = raw['metrics'] as Map<String, dynamic>;
      for (final k in [
        'sleep_duration_minutes',
        'sleep_efficiency',
        'deep_minutes',
      ]) {
        metrics[k] = null;
      }
      raw['scoring'] = {...raw['scoring'] as Map, 'final_score': null};
      final original = sample;
      sample = SleepSession.fromJson(raw);
      addTearDown(() => sample = original);

      await pumpHome(tester, () => at(12, 9));
      expect(find.text('No watch data'), findsNWidgets(3));
      expect(
        find.textContaining('0 min'),
        findsNothing,
        reason: '「0 min」會被讀成整晚沒睡，真相是沒量到',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('score-number'))).data,
        '—',
      );
    });
  });

  group('睡覺畫面', () {
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // 剛按 Start Sleep 會先播「趴下睡著」的過場（點一下跳過），控制項播完才出現
      if (find.byKey(const Key('sleep-intro')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('sleep-intro')));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
    }

    testWidgets('剛按 Start Sleep → 先播過場、控制項藏著；播完（約 4 秒）控制項出現', (tester) async {
      await pumpHome(tester, () => at(12, 23, 41));
      await pressMoon(tester);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('sleep-intro')), findsOneWidget);
      final fade = tester.widget<AnimatedOpacity>(find.ancestor(
          of: find.byKey(const Key('sleep-cancel')), matching: find.byType(AnimatedOpacity)).first);
      expect(fade.opacity, 0, reason: '過場播的時候不疊控制項');
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byKey(const Key('sleep-intro')), findsNothing, reason: '播一次就收');
      expect(find.byKey(const Key('sleep-scene')), findsOneWidget, reason: '接著是睡覺的循環');
    });

    testWidgets('⚠️ 半夜重開 App 回到睡覺畫面 → 不播過場', (tester) async {
      await store.markStart(at(12, 23, 41));
      await pumpHome(tester, () => at(13, 3));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(SleepModeScreen), findsOneWidget);
      expect(find.byKey(const Key('sleep-intro')), findsNothing);
    });

    testWidgets('按 Start sleep → 存進本機，並進入睡覺畫面', (tester) async {
      await pumpHome(tester, () => at(12, 23, 41));
      await pressMoon(tester);
      await settle(tester);
      expect(
        await kv.getString(kBedStartKey),
        isNotNull,
        reason: '只改畫面不存檔的話，關掉 App 就沒了',
      );
      expect(find.byType(SleepModeScreen), findsOneWidget);
      expect(find.text('Sleeping… your watch is tracking'), findsOneWidget);
    });

    testWidgets('中間那顆 → 先出 Sleep schedule；把面板關掉＝不開始睡覺', (tester) async {
      await pumpHome(tester, () => at(12, 23, 41));
      moon.request();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Sleep schedule'), findsOneWidget);
      expect(find.text('Start Sleep'), findsOneWidget);
      expect(find.byKey(const Key('schedule-background')), findsOneWidget,
          reason: '面板後面鋪窗景（2026-11-14）');
      await tester.tapAt(const Offset(20, 20)); // 點面板外面
      await settle(tester);
      expect(await kv.getString(kBedStartKey), isNull, reason: '沒按 Start Sleep 不得記下上床');
      expect(find.byType(SleepModeScreen), findsNothing);
    });

    testWidgets('半夜打開 App（還沒按下床）→ 直接是睡覺畫面', (tester) async {
      await store.markStart(at(12, 23, 41));
      await pumpHome(tester, () => at(13, 3));
      await settle(tester);
      expect(find.byType(SleepModeScreen), findsOneWidget);
    });

    testWidgets('上床滿 14 小時 → 不再是睡覺畫面', (tester) async {
      await store.markStart(at(12, 23, 41));
      await pumpHome(tester, () => at(13, 14));
      await settle(tester);
      expect(find.byType(SleepModeScreen), findsNothing);
    });

    testWidgets('按下床 → 兩個時刻都在本機，回到首頁', (tester) async {
      var now = at(12, 23, 41);
      await pumpHome(tester, () => now);
      await pressMoon(tester);
      await settle(tester);
      now = at(13, 7, 10);
      await tester.drag(find.byKey(const Key('slide-knob')), const Offset(1000, 0));
      await settle(tester);
      expect(find.byType(SleepModeScreen), findsNothing);
      final marks = await store.read(now: now);
      expect(marks.isComplete, isTrue);
      expect(marks.endAt, at(13, 7, 10));
    });

    testWidgets('取消 → 要確認；確認後這次的開始沒了，上一晚的那一對還在', (tester) async {
      // 上一晚：完整一對，還沒上傳
      await store.markStart(at(11, 23, 50));
      await store.markEnd(at(12, 7, 30));
      await pumpHome(tester, () => at(12, 23, 41));
      await pressMoon(tester);
      await settle(tester);

      await tester.tap(find.byKey(const Key('sleep-cancel')));
      await settle(tester);
      expect(find.text('Cancel this sleep?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('sleep-cancel-confirm')));
      await settle(tester);

      expect(find.byType(SleepModeScreen), findsNothing);
      expect(await kv.getString(kBedStartKey), isNull);
      final pending = await store.readPending(now: at(12, 23, 45));
      expect(pending.isComplete, isTrue, reason: '取消今晚不能刪掉上一晚的真資料');
    });

    testWidgets('取消時按「Keep sleeping」→ 什麼都沒變', (tester) async {
      await pumpHome(tester, () => at(12, 23, 41));
      await pressMoon(tester);
      await settle(tester);
      await tester.tap(find.byKey(const Key('sleep-cancel')));
      await settle(tester);
      await tester.tap(find.text('Keep sleeping'));
      await settle(tester);
      expect(find.byType(SleepModeScreen), findsOneWidget);
      expect(await kv.getString(kBedStartKey), isNotNull);
    });

    testWidgets('⚠️ 返回鍵離不開睡覺畫面', (tester) async {
      await pumpHome(tester, () => at(12, 23, 41));
      await pressMoon(tester);
      await settle(tester);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      await navigator.maybePop();
      await settle(tester);
      expect(find.byType(SleepModeScreen), findsOneWidget);
    });

    testWidgets('⚠️ 不說 App 在量：只准講「手錶在量」', (tester) async {
      // 2026-11-12 使用者定副標 `Sleeping… your watch is tracking`——量的是手錶，是事實。
      // 但 App 本身沒有在量，所以其他 measuring／monitoring／tracking 的說法一律不准。
      await pumpHome(tester, () => at(12, 23, 41));
      await pressMoon(tester);
      await settle(tester);
      for (final word in ['easur', 'onitor']) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
      for (final e in find.textContaining('racking').evaluate()) {
        final t = (e.widget as Text).data ?? '';
        expect(t.contains('watch is tracking'), isTrue, reason: t);
      }
    });
  });
}
