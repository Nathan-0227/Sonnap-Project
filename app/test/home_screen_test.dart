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
import 'package:app/services/bed_marks.dart';
import 'package:app/services/camera_insights.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/sleep_repository.dart';
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

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sample = await const AssetSleepRepository().load();
    rawPayload =
        await rootBundle.loadString(AssetSleepRepository.assetPath);
  });

  setUp(() {
    kv = InMemoryKeyValueStore();
    store = BedMarkStore(kv);
  });

  /// [now] 是可變的：測試可以「讓時間過去」。
  Future<void> pumpHome(WidgetTester tester, DateTime Function() now) async {
    // 一支長手機的大小：整個首頁不用捲動就畫得完，tap 才點得到。
    tester.view.physicalSize = const Size(1200, 4200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeScreen(
          repository: _ImmediateRepository(sample),
          bedMarks: store,
          clock: now,
        ),
      ),
    ));
    // ⚠️ 不用 pumpAndSettle：寵物的 Lottie 永遠在動。
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('一頁全放（2026-11-12 定案）', () {
    testWidgets('問候、心情標籤、分數、Start sleep、四張卡都在同一頁', (tester) async {
      await pumpHome(tester, () => at(12, 9));
      expect(find.textContaining('Good morning, Sleeper'), findsOneWidget,
          reason: '沒有帳號時用 Sleeper，不能是人名');
      for (final k in [
        'mood-chip',
        'week-strip',
        'mood-legend',
        'night-sky-effects',
        'home-pet',
        'start-sleep',
        'bedtime-countdown',
        'tile-duration',
        'tile-efficiency',
        'tile-deep',
        'tile-camera',
      ]) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
    });

    testWidgets('下午的問候是 afternoon', (tester) async {
      await pumpHome(tester, () => at(12, 14));
      expect(find.textContaining('Good afternoon'), findsOneWidget);
    });

    testWidgets('「不按也沒關係」那句話在按鈕旁邊', (tester) async {
      await pumpHome(tester, () => at(12, 23, 10));
      expect(find.textContaining('fine if you forget'), findsOneWidget,
          reason: '這是加分項不是取代品，使用者必須看得到');
      expect(find.textContaining('detected anyway'), findsOneWidget);
    });

    testWidgets('就寢時間列：23:10 → 23:30 · 20m left', (tester) async {
      await pumpHome(tester, () => at(12, 23, 10));
      expect(find.text('23:30 · 20m left'), findsOneWidget);
    });

    testWidgets('⚠️ 凌晨兩點：不顯示倒數數字，改成一句話', (tester) async {
      await pumpHome(tester, () => at(13, 2));
      expect(find.byKey(const Key('late-evening')), findsOneWidget);
      expect(find.textContaining('Bedtime was 23:30'), findsOneWidget);
      expect(find.byKey(const Key('bedtime-countdown')), findsNothing,
          reason: '倒數會算成「距離明天還有 21 小時」');
      expect(find.byKey(const Key('start-sleep')), findsOneWidget);
    });

    testWidgets('首頁沒有下床鈕（下床在睡覺畫面裡按）', (tester) async {
      await pumpHome(tester, () => at(12, 9));
      expect(find.text('Out of bed'), findsNothing);
    });

    testWidgets('分數行照抄後端', (tester) async {
      await pumpHome(tester, () => at(12, 9));
      final line = tester.widget<Text>(find.byKey(const Key('score-line')));
      final text = line.textSpan!.toPlainText();
      expect(text, contains('${sample.scoring.scoreAsInt} / 100'));
      expect(text, contains(sample.scoring.finalQuality));
    });

    testWidgets('點效率卡 → 跳出後端的警語原文（畫面上平常不放）', (tester) async {
      await pumpHome(tester, () => at(12, 9));
      final caveat = sample.scoring.composition!.caveats
          .firstWhere((c) => c.component == 'efficiency');
      expect(find.text(caveat.text), findsNothing, reason: '平常不顯示');
      await tester.tap(find.byKey(const Key('tile-efficiency')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(caveat.text), findsOneWidget,
          reason: '文字只能照抄 score_claim.py，Dart 不產生');
    });

    testWidgets('沒有後端 → 攝影機卡說需要後端，不畫數字', (tester) async {
      await pumpHome(tester, () => at(12, 9));
      expect(
          find.descendant(
              of: find.byKey(const Key('tile-camera')),
              matching: find.text('Needs backend')),
          findsOneWidget);
    });

    testWidgets('⚠️ 後端連不到 → 攝影機卡不能說成「那晚沒錄影」', (tester) async {
      tester.view.physicalSize = const Size(1200, 4200);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            repository: _ImmediateRepository(sample),
            bedMarks: store,
            cameraInsights: const _FailedCamera(),
            clock: () => at(12, 9),
          ),
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final tile = find.byKey(const Key('tile-camera'));
      expect(find.descendant(of: tile, matching: find.text('Backend unreachable')),
          findsOneWidget);
      expect(find.descendant(of: tile, matching: find.text('No camera this night')),
          findsNothing);
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
      expect(find.textContaining('0 min'), findsNothing,
          reason: '「0 min」會被讀成整晚沒睡，真相是沒量到');
      final line = tester.widget<Text>(find.byKey(const Key('score-line')));
      expect(line.textSpan!.toPlainText(), contains('— / 100'));
    });
  });

  group('睡覺畫面', () {
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('按 Start sleep → 存進本機，並進入睡覺畫面', (tester) async {
      await pumpHome(tester, () => at(12, 23, 41));
      await tester.tap(find.byKey(const Key('start-sleep')));
      await settle(tester);
      expect(await kv.getString(kBedStartKey), isNotNull,
          reason: '只改畫面不存檔的話，關掉 App 就沒了');
      expect(find.byType(SleepModeScreen), findsOneWidget);
      expect(find.text('Sleep mode · since 23:41'), findsOneWidget);
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
      await tester.tap(find.byKey(const Key('start-sleep')));
      await settle(tester);
      now = at(13, 7, 10);
      await tester.tap(find.byKey(const Key('sleep-out-of-bed')));
      await settle(tester);
      expect(find.byType(SleepModeScreen), findsNothing);
      final marks = await store.read(now: now);
      expect(marks.isComplete, isTrue);
      expect(marks.endAt, at(13, 7, 10));
    });

    testWidgets('取消 → 要確認；確認後這次的開始沒了，上一晚的那一對還在',
        (tester) async {
      // 上一晚：完整一對，還沒上傳
      await store.markStart(at(11, 23, 50));
      await store.markEnd(at(12, 7, 30));
      await pumpHome(tester, () => at(12, 23, 41));
      await tester.tap(find.byKey(const Key('start-sleep')));
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
      await tester.tap(find.byKey(const Key('start-sleep')));
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
      await tester.tap(find.byKey(const Key('start-sleep')));
      await settle(tester);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      await navigator.maybePop();
      await settle(tester);
      expect(find.byType(SleepModeScreen), findsOneWidget);
    });

    testWidgets('⚠️ 不寫 measuring／tracking：睡覺時 App 沒有在量東西',
        (tester) async {
      await pumpHome(tester, () => at(12, 23, 41));
      await tester.tap(find.byKey(const Key('start-sleep')));
      await settle(tester);
      for (final word in ['easur', 'racking', 'onitor']) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
    });
  });
}
