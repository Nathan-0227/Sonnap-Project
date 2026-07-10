import 'package:flutter/material.dart';

class SleepStreakCard extends StatelessWidget {
  final int streakDays;
  final int completedDays;
  final String encouragement;
  final List<String> weekdays;
  final IconData icon;
  final Color iconBackgroundColor;
  final Color completedColor;

  const SleepStreakCard({
    super.key,
    required this.streakDays,
    required this.completedDays,
    required this.encouragement,
    this.weekdays = const [
      "Mon",
      "Tue",
      "Wed",
      "Thu",
      "Fri",
      "Sat",
      "Sun",
    ],
    this.icon = Icons.local_fire_department,
    this.iconBackgroundColor = const Color(0xFFFFA726),
    this.completedColor = const Color(0xFFFFD96A),
  });

  @override
  Widget build(BuildContext context) {
    final safeCompletedDays = completedDays.clamp(
      0,
      weekdays.length,
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2548),
        borderRadius: BorderRadius.circular(22),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isVeryNarrow = constraints.maxWidth < 360;

          if (isVeryNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StreakSummary(
                  streakDays: streakDays,
                  encouragement: encouragement,
                  icon: icon,
                  iconBackgroundColor: iconBackgroundColor,
                  completedColor: completedColor,
                ),
                const SizedBox(height: 16),
                Center(
                  child: _WeekProgress(
                    weekdays: weekdays,
                    completedDays: safeCompletedDays,
                    completedColor: completedColor,
                  ),
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 4,
                child: _StreakSummary(
                  streakDays: streakDays,
                  encouragement: encouragement,
                  icon: icon,
                  iconBackgroundColor: iconBackgroundColor,
                  completedColor: completedColor,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                flex: 5,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: _WeekProgress(
                      weekdays: weekdays,
                      completedDays: safeCompletedDays,
                      completedColor: completedColor,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StreakSummary extends StatelessWidget {
  final int streakDays;
  final String encouragement;
  final IconData icon;
  final Color iconBackgroundColor;
  final Color completedColor;

  const _StreakSummary({
    required this.streakDays,
    required this.encouragement,
    required this.icon,
    required this.iconBackgroundColor,
    required this.completedColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 23,
          backgroundColor: iconBackgroundColor,
          child: Icon(
            icon,
            color: Colors.white,
            size: 27,
          ),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Sleep Streak",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),

              const SizedBox(height: 2),

              Text(
                "$streakDays Days",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: completedColor,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 2),

              Text(
                encouragement,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeekProgress extends StatelessWidget {
  final List<String> weekdays;
  final int completedDays;
  final Color completedColor;

  const _WeekProgress({
    required this.weekdays,
    required this.completedDays,
    required this.completedColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            weekdays.length,
            (index) {
              final isCompleted = index < completedDays;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: CircleAvatar(
                  radius: 12,
                  backgroundColor: isCompleted
                      ? completedColor
                      : Colors.white24,
                  child: isCompleted
                      ? const Icon(
                          Icons.check,
                          color: Colors.black,
                          size: 14,
                        )
                      : null,
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 7),

        Row(
          mainAxisSize: MainAxisSize.min,
          children: weekdays.map((day) {
            return SizedBox(
              width: 30,
              child: Text(
                day,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}