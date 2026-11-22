import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'account_service.dart';
import 'chat_thread.dart';
import 'key_value_store.dart';

/// email＋密碼登入（2026-11-22 grill，記憶 settings-redesign-and-login 的 A'）。
///
/// 只做一件事：換手機、重裝 App 時用 email＋密碼**拿回原本的 user_id**。
///
/// ⚠️ API 照舊用 user_id 認人、沒有 token——登入只是「換回 id」，之後每個請求照舊帶它。
/// ⚠️ 規則（8 個字元、連錯 5 次鎖 15 分鐘、email 小寫）只在後端 `auth.py`；這裡只在送出前擋兩件
///    「明顯不用問伺服器」的事：太短、兩次打的不一樣。錯誤訊息照抄後端回的 `message`。
/// ⚠️ 不寄信、沒有忘記密碼：忘了找 Sonnap 團隊跑 `reset_password.py`。

/// 後端的最短長度（auth.MIN_PASSWORD_LENGTH）。只用來在送出前擋，真正的判斷在後端。
const int kMinPasswordLength = 8;

const String kLoginOffline =
    "We couldn't reach Sonnap's server. Try again when you're on the same Wi-Fi.";

const String kForgotPasswordNote =
    "Forgot your password? Ask the Sonnap team to reset it — we don't send emails.";

/// 送出前的本地檢查（太短、兩次不一樣）。null＝可以送。
String? newPasswordProblem(String password, String confirm) {
  if (password.length < kMinPasswordLength) return 'Use at least $kMinPasswordLength characters.';
  if (password != confirm) return "The two passwords don't match.";
  return null;
}

@immutable
class LoginInfo {
  final bool hasLogin;
  final String? email;
  const LoginInfo({required this.hasLogin, this.email});

  factory LoginInfo.fromJson(Map<String, dynamic> j) =>
      LoginInfo(hasLogin: j['has_login'] == true, email: j['email'] as String?);
}

/// 登入成功拿回來的東西。目標時間是後端存的那一份（新手機上的是預設值，要採用這份）。
@immutable
class LoggedIn {
  final String userId;
  final String? displayName;
  final String? email;
  final String? targetBedtime;
  final String? targetWake;
  const LoggedIn({required this.userId, this.displayName, this.email, this.targetBedtime, this.targetWake});
}

/// 結果：成功時 [value] 有值、[problem] 是 null；失敗時 [problem] 是給人讀的那句。
@immutable
class LoginOutcome<T> {
  final T? value;
  final String? problem;
  const LoginOutcome.ok(T this.value) : problem = null;
  const LoginOutcome.fail(String this.problem) : value = null;
  bool get isOk => problem == null;
}

abstract class LoginApi {
  /// 這個帳號設了登入沒有。連不到回 null（畫面就不畫 Account 那一組）。
  Future<LoginInfo?> fetch(String userId);
  Future<LoginOutcome<LoginInfo>> setUp(String userId, String email, String password);
  Future<LoginOutcome<LoggedIn>> logIn(String email, String password);
  Future<LoginOutcome<LoginInfo>> changePassword(String userId, String oldPassword, String newPassword);
}

class HttpLoginApi implements LoginApi {
  final String baseUrl;
  final Duration timeout;
  const HttpLoginApi({required this.baseUrl, this.timeout = const Duration(seconds: 8)});

  /// 回 (狀態碼, body)；連不到回 null。⚠️ 不印網址（裡面有 user_id）、不印 body（裡面有密碼）。
  Future<(int, Object?)?> _send(String method, String path, [Map<String, Object?>? body]) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.openUrl(method, Uri.parse('$baseUrl$path')).timeout(timeout);
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join();
      Object? decoded;
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        decoded = null;
      }
      return (res.statusCode, decoded);
    } catch (error) {
      debugPrint('LoginApi: $method failed - ${error.runtimeType}');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 後端的 {"detail": {"code", "message"}}；舊版後端沒有這些端點時是 404 的 "Not Found"。
  static String _problem(int status, Object? body) {
    if (body is Map && body['detail'] is Map && (body['detail'] as Map)['message'] is String) {
      return (body['detail'] as Map)['message'] as String;
    }
    if (status == 404) return "Sonnap's server doesn't support logins yet. Ask the team to update it.";
    return 'Something went wrong ($status). Try again.';
  }

  @override
  Future<LoginInfo?> fetch(String userId) async {
    final r = await _send('GET', '/users/$userId/login');
    if (r == null || r.$1 != 200 || r.$2 is! Map<String, dynamic>) return null;
    return LoginInfo.fromJson(r.$2 as Map<String, dynamic>);
  }

  @override
  Future<LoginOutcome<LoginInfo>> setUp(String userId, String email, String password) async {
    final r = await _send('POST', '/users/$userId/login', {'email': email, 'password': password});
    if (r == null) return const LoginOutcome.fail(kLoginOffline);
    if (r.$1 == 201 && r.$2 is Map<String, dynamic>) {
      return LoginOutcome.ok(LoginInfo.fromJson(r.$2 as Map<String, dynamic>));
    }
    return LoginOutcome.fail(_problem(r.$1, r.$2));
  }

  @override
  Future<LoginOutcome<LoggedIn>> logIn(String email, String password) async {
    final r = await _send('POST', '/login', {'email': email, 'password': password});
    if (r == null) return const LoginOutcome.fail(kLoginOffline);
    final b = r.$2;
    if (r.$1 == 200 && b is Map<String, dynamic> && b['user_id'] is String) {
      return LoginOutcome.ok(LoggedIn(
        userId: b['user_id'] as String,
        displayName: b['display_name'] as String?,
        email: b['email'] as String?,
        targetBedtime: b['target_bedtime'] as String?,
        targetWake: b['target_wake'] as String?,
      ));
    }
    return LoginOutcome.fail(_problem(r.$1, b));
  }

  @override
  Future<LoginOutcome<LoginInfo>> changePassword(String userId, String oldPassword, String newPassword) async {
    final r = await _send('POST', '/users/$userId/password',
        {'old_password': oldPassword, 'new_password': newPassword});
    if (r == null) return const LoginOutcome.fail(kLoginOffline);
    if (r.$1 == 200 && r.$2 is Map<String, dynamic>) {
      return LoginOutcome.ok(LoginInfo.fromJson(r.$2 as Map<String, dynamic>));
    }
    return LoginOutcome.fail(_problem(r.$1, r.$2));
  }
}

/// 把登入拿回來的帳號存進手機、登出時清掉。鍵跟 [AccountService] 同一組
/// （刻意不加在 AccountService 上：測試裡有好幾個 `implements AccountService` 的假實作）。
class AccountStorage {
  final KeyValueStore store;
  const AccountStorage(this.store);

  /// 存成「這台手機上的帳號」（同建帳號之後的狀態）。
  Future<AccountStatus> adopt(LoggedIn r) async {
    await store.setString(AccountService.userIdKey, r.userId);
    final name = r.displayName;
    if (name != null && name.isNotEmpty) {
      await store.setString(AccountService.displayNameKey, name);
    } else {
      await store.remove(AccountService.displayNameKey);
    }
    return AccountStatus(AccountState.stored, userId: r.userId, displayName: name);
  }

  /// 登出：清掉手機上的帳號（下次開 App 回到歡迎頁），連同跟助理的對話（那是這個人的）。
  /// 睡眠資料都在後端，再登入就回來；自己勾的習慣、寵物選擇只在手機上，留著。
  Future<void> forget() async {
    for (final k in [
      AccountService.userIdKey,
      AccountService.displayNameKey,
      ChatThreadStore.key,
      ChatThreadStore.legacyKey,
    ]) {
      await store.remove(k);
    }
  }
}
