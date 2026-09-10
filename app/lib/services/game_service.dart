import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'sleep_repository.dart';
import 'user_identity.dart';

/// 遊戲化層：XP、等級、衣櫃、挑戰獎勵。
/// `GET /game`、`GET /closet`、`POST /game/claim`、`POST /closet/equip`。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 這個檔案一格都不算
/// ═══════════════════════════════════════════════════════════════════
///
/// XP、等級、進度條的比例、哪些衣服解鎖了、哪些獎勵可以領，全部是後端
/// `game/` 算好回來的。在 Dart 從 `xp_total` 反推等級、或從
/// `final_quality` 推 XP，就是第二個定義處——而那兩份漂移時畫面照樣
/// 正常顯示，只是跟後端講的不一樣。與「達成度只在後端算」、
/// 「不要在 Dart 從 final_quality 推 pet_mood」是同一條紀律。
///
/// ⚠️ 用 `dart:io` 的 [HttpClient]，不裝 `package:http`（理由見
/// [ApiSleepRepository]）。

/// 為什麼沒有資料。每一種在畫面上要講不同的話。
enum GameStatus {
  ok,

  /// 這支 build 沒有 `--dart-define=SONNAP_API_BASE`
  noBackend,

  /// 還沒建帳號
  noUser,

  /// 連不上、逾時，或後端回了 2xx 以外的狀態
  failed,
}

@immutable
class GameResult<T> {
  final GameStatus status;
  final T? value;

  /// 後端 HTTP 狀態碼（連不上時是 null）。領獎的 409／422、換裝的 403
  /// 要靠它分辨。
  final int? httpStatus;

  /// 後端 `detail` 的原文（英文）。⚠️ 直接顯示，不在 Dart 重寫——
  /// 「幾級解鎖」這種句子是後端依規則組的，重寫一次就是第二個定義處。
  final String? message;

  const GameResult(this.status, {this.value, this.httpStatus, this.message});

  bool get isOk => status == GameStatus.ok && value != null;
}

@immutable
class XpSources {
  final int behaviour;
  final int sleepQuality;
  final int challengeRewards;

  const XpSources({
    required this.behaviour,
    required this.sleepQuality,
    required this.challengeRewards,
  });

  factory XpSources.fromJson(Map<String, dynamic>? json) => XpSources(
        behaviour: (json?['behaviour'] as num?)?.toInt() ?? 0,
        sleepQuality: (json?['sleep_quality'] as num?)?.toInt() ?? 0,
        challengeRewards: (json?['challenge_rewards'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class GameBadge {
  final String badgeId;
  final String title;
  final String description;
  final bool earned;

  const GameBadge({
    required this.badgeId,
    required this.title,
    required this.description,
    required this.earned,
  });

  factory GameBadge.fromJson(Map<String, dynamic> json) => GameBadge(
        badgeId: (json['badge_id'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        earned: (json['earned'] as bool?) ?? false,
      );
}

@immutable
class ClaimableReward {
  final String challengeId;
  final String title;
  final int xp;

  const ClaimableReward({
    required this.challengeId,
    required this.title,
    required this.xp,
  });

  factory ClaimableReward.fromJson(Map<String, dynamic> json) => ClaimableReward(
        challengeId: (json['challenge_id'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        xp: (json['xp'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class GameState {
  final int level;
  final int xpTotal;
  final int xpIntoLevel;

  /// 離下一級還差多少。**null = 已經最高級**，不是 0。
  final int? xpForNext;

  /// 0.0 ~ 1.0，「這一級」走了多少。⚠️ 照抄後端，不從 xpTotal 自己算。
  final double progress;
  final bool maxLevel;

  /// 'baby' / 'young' / 'adult'
  final String growthStage;
  final XpSources sources;
  final List<ClaimableReward> claimable;
  final List<GameBadge> badges;

  /// 後端寫好的說明句（英文）。畫面直接顯示，不在 Dart 重寫。
  final Map<String, String> notes;

  const GameState({
    required this.level,
    required this.xpTotal,
    required this.xpIntoLevel,
    required this.xpForNext,
    required this.progress,
    required this.maxLevel,
    required this.growthStage,
    required this.sources,
    required this.claimable,
    required this.badges,
    required this.notes,
  });

  factory GameState.fromJson(Map<String, dynamic> json) => GameState(
        level: (json['level'] as num?)?.toInt() ?? 1,
        xpTotal: (json['xp_total'] as num?)?.toInt() ?? 0,
        xpIntoLevel: (json['xp_into_level'] as num?)?.toInt() ?? 0,
        xpForNext: (json['xp_for_next'] as num?)?.toInt(),
        progress: ((json['progress'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
        maxLevel: (json['max_level'] as bool?) ?? false,
        growthStage: (json['growth_stage'] as String?) ?? 'baby',
        sources: XpSources.fromJson(json['xp_sources'] as Map<String, dynamic>?),
        claimable: ((json['claimable'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ClaimableReward.fromJson)
            .toList(),
        badges: ((json['badges'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(GameBadge.fromJson)
            .toList(),
        notes: {
          for (final e in ((json['notes'] as Map?) ?? const {}).entries)
            if (e.value is String) '${e.key}': e.value as String,
        },
      );
}

@immutable
class ClosetItem {
  final String itemId;
  final String name;
  final String emoji;
  final int unlockLevel;
  final bool unlocked;
  final bool equipped;

  const ClosetItem({
    required this.itemId,
    required this.name,
    required this.emoji,
    required this.unlockLevel,
    required this.unlocked,
    required this.equipped,
  });

  factory ClosetItem.fromJson(Map<String, dynamic> json) => ClosetItem(
        itemId: (json['item_id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        emoji: (json['emoji'] as String?) ?? '',
        unlockLevel: (json['unlock_level'] as num?)?.toInt() ?? 0,
        // ⚠️ 解鎖與否照抄後端。不要在 Dart 用 level >= unlockLevel 自己判斷——
        //    後端還算上「曾經穿過就不收回」，Dart 那樣算會把它收回。
        unlocked: (json['unlocked'] as bool?) ?? false,
        equipped: (json['equipped'] as bool?) ?? false,
      );
}

@immutable
class ClosetState {
  final int level;
  final String? equippedItemId;
  final List<ClosetItem> items;

  const ClosetState({
    required this.level,
    required this.equippedItemId,
    required this.items,
  });

  /// 現在穿著的那一件。沒穿就是 null。
  ClosetItem? get equipped {
    for (final item in items) {
      if (item.itemId == equippedItemId) return item;
    }
    return null;
  }

  factory ClosetState.fromJson(Map<String, dynamic> json) => ClosetState(
        level: (json['level'] as num?)?.toInt() ?? 1,
        equippedItemId: json['equipped_item_id'] as String?,
        items: ((json['items'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ClosetItem.fromJson)
            .toList(),
      );
}

@immutable
class ClaimOutcome {
  final int xpAwarded;
  final int level;
  final bool leveledUp;

  const ClaimOutcome({
    required this.xpAwarded,
    required this.level,
    required this.leveledUp,
  });
}

class GameService {
  final String baseUrl;
  final UserIdentity identity;
  final Duration timeout;

  const GameService({
    required this.baseUrl,
    required this.identity,
    this.timeout = const Duration(seconds: 3),
  });

  Future<GameResult<GameState>> fetchGame() async {
    final r = await _request('GET', '/game');
    if (!r.isOk) return GameResult(r.status, httpStatus: r.httpStatus, message: r.message);
    return GameResult(GameStatus.ok, value: GameState.fromJson(r.value!));
  }

  Future<GameResult<ClosetState>> fetchCloset() async {
    final r = await _request('GET', '/closet');
    if (!r.isOk) return GameResult(r.status, httpStatus: r.httpStatus, message: r.message);
    return GameResult(GameStatus.ok, value: ClosetState.fromJson(r.value!));
  }

  Future<GameResult<ClaimOutcome>> claim(String challengeId) async {
    final r = await _request('POST', '/game/claim', body: {'challenge_id': challengeId});
    if (!r.isOk) return GameResult(r.status, httpStatus: r.httpStatus, message: r.message);
    final json = r.value!;
    final claimed = (json['claimed'] as Map<String, dynamic>?) ?? const {};
    return GameResult(
      GameStatus.ok,
      value: ClaimOutcome(
        xpAwarded: (claimed['xp'] as num?)?.toInt() ?? 0,
        level: (json['level'] as num?)?.toInt() ?? 1,
        leveledUp: (json['leveled_up'] as bool?) ?? false,
      ),
    );
  }

  /// 換衣服。itemId=null 代表脫掉。成功時 value 是現在穿著的 item_id。
  Future<GameResult<String?>> equip(String? itemId) async {
    final r = await _request('POST', '/closet/equip', body: {'item_id': itemId});
    if (!r.isOk) return GameResult(r.status, httpStatus: r.httpStatus, message: r.message);
    return GameResult(GameStatus.ok, value: r.value!['equipped_item_id'] as String?);
  }

  /// 四個端點共用的那一段。user_id：GET 放 query、POST 放 body（後端定的介面）。
  ///
  /// ⚠️ user_id 本身就是憑證——不印進 log、不放進錯誤訊息。
  Future<GameResult<Map<String, dynamic>>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (baseUrl.trim().isEmpty) return const GameResult(GameStatus.noBackend);
    final userId = await identity.currentUserId();
    if (userId == null) return const GameResult(GameStatus.noUser);

    final base = Uri.parse('$baseUrl$path');
    final uri = method == 'GET' ? base.replace(queryParameters: {'user_id': userId}) : base;
    final client = HttpClient()..connectionTimeout = timeout;

    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      if (method != 'GET') {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({'user_id': userId, ...?body}));
      }
      final response = await request.close().timeout(timeout);
      final text = await response.transform(utf8.decoder).join();
      final decoded = text.isEmpty ? null : jsonDecode(text);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = decoded is Map ? decoded['detail'] : null;
        return GameResult(
          GameStatus.failed,
          httpStatus: response.statusCode,
          message: detail is String ? detail : null,
        );
      }
      if (decoded is! Map<String, dynamic>) {
        return GameResult(GameStatus.failed, httpStatus: response.statusCode);
      }
      return GameResult(GameStatus.ok, value: decoded, httpStatus: response.statusCode);
    } catch (error) {
      debugPrint('Game: $method $path failed - $error');
      return const GameResult(GameStatus.failed);
    } finally {
      client.close(force: true);
    }
  }
}

/// 依建置參數決定要不要建。沒給 API base 就回 null——與
/// [buildChallengesService] 同一個原則。
GameService? buildGameService({String? baseUrlOverride, String? userIdOverride}) {
  final baseUrl = (baseUrlOverride ?? ApiSleepRepository.configuredBaseUrl).trim();
  if (baseUrl.isEmpty) return null;
  return GameService(
    baseUrl: baseUrl,
    identity: buildUserIdentity(userIdOverride: userIdOverride),
  );
}
