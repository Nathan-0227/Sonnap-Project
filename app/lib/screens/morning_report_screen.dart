import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/morning_rating.dart';
import '../services/morning_report.dart';
import '../theme/report_style.dart';
import '../widgets/home_pet.dart';
import '../widgets/sleep_stages_card.dart';
import '../widgets/sleepy_pet.dart';

/// 早晨報告畫面（2026-11-12 定案；11-13 依示意圖重做：深藍夜空、分數圓環當主角、
/// 小狗坐在圓環右下的山丘上、卡片少而短）。
///
/// 由上到下：日期 → 圓環＋山丘＋小狗＋自評小標籤 → Lv／XP 一條 → From your buddy
/// （AI 那段＋小建議）→ Time in bed／Time asleep → Phone down｜Your target
/// → Sleep phases → More details（收合）→ Dream diary → View sleep insights → Back to home。
///
/// 一打開就先畫 [initial]（手機上已經有的），[load] 回來之後換成完整版，
/// [loadSummary] 再晚一點回來（AI 第一次生成要等模型）。
/// 分數、等級、心情、那句話、XP、建議全部照抄後端，規則寫在
/// `services/morning_report.dart`。
///
/// 不放「Great work」這種固定鼓勵句，也不另外發 XP（紅線 5）。
/// 睡眠目標只寫事實（「of your 8h goal」），**不寫 reached、不變色**：
/// 好壞只有後端能判斷，而分數本身就以睡眠時長為主在算，兩個說法會打架。
///
/// 關掉時回傳 [kReportOpenInsights] 代表使用者按了 View sleep insights。
class MorningReportScreen extends StatefulWidget {
  final MorningReport initial;
  final Future<MorningReport> Function()? load;

  /// 拿到完整版之後再接 AI 那段。回傳 `/night-summary` 的 JSON（失敗回 null）。
  final Future<Map<String, dynamic>?> Function()? loadSummary;

  /// 這一晚是不是剛結束（今天早上起床的那一晚）。是的話沒分數時說「在等資料」，
  /// 不是的話說「沒有資料」——幾天前沒戴錶的晚上，資料不會來了。
  final bool pending;

  /// 要不要放 View sleep insights（首頁有給切分頁的方法才放）。
  final bool canOpenInsights;

  const MorningReportScreen({
    super.key,
    required this.initial,
    this.load,
    this.loadSummary,
    this.pending = true,
    this.canOpenInsights = false,
  });

  @override
  State<MorningReportScreen> createState() => _MorningReportScreenState();
}

/// 按了 View sleep insights 時，報告用這個值 pop。
const String kReportOpenInsights = 'insights';

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

/// 「放下手機比目標晚多少」那一行。**只照抄後端的分鐘數**；沒有就不寫。
String? adherenceLine(double? minutes) {
  if (minutes == null) return null;
  if (minutes <= 0) return 'On time';
  return '${reportHm(minutes)} after your target';
}

class _MorningReportScreenState extends State<MorningReportScreen> {
  late MorningReport _report = widget.initial;
  bool _loading = false;
  bool _detailsOpen = false;

  @override
  void initState() {
    super.initState();
    final load = widget.load;
    if (load != null) {
      _loading = true;
      load().then((r) async {
        if (!mounted) return;
        setState(() => _report = r);
        final summary = widget.loadSummary;
        if (summary != null && r.hasScore) {
          final json = await summary();
          if (mounted) setState(() => _report = _report.withSummary(json));
        }
      }).whenComplete(() {
        if (mounted) setState(() => _loading = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    final hasBuddy = r.hasScore && (r.summaryText != null || r.tip != null);
    return ReportFont(
      child: Scaffold(
        backgroundColor: ReportColors.bgTop,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const ReportBackground(),
            SafeArea(
              child: ListView(
                key: const Key('report-list'),
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                children: [
                  _header(r),
                  const SizedBox(height: 14),
                  _hero(r),
                  if (r.level != null) ...[
                    const SizedBox(height: 14),
                    _xp(r),
                  ],
                  if (hasBuddy) ...[
                    const SizedBox(height: 14),
                    _buddy(r),
                  ],
                  const SizedBox(height: 14),
                  _timeCards(r),
                  if (r.lightsOutAt != null) ...[
                    const SizedBox(height: 14),
                    _phoneDown(r),
                  ],
                  if (r.stages != null) ...[
                    const SizedBox(height: 14),
                    SleepStagesCard(
                      stages: r.stages!,
                      totalSleepMinutes: r.sleepMinutes?.round(),
                    ),
                  ] else if (r.hasScore &&
                      (r.hasStageSplit || r.deepMinutes != null)) ...[
                    const SizedBox(height: 14),
                    _splitCard(r),
                  ],
                  if (r.hasDetails) ...[
                    const SizedBox(height: 14),
                    _details(r),
                  ],
                  if (!r.hasScore && widget.pending) ...[
                    const SizedBox(height: 14),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'Once your watch syncs, tap this day in the week row on '
                        'Home to see the full report.',
                        key: Key('report-waiting-hint'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: ReportColors.muted,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                  if (r.dream != null) ...[
                    const SizedBox(height: 14),
                    _linkRow(
                      key: const Key('report-dream'),
                      icon: Icons.auto_stories_rounded,
                      label: 'Dream diary',
                      onTap: () => _showDream(r.dream!),
                    ),
                  ],
                  if (widget.canOpenInsights) ...[
                    const SizedBox(height: 14),
                    _linkRow(
                      key: const Key('report-insights'),
                      icon: Icons.bar_chart_rounded,
                      label: 'View sleep insights',
                      onTap: () =>
                          Navigator.of(context).pop(kReportOpenInsights),
                    ),
                  ],
                  if (r.source == ReportSource.bundled) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'From the data bundled with the app (backend unreachable).',
                      key: Key('report-source-bundled'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: ReportColors.muted, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 14),
                  FilledButton(
                    key: const Key('report-done'),
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: ReportColors.navy,
                      minimumSize: const Size.fromHeight(56),
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(
                        fontFamily: kReportFont,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    child: const Text('Back to home'),
                  ),
                ],
              ),
            ),
          ],
        ),
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
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
              ),
              const Text(
                'Last night',
                style: TextStyle(color: ReportColors.muted, fontSize: 13),
              ),
            ],
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(right: 10),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: ReportColors.muted,
              ),
            ),
          ),
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            key: const Key('report-close'),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              side: const BorderSide(color: Color(0x2EFFFFFF)),
            ),
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
          ),
        ),
      ],
    );
  }

  // ── 圓環＋山丘＋小狗＋自評小標籤 ─────────────────────────────────

  Widget _hero(MorningReport r) {
    const ring = 236.0;
    return SizedBox(
      height: 352,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 4,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: ring,
                height: ring,
                child: r.hasScore ? _scoreRing(r) : _waitingRing(),
              ),
            ),
          ),
          // 山丘：延伸到左右邊（抵掉 ListView 的 16 邊距）
          const Positioned(
            left: -16,
            right: -16,
            bottom: 0,
            height: 120,
            child: CustomPaint(painter: _HillPainter()),
          ),
          if (r.hasScore)
            Positioned(
              right: 18,
              bottom: 50,
              child: HomePet(
                key: const Key('report-pet-awake'),
                mood: r.mood,
                size: 110,
              ),
            )
          else
            const Positioned(
              right: 8,
              bottom: 40,
              child: SleepingPet(key: Key('report-pet-asleep'), size: 140),
            ),
          Positioned(
            left: 0,
            bottom: 8,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 230),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (r.rating != null) _ratingChip(r),
                  if (r.hasScore &&
                      r.moodDescription != null &&
                      r.moodDescription!.isNotEmpty) ...[
                    if (r.rating != null) const SizedBox(height: 8),
                    Text(
                      r.moodDescription!,
                      key: const Key('report-mood-line'),
                      style: const TextStyle(
                        color: ReportColors.soft,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoreRing(MorningReport r) {
    final score = r.score!.round();
    final color = _hex(r.qualityColor) ?? ReportColors.accent;
    final line = [
      if (r.quality != null) r.quality!,
      if (r.scoreMessage != null && r.scoreMessage!.isNotEmpty) r.scoreMessage!,
    ].join(' · ');
    return CustomPaint(
      key: const Key('report-gauge'),
      painter: _RingPainter(value: (score / 100).clamp(0.0, 1.0)),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$score',
              key: const Key('report-score'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 64,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Sleep score',
              style: TextStyle(color: ReportColors.muted, fontSize: 13),
            ),
            if (line.isNotEmpty) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Text(
                  line,
                  key: const Key('report-quality'),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 沒有分數時：虛線圓環。只有「剛結束的那一晚」才說在等資料；
  /// 更早的晚上說沒有資料（yet：早晨匯入晚跑幾天，還是可能補進來）。
  Widget _waitingRing() {
    return CustomPaint(
      key: const Key('report-waiting'),
      painter: const _DashedRingPainter(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.watch_rounded, color: ReportColors.lilac, size: 30),
            const SizedBox(height: 8),
            Text(
              widget.pending ? kWaitingForWatch : kNoWatchData,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
                height: 1.25,
              ),
            ),
            if (widget.pending) ...[
              const SizedBox(height: 8),
              const Text(
                'Your score shows up here once your watch syncs.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ReportColors.muted,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _ratingChip(MorningReport r) {
    final rating = r.rating!;
    return Container(
      key: const Key('report-rating'),
      padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ReportColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            restedFaceAsset(rating.rested),
            width: 30,
            height: 30,
            errorBuilder: (_, _, _) => const SizedBox(width: 30, height: 30),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'You felt',
                  style: TextStyle(color: ReportColors.muted, fontSize: 11),
                ),
                Text(
                  r.ratingLabel ?? rating.label,
                  key: const Key('report-rating-label'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 等級與 XP（照抄 /game） ────────────────────────────────────

  Widget _xp(MorningReport r) {
    final size = r.xpLevelSize;
    final into = r.xpIntoLevel ?? 0;
    final night = r.nightXp;
    return Container(
      key: const Key('report-xp'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: reportCard(radius: 20),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [ReportColors.purple, Color(0xFFC08BFF)],
              ),
            ),
            child: Text(
              'Lv${r.level}',
              key: const Key('report-level'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        size == null
                            ? 'Max level'
                            : '${_n(into)} / ${_n(size)} XP',
                        key: const Key('report-xp-text'),
                        style: const TextStyle(
                            color: ReportColors.muted, fontSize: 12),
                      ),
                    ),
                    if (size != null)
                      Text(
                        '${_n(size - into)} to Lv${(r.level ?? 0) + 1}',
                        key: const Key('report-xp-to-next'),
                        style: const TextStyle(
                            color: ReportColors.muted, fontSize: 12),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 8,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: Colors.white.withValues(alpha: 0.14)),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: (r.xpProgress ?? 0).clamp(0.0, 1.0),
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [ReportColors.purple, Color(0xFFFFB36B)],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (night != null) ...[
            const SizedBox(width: 12),
            Container(
              key: const Key('report-night-xp'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0x29FFC83D),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '+$night XP',
                    style: const TextStyle(
                      color: ReportColors.gold,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                  if (r.nightXpSoFar)
                    const Text(
                      'so far',
                      key: Key('report-night-xp-so-far'),
                      style: TextStyle(
                        color: ReportColors.gold,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── From your buddy：AI 那段＋小建議（都照抄 /night-summary） ─────────────

  Widget _buddy(MorningReport r) {
    final tip = r.tip;
    return Container(
      key: const Key('report-buddy'),
      padding: const EdgeInsets.all(16),
      decoration: reportCard(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 16, color: ReportColors.accent),
              SizedBox(width: 8),
              Text(
                'From your buddy',
                style: TextStyle(
                  color: ReportColors.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (r.summaryText != null) ...[
            const SizedBox(height: 10),
            Text(
              r.summaryText!,
              key: const Key('report-summary'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.5,
              ),
            ),
          ],
          if (tip != null) ...[
            const SizedBox(height: 10),
            Container(
              key: const Key('report-tip'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      // tip 是「下次可以怎麼做」，note 只解釋這一晚——圖示分開
                      tip.isNote
                          ? Icons.info_outline_rounded
                          : Icons.lightbulb_outline_rounded,
                      key: Key(tip.isNote ? 'report-tip-note' : 'report-tip-tip'),
                      size: 18,
                      color: ReportColors.gold,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tip.text,
                      style: const TextStyle(
                        color: ReportColors.soft,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Time in bed／Time asleep ─────────────────────────────────────

  Widget _timeCards(MorningReport r) {
    final inBed = r.timeInBedMinutes;
    final asleep = r.hasScore ? r.sleepMinutes : null;
    final goal = r.goalMinutes;
    final Widget asleepFooter;
    if (asleep == null) {
      asleepFooter = const Text(
        'From your watch',
        style: TextStyle(color: ReportColors.faint, fontSize: 12),
      );
    } else if (goal == null) {
      asleepFooter = const SizedBox.shrink();
    } else {
      asleepFooter = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              key: const Key('report-goal-bar'),
              value: (asleep / goal).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.14),
              // 不依達標與否變色（使用者定）
              color: ReportColors.lilac,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'of your ${reportHm(goal)} goal',
            key: const Key('report-goal-line'),
            style: const TextStyle(color: ReportColors.muted, fontSize: 12),
          ),
        ],
      );
    }
    final start = r.bedStart;
    final end = r.bedEnd;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _timeCard(
              key: const Key('report-in-bed'),
              icon: Icons.bed_rounded,
              label: 'Time in bed',
              value: inBed == null ? '—' : reportHm(inBed),
              valueKey: 'report-in-bed-value',
              change:
                  inBed == null ? null : changeOf(inBed, r.previousTimeInBed),
              changeKey: 'report-in-bed-change',
              dashed: inBed == null,
              footer: Text(
                start == null
                    ? 'No bedtime recorded'
                    : '${reportClock(start)} → '
                        '${end == null ? '—' : reportClock(end)}',
                key: const Key('report-times'),
                style: const TextStyle(color: ReportColors.muted, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _timeCard(
              key: const Key('report-asleep'),
              icon: Icons.nightlight_round,
              label: 'Time asleep',
              value: asleep == null ? '—' : reportHm(asleep),
              valueKey: 'report-duration',
              change: asleep == null
                  ? null
                  : changeOf(asleep, r.previousSleepMinutes),
              changeKey: 'report-duration-change',
              dashed: asleep == null,
              footer: asleepFooter,
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeCard({
    required Key key,
    required IconData icon,
    required String label,
    required String value,
    required String valueKey,
    required ChangeDirection? change,
    required String changeKey,
    required Widget footer,
    bool dashed = false,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(14),
      decoration: reportCard(dashed: dashed),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: ReportColors.muted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style:
                      const TextStyle(color: ReportColors.muted, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    key: Key(valueKey),
                    style: TextStyle(
                      color: dashed ? ReportColors.dim : Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              if (change != null && change != ChangeDirection.same)
                _changeBadge(change, changeKey),
            ],
          ),
          const SizedBox(height: 8),
          footer,
        ],
      ),
    );
  }

  /// 跟上一晚比：**只代表方向**，上升紅、下降綠（使用者定）。
  Widget _changeBadge(ChangeDirection d, String key) {
    final up = d == ChangeDirection.up;
    final color = up ? ReportColors.up : ReportColors.down;
    return Semantics(
      label: up ? 'Up from last night' : 'Down from last night',
      child: Container(
        key: Key('$key-${up ? 'up' : 'down'}'),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          up ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
          color: color,
          size: 24,
        ),
      ),
    );
  }

  // ── Phone down｜Your target ─────────────────────────────────────

  Widget _phoneDown(MorningReport r) {
    final line = adherenceLine(r.adherenceMinutes);
    return Container(
      key: const Key('report-phone-down'),
      padding: const EdgeInsets.all(16),
      decoration: reportCard(),
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _centerStat('Phone down', reportClock(r.lightsOutAt!),
                      Colors.white, 'report-phone-down-at'),
                ),
                if (r.targetBedtime != null) ...[
                  const VerticalDivider(
                      width: 1, thickness: 1, color: ReportColors.border),
                  Expanded(
                    child: _centerStat('Your target', r.targetBedtime!,
                        ReportColors.accent, 'report-target'),
                  ),
                ],
              ],
            ),
          ),
          if (line != null) ...[
            const SizedBox(height: 12),
            Text(
              line,
              key: const Key('report-adherence'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: ReportColors.soft, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _centerStat(String label, String value, Color color, String key) =>
      Column(
        children: [
          Text(label,
              style: const TextStyle(color: ReportColors.muted, fontSize: 13)),
          const SizedBox(height: 2),
          Text(
            value,
            key: Key(key),
            style: TextStyle(
              color: color,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      );

  // ── 淺睡／深睡／REM 比例（沒有 Sleep phases 圖的晚上） ─────────────

  Widget _splitCard(MorningReport r) {
    if (!r.hasStageSplit) {
      // 沒有淺睡就不畫比例條。兩種原因要講不同的話：
      // 沒量到 REM（淺睡會把 REM 吃進去）vs 後端是舊版、沒給淺睡（REM 其實有量到）
      final rem = r.remMeasured && r.remMinutes != null
          ? 'REM ${reportHm(r.remMinutes!)}'
          : 'REM not measured';
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: reportCard(),
        child: Text(
          'Deep ${reportHm(r.deepMinutes!)} · $rem',
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
    return Container(
      key: const Key('report-split'),
      padding: const EdgeInsets.all(16),
      decoration: reportCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sleep phases',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
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
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: p.$3,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          p.$1,
                          style: const TextStyle(
                            color: ReportColors.muted,
                            fontSize: 12,
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
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      reportHm(p.$2),
                      style: const TextStyle(
                        color: ReportColors.muted,
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

  // ── More details（收合）：WASO、心率、效率、攝影機 ──────────────────

  Widget _details(MorningReport r) {
    final showWaso = r.hasScore && r.wasoMinutes != null;
    final showHr =
        r.hasScore && (r.avgHeartRate != null || r.restingHeartRate != null);
    final showEff = r.hasScore && r.efficiency != null;
    final showCam = r.camera?.usualLabel != null;
    final names = [
      if (showWaso) 'Awake time',
      if (showHr) 'Heart rate',
      if (showEff) 'Efficiency',
      if (showCam) 'Movement',
    ];
    return Container(
      decoration: reportCard(radius: 18),
      child: Column(
        children: [
          InkWell(
            key: const Key('report-details-toggle'),
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => _detailsOpen = !_detailsOpen),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.monitor_heart_outlined,
                        size: 18, color: ReportColors.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'More details',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            names.join(' · '),
                            style: const TextStyle(
                                color: ReportColors.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _detailsOpen ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.expand_more_rounded,
                          color: ReportColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: !_detailsOpen
                ? const SizedBox(width: double.infinity)
                : Padding(
                    key: const Key('report-details'),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Divider(height: 1, color: ReportColors.border),
                        if (showWaso)
                          _detailRow(
                            'Awake during the night',
                            reportHm(r.wasoMinutes!),
                            'report-waso',
                          ),
                        if (showHr)
                          _detailRow(
                            'Heart rate',
                            [
                              if (r.avgHeartRate != null)
                                '${r.avgHeartRate!.round()} bpm avg',
                              if (r.restingHeartRate != null)
                                '${r.restingHeartRate!.round()} resting',
                            ].join(' · '),
                            'report-hr',
                          ),
                        if (showEff)
                          _detailRow(
                            'Sleep efficiency',
                            // 照抄，不四捨五入掉小數
                            '${r.efficiency}%',
                            'report-efficiency',
                            notes: [
                              if (r.efficiencyCaveat != null)
                                r.efficiencyCaveat!,
                              if (r.efficiencyBasis != null)
                                'Basis: ${r.efficiencyBasis}',
                            ],
                          ),
                        if (showCam)
                          _detailRow(
                            'Movement (camera)',
                            r.camera!.usualLabel!,
                            'report-camera',
                            notes: const [
                              'Camera data is not part of your score.',
                            ],
                            valueBelow: true,
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, String key,
      {List<String> notes = const [], bool valueBelow = false}) {
    final valueText = Text(
      value,
      key: Key(key),
      textAlign: valueBelow ? TextAlign.start : TextAlign.end,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    );
    const labelStyle = TextStyle(color: ReportColors.muted, fontSize: 13);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (valueBelow) ...[
            Text(label, style: labelStyle),
            const SizedBox(height: 2),
            valueText,
          ] else
            Row(
              children: [
                Expanded(child: Text(label, style: labelStyle)),
                const SizedBox(width: 12),
                Flexible(child: valueText),
              ],
            ),
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                n,
                style: const TextStyle(
                  color: ReportColors.faint,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _linkRow({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          decoration: reportCard(radius: 18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: ReportColors.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: ReportColors.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showDream(String dream) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ReportColors.sheet,
      showDragHandle: true,
      builder: (context) => ReportFont(
        child: SafeArea(
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
                    fontWeight: FontWeight.w900,
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
      ),
    );
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

/// 分數圓環：深色底盤＋淡色全圈，上面依分數畫一段漸層弧（從 12 點鐘開始）。
class _RingPainter extends CustomPainter {
  final double value;
  const _RingPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 16.0;
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 18;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xBF141C46));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Colors.white.withValues(alpha: 0.10),
    );
    if (value <= 0) return;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        colors: [Color(0xFF7FB2FF), Color(0xFFB9A6FF), Color(0xFFFF8AD8)],
        stops: [0, 0.55, 1],
        transform: GradientRotation(-math.pi / 2),
      ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * value, false, fill);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value;
}

/// 等待中：虛線圓環。
class _DashedRingPainter extends CustomPainter {
  const _DashedRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 18;
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xBF141C46));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x59B9A6FF);
    const dash = 6.0;
    const gap = 9.0;
    final count = (2 * math.pi * radius / (dash + gap)).floor();
    final step = 2 * math.pi / count;
    final sweep = step * dash / (dash + gap);
    final rect = Rect.fromCircle(center: center, radius: radius);
    for (var i = 0; i < count; i++) {
      canvas.drawArc(rect, i * step, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter old) => false;
}

/// 小狗坐的山丘（示意圖的曲線，依寬度縮放）。
class _HillPainter extends CustomPainter {
  const _HillPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 390;
    final sy = size.height / 120;
    final ridge = Path()
      ..moveTo(0, 70 * sy)
      ..cubicTo(90 * sx, 40 * sy, 170 * sx, 52 * sy, 230 * sx, 58 * sy)
      ..cubicTo(300 * sx, 64 * sy, 350 * sx, 46 * sy, 390 * sx, 52 * sy);
    final fill = Path.from(ridge)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = ReportColors.hill);
    canvas.drawPath(
      ridge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0x59B9A6FF),
    );
  }

  @override
  bool shouldRepaint(_HillPainter old) => false;
}
