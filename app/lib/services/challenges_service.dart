import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'sleep_repository.dart';
import 'user_identity.dart';

/// 挑戰進度：`GET /challenges`。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 這個檔案不算任何東西
/// ═══════════════════════════════════════════════════════════════════
///
/// 進度、達成與否、分母，**全部由後端 `behavior/challenges.py` 算**，
/// 這裡只負責把 JSON 變成 Dart 物件。在 Dart 重算就會有第二個定義處，
/// 而兩份漂移時不會有任何錯誤訊息——與「達成度只在後端算」、
/// 「不要在 Dart 從 final_quality 推 pet_mood」是同一條紀律。
///
/// 連 `detail`（「還差 2 晚」那種句子）都是後端給的整句英文。
///
/// ⚠️ 用 `dart:io` 的 [HttpClient]，**不裝 `package:http`**——
/// 理由與 [ApiSleepRepository]、[KeyValueStore] 相同（不出 linux/macos/
/// windows 三個平台，多一個套件就多三份 generated plugin 檔的雜訊）。

/// 一個挑戰的三種狀態。
///
/// ⚠️ **[insufficientData] 不是「0%」。** 後端刻意把它跟 [inProgress] 分開
/// （`challenges.py` 的 `evaluate_challenge`：`current_value is None` 才是
/// insufficient_data）。畫成一條空的進度條，使用者會以為自己表現很差，
/// 而事實是我們根本還沒收到他的資料——那兩件事給人的訊息完全相反。
enum ChallengeState {
  /// 達成了
  completed,

  /// 有資料、還沒達成
  inProgress,

  /// **還沒有足夠的資料可以判斷。** 不得畫成 0%。
  insufficientData,
}

@immutable
class ChallengeProgress {
  final String challengeId;
  final String kind;
  final String title;
  final String description;

  /// 後端寫好的一整句英文（「還差 2 晚」「比目標晚了 12 分鐘」）。
  /// ⚠️ 不要在 Dart 重組這句話——它跟後端的判斷邏輯是綁在一起的。
  final String detail;

  final ChallengeState state;

  /// 0.0 ~ 1.0。**null 代表 [ChallengeState.insufficientData]**，
  /// 不是 0。
  final double? progress;

  /// 這個窗格裡真的有記錄的夜數。
  ///
  /// ⚠️ **一定要顯示出來當分母。** `challenges.py:400` 明寫理由：
  /// 沒有它，「達成 3 晚」看不出是 3/3 還是 3/14。
  final int recordedNights;

  final int windowDays;

  /// 這一項是不是「數字越小越好」（作息收斂的離散度）。
  final bool lowerIsBetter;

  const ChallengeProgress({
    required this.challengeId,
    required this.kind,
    required this.title,
    required this.description,
    required this.detail,
    required this.state,
    required this.progress,
    required this.recordedNights,
    required this.windowDays,
    required this.lowerIsBetter,
  });

  static ChallengeState _parseState(String? raw) {
    switch (raw) {
      case 'completed':
        return ChallengeState.completed;
      case 'in_progress':
        return ChallengeState.inProgress;
      case 'insufficient_data':
        return ChallengeState.insufficientData;
    }
    // 後端加了第四種狀態而這裡沒跟上。退到 insufficientData 而不是
    // inProgress：前者畫的是「還沒有資料」，後者會畫出一條可能是假的進度條。
    debugPrint('Challenges: 不認得的 status $raw，當成 insufficient_data');
    return ChallengeState.insufficientData;
  }

  factory ChallengeProgress.fromJson(Map<String, dynamic> json) {
    return ChallengeProgress(
      challengeId: (json['challenge_id'] as String?) ?? '',
      kind: (json['kind'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      detail: (json['detail'] as String?) ?? '',
      state: _parseState(json['status'] as String?),
      // ⚠️ 照抄後端的 progress，不從 current_value / target_value 自己算。
      //    三種型別的換算方式不同（consistency 是比值不是線性遞減），
      //    在這裡重算等於把那段推理複製一份到 Dart。
      progress: (json['progress'] as num?)?.toDouble(),
      recordedNights: (json['recorded_nights'] as num?)?.toInt() ?? 0,
      windowDays: (json['window_days'] as num?)?.toInt() ?? 0,
      lowerIsBetter: (json['lower_is_better'] as bool?) ?? false,
    );
  }
}

/// 為什麼沒有挑戰資料。⚠️ 每一種原因都要分得開，理由同
/// [NightlyUploadStatus]：它們在畫面上要講不同的話，解法也不同。
enum ChallengesStatus {
  ok,

  /// 這支 build 沒有 `--dart-define=SONNAP_API_BASE`
  noBackend,

  /// 還沒建帳號
  noUser,

  /// 連不上、逾時、後端回錯
  failed,
}

@immutable
class ChallengesResult {
  final ChallengesStatus status;
  final List<ChallengeProgress> challenges;
  final String? error;

  const ChallengesResult(
    this.status, {
    this.challenges = const <ChallengeProgress>[],
    this.error,
  });
}

class ChallengesService {
  final String baseUrl;
  final UserIdentity identity;

  /// 與 [ApiSleepRepository] 一樣短。挑戰卡拿不到就不顯示，
  /// 不該讓整頁等在這裡。
  final Duration timeout;

  const ChallengesService({
    required this.baseUrl,
    required this.identity,
    this.timeout = const Duration(seconds: 3),
  });

  Future<ChallengesResult> fetch() async {
    if (baseUrl.trim().isEmpty) {
      return const ChallengesResult(ChallengesStatus.noBackend);
    }

    final userId = await identity.currentUserId();
    if (userId == null) {
      return const ChallengesResult(ChallengesStatus.noUser);
    }

    // ⚠️ user_id 走 query string 是後端定的介面（main.py 的
    //    `user_id: str = Query(...)`）。它本身就是憑證，所以**不要印出來**。
    final uri = Uri.parse('$baseUrl/challenges')
        .replace(queryParameters: {'user_id': userId});
    final client = HttpClient()..connectionTimeout = timeout;

    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        return ChallengesResult(
          ChallengesStatus.failed,
          error: 'GET /challenges returned ${response.statusCode}: $body',
        );
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return const ChallengesResult(
          ChallengesStatus.failed,
          error: '/challenges 回傳的根節點不是物件',
        );
      }

      final raw = decoded['challenges'];
      if (raw is! List) {
        return const ChallengesResult(
          ChallengesStatus.failed,
          error: '/challenges 沒有 challenges 陣列',
        );
      }

      final parsed = raw
          .whereType<Map<String, dynamic>>()
          .map(ChallengeProgress.fromJson)
          .toList();

      debugPrint('Challenges: ok ${parsed.length} challenge(s)');
      return ChallengesResult(ChallengesStatus.ok, challenges: parsed);
    } catch (error) {
      debugPrint('Challenges: failed - $error');
      return ChallengesResult(
        ChallengesStatus.failed,
        error: error.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }
}

/// 依建置參數決定要不要問挑戰進度。沒給 API base 就回 null，
/// 整條路徑不存在——與 [buildNightlyUploader] 同一個原則。
ChallengesService? buildChallengesService({
  String? baseUrlOverride,
  String? userIdOverride,
}) {
  final baseUrl =
      (baseUrlOverride ?? ApiSleepRepository.configuredBaseUrl).trim();
  if (baseUrl.isEmpty) return null;
  return ChallengesService(
    baseUrl: baseUrl,
    identity: buildUserIdentity(userIdOverride: userIdOverride),
  );
}
