import 'package:flutter/material.dart';

import '../services/friends_service.dart';
import 'friend_live_card.dart';
import 'friend_night_card.dart';
import 'home_pet.dart';
import 'streak_card.dart' show speciesOf;

/// 點好友卡片滑出來的那一頁（2026-11-19 使用者定 Q6）：
/// 現在的狀態（大字＋從幾點開始）→ 最近 7 晚放下手機（放大、有星期與時刻）→ 他最近那張動態卡 → Remove friend。
///
/// ⚠️ 狀態、時刻全部照抄後端；7 晚的長條越晚越高、只用一個顏色、沒資料寫「—」不畫 0。
/// ⚠️ 連續天數、熬夜幾晚放在 Ranks／Feed，這裡只講「現在」與作息。
class FriendLiveSheet extends StatelessWidget {
  final FriendSummary friend;
  final DateTime now;
  final FriendNightCard? lastNight;
  final VoidCallback? onRemove;

  const FriendLiveSheet({
    super.key,
    required this.friend,
    required this.now,
    this.lastNight,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final f = friend;
    final (big, unit) = liveBigValue(f, now);
    return Container(
      key: const Key('friend-sheet'),
      decoration: const BoxDecoration(
        color: Color(0xFF141A45),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: ClipOval(
                    child: ColoredBox(
                      color: const Color(0xFF2A2F70),
                      child: Center(
                        child: HomePet(
                          mood: f.liveState == 'asleep' ? 'tired' : f.petMood,
                          species: speciesOf(f.petSpecies),
                          size: 50,
                          animate: false,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(f.displayName,
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const _Label('Right now'),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(big,
                    key: const Key('sheet-big'),
                    style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(unit, style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 13)),
                ),
              ],
            ),
            Text(liveStatusLine(f),
                key: const Key('sheet-status'),
                style: const TextStyle(color: Color(0xFFB9A2FF), fontSize: 14)),
            if (f.recentLightsOut != null) ...[
              const SizedBox(height: 22),
              const _Label('Phone down, last 7 nights'),
              const SizedBox(height: 10),
              WeekLightsOutChart(days: f.recentLightsOut!),
            ],
            if (lastNight != null) ...[
              const SizedBox(height: 22),
              const _Label('Latest night'),
              const SizedBox(height: 10),
              FriendNightCardView(card: lastNight!),
            ],
            const SizedBox(height: 16),
            if (onRemove != null)
              TextButton.icon(
                key: const Key('remove-friend'),
                onPressed: onRemove,
                icon: const Icon(Icons.person_remove_rounded, color: Color(0xFFFF6B6B)),
                label: const Text('Remove friend', style: TextStyle(color: Color(0xFFFF6B6B))),
              ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: const TextStyle(
          color: Color(0x99FFFFFF), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1));
}

/// 7 晚放下手機（放大版）：每晚一根，越晚越高，柱頂寫時刻、底下寫星期幾；沒資料寫「—」。
class WeekLightsOutChart extends StatelessWidget {
  final List<LightsOutDay> days;
  const WeekLightsOutChart({super.key, required this.days});

  static const _h = 110.0;
  static const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final hs = lightsOutBarHeights(days);
    return Row(
      key: const Key('week-lights-out'),
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < days.length; i++)
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(days[i].time ?? '—',
                    style: TextStyle(
                        color: days[i].time == null ? const Color(0x66FFFFFF) : Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Container(
                  width: 14,
                  height: hs[i] == null ? 4 : _h * hs[i]!,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    color: hs[i] == null ? const Color(0x22FFFFFF) : null,
                    gradient: hs[i] == null
                        ? null
                        : LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: i == days.length - 1
                                ? const [Color(0xFF7657FF), Color(0xFFC6B3FF)]
                                : const [Color(0xFF4B3BB0), Color(0xFF8C73F0)],
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(weekdayOf(days[i].date),
                    style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 11)),
              ],
            ),
          ),
      ],
    );
  }

  /// "2026-11-19" → "Thu"。讀不懂寫空字串。
  static String weekdayOf(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? '' : _wd[d.weekday - 1];
  }
}
