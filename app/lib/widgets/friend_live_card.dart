import 'package:flutter/material.dart';

import '../models/wall_clock.dart';
import '../services/friends_service.dart';
import 'home_pet.dart';
import 'streak_card.dart' show speciesOf;

/// 好友頁 Friends 分頁的一張卡（2026-11-19 使用者給參考圖、grill 定 Q1–Q11）。
///
/// 左：寵物頭像（睡著畫 tired，其他畫他那晚的行為心情；狗／貓照他分享的）
/// 中：名字 → 大字 → 一行狀態
/// 右：狀態圖示＋「12m ago」小標籤 → 最近 7 晚放下手機的小長條
///
/// ⚠️ 狀態（asleep／up／past_bedtime／awake）**全由後端判**（social/live_status.py），Dart 只照抄。
/// ⚠️ past_bedtime **不寫 staying up**：「不按也沒關係」，沒按的人可能早就睡了。
/// ⚠️ 大字：睡著的人寫「從按 Start Sleep 到現在過了多久」，其他人寫昨晚幾點放下手機；
///    **不放手錶的睡眠時長**（那是生理資料，不在好友白名單裡）。
/// ⚠️ 小長條越晚越高、只用一個顏色、不分好壞；沒資料的晚上畫一個淡點，不畫成 0。
/// ⚠️ 時刻一律 parseWallClock（不 toLocal）。

/// 列表的順序（2026-11-19 使用者定 Q4）：睡著（睡最久的在前）→ 過了就寢 → 醒著 → 起床了 → 沒分享。
/// 同一種再照名字。⚠️ 只排版，狀態本身照抄後端。
List<FriendSummary> sortByLiveState(List<FriendSummary> friends) {
  int rank(String? s) => switch (s) {
        'asleep' => 0,
        'past_bedtime' => 1,
        'awake' => 2,
        'up' => 3,
        _ => 4,
      };
  final out = [...friends];
  out.sort((a, b) {
    final r = rank(a.liveState).compareTo(rank(b.liveState));
    if (r != 0) return r;
    if (a.liveState == 'asleep') {
      final sa = parseWallClock(a.liveSince);
      final sb = parseWallClock(b.liveSince);
      if (sa != null && sb != null && sa != sb) return sa.compareTo(sb);
    }
    return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  });
  return out;
}

/// 列表最上面的「You」卡（Q5）：好友現在看到的你。
/// [shared]：分享設定的 live_status；false＝好友看不到，給一顆去分享設定的按鈕；null＝還不知道。
class YouLiveCard extends StatelessWidget {
  final FriendSummary me;
  final DateTime now;
  final bool? shared;
  final VoidCallback? onOpenSharing;

  const YouLiveCard({
    super.key,
    required this.me,
    required this.now,
    required this.shared,
    this.onOpenSharing,
  });

  @override
  Widget build(BuildContext context) {
    final hidden = shared == false;
    return Container(
      key: const Key('you-card'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x339B7BFF)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: ClipOval(
              child: ColoredBox(
                color: const Color(0xFF2A2F70),
                child: Center(
                  child: HomePet(
                    mood: me.liveState == 'asleep' ? 'tired' : me.petMood,
                    species: speciesOf(me.petSpecies),
                    size: 36,
                    animate: false,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('You',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                Text(
                  hidden ? "Friends can't see your live status" : liveStatusLine(me),
                  key: const Key('you-status'),
                  maxLines: 2,
                  style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 12),
                ),
              ],
            ),
          ),
          if (hidden && onOpenSharing != null)
            TextButton(
              key: const Key('you-share'),
              onPressed: onOpenSharing,
              child: const Text('Share'),
            ),
        ],
      ),
    );
  }
}

/// 子分頁的篩選：'asleep'／'still_up'；別的（Up、沒分享）只出現在 All。
String? liveFilterOf(FriendSummary f) => switch (f.liveState) {
      'asleep' => 'asleep',
      'past_bedtime' || 'awake' => 'still_up',
      _ => null,
    };

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 「1h 12m」「40m」。負數或 null → null。
String? durationLabel(Duration? d) {
  if (d == null || d.isNegative) return null;
  final m = d.inMinutes;
  if (m < 60) return '${m}m';
  return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}

/// 卡片上的大字與它下面那個小字。
(String, String) liveBigValue(FriendSummary f, DateTime now) {
  if (f.liveState == 'asleep') {
    final since = parseWallClock(f.liveSince);
    final d = since == null ? null : durationLabel(now.difference(since));
    if (d != null) return (d, 'asleep');
  }
  final down = parseWallClock(f.lastLightsOutAt);
  if (down != null) return (_hhmm(down), 'phone down, latest night');
  return ('—', 'no phone-down time shared');
}

/// 大字下面那一行。只陳述事實。
String liveStatusLine(FriendSummary f) {
  final since = parseWallClock(f.liveSince);
  switch (f.liveState) {
    case 'asleep':
      return since == null ? 'Asleep' : 'Asleep since ${_hhmm(since)}';
    case 'up':
      return since == null ? 'Up' : 'Up since ${_hhmm(since)}';
    case 'past_bedtime':
      final m = durationLabel(
        f.minutesPastBedtime == null ? null : Duration(minutes: f.minutesPastBedtime!),
      );
      return m == null ? 'No Start Sleep yet' : 'No Start Sleep yet · $m past bedtime';
    case 'awake':
      return 'Awake';
    default:
      return "Live status not shared";
  }
}

/// 右上的小標籤：狀態多久前開始（只有 asleep／up；past_bedtime 的時間已經寫在狀態那行）。
String? agoLabel(FriendSummary f, DateTime now) {
  if (f.liveState != 'asleep' && f.liveState != 'up') return null;
  final since = parseWallClock(f.liveSince);
  if (since == null) return null;
  final d = now.difference(since);
  if (d.isNegative) return null;
  if (d.inMinutes < 1) return 'just now';
  return '${durationLabel(d)} ago';
}

/// 小長條的高度（0–1）：18:00 → 隔天 12:00 這 18 小時裡的位置，越晚越高。
/// 沒資料 → null（畫淡點）。
List<double?> lightsOutBarHeights(List<LightsOutDay> days) => [
      for (final d in days) _barHeight(d.time),
    ];

double? _barHeight(String? hhmm) {
  if (hhmm == null) return null;
  final parts = hhmm.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  var minutes = (h * 60 + m) - 18 * 60;
  if (minutes < 0) minutes += 24 * 60;
  const span = 18 * 60;
  return (minutes.clamp(0, span) / span).toDouble().clamp(0.08, 1.0);
}

class FriendLiveCard extends StatelessWidget {
  final FriendSummary friend;
  final DateTime now;
  final VoidCallback? onTap;

  const FriendLiveCard({super.key, required this.friend, required this.now, this.onTap});

  static const _bg = Color(0xFF1A1F4E);
  static const _accent = Color(0xFF9B7BFF);

  @override
  Widget build(BuildContext context) {
    final f = friend;
    final (big, unit) = liveBigValue(f, now);
    final ago = agoLabel(f, now);
    final asleep = f.liveState == 'asleep';
    return InkWell(
      key: Key('friend-${f.handle}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0x334F5BD5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Avatar(friend: f, asleep: asleep),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(big,
                            key: Key('friend-big-${f.handle}'),
                            softWrap: false,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                        const SizedBox(width: 6),
                        Text(unit,
                            softWrap: false,
                            style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 11)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(liveStatusLine(f),
                      key: Key('friend-status-${f.handle}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: asleep ? _accent : const Color(0xB3FFFFFF), fontSize: 12.5)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StateIcon(state: f.liveState),
                    if (ago != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0x22FFFFFF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(ago,
                            key: Key('friend-ago-${f.handle}'),
                            style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 11)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                if (f.recentLightsOut != null)
                  _LightsOutBars(key: Key('friend-bars-${f.handle}'), days: f.recentLightsOut!),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final FriendSummary friend;
  final bool asleep;
  const _Avatar({required this.friend, required this.asleep});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 62,
      height: 62,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [Color(0xFF3B3F8F), Color(0xFF252A66)]),
            ),
            child: ClipOval(
              child: Center(
                // 睡著畫 tired（睡臉）；其他照他分享的行為心情，沒有就 HomePet 自己退回 bored
                child: HomePet(
                  mood: asleep ? 'tired' : friend.petMood,
                  species: speciesOf(friend.petSpecies),
                  size: 54,
                  animate: false,
                ),
              ),
            ),
          ),
          if (asleep)
            const Positioned(
              right: -2,
              bottom: -2,
              child: CircleAvatar(
                radius: 10,
                backgroundColor: Color(0xFF1A1F4E),
                child: Icon(Icons.nightlight_round, size: 14, color: Color(0xFFFFD66B)),
              ),
            ),
        ],
      ),
    );
  }
}

class _StateIcon extends StatelessWidget {
  final String? state;
  const _StateIcon({required this.state});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (state) {
      'asleep' => (Icons.nightlight_round, const Color(0xFFB9A2FF)),
      'up' => (Icons.wb_twilight_rounded, const Color(0xFFFFC27A)),
      'past_bedtime' => (Icons.phone_android_rounded, const Color(0xFF9FB2E8)),
      'awake' => (Icons.wb_sunny_rounded, const Color(0xFFFFD66B)),
      _ => (Icons.bedtime_off_outlined, const Color(0x66FFFFFF)),
    };
    return Icon(icon, size: 22, color: color, key: Key('state-icon-${state ?? 'none'}'));
  }
}

class _LightsOutBars extends StatelessWidget {
  final List<LightsOutDay> days;
  const _LightsOutBars({super.key, required this.days});

  static const _h = 34.0;

  @override
  Widget build(BuildContext context) {
    final hs = lightsOutBarHeights(days);
    return Semantics(
      label: 'Phone-down time, last ${days.length} nights. Taller is later.',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < hs.length; i++)
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: hs[i] == null
                  ? Container(
                      width: 6,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    )
                  : Container(
                      width: 6,
                      height: _h * hs[i]!,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: i == hs.length - 1
                              ? const [Color(0xFF7657FF), Color(0xFFC6B3FF)]
                              : const [Color(0xFF4B3BB0), Color(0xFF8C73F0)],
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}
