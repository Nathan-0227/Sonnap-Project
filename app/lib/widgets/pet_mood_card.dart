import 'package:flutter/material.dart';

class PetMoodCard extends StatelessWidget {
  final String mood;
  final String description;
  final IconData icon;
  final Color moodColor;

  const PetMoodCard({
    super.key,
    required this.mood,
    required this.description,
    required this.icon,
    required this.moodColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // 原本是固定 height: 150。改成 minHeight 是因為較長的心情字（例如
      // "Anxious"，contract 的四個合法值之一）在 150 高度下會撐破版面、
      // 出現黃黑斜線。改成下限之後短字維持原樣，只有放不下時才長高。
      constraints: const BoxConstraints(minHeight: 150),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10265A),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Pet Mood",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  mood,
                  style: TextStyle(
                    color: moodColor,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  description,
                  maxLines: 2,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            icon,
            color: moodColor,
            size: 50,
          ),
        ],
      ),
    );
  }
}