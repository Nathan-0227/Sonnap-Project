import 'dart:async';

import 'package:flutter/material.dart';

import '../services/journey_service.dart';
import '../services/pet_choice.dart';
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

/// 寵物在路上走的頭（使用者生成，2026-11-19）。**不是心情臉**：狗頭表情在 App 裡固定代表
/// 後端判的心情（一週心情列），這裡要的是側面走路、沒有明顯情緒的樣子。缺圖退回 🐾。
String journeyHeadAsset(PetSpecies s) => s == PetSpecies.cat
    ? 'assets/plan/journey_cat.png'
    : 'assets/plan/journey_dog.png';

/// 作息＋Journey 合成一張卡（11-19 使用者定：作息條本來就寫今晚幾點，路直接畫在它下面）。
///
///   🌙 03:00   ☀ 10:00               7h ›     ← 點了開轉盤（Journey 進行中是鎖住的）
///   ─────────────────────────────────────
///   進行中：Stop 2 of 5                    ⋯
///          🌅 ━━━ 🐶 ┄┄ • ┄┄ • ┄┄ 🏁       ← 點一個點看那一站幾點起床
///                 ☀ ☀ ○                    ← 連續幾天準時
///   沒有：  🚩 Start a journey               ›
class JourneySection extends StatelessWidget {
  final JourneyController controller;

  /// 按 Start a journey（開設定面板）。
  final VoidCallback onStart;

  /// 作息（進行中時就是這一站）。點上半部開轉盤。
  final TimeOfDay bedtime;
  final TimeOfDay? wake;
  final VoidCallback onEditSchedule;

  const JourneySection({
    super.key,
    required this.controller,
    required this.onStart,
    required this.bedtime,
    required this.wake,
    required this.onEditSchedule,
  });

  @override
  Widget build(BuildContext context) {
    final info = controller.info;
    final j = info?.journey;
    return Material(
      key: const Key('journey-section'),
      color: const Color(0xF2262C66),
      elevation: 6,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: ReportColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _schedule(),
          const Divider(height: 1, thickness: 1, color: ReportColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 6, 10),
            child: j != null && j.active ? _active(context, j) : _idle(j, info),
          ),
        ],
      ),
    );
  }

  Widget _schedule() {
    final w = wake;
    final span = w == null ? null : sleepSpan(bedtime, w);
    Widget part(IconData icon, Color color, String value, Key key) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 6),
        Text(
          value,
          key: key,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
    return InkWell(
      key: const Key('journey-schedule'),
      onTap: onEditSchedule,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
        child: Row(
          children: [
            part(
              Icons.bedtime_rounded,
              ReportColors.gold,
              hhmm(bedtime),
              const Key('plan-bedtime'),
            ),
            const SizedBox(width: 16),
            part(
              Icons.wb_sunny_rounded,
              ReportColors.gold,
              w == null ? '—' : hhmm(w),
              const Key('plan-wake'),
            ),
            const Spacer(),
            // 只寫事實：幾小時。不判斷夠不夠。
            if (span != null)
              Text(
                reportHm(span.inMinutes),
                style: const TextStyle(
                  color: ReportColors.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            const Icon(Icons.chevron_right_rounded, color: ReportColors.accent),
          ],
        ),
      ),
    );
  }

  Widget _idle(JourneyState? j, JourneyInfo? info) {
    final noBackend = controller.api == null;
    const small = TextStyle(
      color: ReportColors.dim,
      fontSize: 13,
      fontWeight: FontWeight.w700,
    );
    if (noBackend) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Text(
          'Journey needs the backend',
          key: Key('journey-no-backend'),
          style: small,
        ),
      );
    }
    // 有後端但還沒問到（連不上）：照實說，不要只是一顆灰掉的按鈕
    if (info == null) {
      return Row(
        children: [
          const Expanded(
            child: Text(
              "Can't reach the backend right now",
              key: Key('journey-unreachable'),
              style: small,
            ),
          ),
          TextButton(
            key: const Key('journey-retry'),
            onPressed: () => unawaited(controller.refresh()),
            child: const Text('Try again'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (j != null &&
            j.status == JourneyStatus.done &&
            controller.showNotice)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Text(
              journeyNoticeText(j),
              key: const Key('journey-notice'),
              style: const TextStyle(
                color: ReportColors.gold,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        InkWell(
          key: const Key('journey-start'),
          onTap: onStart,
          borderRadius: BorderRadius.circular(14),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(Icons.flag_rounded, color: ReportColors.gold, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Start a journey',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: ReportColors.accent),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _active(BuildContext context, JourneyState j) {
    final n = j.stops.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.route_rounded,
              size: 16,
              color: ReportColors.faint,
            ),
            const SizedBox(width: 6),
            Text(
              'Stop ${j.stopIndex + 1} of $n',
              key: const Key('journey-title'),
              style: const TextStyle(
                color: ReportColors.soft,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (controller.showNotice) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: ReportColors.gold.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'New stop',
                  key: Key('journey-notice'),
                  style: TextStyle(
                    color: ReportColors.gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
            const Spacer(),
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
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: JourneyRoad(
            journey: j,
            // 剛前進、還沒看過：🐾 從上一站走過來（一次）
            walkFromPrevious: controller.showNotice && j.stopIndex > 0,
          ),
        ),
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
            'Tap a dot on the road to see its wake time. '
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

/// 一條路（照使用者給的參考圖）：左邊 🌅 起點、寵物＝這一站、右邊 🏁 終點。
/// 走過的實線、還沒走的虛線，每一站一個小點；**點一個點（含兩端）在上面冒出那一站的起床時間**，
/// 再點一次或點別處收起來。位置只照抄 stop_index 與 stops 的個數。
///
/// [walkFromPrevious]：剛前進一站時，寵物從上一站沿著路走過來（一次，約 1.2 秒）；
/// 系統開「減少動態效果」時直接在這一站、不走。
class JourneyRoad extends StatefulWidget {
  final JourneyState journey;
  final bool walkFromPrevious;
  const JourneyRoad({
    super.key,
    required this.journey,
    this.walkFromPrevious = false,
  });

  @override
  State<JourneyRoad> createState() => _JourneyRoadState();
}

class _JourneyRoadState extends State<JourneyRoad>
    with SingleTickerProviderStateMixin {
  static const double _end = 30; // 兩端圓的直徑
  static const double _marker = 40;
  static const double _height = 46;

  late final AnimationController _walk = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  int? _selected; // -1＝起點，0..n-1＝第幾站
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.walkFromPrevious && !MediaQuery.disableAnimationsOf(context)) {
      _walk.forward(from: 0);
    } else {
      _walk.value = 1;
    }
  }

  @override
  void dispose() {
    _walk.dispose();
    super.dispose();
  }

  TimeOfDay _wakeAt(int i) =>
      i < 0 ? widget.journey.startWake : widget.journey.stops[i].wake;

  @override
  Widget build(BuildContext context) {
    final j = widget.journey;
    final n = j.stops.length;
    double frac(int i) => n == 0 ? 0 : (i + 1) / n; // 起點 i=-1 → 0；最後一站 → 1
    return SizedBox(
      height: _height,
      child: LayoutBuilder(
        builder: (context, box) {
          final left = _end / 2, right = box.maxWidth - _end / 2;
          double x(int i) => left + (right - left) * frac(i);
          final cy = _height / 2;

          void tapAt(Offset p) {
            int? best;
            var bestD = 22.0;
            for (var i = -1; i < n; i++) {
              final d = (p.dx - x(i)).abs();
              if (d < bestD) {
                bestD = d;
                best = i;
              }
            }
            setState(
              () =>
                  _selected = (best == null || best == _selected) ? null : best,
            );
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => tapAt(d.localPosition),
            child: AnimatedBuilder(
              animation: _walk,
              builder: (context, _) {
                final t = Curves.easeInOut.transform(_walk.value);
                final from = widget.walkFromPrevious
                    ? x(j.stopIndex - 1)
                    : x(j.stopIndex);
                final hereX = from + (x(j.stopIndex) - from) * t;
                // 走的時候上下輕輕晃（像在走路），停下來就不晃
                final bob = _walk.isAnimating
                    ? (1 - (2 * ((t * 6) % 1) - 1).abs()) * 4
                    : 0.0;
                final atGoal = j.stopIndex >= n - 1 && !_walk.isAnimating;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _RoadPainter(
                          from: left,
                          to: right,
                          here: hereX,
                          dots: [
                            for (var i = j.stopIndex + 1; i < n - 1; i++) x(i),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: cy - _end / 2,
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
                        top: cy - _end / 2,
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
                      key: const Key('journey-here'),
                      left: hereX - _marker / 2,
                      top: cy - _marker / 2 - bob,
                      child: const _PetHead(size: _marker),
                    ),
                    if (_selected != null)
                      Positioned(
                        left: x(_selected!) - 30,
                        width: 60,
                        top: -30,
                        child: IgnorePointer(
                          child: Center(
                            child: Container(
                              key: const Key('journey-bubble'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black38,
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: Text(
                                hhmm(_wakeAt(_selected!)),
                                key: const Key('journey-bubble-text'),
                                style: const TextStyle(
                                  color: ReportColors.navy,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
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
    Key key,
  ) => Container(
    key: key,
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: fill,
      border: Border.all(color: border, width: 2),
    ),
    child: Center(child: child),
  );
}

/// 自己選的寵物（小狗／貓）的頭；缺圖時是金色圓圈＋🐾。
class _PetHead extends StatelessWidget {
  final double size;
  const _PetHead({required this.size});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<PetSpecies>(
    valueListenable: PetChoice.current,
    builder: (context, species, _) => SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        journeyHeadAsset(species),
        key: Key('journey-head-${species.name}'),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ReportColors.gold,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(color: Color(0x88FFD772), blurRadius: 12),
            ],
          ),
          child: const Icon(
            Icons.pets_rounded,
            size: 20,
            color: ReportColors.navy,
          ),
        ),
      ),
    ),
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
      if (d > here + 6) canvas.drawCircle(Offset(d, y), 4, dot);
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
