import 'package:flutter/material.dart';

import '../widgets/assistant_header.dart';
import '../widgets/chat_input_card.dart';
import '../widgets/explain_sleep_card.dart';
import '../widgets/suggestion_card.dart';

class AssistantScreen extends StatefulWidget {
  final String username;

  const AssistantScreen({
    super.key,
    this.username = "Jeremy",
  });

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  bool isLoading = false;

  String aiResponse =
      "Ask Sonnap a question to receive a sleep explanation.";

  String lastQuestion = "";

  Future<String> _getMockAiResponse(String question) async {
    await Future.delayed(const Duration(seconds: 1));

    final normalizedQuestion = question.toLowerCase();

    if (normalizedQuestion.contains("tired")) {
      return "You may feel tired because your sleep duration was shorter "
          "than usual and your bedtime was later than your target.";
    }

    if (normalizedQuestion.contains("sleep score")) {
      return "You can improve your sleep score by keeping a consistent "
          "bedtime, sleeping long enough, and reducing movement before sleep.";
    }

    if (normalizedQuestion.contains("deep sleep")) {
      return "Your deep sleep may be affected by short sleep duration, "
          "stress, late-night phone use, and an inconsistent bedtime.";
    }

    if (normalizedQuestion.contains("pet")) {
      return "Your pet's mood represents your recent sleep quality. "
          "Better and more consistent sleep can help your pet look happier.";
    }

    if (normalizedQuestion.contains("tips")) {
      return "Try to avoid screens before bedtime, keep your room quiet, "
          "and follow the same sleep schedule every night.";
    }

    return "This is a temporary response for:\n\n"
        "\"$question\"\n\n"
        "The real AI response will appear here after the backend is connected.";
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

    try {
      final response = await _getMockAiResponse(cleanedQuestion);

      if (!mounted) return;

      setState(() {
        aiResponse = response;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        aiResponse =
            "Something went wrong while processing your question. "
            "Please try again.";
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Unable to get an AI response."),
        ),
      );
    }
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