import 'package:flutter/material.dart';

import '../services/game_service.dart';
import '../theme/app_accent.dart';
import '../theme/sonnap_colors.dart';

/// 寵物頭上的等級（2026-11-21 使用者定）：★ Lv 徽章＋一條細進度條＋「185 XP to Lv 7」。
/// 首頁與睡眠計畫頁共用這一份；點了開獎勵頁。
///
/// ⚠️ 全部照抄後端 `/game`：條填多少是 [GameState.progress]、還差幾 XP 是
///    [GameState.xpForNext]。**不從 xpTotal 自己算**——升級曲線只在 `game/levels.py`。
/// ⚠️ 最高級（`max_level`，或 `xp_for_next` 是 null）：條畫滿、寫 Max level，不寫「0 XP to」。
class LevelProgress extends StatelessWidget {
  final GameState game;
  final VoidCallback? onTap;

  const LevelProgress({super.key, required this.game, this.onTap});

  static const double barWidth = 120;

  bool get _isMax => game.maxLevel || game.xpForNext == null;

  String get caption =>
      _isMax ? 'Max level' : '${game.xpForNext} XP to Lv ${game.level + 1}';

  @override
  Widget build(BuildContext context) {
    final progress = _isMax ? 1.0 : game.progress;
    return Semantics(
      button: onTap != null,
      label: 'Level ${game.level}, $caption',
      excludeSemantics: true,
      child: GestureDetector(
        key: const Key('level-progress'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                key: const Key('level-badge'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: accentOf(context).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accentOf(context)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, color: Color(0xFFFFD96A), size: 14),
                    const SizedBox(width: 3),
                    Text(
                      'Lv ${game.level}',
                      style: const TextStyle(
                        color: SonnapColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              // 細條：底槽＋金色那段（同早晨報告經驗條的金色）
              SizedBox(
                key: const Key('level-bar'),
                width: barWidth,
                height: 5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      key: const Key('level-bar-fill'),
                      widthFactor: progress.clamp(0.0, 1.0),
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD96A),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                caption,
                key: const Key('level-caption'),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  shadows: const [Shadow(color: Color(0x99000000), blurRadius: 4)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
