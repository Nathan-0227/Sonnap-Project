import 'dart:convert';

import 'key_value_store.dart';

/// 回答底下的一條建議（2026-11-22）：後端的建議 id（`behavior/morning_tips.py`）＋
/// 後端固定表那一句 Why（`ai/chat.WHY`，不是 AI 寫的；對不上計畫的是 null）。
class ChatTip {
  final String id;
  final String? why;
  const ChatTip(this.id, this.why);

  Map<String, dynamic> toJson() => {'id': id, 'why': why};

  static ChatTip? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final why = raw['why'];
    if (id is! String || id.isEmpty) return null;
    return ChatTip(id, why is String && why.trim().isNotEmpty ? why : null);
  }
}

/// 回答底下的連結：哪一晚（date）的哪一頁（key，見 `night_sheet_link.dart`）。
class ChatLink {
  final String key;
  final String date;
  const ChatLink(this.key, this.date);

  Map<String, dynamic> toJson() => {'key': key, 'date': date};

  static ChatLink? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key'];
    final date = raw['date'];
    if (key is! String || date is! String || key.isEmpty || date.isEmpty) return null;
    return ChatLink(key, date);
  }
}

/// 回答講的是哪一晚或哪一段（2026-11-22）。日期一律**起床那天**（同早晨報告的標題）。
/// 照抄後端 `/chat` 的 `period`；Dart 不判斷問題問的是哪一晚。
class ChatPeriod {
  /// 'night' 或 'range'。
  final String kind;
  final String? date;
  final String? start;
  final String? end;
  const ChatPeriod.night(String this.date)
      : kind = 'night',
        start = null,
        end = null;
  const ChatPeriod.range(String this.start, String this.end)
      : kind = 'range',
        date = null;

  Map<String, dynamic> toJson() => kind == 'night'
      ? {'kind': 'night', 'date': date}
      : {'kind': 'range', 'start': start, 'end': end};

  static ChatPeriod? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final date = raw['date'];
    final start = raw['start'];
    final end = raw['end'];
    if (raw['kind'] == 'night' && date is String && DateTime.tryParse(date) != null) {
      return ChatPeriod.night(date);
    }
    if (raw['kind'] == 'range' && start is String && end is String &&
        DateTime.tryParse(start) != null && DateTime.tryParse(end) != null) {
      return ChatPeriod.range(start, end);
    }
    return null;
  }
}

/// 助理頁的一則訊息。
///
/// [failed] 的那則是「答不出來」的泡泡：只在畫面上，不存、也不送回後端
/// （送回去等於叫模型接著一段沒過驗證的話往下講）。
///
/// 2026-11-22 起回答分段（[headline]／[why]／[tips]／[link]）。[text] 仍是合起來的那一段：
/// 當前文送回後端用它，舊版存下來的訊息也只有它（畫面照一段文字顯示）。
class ChatTurn {
  final bool fromUser;
  final String text;
  final bool failed;
  final String? headline;
  final String? why;
  final List<ChatTip> tips;
  final ChatLink? link;
  final ChatPeriod? period;

  const ChatTurn.user(this.text)
      : fromUser = true,
        failed = false,
        headline = null,
        why = null,
        tips = const [],
        link = null,
        period = null;
  const ChatTurn.buddy(this.text,
      {this.failed = false,
      this.headline,
      this.why,
      this.tips = const [],
      this.link,
      this.period})
      : fromUser = false;

  /// 有沒有分段（舊的訊息、答不出來的那則沒有）。
  bool get structured => headline != null;

  Map<String, dynamic> toJson() => {
        'role': fromUser ? 'user' : 'assistant',
        'text': text,
        if (headline != null) 'headline': headline,
        if (why != null) 'why': why,
        if (tips.isNotEmpty) 'tips': [for (final t in tips) t.toJson()],
        if (link != null) 'link': link!.toJson(),
        if (period != null) 'period': period!.toJson(),
      };

  static ChatTurn? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final text = raw['text'];
    if (text is! String || text.trim().isEmpty) return null;
    switch (raw['role']) {
      case 'user':
        return ChatTurn.user(text);
      case 'assistant':
        final headline = raw['headline'];
        final why = raw['why'];
        final tips = raw['tips'];
        return ChatTurn.buddy(
          text,
          headline: headline is String && headline.trim().isNotEmpty ? headline : null,
          why: why is String && why.trim().isNotEmpty ? why : null,
          tips: tips is List ? [for (final t in tips.map(ChatTip.fromJson)) ?t] : const [],
          link: ChatLink.fromJson(raw['link']),
          period: ChatPeriod.fromJson(raw['period']),
        );
      default:
        return null;
    }
  }
}

/// 後端一次最多看幾輪前面的對話（2026-11-19 使用者定：5 輪，可以追問「為什麼」）。
const int kChatContextRounds = 5;

/// 手機上最多留幾則（只留一段對話，右上 ✎ 開新的）。
const int kChatKeepTurns = 40;

/// 從畫面上的對話挑出要一起送給後端的前文：**只拿完整的一問一答**，
/// 答不出來的那幾輪整輪跳過，最多 [kChatContextRounds] 輪、舊的在前。
/// 回答只送合起來的 [ChatTurn.text]（後端的前文只收文字）。
List<Map<String, String>> chatContext(List<ChatTurn> turns) {
  final rounds = <List<Map<String, String>>>[];
  for (var i = 0; i + 1 < turns.length; i++) {
    final q = turns[i];
    final a = turns[i + 1];
    if (q.fromUser && !a.fromUser && !a.failed) {
      rounds.add([
        {'role': 'user', 'text': q.text},
        {'role': 'assistant', 'text': a.text},
      ]);
      i++;
    }
  }
  final recent = rounds.length > kChatContextRounds
      ? rounds.sublist(rounds.length - kChatContextRounds)
      : rounds;
  return [for (final r in recent) ...r];
}

/// 這段對話已經問過的問題（追問膠囊不再出現它們）。
Set<String> askedQuestions(List<ChatTurn> turns) =>
    {for (final t in turns) if (t.fromUser) t.text.trim()};

/// 對話存在手機上（`sonnap/store`），關掉 App 再開還在。
///
/// 2026-11-22 回答分段後存到新的鍵 [key]（v2）。v2 還沒有時讀舊的 [legacyKey]，
/// 那些訊息只有文字、照一段顯示，不轉換（grill Q9）。
class ChatThreadStore {
  static const key = 'assistant_thread_v2';
  static const legacyKey = 'assistant_thread_v1';
  final KeyValueStore store;
  const ChatThreadStore(this.store);

  Future<List<ChatTurn>> load() async {
    final raw = await store.getString(key) ?? await store.getString(legacyKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return [for (final t in list.map(ChatTurn.fromJson)) ?t];
    } catch (_) {
      return [];
    }
  }

  /// 只存**有答案的一問一答**：答不出來的那一輪，問題和失敗訊息一起不存。
  /// （2026-11-20 實機：原本只丟掉失敗訊息、問題照存，App 重開後留下一串沒有回答的問題。）
  Future<void> save(List<ChatTurn> turns) async {
    final kept = <ChatTurn>[];
    for (var i = 0; i + 1 < turns.length; i++) {
      final q = turns[i];
      final a = turns[i + 1];
      if (q.fromUser && !a.fromUser && !a.failed) {
        kept
          ..add(q)
          ..add(a);
        i++;
      }
    }
    final tail = kept.length > kChatKeepTurns ? kept.sublist(kept.length - kChatKeepTurns) : kept;
    await store.setString(key, jsonEncode([for (final t in tail) t.toJson()]));
  }

  Future<void> clear() async {
    await store.remove(key);
    await store.remove(legacyKey);
  }
}
