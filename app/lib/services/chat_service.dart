import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'user_identity.dart';

/// 睡眠助理：`POST /chat`。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ LLM 是唯一的答案來源，連不到就老實講連不到
/// ═══════════════════════════════════════════════════════════════════
///
/// 答案由後端的 Claude 產生，並通過四道驗證（醫療用語、數字要在事實裡、
/// 中文洩漏、拼字數值）才回來。這裡**不在 Dart 編一個答案**——連不上、
/// 伺服器沒設定金鑰、或兩次都沒過驗證時，畫面要講的是「答不出來」，
/// 不是一段看起來像答案的通用句子。
///
/// ⚠️ 逾時要比其他服務長：後端呼叫 Claude 最多等 60 秒，還可能重問一次。
///    用 3 秒的話幾乎每一題都會被當成「連不上」。
///
/// ⚠️ 每問一次都會花 API 額度。

enum ChatStatus { ok, noBackend, noUser, failed }

@immutable
class ChatResult {
  final ChatStatus status;
  final String? answer;
  final int? httpStatus;

  /// 後端 `detail` 的原文（英文）。503 的原因（沒設定／連不上／沒過驗證）
  /// 由後端寫，Dart 直接顯示。
  final String? message;

  const ChatResult(this.status, {this.answer, this.httpStatus, this.message});

  bool get isOk => status == ChatStatus.ok && answer != null;
}

class ChatService {
  final String baseUrl;
  final UserIdentity identity;
  final Duration timeout;

  const ChatService({
    required this.baseUrl,
    required this.identity,
    this.timeout = const Duration(seconds: 150),
  });

  Future<ChatResult> ask(String message) async {
    if (baseUrl.trim().isEmpty) return const ChatResult(ChatStatus.noBackend);
    final userId = await identity.currentUserId();
    if (userId == null) return const ChatResult(ChatStatus.noUser);

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(Uri.parse('$baseUrl/chat')).timeout(timeout);
      request.headers.contentType = ContentType.json;
      // ⚠️ user_id 本身就是憑證——不印進 log、不放進錯誤訊息。
      request.write(jsonEncode({'user_id': userId, 'message': message.trim()}));
      final response = await request.close().timeout(timeout);
      final text = await response.transform(utf8.decoder).join();
      final decoded = text.isEmpty ? null : jsonDecode(text);

      if (response.statusCode != 200) {
        final detail = decoded is Map ? decoded['detail'] : null;
        return ChatResult(
          ChatStatus.failed,
          httpStatus: response.statusCode,
          message: detail is String ? detail : null,
        );
      }
      final answer = decoded is Map ? decoded['answer'] : null;
      if (answer is! String || answer.trim().isEmpty) {
        return ChatResult(ChatStatus.failed, httpStatus: response.statusCode);
      }
      return ChatResult(ChatStatus.ok, answer: answer, httpStatus: response.statusCode);
    } catch (error) {
      debugPrint('Chat: failed - $error');
      return const ChatResult(ChatStatus.failed);
    } finally {
      client.close(force: true);
    }
  }
}
