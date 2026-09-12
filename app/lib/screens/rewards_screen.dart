import 'package:flutter/material.dart';

import '../services/game_service.dart';

/// 獎勵：可以領的挑戰獎勵、徽章。
///
/// ⚠️ 「哪些可以領」「徽章拿到了沒」全部照抄後端（`GET /game`）。
/// 挑戰有沒有完成是 `behavior/challenges.py` 判定的，這裡再判一次就是
/// 第二個定義處。
///
/// ⚠️ 沒有東西可以領時，要**講清楚怎麼樣才會有**——空白一片的畫面會讓人
/// 以為這個功能壞了，或以為「多開幾次 App」就會有（那正是紅線 5 要避免的
/// 誤解：獎勵跟你做了什麼有關，跟你來了幾次無關）。
class RewardsScreen extends StatefulWidget {
  final GameService service;

  const RewardsScreen({super.key, required this.service});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  GameResult<GameState>? _result;
  String? _claiming;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.service.fetchGame();
    if (!mounted) return;
    setState(() => _result = r);
  }

  Future<void> _claim(ClaimableReward reward) async {
    if (_claiming != null) return;
    setState(() => _claiming = reward.challengeId);
    final r = await widget.service.claim(reward.challengeId);
    if (!mounted) return;
    setState(() => _claiming = null);

    final outcome = r.value;
    final text = r.isOk && outcome != null
        ? outcome.leveledUp
            ? '+${outcome.xpAwarded} XP — level up! You are now level ${outcome.level}.'
            : '+${outcome.xpAwarded} XP'
        // ⚠️ 失敗時照抄後端的 detail（409「這個窗格領過了」、422「還沒完成」
        //    講的是不同的事），不要自己寫一句通用的「失敗」。
        : (r.message ?? 'Could not reach the backend.');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF081326),
      appBar: AppBar(
        backgroundColor: const Color(0xFF081326),
        foregroundColor: Colors.white,
        title: const Text('Rewards'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final r = _result;
    if (r == null) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF7657FF)));
    }
    final game = r.value;
    if (!r.isOk || game == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Rewards live on the backend, and it cannot be reached right now.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _heading('Ready to claim'),
        if (game.claimable.isEmpty)
          const Text(
            'Nothing to claim yet. A reward appears when you complete a challenge '
            '- for example, putting your phone down on time three nights in a row.',
            key: Key('rewards-empty'),
            style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
          )
        else
          for (final reward in game.claimable) _rewardTile(reward),
        const SizedBox(height: 22),
        _heading('Badges'),
        for (final badge in game.badges) _badgeTile(badge),
        if (game.notes['rewards_follow_quality'] != null) ...[
          const SizedBox(height: 18),
          Text(
            game.notes['rewards_follow_quality']!,
            style: const TextStyle(color: Color(0xFF8498B7), fontSize: 11, height: 1.4),
          ),
        ],
      ],
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      );

  Widget _rewardTile(ClaimableReward reward) {
    final busy = _claiming == reward.challengeId;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF10265A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFD96A)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              reward.title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
          FilledButton(
            key: Key('claim-${reward.challengeId}'),
            onPressed: busy ? null : () => _claim(reward),
            child: Text(busy ? '...' : 'Claim +${reward.xp} XP'),
          ),
        ],
      ),
    );
  }

  Widget _badgeTile(GameBadge badge) {
    return Container(
      key: Key('badge-${badge.badgeId}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: badge.earned ? const Color(0xFF233A73) : const Color(0xFF0D1C3D),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            badge.earned ? Icons.verified_rounded : Icons.lock_outline_rounded,
            color: badge.earned ? const Color(0xFF7ED957) : Colors.white24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  badge.title,
                  style: TextStyle(
                    color: badge.earned ? Colors.white : Colors.white38,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  badge.description,
                  style: TextStyle(
                    color: badge.earned ? Colors.white60 : Colors.white24,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
