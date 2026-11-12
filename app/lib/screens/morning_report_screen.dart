import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/morning_report.dart';
import '../theme/sonnap_colors.dart';
import '../widgets/home_pet.dart';
import '../widgets/sleep_stages_card.dart';
import '../widgets/sleepy_pet.dart';

/// 早晨報告畫面（2026-11-12，版面 11-12 依參考圖改版）。
///
/// 由上到下：日期 → 細線大字的起床時間疊在小狗後面 → 等級／XP → 半圓分數
/// → 上床／起床與睡眠目標 → Sleep phases（沒有圖時是比例條）→ Dream diary
/// → Back to home。**只放這一晚的資料**（使用者定：不放日期圈圈列、不放 7 晚長條圖）。
///
/// 一打開就先畫 [initial]（手機上已經有的），[load] 回來之後換成完整版。
/// 分數、等級、心情、那句話、XP 全部照抄後端，規則寫在
/// `services/morning_report.dart`。
///
/// 不放「Great work」這種固定鼓勵句，也不另外發 XP（紅線 5）。
/// 睡眠目標只寫事實（「7h 25m of your 8h goal」），**不寫 reached、不變色**：
/// 好壞只有後端能判斷，而分數本身就以睡眠時長為主在算，兩個說法會打架。
class MorningReportScreen extends StatefulWidget {
  final MorningReport initial;
  final Future<MorningReport> Function()? load;

  /// 這一晚是不是剛結束（今天早上起床的那一晚）。是的話沒分數時說「在等資料」，
  /// 不是的話說「沒有資料」——幾天前沒戴錶的晚上，資料不會來了。
  final bool pending;

  const MorningReportScreen({
    super.key,
    required this.initial,
    this.load,
    this.pending = true,
  });

  @override
  State<MorningReportScreen> createState() => _MorningReportScreenState();
}

/// 「Thursday, Nov 13」。自己組而不用 intl 的 DateFormat：那會跟著手機語言走
/// （中文手機上變成中文，或沒初始化語系時直接丟錯），而全 App 的輸出是英文。
String reportDateTitle(DateTime d) {
  const days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
}

/// 背景。缺圖時退回同色系的漸層，不會報錯。
const String kDawnBackground = 'assets/backgrounds/dawn.png';

class _MorningReportScreenState extends State<MorningReportScreen> {
  late MorningReport _report = widget.initial;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final load = widget.load;
    if (load != null) {
      _loading = true;
      load().then((r) {
        if (mounted) setState(() => _report = r);
      }).whenComplete(() {
        if (mounted) setState(() => _loading = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return Scaffold(
      backgroundColor: const Color(0xFF2A2F7A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            kDawnBackground,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF2A2F7A),
                    Color(0xFF8B6DD8),
                    Color(0xFFF3A0C0),
                    Color(0xFFFFC98A),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: ListView(
              key: const Key('report-list'),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                _header(r),
                _hero(r),
                if (r.level != null) ...[
                  const SizedBox(height: 4),
                  _xp(r),
                ],
                const SizedBox(height: 14),
                r.hasScore ? _gauge(r) : _waitingCard(),
                const SizedBox(height: SonnapColors.gap),
                _timesCard(r),
                if (r.stages != null) ...[
                  const SizedBox(height: SonnapColors.gap),
                  SleepStagesCard(
                    stages: r.stages!,
                    totalSleepMinutes: r.sleepMinutes?.round(),
                  ),
                ] else if (r.hasScore &&
                    (r.hasStageSplit || r.deepMinutes != null)) ...[
                  const SizedBox(height: SonnapColors.gap),
                  _splitCard(r),
                ],
                if (r.dream != null) ...[
                  const SizedBox(height: SonnapColors.gap),
                  OutlinedButton.icon(
                    key: const Key('report-dream'),
                    onPressed: () => _showDream(r.dream!),
                    icon: const Icon(Icons.auto_stories_rounded),
                    label: const Text('Dream diary'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: SonnapColors.card,
                      side: const BorderSide(color: SonnapColors.accentSoft),
                      minimumSize: const Size.fromHeight(50),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ],
                if (r.source == ReportSource.bundled) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'From the data bundled with the app (backend unreachable).',
                    key: Key('report-source-bundled'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  key: const Key('report-done'),
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF2A2F7A),
                    minimumSize: const Size.fromHeight(54),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: const Text('Back to home'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 頂端：日期（使用者定：不放晚數、不放日期圈圈列） ─────────────────

  Widget _header(MorningReport r) {
    final d = DateTime.tryParse(r.date);
    final text = d == null ? r.date : reportDateTitle(d);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                key: const Key('report-date'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Text(
                'Last night',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white70,
              ),
            ),
          ),
        IconButton(
          key: const Key('report-close'),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded, color: Colors.white),
        ),
      ],
    );
  }

  // ── 細線大字的起床時間，小狗疊在它下半部 ───────────────────────────

  Widget _hero(MorningReport r) {
    final wake = r.wakeAt;
    const petSize = 190.0;
    return Column(
      children: [
        SizedBox(
          height: 270,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              if (wake != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // 小標放在數字右上角（參考圖的 AM 位置）——放下面會被小狗的頭蓋住
                      Padding(
                        padding: const EdgeInsets.only(right: 24),
                        child: Text(
                          r.bedEnd != null ? 'Out of bed' : 'Woke up (watch)',
                          key: const Key('report-wake-label'),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Center(
                        child: FittedBox(
                          child: Text(
                            _t(wake),
                            key: const Key('report-wake-big'),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: 104,
                              fontWeight: FontWeight.w200,
                              letterSpacing: 2,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Positioned(
                bottom: 0,
                child: r.hasScore
                    ? HomePet(
                        key: const Key('report-pet-awake'),
                        mood: r.mood,
                        size: petSize,
                      )
                    : const SleepingPet(
                        key: Key('report-pet-asleep'),
                        size: petSize + 20,
                      ),
              ),
            ],
          ),
        ),
        if (r.moodDescription != null && r.moodDescription!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              r.moodDescription!,
              key: const Key('report-mood-line'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  // ── 等級與 XP（照抄 /game） ────────────────────────────────────

  Widget _xp(MorningReport r) {
    final size = r.xpLevelSize;
    final into = r.xpIntoLevel ?? 0;
    final night = r.nightXp;
    return Column(
      key: const Key('report-xp'),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Expanded(
              child: Text(
                'Your Experience',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            Text(
              'Lv.${r.level}',
              key: const Key('report-level'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1.0,
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: night == null
                    ? const SizedBox.shrink()
                    : Text(
                        r.nightXpSoFar ? '+$night XP so far' : '+$night XP',
                        key: const Key('report-night-xp'),
                        style: const TextStyle(
                          color: Color(0xFFFFE08A),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Stack(
          alignment: Alignment.centerLeft,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: (r.xpProgress ?? 0).clamp(0.0, 1.0),
                minHeight: 20,
                backgroundColor: Colors.white.withValues(alpha: 0.25),
                color: Colors.white,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Text(
                size == null ? 'Max level' : '${_n(into)} / ${_n(size)} XP',
                key: const Key('report-xp-text'),
                style: const TextStyle(
                  color: Color(0xFF2A2F7A),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _card(Widget child, {Key? key}) => Container(
        key: key,
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: sonnapCardDecoration(),
        child: child,
      );

  // ── 半圓分數 ────────────────────────────────────────────────

  Widget _gauge(MorningReport r) {
    final score = r.score!.round();
    final color = _hex(r.qualityColor) ?? SonnapColors.accentSoft;
    return _card(
      key: const Key('report-gauge'),
      Column(
        children: [
          SizedBox(
            width: 220,
            height: 124,
            child: CustomPaint(
              painter: _ArcPainter(value: (score / 100).clamp(0.0, 1.0)),
              child: Align(
                alignment: const Alignment(0, 0.75),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$score',
                      key: const Key('report-score'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                    const Text(
                      'Sleep score',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          if (r.quality != null)
            Text(
              '${r.quality} sleep',
              key: const Key('report-quality'),
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          if (r.scoreMessage != null && r.scoreMessage!.isNotEmpty)
            Text(
              r.scoreMessage!.toUpperCase(),
              key: const Key('report-score-message'),
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
        ],
      ),
    );
  }

  /// 沒有分數時的那一格。只有「剛結束的那一晚」才說在等資料；
  /// 更早的晚上說沒有資料（yet：早晨匯入晚跑幾天，還是可能補進來）。
  Widget _waitingCard() => _card(
        Column(
          key: const Key('report-waiting'),
          children: [
            const Icon(Icons.watch_rounded,
                color: SonnapColors.accentSoft, size: 30),
            const SizedBox(height: 8),
            Text(
              widget.pending ? kWaitingForWatch : kNoWatchData,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (widget.pending) ...[
              const SizedBox(height: 6),
              const Text(
                "Once your watch syncs, tap this day in the week row on Home "
                "to see your score.",
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white70, fontSize: 13, height: 1.4),
              ),
            ],
          ],
        ),
      );

  // ── 上床／起床、睡眠時間與目標 ─────────────────────────────────

  Widget _timesCard(MorningReport r) {
    // 有按鈕用按鈕；沒有按鈕、有分數時用手錶的入睡→起床，標籤照實寫
    final DateTime? from;
    final DateTime? to;
    final String fromLabel;
    final String toLabel;
    if (r.bedStart != null) {
      from = r.bedStart;
      to = r.bedEnd;
      fromLabel = 'In bed';
      toLabel = 'Out of bed';
    } else if (r.hasScore) {
      from = r.asleepAt;
      to = r.wokeAt;
      fromLabel = 'Asleep';
      toLabel = 'Woke up';
    } else {
      from = null;
      to = null;
      fromLabel = '';
      toLabel = '';
    }

    final children = <Widget>[];
    if (from != null || to != null) {
      children.add(
        Row(
          key: const Key('report-times'),
          children: [
            Expanded(
              child: _clock(Icons.bedtime_rounded, const Color(0xFFFFD27A),
                  from, fromLabel, 'report-from'),
            ),
            Expanded(
              child: _clock(Icons.wb_sunny_rounded, const Color(0xFFFFB36B),
                  to, toLabel, 'report-to'),
            ),
          ],
        ),
      );
    }

    final asleep = r.hasScore ? r.sleepMinutes : null;
    if (asleep != null) {
      if (children.isNotEmpty) {
        children.add(Divider(
          height: 26,
          color: Colors.white.withValues(alpha: 0.15),
        ));
      }
      final goal = r.goalMinutes;
      children.add(
        Row(
          children: [
            Expanded(
              child: _stat(_hm(asleep.round()), 'Time asleep', 'report-duration'),
            ),
            if (goal != null)
              Expanded(child: _stat(_hm(goal), 'Sleep goal', 'report-goal')),
          ],
        ),
      );
      if (goal != null) {
        children.add(const SizedBox(height: 14));
        children.add(
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              key: const Key('report-goal-bar'),
              value: (asleep / goal).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              // 不依達標與否變色（使用者定）
              color: SonnapColors.accentSoft,
            ),
          ),
        );
        children.add(const SizedBox(height: 8));
        children.add(
          Text(
            '${_hm(asleep.round())} of your ${_hm(goal)} goal',
            key: const Key('report-goal-line'),
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        );
      }
    }

    if (children.isEmpty) {
      children.add(
        const Text(
          'No bedtime recorded for this night.',
          key: Key('report-no-times'),
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
      );
    }
    return _card(
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _clock(
      IconData icon, Color color, DateTime? t, String label, String key) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t == null ? '—' : _t(t),
                key: Key(key),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(label,
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stat(String value, String label, String key) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            key: Key(key),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ],
      );

  // ── 淺睡／深睡／REM 比例（沒有 Sleep phases 圖的晚上） ─────────────

  Widget _splitCard(MorningReport r) {
    if (!r.hasStageSplit) {
      // 沒有淺睡就不畫比例條。兩種原因要講不同的話：
      // 沒量到 REM（淺睡會把 REM 吃進去）vs 後端是舊版、沒給淺睡（REM 其實有量到）
      final rem = r.remMeasured && r.remMinutes != null
          ? 'REM ${_hm(r.remMinutes!.round())}'
          : 'REM not measured';
      return _card(
        Text(
          'Deep ${_hm(r.deepMinutes!.round())} · $rem',
          key: const Key('report-split-partial'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
      );
    }
    final parts = [
      ('Light', r.lightMinutes!, SleepStagesCard.light),
      ('Deep', r.deepMinutes!, SleepStagesCard.deep),
      ('REM', r.remMinutes!, SleepStagesCard.rem),
    ];
    final total = parts.fold<double>(0, (s, p) => s + p.$2);
    return _card(
      Column(
        key: const Key('report-split'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sleep phases',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 16,
              child: Row(
                children: [
                  for (final p in parts)
                    if (p.$2 > 0)
                      Expanded(
                        flex: (p.$2 * 10).round().clamp(1, 1 << 30),
                        child: ColoredBox(color: p.$3),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final p in parts)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: p.$3,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          p.$1,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      total <= 0 ? '—' : '${(p.$2 / total * 100).round()}%',
                      key: Key('report-split-${p.$1.toLowerCase()}'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      _hm(p.$2.round()),
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showDream(String dream) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1B1F4A),
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Your buddy's dream diary",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                dream,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _t(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _hm(int m) {
    final h = m ~/ 60;
    final r = m % 60;
    if (h == 0) return '${r}m';
    if (r == 0) return '${h}h';
    return '${h}h ${r}m';
  }

  /// 1219 → 1,219
  static String _n(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  static Color? _hex(String? s) {
    if (s == null) return null;
    final v = int.tryParse(s.replaceFirst('#', ''), radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }
}

/// 半圓量表：底下一條淡色全弧，上面依分數畫一段漸層弧。
class _ArcPainter extends CustomPainter {
  final double value;
  const _ArcPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final radius = math.min(size.width / 2, size.height) - stroke / 2;
    final center = Offset(size.width / 2, size.height - stroke / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.15);
    canvas.drawArc(rect, math.pi, math.pi, false, base);
    if (value <= 0) return;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        startAngle: math.pi,
        endAngle: 2 * math.pi,
        colors: [Color(0xFF6FA8FF), Color(0xFFB9A6FF), Color(0xFFFF8AD8)],
      ).createShader(rect);
    canvas.drawArc(rect, math.pi, math.pi * value, false, fill);
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.value != value;
}
