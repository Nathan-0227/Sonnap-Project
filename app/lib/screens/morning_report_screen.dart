import 'package:flutter/material.dart';

import '../services/morning_report.dart';
import '../theme/sonnap_colors.dart';
import '../widgets/home_pet.dart';
import '../widgets/sleep_stages_card.dart';
import '../widgets/sleepy_pet.dart';

/// 早晨報告畫面（2026-11-12）。
///
/// 一打開就先畫 [initial]（手機上已經有的：日期、上床→起床、睡姿小狗），
/// [load] 回來之後換成完整版。**分數、等級、心情、那句話全部照抄後端**，
/// 規則寫在 `services/morning_report.dart` 的 [buildMorningReport]。
///
/// 不放「Great work」這種固定鼓勵句，也不發 XP：好的夜晚與差的夜晚
/// 拿到一樣的稱讚，就是紅線 5。
class MorningReportScreen extends StatefulWidget {
  final MorningReport initial;
  final Future<MorningReport> Function()? load;

  const MorningReportScreen({super.key, required this.initial, this.load});

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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _header(r),
                const SizedBox(height: 4),
                Center(
                  child: SizedBox(
                    height: 210,
                    child: r.hasScore
                        ? HomePet(
                            key: const Key('report-pet-awake'),
                            mood: r.mood,
                            size: 200,
                          )
                        : const SleepingPet(
                            key: Key('report-pet-asleep'),
                            size: 210,
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                r.hasScore ? _scoreCard(r) : _waitingCard(),
                const SizedBox(height: SonnapColors.gap),
                _durationCard(r),
                if (r.hasScore && (r.hasStageSplit || r.deepMinutes != null)) ...[
                  const SizedBox(height: SonnapColors.gap),
                  _splitCard(r),
                ],
                if (r.stages != null) ...[
                  const SizedBox(height: SonnapColors.gap),
                  SleepStagesCard(
                    stages: r.stages!,
                    totalSleepMinutes: r.sleepMinutes?.round(),
                  ),
                ],
                if (r.moodDescription != null &&
                    r.moodDescription!.isNotEmpty) ...[
                  const SizedBox(height: SonnapColors.gap),
                  _card(
                    Text(
                      r.moodDescription!,
                      key: const Key('report-mood-line'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: SonnapColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
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
                    backgroundColor: SonnapColors.accent,
                    minimumSize: const Size.fromHeight(54),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 頂端：日期（使用者定：不放晚數） ─────────────────────────────

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

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: sonnapCardDecoration(),
        child: child,
      );

  // ── 分數 ────────────────────────────────────────────────────

  Widget _scoreCard(MorningReport r) {
    const ring = 104.0;
    final score = r.score!.round();
    final color = _hex(r.qualityColor) ?? SonnapColors.accentSoft;
    return _card(
      Row(
        children: [
          SizedBox(
            width: ring,
            height: ring,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: ring,
                  height: ring,
                  child: CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 8,
                    strokeCap: StrokeCap.round,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    color: SonnapColors.accentSoft,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$score',
                      key: const Key('report-score'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Sleep Score',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (r.quality != null)
                  Text(
                    '${r.quality} sleep',
                    key: const Key('report-quality'),
                    style: TextStyle(
                      color: color,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                if (r.scoreMessage != null && r.scoreMessage!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    r.scoreMessage!,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _waitingCard() => _card(
        Column(
          key: const Key('report-waiting'),
          children: const [
            Icon(Icons.watch_rounded, color: SonnapColors.accentSoft, size: 30),
            SizedBox(height: 8),
            Text(
              kWaitingForWatch,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 6),
            Text(
              "Once your watch syncs, tap this day in the week row on Home "
              "to see your score.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      );

  // ── 睡眠長度與時間 ──────────────────────────────────────────

  Widget _durationCard(MorningReport r) {
    final lines = <Widget>[];
    final minutes = r.hasScore ? r.sleepMinutes : null;
    if (minutes != null) {
      lines.add(
        Text(
          _hm(minutes.round()),
          key: const Key('report-duration'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 34,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
      lines.add(
        const Text(
          'Asleep (measured by your watch)',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      );
      lines.add(const SizedBox(height: 10));
    }

    final String? times;
    if (r.bedStart != null) {
      times = r.bedEnd != null
          ? 'In bed ${_t(r.bedStart!)} – ${_t(r.bedEnd!)}'
          : 'In bed from ${_t(r.bedStart!)}';
    } else if (r.hasScore && r.asleepAt != null && r.wokeAt != null) {
      // 沒按按鈕：改給手錶的入睡→起床，並標成 Asleep，不冒充上床時間
      times = 'Asleep ${_t(r.asleepAt!)} – ${_t(r.wokeAt!)}';
    } else {
      times = null;
    }
    if (times != null) {
      lines.add(
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bedtime_rounded, size: 18, color: Color(0xFFFFD27A)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                times,
                key: const Key('report-times'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.wb_sunny_rounded, size: 18, color: Color(0xFFFFB36B)),
          ],
        ),
      );
    }
    if (lines.isEmpty) {
      lines.add(
        const Text(
          'No bedtime recorded for this night.',
          key: Key('report-no-times'),
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
      );
    }
    return _card(Column(children: lines));
  }

  // ── 淺睡／深睡／REM 比例 ─────────────────────────────────────

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
    return '${h}h ${r}m';
  }

  static Color? _hex(String? s) {
    if (s == null) return null;
    final v = int.tryParse(s.replaceFirst('#', ''), radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }
}
