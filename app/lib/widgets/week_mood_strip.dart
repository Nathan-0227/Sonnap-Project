import 'package:flutter/material.dart';

import '../models/sleep_session.dart';
import '../theme/sonnap_colors.dart';

/// 首頁上方的一週日期列：最近 7 天，每天一個心情小圖示。只顯示，不能點。
///
/// ⚠️ 用心情圖示而不是寵物小臉：2D 小狗目前只有兩種樣子，用小臉的話
///    anxious 那晚看起來會跟 bored 一樣（2026-11-12 使用者決定）。
/// ⚠️ 心情照抄 history 每晚的 `pet_mood`，Dart 不從分數推。
class WeekMoodStrip extends StatelessWidget {
  final List<HistoryEntry> history;

  const WeekMoodStrip({super.key, required this.history});

  /// 以最新那一晚為終點往回 7 個日曆天。中間沒資料的那天留空格，
  /// 不能直接取最後 7 筆——那會把「中間沒戴錶」的日子藏起來。
  static List<(DateTime, HistoryEntry?)> lastSevenDays(
      List<HistoryEntry> history) {
    final byDate = <String, HistoryEntry>{};
    DateTime? latest;
    for (final e in history) {
      final d = DateTime.tryParse(e.date);
      if (d == null) continue;
      byDate[e.date] = e;
      if (latest == null || d.isAfter(latest)) latest = d;
    }
    if (latest == null) return const [];
    return [
      for (var i = 6; i >= 0; i--)
        () {
          final d = DateTime(latest!.year, latest.month, latest.day - i);
          final key =
              '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          return (d, byDate[key]);
        }(),
    ];
  }

  static const _weekday = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final days = lastSevenDays(history);
    if (days.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const Key('week-strip'),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: sonnapCardDecoration(),
      child: Column(
        children: [
          Row(
        children: [
          for (final (i, (date, entry)) in days.indexed)
            Expanded(
              child: Column(
                children: [
                  Text(_weekday[date.weekday - 1],
                      style: const TextStyle(
                          color: SonnapColors.textMuted, fontSize: 11)),
                  const SizedBox(height: 2),
                  Text('${date.day}',
                      style: TextStyle(
                          color: i == days.length - 1
                              ? SonnapColors.textPrimary
                              : SonnapColors.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  MoodDot(mood: entry?.petMood),
                ],
              ),
            ),
        ],
      ),
          const SizedBox(height: 10),
          // 圖示說明（2026-11-12：使用者反映看不懂那排圖示代表什麼）
          const _MoodLegend(),
        ],
      ),
    );
  }
}

class _MoodLegend extends StatelessWidget {
  const _MoodLegend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: const Key('mood-legend'),
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final m in const ['happy', 'bored', 'tired', 'anxious'])
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(moodIcon(m), color: moodColor(m), size: 14),
              const SizedBox(width: 3),
              Text(moodLabel(m),
                  style: const TextStyle(
                      color: SonnapColors.textSecondary, fontSize: 11)),
            ],
          ),
      ],
    );
  }
}

/// 一晚的心情小圖示。四種心情的圖案與顏色都不同；null = 那天沒有資料。
class MoodDot extends StatelessWidget {
  final String? mood;
  const MoodDot({super.key, required this.mood});

  @override
  Widget build(BuildContext context) {
    final m = mood;
    if (m == null) {
      return Container(
        key: const Key('mood-dot-none'),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: SonnapColors.cardBorder, width: 2),
        ),
      );
    }
    return Container(
      key: Key('mood-dot-$m'),
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: moodColor(m).withValues(alpha: 0.18),
      ),
      child: Icon(moodIcon(m), color: moodColor(m), size: 18),
    );
  }
}

// ── 純呈現的對映：後端給的心情字串 → 圖示與顏色 ─────────────────
// 這裡不做判斷，只是查表。首頁的心情標籤與日期列共用這一份。

String moodLabel(String mood) =>
    mood.isEmpty ? 'Unknown' : mood[0].toUpperCase() + mood.substring(1);

IconData moodIcon(String mood) => switch (mood) {
      'happy' => Icons.sentiment_very_satisfied,
      'tired' => Icons.bedtime_outlined,
      'anxious' => Icons.sentiment_very_dissatisfied,
      _ => Icons.sentiment_neutral,
    };

Color moodColor(String mood) => switch (mood) {
      'happy' => const Color(0xFF7ED957),
      'tired' => const Color(0xFFFF9518),
      'anxious' => const Color(0xFFFF4F63),
      _ => const Color(0xFFFFC83D),
    };
