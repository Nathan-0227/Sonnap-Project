import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/sleep_session.dart';

/// 這一份資料是從哪裡來的。
///
/// 這個值**必須讓使用者看得到**（Insights 頁的 Tracking Sources 卡）。
/// 理由見 [FallbackSleepRepository]：安靜地顯示過期資料，比明確地報錯更糟。
enum SleepDataSource {
  /// 打包進 APK 的 `assets/data/app_payload.json`。永遠可用，但凍結在 build 當下。
  asset,

  /// 後端 `GET /get-sleep-data`。跟著 pipeline 走，重跑就有新資料。
  api,
}

/// 取得睡眠資料的介面。
///
/// 之所以先抽介面，是因為要在「打包的 asset」與「打 API」之間切換時
/// UI 一行都不用動。三個畫面（Home / Insights / Assistant）都吃這個型別。
abstract class SleepRepository {
  Future<SleepSession> load();
}

/// 從 App 打包進去的 asset 讀資料。
///
/// **這是保底路徑，永遠可用。** 選它當退路的理由：
/// - `rootBundle` 與 `dart:convert` 都是內建，不讓 `pubspec.yaml` 多任何套件
/// - Demo 時什麼都不用開，飛航模式也能跑
/// - 不必處理模擬器 10.0.2.2 / 實機區網 IP / 防火牆 / CORS 那一整組問題
///
/// 代價：資料凍結在 build 當下，要更新就得重新 build。
///
/// 這個檔案由 `python garmin/run_pipeline.py` 產生，而且 **main.py 對外服務的
/// 是同一個檔案**——所以 App 顯示的內容跟 API 回傳的內容結構上不可能不一致。
class AssetSleepRepository implements SleepRepository {
  static const String assetPath = 'assets/data/app_payload.json';

  const AssetSleepRepository();

  @override
  Future<SleepSession> load() async {
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('app_payload.json 的根節點不是物件');
    }

    final session = SleepSession.fromJson(decoded);

    // ⚠️ 只印一行摘要。先前這裡用 `print()` 把**整份 payload** 倒進 logcat，
    // 那份資料含使用者每一晚的入睡時間、起床時間與分數——除錯時方便，
    // 但那是把個人生理資料寫進一個裝了 adb 就讀得到的地方。
    // 改用 debugPrint 還有一個好處：release build 會整段被移除。
    debugPrint(
      'SleepRepository[asset]: ${session.sessionId}, '
      '${session.history.length} nights',
    );
    return session;
  }
}

/// 從後端 `GET /get-sleep-data` 取資料。
///
/// ## 為什麼用 `dart:io` 的 HttpClient，不裝 `package:http`
///
/// 延續專案「優先用標準庫，非必要不用套件」的既有原則——`ai/llm_client.py`
/// 用 `urllib.request` 打 Claude API 而不裝 SDK，是同一個理由。這裡只需要
/// 一個 GET 和一次 JSON 解析，多一個相依換不到任何東西。
///
/// ⚠️ 代價：`dart:io` 在 **Flutter Web 上不能用**。這個專案出的是 APK，
/// 所以沒有影響；真的要支援 web 時再換成 `package:http`。
///
/// ## baseUrl 怎麼給
///
/// 建置時用 `--dart-define` 帶入，不寫死在程式裡：
///
/// ```
/// flutter build apk --dart-define=SONNAP_API_BASE=http://192.168.1.23:8000
/// ```
///
/// ⚠️ **實機不能用 `localhost`**——那會指向手機自己。要用開發機在區網上的 IP，
/// 而且兩台要在同一個 WiFi。Android 模擬器則是 `http://10.0.2.2:8000`。
class ApiSleepRepository implements SleepRepository {
  final String baseUrl;

  /// 短一點。這個 timeout 是「demo 當場等多久才放棄」，不是「網路有多慢」——
  /// 後端沒開的時候要立刻退到 asset，不能讓畫面卡在轉圈圈。
  final Duration timeout;

  const ApiSleepRepository({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 3),
  });

  /// `--dart-define=SONNAP_API_BASE=...`。沒給就是空字串 = 不啟用 API。
  static const String defineKey = 'SONNAP_API_BASE';
  static const String configuredBaseUrl =
      String.fromEnvironment(defineKey, defaultValue: '');

  @override
  Future<SleepSession> load() async {
    final uri = Uri.parse('$baseUrl/get-sleep-data');
    final client = HttpClient()..connectionTimeout = timeout;

    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);

      if (response.statusCode != 200) {
        // 503 是後端刻意的：資料檔還沒產生。把它跟其他錯誤分開講，
        // 因為解法完全不同（跑 pipeline vs 檢查網路）。
        final hint = response.statusCode == 503
            ? 'the backend has no payload yet - run `python garmin/run_pipeline.py`'
            : 'unexpected status';
        throw HttpException(
          'GET $uri returned ${response.statusCode} ($hint)',
          uri: uri,
        );
      }

      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);

      if (decoded is! Map<String, dynamic>) {
        throw FormatException('$uri 回傳的根節點不是物件');
      }

      final session = SleepSession.fromJson(decoded);
      debugPrint(
        'SleepRepository[api]: ${session.sessionId}, '
        '${session.history.length} nights from $baseUrl',
      );
      return session;
    } finally {
      client.close(force: true);
    }
  }
}

/// 先打 API，失敗就退回打包的 asset。
///
/// ## 這跟後端「不 fallback 回假資料」不衝突
///
/// `main.py` 的 `/get-sleep-data` 在資料檔不存在時回 503 而**不**給一份寫死的
/// mock，理由是「忘記跑 pipeline」不該看起來跟正常運作一樣。那條規則守的是
/// **不要拿假資料冒充真資料**。
///
/// 這裡退回 asset 不一樣：asset 裡是**真的資料**，只是可能過期。兩者的失敗
/// 模式不同，處置也該不同。
///
/// ⚠️ **但過期而不自知同樣是一種說謊**，所以 [lastSource] 必須顯示在畫面上。
/// 「明明後端沒開，使用者卻以為看到的是即時資料」正是這個設計要防的。
class FallbackSleepRepository implements SleepRepository {
  final SleepRepository primary;
  final SleepRepository fallback;

  FallbackSleepRepository({required this.primary, required this.fallback});

  /// 最近一次 [load] 實際用到的來源。
  ///
  /// ⚠️ 這是「最近一次」而不是「每次呼叫各自的結果」——三個畫面共用同一個
  /// repository 實例、各自載入，值會被後完成的那次覆蓋。因為三邊讀的是同一份
  /// 資料、結果會收斂到同一個值，對顯示來源而言夠用。要做到逐次精確就得改
  /// `load()` 的回傳型別，那會動到三個畫面，不值得。
  SleepDataSource lastSource = SleepDataSource.asset;

  /// API 失敗的原因，給 UI 顯示用。成功時是 null。
  String? lastPrimaryError;

  @override
  Future<SleepSession> load() async {
    try {
      final session = await primary.load();
      lastSource = SleepDataSource.api;
      lastPrimaryError = null;
      return session;
    } catch (error) {
      // 任何失敗都退到 asset：連不上、逾時、503、JSON 壞掉都算。
      // demo 當場最不能接受的就是「後端沒開所以整個 App 打不開」。
      lastSource = SleepDataSource.asset;
      lastPrimaryError = error.toString();
      debugPrint('SleepRepository: API failed, falling back to asset - $error');
      return fallback.load();
    }
  }
}

/// 依建置參數決定要用哪一種 repository。
///
/// 沒給 `--dart-define=SONNAP_API_BASE` 就直接回 [AssetSleepRepository]，
/// 行為與加上這一層之前**完全相同**——這是刻意的，讓「什麼都沒設定」
/// 仍然是那條最穩、demo 一定跑得起來的路徑。
SleepRepository buildSleepRepository({String? baseUrlOverride}) {
  final baseUrl =
      (baseUrlOverride ?? ApiSleepRepository.configuredBaseUrl).trim();

  if (baseUrl.isEmpty) {
    return const AssetSleepRepository();
  }

  return FallbackSleepRepository(
    primary: ApiSleepRepository(baseUrl: baseUrl),
    fallback: const AssetSleepRepository(),
  );
}
