import 'package:flutter/material.dart';

class FriendPet {
  final String emoji;
  final String name;
  final String owner;
  final String status;
  final String lastInfo;
  final String mood;
  final String moodNote;
  final String moodEmoji;
  final Color pawColor;
  final Color onlineColor;
  final Color statusColor;
  final Color moodColor;

  const FriendPet({
    required this.emoji,
    required this.name,
    required this.owner,
    required this.status,
    required this.lastInfo,
    required this.mood,
    required this.moodNote,
    required this.moodEmoji,
    required this.pawColor,
    required this.onlineColor,
    required this.statusColor,
    required this.moodColor,
  });
}