import 'package:flutter/material.dart';
import '../models/friend_pet.dart';

class FriendListCard extends StatelessWidget {
  final List<FriendPet> friends;
  final String selectedMood;
  final ValueChanged<FriendPet>? onVisit;

  const FriendListCard({
    super.key,
    required this.friends,
    required this.selectedMood,
    this.onVisit,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedMood = selectedMood.toLowerCase();

    final visibleFriends = normalizedMood == "all"
        ? friends
        : friends
            .where(
              (friend) => friend.mood.toLowerCase() == normalizedMood,
            )
            .toList();

    if (visibleFriends.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF10265A),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Column(
          children: [
            Icon(
              Icons.pets_rounded,
              color: Colors.white38,
              size: 42,
            ),
            SizedBox(height: 12),
            Text(
              "No friends found with this mood.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: visibleFriends.map((friend) {
        return FriendPetRow(
          emoji: friend.emoji,
          name: friend.name,
          pawColor: friend.pawColor,
          onlineColor: friend.onlineColor,
          owner: friend.owner,
          status: friend.status,
          lastInfo: friend.lastInfo,
          mood: friend.mood,
          moodNote: friend.moodNote,
          moodEmoji: friend.moodEmoji,
          statusColor: friend.statusColor,
          moodColor: friend.moodColor,
          onVisit: onVisit == null ? null : () => onVisit!(friend),
        );
      }).toList(),
    );
  }
}

class FriendPetRow extends StatelessWidget {
  final String emoji;
  final String name;
  final Color pawColor;
  final Color onlineColor;
  final String owner;
  final String status;
  final String lastInfo;
  final String mood;
  final String moodNote;
  final String moodEmoji;
  final Color statusColor;
  final Color moodColor;
  final VoidCallback? onVisit;

  const FriendPetRow({
    super.key,
    required this.emoji,
    required this.name,
    required this.pawColor,
    required this.onlineColor,
    required this.owner,
    required this.status,
    required this.lastInfo,
    required this.mood,
    required this.moodNote,
    required this.moodEmoji,
    required this.statusColor,
    required this.moodColor,
    this.onVisit,
  });

  @override
  Widget build(BuildContext context) {
    final isAsleep = status.toLowerCase() == "asleep";

    return Container(
      constraints: const BoxConstraints(
        minHeight: 112,
    ),

      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF10265A),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              SizedBox(
                width: 64,
                child: Center(
                  child: Text(
                    emoji,
                    style: const TextStyle(fontSize: 48),
                  ),
                ),
              ),
              Positioned(
                right: 4,
                bottom: 6,
                child: CircleAvatar(
                  radius: 7,
                  backgroundColor: onlineColor,
                ),
              ),
            ],
          ),

          const SizedBox(width: 10),

          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.pets, color: pawColor, size: 16),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  "Owner: $owner",
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),
          const _DividerLine(),
          const SizedBox(width: 8),

          Expanded(
             flex: 3,
             child: _InfoColumn(
             title: "Sleep Status",
             main: isAsleep ? "🌙 $status" : "📱 $status",
             subtitle: lastInfo,
             color: statusColor,
            ),
          ),

          const SizedBox(width: 8),
          const _DividerLine(),
          const SizedBox(width: 8),

          Expanded(
            flex: 2,
            child: _InfoColumn(
            title: "Pet Mood",
            main: "$moodEmoji $mood",
            subtitle: moodNote,
            color: moodColor,
            ),
          ),

          const SizedBox(width: 8),

          ElevatedButton(
            onPressed: onVisit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4E54D9),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 9,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Visit",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                SizedBox(width: 2),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoColumn extends StatelessWidget {
  final String title;
  final String main;
  final String subtitle;
  final Color color;

  const _InfoColumn({
    required this.title,
    required this.main,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
            ),
          ),

          const SizedBox(height: 7),

          Text(
            main,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 7),

          Text(
            subtitle,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _DividerLine extends StatelessWidget {
  const _DividerLine();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 68,
      color: Colors.white12,
    );
  }
}