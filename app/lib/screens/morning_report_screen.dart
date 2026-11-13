import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/morning_rating.dart';
import '../services/morning_report.dart';
import '../theme/report_style.dart';
import '../widgets/dream_diary.dart';
import '../widgets/home_pet.dart';
import '../models/night_curve.dart';
import '../models/yesterday_activity.dart';
import '../services/night_compare.dart' show shortDate;
import '../widgets/day_heart_rate_chart.dart';
import '../widgets/report_tiles.dart';
import '../widgets/sleep_stages_card.dart';
import '../widgets/sleepy_pet.dart';

/// 早晨報告畫面（2026-11-12 定案；11-13 依示意圖重做：深藍夜空、分數圓環當主角、
/// 小狗坐在圓環右下的山丘上、卡片少而短）。
///
/// 由上到下：日期 → 圓環＋山丘＋小狗＋自評小標籤 → Lv／XP 一條 → From your buddy
/// （AI 那段＋小建議）→ Time in bed／Time asleep → Phone down｜Your target
/// → Sleep phases → More details（收合）→ View sleep insights → Back to home。
/// 那一晚有夢境時，小狗頭上有「I had a dream…」對話框，點開看夢境日記（`widgets/dream_diary.dart`）。
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

  /// 點開夢境之後（首頁用來記「這個夢看過了」）。
  final VoidCallback? onDreamOpened;

  const MorningReportScreen({
    super.key,
    required this.initial,
    this.load,
    this.loadSummary,
    this.pending = true,
    this.canOpenInsights = false,
    this.onDreamOpened,
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
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
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

  @override
  void initState() {
    super.initState();
    final load = widget.load;
    if (load != null) {
      _loading = true;
      load()
          .then((r) async {
            if (!mounted) return;
            setState(() => _report = r);
            final summary = widget.loadSummary;
            if (summary != null && r.hasScore) {
              final json = await summary();
              if (mounted) setState(() => _report = _report.withSummary(json));
            }
          })
          .whenComplete(() {
            if (mounted) setState(() => _loading = false);
          });
    } else if (widget.loadSummary != null && widget.initial.hasScore) {
      // 等待畫面已經備好分數，只剩 AI 那段還在路上（超過等待時間）
      _loading = true;
      widget.loadSummary!()
          .then((json) {
            if (mounted) setState(() => _report = _report.withSummary(json));
          })
          .whenComplete(() {
            if (mounted) setState(() => _loading = false);
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    final hasBuddy = r.hasScore && (_buddyText(r) != null || r.tip != null);
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
                  if (r.level != null) ...[const SizedBox(height: 14), _xp(r)],
                  if (hasBuddy) ...[const SizedBox(height: 14), _buddy(r)],
                  // 昨晚的數字（2026-11-14 改成圖形格子，參考圖：每一格的圖就是那個數字）
                  const SizedBox(height: 18),
                  reportSectionTitle(
                    'Last night',
                    key: const Key('report-last-night'),
                  ),
                  _lastNightTiles(r),
                  if (r.stages != null) ...[
                    const SizedBox(height: 14),
                    SleepStagesCard(
                      stages: r.stages!,
                      totalSleepMinutes: r.sleepMinutes?.round(),
                      // 點 Heart rate／Movement 疊線（2026-11-13）
                      heartRate: r.heartRate,
                      movement: r.movement,
                      camera: r.cameraMotion,
                      restingHeartRate: r.restingHeartRate,
                    ),
                  ] else if (r.hasScore &&
                      (r.hasStageSplit || r.deepMinutes != null)) ...[
                    const SizedBox(height: 14),
                    _splitCard(r),
                  ],
                  // 前一天的 Garmin 白天資料：只呈現、不計分；那天沒資料就整段不畫
                  if (r.yesterday != null &&
                      _yesterdayTiles(r.yesterday!) != null) ...[
                    const SizedBox(height: 18),
                    reportSectionTitle(
                      'Yesterday · ${_dayLabel(r.yesterday!.date)}',
                      key: const Key('report-yesterday'),
                    ),
                    _yesterdayTiles(r.yesterday!)!,
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
                  // 夢境改成小狗頭上的對話框（_hero），這裡不再放一列（2026-11-13）
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
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.white,
              size: 20,
            ),
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
          // 小狗頭邊一朵小雲，點開看完整夢境；那一晚沒有夢就不出現。
          // 報告用小的（不寫字）：大的那朵會蓋到分數圓環的右半邊，圓環右邊只剩約 70 寬。
          if (r.dream != null)
            Positioned(
              key: const Key('report-dream'),
              right: 4,
              bottom: r.hasScore ? 162 : 150,
              child: DreamBubble(compact: true, onTap: () => _showDream(r)),
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
            const Icon(
              Icons.watch_rounded,
              color: ReportColors.lilac,
              size: 30,
            ),
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
                          color: ReportColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (size != null)
                      Text(
                        '${_n(size - into)} to Lv${(r.level ?? 0) + 1}',
                        key: const Key('report-xp-to-next'),
                        style: const TextStyle(
                          color: ReportColors.muted,
                          fontSize: 12,
                        ),
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
                                colors: [
                                  ReportColors.purple,
                                  Color(0xFFFFB36B),
                                ],
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

  /// AI 那段。⚠️ 後端寫不出來時（source = fallback）回的是 score_message＋mood_description，
  /// 也就是圓環下面已經有的那兩句——再放一次就是同一句話出現兩遍，所以不放，只留小建議。
  static String? _buddyText(MorningReport r) =>
      r.summarySource == 'fallback' ? null : r.summaryText;

  Widget _buddy(MorningReport r) {
    final tip = r.tip;
    final text = _buddyText(r);
    return Container(
      key: const Key('report-buddy'),
      padding: const EdgeInsets.all(16),
      decoration: reportCard(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: ReportColors.accent,
              ),
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
          if (text != null) ...[
            const SizedBox(height: 10),
            Text(
              text,
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
                      key: Key(
                        tip.isNote ? 'report-tip-note' : 'report-tip-tip',
                      ),
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

  // ── 圖形格子（2026-11-14 使用者定，參考圖：每一格的圖就是那個數字）─────────
  //
  // ⚠️ 底下那行只寫事實（參考圖寫 Elevated／Perfect day，我們不寫）；沒值的格子不畫、不畫成 0。

  static const _cAsleep = Color(0xFFB9A6FF);
  static const _cBed = Color(0xFF8FA8FF);
  static const _cPhone = Color(0xFFFFC97A);
  static const _cEff = Color(0xFF7EC8FF);
  static const _cAwake = Color(0xFFFF8AD8);
  static const _cHr = Color(0xFFFF8AB8);
  static const _cCam = Color(0xFFFFD96A);
  static const _cSteps = Color(0xFFFFB37A);
  static const _cActive = Color(0xFFFFD96A);
  static const _cStress = Color(0xFFA996FF);
  static const _cBattery = Color(0xFF6FE3C1);
  static const _cMove = Color(0xFF7ED957);

  Widget? _badge(ChangeDirection? d, String key) =>
      d == null || d == ChangeDirection.same ? null : _changeBadge(d, key);

  /// 曲線 → 小折線的點（x 照時間，0–1）。
  static List<(double, double)> _curvePoints(NightCurve c) {
    final pts = c.points;
    final t0 = pts.first.time;
    final span = pts.last.time.difference(t0).inSeconds;
    if (span <= 0) return const [];
    return [
      for (final p in pts) (p.time.difference(t0).inSeconds / span, p.value),
    ];
  }

  void _openCurve(MorningReport r, String overlay) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ReportColors.sheet,
      builder: (_) => SafeArea(
        child: Padding(
          key: Key('report-curve-$overlay'),
          padding: const EdgeInsets.all(16),
          child: SleepStagesCard(
            stages: r.stages!,
            totalSleepMinutes: r.sleepMinutes?.round(),
            heartRate: r.heartRate,
            movement: r.movement,
            camera: r.cameraMotion,
            restingHeartRate: r.restingHeartRate,
            initialOverlay: overlay,
          ),
        ),
      ),
    );
  }

  Widget _lastNightTiles(MorningReport r) {
    final asleep = r.hasScore ? r.sleepMinutes : null;
    final goal = r.goalMinutes;
    final inBed = r.timeInBedMinutes;
    final start = r.bedStart;
    final end = r.bedEnd;

    final asleepTile = ReportTile(
      key: const Key('report-asleep'),
      icon: Icons.nightlight_round,
      color: _cAsleep,
      title: 'Time asleep',
      value: asleep == null ? '—' : reportHm(asleep),
      valueKey: const Key('report-duration'),
      valueTrailing: _badge(
        asleep == null ? null : changeOf(asleep, r.previousSleepMinutes),
        'report-duration-change',
      ),
      dashed: asleep == null,
      // 光帶長度＝睡了多久÷目標；**不依達標與否變色**（使用者定）
      graphic: asleep != null && goal != null && goal > 0
          ? paintBox(
              WaveBarPainter(asleep / goal, _cAsleep),
              key: const Key('report-goal-bar'),
            )
          : null,
      graphicHeight: 30,
      lines: [
        if (asleep == null)
          const Text('From your watch')
        else if (goal != null)
          Text(
            'of your ${reportHm(goal)} goal',
            key: const Key('report-goal-line'),
          ),
      ],
    );

    final inBedTile = ReportTile(
      key: const Key('report-in-bed'),
      icon: Icons.bed_rounded,
      color: _cBed,
      title: 'Time in bed',
      value: inBed == null ? '—' : reportHm(inBed),
      valueKey: const Key('report-in-bed-value'),
      valueTrailing: _badge(
        inBed == null ? null : changeOf(inBed, r.previousTimeInBed),
        'report-in-bed-change',
      ),
      dashed: inBed == null,
      graphic: start == null
          ? null
          : paintBox(
              NightTimelinePainter(
                nightMinute(start.hour, start.minute),
                end == null ? null : nightMinute(end.hour, end.minute),
                _cBed,
              ),
              key: const Key('report-bed-timeline'),
            ),
      graphicHeight: 30,
      lines: [
        // 沒按按鈕：不拿手錶的入睡冒充上床
        Text(
          start == null
              ? 'No bedtime recorded'
              : '${reportClock(start)} → ${end == null ? '—' : reportClock(end)}',
          key: const Key('report-times'),
        ),
      ],
    );

    Widget? phoneTile;
    final lightsOut = r.lightsOutAt;
    if (lightsOut != null) {
      final target = r.targetBedtime;
      final tParts = target?.split(':');
      final ok = tParts != null && tParts.length == 2;
      final th = ok ? int.tryParse(tParts[0]) : null;
      final tm = ok ? int.tryParse(tParts[1]) : null;
      final line = adherenceLine(r.adherenceMinutes);
      phoneTile = ReportTile(
        key: const Key('report-phone-down'),
        icon: Icons.phone_android_rounded,
        color: _cPhone,
        title: 'Phone down',
        value: reportClock(lightsOut),
        valueKey: const Key('report-phone-down-at'),
        graphic: th == null || tm == null
            ? null
            : paintBox(
                ClockArcPainter(
                  nightMinute(th, tm),
                  nightMinute(lightsOut.hour, lightsOut.minute),
                  _cPhone,
                ),
                key: const Key('report-phone-arc'),
              ),
        graphicHeight: 40,
        lines: [
          if (target != null)
            // Wrap：半格放不下時換行，不溢出
            Wrap(
              children: [
                const Text('Your target '),
                Text(
                  target,
                  key: const Key('report-target'),
                  style: const TextStyle(
                    color: ReportColors.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          // 達成度只照抄後端（跨午夜在 behavior/adherence.py 算）
          if (line != null) Text(line, key: const Key('report-adherence')),
        ],
      );
    }

    Widget? awakeTile;
    if (r.hasScore && r.wasoMinutes != null) {
      final st = r.stages;
      List<(double, double)>? segs;
      if (st != null) {
        final total = st.end.difference(st.start).inSeconds;
        if (total > 0) {
          segs = [
            for (final s in st.segments)
              if (s.stage == 'awake')
                (
                  s.start.difference(st.start).inSeconds / total,
                  s.end.difference(st.start).inSeconds / total,
                ),
          ];
        }
      }
      awakeTile = ReportTile(
        key: const Key('report-awake'),
        icon: Icons.visibility_rounded,
        color: _cAwake,
        title: 'Awake',
        value: reportHm(r.wasoMinutes!),
        valueKey: const Key('report-waso'),
        graphic: segs == null
            ? null
            : paintBox(
                SegmentStripPainter(segs, _cAwake),
                key: const Key('report-awake-strip'),
              ),
        graphicHeight: 20,
        lines: const [Text('during the night')],
      );
    }

    // 心率：有曲線就用曲線那一段的平均（跟 Sleep Stages 點 Heart rate 同一個數）；
    // 沒有曲線才用 metrics 的平均。⚠️ 同一頁不得出現兩個不同的「平均心率」。
    Widget? hrTile;
    final hrCurve = r.heartRate;
    final hrAvg = hrCurve?.avg ?? r.avgHeartRate;
    if (r.hasScore && (hrAvg != null || r.restingHeartRate != null)) {
      hrTile = ReportTile(
        key: const Key('report-hr-tile'),
        icon: Icons.favorite_rounded,
        color: _cHr,
        title: 'Heart rate',
        value: hrAvg == null ? null : '${hrAvg.round()} bpm',
        graphic: hrCurve == null
            ? null
            : paintBox(
                SparklinePainter(_curvePoints(hrCurve), _cHr),
                key: const Key('report-hr-line'),
              ),
        onTap: hrCurve == null || r.stages == null
            ? null
            : () => _openCurve(r, 'heartRate'),
        lines: [
          Text(
            [
              if (hrAvg != null) '${hrAvg.round()} bpm avg',
              if (r.restingHeartRate != null)
                '${r.restingHeartRate!.round()} resting',
            ].join(' · '),
            key: const Key('report-hr'),
          ),
        ],
      );
    }

    Widget? camTile;
    if (r.camera?.usualLabel != null) {
      final cam = r.cameraMotion;
      camTile = ReportTile(
        key: const Key('report-camera-tile'),
        icon: Icons.videocam_rounded,
        color: _cCam,
        title: 'Movement (camera)',
        graphic: cam == null
            ? null
            : paintBox(
                SparklinePainter(_curvePoints(cam), _cCam, lo: 0),
                key: const Key('report-camera-line'),
              ),
        onTap: cam == null || r.stages == null
            ? null
            : () => _openCurve(r, 'camera'),
        lines: [
          // 後端寫好的那句「跟你平常比」，照抄
          Text(
            r.camera!.usualLabel!,
            key: const Key('report-camera'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Text(
            'Camera data is not part of your score.',
            style: TextStyle(color: ReportColors.faint, fontSize: 11),
          ),
        ],
      );
    }

    // 效率：圓環＝百分比。警語與 basis 很長，點格子才跳出來（以前也是收在 More details 裡）
    Widget? effTile;
    if (r.hasScore && r.efficiency != null) {
      final notes = [
        // 與 Insights 頁同一個寫法（「Efficiency - 原文」）：後端那段字照抄
        if (r.efficiencyCaveat != null) 'Efficiency - ${r.efficiencyCaveat!}',
        // App 裡有好幾個「效率」，只有 basis 分得開
        if (r.efficiencyBasis != null) 'Basis: ${r.efficiencyBasis}',
      ];
      effTile = ReportTile(
        key: const Key('report-efficiency-tile'),
        icon: Icons.speed_rounded,
        color: _cEff,
        title: 'Efficiency',
        // 照抄，不四捨五入掉小數
        value: '${r.efficiency}%',
        valueKey: const Key('report-efficiency'),
        graphic: paintBox(
          RingPainter(r.efficiency!, _cEff),
          key: const Key('report-efficiency-ring'),
        ),
        graphicHeight: 56,
        onTap: notes.isEmpty
            ? null
            : () => showModalBottomSheet<void>(
                context: context,
                backgroundColor: ReportColors.sheet,
                builder: (_) => SafeArea(
                  child: Padding(
                    key: const Key('report-efficiency-sheet'),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sleep efficiency · ${r.efficiency}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        for (final n in notes)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              n,
                              style: const TextStyle(
                                color: ReportColors.soft,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
        lines: [if (notes.isNotEmpty) const Text('How it is measured')],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        reportTileGrid([
          asleepTile,
          inBedTile,
          phoneTile,
          awakeTile,
          effTile,
          hrTile,
          camTile,
        ]),
      ],
    );
  }

  static String _dayLabel(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    const w = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${w[d.weekday - 1]}, ${shortDate(iso)}';
  }

  static String _comma(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  static String _secHm(int sec) => reportHm(sec / 60);

  /// 那一天的白天資料格子。一格都沒有 → null（整段不畫）。
  Widget? _yesterdayTiles(YesterdayActivity y) {
    // 最近 7 天（到那一天為止）
    List<(String, double)> last7(int? Function(ActivityHistoryDay) pick) {
      final days = [
        for (final h in y.history)
          if (h.date.compareTo(y.date) <= 0 && pick(h) != null) h,
      ]..sort((a, b) => a.date.compareTo(b.date));
      final tail = days.length > 7 ? days.sublist(days.length - 7) : days;
      return [for (final h in tail) (shortDate(h.date), pick(h)!.toDouble())];
    }

    Widget? stepsTile;
    if (y.steps != null) {
      final hist = last7((h) => h.steps);
      stepsTile = ReportTile(
        key: const Key('report-steps'),
        icon: Icons.directions_walk_rounded,
        color: _cSteps,
        title: 'Steps',
        value: _comma(y.steps!),
        valueKey: const Key('report-steps-value'),
        graphic: hist.length < 2
            ? null
            : paintBox(
                MountainPainter([for (final h in hist) h.$2], _cSteps),
                key: const Key('report-steps-mountain'),
              ),
        onTap: hist.length < 2
            ? null
            : () => showReportBarsSheet(
                context,
                id: 'steps',
                title: 'Steps',
                bars: hist,
                format: (v) => _comma(v.round()),
              ),
        lines: [
          // 只寫 goal，不寫 reached（紅線 2）
          if (y.stepGoal != null) Text('goal ${_comma(y.stepGoal!)}'),
          if (y.distanceM != null || y.floorsUp != null)
            Text(
              [
                if (y.distanceM != null)
                  '${(y.distanceM! / 1000).toStringAsFixed(1)} km',
                if (y.floorsUp != null)
                  '${y.floorsUp!.toStringAsFixed(0)} floors up',
              ].join(' · '),
            ),
        ],
      );
    }

    Widget? activeTile;
    if (y.hasActivity) {
      final hist = last7((h) => h.activeMinutes);
      final active = y.activeMinutes;
      activeTile = ReportTile(
        key: const Key('report-active'),
        icon: Icons.bolt_rounded,
        color: _cActive,
        title: 'Active time',
        value: active == null ? null : reportHm(active),
        graphic: paintBox(
          StackedBarPainter([
            ((y.highlyActiveSec ?? 0).toDouble(), _cActive),
            ((y.activeSec ?? 0).toDouble(), _cActive.withValues(alpha: 0.55)),
            (
              (y.sedentarySec ?? 0).toDouble(),
              Colors.white.withValues(alpha: 0.16),
            ),
          ]),
          key: const Key('report-active-bar'),
        ),
        graphicHeight: 18,
        onTap: hist.length < 2
            ? null
            : () => showReportBarsSheet(
                context,
                id: 'active',
                title: 'Active time',
                bars: hist,
                format: (v) => reportHm(v),
              ),
        lines: [
          Text(
            [
              if (y.highlyActiveSec != null)
                'high ${_secHm(y.highlyActiveSec!)}',
              if (y.activeSec != null) 'active ${_secHm(y.activeSec!)}',
              if (y.sedentarySec != null) 'still ${_secHm(y.sedentarySec!)}',
            ].join(' · '),
          ),
        ],
      );
    }

    Widget? stressTile;
    if (y.hasStress) {
      // 同一色系深淺，不用紅黃（使用者定）；只給各段的時間，不加說明
      final parts = [
        ('Rest', y.stressRestSec, _cStress.withValues(alpha: 0.3)),
        ('Low', y.stressLowSec, _cStress.withValues(alpha: 0.55)),
        ('Medium', y.stressMediumSec, _cStress.withValues(alpha: 0.8)),
        ('High', y.stressHighSec, _cStress),
      ];
      stressTile = ReportTile(
        key: const Key('report-stress'),
        icon: Icons.spa_rounded,
        color: _cStress,
        title: 'Stress',
        graphic: paintBox(
          GaugePainter([for (final p in parts) ((p.$2 ?? 0).toDouble(), p.$3)]),
          key: const Key('report-stress-gauge'),
        ),
        graphicHeight: 52,
        lines: [
          Text(
            [
              for (final p in parts)
                if (p.$2 != null) '${p.$1} ${_secHm(p.$2!)}',
            ].join(' · '),
          ),
        ],
      );
    }

    Widget? batteryTile;
    if (y.hasBodyBattery) {
      final up = y.bodyBatteryCharged;
      final down = y.bodyBatteryDrained;
      batteryTile = ReportTile(
        key: const Key('report-body-battery'),
        icon: Icons.battery_charging_full_rounded,
        color: _cBattery,
        title: 'Body Battery',
        value: [if (up != null) '+$up', if (down != null) '−$down'].join(' / '),
        // 不畫成電池：Garmin 只給充了多少、用掉多少，沒有「剩幾 %」
        graphic: paintBox(
          TwoBarsPainter(
            (up ?? 0).toDouble(),
            (down ?? 0).toDouble(),
            _cBattery,
            _cBattery.withValues(alpha: 0.4),
          ),
          key: const Key('report-body-battery-bars'),
        ),
        lines: const [Text('charged · drained')],
      );
    }

    Widget? dayHrTile;
    final dayHr = y.dayHeartRate;
    if (dayHr != null) {
      dayHrTile = ReportTile(
        key: const Key('report-day-hr'),
        icon: Icons.monitor_heart_rounded,
        color: _cHr,
        title: 'Heart rate',
        value: '${dayHr.min.round()}–${dayHr.max.round()} bpm',
        graphic: paintBox(
          SparklinePainter(_curvePoints(dayHr), _cHr),
          key: const Key('report-day-hr-line'),
        ),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          backgroundColor: ReportColors.sheet,
          builder: (_) => SafeArea(
            child: Padding(
              key: const Key('report-day-hr-sheet'),
              padding: const EdgeInsets.all(20),
              child: SizedBox(height: 180, child: DayHeartRateChart(dayHr)),
            ),
          ),
        ),
        lines: [
          Text(
            [
              'all day',
              if (y.restingHeartRate != null) 'resting ${y.restingHeartRate}',
            ].join(' · '),
          ),
        ],
      );
    }

    Widget? moveTile;
    final moves = y.moveIq;
    if (moves != null && moves.isNotEmpty) {
      final walks = moves.where((m) => m.type == 'walking').length;
      final rides = moves.where((m) => m.type == 'cycling').length;
      final others = moves.length - walks - rides;
      moveTile = ReportTile(
        key: const Key('report-moveiq'),
        icon: Icons.route_rounded,
        color: _cMove,
        title: 'Move IQ',
        value: [
          if (walks > 0) '$walks walk${walks == 1 ? '' : 's'}',
          if (rides > 0) '$rides ride${rides == 1 ? '' : 's'}',
          if (others > 0) '$others other',
        ].join(' · '),
        graphic: paintBox(
          SegmentStripPainter(
            [
              for (final m in moves)
                if (m.startMinuteOfDay != null)
                  (
                    m.startMinuteOfDay! / 1440,
                    (m.startMinuteOfDay! + m.minutes) / 1440,
                  ),
            ],
            _cMove,
            ticks: const [
              (0, '0'),
              (0.25, '6'),
              (0.5, '12'),
              (0.75, '18'),
              (1, '24'),
            ],
          ),
          key: const Key('report-moveiq-timeline'),
        ),
        graphicHeight: 30,
      );
    }

    final tiles = [
      stepsTile,
      activeTile,
      stressTile,
      batteryTile,
      dayHrTile,
      moveTile,
    ];
    if (tiles.every((t) => t == null)) return null;
    return reportTileGrid(tiles);
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
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: ReportColors.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showDream(MorningReport r) {
    showDreamDiary(context, text: r.dream!, date: r.date, mood: r.mood);
    widget.onDreamOpened?.call();
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
    const colors = [Color(0xFF7FB2FF), Color(0xFFB9A6FF), Color(0xFFFF8AD8)];
    const stops = [0.0, 0.55, 1.0];
    final sweep = 2 * math.pi * value;
    // ⚠️ 不用 StrokeCap.round：起點的圓頭會伸到 12 點鐘左邊一點點，
    //    掃描漸層在那裡繞回尾端的粉紅色（實機看得到一個粉紅小點）。
    //    改成平頭弧＋兩端各補一個同色圓點。
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..shader = const SweepGradient(
        colors: colors,
        stops: stops,
        transform: GradientRotation(-math.pi / 2),
      ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, fill);
    Offset at(double a) => center + Offset(math.cos(a), math.sin(a)) * radius;
    canvas.drawCircle(at(-math.pi / 2), stroke / 2, Paint()..color = colors[0]);
    canvas.drawCircle(
      at(-math.pi / 2 + sweep),
      stroke / 2,
      Paint()..color = _colorAt(value, colors, stops),
    );
  }

  static Color _colorAt(double t, List<Color> colors, List<double> stops) {
    for (var i = 1; i < stops.length; i++) {
      if (t <= stops[i]) {
        final f = (t - stops[i - 1]) / (stops[i] - stops[i - 1]);
        return Color.lerp(colors[i - 1], colors[i], f)!;
      }
    }
    return colors.last;
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
