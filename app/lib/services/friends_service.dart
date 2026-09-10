import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'user_identity.dart';

/// 好友：`GET /friends`、`POST /friends`、`DELETE /friends/{邀請碼}`。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 這裡拿到的只有行為指標，而且沒有任何一個別人的 user_id
/// ═══════════════════════════════════════════════════════════════════
///
/// 後端刻意只分享「幾點放下手機」這一類（白名單在 social/friends.py），
/// 不分享分數、深睡、心率——跨裝置不能比，而且是健康資訊。
/// 好友之間的名牌是**邀請碼**（[FriendSummary.handle]），不是 user_id：
/// user_id 本身就是憑證，拿到別人的等於能冒充他。
///
/// ⚠️ 這個檔案一格都不算。連續夜數、熬夜比率、排名，全部照抄後端。

enum FriendsStatus { ok, noBackend, noUser, failed }

@immutable
class FriendsResult<T> {
  final FriendsStatus status;
  final T? value;
  final int? httpStatus;

  /// 後端 `detail` 的原文（英文）。404「沒有這個碼」、409「已經是朋友」、
  /// 422「那是你自己的碼」講的是不同的事，直接顯示、不在 Dart 重寫。
  final String? message;

  const FriendsResult(this.status, {this.value, this.httpStatus, this.message});

  bool get isOk => status == FriendsStatus.ok && value != null;
}

@immutable
class FriendSummary {
  /// 邀請碼。好友之間的名牌。
  final String handle;
  final String displayName;

  /// 行為版心情：'happy' / 'bored' / 'tired'，或 null（最近沒有記錄）。
  final String? petMood;
  final String? lastNightDate;

  /// ISO8601（含 +08:00）。⚠️ 顯示時一律走 parseWallClock()。
  final String? lastLightsOutAt;
  final bool? lastNightLate;
  final int currentStreak;
  final int bestStreak;

  /// null = 還沒有任何一晚有記錄，不是 0。
  final double? lateNightRatio;
  final int lateNights;
  final int recordedNights;

  const FriendSummary({
    required this.handle,
    required this.displayName,
    required this.petMood,
    required this.lastNightDate,
    required this.lastLightsOutAt,
    required this.lastNightLate,
    required this.currentStreak,
    required this.bestStreak,
    required this.lateNightRatio,
    required this.lateNights,
    required this.recordedNights,
  });

  factory FriendSummary.fromJson(Map<String, dynamic> json) => FriendSummary(
        handle: (json['handle'] as String?) ?? '',
        displayName: (json['display_name'] as String?) ?? '',
        petMood: json['pet_mood'] as String?,
        lastNightDate: json['last_night_date'] as String?,
        lastLightsOutAt: json['last_lights_out_at'] as String?,
        lastNightLate: json['last_night_late'] as bool?,
        currentStreak: (json['current_streak'] as num?)?.toInt() ?? 0,
        bestStreak: (json['best_streak'] as num?)?.toInt() ?? 0,
        lateNightRatio: (json['late_night_ratio'] as num?)?.toDouble(),
        lateNights: (json['late_nights'] as num?)?.toInt() ?? 0,
        recordedNights: (json['recorded_nights'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class LeaderboardEntry {
  final int rank;
  final String handle;
  final String displayName;
  final int currentStreak;
  final int bestStreak;

  const LeaderboardEntry({
    required this.rank,
    required this.handle,
    required this.displayName,
    required this.currentStreak,
    required this.bestStreak,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) => LeaderboardEntry(
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        handle: (json['handle'] as String?) ?? '',
        displayName: (json['display_name'] as String?) ?? '',
        currentStreak: (json['current_streak'] as num?)?.toInt() ?? 0,
        bestStreak: (json['best_streak'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class FriendsState {
  final String myInviteCode;
  final List<FriendSummary> friends;

  /// ⚠️ 已經由後端排好。Dart 不重排——同分怎麼排是後端的規則。
  final List<LeaderboardEntry> leaderboard;
  final Map<String, String> notes;

  const FriendsState({
    required this.myInviteCode,
    required this.friends,
    required this.leaderboard,
    required this.notes,
  });

  factory FriendsState.fromJson(Map<String, dynamic> json) => FriendsState(
        myInviteCode: (json['my_invite_code'] as String?) ?? '',
        friends: ((json['friends'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(FriendSummary.fromJson)
            .toList(),
        leaderboard: ((json['leaderboard'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LeaderboardEntry.fromJson)
            .toList(),
        notes: {
          for (final e in ((json['notes'] as Map?) ?? const {}).entries)
            if (e.value is String) '${e.key}': e.value as String,
        },
      );
}

class FriendsService {
  final String baseUrl;
  final UserIdentity identity;
  final Duration timeout;

  const FriendsService({
    required this.baseUrl,
    required this.identity,
    this.timeout = const Duration(seconds: 3),
  });

  Future<FriendsResult<FriendsState>> fetch() async {
    final r = await _request('GET', '/friends');
    if (!r.isOk) return FriendsResult(r.status, httpStatus: r.httpStatus, message: r.message);
    return FriendsResult(FriendsStatus.ok, value: FriendsState.fromJson(r.value!));
  }

  /// 用邀請碼加好友。成功時 value 是那位朋友的摘要。
  Future<FriendsResult<FriendSummary>> add(String inviteCode) async {
    final r = await _request('POST', '/friends', body: {'invite_code': inviteCode.trim()});
    if (!r.isOk) return FriendsResult(r.status, httpStatus: r.httpStatus, message: r.message);
    final friend = r.value!['friend'];
    if (friend is! Map<String, dynamic>) return const FriendsResult(FriendsStatus.failed);
    return FriendsResult(FriendsStatus.ok, value: FriendSummary.fromJson(friend));
  }

  Future<FriendsResult<String>> remove(String handle) async {
    final r = await _request('DELETE', '/friends/${Uri.encodeComponent(handle)}');
    if (!r.isOk) return FriendsResult(r.status, httpStatus: r.httpStatus, message: r.message);
    return FriendsResult(FriendsStatus.ok, value: (r.value!['removed'] as String?) ?? handle);
  }

  /// ⚠️ user_id：GET／DELETE 放 query、POST 放 body（後端定的介面）。
  ///    它本身就是憑證——不印進 log、不放進錯誤訊息。
  Future<FriendsResult<Map<String, dynamic>>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (baseUrl.trim().isEmpty) return const FriendsResult(FriendsStatus.noBackend);
    final userId = await identity.currentUserId();
    if (userId == null) return const FriendsResult(FriendsStatus.noUser);

    final base = Uri.parse('$baseUrl$path');
    final uri = method == 'POST' ? base : base.replace(queryParameters: {'user_id': userId});
    final client = HttpClient()..connectionTimeout = timeout;

    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      if (method == 'POST') {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({'user_id': userId, ...?body}));
      }
      final response = await request.close().timeout(timeout);
      final text = await response.transform(utf8.decoder).join();
      final decoded = text.isEmpty ? null : jsonDecode(text);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = decoded is Map ? decoded['detail'] : null;
        return FriendsResult(
          FriendsStatus.failed,
          httpStatus: response.statusCode,
          message: detail is String ? detail : null,
        );
      }
      if (decoded is! Map<String, dynamic>) {
        return FriendsResult(FriendsStatus.failed, httpStatus: response.statusCode);
      }
      return FriendsResult(FriendsStatus.ok, value: decoded, httpStatus: response.statusCode);
    } catch (error) {
      debugPrint('Friends: $method $path failed - $error');
      return const FriendsResult(FriendsStatus.failed);
    } finally {
      client.close(force: true);
    }
  }
}
