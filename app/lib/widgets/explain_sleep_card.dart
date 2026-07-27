import 'package:flutter/material.dart';

class ExplainSleepCard extends StatelessWidget {
  final String explanation;
  final bool isLoading;

  const ExplainSleepCard({
    super.key,
    required this.explanation,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF10265A),
        borderRadius: BorderRadius.circular(24),
      ),
      child: isLoading
          ? const SizedBox(
              height: 170,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      color: Color(0xFF8B6DFF),
                    ),
                    SizedBox(height: 16),
                    Text(
                      "Analyzing your sleep data...",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Color(0xFF5B5CFF),
                      child: Icon(
                        Icons.smart_toy_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Sleep Explanation",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: Color(0xFFFFD96A),
                      size: 22,
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B2F63),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    explanation,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                const Row(
                  children: [
                    Icon(
                      Icons.insights_rounded,
                      color: Color(0xFF8B6DFF),
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      "What affected your sleep",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                const _ReasonRow(
                  icon: Icons.schedule_rounded,
                  title: "Late bedtime",
                  detail:
                      "You went to sleep later than your target bedtime.",
                ),

                const SizedBox(height: 10),

                const _ReasonRow(
                  icon: Icons.timelapse_rounded,
                  title: "Short sleep duration",
                  detail:
                      "Your total sleep duration was shorter than recommended.",
                ),

                const SizedBox(height: 10),

                const _ReasonRow(
                  icon: Icons.sync_problem_rounded,
                  title: "Inconsistent sleep schedule",
                  detail:
                      "Your bedtime changed frequently during the week.",
                ),

                const SizedBox(height: 18),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF243B78),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color:
                          const Color(0xFF5B5CFF).withValues(alpha: 0.45),
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_rounded,
                        color: Color(0xFFFFD96A),
                        size: 24,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "AI Recommendation",
                              style: TextStyle(
                                color: Color(0xFFFFD96A),
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              "Try following a consistent bedtime and avoid using your phone before sleeping.",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _ReasonRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _ReasonRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: Color(0xFF233A73),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: const Color(0xFFFFD96A),
            size: 19,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}