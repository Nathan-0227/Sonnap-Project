import 'package:flutter/material.dart';
import '../models/friend_pet.dart';
import '../widgets/top_streak_card.dart';
import '../widgets/mood_filter_bar.dart';
import '../widgets/friend_list_card.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  String selectedMood = "All";

  final List<FriendPet> friends = const [
    FriendPet(
      emoji: "🐰",
      name: "Mochi",
      owner: "Katy",
      status: "Asleep",
      lastInfo: "Last Sleep 22:42",
      mood: "Happy",
      moodNote: "Feeling great!",
      moodEmoji: "🙂",
      pawColor: Color(0xFFFFA6B7),
      onlineColor: Color(0xFF7ED957),
      statusColor: Color(0xFF6A5CFF),
      moodColor: Color(0xFF7ED957),
    ),
    FriendPet(
      emoji: "🐶",
      name: "Coco",
      owner: "Andrew",
      status: "Not Yet",
      lastInfo: "Not asleep yet",
      mood: "Tired",
      moodNote: "Needs more rest",
      moodEmoji: "😟",
      pawColor: Color(0xFFFFB300),
      onlineColor: Color(0xFFFFB300),
      statusColor: Color(0xFF8B6DFF),
      moodColor: Color(0xFFFFB300),
    ),
    FriendPet(
      emoji: "🐱",
      name: "Nala",
      owner: "Emil",
      status: "Asleep",
      lastInfo: "Last Sleep 23:10",
      mood: "Happy",
      moodNote: "Slept well!",
      moodEmoji: "🙂",
      pawColor: Color(0xFF5B5CFF),
      onlineColor: Color(0xFF7ED957),
      statusColor: Color(0xFF6A5CFF),
      moodColor: Color(0xFF7ED957),
    ),
    FriendPet(
      emoji: "🐕",
      name: "Dango",
      owner: "Heidi",
      status: "Not Yet",
      lastInfo: "Online now",
      mood: "Sick",
      moodNote: "Take care!",
      moodEmoji: "😟",
      pawColor: Color(0xFFFF5252),
      onlineColor: Color(0xFFFF5252),
      statusColor: Color(0xFF8B6DFF),
      moodColor: Color(0xFFFF5252),
    ),
  ];

  final List<TopStreakUser> topStreakUsers = const [
    TopStreakUser(
      rank: 1,
      emoji: "🐱",
      name: "Katy",
      streakDays: 12,
      bestDays: 15,
    ),
    TopStreakUser(
      rank: 2,
      emoji: "🐶",
      name: "Jamie",
      streakDays: 8,
      bestDays: 10,
    ),
    TopStreakUser(
      rank: 3,
      emoji: "🐰",
      name: "Emil",
      streakDays: 7,
      bestDays: 12,
    ),
  ];

  void _visitFriend(FriendPet friend) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Visiting ${friend.name}'s pet..."),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asleepCount =
        friends.where((f) => f.status.toLowerCase() == "asleep").length;

    final notAsleepCount = friends.length - asleepCount;
    
    return SafeArea(
      child: Center(
        child: SizedBox(
          width: MediaQuery.of(context).size.width > 650
              ? 650
              : MediaQuery.of(context).size.width,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Friends ✨",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  "See how your friends' pets are doing tonight.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                  ),
                ),

                const SizedBox(height: 24),

                Container(
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
                      const Row(
                        children: [
                          Icon(
                            Icons.groups_rounded,
                            color: Color(0xFF7C6DFF),
                          ),
                          SizedBox(width: 8),
                          Text(
                            "Sleep Circle",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                const CircleAvatar(
                                  radius: 22,
                                  backgroundColor: Color(0xFF3546B8),
                                  child: Icon(
                                    Icons.nightlight_round,
                                    color: Color(0xFFFFD96A),
                                  ),
                                ),

                                const SizedBox(width: 12),

                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "$asleepCount",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Text(
                                      "Friends asleep",
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          Container(
                            width: 1,
                            height: 55,
                            color: Colors.white12,
                          ),

                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                const CircleAvatar(
                                  radius: 22,
                                  backgroundColor: Color(0xFF7C6DFF),
                                  child: Icon(
                                    Icons.phone_android_rounded,
                                    color: Colors.white,
                                  ),
                                ),

                                const SizedBox(width: 12),

                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "$notAsleepCount",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Text(
                                      "Not asleep yet",
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                TopStreakCard(
                  users: topStreakUsers,
                  onViewAll: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Full ranking will be available later.",
                        ),
                      ),
                    );
                  },
                ),

                MoodFilterBar(
                  selectedMood: selectedMood,
                  onMoodSelected: (mood) {
                    setState(() {
                      selectedMood = mood;
                    });
                  },
                ),

                FriendListCard(
                  friends: friends,
                  selectedMood: selectedMood,
                  onVisit: _visitFriend,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}