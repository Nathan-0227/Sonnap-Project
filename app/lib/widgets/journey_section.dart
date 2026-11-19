import 'dart:async';

import 'package:flutter/material.dart';

import '../services/journey_service.dart';
import '../theme/report_style.dart';
import 'report_sheet.dart';
import 'sleep_dial.dart' show hhmm, sleepSpan;

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

  const JourneySection({super.key, required this.controller, required this.onStart});

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
            child: Text(text,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
          ),
          ?trailing,
        ],
      );

  Widget _notice(JourneyState j) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(journeyNoticeText(j),
            key: const Key('journey-notice'),
            style: const TextStyle(color: ReportColors.gold, fontSize: 14, fontWeight: FontWeight.w800)),
      );

  Widget _idle(BuildContext context, JourneyState? j, JourneyInfo? info, bool noBackend) {
    final step = info?.stepMinutes ?? 30;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Journey'),
        if (j != null && j.status == JourneyStatus.done && controller.showNotice) _notice(j),
        const SizedBox(height: 6),
        Text('Move your wake time earlier, $step minutes at a time. '
            'Your bedtime moves with it.',
            style: const TextStyle(color: ReportColors.muted, fontSize: 13, height: 1.35)),
        const SizedBox(height: 10),
        if (noBackend)
          const Text('Needs the backend',
              key: Key('journey-no-backend'),
              style: TextStyle(color: ReportColors.dim, fontSize: 13, fontWeight: FontWeight.w700))
        // 有後端但還沒問到（連不上）：照實說，不要只是一顆灰掉的按鈕（11-19 實機：看不出為什麼按不了）
        else if (info == null)
          Row(
            children: [
              const Expanded(
                child: Text("Can't reach the backend right now",
                    key: Key('journey-unreachable'),
                    style: TextStyle(color: ReportColors.dim, fontSize: 13, fontWeight: FontWeight.w700)),
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
              label: const Text('Start a journey', style: TextStyle(fontWeight: FontWeight.w800)),
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

  Widget _active(BuildContext context, JourneyState j, JourneyInfo info) {
    final n = j.stops.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Journey · stop ${j.stopIndex + 1} of $n',
            trailing: TextButton(
              key: const Key('journey-stop'),
              onPressed: () => unawaited(_confirmStop(context)),
              style: TextButton.styleFrom(foregroundColor: ReportColors.faint),
              child: const Text('Stop journey'),
            )),
        if (controller.showNotice) _notice(j),
        const SizedBox(height: 12),
        _JourneyPath(journey: j),
        const SizedBox(height: 10),
        Row(
          children: [
            ...List.generate(
              j.onTimeNeeded,
              (i) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  i < j.onTimeStreak ? Icons.wb_sunny_rounded : Icons.circle_outlined,
                  size: 16,
                  color: i < j.onTimeStreak ? ReportColors.gold : ReportColors.dim,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text('${j.onTimeStreak} of ${j.onTimeNeeded} on-time mornings',
                  key: const Key('journey-streak'),
                  style: const TextStyle(color: ReportColors.soft, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Up within an hour of ${hhmm(j.current!.wake)}, ${j.onTimeNeeded} mornings in a row, '
          'and the next stop starts. A missed morning starts the count again.',
          style: const TextStyle(color: ReportColors.faint, fontSize: 12, height: 1.35),
        ),
      ],
    );
  }

  Future<void> _confirmStop(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ReportColors.sheet,
        title: const Text('Stop this journey?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Your schedule stays at this stop. You can start a new journey any time.',
          style: TextStyle(color: ReportColors.muted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep going')),
          TextButton(
              key: const Key('journey-stop-confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Stop')),
        ],
      ),
    );
    if (ok != true) return;
    final done = await controller.stop();
    if (!done && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Couldn't reach the backend. Try again later.")));
    }
  }
}

/// 一站一個點：走過的實心、這一站金色放大、還沒到的空心；兩端寫起床時間。
class _JourneyPath extends StatelessWidget {
  final JourneyState journey;
  const _JourneyPath({required this.journey});

  @override
  Widget build(BuildContext context) {
    final j = journey;
    final cur = j.current!;
    Widget dot(int i) {
      final passed = i < j.stopIndex, here = i == j.stopIndex;
      final s = here ? 16.0 : 10.0;
      return Container(
        key: Key('journey-dot-$i'),
        width: s,
        height: s,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: here ? ReportColors.gold : (passed ? ReportColors.lilac : Colors.transparent),
          border: Border.all(color: here ? ReportColors.gold : ReportColors.lilac, width: 2),
          boxShadow: here ? const [BoxShadow(color: Color(0x88FFD772), blurRadius: 10)] : null,
        ),
      );
    }

    final items = <Widget>[];
    for (var i = 0; i < j.stops.length; i++) {
      if (i > 0) {
        items.add(Expanded(
          child: Container(
            height: 2,
            color: i <= j.stopIndex ? ReportColors.lilac : ReportColors.border,
          ),
        ));
      }
      items.add(dot(i));
    }
    return Column(
      children: [
        Row(children: items),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('up ${hhmm(j.startWake)}',
                style: const TextStyle(color: ReportColors.dim, fontSize: 12)),
            const Spacer(),
            Text('Tonight: bed ${hhmm(cur.bedtime)} · up ${hhmm(cur.wake)}',
                key: const Key('journey-current'),
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('goal ${hhmm(j.endWake)}',
                key: const Key('journey-goal'),
                style: const TextStyle(color: ReportColors.gold, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ],
    );
  }
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
  TimeOfDay? _goal;
  late int _sleep = _initialSleep();
  bool _busy = false;
  String? _error;

  int _initialSleep() {
    final dial = sleepSpan(widget.dialBedtime, widget.dialWake).inMinutes;
    return dial < widget.info.minSleepMinutes ? widget.info.minSleepMinutes : dial;
  }

  Future<void> _pick({required bool start}) async {
    final t = await showTimePicker(
      context: context,
      initialTime: start ? _start : (_goal ?? _start),
    );
    if (t == null || !mounted) return;
    setState(() {
      _error = null;
      if (start) {
        _start = t;
      } else {
        _goal = t;
      }
    });
  }

  Future<void> _go() async {
    final goal = _goal;
    if (goal == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final out = await widget.controller.start(startWake: _start, endWake: goal, sleepMinutes: _sleep);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (out) {
      case JourneyStartOutcome.started:
        Navigator.of(context).pop(true);
      case JourneyStartOutcome.alreadyThere:
        setState(() => _error = "You're already there — just change your schedule.");
      case JourneyStartOutcome.failed:
        setState(() => _error = "Couldn't reach the backend. Try again later.");
    }
  }

  String _hm(int minutes) => minutes % 60 == 0 ? '${minutes ~/ 60}h' : '${minutes ~/ 60}h ${minutes % 60}m';

  Widget _row({required Key key, required String label, required String sub, required String value,
      VoidCallback? onTap, bool highlight = false}) {
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(sub, style: const TextStyle(color: ReportColors.faint, fontSize: 12)),
                  ],
                ),
              ),
              Text(value,
                  style: TextStyle(
                      color: highlight ? ReportColors.gold : Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900)),
              const SizedBox(width: 4),
              const Icon(Icons.edit_rounded, size: 16, color: ReportColors.accent),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final min = info.minSleepMinutes;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Start a journey',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('Your wake time moves ${info.stepMinutes} minutes earlier at each stop. '
              'Bedtime follows, so you keep the same sleep length.',
              style: const TextStyle(color: ReportColors.muted, fontSize: 13, height: 1.35)),
          const SizedBox(height: 16),
          _row(
            key: const Key('journey-setup-start'),
            label: 'You wake up now',
            sub: info.suggestedStart != null ? 'Middle of your last 7 nights' : 'From your schedule',
            value: hhmm(_start),
            onTap: () => unawaited(_pick(start: true)),
          ),
          const SizedBox(height: 10),
          _row(
            key: const Key('journey-setup-goal'),
            label: 'Goal wake time',
            sub: 'You choose where it ends',
            value: _goal == null ? 'Pick' : hhmm(_goal!),
            highlight: true,
            onTap: () => unawaited(_pick(start: false)),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
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
                      const Text('Sleep length',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text('At least ${_hm(min)} is recommended',
                          key: const Key('journey-setup-min-note'),
                          style: const TextStyle(color: ReportColors.faint, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('journey-setup-less'),
                  onPressed: _sleep - 15 < min ? null : () => setState(() => _sleep -= 15),
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  color: ReportColors.accent,
                ),
                Text(_hm(_sleep),
                    key: const Key('journey-setup-sleep'),
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                IconButton(
                  key: const Key('journey-setup-more'),
                  onPressed: _sleep + 15 > 12 * 60 ? null : () => setState(() => _sleep += 15),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  color: ReportColors.accent,
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                key: const Key('journey-setup-error'),
                style: const TextStyle(color: ReportColors.gold, fontSize: 13, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('journey-setup-go'),
              onPressed: _goal == null || _busy ? null : () => unawaited(_go()),
              style: FilledButton.styleFrom(
                backgroundColor: ReportColors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const StadiumBorder(),
              ),
              child: Text(_busy ? 'Starting…' : 'Start journey',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}
