import 'package:flutter/material.dart';

import '../widgets/feature_card.dart';
import '../widgets/header_card.dart';
import '../widgets/pet_card.dart';
import '../widgets/pet_mood_card.dart';
import '../widgets/sleep_score_card.dart';
import '../widgets/sleep_streak_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _showComingSoon(
    BuildContext context,
    String feature,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("$feature will be available later."),
      ),
    );
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
              children: [
                HeaderCard(
                  username: "Jeremy",
                  message: "Let's get a good night's sleep!",
                  initialReminderOn: true,
                  initialTargetBedtime: const TimeOfDay(
                    hour: 23,
                    minute: 30,
                  ),
                  onReminderChanged: (value) {
                    debugPrint("Reminder: $value");
                    // Save to local storage or backend later.
                  },
                  onBedtimeChanged: (value) {
                    debugPrint(
                      "Bedtime: "
                      "${value.hour.toString().padLeft(2, '0')}:"
                      "${value.minute.toString().padLeft(2, '0')}",
                    );
                    // Save to local storage or backend later.
                  },
                ),

                const SleepStreakCard(
                  streakDays: 12,
                  completedDays: 7,
                  encouragement: "Amazing consistency!",
                  completedColor: Color(0xFF9AD36A),
                  iconBackgroundColor: Color(0xFFFF7043),
                ),

                PetCard(
                  message: "Sweet dreams\nare waiting\nfor us! 🌙",
                  animationPath: "assets/animations/happy_dog.json",
                  onDiaryTap: () {
                    _showComingSoon(context, "Dream Diary");
                  },
                  onFlowerTap: () {
                    _showComingSoon(context, "Pet activity");
                  },
                ),

                const Row(
                  children: [
                    Expanded(
                      child: SleepScoreCard(
                        score: 82,
                        message: "Great job!",
                        progressColor: Color(0xFF9AD36A),
                        icon: Icons.sentiment_satisfied_alt,
                      ),
                    ),

                    SizedBox(width: 12),

                    Expanded(
                      child: PetMoodCard(
                        mood: "Happy",
                        description: "Your buddy is feeling great!",
                        icon: Icons.sentiment_very_satisfied,
                        moodColor: Color(0xFF7ED957),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                Row(
                  children: [
                    Expanded(
                      child: FeatureCard(
                        icon: Icons.checkroom_rounded,
                        title: "Closet",
                        subtitle: "Dress up your buddy!",
                        onTap: () {
                          _showComingSoon(context, "Closet");
                        },
                      ),
                    ),

                    const SizedBox(width: 16),

                    Expanded(
                      child: FeatureCard(
                        icon: Icons.card_giftcard_rounded,
                        title: "Rewards",
                        subtitle:
                            "Complete goals\nand unlock\nawesome rewards!",
                        onTap: () {
                          _showComingSoon(context, "Rewards");
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}