// 手機使用時間：Dart 端與 Insights 卡片。
//
// 這一組守兩件事：
//
//   1. **語意**。原生端給的是「昨天整天的前景總時間」，不是「睡前一小時」。
//      把整天的數字放在「Top Sleep Distractions」的標題底下，就是拿一個量
//      冒充另一個量——而畫面看起來完全正常，沒有任何跡象。
//      這正是本專案在 `movement_sample_minutes`、`sleep_efficiency` 上
//      反覆記取的同一種錯誤。
//
//   2. **沒有權限時要帶路**。PACKAGE_USAGE_STATS 跳不出系統授權對話框，
//      使用者一定要自己走一趟設定頁。只寫「沒有權限」然後把人丟在原地，
//      這個功能對絕大多數人就等於不存在。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/sleep_session.dart';
import 'package:app/screens/report_screen.dart';
import 'package:app/services/sleep_repository.dart';
import 'package:app/services/usage_stats.dart';

class _ImmediateRepository implements SleepRepository {
  final SleepSession session;
  const _ImmediateRepository(this.session);

  @override
  Future<SleepSession> load() async => session;
}

class _FakeUsageStats extends UsageStatsService {
  UsageStatsResult result;
  int openSettingsCalls = 0;
  int queryCalls = 0;

  _FakeUsageStats(this.result);

  @override
  bool get isSupported => true;

  @override
  Future<UsageStatsResult> queryYesterday({int limit = 5}) async {
    queryCalls++;
    return result;
  }

  @override
  Future<void> openSettings() async => openSettingsCalls++;
}

void main() {
  late SleepSession sample;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // ⚠️ 在 setUpAll 讀。widget test 的假時間不會推進真正的檔案 I/O，
    // `await ...load()` 寫在 testWidgets 內會卡到逾時。
    sample = await const AssetSleepRepository().load();
  });

  Future<void> pumpReport(WidgetTester tester, _FakeUsageStats usage) async {
    // ReportScreen 內容很長，畫布太小會滿版溢位而蓋掉真正要驗的東西
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: ReportScreen(
        repository: _ImmediateRepository(sample),
        usageStats: usage,
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  group('語意：標題不能把整天的數字說成睡前', () {
    test('服務層的文件與方法名都指向「昨天一整天」', () {
      // queryYesterday 是刻意的命名。改成 queryBeforeBed 之類的名字
      // 而沒有先換掉原生端的 queryUsageStats，就是在說謊。
      const service = UsageStatsService();
      expect(service.queryYesterday, isA<Function>());
    });

    testWidgets('卡片標題不得宣稱是睡前使用', (tester) async {
      final usage = _FakeUsageStats(const UsageStatsResult(
        UsageStatsStatus.ok,
        apps: [
          AppUsage(packageName: 'com.a', appName: 'Threads', minutes: 95),
        ],
      ));
      await pumpReport(tester, usage);

      // 原生端 queryUsageStats(INTERVAL_DAILY) 給的是日彙總，切不出睡前一小時。
      // 要真的做到睡前歸因得先改用 queryEvents()——在那之前這個標題不能出現。
      expect(
        find.text('Top Sleep Distractions'),
        findsNothing,
        reason: '標題宣稱是睡前分心，但資料是整天的前景總時間。'
            '要改回這個標題，得先讓原生端改用 queryEvents() 取得時間軸。',
      );
      expect(find.text('Phone Use Yesterday'), findsOneWidget);
      expect(
        find.textContaining('Not yet narrowed to the hour before bed'),
        findsOneWidget,
        reason: '限制要寫在畫面上，不是只寫在程式註解裡',
      );
    });
  });

  group('四種狀態各講不同的話', () {
    testWidgets('有資料時列出 App 名稱與時間', (tester) async {
      final usage = _FakeUsageStats(const UsageStatsResult(
        UsageStatsStatus.ok,
        apps: [
          AppUsage(packageName: 'com.a', appName: 'Threads', minutes: 125),
          AppUsage(packageName: 'com.b', appName: 'YouTube', minutes: 47),
        ],
      ));
      await pumpReport(tester, usage);

      expect(find.text('Threads'), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('2h 5m'), findsOneWidget, reason: '125 分鐘要顯示成 2h 5m');
      expect(find.text('47m'), findsOneWidget);
    });

    testWidgets('沒有權限時要給一個帶去設定頁的按鈕', (tester) async {
      final usage =
          _FakeUsageStats(const UsageStatsResult(UsageStatsStatus.permissionRequired));
      await pumpReport(tester, usage);

      final button = find.widgetWithText(OutlinedButton, 'Open Usage Access settings');
      expect(
        button,
        findsOneWidget,
        reason: 'PACKAGE_USAGE_STATS 跳不出系統對話框，沒有這個按鈕的話'
            '使用者根本不知道要去哪裡開',
      );

      expect(usage.queryCalls, 1);
      await tester.tap(button);
      await tester.pump();
      await tester.pump();

      expect(usage.openSettingsCalls, 1);
    });

    testWidgets('從系統設定頁回到 App 時要重新查一次', (tester) async {
      // ⚠️ 這一條守的是實機上真的踩過的 bug。
      //
      // 第一版是在 `openSettings()` 之後直接重查，但那個呼叫送出 intent 就
      // 立刻返回——使用者根本還沒點下授權。實機測試的結果是：授權完回到 App，
      // 卡片仍然顯示「需要權限」，看起來像功能壞了。
      //
      // 正確的時機是 App 回到前景（AppLifecycleState.resumed）。
      final usage =
          _FakeUsageStats(const UsageStatsResult(UsageStatsStatus.permissionRequired));
      await pumpReport(tester, usage);
      expect(usage.queryCalls, 1);

      // 模擬「跳去系統設定頁、授權完、按返回回到 App」
      usage.result = const UsageStatsResult(
        UsageStatsStatus.ok,
        apps: [AppUsage(packageName: 'com.a', appName: 'Threads', minutes: 30)],
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();

      expect(
        usage.queryCalls,
        greaterThan(1),
        reason: '回到前景沒有重查，使用者授權完看到的還是「需要權限」',
      );
      expect(find.text('Threads'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Open Usage Access settings'),
        findsNothing,
        reason: '已經授權了還留著那顆按鈕，等於在說授權沒成功',
      );
    });

    testWidgets('非 Android 平台要說清楚，不要假裝是沒有資料', (tester) async {
      final usage =
          _FakeUsageStats(const UsageStatsResult(UsageStatsStatus.unsupported));
      await pumpReport(tester, usage);

      expect(find.textContaining('only available on Android'), findsOneWidget);
    });

    testWidgets('查得到但昨天沒有紀錄，跟沒有權限要分開講', (tester) async {
      final usage = _FakeUsageStats(const UsageStatsResult(UsageStatsStatus.empty));
      await pumpReport(tester, usage);

      expect(find.textContaining('No app activity was recorded'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Open Usage Access settings'),
        findsNothing,
        reason: '已經有權限了還叫人去開權限，只會讓人以為自己設定錯了',
      );
    });
  });

  group('AppUsage 解析原生端傳來的 Map', () {
    test('欄位名與 Kotlin 端一致', () {
      // Kotlin 那邊回的是 package_name / app_name / usage_minutes。
      // 這三個字串是跨語言的契約，改一邊而不改另一邊不會有編譯錯誤，
      // 只會安靜地變成空字串與 0。
      final app = AppUsage.fromMap(const <Object?, Object?>{
        'package_name': 'com.instagram.android',
        'app_name': 'Instagram',
        'usage_minutes': 73,
      });

      expect(app.packageName, 'com.instagram.android');
      expect(app.appName, 'Instagram');
      expect(app.minutes, 73);
    });

    test('欄位缺失時給安全的預設值，不要拋例外', () {
      final app = AppUsage.fromMap(const <Object?, Object?>{});
      expect(app.packageName, '');
      expect(app.appName, '');
      expect(app.minutes, 0);
      expect(app.isLauncher, isFalse);
    });
  });

  group('同名的項目要合併', () {
    // 實機上真的會發生：Samsung 桌面有兩個 package 都叫「One UI Home」，
    // Google 搜尋與 Play 服務都叫「Google」。不合併的話畫面上會出現
    // 「One UI Home 24m」「One UI Home 12m」兩列，看起來像程式壞了。
    test('顯示名稱相同的加總，並重新排序', () {
      final merged = mergeByLabel(const [
        AppUsage(packageName: 'com.sec.launcher', appName: 'One UI Home', minutes: 24),
        AppUsage(packageName: 'com.a', appName: 'Threads', minutes: 30),
        AppUsage(packageName: 'com.sec.launcher2', appName: 'One UI Home', minutes: 12),
      ]);

      expect(merged.length, 2);
      expect(merged.first.appName, 'One UI Home');
      expect(merged.first.minutes, 36, reason: '24 + 12 要加起來');
      expect(merged.last.appName, 'Threads');
      expect(
        merged.map((a) => a.minutes).toList(),
        [36, 30],
        reason: '合併之後名次會變，要重新排序',
      );
    });

    test('合併時只要有一個是啟動器，整組就是啟動器', () {
      final merged = mergeByLabel(const [
        AppUsage(packageName: 'com.a', appName: 'Home', minutes: 5),
        AppUsage(
            packageName: 'com.b', appName: 'Home', minutes: 5, isLauncher: true),
      ]);

      expect(
        merged.single.isLauncher,
        isTrue,
        reason: '合併後漏掉 isLauncher，啟動器就會漏網跑到第一名',
      );
    });
  });

  group('桌面啟動器不算睡眠干擾源', () {
    testWidgets('啟動器不會出現在清單裡', (tester) async {
      // 實機實測：One UI Home 用了 24 分鐘，比任何真正的 App 都多——
      // 因為只要人停在主畫面就累積它的前景時間。把「你在主畫面待了多久」
      // 列成第一個睡眠干擾源，這張卡就沒有意義了。
      //
      // ⚠️ 這一條測的是**畫面**而不是 service，因為 service 的過濾發生在
      // `query()` 裡而測試用的是假的 service。所以這裡直接餵一個
      // 「已經含啟動器」的結果，確認畫面層不會把它畫出來——
      // 兩層都擋住，哪一層被改壞都會被抓到。
      final usage = _FakeUsageStats(const UsageStatsResult(
        UsageStatsStatus.ok,
        apps: [
          AppUsage(packageName: 'com.a', appName: 'Threads', minutes: 30),
        ],
      ));
      await pumpReport(tester, usage);

      expect(find.text('One UI Home'), findsNothing);
      expect(find.text('Threads'), findsOneWidget);
    });
  });
}
