import 'package:flutter/material.dart';

import '../models/sleep_session.dart';
import '../theme/sonnap_colors.dart';

/// 首頁上方的一週日期列：最近 7 天，每天一個心情小圖示。
/// 每一天都能點，打開那一晚的早晨報告（[onDayTap]，2026-11-12）。
///
/// ⚠️ **沒有心情的那天也要能點、也要畫出來**（使用者定）：心情來自打包檔，
///    要等電腦跑完早晨匯入才會多出那一晚；分數卻可能更早由 Health Connect
///    送到後端。等待畫面叫使用者「回首頁點這一天」，那一天就必須在、而且點得到。
///    所以終點是 [today] 而不是 history 最新那一晚。
///
/// 每一天畫的是**寵物的狗頭表情**（[MoodFace]，2026-11-13 使用者給的四張圖）。
/// 起床自評卡那五顆圓臉是「你覺得怎樣」，這裡是「寵物的心情」——兩種不能用同一套臉，
/// 不然同一個早上會看到兩個意思不同的同一張臉。
/// （11-12 不用小臉，是因為 2D 小狗當時只有兩種身體，anxious 會跟 bored 一樣；
///  狗頭四種表情都不同，那個理由不再成立。）
/// ⚠️ 心情照抄 history 每晚的 `pet_mood`，Dart 不從分數推。
class WeekMoodStrip extends StatelessWidget {
  final List<HistoryEntry> history;

  /// 點某一天。參數是那一晚的日期（YYYY-MM-DD，與 history 的 date 相同）。
  final ValueChanged<String>? onDayTap;

  /// 今天（日曆日）。給了就以它為終點；沒給就以 history 最新那一晚為終點。
  final DateTime? today;

  const WeekMoodStrip({
    super.key,
    required this.history,
    this.onDayTap,
    this.today,
  });

  static String dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 以最新那一晚為終點往回 7 個日曆天。中間沒資料的那天留空格，
  /// 不能直接取最後 7 筆——那會把「中間沒戴錶」的日子藏起來。
  static List<(DateTime, HistoryEntry?)> lastSevenDays(
      List<HistoryEntry> history, {DateTime? today}) {
    final byDate = <String, HistoryEntry>{};
    DateTime? latest;
    for (final e in history) {
      final d = DateTime.tryParse(e.date);
      if (d == null) continue;
      byDate[e.date] = e;
      if (latest == null || d.isAfter(latest)) latest = d;
    }
    if (today != null) {
      final t = DateTime(today.year, today.month, today.day);
      if (latest == null || t.isAfter(latest)) latest = t;
    }
    if (latest == null) return const [];
    return [
      for (var i = 6; i >= 0; i--)
        () {
          final d = DateTime(latest!.year, latest.month, latest.day - i);
          return (d, byDate[dateKey(d)]);
        }(),
    ];
  }

  static const _weekday = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final days = lastSevenDays(history, today: today);
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
              child: InkWell(
                key: Key('week-day-${date.day}'),
                borderRadius: BorderRadius.circular(12),
                onTap: onDayTap == null ? null : () => onDayTap!(dateKey(date)),
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
              MoodFace(mood: m, size: 18),
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
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: moodColor(m).withValues(alpha: 0.18),
        border: Border.all(color: moodColor(m).withValues(alpha: 0.7), width: 1.5),
      ),
      child: MoodFace(mood: m, size: 26),
    );
  }
}

// ── 純呈現的對映：後端給的心情字串 → 圖示與顏色 ─────────────────
// 這裡不做判斷，只是查表。首頁的心情標籤與日期列共用這一份。

/// 心情 → 狗頭表情圖。不認得的一律 bored（同 HomePet：絕不退回 happy）。
String moodFaceAsset(String mood) => switch (mood) {
      'happy' => 'assets/moods/dog_happy.png',
      'tired' => 'assets/moods/dog_tired.png',
      'anxious' => 'assets/moods/dog_anxious.png',
      _ => 'assets/moods/dog_bored.png',
    };

/// 寵物心情的狗頭表情。圖讀不到時退回 [moodIcon]（不會報錯、也不會空白）。
class MoodFace extends StatelessWidget {
  final String mood;
  final double size;
  const MoodFace({super.key, required this.mood, this.size = 24});

  @override
  Widget build(BuildContext context) => Image.asset(
        moodFaceAsset(mood),
        key: Key('mood-face-$mood'),
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) =>
            Icon(moodIcon(mood), color: moodColor(mood), size: size * 0.8),
      );
}

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
