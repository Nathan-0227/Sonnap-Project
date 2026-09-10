import 'package:flutter/material.dart';

import '../services/account_service.dart';
import '../services/chat_service.dart';
import '../widgets/assistant_header.dart';
import '../widgets/chat_input_card.dart';
import '../widgets/explain_sleep_card.dart';
import '../widgets/suggestion_card.dart';

/// 睡眠助理。答案來自後端的 Claude（`POST /chat`），只根據這個人自己的資料。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ LLM 是唯一的答案來源（計畫檔 B6，使用者的決定）
/// ═══════════════════════════════════════════════════════════════════
///
/// 這裡原本是一個查表路由器（`services/assistant_answers.dart`，12 個主題），
/// 當時的理由是「不重複付費、離線可用」。使用者在計畫檔選擇改用 LLM 當唯一
/// 來源，查表因此退場——那支檔案與它的測試還留著，計畫檔提過可以用
/// `--dart-define` 旗標把它留成離線退路，但**預設不接**。
///
/// ⚠️ 連不到後端、伺服器沒設定金鑰、或回答沒過驗證時，**老實講答不出來**，
///    不在 Dart 編一段看起來像答案的通用句子。那正是這個畫面最早的問題：
///    寫死的關鍵字對照，回的是與使用者實際睡眠無關的話。
/// ⚠️ 失敗的原因照抄後端的 detail（沒設定／連不上／沒過驗證），不自己改寫。
/// ⚠️ 每問一次都會花 API 額度。
class AssistantScreen extends StatefulWidget {
  final String username;

  /// null = 這支 build 沒有後端。
  final ChatService? chat;

  const AssistantScreen({
    super.key,
    this.username = kFallbackDisplayName,
    this.chat,
  });

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  bool isLoading = false;

  String aiResponse = "Ask Sonnap a question about last night's sleep.";

  String lastQuestion = "";

  Future<void> _sendQuestion(String question) async {
    final cleanedQuestion = question.trim();

    if (cleanedQuestion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a question.")),
      );
      return;
    }

    if (isLoading) return;

    final chat = widget.chat;
    if (chat == null) {
      setState(() {
        lastQuestion = cleanedQuestion;
        aiResponse = "The sleep assistant needs the Sonnap backend. "
            "Connect to the server to ask questions about your sleep.";
      });
      return;
    }

    setState(() {
      isLoading = true;
      lastQuestion = cleanedQuestion;
    });

    final result = await chat.ask(cleanedQuestion);
    if (!mounted) return;

    setState(() {
      aiResponse = result.isOk
          ? result.answer!
          : (result.message ?? "The sleep assistant cannot be reached right now.");
      isLoading = false;
    });
  }

  void _openHistory() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Chat history will be added later.")),
    );
  }

  void _askAgain() {
    if (lastQuestion.isEmpty || isLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ask a question first.")),
      );
      return;
    }
    _sendQuestion(lastQuestion);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    return SafeArea(
      child: Center(
        child: SizedBox(
          width: screenWidth > 520 ? 520 : screenWidth,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AssistantHeader(username: widget.username),
                const SizedBox(height: 18),
                ChatInputCard(onSend: _sendQuestion, onHistory: _openHistory),
                const SizedBox(height: 18),
                ExplainSleepCard(explanation: aiResponse, isLoading: isLoading),
                const SizedBox(height: 18),
                SuggestionCard(onQuestionSelected: _sendQuestion),
                const SizedBox(height: 16),
                if (lastQuestion.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: isLoading ? null : _askAgain,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text("Ask Again"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
