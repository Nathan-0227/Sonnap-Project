import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'key_value_store.dart';
import 'user_identity.dart';

/// 起床自評（2026-11-12 定案）：滑完 Slide to get up 就跳出，在看到分數之前。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 不進分數、不給 XP、不給好友看
/// ═══════════════════════════════════════════════════════════════════
///
/// 後端 `POST /rested` 只存、只並列顯示（評分層與遊戲化層都不讀 morning_ratings）。
/// 這裡也一樣：**不從自評推任何東西**——不換寵物心情、不改那句話。
///
/// ⚠️ 選項與標籤文字的正本在 `behavior/morning_tips.py`（RESTED_LABELS、TAGS）。
///    這裡另存一份只因為卡片要在連不到後端時也能畫；`morning_rating_test.dart`
///    會直接讀那支 Python 逐字比對，改一邊沒改另一邊就會紅。
///    題目照抄 Consensus Sleep Diary-M 第 10 題（Carney 2012，附錄 Figure 2），
///    **連「woke-up」的連字號也照抄**（研究文件定的；測試會比對那份文件）。
const String kRestedQuestion =
    'How rested or refreshed did you feel when you woke-up for the day?';

const Map<int, String> kRestedLabels = {
  1: 'Not at all rested',
  2: 'Slightly rested',
  3: 'Somewhat rested',
  4: 'Well-rested',
  5: 'Very well-rested',
};

/// 可以勾的標籤（id → 畫面上的字）。順序就是畫面上的順序。
const List<(String, String)> kRestedTags = [
  ('late_caffeine', 'Late caffeine'),
  ('alcohol', 'Alcohol'),
  ('exercise', 'Exercise'),
  ('stress', 'Stress'),
  ('napped', 'Napped'),
  ('woken_by_someone', 'Woken up by someone'),
  ('unwell', 'Feeling unwell'),
  ('travel', 'Travel'),
  ('noise', 'Noise'),
  ('temperature', 'Too hot / cold'),
];

/// 五張臉（使用者以 prompt 生成）。
String restedFaceAsset(int rested) => 'assets/rested/rested_$rested.png';

/// 首頁的補填小卡在起床後多久內出現（使用者定）。
const Duration kRestedMakeUpWindow = Duration(hours: 6);

@immutable
class MorningRating {
  /// 那一晚（起床日），YYYY-MM-DD。與後端 night_date 同一個約定。
  final String date;
  final int rested;
  final List<String> tags;

  /// 起床後幾分鐘才填（回想越久越不準，記下來報告時才分得開）。
  final int? minutesAfterWake;

  const MorningRating({
    required this.date,
    required this.rested,
    this.tags = const [],
    this.minutesAfterWake,
  });

  String get label => kRestedLabels[rested] ?? '';

  List<String> get tagLabels => [
        for (final (id, text) in kRestedTags)
          if (tags.contains(id)) text,
      ];

  Map<String, dynamic> toJson() => {
        'date': date,
        'rested': rested,
        'tags': tags,
        'minutes_after_wake': minutesAfterWake,
      };

  static MorningRating? fromJsonOrNull(dynamic raw) {
    if (raw is! Map) return null;
    final rested = (raw['rested'] as num?)?.toInt();
    final date = raw['date'] as String?;
    if (rested == null || date == null || !kRestedLabels.containsKey(rested)) {
      return null;
    }
    return MorningRating(
      date: date,
      rested: rested,
      tags: [
        for (final t in (raw['tags'] as List?) ?? const [])
          if (t is String) t,
      ],
      minutesAfterWake: (raw['minutes_after_wake'] as num?)?.toInt(),
    );
  }
}

/// 起床後幾分鐘。[wakeAt] 是按 Out of bed 的時刻；沒有就是 null（不猜）。
int? minutesAfterWake(DateTime? wakeAt, DateTime now) {
  if (wakeAt == null) return null;
  final m = now.difference(wakeAt).inMinutes;
  return m < 0 ? 0 : m;
}

/// 首頁要不要顯示補填小卡：起床 6 小時內、那一晚還沒填過。
/// （按了 Skip 也照樣顯示——Skip 只是「現在不想填」。）
bool showRestedMakeUp({
  required DateTime? wakeAt,
  required DateTime now,
  required MorningRating? existing,
}) {
  if (wakeAt == null || existing != null) return false;
  final since = now.difference(wakeAt);
  return !since.isNegative && since <= kRestedMakeUpWindow;
}

enum RestedSendResult {
  /// 後端收下了
  sent,

  /// 連不到／逾時／5xx：留著，下次再送
  retryLater,

  /// 後端說格式不對（4xx）：再送也一樣，不再送
  rejected,

  /// 這支 build 沒有後端或還沒有帳號：只存在手機上
  noBackend,
}

abstract class RestedSender {
  Future<RestedSendResult> send(MorningRating rating);
}

class RestedService implements RestedSender {
  final String baseUrl;
  final UserIdentity identity;
  final Duration timeout;

  const RestedService({
    required this.baseUrl,
    required this.identity,
    this.timeout = const Duration(seconds: 4),
  });

  @override
  Future<RestedSendResult> send(MorningRating rating) async {
    if (baseUrl.trim().isEmpty) return RestedSendResult.noBackend;
    final userId = await identity.currentUserId();
    if (userId == null) return RestedSendResult.noBackend;
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request =
          await client.postUrl(Uri.parse('$baseUrl/rested')).timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'user_id': userId, ...rating.toJson()}));
      final response = await request.close().timeout(timeout);
      await response.drain<void>();
      final code = response.statusCode;
      if (code >= 200 && code < 300) return RestedSendResult.sent;
      // ⚠️ 不印 body：請求裡有 user_id（憑證）。
      debugPrint('Rested: POST /rested returned $code');
      if (code >= 400 && code < 500) return RestedSendResult.rejected;
      return RestedSendResult.retryLater;
    } catch (error) {
      debugPrint('Rested: failed - $error');
      return RestedSendResult.retryLater;
    } finally {
      client.close(force: true);
    }
  }
}

/// 存在手機上（連不到後端時報告照樣畫得出「You felt」），送不出去的下次再送。
class MorningRatingStore {
  final KeyValueStore store;
  const MorningRatingStore(this.store);

  static String _key(String date) => 'rested_$date';
  static const String _unsentKey = 'rested_unsent';

  Future<MorningRating?> read(String date) async {
    try {
      final raw = await store.getString(_key(date));
      if (raw == null) return null;
      return MorningRating.fromJsonOrNull(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> _unsent() async {
    try {
      final raw = await store.getString(_unsentKey);
      if (raw == null) return [];
      return [for (final d in jsonDecode(raw) as List) d.toString()];
    } catch (_) {
      return [];
    }
  }

  Future<void> _setUnsent(List<String> dates) =>
      store.setString(_unsentKey, jsonEncode(dates));

  /// 先存在手機上，再送。回傳送的結果。
  Future<RestedSendResult> save(MorningRating rating, RestedSender? sender) async {
    await store.setString(_key(rating.date), jsonEncode(rating.toJson()));
    final result =
        sender == null ? RestedSendResult.noBackend : await sender.send(rating);
    final unsent = await _unsent();
    unsent.remove(rating.date);
    if (result == RestedSendResult.retryLater) unsent.add(rating.date);
    await _setUnsent(unsent);
    return result;
  }

  /// 補送之前沒送出去的（首頁打開時呼叫）。
  Future<void> retryUnsent(RestedSender sender) async {
    final unsent = await _unsent();
    if (unsent.isEmpty) return;
    final still = <String>[];
    for (final date in unsent) {
      final rating = await read(date);
      if (rating == null) continue;
      if (await sender.send(rating) == RestedSendResult.retryLater) {
        still.add(date);
      }
    }
    await _setUnsent(still);
  }
}
