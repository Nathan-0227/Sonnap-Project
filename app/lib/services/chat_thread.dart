import 'dart:convert';

import 'key_value_store.dart';

/// 助理頁的一則訊息。
///
/// [failed] 的那則是「答不出來」的泡泡：只在畫面上，不存、也不送回後端
/// （送回去等於叫模型接著一段沒過驗證的話往下講）。
class ChatTurn {
  final bool fromUser;
  final String text;
  final bool failed;

  const ChatTurn.user(this.text)
      : fromUser = true,
        failed = false;
  const ChatTurn.buddy(this.text, {this.failed = false}) : fromUser = false;

  Map<String, dynamic> toJson() => {'role': fromUser ? 'user' : 'assistant', 'text': text};

  static ChatTurn? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final text = raw['text'];
    if (text is! String || text.trim().isEmpty) return null;
    return switch (raw['role']) {
      'user' => ChatTurn.user(text),
      'assistant' => ChatTurn.buddy(text),
      _ => null,
    };
  }
}

/// 後端一次最多看幾輪前面的對話（2026-11-19 使用者定：5 輪，可以追問「為什麼」）。
const int kChatContextRounds = 5;

/// 手機上最多留幾則（只留一段對話，右上 ✎ 開新的）。
const int kChatKeepTurns = 40;

/// 從畫面上的對話挑出要一起送給後端的前文：**只拿完整的一問一答**，
/// 答不出來的那幾輪整輪跳過，最多 [kChatContextRounds] 輪、舊的在前。
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

/// 對話存在手機上（`sonnap/store`），關掉 App 再開還在。
class ChatThreadStore {
  static const key = 'assistant_thread_v1';
  final KeyValueStore store;
  const ChatThreadStore(this.store);

  Future<List<ChatTurn>> load() async {
    final raw = await store.getString(key);
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

  Future<void> clear() => store.remove(key);
}
