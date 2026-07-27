import 'package:flutter/material.dart';

class TopStreakUser {
  final int rank;
  final String emoji;
  final String name;
  final int streakDays;
  final int bestDays;

  const TopStreakUser({
    required this.rank,
    required this.emoji,
    required this.name,
    required this.streakDays,
    required this.bestDays,
  });
}

class TopStreakCard extends StatelessWidget {
  final List<TopStreakUser> users;
  final VoidCallback? onViewAll;

  const TopStreakCard({
    super.key,
    required this.users,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final displayedUsers = users.take(3).toList();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF10265A),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_fire_department,
                color: Color(0xFFFFB300),
              ),

              const SizedBox(width: 8),

              const Expanded(
                child: Text(
                  "Sleep Streak (Top 3)",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              TextButton(
                onPressed: onViewAll,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white54,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "View All",
                      style: TextStyle(fontSize: 14),
                    ),
                    SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          if (displayedUsers.isEmpty)
            const SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  Icon(
                    Icons.emoji_events_outlined,
                    color: Colors.white38,
                    size: 42,
                  ),
                  SizedBox(height: 10),
                  Text(
                    "No streak data available.",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: displayedUsers.map((user) {
                return Expanded(
                  child: _TopUser(user: user),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _TopUser extends StatelessWidget {
  final TopStreakUser user;

  const _TopUser({
    required this.user,
  });

  Color get rankColor {
    switch (user.rank) {
      case 1:
        return const Color(0xFFFFD54F);
      case 2:
        return const Color(0xFFB0BEC5);
      case 3:
        return const Color(0xFFCD7F32);
      default:
        return Colors.white38;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: rankColor,
            child: Text(
              "${user.rank}",
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(height: 10),

          Text(
            user.emoji,
            style: const TextStyle(fontSize: 50),
          ),

          const SizedBox(height: 8),

          Text(
            user.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            "${user.streakDays} Days",
            style: const TextStyle(
              color: Color(0xFF7ED957),
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            "Best: ${user.bestDays} Days",
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}