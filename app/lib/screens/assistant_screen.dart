import 'package:flutter/material.dart';

import '../models/sleep_session.dart';
import '../services/assistant_answers.dart';
import '../services/sleep_repository.dart';
import '../widgets/assistant_header.dart';
import '../widgets/chat_input_card.dart';
import '../widgets/explain_sleep_card.dart';
import '../widgets/suggestion_card.dart';

/// 睡眠助理。回答**完全來自 `app_payload.json`**，不呼叫任何線上服務。
///
/// 修改前這裡是一組寫死的關鍵字對照，回的是與使用者實際睡眠無關的通用句子，
/// 而且答不出來時說 "The real AI response will appear here after the backend
/// is connected."——那等於承諾一個不存在的功能。
///
/// 現在改成讀與首頁**同一份 payload**，回答邏輯在
/// `services/assistant_answers.dart`（抽出去才測得到，且能確保每個回答
/// 都追溯得到某個後端欄位）。
///
/// ⚠️ 這裡刻意**不接 Claude API**。理由有三：
///   1. payload 裡的 `ai_content.advice` 已經是 Claude 生成的，
///      每晚一次、在 pipeline 跑完時就產好了——問答再打一次 API
///      等於為同一件事付兩次費用
///   2. 資料通道已定案走 bundled asset 不走 HTTP（見 CLAUDE.md）
///   3. 離線可用，demo 不依賴網路
class AssistantScreen extends StatefulWidget {
  final String username;
  final SleepRepository repository;

  const AssistantScreen({
    super.key,
    this.username = "Jeremy",
    this.repository = const AssetSleepRepository(),
  });

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  bool isLoading = false;

  String aiResponse =
      "Ask Sonnap a question about last night's sleep.";

  String lastQuestion = "";

  /// 載入一次就留著，之後每個問題都用同一份資料回答。
  SleepSession? _session;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    try {
      final session = await widget.repository.load();
      if (!mounted) return;
      setState(() {
        _session = session;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = "$error";
      });
    }
  }

  Future<void> _sendQuestion(String question) async {
    final cleanedQuestion = question.trim();

    if (cleanedQuestion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter a question."),
        ),
      );
      return;
    }

    if (isLoading) return;

    setState(() {
      isLoading = true;
      lastQuestion = cleanedQuestion;
    });

    // 資料還沒載進來（或載入失敗）就先補一次，不要直接回答不出來
    if (_session == null) {
      await _loadSession();
    }

    if (!mounted) return;

    if (_session == null) {
      setState(() {
        aiResponse = "Your sleep data could not be loaded, so I cannot answer "
            "questions about it yet.\n\n"
            "Run `python garmin/run_pipeline.py` to generate "
            "assets/data/app_payload.json, then rebuild the app."
            "${_loadError != null ? '\n\n$_loadError' : ''}";
        isLoading = false;
      });
      return;
    }

    final answer = answerQuestion(cleanedQuestion, _session);

    setState(() {
      aiResponse = answer.text;
      isLoading = false;
    });
  }

  void _openHistory() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Chat history will be added later."),
      ),
    );
  }

  void _askAgain() {
    if (lastQuestion.isEmpty || isLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Ask a question first."),
        ),
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
                AssistantHeader(
                  username: widget.username,
                ),

                const SizedBox(height: 18),

                ChatInputCard(
                  onSend: _sendQuestion,
                  onHistory: _openHistory,
                ),

                const SizedBox(height: 18),

                ExplainSleepCard(
                  explanation: aiResponse,
                  isLoading: isLoading,
                ),

                const SizedBox(height: 18),

                SuggestionCard(
                  onQuestionSelected: _sendQuestion,
                ),

                const SizedBox(height: 16),

                if (lastQuestion.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: isLoading ? null : _askAgain,
                      icon: const Icon(
                        Icons.refresh_rounded,
                      ),
                      label: const Text(
                        "Ask Again",
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(
                          color: Colors.white24,
                        ),
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