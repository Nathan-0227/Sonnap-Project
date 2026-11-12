// 首頁早晚兩版、Today/Tonight 切換、睡覺畫面（2026-11-12 定案）。
//
// 守的都是「壞掉時不會報錯」的地方：
// - 「不按也沒關係」那句話要在 Start sleep 旁邊（原本在 bed_mark_buttons_test）
// - 晚上版不顯示心情標籤（那不是心情，是「該睡了」）
// - 凌晨兩點不顯示倒數數字（會算成「距離明天還有 21 小時」）
// - 取消不能刪掉上一晚還沒上傳的那一對；下床要真的存進本機
// - 睡覺畫面不寫 measuring/tracking、返回鍵離不開
import 'package:app/models/sleep_session.dart';
import 'package:app/screens/home_screen.dart';
import 'package:app/screens/sleep_mode_screen.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/sleep_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ImmediateRepository implements SleepRepository {
  final SleepSession session;
  const _ImmediateRepository(this.session);

  @override
  Future<SleepSession> load() async => session;
}

DateTime at(int day, int h, [int m = 0]) => DateTime(2026, 11, day, h, m);

void main() {
  late SleepSession sample;
  late InMemoryKeyValueStore kv;
  late BedMarkStore store;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sample = await const AssetSleepRepository().load();
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

  group('白天版（09:00，目標 23:30）', () {
    testWidgets('問候、心情、分數都在；沒有 Start sleep', (tester) async {
      await pumpHome(tester, () => at(12, 9));
      expect(find.byKey(const Key('day-greeting')), findsOneWidget);
      expect(find.textContaining('Good morning, Sleeper'), findsOneWidget,
          reason: '沒有帳號時用 Sleeper，不能是人名');
      expect(find.byKey(const Key('mood-chip')), findsOneWidget);
      expect(find.byKey(const Key('start-sleep')), findsNothing);
      expect(find.byKey(const Key('sleepy-pet')), findsNothing);
    });

    testWidgets('下午照樣是白天版，但問候是 afternoon', (tester) async {
      await pumpHome(tester, () => at(12, 14));
      expect(find.textContaining('Good afternoon'), findsOneWidget);
      expect(find.byKey(const Key('start-sleep')), findsNothing);
    });
  });

  group('晚上版（23:10，目標 23:30）', () {
    testWidgets('Start sleep 與「不按也沒關係」都在', (tester) async {
      await pumpHome(tester, () => at(12, 23, 10));
      expect(find.byKey(const Key('start-sleep')), findsOneWidget);
      expect(find.textContaining('Optional'), findsOneWidget,
          reason: '這是加分項不是取代品，使用者必須看得到');
      expect(find.textContaining('detected anyway'), findsOneWidget);
      expect(find.byKey(const Key('bedtime-countdown')), findsOneWidget);
    });

    testWidgets('⚠️ 不顯示心情標籤：晚上的寵物不是心情', (tester) async {
      await pumpHome(tester, () => at(12, 23, 10));
      expect(find.byKey(const Key('sleepy-pet')), findsOneWidget);
      expect(find.byKey(const Key('mood-chip')), findsNothing);
      // 反向對照：白天版確實有那個標籤，所以上面那條不是假性通過
      await tester.tap(find.byKey(const Key('mode-today')));
      await tester.pump();
      expect(find.byKey(const Key('mood-chip')), findsOneWidget);
    });
  });

  group('凌晨兩點還沒睡（目標 23:30）', () {
    testWidgets('不顯示倒數數字，改成一句話；Start sleep 照樣在', (tester) async {
      await pumpHome(tester, () => at(13, 2));
      expect(find.byKey(const Key('late-evening')), findsOneWidget);
      expect(find.text('Bedtime was 23:30'), findsOneWidget);
      expect(find.byKey(const Key('bedtime-countdown')), findsNothing,
          reason: '倒數會算成「距離明天還有 21 小時」');
      expect(find.byKey(const Key('start-sleep')), findsOneWidget);
    });
  });

  group('Today / Tonight 手動切換', () {
    testWidgets('白天切到 Tonight 看得到晚上版，再切回來', (tester) async {
      await pumpHome(tester, () => at(12, 14));
      await tester.tap(find.byKey(const Key('mode-tonight')));
      await tester.pump();
      expect(find.byKey(const Key('start-sleep')), findsOneWidget);
      await tester.tap(find.byKey(const Key('mode-today')));
      await tester.pump();
      expect(find.byKey(const Key('start-sleep')), findsNothing);
    });

    testWidgets('⚠️ 切換不留下來：重開 App 恢復自動', (tester) async {
      await pumpHome(tester, () => at(12, 14));
      await tester.tap(find.byKey(const Key('mode-tonight')));
      await tester.pump();
      expect(find.byKey(const Key('start-sleep')), findsOneWidget);
      // 模擬重開 App：整棵樹換掉再建一次
      await tester.pumpWidget(const SizedBox());
      await pumpHome(tester, () => at(12, 14));
      expect(find.byKey(const Key('start-sleep')), findsNothing,
          reason: '手動切換只活在這次開著的 App 裡');
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
