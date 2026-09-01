// 後端連不上時退回打包的 asset——但**必須留下痕跡**。
//
// 這一組守的是一個很容易寫壞的東西：fallback 本身好寫，難的是「退了之後
// 有沒有人知道」。如果 lastSource 沒有被正確設定，畫面就會顯示過期資料
// 卻標示成即時的——那比整個壞掉更糟，因為沒有任何跡象。
//
// ⚠️ 這跟後端 `/get-sleep-data` 在沒有資料時回 503 而不給 mock 並不衝突：
// 後端守的是「不要拿假資料冒充真資料」；這裡退回的 asset 是**真資料**，
// 只是可能過期。兩種失敗模式不同，處置也不同。

import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/sleep_session.dart';
import 'package:app/services/sleep_repository.dart';

/// 永遠成功的假 repository。回傳的內容不重要，測的是「走了哪一條路」。
class _StubRepository implements SleepRepository {
  final SleepSession session;
  int loadCount = 0;

  _StubRepository(this.session);

  @override
  Future<SleepSession> load() async {
    loadCount++;
    return session;
  }
}

/// 永遠失敗的假 repository，模擬後端沒開。
class _FailingRepository implements SleepRepository {
  final Object error;
  int loadCount = 0;

  _FailingRepository(this.error);

  @override
  Future<SleepSession> load() async {
    loadCount++;
    throw error;
  }
}

void main() {
  // 用真的 asset 產生一個 SleepSession，省得手刻整份 payload
  late SleepSession sample;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sample = await const AssetSleepRepository().load();
  });

  test('API 成功時用 API，並記錄來源是 api', () async {
    final primary = _StubRepository(sample);
    final fallback = _StubRepository(sample);
    final repo = FallbackSleepRepository(primary: primary, fallback: fallback);

    await repo.load();

    expect(repo.lastSource, SleepDataSource.api);
    expect(repo.lastPrimaryError, isNull);
    expect(primary.loadCount, 1);
    expect(
      fallback.loadCount,
      0,
      reason: 'API 成功時不該再去讀 asset',
    );
  });

  test('API 失敗時退回 asset，而且來源要標成 asset', () async {
    final primary = _FailingRepository(Exception('connection refused'));
    final fallback = _StubRepository(sample);
    final repo = FallbackSleepRepository(primary: primary, fallback: fallback);

    final session = await repo.load();

    expect(session.sessionId, sample.sessionId);
    expect(
      repo.lastSource,
      SleepDataSource.asset,
      reason: '退回 asset 卻仍標示成 api，畫面就會把過期資料說成即時資料——'
          '那比整個壞掉更糟，因為沒有任何跡象',
    );
    expect(fallback.loadCount, 1);
  });

  test('退回時要留下失敗原因，不能靜靜吞掉', () async {
    final repo = FallbackSleepRepository(
      primary: _FailingRepository(Exception('SocketException: refused')),
      fallback: _StubRepository(sample),
    );

    await repo.load();

    expect(repo.lastPrimaryError, isNotNull);
    expect(repo.lastPrimaryError, contains('refused'));
  });

  test('先失敗後成功，來源要跟著改回 api', () async {
    // 只在第一次失敗的 primary
    var calls = 0;
    final repo = FallbackSleepRepository(
      primary: _ConditionalRepository(() {
        calls++;
        if (calls == 1) throw Exception('backend was still starting');
        return sample;
      }),
      fallback: _StubRepository(sample),
    );

    await repo.load();
    expect(repo.lastSource, SleepDataSource.asset);

    await repo.load();
    expect(
      repo.lastSource,
      SleepDataSource.api,
      reason: '後端起來之後仍顯示 asset，使用者會以為一直沒連上',
    );
    expect(repo.lastPrimaryError, isNull);
  });

  test('沒設定 API base URL 時，行為與加這一層之前完全相同', () {
    // 「什麼都沒設定」必須仍然是那條最穩、demo 一定跑得起來的路徑
    expect(buildSleepRepository(baseUrlOverride: ''), isA<AssetSleepRepository>());
    expect(
      buildSleepRepository(baseUrlOverride: '   '),
      isA<AssetSleepRepository>(),
      reason: '只有空白的設定值等同沒設定，不該當成一個網址去連',
    );
  });

  test('有設定 base URL 時才包上 fallback 那一層', () {
    final repo = buildSleepRepository(baseUrlOverride: 'http://10.0.2.2:8000');
    expect(repo, isA<FallbackSleepRepository>());

    final fallback = repo as FallbackSleepRepository;
    expect(fallback.primary, isA<ApiSleepRepository>());
    expect(
      fallback.fallback,
      isA<AssetSleepRepository>(),
      reason: '退路一定要是 asset——那是唯一保證存在的資料來源',
    );
    expect(
      fallback.lastSource,
      SleepDataSource.asset,
      reason: '還沒載入過就宣稱資料來自 API 是說謊',
    );
  });
}

/// 由呼叫端決定每次要成功還是失敗。
class _ConditionalRepository implements SleepRepository {
  final SleepSession Function() behaviour;

  _ConditionalRepository(this.behaviour);

  @override
  Future<SleepSession> load() async => behaviour();
}
