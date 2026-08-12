import 'package:flutter/material.dart';

import '../models/sleep_session.dart';
import '../services/sleep_repository.dart';
import '../widgets/feature_card.dart';
import '../widgets/header_card.dart';
import '../widgets/pet_card.dart';
import '../widgets/pet_mood_card.dart';
import '../widgets/sleep_score_card.dart';
import '../widgets/sleep_streak_card.dart';

/// 首頁。資料來自 `assets/data/app_payload.json`（由 Python pipeline 產生）。
///
/// 這裡刻意**不對數據做任何判斷**——分數好不好、該顯示哪種心情、該說哪句話，
/// 全部由後端算好放在 payload 裡。專案原則是「Python 判斷，Dart 只負責畫」，
/// 這樣所有判斷都可以追溯到有文獻依據的那一層。
class HomeScreen extends StatefulWidget {
  final SleepRepository repository;

  const HomeScreen({
    super.key,
    this.repository = const AssetSleepRepository(),
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// 在 initState 建立而不是在 build 裡——放 build 的話每次重繪都會重讀檔案。
  late Future<SleepSession> _sessionFuture;

  @override
  void initState() {
    super.initState();
    _sessionFuture = widget.repository.load();
  }

  void _reload() {
    setState(() {
      _sessionFuture = widget.repository.load();
    });
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("$feature will be available later.")),
    );
  }

  /// 夢境日記。
  ///
  /// ⚠️ 標題必須寫成「寵物的夢」——Garmin 完全沒有量測夢境內容，
  /// 寫成「你的夢」就是誤述資料支持的範圍。disclaimer 一併顯示。
  void _showDream(SleepSession session) {
    final ai = session.aiContent;
    if (!ai.hasDream) {
      _showComingSoon("Dream Diary");
      return;
    }

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF10265A),
        title: const Text(
          "Your buddy's dream diary",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ai.dreamSummary!,
                style: const TextStyle(color: Colors.white70, height: 1.5),
              ),
              const SizedBox(height: 16),
              Text(
                session.disclaimer ?? "",
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close",
                style: TextStyle(color: Color(0xFFFFD96A))),
          ),
        ],
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
          child: FutureBuilder<SleepSession>(
            future: _sessionFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF8B6DFF)),
                );
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return _buildError(snapshot.error);
              }
              return _buildContent(snapshot.data!);
            },
          ),
        ),
      ),
    );
  }

  /// 讀不到資料時要明確講出原因與解法，不要留白畫面。
  /// 最可能的原因就是還沒跑過 pipeline，asset 檔根本不存在。
  Widget _buildError(Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded,
                color: Colors.white38, size: 48),
            const SizedBox(height: 16),
            const Text(
              "No sleep data yet",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Run `python garmin/run_pipeline.py` to generate\n"
              "assets/data/app_payload.json, then rebuild the app.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text("Retry"),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 16),
              Text(
                "$error",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white24, fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContent(SleepSession session) {
    final display = session.display;
    final scoreColor = Color(display.colorValue);
    final mood = session.status.petMood;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          HeaderCard(
            username: "Jeremy",
            message: display.headerMessage,
            initialReminderOn: true,
            initialTargetBedtime: const TimeOfDay(hour: 23, minute: 30),
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

          SleepStreakCard(
            streakDays: session.streak.streakDays,
            completedDays: session.streak.completedDays,
            encouragement: display.streakEncouragement,
            completedColor: const Color(0xFF9AD36A),
            iconBackgroundColor: const Color(0xFFFF7043),
          ),

          PetCard(
            message: display.petMessage,
            animationPath: "assets/animations/happy_dog.json",
            onDiaryTap: () => _showDream(session),
            onFlowerTap: () => _showComingSoon("Pet activity"),
          ),

          // IntrinsicHeight + stretch：兩張卡的高度下限都是 150，但內容較長時
          // （例如心情是 "Anxious"）其中一張會長高。包一層讓兩張一起長，
          // 否則會一高一矮、垂直置中看起來歪掉。
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SleepScoreCard(
                    score: session.scoring.scoreAsInt,
                    message: display.scoreMessage,
                    progressColor: scoreColor,
                    icon: _scoreIcon(session.scoring.finalQuality),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PetMoodCard(
                    mood: _moodLabel(mood),
                    description: display.moodDescription,
                    icon: _moodIcon(mood),
                    moodColor: _moodColor(mood),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: FeatureCard(
                  icon: Icons.checkroom_rounded,
                  title: "Closet",
                  subtitle: "Dress up your buddy!",
                  onTap: () => _showComingSoon("Closet"),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FeatureCard(
                  icon: Icons.card_giftcard_rounded,
                  title: "Rewards",
                  subtitle: "Complete goals\nand unlock\nawesome rewards!",
                  onTap: () => _showComingSoon("Rewards"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 純呈現的對映：把後端給的字串換成圖示與顏色 ──────────────────
  // 這裡不做任何判斷，只是查表。「哪種分數對應哪種心情」的判斷在後端。

  static String _moodLabel(String mood) =>
      mood.isEmpty ? "Unknown" : mood[0].toUpperCase() + mood.substring(1);

  static IconData _moodIcon(String mood) {
    switch (mood) {
      case 'happy':
        return Icons.sentiment_very_satisfied;
      case 'bored':
        return Icons.sentiment_neutral;
      case 'tired':
        return Icons.sentiment_dissatisfied;
      case 'anxious':
        return Icons.sentiment_very_dissatisfied;
      default:
        return Icons.sentiment_neutral;
    }
  }

  static Color _moodColor(String mood) {
    switch (mood) {
      case 'happy':
        return const Color(0xFF7ED957);
      case 'bored':
        return const Color(0xFFFFC83D);
      case 'tired':
        return const Color(0xFFFF9518);
      case 'anxious':
        return const Color(0xFFFF4F63);
      default:
        return const Color(0xFFFFC83D);
    }
  }

  static IconData _scoreIcon(String quality) {
    switch (quality) {
      case 'Good':
        return Icons.sentiment_satisfied_alt;
      case 'Normal':
        return Icons.sentiment_neutral;
      default:
        return Icons.sentiment_dissatisfied;
    }
  }
}
