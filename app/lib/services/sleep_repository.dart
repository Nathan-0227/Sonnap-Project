import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/sleep_session.dart';

/// 取得睡眠資料的介面。
///
/// 目前只有 asset 一種實作。之所以先抽介面，是因為之後要改成打 API 時
/// 只要換一個實作類別，UI 一行都不用動。
abstract class SleepRepository {
  Future<SleepSession> load();
}

/// 從 App 打包進去的 asset 讀資料。
///
/// **這是目前的預設路徑。** 選它的理由：
/// - `rootBundle` 與 `dart:convert` 都是 Flutter/Dart 內建，
///   **不會讓 pubspec.yaml 多任何一個套件**
/// - Demo 時什麼都不用開，飛航模式也能跑
/// - 不必處理模擬器 10.0.2.2 / 實機區網 IP / 防火牆 / CORS 那一整組問題
///
/// 代價：資料凍結在 build 當下。要更新資料就得重新 build。
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
    return SleepSession.fromJson(decoded);
  }
}

// ── 之後要接 HTTP 時在這裡加 ApiSleepRepository ──────────────────
//
// class ApiSleepRepository implements SleepRepository {
//   final String baseUrl;   // Android 模擬器用 http://10.0.2.2:8000
//   ...                     // 實機要用電腦的區網 IP，且要同一個 WiFi
// }
//
// 需要先在 pubspec.yaml 加 http 套件。後端已經備好了：
// main.py 的 GET /get-sleep-data 回傳的就是同一份 JSON，CORS 也開好了。
// 刻意還沒做，是因為 demo 走 asset 更穩，而多裝一個套件要有實際需求才值得。
