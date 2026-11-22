import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/game_service.dart';
import '../services/key_value_store.dart';
import '../widgets/home_pet.dart';
import '../widgets/level_progress.dart';
import '../widgets/report_sheet.dart';

/// 獎勵：獎盃架（2026-11-22 grill，版面 B）。
///
/// 由上到下：房間（寵物站在地毯上、頭上等級條）→ 金色「N rewards ready」卡（Claim all）
/// → 徽章架（一格一個系列，點開看 5 級）→ 最近 7 晚各拿幾 XP。
///
/// ⚠️ 「哪些可以領」「徽章拿到第幾級、哪一晚拿到」全部照抄後端（`GET /game`）。
///    挑戰有沒有完成、徽章有沒有拿到都是後端判的，這裡再判一次就是第二個定義處。
///    拿到的徽章不收回也是後端記的——Dart 從 value 與門檻自己判，資料改正之後就會收回。
///
/// ⚠️ 沒有東西可以領時，要**講清楚怎麼樣才會有**——空白一片的畫面會讓人
///    以為這個功能壞了，或以為「多開幾次 App」就會有（紅線 5：獎勵跟你做了什麼有關，
///    跟你來了幾次無關）。
class RewardsScreen extends StatefulWidget {
  final GameService service;

  /// 寵物的心情（同首頁那一份，後端 `pet_mood`）。拿不到 → HomePet 畫 bored，不編一個開心的。
  final String? mood;

  /// 紅點記在哪（看過哪幾級）。null＝手機上的 `sonnap/store`。
  final KeyValueStore? store;

  const RewardsScreen({super.key, required this.service, this.mood, this.store});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

/// 新拿到、還沒在獎勵頁看過的徽章那一級（紅點）。只存在手機上。
class BadgeSeenStore {
  /// ⚠️ 改這個字串＝每一級都會重新亮紅點。
  static const String key = 'badges_seen_v1';
  final KeyValueStore store;
  const BadgeSeenStore(this.store);

  Future<Set<String>> load() async {
    try {
      final raw = await store.getString(key);
      final decoded = raw == null ? null : jsonDecode(raw);
      if (decoded is List) return {for (final v in decoded) if (v is String) v};
    } catch (_) {}
    return {};
  }

  Future<void> save(Set<String> seen) async {
    try {
      await store.setString(key, jsonEncode(seen.toList()..sort()));
    } catch (_) {}
  }
}

/// 等級外框的顏色：銅 → 銀 → 金 → 紫 →（第 5 級是彩虹漸層，這一格只給級數小圓點用）。
const List<Color> kBadgeTierColors = [
  Color(0xFFC98A4B),
  Color(0xFFD5DCE8),
  Color(0xFFFFD96A),
  Color(0xFFB9A8FF),
  Color(0xFFFF9BD2),
];

/// 徽章圖檔：`assets/badges/<系列>.png`（使用者生成，2026-11-22）。缺圖退回圖示。
String badgeAsset(String seriesId) => 'assets/badges/$seriesId.png';

const _bg = Color(0xFF081326);
const _card = Color(0xFF10265A);
const _muted = Color(0xFFA9B8D6);
const _gold = Color(0xFFFFD96A);

/// 房間圖（使用者生成，1122×1402）的地毯中心，換圖要重量。
const double kRewardsRugY = 0.80;
const double kRewardsRoomAspect = 1122 / 1402;

class _RewardsScreenState extends State<RewardsScreen> {
  GameResult<GameState>? _result;
  String? _equipped;
  Set<String> _unseen = const {};
  bool _claiming = false;

  KeyValueStore get _store => widget.store ?? const PlatformKeyValueStore();

  @override
  void initState() {
    super.initState();
    _load(markSeen: true);
  }

  Future<void> _load({bool markSeen = false}) async {
    final r = await widget.service.fetchGame();
    final closet = await widget.service.fetchCloset();
    if (!mounted) return;
    final game = r.value;
    if (markSeen && game != null) {
      final seenStore = BadgeSeenStore(_store);
      final seen = await seenStore.load();
      final earned = {for (final s in game.badgeSeries) ...s.earnedKeys};
      // 這一次進來看到的紅點留到離開；記成看過，下次就不亮
      _unseen = earned.difference(seen);
      if (_unseen.isNotEmpty) await seenStore.save({...seen, ...earned});
      if (!mounted) return;
    }
    setState(() {
      _result = r;
      _equipped = closet.value?.equippedItemId;
    });
  }

  Future<void> _claimAll(GameState game) async {
    if (_claiming) return;
    setState(() => _claiming = true);
    var xp = 0;
    int? level;
    var leveledUp = false;
    String? firstError;
    Future<void> take(Future<GameResult<ClaimOutcome>> call) async {
      final r = await call;
      final o = r.value;
      if (r.isOk && o != null) {
        xp += o.xpAwarded;
        level = o.level;
        leveledUp = leveledUp || o.leveledUp;
      } else {
        // ⚠️ 照抄後端的 detail（409「領過了」、422「還沒完成」講的是不同的事）
        firstError ??= r.message ?? 'Could not reach the backend.';
      }
    }

    for (final c in game.claimable) {
      await take(widget.service.claim(c.challengeId));
    }
    for (final b in game.claimableBadges) {
      await take(widget.service.claimBadge(b.achievementId));
    }
    if (!mounted) return;
    setState(() => _claiming = false);
    final text = xp > 0
        ? leveledUp
            ? '+$xp XP — level up! You are now level $level.'
            : '+$xp XP'
        : firstError ?? 'Nothing was claimed.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final r = _result;
    if (r == null) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF7657FF)));
    }
    final game = r.value;
    if (!r.isOk || game == null) {
      return SafeArea(
        child: Stack(
          children: [
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Rewards live on the backend, and it cannot be reached right now.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
            Positioned(left: 8, top: 4, child: _backButton(context)),
          ],
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _room(context, game),
        Transform.translate(
          offset: const Offset(0, -28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _claimCard(game),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _shelf(context, game),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: _lastNights(game),
        ),
        if (game.notes['rewards_follow_quality'] != null)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
            child: Text(
              game.notes['rewards_follow_quality']!,
              style: const TextStyle(color: Color(0xFF8498B7), fontSize: 11, height: 1.4),
            ),
          ),
      ],
    );
  }

  Widget _backButton(BuildContext context) => Material(
        color: const Color(0x66081326),
        shape: const CircleBorder(),
        child: IconButton(
          key: const Key('rewards-back'),
          tooltip: 'Back',
          icon: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 28),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      );

  // ── 房間 ───────────────────────────────────────────────────────────

  Widget _room(BuildContext context, GameState game) {
    final top = MediaQuery.paddingOf(context).top;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = w / kRewardsRoomAspect;
      // 0.58：實機看 0.46 太小（2026-11-22 使用者）；腳一樣踩在地毯中心
      final petSize = w * 0.58;
      final petTop = h * kRewardsRugY - petSize * 0.82;
      return SizedBox(
        key: const Key('rewards-room'),
        height: h,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/backgrounds/rewards_room.jpg',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF2B2257), Color(0xFF3B2C63), Color(0xFF5A3E52)],
                    ),
                  ),
                ),
              ),
            ),
            // 下緣淡進頁面的底色，接到金色卡片
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 80,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00081326), _bg],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              key: const Key('rewards-pet'),
              left: (w - petSize) / 2,
              top: petTop,
              width: petSize,
              height: petSize,
              child: HomePet(
                mood: widget.mood,
                size: petSize,
                equippedItemId: _equipped,
                growthStage: game.growthStage,
              ),
            ),
            Positioned(left: 8, top: top + 4, child: _backButton(context)),
            Positioned(
              left: 0,
              right: 0,
              top: top + 14,
              child: const IgnorePointer(
                child: Center(
                  child: Text(
                    'Rewards',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: petTop - 48,
              // 不加深色底（2026-11-22 使用者試過後拿掉）
              child: Center(
                child: KeyedSubtree(
                  key: const Key('rewards-level'),
                  child: LevelProgress(game: game),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  // ── 可以領的 ─────────────────────────────────────────────────────────

  Widget _claimCard(GameState game) {
    final n = game.claimable.length + game.claimableBadges.length;
    if (n == 0) {
      return Container(
        key: const Key('rewards-empty'),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(22)),
        // 兩行就好（使用者 2026-11-22：字太多）。仍然要說「從哪裡來」——
        // 不然會以為多開幾次 App 就會有（紅線 5）
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nothing to claim',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
            SizedBox(height: 2),
            Text('New rewards come from challenges and badges.',
                style: TextStyle(color: _muted, fontSize: 12.5)),
          ],
        ),
      );
    }
    final total = [
      for (final c in game.claimable) c.xp,
      for (final b in game.claimableBadges) b.xp,
    ].fold<int>(0, (a, b) => a + b);
    // 不列出是哪幾個（使用者 2026-11-22：字太多）；明細在每個徽章點開的頁裡看得到
    return Container(
      key: const Key('rewards-ready'),
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(24)),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1C2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.card_giftcard_rounded, color: Color(0xFF7A4A00), size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              n == 1 ? '1 reward ready' : '$n rewards ready',
              style: const TextStyle(
                  color: Color(0xFF2A1A00), fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('claim-all'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2A1A00),
              foregroundColor: _gold,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            onPressed: _claiming ? null : () => _claimAll(game),
            child: Text(_claiming ? '...' : 'Claim +$total',
                style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  // ── 徽章架 ───────────────────────────────────────────────────────────

  Widget _shelf(BuildContext context, GameState game) {
    if (game.badgeSeries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Badges need a newer backend.',
          key: Key('badges-need-backend'),
          style: TextStyle(color: _muted, fontSize: 12.5),
        ),
      );
    }
    final groups = game.badgeGroups.isNotEmpty
        ? game.badgeGroups
        : [for (final g in {for (final s in game.badgeSeries) s.group}) (g, g)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (id, label) in groups)
          if (game.badgeSeries.any((s) => s.group == id))
            _shelfGroup(context, label, [for (final s in game.badgeSeries) if (s.group == id) s]),
      ],
    );
  }

  Widget _shelfGroup(BuildContext context, String label, List<BadgeSeries> series) {
    final rows = <List<BadgeSeries>>[
      for (var i = 0; i < series.length; i += 3)
        series.sublist(i, (i + 3).clamp(0, series.length)),
    ];
    final earned = series.fold<int>(0, (a, s) => a + s.level);
    final all = series.fold<int>(0, (a, s) => a + s.maxLevel);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
              ),
              Text('$earned / $all levels',
                  style: const TextStyle(
                      color: _muted, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 16, 10, 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1630),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                for (final row in rows) _shelfRow(context, row),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _shelfRow(BuildContext context, List<BadgeSeries> row) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 3; i++)
                  Expanded(child: i < row.length ? _tile(context, row[i]) : const SizedBox()),
              ],
            ),
            const SizedBox(height: 6),
            // 木架：板子＋底下一條影子
            Container(
              height: 11,
              decoration: BoxDecoration(
                color: const Color(0xFF8A5A3C),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Container(
              height: 5,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF5E3C28),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(4)),
              ),
            ),
          ],
        ),
      );

  Widget _tile(BuildContext context, BadgeSeries s) {
    final isNew = s.earnedKeys.any(_unseen.contains);
    final next = s.next;
    final progress = next == null ? 'All ${s.maxLevel} levels' : '${next.value} / ${next.threshold}';
    return Semantics(
      button: true,
      label: '${s.title}, level ${s.level} of ${s.maxLevel}'
          '${next == null ? '' : ', ${next.value} of ${next.threshold} ${badgeUnit(next.threshold, s.unit)} to the next level'}',
      child: InkWell(
        key: Key('badge-tile-${s.seriesId}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => showBadgeSheet(context, s),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  BadgeMedal(series: s, size: 74),
                  if (isNew)
                    Positioned(
                      right: 2,
                      top: 2,
                      child: Container(
                        key: Key('badge-new-${s.seriesId}'),
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF4D5E),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF1A1630), width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                s.title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: s.level > 0 ? Colors.white : const Color(0xFFB0A8D0),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(progress,
                  style: const TextStyle(
                      color: _muted, fontSize: 10.5, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  // ── 最近 7 晚 ───────────────────────────────────────────────────────

  Widget _lastNights(GameState game) {
    final nights = game.recentNights;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Last 7 nights',
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        if (nights.isEmpty)
          const Text('No nights yet.', style: TextStyle(color: _muted, fontSize: 12.5))
        else
          Row(
            children: [
              for (final n in nights)
                Expanded(
                  child: Container(
                    key: Key('night-xp-${n.date}'),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: n.total == 0 ? const Color(0xFF0D1C3D) : _card,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        // +0 照實寫（紅線 5：差的晚上就是拿得少）
                        Text('+${n.total}',
                            style: TextStyle(
                              color: n.total == 0 ? const Color(0xFF8EA0C2) : _gold,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            )),
                        const SizedBox(height: 3),
                        Text(_weekday(n.date),
                            style: const TextStyle(
                                color: _muted, fontSize: 10, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// 單位跟著數字走：1 → "1 night"、"1 night in a row"；其他照後端給的複數。
/// 後端的 unit 一律是第一個字複數（nights、mornings、visits…），只改第一個字。
String badgeUnit(int n, String unit) {
  if (n != 1) return unit;
  final i = unit.indexOf(' ');
  final first = i < 0 ? unit : unit.substring(0, i);
  final rest = i < 0 ? '' : unit.substring(i);
  final single = first.endsWith('s') ? first.substring(0, first.length - 1) : first;
  return '$single$rest';
}

String _weekday(String date) {
  final d = DateTime.tryParse(date);
  if (d == null) return '';
  return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
}

/// "2026-11-20" → "Nov 20"。不用 intl（那會跟著手機語言走）。
String badgeDate(String? date) {
  final d = date == null ? null : DateTime.tryParse(date);
  if (d == null) return '';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${m[d.month - 1]} ${d.day}';
}

/// 一枚徽章：圖＋外框（顏色＝拿到第幾級），右下角寫級數。沒拿到：灰階變淡＋鎖。
class BadgeMedal extends StatelessWidget {
  final BadgeSeries series;
  final double size;

  /// 指定畫第幾級（詳細頁每一列用）；null＝目前的級數。
  final int? tier;

  /// 那一級拿到了沒（詳細頁每一列用）；預設看 [tier]／目前級數是不是 > 0。
  final bool earned;

  const BadgeMedal({super.key, required this.series, this.size = 74, this.tier, bool? earned})
      : earned = earned ?? true;

  @override
  Widget build(BuildContext context) {
    final level = tier ?? series.level;
    final lit = level > 0 && earned;
    final rainbow = lit && level >= 5;
    final ring = lit ? kBadgeTierColors[(level - 1).clamp(0, kBadgeTierColors.length - 1)] : null;
    final image = Image.asset(
      badgeAsset(series.seriesId),
      width: size * 0.74,
      height: size * 0.74,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => Icon(Icons.emoji_events_rounded,
          size: size * 0.5, color: lit ? _gold : Colors.white24),
    );
    return SizedBox(
      key: Key('medal-${series.seriesId}-${lit ? level : 0}'),
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 外框：第 1–4 級一個顏色；第 5 級彩虹（漸層底＋內圈蓋回底色）
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: rainbow ? null : (lit ? const Color(0xFF241F40) : const Color(0xFF16122A)),
                gradient: rainbow
                    ? const SweepGradient(colors: [
                        Color(0xFFFF9BD2),
                        Color(0xFFFFD96A),
                        Color(0xFF9BE7A0),
                        Color(0xFF8FC8FF),
                        Color(0xFFB9A8FF),
                        Color(0xFFFF9BD2),
                      ])
                    : null,
                border: rainbow
                    ? null
                    : ring == null
                        ? Border.all(color: const Color(0xFF4A4170), width: 2)
                        : Border.all(color: ring, width: size * 0.06),
              ),
            ),
          ),
          if (rainbow)
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.all(size * 0.06),
                child: const DecoratedBox(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Color(0xFF241F40)),
                ),
              ),
            ),
          Center(
            child: lit
                ? image
                // 沒拿到：灰階＋淡，看得出是什麼但明顯還沒有
                : Opacity(
                    opacity: 0.35,
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.matrix([
                        0.33, 0.33, 0.33, 0, 0, //
                        0.33, 0.33, 0.33, 0, 0, //
                        0.33, 0.33, 0.33, 0, 0, //
                        0, 0, 0, 1, 0, //
                      ]),
                      child: image,
                    ),
                  ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: size * 0.34,
              height: size * 0.34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ring ?? const Color(0xFF2A2450),
                border: Border.all(color: const Color(0xFF1A1630), width: 2),
              ),
              child: lit
                  ? Text('$level',
                      style: TextStyle(
                        color: const Color(0xFF2A1A00),
                        fontSize: size * 0.17,
                        fontWeight: FontWeight.w900,
                      ))
                  : Icon(Icons.lock_rounded, size: size * 0.17, color: const Color(0xFF8C84B0)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 點一個系列：5 級、哪一晚拿到、XP 領了沒、下一級還差多少。
Future<void> showBadgeSheet(BuildContext context, BadgeSeries s) {
  final next = s.next;
  return showReportSheet<void>(
    context: context,
    builder: (context) => Container(
      key: const Key('badge-sheet'),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF151A3C), Color(0xFF1B1F48), Color(0xFF2B3470)],
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: BadgeMedal(series: s, size: 112)),
              const SizedBox(height: 12),
              Text(s.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(s.how,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _muted, fontSize: 13, height: 1.4)),
              const SizedBox(height: 8),
              Text(
                next == null
                    ? 'All ${s.maxLevel} levels earned'
                    : '${next.value} / ${next.threshold} ${badgeUnit(next.threshold, s.unit)} to level ${next.tier}',
                key: const Key('badge-sheet-progress'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: _gold, fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 18),
              for (final t in s.tiers) _tierRow(s, t),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _tierRow(BadgeSeries s, BadgeTier t) {
  final right = !t.earned
      ? 'Locked'
      : t.claimed
          ? '+${t.xp} XP claimed'
          : '+${t.xp} XP to claim';
  return Container(
    key: Key('badge-tier-${t.tier}'),
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: t.earned ? const Color(0x22FFFFFF) : const Color(0x11FFFFFF),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        BadgeMedal(series: s, size: 44, tier: t.tier, earned: t.earned),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Level ${t.tier} · ${t.threshold} ${badgeUnit(t.threshold, s.unit)}',
                  style: TextStyle(
                    color: t.earned ? Colors.white : const Color(0xFFB0A8D0),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  )),
              if (t.earned && t.earnedOn != null)
                Text('Earned ${badgeDate(t.earnedOn)}',
                    style: const TextStyle(color: _muted, fontSize: 12)),
            ],
          ),
        ),
        Text(right,
            style: TextStyle(
              color: t.earned && !t.claimed ? _gold : _muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            )),
      ],
    ),
  );
}
