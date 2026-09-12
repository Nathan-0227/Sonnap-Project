import 'package:flutter/material.dart';

class MoodFilterBar extends StatelessWidget {
  final String selectedMood;
  final ValueChanged<String> onMoodSelected;

  /// 要顯示哪些選項。不給就用 [moods]（原本的五個）。
  ///
  /// ⚠️ 好友畫面會傳一份不含「Sick」的清單：朋友之間只分享行為版心情，
  /// 永遠不會出現生理來源的狀態，留著那個選項只會永遠篩出空的一頁。
  final List<Map<String, String>>? options;

  const MoodFilterBar({
    super.key,
    required this.selectedMood,
    required this.onMoodSelected,
    this.options,
  });

  static const List<Map<String, String>> moods = [
    {
      "label": "All",
      "emoji": "",
    },
    {
      "label": "Happy",
      "emoji": "🙂",
    },
    {
      "label": "Normal",
      "emoji": "😐",
    },
    {
      "label": "Tired",
      "emoji": "😟",
    },
    {
      "label": "Sick",
      "emoji": "😡",
    },
  ];

  @override
  Widget build(BuildContext context) {
    final normalizedSelection = selectedMood.toLowerCase();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF10265A),
        borderRadius: BorderRadius.circular(22),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: (options ?? moods).map((mood) {
            final label = mood["label"]!;
            final emoji = mood["emoji"]!;

            final isSelected =
                normalizedSelection == label.toLowerCase();

            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                onTap: () => onMoodSelected(label),
                borderRadius: BorderRadius.circular(18),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF5B5CFF)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    emoji.isEmpty ? label : "$emoji  $label",
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : Colors.white70,
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}