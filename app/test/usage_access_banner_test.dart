// 首頁的「手機使用權限」提示條（2026-11-19 使用者定：從 Insights 的手機分心卡搬到首頁）。
//
// 沒開「使用情況存取」就偵測不到幾點放下手機，熬夜、挑戰、Phone down 全部沒資料，
// 而且不會有任何錯誤訊息。守三件事：
//   1. 沒開 → 首頁看得到提示，點了帶去系統設定
//   2. 從設定回來（resumed）已經開了 → 提示消失
//   3. 不支援的平台（iOS、桌機）不出現——那裡本來就沒有這個權限可開
import 'package:app/models/sleep_session.dart';
import 'package:app/screens/home_screen.dart';
import 'package:app/services/alarm.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/sleep_repository.dart';
import 'package:app/services/usage_stats.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ImmediateRepository implements SleepRepository {
  final SleepSession session;
  const _ImmediateRepository(this.session);

  @override
  Future<SleepSession> load() async => session;
}

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

class _FakeUsage extends UsageStatsService {
  final bool supported;
  bool access;
  int opened = 0;

  _FakeUsage({this.supported = true, this.access = false});

  @override
  bool get isSupported => supported;

  @override
  Future<bool> hasAccess() async => access;

  @override
  Future<void> openSettings() async => opened++;
}

void main() {
  late SleepSession sample;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sample = await const AssetSleepRepository().load();
  });

  Future<void> pumpHome(WidgetTester tester, _FakeUsage usage) async {
    tester.view.physicalSize = const Size(1200, 4200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            repository: _ImmediateRepository(sample),
            bedMarks: BedMarkStore(InMemoryKeyValueStore()),
            alarmScheduler: _NoAlarm(),
            usageStats: usage,
            clock: () => DateTime(2026, 11, 19, 9),
          ),
        ),
      ),
    );
    // ⚠️ 不用 pumpAndSettle：寵物的動畫永遠在動。
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  const banner = Key('usage-access-banner');

  testWidgets('沒開權限 → 首頁有提示，點了帶去系統設定', (tester) async {
    final usage = _FakeUsage();
    await pumpHome(tester, usage);
    expect(find.byKey(banner), findsOneWidget);

    await tester.tap(find.byKey(banner));
    await tester.pump();
    expect(usage.opened, 1);
  });

  testWidgets('從設定回來已經開了 → 提示消失', (tester) async {
    final usage = _FakeUsage();
    await pumpHome(tester, usage);
    expect(find.byKey(banner), findsOneWidget);

    usage.access = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(banner), findsNothing,
        reason: '開了還掛著提示，使用者會以為沒開成功');
  });

  testWidgets('已經開了 → 一開始就沒有提示', (tester) async {
    await pumpHome(tester, _FakeUsage(access: true));
    expect(find.byKey(banner), findsNothing);
  });

  testWidgets('不支援的平台 → 不出現', (tester) async {
    await pumpHome(tester, _FakeUsage(supported: false));
    expect(find.byKey(banner), findsNothing);
  });
}
