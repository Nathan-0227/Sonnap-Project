import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'sleep_repository.dart';
import 'user_identity.dart';

/// `GET /home` 的 **behavior 區塊**——目前只為了熬夜比率。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 這個服務刻意只讀 `behavior`，不讀 `status`
/// ═══════════════════════════════════════════════════════════════════
///
/// `/home` 也回 `status.pet_mood`。**不要在這裡解析它。** 這個 App 裡
/// 「今晚的寵物心情」只有一個來源（[SleepRepository] 的 payload），
/// 多一個來源就會出現首頁與 Insights 顯示兩隻不同寵物的情況——
/// 那正是 `tests/test_history_mood.py` 第 3 條在守的東西，
/// 而它壞掉時沒有任何錯誤訊息。
///
/// 同理不讀 `behavior.adherence_minutes`：那一行的數字來自
/// `POST /nightly` 的回應（見 [NightlyUploadResult]），畫面上已經有了。
/// 兩個都畫就會變成同一件事有兩個數字在打架。
///
/// ⚠️ 熬夜比率**一格都不算**。分母是「有測到資料的夜數」而不是日曆天，
/// 那個取捨寫在 `behavior/adherence.py` 的 `late_night_ratio()`：
/// 把沒資料的日子當成「沒熬夜」數字會好看但沒有意義，當成「熬夜」
/// 則是憑空捏造。在 Dart 用別的分母重算，就等於把那段推理丟掉。

/// 後端算好的熬夜比率。
@immutable
class BehaviorSummary {
  /// 0.0 ~ 1.0。**null 代表還沒有任何一晚有記錄**，不是 0——
  /// 「沒熬夜」與「沒資料」是兩件事。
  final double? lateNightRatio;

  /// 判定為熬夜的夜數（分子）。
  final int lateNights;

  /// **有測到資料**的夜數（分母）。⚠️ 不是日曆天數。
  final int recordedNights;

  /// 後端往回看幾天。用來誠實地講「最近 N 天裡有 M 晚有記錄」。
  final int windowDays;

  const BehaviorSummary({
    required this.lateNightRatio,
    required this.lateNights,
    required this.recordedNights,
    required this.windowDays,
  });

  factory BehaviorSummary.fromJson(
    Map<String, dynamic> behavior, {
    required int windowDays,
  }) {
    return BehaviorSummary(
      // ⚠️ 照抄。不要寫成 `?? 0`——null 是「還沒有資料」，
      //    0.0 是「一晚都沒熬夜」，兩者在畫面上要講不同的話。
      lateNightRatio: (behavior['late_night_ratio'] as num?)?.toDouble(),
      lateNights: (behavior['late_nights'] as num?)?.toInt() ?? 0,
      recordedNights: (behavior['recorded_nights'] as num?)?.toInt() ?? 0,
      windowDays: windowDays,
    );
  }
}

/// 為什麼沒有資料。理由同 [ChallengesStatus]：每一種在畫面上要講不同的話。
enum HomeStatus { ok, noBackend, noUser, failed }

@immutable
class HomeResult {
  final HomeStatus status;
  final BehaviorSummary? behavior;
  final String? error;

  const HomeResult(this.status, {this.behavior, this.error});
}

class HomeService {
  final String baseUrl;
  final UserIdentity identity;
  final Duration timeout;

  /// 後端 `DEFAULT_HISTORY_DAYS`。
  ///
  /// ⚠️ 這是**後端的**常數在 Dart 這邊的一份拷貝，只用來寫那句
  /// 「最近 30 天」的文案，不參與任何計算。後端改了這裡沒改，
  /// 症狀是文案講錯天數而數字仍然正確——所以寧可寫死在一個
  /// 有名字的地方，也不要散在 UI 字串裡。
  static const int historyDays = 30;

  const HomeService({
    required this.baseUrl,
    required this.identity,
    this.timeout = const Duration(seconds: 3),
  });

  Future<HomeResult> fetch() async {
    if (baseUrl.trim().isEmpty) {
      return const HomeResult(HomeStatus.noBackend);
    }

    final userId = await identity.currentUserId();
    if (userId == null) {
      return const HomeResult(HomeStatus.noUser);
    }

    // ⚠️ user_id 本身就是憑證，不要印出來。
    final uri = Uri.parse('$baseUrl/home')
        .replace(queryParameters: {'user_id': userId});
    final client = HttpClient()..connectionTimeout = timeout;

    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        return HomeResult(
          HomeStatus.failed,
          error: 'GET /home returned ${response.statusCode}: $body',
        );
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return const HomeResult(
          HomeStatus.failed,
          error: '/home 回傳的根節點不是物件',
        );
      }

      final behavior = decoded['behavior'];
      if (behavior is! Map<String, dynamic>) {
        return const HomeResult(
          HomeStatus.failed,
          error: '/home 沒有 behavior 區塊',
        );
      }

      final summary =
          BehaviorSummary.fromJson(behavior, windowDays: historyDays);
      debugPrint(
        'Home: ok late=${summary.lateNights}/${summary.recordedNights} '
        'ratio=${summary.lateNightRatio}',
      );
      return HomeResult(HomeStatus.ok, behavior: summary);
    } catch (error) {
      debugPrint('Home: failed - $error');
      return HomeResult(HomeStatus.failed, error: error.toString());
    } finally {
      client.close(force: true);
    }
  }
}

/// 依建置參數決定要不要問。沒給 API base 就回 null——與
/// [buildChallengesService]、[buildNightlyUploader] 同一個原則。
HomeService? buildHomeService({
  String? baseUrlOverride,
  String? userIdOverride,
}) {
  final baseUrl =
      (baseUrlOverride ?? ApiSleepRepository.configuredBaseUrl).trim();
  if (baseUrl.isEmpty) return null;
  return HomeService(
    baseUrl: baseUrl,
    identity: buildUserIdentity(userIdOverride: userIdOverride),
  );
}
