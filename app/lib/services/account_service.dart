import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'key_value_store.dart';
import 'user_identity.dart';

/// 這台裝置目前處在哪一種身分狀態。
///
/// ⚠️ 四種要分得開。混成「有 / 沒有」的話，「後端沒開所以還建不了帳號」
/// 會長得跟「這支 build 根本不打算連後端」一模一樣，而兩者的處置完全不同。
enum AccountState {
  /// 建置參數帶了 `SONNAP_USER_ID`。demo build 走這條，不問暱稱。
  buildTime,

  /// 這台裝置上存過帳號了
  stored,

  /// 有後端、但還沒有帳號 → 要問暱稱
  needsOnboarding,

  /// 這支 build 沒有後端。純 asset 模式，不需要身分
  noBackend,
}

@immutable
class AccountStatus {
  final AccountState state;
  final String? userId;
  final String? displayName;

  const AccountStatus(this.state, {this.userId, this.displayName});
}

/// 暱稱制帳號：建立、存下來、之後每次開 App 沿用。
///
/// ═══════════════════════════════════════════════════════════════════
/// 這是 [BuildTimeUserIdentity] 的另一半
/// ═══════════════════════════════════════════════════════════════════
///
/// | | 身分從哪來 | 一支 APK |
/// |---|---|---|
/// | `--dart-define=SONNAP_USER_ID` | 建置時寫死 | = 一個人 |
/// | 這個檔案 | 首次開啟 `POST /users` | 給所有人 |
///
/// D2 要發給十來個同學，不可能一人一份客製 APK，所以這條是必要的。
/// 建置參數那條留著是因為 demo 更省事，而且它**優先**——
/// 拿 demo build 測試時不該跳出一個問暱稱的畫面。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 建不了帳號**絕對不能擋住 App**
/// ═══════════════════════════════════════════════════════════════════
///
/// 後端沒開是 demo 的常態（`FallbackSleepRepository` 整個就是為此存在的）。
/// 帳號建不起來時使用者仍然要能看睡眠報告、夢境日記、寵物——只是那一晚的
/// 行為資料上傳不了而已。這裡的每一個失敗路徑都回一個狀態，不拋例外。
class AccountService {
  /// user_id 存在這個鍵底下。
  ///
  /// ⚠️ 改這個字串等於把所有既有使用者的帳號弄丟（讀不到就會重建一個新的，
  /// 而舊帳號的歷史資料還留在後端、再也對不回來）。要改就要一併寫遷移。
  static const String userIdKey = 'user_id';
  static const String displayNameKey = 'display_name';

  final String baseUrl;
  final KeyValueStore store;
  final Duration timeout;

  const AccountService({
    required this.baseUrl,
    this.store = const PlatformKeyValueStore(),
    this.timeout = const Duration(seconds: 5),
  });

  /// 現在是哪一種狀態。App 啟動時問一次。
  Future<AccountStatus> resolve() async {
    // 建置參數優先。理由見類別說明。
    final built = await const BuildTimeUserIdentity().currentUserId();
    if (built != null) {
      return AccountStatus(AccountState.buildTime, userId: built);
    }

    if (baseUrl.trim().isEmpty) {
      return const AccountStatus(AccountState.noBackend);
    }

    final stored = await store.getString(userIdKey);
    if (stored != null && stored.isNotEmpty) {
      return AccountStatus(
        AccountState.stored,
        userId: stored,
        displayName: await store.getString(displayNameKey),
      );
    }

    return const AccountStatus(AccountState.needsOnboarding);
  }

  /// 建一個帳號並存下來。成功回 [AccountStatus]，失敗回 null。
  ///
  /// ⚠️ **先存再回傳。** 存失敗的話下次開 App 會再問一次暱稱，
  /// 而後端已經多了一個沒人用的帳號——不好看，但比「拿到 id 卻沒存下來、
  /// 使用者每天都是新的一個人」好得多。
  Future<AccountStatus?> createAccount({
    required String displayName,
    required String targetBedtime,
  }) async {
    final uri = Uri.parse('$baseUrl/users');
    final client = HttpClient()..connectionTimeout = timeout;

    try {
      final request = await client.postUrl(uri).timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'display_name': displayName,
        'target_bedtime': targetBedtime,
        // 這兩個欄位後端有預設值，但明寫出來比較看得懂這支 App 是什麼身分。
        // study_cohort L0 = 只有手機、沒有穿戴裝置，那是 D2 大多數同學的情況。
        'study_cohort': 'L0',
      }));

      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode != 201) {
        debugPrint('AccountService: POST $uri -> ${response.statusCode} $body');
        return null;
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;

      final userId = decoded['user_id'] as String?;
      if (userId == null || userId.isEmpty) return null;

      await store.setString(userIdKey, userId);
      await store.setString(displayNameKey, displayName);

      // ⚠️ 不印 user_id——它是憑證，logcat 裝了 adb 就讀得到。
      debugPrint('AccountService: created account for "$displayName"');
      return AccountStatus(
        AccountState.stored,
        userId: userId,
        displayName: displayName,
      );
    } catch (error) {
      debugPrint('AccountService: createAccount failed - $error');
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

/// 從已經解析好的狀態拿身分。
///
/// 之所以不讓它自己去查，是因為狀態在 App 啟動時就解析過一次了，
/// 每次上傳再問一次原生端只是白繞一圈。
class ResolvedUserIdentity implements UserIdentity {
  final String? userId;

  const ResolvedUserIdentity(this.userId);

  @override
  Future<String?> currentUserId() async => userId;
}
