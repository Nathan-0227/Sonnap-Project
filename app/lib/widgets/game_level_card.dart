import 'package:flutter/material.dart';

import '../services/game_service.dart';

/// 首頁的等級卡：等級、成長階段、這一級的進度、XP 從哪來。
///
/// ⚠️ 每一個數字都照抄後端（`GET /game`）。尤其是進度條——它是**這一級**
/// 走了多少，由後端的 `progress` 給；在這裡用 xpTotal 自己除，升級那一刻
/// 進度條不會歸零，使用者就看不出自己升級了。
///
/// ⚠️ 刻意把 XP 的來源拆開列出來（行為／睡眠品質／挑戰獎勵）。只給一個
/// 總數的話，使用者看不出「準時放下手機」才是大宗——而那正是這個
/// 遊戲化層想讓人看見的事（設計紅線 5）。
class GameLevelCard extends StatelessWidget {
  final GameState state;
  final VoidCallback? onRewardsTap;

  const GameLevelCard({super.key, required this.state, this.onRewardsTap});

  static String stageLabel(String stage) {
    switch (stage) {
      case 'adult':
        return 'Grown-up';
      case 'young':
        return 'Young';
      default:
        return 'Baby';
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = state.sources;
    final ready = state.claimable.length;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF10265A),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star_rounded, color: Color(0xFFFFD96A), size: 22),
              const SizedBox(width: 8),
              Text(
                'Level ${state.level}',
                key: const Key('game-level'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF233A73),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  stageLabel(state.growthStage),
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
              const Spacer(),
              const Text(
                'from backend',
                style: TextStyle(color: Color(0xFF5B6E8C), fontSize: 8),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              key: const Key('game-progress'),
              value: state.progress,
              minHeight: 8,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(Color(0xFF8B6DFF)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            // ⚠️ 「最高級」要自己一句話，不能顯示成「0 XP to the next level」。
            state.maxLevel || state.xpForNext == null
                ? 'Max level reached'
                : '${state.xpForNext} XP to the next level',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Behaviour ${s.behaviour} · Sleep ${s.sleepQuality} · '
            'Rewards ${s.challengeRewards} XP',
            key: const Key('game-sources'),
            style: const TextStyle(color: Color(0xFF8498B7), fontSize: 11),
          ),
          if (ready > 0) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: onRewardsTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.card_giftcard_rounded,
                        color: Color(0xFF7ED957), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      ready == 1 ? '1 reward ready to claim' : '$ready rewards ready to claim',
                      style: const TextStyle(
                        color: Color(0xFF7ED957),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
