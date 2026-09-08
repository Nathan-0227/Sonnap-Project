// 挑戰進度：服務層與 Insights 卡片。
//
// 這一組守的是三件**壞掉都不會報錯**的事——每一條在後端都有對應的
// 一段推理，Dart 這邊只要「照直覺重寫一次」就會安靜地講錯話：
//
//   1. **進度不是 Dart 算的。** consistency 那一項的進度是
//      `目標 ÷ 實際`（比值），不是線性遞減；照直覺從 current/target
//      重算會得到完全不同的數字，而畫面看起來一樣正常。
//
//   2. **insufficient_data 不是 0%。** 後端刻意把「還不知道」與
//      「完全沒進展」分開（challenges.py 的 evaluate_challenge：
//      current_value is None 才是 insufficient_data）。畫成一條空的
//      進度條，使用者會以為自己表現很差，而事實是我們還沒收到他的資料。
//
//   3. **recorded_nights 一定要顯示當分母。** challenges.py:400 明寫
//      理由：沒有它，「達成 3 晚」看不出是 3/3 還是 3/14。
//
// 服務層用真的 HttpServer 起在 127.0.0.1，因為要驗的是「解析後端真的
// 回過來的東西」——用假的 client 就等於在測自己寫的假物件。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/sleep_session.dart';
import 'package:app/screens/report_screen.dart';
import 'package:app/services/challenges_service.dart';
import 'package:app/services/sleep_repository.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/lights_out.dart';
import 'package:app/services/pre_bed_apps.dart';
import 'package:app/services/usage_stats.dart';
import 'package:app/services/user_identity.dart';

const String testUserId = '00000000-5017-4e01-9a30-000000000001';

/// 一份照 behavior/challenges.py 的 evaluate_challenge() 真實輸出寫的樣本。
/// 三個挑戰剛好蓋到三種狀態。
const Map<String, dynamic> kSampleResponse = {
  'user_id': testUserId,
  'as_of': null,
  'challenges': [
    {
      'challenge_id': 'on_time_tonight',
      'kind': 'time',
      'title': 'Lights out on time',
      'description': 'Put your phone down before your target bedtime tonight.',
      'target_value': 0.0,
      'window_days': 1,
      'current_value': -12.0,
      'achieved_days': 1,
      'recorded_nights': 1,
      'progress': 1.0,
      'lower_is_better': false,
      'completed': true,
      'status': 'completed',
      'detail': 'Put your phone down 12 min early.',
    },
    {
      'challenge_id': 'streak_nights',
      'kind': 'streak',
      'title': 'Three nights in a row',
      'description': 'Put your phone down before your target bedtime three nights running.',
      'target_value': 3.0,
      'window_days': 14,
      'current_value': 1.0,
      'achieved_days': 1,
      'recorded_nights': 9,
      'progress': 0.333,
      'lower_is_better': false,
      'completed': false,
      'status': 'in_progress',
      'detail': '1 night(s) so far - 2 more to finish.',
    },
    {
      'challenge_id': 'bedtime_consistency_7d',
      'kind': 'consistency',
      'title': 'Steady bedtime',
      'description': 'Keep the last 7 bedtimes within 60 minutes of your own average.',
      'target_value': 60.0,
      'window_days': 7,
      // ⚠️ 這一項是**唯一能分辨「有沒有在 Dart 重算」的樣本**。
      //    後端用的是「目標 ÷ 實際」= 60/90 = 0.667。
      //    照直覺從 current/target 重算會得到 90/60 = 1.5 → 截成 100%。
      //    streak 那一項（1/3）兩種算法剛好一樣，分辨不出來。
      'current_value': 90.0,
      'achieved_days': 6,
      'recorded_nights': 6,
      'progress': 0.667,
      'lower_is_better': true,
      'completed': false,
      'status': 'in_progress',
      'detail': 'Bedtimes over the last 6 nights varied by up to 90 min from '
          'your average; the target is within 60 min.',
    },
  ],
};

/// 同一份，但作息收斂那一項還沒有足夠的夜數——後端回 insufficient_data。
const Map<String, dynamic> kSparseResponse = {
  'user_id': testUserId,
  'as_of': null,
  'challenges': [
    {
      'challenge_id': 'bedtime_consistency_7d',
      'kind': 'consistency',
      'title': 'Steady bedtime',
      'description': 'Keep the last 7 bedtimes within 60 minutes of your own average.',
      'target_value': 60.0,
      'window_days': 7,
      'current_value': null,
      'achieved_days': 0,
      'recorded_nights': 2,
      'progress': null,
      'lower_is_better': true,
      'completed': false,
      'status': 'insufficient_data',
      'detail': 'Only 2 of the last 7 nights have records; at least 4 are needed '
          'to measure consistency.',
    },
  ],
};

class _FakeBackend {
  late final HttpServer server;
  final List<String> paths = [];
  int statusCode = 200;
  Map<String, dynamic> response = kSampleResponse;

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

/// 直接回一份固定結果，不碰 HTTP。widget test 要驗的是「拿到之後怎麼畫」。
class _StubChallenges implements ChallengesService {
  final ChallengesResult result;
  const _StubChallenges(this.result);

  @override
  Future<ChallengesResult> fetch() async => result;

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

ChallengesResult _parsed([Map<String, dynamic> source = kSampleResponse]) =>
    ChallengesResult(
      ChallengesStatus.ok,
      challenges: (source['challenges'] as List)
          .cast<Map<String, dynamic>>()
          .map(ChallengeProgress.fromJson)
          .toList(),
    );

void main() {
  group('服務層：照抄後端，不重算', () {
    late _FakeBackend backend;
    late String baseUrl;
    HttpOverrides? savedOverrides;

    setUp(() async {
      // ⚠️ 不能省。TestWidgetsFlutterBinding 會把全域 HttpClient 換成
      //    「一律回 400」的假實作，而這個檔案底下有 testWidgets，
      //    所以整個檔案都會裝上它。症狀是連 127.0.0.1:1 都「成功」拿到
      //    400 而不是 SocketException，錯誤訊息完全不指向 HttpOverrides。
      savedOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      backend = _FakeBackend();
      baseUrl = await backend.start();
    });
    tearDown(() async {
      await backend.stop();
      HttpOverrides.global = savedOverrides;
    });

    test('GET /challenges?user_id=...，三個挑戰都解析得出來', () async {
      final service = ChallengesService(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      );
      final result = await service.fetch();

      expect(result.status, ChallengesStatus.ok);
      expect(result.challenges, hasLength(3));
      expect(backend.paths.single, contains('/challenges'));
      expect(backend.paths.single, contains('user_id=$testUserId'));
    });

    test('progress 照抄後端的數字，不從 current/target 自己算', () async {
      // streak：current 1、target 3。後端回 0.333。
      // consistency 那一項後端用的是「目標 ÷ 實際」而不是線性遞減——
      // 在 Dart 照直覺重算，這兩個數字都會不一樣。
      final service = ChallengesService(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      );
      final result = await service.fetch();

      final streak = result.challenges[1];
      expect(streak.progress, 0.333);
    });

    test('consistency 的 progress 是 60/90 而不是 90/60', () async {
      // 這一條是紅線 1 真正的守門員。後端用比值（目標 ÷ 實際），
      // 照直覺重算會得到 1.5 → 畫面上顯示 100%，而使用者其實沒達成。
      final service = ChallengesService(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      );
      final result = await service.fetch();

      expect(result.challenges[2].progress, 0.667);
      expect(result.challenges[2].lowerIsBetter, isTrue);
    });

    test('detail 是後端寫好的整句，不是 Dart 組的', () async {
      final service = ChallengesService(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      );
      final result = await service.fetch();

      expect(
        result.challenges[1].detail,
        '1 night(s) so far - 2 more to finish.',
      );
    });

    test('insufficient_data → progress 是 null 而不是 0', () async {
      backend.response = kSparseResponse;
      final service = ChallengesService(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      );
      final result = await service.fetch();

      final consistency = result.challenges.single;
      expect(consistency.state, ChallengeState.insufficientData);
      expect(
        consistency.progress,
        isNull,
        reason: '解析成 0.0 的話，UI 就再也分不出「還不知道」與「完全沒進展」',
      );
    });

    test('不認得的 status 退到 insufficientData，不是 inProgress', () async {
      // 後端之後多加一種狀態而這裡沒跟上時，寧可說「還沒有資料」，
      // 也不要畫出一條可能是假的進度條。
      final parsed = ChallengeProgress.fromJson(const {
        'challenge_id': 'x',
        'status': 'something_new',
        'progress': 0.5,
      });
      expect(parsed.state, ChallengeState.insufficientData);
    });

    test('後端回錯就是 failed，不假裝成空清單', () async {
      backend.statusCode = 404;
      final service = ChallengesService(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      );
      final result = await service.fetch();

      expect(result.status, ChallengesStatus.failed);
      expect(result.challenges, isEmpty);
    });
  });

  group('服務層：拿不到的三種原因要分得開', () {
    test('沒設定後端 → noBackend', () async {
      const service = ChallengesService(
        baseUrl: '',
        identity: BuildTimeUserIdentity(overrideId: testUserId),
      );
      expect((await service.fetch()).status, ChallengesStatus.noBackend);
    });

    test('沒建帳號 → noUser（不是 failed）', () async {
      const service = ChallengesService(
        baseUrl: 'http://127.0.0.1:1',
        identity: BuildTimeUserIdentity(overrideId: ''),
      );
      expect((await service.fetch()).status, ChallengesStatus.noUser);
    });

    test('沒給 API base 就不建 service', () {
      expect(buildChallengesService(baseUrlOverride: ''), isNull);
    });
  });

  group('卡片：三條紅線', () {
    late SleepSession sample;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      sample = await const AssetSleepRepository().load();
    });

    Future<void> pump(WidgetTester tester, ChallengesService? challenges) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: ReportScreen(
          repository: _ImmediateRepository(sample),
          usageStats: const _SilentUsageStats(),
          // ⚠️ 預設是 PlatformKeyValueStore，在 widget test 裡永遠不回應。
          bedMarks: BedMarkStore(InMemoryKeyValueStore()),
          challenges: challenges,
        ),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('三個挑戰的標題都出現', (tester) async {
      await pump(tester, _StubChallenges(_parsed()));
      expect(find.text('Lights out on time'), findsOneWidget);
      expect(find.text('Three nights in a row'), findsOneWidget);
      expect(find.text('Steady bedtime'), findsOneWidget);
    });

    testWidgets('紅線 2：insufficient_data 不得畫成 0%', (tester) async {
      await pump(tester, _StubChallenges(_parsed(kSparseResponse)));

      expect(
        find.text('not enough data yet'),
        findsOneWidget,
        reason: '「還不知道」要有自己的講法，不能跟「完全沒進展」共用一條空進度條',
      );
      expect(
        find.text('0%'),
        findsNothing,
        reason: '畫成 0% 就等於對使用者說「你表現很差」，而事實是我們還沒'
            '收到他的資料——兩者要講的話完全相反',
      );
    });

    testWidgets('紅線 3：recorded_nights 要當分母顯示出來', (tester) async {
      await pump(tester, _StubChallenges(_parsed()));

      expect(
        find.text('9/14 nights'),
        findsOneWidget,
        reason: '沒有分母的話，「連續 1 晚」看不出是 1/1 還是 1/14',
      );
      expect(find.text('6/7 nights'), findsOneWidget);
    });

    testWidgets('紅線 1：百分比照抄後端，不是 Dart 從 current/target 算的',
        (tester) async {
      // 作息收斂：離散 90 分、目標 60 分。
      //   後端（目標 ÷ 實際）→ 0.667 → **67%，而且沒達成**
      //   照直覺（實際 ÷ 目標）→ 1.5   → 截成 100%，看起來達成了
      // 兩個數字差這麼多，而畫面上長得一樣正常——這就是為什麼進度
      // 一格都不能在 Dart 算。
      // 只放這一項——「準時上床」那一項真的達成了、本來就顯示 100%，
      // 放在一起的話下面那條 findsNothing 會撞到它。
      await pump(
        tester,
        _StubChallenges(ChallengesResult(
          ChallengesStatus.ok,
          challenges: [_parsed().challenges[2]],
        )),
      );
      expect(find.text('67%'), findsOneWidget);
      expect(
        find.text('100%'),
        findsNothing,
        reason: '90 分的離散度沒有達成 60 分的目標，不該顯示 100%',
      );
    });

    testWidgets('後端回的那句 detail 原樣顯示', (tester) async {
      await pump(tester, _StubChallenges(_parsed()));
      expect(find.text('1 night(s) so far - 2 more to finish.'), findsOneWidget);
      expect(
        find.text(
          'Bedtimes over the last 6 nights varied by up to 90 min from '
          'your average; the target is within 60 min.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('拿不到就整張卡不出現，不畫一張空的', (tester) async {
      await pump(
        tester,
        const _StubChallenges(ChallengesResult(ChallengesStatus.failed)),
      );
      expect(
        find.text('Challenges'),
        findsNothing,
        reason: '顯示一張空的或上次的，會讓人以為那是今天的進度',
      );
    });

    testWidgets('沒有後端的 build 完全不受影響', (tester) async {
      await pump(tester, null);
      expect(find.text('Challenges'), findsNothing);
    });
  });
}
