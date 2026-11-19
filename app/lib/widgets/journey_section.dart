import 'dart:async';

import 'package:flutter/material.dart';

import '../services/journey_service.dart';
import '../theme/report_style.dart';
import 'report_sheet.dart';
import 'sleep_dial.dart' show SleepDial, hhmm, sleepSpan;

/// 睡眠計畫頁作息條底下的 Journey（2026-11-19 使用者 grill 定，Q1–Q18）。
///
/// ⚠️ 這裡**不算任何東西**：幾站、每站幾點、連續幾天、能不能前進、終點是不是比起點早，
///    都照抄後端（behavior/journey.py）。數字（30 分、3 天、7 小時）也從後端拿。
/// ⚠️ 只寫時間，不寫「你的生理時鐘提前了」（Sletten 2018：放下手機變早不等於時鐘移了）。
/// ⚠️ 不給 XP、不慶祝（Q15）。

/// 前進一站／走完的那一行（計畫頁與首頁小卡同一句）。
String journeyNoticeText(JourneyState j) => j.status == JourneyStatus.done
    ? 'You reached your goal schedule'
    : 'Next stop from tonight: bed ${hhmm(j.current!.bedtime)} · up ${hhmm(j.current!.wake)}';

class JourneySection extends StatelessWidget {
  final JourneyController controller;

  /// 按 Start a journey（開設定面板）。
  final VoidCallback onStart;

  const JourneySection({
    super.key,
    required this.controller,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final info = controller.info;
    final j = info?.journey;
    final noBackend = controller.api == null;
    return Container(
      key: const Key('journey-section'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xF2262C66),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ReportColors.border),
      ),
      child: j != null && j.active
          ? _active(context, j, info!)
          : _idle(context, j, info, noBackend),
    );
  }

  Widget _title(String text, {Widget? trailing}) => Row(
    children: [
      const Icon(Icons.route_rounded, color: ReportColors.gold, size: 20),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      ?trailing,
    ],
  );

  Widget _notice(JourneyState j) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      journeyNoticeText(j),
      key: const Key('journey-notice'),
      style: const TextStyle(
        color: ReportColors.gold,
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _idle(
    BuildContext context,
    JourneyState? j,
    JourneyInfo? info,
    bool noBackend,
  ) {
    final step = info?.stepMinutes ?? 30;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Journey'),
        if (j != null &&
            j.status == JourneyStatus.done &&
            controller.showNotice)
          _notice(j),
        const SizedBox(height: 6),
        Text(
          'Move your wake time earlier, $step minutes at a time. '
          'Your bedtime moves with it.',
          style: const TextStyle(
            color: ReportColors.muted,
            fontSize: 13,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        if (noBackend)
          const Text(
            'Needs the backend',
            key: Key('journey-no-backend'),
            style: TextStyle(
              color: ReportColors.dim,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          )
        // 有後端但還沒問到（連不上）：照實說，不要只是一顆灰掉的按鈕（11-19 實機：看不出為什麼按不了）
        else if (info == null)
          Row(
            children: [
              const Expanded(
                child: Text(
                  "Can't reach the backend right now",
                  key: Key('journey-unreachable'),
                  style: TextStyle(
                    color: ReportColors.dim,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                key: const Key('journey-retry'),
                onPressed: () => unawaited(controller.refresh()),
                child: const Text('Try again'),
              ),
            ],
          )
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('journey-start'),
              onPressed: onStart,
              icon: const Icon(Icons.flag_rounded, size: 18),
              label: const Text(
                'Start a journey',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: ReportColors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: const StadiumBorder(),
              ),
            ),
          ),
      ],
    );
  }

  /// 進行中（11-19 使用者給參考圖改版：一條路、少字）：
  ///   上：第幾站 ……… 今晚 🌙 就寢 ☀ 起床  ⋯
  ///   中：起點 ━━ 🐾 ┄┄•┄┄• 🏁（走過實線、還沒到虛線＋小點）
  ///   下：三顆太陽＝連續幾天準時（亮的是做到的）
  /// 說明與 Stop 收進 ⋯。
  Widget _active(BuildContext context, JourneyState j, JourneyInfo info) {
    final n = j.stops.length;
    final cur = j.current!;
    Widget time(IconData icon, Color color, TimeOfDay t, Key key) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 3),
        Text(
          hhmm(t),
          key: key,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controller.showNotice)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: ReportColors.gold.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'New stop from tonight',
                key: Key('journey-notice'),
                style: TextStyle(
                  color: ReportColors.gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        Row(
          children: [
            Text(
              'Stop ${j.stopIndex + 1} of $n',
              key: const Key('journey-title'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Spacer(),
            time(
              Icons.bedtime_rounded,
              ReportColors.lilac,
              cur.bedtime,
              const Key('journey-current-bed'),
            ),
            const SizedBox(width: 10),
            time(
              Icons.wb_sunny_rounded,
              ReportColors.gold,
              cur.wake,
              const Key('journey-current-wake'),
            ),
            PopupMenuButton<String>(
              key: const Key('journey-menu'),
              icon: const Icon(
                Icons.more_horiz_rounded,
                color: ReportColors.faint,
              ),
              color: ReportColors.sheet,
              padding: EdgeInsets.zero,
              onSelected: (v) {
                if (v == 'how') unawaited(_howItWorks(context, j));
                if (v == 'stop') unawaited(_confirmStop(context));
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'how',
                  key: Key('journey-how'),
                  child: Text(
                    'How it works',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                PopupMenuItem(
                  value: 'stop',
                  key: Key('journey-stop'),
                  child: Text(
                    'Stop journey',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        _JourneyRoad(journey: j),
        const SizedBox(height: 8),
        Center(
          child: Semantics(
            label: '${j.onTimeStreak} of ${j.onTimeNeeded} on-time mornings',
            child: Row(
              key: const Key('journey-streak'),
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                j.onTimeNeeded,
                (i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Icon(
                    i < j.onTimeStreak
                        ? Icons.wb_sunny_rounded
                        : Icons.wb_sunny_outlined,
                    key: Key(
                      'journey-sun-$i-${i < j.onTimeStreak ? 'on' : 'off'}',
                    ),
                    size: 20,
                    color: i < j.onTimeStreak
                        ? ReportColors.gold
                        : ReportColors.dim,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 卡片上拿掉的那段說明（使用者要少字），收進 ⋯ → How it works。
  Future<void> _howItWorks(BuildContext context, JourneyState j) =>
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ReportColors.sheet,
          title: const Text(
            'How it works',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'Get up within an hour of ${hhmm(j.current!.wake)} for '
            '${j.onTimeNeeded} mornings in a row and the next stop starts. '
            'A missed morning starts the count again. '
            'Your goal: up at ${hhmm(j.endWake)}.',
            key: const Key('journey-how-text'),
            style: const TextStyle(color: ReportColors.muted, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );

  Future<void> _confirmStop(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ReportColors.sheet,
        title: const Text(
          'Stop this journey?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Your schedule stays at this stop. You can start a new journey any time.',
          style: TextStyle(color: ReportColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep going'),
          ),
          TextButton(
            key: const Key('journey-stop-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final done = await controller.stop();
    if (!done && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't reach the backend. Try again later."),
        ),
      );
    }
  }
}

/// 一條路（照使用者給的參考圖）：左邊起點、🐾＝這一站、右邊 🏁＝終點。
/// 走過的那段實線，還沒走的虛線，中間每一站一個小點。位置只照抄 stop_index／stops 的個數。
class _JourneyRoad extends StatelessWidget {
  final JourneyState journey;
  const _JourneyRoad({required this.journey});

  static const double _end = 30; // 兩端圓的直徑
  static const double _marker = 36;

  @override
  Widget build(BuildContext context) {
    final j = journey;
    final n = j.stops.length;
    // 起點在 0、第 i 站在 (i+1)/n、最後一站＝終點在 1
    final here = n == 0 ? 0.0 : (j.stopIndex + 1) / n;
    final atGoal = j.stopIndex >= n - 1;
    return SizedBox(
      height: _marker + 4,
      child: LayoutBuilder(
        builder: (context, box) {
          final left = _end / 2, right = box.maxWidth - _end / 2;
          double x(double f) => left + (right - left) * f;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _RoadPainter(
                    from: left,
                    to: right,
                    here: x(here),
                    dots: [
                      for (var i = j.stopIndex + 1; i < n - 1; i++)
                        x((i + 1) / n),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: (_marker + 4 - _end) / 2,
                child: _circle(
                  _end,
                  ReportColors.lilac.withValues(alpha: 0.25),
                  ReportColors.lilac,
                  const Icon(
                    Icons.wb_twilight_rounded,
                    size: 16,
                    color: ReportColors.lilac,
                  ),
                  const Key('journey-road-start'),
                ),
              ),
              if (!atGoal)
                Positioned(
                  left: right - _end / 2,
                  top: (_marker + 4 - _end) / 2,
                  child: _circle(
                    _end,
                    ReportColors.gold.withValues(alpha: 0.18),
                    ReportColors.gold,
                    const Icon(
                      Icons.flag_rounded,
                      size: 16,
                      color: ReportColors.gold,
                    ),
                    const Key('journey-goal'),
                  ),
                ),
              Positioned(
                left: x(here) - _marker / 2,
                top: 2,
                child: _circle(
                  _marker,
                  ReportColors.gold,
                  Colors.white,
                  const Icon(
                    Icons.pets_rounded,
                    size: 20,
                    color: ReportColors.navy,
                  ),
                  const Key('journey-here'),
                  glow: true,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _circle(
    double size,
    Color fill,
    Color border,
    Widget child,
    Key key, {
    bool glow = false,
  }) => Container(
    key: key,
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: fill,
      border: Border.all(color: border, width: 2),
      boxShadow: glow
          ? const [BoxShadow(color: Color(0x88FFD772), blurRadius: 12)]
          : null,
    ),
    child: Center(child: child),
  );
}

class _RoadPainter extends CustomPainter {
  final double from, to, here;
  final List<double> dots;
  _RoadPainter({
    required this.from,
    required this.to,
    required this.here,
    required this.dots,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final done = Paint()
      ..color = ReportColors.lilac
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(from, y), Offset(here, y), done);
    final todo = Paint()
      ..color = const Color(0x55FFFFFF)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var x = here + 8; x < to; x += 10) {
      canvas.drawLine(Offset(x, y), Offset((x + 4).clamp(x, to), y), todo);
    }
    final dot = Paint()..color = const Color(0xCCFFFFFF);
    for (final d in dots) {
      canvas.drawCircle(Offset(d, y), 4, dot);
    }
  }

  @override
  bool shouldRepaint(_RoadPainter old) =>
      old.here != here ||
      old.from != from ||
      old.to != to ||
      old.dots.length != dots.length;
}

// ── 開始一段 Journey 的面板 ─────────────────────────────────────────────

/// 回傳 true＝開始了。起點預設是後端的建議（最近 7 晚中間值），沒有就用轉盤上的起床。
/// 終點由使用者自己選（文獻不給時刻，Q10）。睡眠長度預設轉盤上的，最少 7 小時。
Future<bool> showJourneySetupSheet(
  BuildContext context, {
  required JourneyController controller,
  required TimeOfDay dialBedtime,
  required TimeOfDay dialWake,
}) async {
  final info = controller.info ?? const JourneyInfo();
  final r = await showReportSheet<bool>(
    context: context,
    builder: (_) => _JourneySetup(
      controller: controller,
      info: info,
      dialBedtime: dialBedtime,
      dialWake: dialWake,
    ),
  );
  return r ?? false;
}

class _JourneySetup extends StatefulWidget {
  final JourneyController controller;
  final JourneyInfo info;
  final TimeOfDay dialBedtime;
  final TimeOfDay dialWake;
  const _JourneySetup({
    required this.controller,
    required this.info,
    required this.dialBedtime,
    required this.dialWake,
  });

  @override
  State<_JourneySetup> createState() => _JourneySetupState();
}

class _JourneySetupState extends State<_JourneySetup> {
  late TimeOfDay _start = widget.info.suggestedStart ?? widget.dialWake;
  late int _sleep = _initialSleep();

  /// 目標（轉盤上的太陽）。一開始放在起點上，**拖過才算選了**——
  /// 終點要使用者自己訂（Q10），而「比起點早」由後端判（Dart 不算跨午夜）。
  late TimeOfDay _goalWake = _start;
  bool _goalPicked = false;
  bool _busy = false;
  String? _error;

  int _initialSleep() {
    // 預設＝轉盤上現在睡多久；不設下限（使用者 11-19：每個人需要的不一樣）
    return sleepSpan(widget.dialBedtime, widget.dialWake).inMinutes;
  }

  /// 只是畫面上的預覽（就寢＝起床 − 睡多久、起點 ±5 分）；真正的每一站由後端排。
  static TimeOfDay _shift(TimeOfDay t, int minutes) => TimeOfDay.fromDateTime(
    DateTime(2000, 1, 1, t.hour, t.minute).add(Duration(minutes: minutes)),
  );

  TimeOfDay get _goalBed => _shift(_goalWake, -_sleep);

  /// 拖太陽：目標起床換了，就寢跟著（睡眠長度不變）。
  void _onWake(TimeOfDay t) => setState(() {
    _goalWake = t;
    _goalPicked = true;
    _error = null;
  });

  /// 拖月亮：改的是睡多久，拖到哪就是哪（不設下限）。
  void _onBed(TimeOfDay t) {
    final len = sleepSpan(t, _goalWake).inMinutes;
    setState(() {
      _sleep = len;
      _error = null;
    });
  }

  void _nudgeStart(int minutes) => setState(() {
    final wasOnStart = !_goalPicked;
    _start = _shift(_start, minutes);
    if (wasOnStart) _goalWake = _start; // 還沒選目標時，太陽跟著起點
    _error = null;
  });

  Future<void> _go() async {
    if (!_goalPicked) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final out = await widget.controller.start(
      startWake: _start,
      endWake: _goalWake,
      sleepMinutes: _sleep,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (out) {
      case JourneyStartOutcome.started:
        Navigator.of(context).pop(true);
      case JourneyStartOutcome.alreadyThere:
        setState(
          () => _error = "You're already there — just change your schedule.",
        );
      case JourneyStartOutcome.failed:
        setState(() => _error = "Couldn't reach the backend. Try again later.");
    }
  }

  String _hm(int minutes) => minutes % 60 == 0
      ? '${minutes ~/ 60}h'
      : '${minutes ~/ 60}h ${minutes % 60}m';

  Widget _nudge(Key key, IconData icon, VoidCallback onTap) => IconButton(
    key: key,
    onPressed: onTap,
    icon: Icon(icon),
    color: ReportColors.accent,
    visualDensity: VisualDensity.compact,
  );

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    // 不透明的底（同加習慣那一頁）：showReportSheet 本身是透明的。
    // ⚠️ 不包捲動：轉盤是用拖的，外面有捲動的話上下拖會被捲動吃掉。
    return Container(
      key: const Key('journey-setup'),
      decoration: const BoxDecoration(
        color: ReportColors.sheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Start a journey',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Your wake time moves ${info.stepMinutes} minutes earlier at each stop. '
                'Bedtime follows, so you keep the same sleep length.',
                style: const TextStyle(
                  color: ReportColors.muted,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              // 現在幾點起：照最近 7 晚抓的，通常只要微調 → ±5 分鐘
              Container(
                padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'You wake up now',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            info.suggestedStart != null
                                ? 'Middle of your last 7 nights'
                                : 'From your schedule',
                            style: const TextStyle(
                              color: ReportColors.faint,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _nudge(
                      const Key('journey-setup-start-less'),
                      Icons.remove_circle_outline_rounded,
                      () => _nudgeStart(-5),
                    ),
                    Text(
                      hhmm(_start),
                      key: const Key('journey-setup-start'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    _nudge(
                      const Key('journey-setup-start-more'),
                      Icons.add_circle_outline_rounded,
                      () => _nudgeStart(5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'YOUR GOAL',
                style: TextStyle(
                  color: ReportColors.faint,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _goalPicked
                    ? 'Drag the moon to change how long you sleep'
                    : 'Drag the sun to your goal wake time',
                key: const Key('journey-setup-hint'),
                style: const TextStyle(color: ReportColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Center(
                child: SleepDial(
                  key: const Key('journey-setup-dial'),
                  bedtime: _goalBed,
                  wake: _goalWake,
                  onBedtimeChanged: _onBed,
                  onWakeChanged: _onWake,
                  size: 240,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.bedtime_rounded,
                    size: 18,
                    color: ReportColors.lilac,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    hhmm(_goalBed),
                    key: const Key('journey-setup-goal-bed'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 18),
                  const Icon(
                    Icons.wb_sunny_rounded,
                    size: 18,
                    color: ReportColors.gold,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    hhmm(_goalWake),
                    key: const Key('journey-setup-goal-wake'),
                    style: const TextStyle(
                      color: ReportColors.gold,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  '${_hm(_sleep)} of sleep · ${_hm(info.recommendedSleepMinutes)} or more is recommended',
                  key: const Key('journey-setup-min-note'),
                  // 只寫事實＋參考，不變色、不判斷夠不夠
                  style: const TextStyle(
                    color: ReportColors.faint,
                    fontSize: 12,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  key: const Key('journey-setup-error'),
                  style: const TextStyle(
                    color: ReportColors.gold,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('journey-setup-go'),
                  onPressed: !_goalPicked || _busy
                      ? null
                      : () => unawaited(_go()),
                  style: FilledButton.styleFrom(
                    backgroundColor: ReportColors.purple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    _busy ? 'Starting…' : 'Start journey',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
