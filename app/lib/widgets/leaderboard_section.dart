import 'package:flutter/material.dart';

import '../services/friends_service.dart';
import 'home_pet.dart';
import 'streak_card.dart' show speciesOf;

/// 好友排行榜（第二批，2026-11-16 共識摘要第 3 節）。
///
/// 上面一排指標（可左右滑，預設 On time）、一排時段；頒獎台前三名、下面其他名次、
/// 不到門檻的人（沒有名次）、最下面釘一張「你」的卡。
/// ⚠️ 名次、門檻、並列、名次變化**全部照抄後端**，Dart 不排序、不算平均。
/// ⚠️ 名次變化的箭頭只代表方向：往上紅、往下綠（同首頁「跟上一晚比」的規矩），不是好壞。
/// ⚠️ 排行只是好玩，不代表誰睡得好——所以沒有「Great job」之類的字。
class LeaderboardSection extends StatefulWidget {
  final FriendsService service;
  const LeaderboardSection({super.key, required this.service});

  @override
  State<LeaderboardSection> createState() => _LeaderboardSectionState();
}

const _kUp = Color(0xFFFF6B6B); // 名次往上：紅（只代表方向）
const _kDown = Color(0xFF4CD08A); // 名次往下：綠
const _kAccent = Color(0xFF7657FF);

/// 還沒拿到後端回應時先畫的那排標籤（跟後端 METRIC_ORDER 同順序；拿到之後照後端的）。
const _kDefaultMetrics = [
  ('on_time', 'On time'),
  ('streak', 'Streak'),
  ('steady', 'Steady'),
  ('steps', 'Steps'),
  ('sleep', 'Sleep'),
  ('score', 'Score'),
  ('chill', 'Chill'),
];

class _LeaderboardSectionState extends State<LeaderboardSection> {
  String _metric = 'on_time';
  String? _period;
  LeaderboardBoard? _board;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final metric = _metric, period = _period;
    final r = await widget.service.fetchLeaderboard(metric, period: period);
    if (!mounted || metric != _metric || period != _period) return; // 已經切到別的
    setState(() {
      _loading = false;
      _failed = !r.isOk;
      if (r.isOk) _board = r.value;
    });
  }

  void _pick({String? metric, String? period}) {
    setState(() {
      if (metric != null && metric != _metric) {
        _metric = metric;
        _period = null; // 換指標時用那個指標預設的時段
      }
      if (period != null) _period = period;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final b = _board;
    final metrics = b?.metrics.isNotEmpty == true
        ? b!.metrics
        : _kDefaultMetrics;
    return Container(
      key: const Key('leaderboard'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF10265A),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Leaderboard',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final (key, label) in metrics)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _Chip(
                      key: Key('lb-metric-$key'),
                      label: label,
                      selected: key == _metric,
                      onTap: () => _pick(metric: key),
                    ),
                  ),
              ],
            ),
          ),
          if (b != null && b.metric == _metric && b.periods.length > 1) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: const Color(0x22FFFFFF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  for (final (key, label) in b.periods)
                    Expanded(
                      child: GestureDetector(
                        key: Key('lb-period-$key'),
                        onTap: () => _pick(period: key),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          decoration: BoxDecoration(
                            color: key == b.period
                                ? _kAccent
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(17),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            label,
                            style: TextStyle(
                              color: key == b.period
                                  ? Colors.white
                                  : const Color(0xB3FFFFFF),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (b == null && _loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (b == null && _failed)
            const Text(
              "Couldn't load the leaderboard.",
              key: Key('lb-failed'),
              style: TextStyle(color: Colors.white70),
            )
          else if (b != null)
            AnimatedOpacity(
              opacity: _loading ? 0.5 : 1,
              duration: const Duration(milliseconds: 150),
              child: _BoardBody(board: b),
            ),
        ],
      ),
    );
  }
}

class _BoardBody extends StatelessWidget {
  final LeaderboardBoard board;
  const _BoardBody({required this.board});

  @override
  Widget build(BuildContext context) {
    final top = board.entries.take(3).toList();
    final rest = board.entries.skip(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (top.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              board.need > 1
                  ? 'No one has ${board.need} nights yet this ${board.period}.'
                  : 'No one on this board yet.',
              key: const Key('lb-empty'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          )
        else
          _Podium(top: top, title: board.title),
        for (final e in rest) _Row(entry: e),
        if (board.below.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            board.need > 1
                ? 'Not ranked yet · needs ${board.need} nights'
                : 'Not ranked yet',
            style: const TextStyle(
              color: Color(0x99FFFFFF),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          for (final e in board.below) _Row(entry: e, below: true),
        ],
        const SizedBox(height: 12),
        _MeCard(board: board),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? Colors.white : const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? const Color(0xFF10265A) : Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    ),
  );
}

String _nameOf(RankedFriend e) =>
    e.mine ? 'You' : e.displayName.replaceAll(' (demo)', '');

/// 名次變化：只代表方向（往上紅、往下綠），0 是一條短橫線，上個時段沒上榜就不畫。
Widget _changeMark(int? change) {
  if (change == null) return const SizedBox(width: 34);
  if (change == 0) {
    return const SizedBox(
      width: 34,
      child: Text(
        '–',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0x80FFFFFF)),
      ),
    );
  }
  final up = change > 0;
  // 名次差兩位數時放不下 → 整個縮小，不溢出
  return SizedBox(
    width: 34,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
            color: up ? _kUp : _kDown,
            size: 20,
          ),
          Text(
            '${change.abs()}',
            style: TextStyle(
              color: up ? _kUp : _kDown,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _demoTag() => Container(
  margin: const EdgeInsets.only(left: 6),
  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
  decoration: BoxDecoration(
    border: Border.all(color: const Color(0x66FFFFFF)),
    borderRadius: BorderRadius.circular(8),
  ),
  child: const Text(
    'Demo',
    style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 9),
  ),
);

class _Podium extends StatelessWidget {
  final List<RankedFriend> top;
  final String title;
  const _Podium({required this.top, required this.title});

  @override
  Widget build(BuildContext context) {
    // 2 · 1 · 3 的位置；人數不到 3 的位置空著
    final order = [
      if (top.length > 1) top[1] else null,
      top[0],
      if (top.length > 2) top[2] else null,
    ];
    const heights = [70.0, 96.0, 56.0];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final (i, e) in order.indexed)
          Expanded(
            child: e == null
                ? const SizedBox.shrink()
                : Column(
                    key: Key('lb-podium-${e.handle}'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (i == 1)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            title,
                            key: const Key('lb-title'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFFFD27A),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      HomePet(
                        mood: e.petMood,
                        size: i == 1 ? 64 : 52,
                        species: speciesOf(e.petSpecies),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _nameOf(e),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: e.mine
                                    ? const Color(0xFFC9B8FF)
                                    : Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (e.demo) _demoTag(),
                        ],
                      ),
                      Text(
                        e.display ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xCCFFFFFF),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: heights[i],
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              i == 1
                                  ? const Color(0xFF8E74FF)
                                  : const Color(0xFF4A3FA8),
                              const Color(0x334A3FA8),
                            ],
                          ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12),
                          ),
                        ),
                        alignment: Alignment.topCenter,
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          children: [
                            Text(
                              '${e.rank}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            _changeMark(e.change),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final RankedFriend entry;
  final bool below;
  const _Row({required this.entry, this.below = false});

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return Container(
      key: Key('${below ? 'lb-below' : 'lb-row'}-${e.handle}'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              below ? '–' : '${e.rank}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
          HomePet(mood: e.petMood, size: 32, species: speciesOf(e.petSpecies)),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    _nameOf(e),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: e.mine ? const Color(0xFFC9B8FF) : Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (e.demo) _demoTag(),
              ],
            ),
          ),
          Text(
            below
                ? '${e.nights} ${e.nights == 1 ? 'night' : 'nights'} so far'
                : (e.display ?? ''),
            style: TextStyle(
              color: below ? const Color(0x99FFFFFF) : Colors.white,
              fontSize: 13,
            ),
          ),
          if (!below) _changeMark(e.change),
        ],
      ),
    );
  }
}

/// 最下面釘一張「你」的卡：就算沒進前三也看得到自己第幾名（Duolingo 的做法）。
class _MeCard extends StatelessWidget {
  final LeaderboardBoard board;
  const _MeCard({required this.board});

  @override
  Widget build(BuildContext context) {
    final me = board.me;
    final String text;
    switch (board.meStatus) {
      case 'ranked':
        text = 'You · #${me!.rank} · ${me.display ?? ''}';
      case 'below':
        final left = board.need - (me?.nights ?? 0);
        text =
            'You have ${me?.nights ?? 0} of ${board.need} nights — $left more to be ranked';
      default:
        text = 'Share “${board.shareLabel ?? board.label}” to join this board';
    }
    return Container(
      key: const Key('lb-me'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x337657FF),
        border: Border.all(color: const Color(0xFFA48BFF), width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          if (board.meStatus == 'ranked') _changeMark(me?.change),
        ],
      ),
    );
  }
}
