// 手錶實測的睡眠效率（`GET /home` 的 `behavior.measured_efficiency`）。
//
// 這一組守四件**壞掉都不會報錯**的事：
//
//   1. **算不出來不是 0%。** 要同時有手錶資料與「開始／結束睡覺」兩個
//      按鈕才算得出來，所以 null 是常態。畫成 0% 等於告訴一個我們根本
//      沒量到的人「你整夜沒睡著」。
//   2. **那句「不計分」必須照抄後端。** 這個 App 裡有四個東西叫「睡眠
//      效率」，其中手錶自己那個 2026-10-01 起已經停止計分。這一個也不
//      計分——在 Dart 把它改寫成「參考值」就等於自己發明了一種說法。
//   3. **basis 不能省。** 四個「效率」只有 basis 分得開它們；只讀數字
//      的人會拿它去比另外三個。
//   4. **Dart 不重算這個百分比。** 分子在 wearable_nightly、分母在
//      nightly_behavior，後端讀取時才 join（兩張表寫入時機不固定）。
//      在 Dart 乘一次就有第二個定義處，而兩份漂移時不會有錯誤訊息。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/sleep_session.dart';
import 'package:app/screens/report_screen.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/home_service.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/lights_out.dart';
import 'package:app/services/pre_bed_apps.dart';
import 'package:app/services/sleep_repository.dart';
import 'package:app/services/usage_stats.dart';
import 'package:app/services/user_identity.dart';

const String testUserId = '00000000-5017-4e01-9a30-000000000001';

/// 後端 `behavior/sleep_efficiency.py` 的原文（算得出來的情況）。
/// ⚠️ 照抄，不要在測試裡改寫——這條測試的意義就是「畫面上的字來自後端」。
const String kOkNote =
    "Watch-measured total sleep divided by the user's own 'going to sleep' "
    "to 'got up' window (time attempting to sleep). Presentation only - it "
    "never feeds the sleep score.";

/// 算不出來時後端給的原因（最常見的那一個：沒按按鈕）。
const String kNoMarksNote =
    'no bed_start/bed_end: the user did not mark getting into or out of bed';

/// 有數字的那一晚。91.7% 是 2026-09-13 的實測值（480 分 ÷ 523.4 分）。
const Map<String, dynamic> kHomeWithEfficiency = {
  'schema_version': 2,
  'date': '2026-09-13',
  'behavior': {
    'late_night_ratio': 0.444,
    'late_nights': 12,
    'recorded_nights': 27,
    'measured_efficiency': 91.7,
    'measured_efficiency_basis': 'watch_tst__phone_tats',
    'measured_efficiency_note': kOkNote,
  },
};

/// 沒按按鈕的那一晚：後端回 **null** 並附上原因。
const Map<String, dynamic> kHomeWithoutMarks = {
  'schema_version': 2,
  'date': '2026-09-14',
  'behavior': {
    'late_night_ratio': 0.444,
    'late_nights': 12,
    'recorded_nights': 27,
    'measured_efficiency': null,
    'measured_efficiency_basis': 'watch_tst__phone_tats',
    'measured_efficiency_note': kNoMarksNote,
  },
};

/// 舊版後端：根本沒有這三個欄位。
const Map<String, dynamic> kHomeOldBackend = {
  'schema_version': 2,
  'date': '2026-09-01',
  'behavior': {
    'late_night_ratio': 0.444,
    'late_nights': 12,
    'recorded_nights': 27,
  },
};

class _FakeBackend {
  late final HttpServer server;
  final List<String> paths = [];
  Map<String, dynamic> response = kHomeWithEfficiency;

  Future<String> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      paths.add(request.uri.toString());
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    return 'http://127.0.0.1:${server.port}';
  }

  Future<void> stop() => server.close(force: true);
}

class _ImmediateRepository implements SleepRepository {
  final SleepSession session;
  const _ImmediateRepository(this.session);

  @override
  Future<SleepSession> load() async => session;
}

class _StubHome implements HomeService {
  final HomeResult result;
  const _StubHome(this.result);

  @override
  Future<HomeResult> fetch() async => result;

  @override
  String get baseUrl => 'stub';

  @override
  UserIdentity get identity => const BuildTimeUserIdentity(overrideId: 'stub');

  @override
  Duration get timeout => const Duration(seconds: 1);
}

/// ⚠️ 三個方法都要攔，少攔一個就會打到真的 MethodChannel，而它在測試
/// 環境裡**永遠不會完成**——`_loadHome()` 根本不會跑，症狀是「整張卡不見」
/// 而錯誤訊息完全不指向這裡（照抄 `late_nights_test.dart` 的說明）。
class _SilentUsageStats extends UsageStatsService {
  const _SilentUsageStats();

  @override
  Future<UsageStatsResult> queryYesterday({int limit = 5}) async =>
      const UsageStatsResult(UsageStatsStatus.unsupported);

  @override
  Future<LightsOutResult> lightsOut({
    Duration window = kLightsOutWindow,
    int minQuietMinutes = kMinQuietMinutes,
    DateTime? now,
  }) async =>
      const LightsOutResult(LightsOutStatus.unsupported);

  @override
  Future<PreBedResult> preBed({
    required LightsOutResult lightsOut,
    Map<String, String> labels = const {},
    Duration window = kPreBedWindow,
  }) async =>
      const PreBedResult();
}

HomeResult _parsed(Map<String, dynamic> source) => HomeResult(
      HomeStatus.ok,
      behavior: BehaviorSummary.fromJson(
        source['behavior'] as Map<String, dynamic>,
        windowDays: HomeService.historyDays,
      ),
    );

void main() {
  group('【1】服務層', () {
    late _FakeBackend backend;
    late String baseUrl;
    HttpOverrides? savedOverrides;

    setUp(() async {
      // ⚠️ 同一個檔案裡有 testWidgets 就會裝上「一律回 400」的假 HttpClient。
      savedOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      backend = _FakeBackend();
      baseUrl = await backend.start();
    });
    tearDown(() async {
      await backend.stop();
      HttpOverrides.global = savedOverrides;
    });

    test('三個欄位都解析得出來', () async {
      final result = await HomeService(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      ).fetch();

      expect(result.status, HomeStatus.ok);
      expect(result.behavior!.measuredEfficiency, 91.7);
      expect(result.behavior!.measuredEfficiencyBasis, 'watch_tst__phone_tats');
      expect(result.behavior!.measuredEfficiencyNote, kOkNote);
    });

    test('⚠️ 算不出來時是 null，不是 0', () async {
      backend.response = kHomeWithoutMarks;
      final result = await HomeService(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      ).fetch();

      expect(result.behavior!.measuredEfficiency, isNull,
          reason: '解析成 0.0 之後就再也分不出「沒量到」與「整夜沒睡著」');
      expect(result.behavior!.measuredEfficiencyNote, kNoMarksNote,
          reason: '原因要留著——沒按按鈕是使用者唯一改得了的事');
    });
  });

  group('卡片', () {
    late SleepSession sample;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      sample = await const AssetSleepRepository().load();
    });

    Future<void> pump(WidgetTester tester, HomeService? home) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: ReportScreen(
          repository: _ImmediateRepository(sample),
          usageStats: const _SilentUsageStats(),
          bedMarks: BedMarkStore(InMemoryKeyValueStore()),
          home: home,
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
    }

    testWidgets('【2】有數字 → 百分比照抄（不四捨五入掉小數）', (tester) async {
      await pump(tester, _StubHome(_parsed(kHomeWithEfficiency)));

      expect(find.text('91.7%'), findsOneWidget,
          reason: '後端給 91.7，畫面就是 91.7——印成 92% 會讓人以為它比實際精確');
    });

    testWidgets('【3】那句「不計分」與 basis 都必須在', (tester) async {
      await pump(tester, _StubHome(_parsed(kHomeWithEfficiency)));

      expect(find.textContaining('never feeds the sleep score'), findsOneWidget,
          reason: '照抄後端。改寫成「參考值」就是自己發明了一種說法');
      expect(find.textContaining('time attempting to sleep'), findsOneWidget,
          reason: '分母是自述的那段窗，這句話是唯一講出來的地方');
      expect(find.textContaining('watch_tst__phone_tats'), findsOneWidget,
          reason: '四個「效率」只有 basis 分得開，省掉就會被拿去比另外三個');
    });

    testWidgets('【4】算不出來 → 說原因，**不得**出現 0%', (tester) async {
      await pump(tester, _StubHome(_parsed(kHomeWithoutMarks)));

      expect(find.textContaining('did not mark getting into or out of bed'),
          findsOneWidget,
          reason: '原因照抄後端；「沒按按鈕」與「沒戴錶」要分得開');
      expect(find.text('0.0%'), findsNothing);
      expect(find.text('0%'), findsNothing,
          reason: '0% 會被讀成「整夜沒睡著」，而真相是我們沒量到');
      // basis 在算不出來時照樣要有——那一列講的是「這個欄位是什麼」，
      // 不是「這一晚的值」。
      expect(find.textContaining('watch_tst__phone_tats'), findsOneWidget);
    });

    testWidgets('【5】舊版後端沒有這幾個欄位 → 整張卡不出現', (tester) async {
      await pump(tester, _StubHome(_parsed(kHomeOldBackend)));

      expect(find.text('Sleep Efficiency (measured)'), findsNothing,
          reason: '沒有 note 代表後端還沒有這個欄位，不是「這一晚沒有」');
    });

    testWidgets('【6】反向對照：沒有後端時整張卡不存在', (tester) async {
      await pump(tester, null);

      expect(find.text('Sleep Efficiency (measured)'), findsNothing,
          reason: '單機模式是預期行為，不是降級');
    });
  });
}
