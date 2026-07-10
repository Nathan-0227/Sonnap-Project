import 'package:flutter/material.dart';

class SuggestionItem {
  final IconData icon;
  final String question;

  const SuggestionItem({
    required this.icon,
    required this.question,
  });
}

class SuggestionCard extends StatelessWidget {
  final List<SuggestionItem> suggestions;
  final ValueChanged<String> onQuestionSelected;

  const SuggestionCard({
    super.key,
    required this.onQuestionSelected,
    this.suggestions = const [
      SuggestionItem(
        icon: Icons.bedtime_rounded,
        question: "Why am I tired today?",
      ),
      SuggestionItem(
        icon: Icons.auto_graph_rounded,
        question: "How can I improve my sleep score?",
      ),
      SuggestionItem(
        icon: Icons.nightlight_round,
        question: "How much deep sleep did I get?",
      ),
      SuggestionItem(
        icon: Icons.favorite_rounded,
        question: "How is my pet's mood related to my sleep?",
      ),
      SuggestionItem(
        icon: Icons.lightbulb_outline_rounded,
        question: "Give me some tips for tonight.",
      ),
    ],
  });

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Suggested Questions",
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 16),

        ...suggestions.map(
          (suggestion) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  onQuestionSelected(suggestion.question);
                },
                borderRadius: BorderRadius.circular(22),
                child: Ink(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10265A),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFF233A73),
                        child: Icon(
                          suggestion.icon,
                          color: const Color(0xFFFFD96A),
                          size: 22,
                        ),
                      ),

                      const SizedBox(width: 16),

                      Expanded(
                        child: Text(
                          suggestion.question,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: Colors.white38,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}