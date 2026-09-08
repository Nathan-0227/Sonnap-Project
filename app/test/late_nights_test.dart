// 熬夜比率：服務層與 Insights 卡片。
//
// 這一組守三件**壞掉都不會報錯**的事：
//
//   1. **分母不是日曆天。** behavior/adherence.py 的 late_night_ratio()
//      刻意用「有測到資料的夜數」當分母——把沒資料的日子當成「沒熬夜」
//      數字會好看但沒有意義，當成「熬夜」則是憑空捏造。所以畫面上一定
//      要把分母講出來：40% 看起來像「30 天裡有 12 天」，實際上可能是
//      「5 晚裡有 2 晚」，而那兩件事的可信度差很遠。
//
//   2. **ratio == null 不是 0%。** 「還沒有任何一晚有記錄」與「一晚都
//      沒熬夜」在畫面上要講完全相反的話。解析成 0.0 就再也分不出來。
//
//   3. **這個服務不讀 /home 的 status 區塊。** 這個 App 裡「寵物心情」
//      只有一個來源（SleepRepository 的 payload）。多一個來源就會出現
//      首頁與 Insights 顯示兩隻不同寵物的情況，而且沒有任何錯誤訊息——
//      那正是 tests/test_history_mood.py 第 3 條在守的東西。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/sleep_session.dart';
import 'package:app/screens/report_screen.dart';
import 'package:app/services/home_service.dart';
import 'package:app/services/sleep_repository.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/lights_out.dart';
import 'package:app/services/pre_bed_apps.dart';
import 'package:app/services/usage_stats.dart';
import 'package:app/services/user_identity.dart';

const String testUserId = '00000000-5017-4e01-9a30-000000000001';

/// 照 main.py 的 /home 真實輸出寫的樣本（只留這一組用得到的部分，
/// 外加一個 status 區塊——第 3 條測試就是要證明我們沒有去讀它）。
const Map<String, dynamic> kHomeResponse = {
  'schema_version': 2,
  'date': '2026-09-01',
  'user': {
    'user_id': testUserId,
    'display_name': 'Nathan',
    'target_bedtime': '23:30',
  },
  'status': {
    'pet_mood': 'anxious',
    'energy_level': 41,
  },
  'behavior': {
    'target_bedtime': '23:30',
    'lights_out_at': '2026-09-01T03:51:16+08:00',
    'adherence_minutes': 261.0,
    'is_late': true,
    'source': 'phone',
    'late_night_ratio': 0.444,
    'late_nights': 12,
    'recorded_nights': 27,
  },
};

/// 還沒有任何一晚有記錄。後端這時回 null，不是 0。
const Map<String, dynamic> kEmptyHomeResponse = {
  'schema_version': 2,
  'date': null,
  'behavior': {
    'target_bedtime': '23:30',
    'lights_out_at': null,
    'late_night_ratio': null,
    'late_nights': 0,
    'recorded_nights': 0,
  },
};

class _FakeBackend {
  late final HttpServer server;
  final List<String> paths = [];
  int statusCode = 200;
  Map<String, dynamic> response = kHomeResponse;

  Future<String> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      paths.add(request.uri.toString());
      request.response.statusCode = statusCode;
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

/// 什麼都不回的使用時間服務——這兩組不驗那張卡。
///
/// ⚠️ **三個方法都要攔。** 少攔任何一個，widget test 就會打到真的
/// MethodChannel，而它在測試環境裡**永遠不會完成**——`_loadUsage()`
/// 整個卡在那個 await 上，後面的 `_loadChallenges()` / `_loadHome()`
/// 根本不會跑。症狀是「卡片整張不見」，錯誤訊息完全不指向這裡。
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

HomeResult _parsed([Map<String, dynamic> source = kHomeResponse]) => HomeResult(
      HomeStatus.ok,
      behavior: BehaviorSummary.fromJson(
        source['behavior'] as Map<String, dynamic>,
        windowDays: HomeService.historyDays,
      ),
    );

void main() {
  group('服務層', () {
    late _FakeBackend backend;
    late String baseUrl;
    HttpOverrides? savedOverrides;

    setUp(() async {
      // ⚠️ 同一個檔案裡有 testWidgets 就會裝上「一律回 400」的假 HttpClient。
      //    見 account_test.dart 那一大段註解。
      savedOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      backend = _FakeBackend();
      baseUrl = await backend.start();
    });
    tearDown(() async {
      await backend.stop();
      HttpOverrides.global = savedOverrides;
    });

    test('GET /home?user_id=...，behavior 區塊解析得出來', () async {
      final service = HomeService(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      );
      final result = await service.fetch();

      expect(result.status, HomeStatus.ok);
      expect(backend.paths.single, contains('/home'));
      expect(backend.paths.single, contains('user_id=$testUserId'));
      expect(result.behavior!.lateNightRatio, 0.444);
      expect(result.behavior!.lateNights, 12);
      expect(result.behavior!.recordedNights, 27);
    });

    test('沒有一晚有記錄 → ratio 是 null 而不是 0', () async {
      backend.response = kEmptyHomeResponse;
      final service = HomeService(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      );
      final result = await service.fetch();

      expect(
        result.behavior!.lateNightRatio,
        isNull,
        reason: '解析成 0.0 的話，畫面會恭喜一個我們根本沒測到的人',
      );
      expect(result.behavior!.recordedNights, 0);
    });

    test('完全不讀 status 區塊——拿掉它照樣成功', () async {
      // 這個 App 裡「寵物心情」只有一個來源（repository 的 payload）。
      // 這一條證明 HomeService 沒有偷偷變成第二個來源：整個 status
      // 拿掉都不影響它。
      backend.response = {
        'schema_version': 2,
        'behavior': kHomeResponse['behavior'],
      };
      final service = HomeService(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      );
      final result = await service.fetch();

      expect(result.status, HomeStatus.ok);
      expect(result.behavior!.lateNights, 12);
    });

    test('沒有 behavior 區塊 → failed，不假裝成 0 晚', () async {
      backend.response = const {'schema_version': 2};
      final service = HomeService(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      );
      expect((await service.fetch()).status, HomeStatus.failed);
    });

    test('後端回錯就是 failed', () async {
      backend.statusCode = 404;
      final service = HomeService(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      );
      final result = await service.fetch();
      expect(result.status, HomeStatus.failed);
      expect(result.behavior, isNull);
    });
  });

  group('拿不到的原因要分得開', () {
    test('沒設定後端 → noBackend', () async {
      const service = HomeService(
        baseUrl: '',
        identity: BuildTimeUserIdentity(overrideId: testUserId),
      );
      expect((await service.fetch()).status, HomeStatus.noBackend);
    });

    test('沒建帳號 → noUser', () async {
      const service = HomeService(
        baseUrl: 'http://127.0.0.1:1',
        identity: BuildTimeUserIdentity(overrideId: ''),
      );
      expect((await service.fetch()).status, HomeStatus.noUser);
    });

    test('沒給 API base 就不建 service', () {
      expect(buildHomeService(baseUrlOverride: ''), isNull);
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
          // ⚠️ 預設是 PlatformKeyValueStore，在 widget test 裡永遠不回應。
          bedMarks: BedMarkStore(InMemoryKeyValueStore()),
          home: home,
        ),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('比率與分母都顯示出來', (tester) async {
      await pump(tester, _StubHome(_parsed()));

      expect(find.text('44%'), findsOneWidget);
      expect(
        find.text('late on 12 of 27 recorded nights'),
        findsOneWidget,
        reason: '沒有分母的話，44% 看起來像「30 天裡有 13 天」，'
            '但它也可能是「5 晚裡有 2 晚」',
      );
    });

    testWidgets('那句「不是日曆天」的說明一定要在', (tester) async {
      await pump(tester, _StubHome(_parsed()));
      expect(
        find.textContaining('not over calendar days'),
        findsOneWidget,
        reason: '分母的意義本身就是這張卡最容易被誤讀的地方',
      );
    });

    testWidgets('沒有記錄 → 說「還沒有」，不得畫成 0%', (tester) async {
      await pump(tester, _StubHome(_parsed(kEmptyHomeResponse)));

      expect(find.textContaining('No nights recorded yet'), findsOneWidget);
      expect(
        find.text('0%'),
        findsNothing,
        reason: '0% 的意思是「你一晚都沒熬夜」——那是在恭喜一個我們根本'
            '沒測到的人',
      );
    });

    testWidgets('拿不到就整張卡不出現', (tester) async {
      await pump(tester, const _StubHome(HomeResult(HomeStatus.failed)));
      expect(find.text('Late Nights'), findsNothing);
    });

    testWidgets('連不上但手上還有上一次的數字 → 也不顯示', (tester) async {
      // ⚠️ 這一條才是「只看 behavior != null 就畫」會漏掉的情況。
      //    連不上時把上次的比率繼續掛在畫面上，使用者會以為那是今天的。
      await pump(
        tester,
        _StubHome(HomeResult(
          HomeStatus.failed,
          behavior: _parsed().behavior,
        )),
      );
      expect(find.text('Late Nights'), findsNothing);
      expect(find.text('44%'), findsNothing);
    });

    testWidgets('沒有後端的 build 完全不受影響', (tester) async {
      await pump(tester, null);
      expect(find.text('Late Nights'), findsNothing);
    });
  });
}
