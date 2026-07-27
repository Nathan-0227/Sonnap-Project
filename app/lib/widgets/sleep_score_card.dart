import 'package:flutter/material.dart';

class SleepScoreCard extends StatelessWidget {
  final int score;
  final String message;
  final Color progressColor;
  final IconData icon;

  const SleepScoreCard({
  super.key,
  required this.score,
  required this.message,
  required this.progressColor,
  required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (score / 100).clamp(0.0, 1.0);

    return Container(
      height: 150,
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
                  "Sleep Score",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),

                const SizedBox(height: 8),

                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: "$score",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const TextSpan(
                        text: "/100",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                Text(
                  message,
                  style: TextStyle(
                    color: progressColor,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 8,
                  backgroundColor: Colors.white24,
                  color: const Color(0xFF9AD36A),
                ),
              ),
              Icon(
                icon,
                color: progressColor,
                size: 34,
              ),
            ],
          ),
        ],
      ),
    );
  }
}