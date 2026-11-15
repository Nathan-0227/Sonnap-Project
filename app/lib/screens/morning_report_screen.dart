import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/game_service.dart' show NightXp;
import '../services/morning_rating.dart';
import '../services/morning_report.dart';
import '../theme/report_style.dart';
import '../widgets/dream_book.dart';
import '../widgets/dream_diary.dart';
import '../widgets/home_pet.dart';
import '../models/night_curve.dart';
import '../models/yesterday_activity.dart';
import '../services/night_compare.dart' show NightValue, shortDate;
import '../widgets/day_heart_rate_chart.dart';
import '../widgets/report_tiles.dart';
import '../widgets/sleep_stages_card.dart';
import '../widgets/phone_week_sheet.dart';
import '../services/camera_insights.dart'
    show CameraNight, EfficiencyNight, SleepHeartRate;
import '../widgets/heart_rate_sheet.dart';
import '../widgets/movement_sheet.dart';
import '../widgets/efficiency_sheet.dart';
import '../widgets/awake_week_sheet.dart';
import '../widgets/bed_week_sheet.dart';
import '../widgets/sleep_week_sheet.dart';
import '../widgets/sleepy_pet.dart';
import '../widgets/steps_sheet.dart';
import '../widgets/kcal_sheet.dart';
import '../widgets/active_sheet.dart';

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

  /// 這一晚的夢看過了沒（首頁的 DreamReadStore）。沒給＝當作沒看過，日記本會抖。
  final Future<bool> Function()? isDreamRead;

  /// 每晚睡了幾分鐘（首頁那一份打包檔的 history）。Time asleep 點開的一週長條圖用；沒給就不能點。
  final Future<List<NightValue>> Function()? loadSleepSeries;

  /// 每晚的上床／起床：按鈕（後端）與手錶（打包檔）各一份，日期 → (開始, 結束)。
  /// Time in bed 點開的一週圖用；沒給就不能點。
  final Future<
    ({
      Map<String, (DateTime?, DateTime?)> buttons,
      Map<String, (DateTime?, DateTime?)> watch,
    })
  >
  Function()?
  loadBedTimes;

  /// 每晚放下手機的時刻＋後端判的晚不晚（後端 /insights）。Phone down 點開的一週圖用；沒給就不能點。
  final Future<Map<String, PhoneDown>> Function()? loadPhoneDowns;

  /// 每晚清醒幾分鐘（後端 /insights）。Awake 點開的一週圖用；沒給、或連不到（null）就只看這一晚。
  final Future<Map<String, double>?> Function()? loadAwakeMinutes;

  /// 每晚進分數的效率＋種類＋名字（後端 /insights）。Efficiency 點開的一週用；沒給或連不到就只看這一晚。
  final Future<Map<String, EfficiencyNight>?> Function()? loadEfficiencyNights;

  /// 每晚睡著那一段的心率平均＋最低（後端 /insights）。Sleeping heart rate 點開的一週用；沒給或連不到就只看這一晚。
  final Future<Map<String, SleepHeartRate>?> Function()? loadSleepHeartRates;

  /// 每晚的攝影機資料（後端 /insights 的 camera.history）。Movement 點開的一週用；沒給或連不到就只看這一晚。
  final Future<List<CameraNight>?> Function()? loadCameraNights;

  const MorningReportScreen({
    super.key,
    required this.initial,
    this.load,
    this.loadSummary,
    this.pending = true,
    this.canOpenInsights = false,
    this.onDreamOpened,
    this.isDreamRead,
    this.loadSleepSeries,
    this.loadBedTimes,
    this.loadPhoneDowns,
    this.loadAwakeMinutes,
    this.loadEfficiencyNights,
    this.loadSleepHeartRates,
    this.loadCameraNights,
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

  /// 先當作看過（不抖），問到「還沒看過」才開始抖——免得看過的人一打開先抖一下。
  bool _dreamRead = true;

  @override
  void initState() {
    super.initState();
    final isRead = widget.isDreamRead;
    if (isRead == null) {
      _dreamRead = false;
    } else {
      isRead()
          .then((read) {
            if (mounted && !read) setState(() => _dreamRead = false);
          })
          .catchError((_) {});
    }
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
                  // 頂端日出背景（使用者生成的 dawn.png）：日期與分數區一起，跟著捲動
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Positioned(
                        left: -16,
                        right: -16,
                        top: -18,
                        bottom: 0,
                        child: ReportDawnBackdrop(),
                      ),
                      Column(
                        children: [
                          _header(r),
                          const SizedBox(height: 14),
                          _hero(r),
                          if (r.level != null) ...[
                            const SizedBox(height: 4),
                            _xp(r),
                          ],
                          if (_moodLine(r) != null) ...[
                            const SizedBox(height: 14),
                            _moodLine(r)!,
                          ],
                          const SizedBox(height: 8),
                        ],
                      ),
                    ],
                  ),
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

  // ── 半圓分數＋小狗（置中）＋自評小標籤＋日記本 ───────────────────────
  // 2026-11-14 使用者定（參考圖：主角在中間、上面一道弧）：分數只畫**一條半圓線**，
  // 不墊深色圓盤；小狗坐在弧底下的草坡上；左下 You felt、右下日記本；那句話在場景下面置中。

  static const double _sceneHeight = 262;
  static const double _arcRadius = 150;

  /// 半圓的圓心離場景底部多高（弧的兩端在這個高度）。
  static const double _arcBaseFromBottom = 80;

  Widget _hero(MorningReport r) {
    return SizedBox(
      height: _sceneHeight,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          const arcTop = _sceneHeight - _arcBaseFromBottom - _arcRadius;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // 半圓線
              Positioned(
                left: w / 2 - _arcRadius - 10,
                top: arcTop - 10,
                width: (_arcRadius + 10) * 2,
                height: _arcRadius + 20,
                child: CustomPaint(
                  key: Key(r.hasScore ? 'report-gauge' : 'report-waiting'),
                  painter: r.hasScore
                      ? _ArcPainter(value: (r.score! / 100).clamp(0.0, 1.0))
                      : const _DashedArcPainter(),
                ),
              ),
              // 弧裡面的字（小狗頭上）
              Positioned(
                left: w / 2 - _arcRadius + 24,
                width: (_arcRadius - 24) * 2,
                top: arcTop + 18,
                child: r.hasScore ? _scoreText(r) : _waitingText(),
              ),
              // 小狗坐在弧底下的草坡上：腳下一片淡影子
              Positioned(
                left: w / 2 - 44,
                bottom: 6,
                child: const _GroundShadow(width: 88),
              ),
              if (r.hasScore)
                Positioned(
                  left: w / 2 - 58,
                  bottom: 4,
                  child: HomePet(
                    key: const Key('report-pet-awake'),
                    mood: r.mood,
                    size: 116,
                  ),
                )
              else
                Positioned(
                  left: w / 2 - 65,
                  bottom: -4,
                  child: const SleepingPet(
                    key: Key('report-pet-asleep'),
                    size: 130,
                  ),
                ),
              // 左下：起床自評（臉＋字）
              if (r.rating != null)
                Positioned(
                  left: 0,
                  bottom: 4,
                  width: w / 2 - 54,
                  child: _ratingChip(r),
                ),
              // 右下：夢境日記（使用者生成）。點開看完整夢境；那一晚沒有夢就不出現。
              // 2026-11-14 取代頭邊小雲：雲裡的月亮星星＝正在睡，跟日出、醒著的小狗對不上。
              if (r.dream != null)
                Positioned(
                  key: const Key('report-dream'),
                  // 草坡往右邊斜下去，書要放低一點才在草地上
                  right: 6,
                  bottom: -30,
                  child: DreamBook(
                    unread: !_dreamRead,
                    onTap: () => _showDream(r),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// 小狗那句話（照抄後端 mood_description），放在經驗條下面置中。
  Widget? _moodLine(MorningReport r) {
    final mood = r.moodDescription;
    if (!r.hasScore || mood == null || mood.isEmpty) return null;
    return Text(
      mood,
      key: const Key('report-mood-line'),
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: ReportColors.soft,
        fontSize: 13,
        shadows: _onSky,
      ),
    );
  }

  static const _onSky = [Shadow(color: Color(0x99060A20), blurRadius: 14)];

  Widget _scoreText(MorningReport r) {
    final score = r.score!.round();
    final color = _hex(r.qualityColor) ?? ReportColors.accent;
    final line = [
      if (r.quality != null) r.quality!,
      if (r.scoreMessage != null && r.scoreMessage!.isNotEmpty) r.scoreMessage!,
    ].join(' · ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$score',
          key: const Key('report-score'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 58,
            fontWeight: FontWeight.w900,
            height: 1,
            shadows: _onSky,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Sleep score',
          style: TextStyle(
            color: ReportColors.soft,
            fontSize: 13,
            shadows: _onSky,
          ),
        ),
        if (line.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            line,
            key: const Key('report-quality'),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              shadows: _onSky,
            ),
          ),
        ],
      ],
    );
  }

  Widget _waitingText() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.watch_rounded, color: ReportColors.lilac, size: 26),
        const SizedBox(height: 6),
        Text(
          widget.pending ? kWaitingForWatch : kNoWatchData,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            height: 1.25,
            shadows: _onSky,
          ),
        ),
        if (widget.pending) ...[
          const SizedBox(height: 6),
          const Text(
            'Your score shows up here once your watch syncs.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ReportColors.soft,
              fontSize: 12,
              height: 1.35,
              shadows: _onSky,
            ),
          ),
        ],
      ],
    );
  }

  /// 起床自評：只放臉＋那個字（2026-11-14 使用者定：拿掉「You felt」、不要框，不突兀）。
  Widget _ratingChip(MorningReport r) {
    final rating = r.rating!;
    return Row(
      key: const Key('report-rating'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          restedFaceAsset(rating.rested),
          width: 22,
          height: 22,
          errorBuilder: (_, _, _) => const SizedBox(width: 22, height: 22),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            r.ratingLabel ?? rating.label,
            key: const Key('report-rating-label'),
            style: const TextStyle(
              color: ReportColors.soft,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              shadows: _onSky,
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
    // 2026-11-14 使用者定（參考圖）：不要卡片框，直接放在草坡上——
    // 大字 Lv.6 → 「Your experience」＋右邊這一晚的 +N XP → 經驗條（字寫在條裡）。
    return Column(
      key: const Key('report-xp'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Lv.${r.level}',
          key: const Key('report-level'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 34,
            fontWeight: FontWeight.w900,
            height: 1.1,
            shadows: _onSky,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Expanded(
              child: Text(
                'Your experience',
                style: TextStyle(
                  color: ReportColors.soft,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  shadows: _onSky,
                ),
              ),
            ),
            // 這一晚 +N（照抄 /game）；差的晚上照實寫 +0，不藏（紅線 5）
            if (night != null)
              Row(
                key: const Key('report-night-xp'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '+$night XP',
                    style: const TextStyle(
                      color: ReportColors.gold,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      shadows: _onSky,
                    ),
                  ),
                  if (r.nightXpSoFar)
                    const Text(
                      ' so far',
                      key: Key('report-night-xp-so-far'),
                      style: TextStyle(
                        color: ReportColors.gold,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 6),
        _XpBar(date: r.date, into: into, size: size, nights: r.recentNightXp),
        if (size != null) ...[
          const SizedBox(height: 4),
          Text(
            '${_n(size - into)} to Lv.${(r.level ?? 0) + 1}',
            key: const Key('report-xp-to-next'),
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: ReportColors.soft,
              fontSize: 11,
              shadows: _onSky,
            ),
          ),
        ],
      ],
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
  static const _cKcal = Color(0xFFFF8A6B);
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
      title: 'Total sleep',
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
      onTap: widget.loadSleepSeries == null ? null : () => _showSleepWeek(r),
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
      onTap: widget.loadBedTimes == null ? null : () => _showBedWeek(r),
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
        onTap: widget.loadPhoneDowns == null ? null : () => _showPhoneWeek(r),
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
        onTap: () => _showAwake(r),
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
        // 2026-11-15 使用者定：標題講清楚是睡著那一段（不是整天的心率）；格子窄，寫縮寫，點開才寫全名
        title: 'Sleeping HR',
        value: hrAvg == null ? null : '${hrAvg.round()} bpm',
        graphic: hrCurve == null
            ? null
            : paintBox(
                SparklinePainter(_curvePoints(hrCurve), _cHr),
                key: const Key('report-hr-line'),
              ),
        // 點開：這一晚依階段上色的線＋各階段平均＋一週（2026-11-15）
        onTap: hrCurve == null ? null : () => _showHeartRate(r),
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
        // 點開：片段（影片）＋動作線＋一週跟平常比（2026-11-15）
        onTap: () => _showMovement(r),
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
      // 2026-11-15 使用者定：照參考圖（Battery 卡）從底下往上填滿，填多高就是效率；
      // 數字在左下、% 小一號，下面一行是那一種的名字（後端照抄）
      effTile = ReportFillTile(
        key: const Key('report-efficiency-tile'),
        icon: Icons.speed_rounded,
        color: _cEff,
        title: 'Efficiency',
        // 照抄，不四捨五入掉小數（只把 100.0 寫成 100）
        value: effNumber(r.efficiency!),
        unit: '%',
        valueKey: const Key('report-efficiency'),
        fraction: r.efficiency! / 100,
        caption: r.efficiencyLabel,
        // 點開：這一晚怎麼算的（分子分母、哪一種）＋一週（依種類畫實心／空心）
        onTap: () => _showEfficiency(r),
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

    // 11-15 使用者定（照參考圖 Step Counter）：圓弧＝步數÷那天的目標，超過就滿圈、不變色不打勾。
    Widget? stepsTile;
    if (y.steps != null) {
      final stats = stepsStatsLine(y.distanceM, y.floorsUp);
      stepsTile = ReportTile(
        key: const Key('report-steps'),
        icon: Icons.directions_walk_rounded,
        color: _cSteps,
        title: 'Steps',
        graphic: StepsArc(
          key: const Key('report-steps-arc'),
          steps: y.steps!,
          fraction: stepsFraction(y.steps, y.stepGoal),
          color: _cSteps,
          valueKey: const Key('report-steps-value'),
        ),
        graphicHeight: 118,
        onTap: () => showStepsSheet(
          context,
          day: y,
          color: _cSteps,
          fontFamily: kReportFont,
        ),
        lines: [
          // 只寫 goal，不寫 reached（紅線 2）
          if (y.stepGoal != null)
            Center(child: Text('Goal ${_comma(y.stepGoal!)}')),
          if (stats != null) Center(child: Text(stats)),
        ],
      );
    }

    // 11-15 使用者定：活動卡路里拆出來自成一格（原本報告沒有）。只算動起來燒的，不是一整天的總消耗。
    Widget? kcalTile;
    if (y.activeKcal != null) {
      final hist = last7((h) => h.activeKcal);
      kcalTile = ReportTile(
        key: const Key('report-kcal'),
        icon: Icons.local_fire_department_rounded,
        color: _cKcal,
        title: 'Active kcal',
        value: _comma(y.activeKcal!),
        valueKey: const Key('report-kcal-value'),
        valueTrailing: const Text(
          'kcal',
          style: TextStyle(
            color: ReportColors.muted,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        graphic: hist.length < 2
            ? null
            : paintBox(
                MiniBarsPainter([for (final h in hist) h.$2], _cKcal),
                key: const Key('report-kcal-bars'),
              ),
        // 11-15 使用者定：點開是 Calories 頁（靜止＋活動的圓環、一週）
        onTap: () => showKcalSheet(
          context,
          day: y,
          color: _cKcal,
          fontFamily: kReportFont,
        ),
        lines: const [Text('active only, not total burn')],
      );
    }

    Widget? activeTile;
    if (y.hasActivity) {
      final active = y.activeMinutes;
      // 11-15 使用者定：一座山＝一整天，漸層每一段的面積＝那段的比例（active_sheet.dart）
      final parts = activeParts(y);
      activeTile = ReportTile(
        key: const Key('report-active'),
        icon: Icons.bolt_rounded,
        color: _cActive,
        title: 'Active time',
        value: active == null ? null : reportHm(active),
        valueKey: const Key('report-active-value'),
        graphic: parts != null
            ? ActivityMountain(
                key: const Key('report-active-mountain'),
                parts: parts,
              )
            : paintBox(
                StackedBarPainter([
                  ((y.highlyActiveSec ?? 0).toDouble(), _cActive),
                  (
                    (y.activeSec ?? 0).toDouble(),
                    _cActive.withValues(alpha: 0.55),
                  ),
                  (
                    (y.sedentarySec ?? 0).toDouble(),
                    Colors.white.withValues(alpha: 0.16),
                  ),
                ]),
                key: const Key('report-active-bar'),
              ),
        graphicHeight: parts != null ? 110 : 18,
        onTap: () => showActiveSheet(context, day: y, fontFamily: kReportFont),
        lines: [
          if (parts != null)
            Text(activeTileLine(parts))
          else
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
      // 11-15 使用者定的順序：7 格時最後一格（Move IQ 時間軸）佔整列
      stepsTile,
      kcalTile,
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

  /// Time in bed 點開：這一晚往回 7 晚幾點上床、幾點起床。按鈕優先、沒按退回手錶。
  /// 這一晚的按鈕以報告上的為準（剛按的可能還沒上傳）。
  Future<void> _showBedWeek(MorningReport r) async {
    var buttons = <String, (DateTime?, DateTime?)>{};
    var watch = <String, (DateTime?, DateTime?)>{};
    try {
      final t = await widget.loadBedTimes!();
      buttons = {...t.buttons};
      watch = {...t.watch};
    } catch (_) {}
    if (r.bedStart != null && r.bedEnd != null) {
      buttons[r.date] = (r.bedStart, r.bedEnd);
    }
    if (!mounted) return;
    await showBedWeekSheet(
      context,
      title: 'Time in bed',
      icon: Icons.bed_rounded,
      color: _cBed,
      fontFamily: kReportFont,
      week: bedWeek(endDate: r.date, buttons: buttons, watch: watch),
    );
  }

  /// Efficiency 點開。這一晚的數字、種類、名字、警語都以報告上的為準（同一支 scoredEfficiency 挑的）；
  /// 一週只有後端有，這一晚那根長條用報告上的數字蓋過去，保證跟格子一樣。
  Future<void> _showEfficiency(MorningReport r) async {
    Map<String, EfficiencyNight>? week;
    try {
      final m = await widget.loadEfficiencyNights?.call();
      if (m != null && m.isNotEmpty) {
        week = {
          ...m,
          if (r.efficiencyKind != null)
            r.date: EfficiencyNight(
              r.efficiency!,
              r.efficiencyKind!,
              r.efficiencyLabel,
            ),
        };
      }
    } catch (_) {}
    if (!mounted) return;
    await showEfficiencySheet(
      context,
      color: _cEff,
      fontFamily: kReportFont,
      date: r.date,
      value: r.efficiency!,
      label: r.efficiencyLabel,
      kind: r.efficiencyKind,
      // 11-15 使用者定：點開不放警語（上面「asleep of counted」已經說明怎麼算的）。警語仍在 Insights 分數卡
      asleepMinutes: r.sleepMinutes,
      span: countedSpan(
        r.efficiencyKind,
        bedStart: r.bedStart,
        bedEnd: r.bedEnd,
        asleepAt: r.asleepAt,
        wokeAt: r.wokeAt,
      ),
      week: week,
    );
  }

  /// Movement (camera) 點開。這一晚以報告上的那一晚為準；一週只有後端有。
  Future<void> _showMovement(MorningReport r) async {
    List<CameraNight>? week;
    try {
      final m = await widget.loadCameraNights?.call();
      if (m != null && m.isNotEmpty) {
        week = [
          for (final n in m)
            if (n.date != r.date) n,
          r.camera!,
        ];
      }
    } catch (_) {}
    if (!mounted) return;
    await showMovementSheet(
      context,
      color: _cCam,
      fontFamily: kReportFont,
      night: r.camera!,
      date: r.date,
      curve: r.cameraMotion,
      stages: r.stages,
      week: week,
    );
  }

  /// Sleeping heart rate 點開。這一晚的曲線、平均、最低以報告上的為準；
  /// 一週只有後端有，這一晚那一欄用報告的數字蓋過去，保證跟格子一樣。
  Future<void> _showHeartRate(MorningReport r) async {
    final curve = r.heartRate!;
    Map<String, SleepHeartRate>? week;
    try {
      final m = await widget.loadSleepHeartRates?.call();
      if (m != null && m.isNotEmpty) {
        week = {...m, r.date: SleepHeartRate(curve.avg, curve.min)};
      }
    } catch (_) {}
    if (!mounted) return;
    await showHeartRateSheet(
      context,
      color: _cHr,
      fontFamily: kReportFont,
      curve: curve,
      date: r.date,
      stages: r.stages,
      restingHeartRate: r.restingHeartRate,
      week: week,
    );
  }

  /// Awake 點開：這一晚什麼時候醒、醒多久＋一週。一週只有後端有；連不到就只看這一晚。
  /// 這一晚的總數以報告上的為準。
  Future<void> _showAwake(MorningReport r) async {
    List<NightValue>? series;
    try {
      final m = await widget.loadAwakeMinutes?.call();
      if (m != null && m.isNotEmpty) {
        series = [
          for (final e in m.entries)
            if (e.key != r.date) NightValue(e.key, e.value),
          NightValue(r.date, r.wasoMinutes!.toDouble()),
        ];
      }
    } catch (_) {}
    if (!mounted) return;
    await showAwakeSheet(
      context,
      title: 'Awake',
      icon: Icons.visibility_rounded,
      color: _cAwake,
      fontFamily: kReportFont,
      date: r.date,
      totalMinutes: r.wasoMinutes!.toDouble(),
      stages: r.stages,
      series: series,
    );
  }

  /// Phone down 點開：這一晚往回 7 晚幾點放下手機。這一晚的時刻以報告上的為準；
  /// 晚不晚只照抄後端（history 裡那一晚的 is_late），這一晚 history 沒有就不算進「N of M」。
  Future<void> _showPhoneWeek(MorningReport r) async {
    var downs = <String, PhoneDown>{};
    try {
      downs = {...await widget.loadPhoneDowns!()};
    } catch (_) {}
    final mine = r.lightsOutAt;
    if (mine != null) {
      downs[r.date] = PhoneDown(
        mine,
        downs[r.date]?.isLate,
        downs[r.date]?.inBedMinutes,
      );
    }
    if (!mounted) return;
    await showPhoneWeekSheet(
      context,
      title: 'Phone down',
      icon: Icons.phone_android_rounded,
      color: _cPhone,
      fontFamily: kReportFont,
      target: r.targetBedtime,
      week: phoneWeek(endDate: r.date, downs: downs),
    );
  }

  /// Time asleep 點開：這一晚往回 7 晚＋平均。這一晚的數字以報告上的為準（後端剛算好的可能比打包檔新）。
  Future<void> _showSleepWeek(MorningReport r) async {
    List<NightValue> series;
    try {
      series = await widget.loadSleepSeries!();
    } catch (_) {
      series = const [];
    }
    final mine = r.hasScore ? r.sleepMinutes : null;
    if (mine != null) {
      series = [
        for (final n in series)
          if (n.date != r.date) n,
        NightValue(r.date, mine.toDouble()),
      ];
    }
    if (!mounted) return;
    await showSleepWeekSheet(
      context,
      title: 'Total sleep',
      // 標題跟這張格子同一個圖示、同一個顏色（使用者定）
      icon: Icons.nightlight_round,
      color: _cAsleep,
      fontFamily: kReportFont,
      series: series,
      endDate: r.date,
      goalMinutes: r.goalMinutes,
    );
  }

  void _showDream(MorningReport r) {
    setState(() => _dreamRead = true);
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

/// 經驗條（2026-11-14 使用者定，參考圖）：沒有框，「215 / 400 XP」寫在條裡。
/// 條是**一種顏色**（白），最近幾晚之間一條細線分開（`xpBarSegments`，只排版不算 XP），
/// 只有這份報告那一晚是金色（跟上面的 +N XP 同色）。+0 的晚上沒有格子。
/// （第一版每晚換深淺、更早的另一色，使用者覺得顏色太多。）
class _XpBar extends StatelessWidget {
  final String date;
  final int into;
  final int? size;
  final List<NightXp> nights;

  const _XpBar({
    required this.date,
    required this.into,
    required this.size,
    required this.nights,
  });

  static const double _height = 22;
  static const _fill = Color(0xF2FFFFFF);
  static const _mine = ReportColors.gold;
  static const _ink = Color(0xFF1D2860);

  @override
  Widget build(BuildContext context) {
    final total = size;
    final segments = total == null
        ? const <XpSegment>[]
        : xpBarSegments(into: into, nights: nights);
    final text = total == null
        ? 'Max level'
        : '${_MorningReportScreenState._n(into)} / ${_MorningReportScreenState._n(total)} XP';
    final progress = total == null || total <= 0
        ? 1.0
        : (into / total).clamp(0.0, 1.0);
    return SizedBox(
      height: _height,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          double x(int v) =>
              total == null || total <= 0 ? 0 : (v / total).clamp(0.0, 1.0) * w;
          // 字放在條的左邊；進度太短時字落在空的那段，改用白字
          final onFill = progress * w > 120;
          return ClipRRect(
            borderRadius: BorderRadius.circular(_height / 2),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                if (total == null)
                  const Positioned.fill(child: ColoredBox(color: _fill)),
                for (final g in segments)
                  Positioned(
                    key: Key('xp-seg-${g.date ?? 'earlier'}'),
                    left: x(g.start),
                    top: 0,
                    bottom: 0,
                    width: x(g.end) - x(g.start),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: g.date == date ? _mine : _fill,
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        text,
                        key: const Key('report-xp-text'),
                        style: TextStyle(
                          color: onFill ? _ink : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 分數：一條半圓線（彩虹形，使用者定：只有線、不墊底盤）。
/// 淡色整條當底，上面從左端依分數畫一段漸層，弧長＝分數 / 100。
/// 畫布 = (2(R+10), R+20)，圓心在 (R+10, R+10)：留 10 給線寬與光暈。
class _ArcPainter extends CustomPainter {
  final double value;
  const _ArcPainter({required this.value});

  static const stroke = 12.0;
  static const colors = [
    Color(0xFF7FB2FF),
    Color(0xFFB9A6FF),
    Color(0xFFFF8AD8),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2 - 10;
    final center = Offset(size.width / 2, radius + 10);
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      rect,
      math.pi,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.16),
    );
    if (value <= 0) return;
    // 左→右的線性漸層：半圓不會繞回起點，可以用圓頭
    final shader = const LinearGradient(colors: colors).createShader(rect);
    final sweep = math.pi * value;
    canvas.drawArc(
      rect,
      math.pi,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + 6
        ..strokeCap = StrokeCap.round
        ..shader = shader
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
        ..color = Colors.white.withValues(alpha: 0.5),
    );
    canvas.drawArc(
      rect,
      math.pi,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.value != value;
}

/// 等待中：虛線半圓（同一道弧，沒有分數）。
class _DashedArcPainter extends CustomPainter {
  const _DashedArcPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2 - 10;
    final center = Offset(size.width / 2, radius + 10);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x8CB9A6FF);
    const dash = 6.0;
    const gap = 9.0;
    final count = (math.pi * radius / (dash + gap)).floor();
    final step = math.pi / count;
    final sweep = step * dash / (dash + gap);
    final rect = Rect.fromCircle(center: center, radius: radius);
    for (var i = 0; i < count; i++) {
      canvas.drawArc(rect, math.pi + i * step, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedArcPainter old) => false;
}

/// 頂端背景：使用者為這個位置生成的日出山丘（右下草坡給小狗坐），上下兩端淡進報告的深藍。
/// 讀不到圖時退回程式畫的山丘。
const String kReportDawnAsset = 'assets/backgrounds/report_dawn.jpg';

class ReportDawnBackdrop extends StatelessWidget {
  const ReportDawnBackdrop({super.key});

  static const _hill = Align(
    alignment: Alignment.bottomCenter,
    child: SizedBox(
      height: 120,
      width: double.infinity,
      child: CustomPaint(painter: _HillPainter()),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // 下緣讓整張圖淡成透明、露出底下報告的漸層：直接淡成某個顏色的話，
    // 跟背景在那個高度的顏色對不上，會多一條分界線（實機看到過）。
    return IgnorePointer(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0, 0.8, 1],
        ).createShader(rect),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              kReportDawnAsset,
              key: const Key('report-dawn'),
              fit: BoxFit.cover,
              // 不貼底：往下挪，太陽才從分數圓環下面露出來、草坡落在小狗腳下
              alignment: const Alignment(0, 0.6),
              errorBuilder: (_, _, _) => _hill,
            ),
            // 壓一層深藍，白字與圓環才看得清楚；上緣接狀態列、下緣接格子
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    ReportColors.bgTop,
                    Color(0x590B1636),
                    Color(0x140B1636),
                    Color(0x260B1636),
                  ],
                  stops: [0, 0.18, 0.5, 1],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 角色腳下的淡影子（橢圓、邊緣模糊）。
class _GroundShadow extends StatelessWidget {
  final double width;
  const _GroundShadow({required this.width});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: width,
        height: width * 0.16,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.all(
            Radius.elliptical(width / 2, width * 0.08),
          ),
          color: const Color(0x40060A20),
          boxShadow: const [
            BoxShadow(color: Color(0x40060A20), blurRadius: 8, spreadRadius: 2),
          ],
        ),
      ),
    );
  }
}

/// 小狗坐的山丘（示意圖的曲線，依寬度縮放）。讀不到日出圖時用。
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
