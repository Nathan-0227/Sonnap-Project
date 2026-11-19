import 'dart:async';

import 'package:flutter/material.dart';

import '../services/alarm.dart';
import '../services/challenges_service.dart';
import '../services/nightly_sync.dart';
import '../services/plan_reminders.dart';
import '../services/sleep_plan.dart';
import '../theme/report_style.dart';
import '../widgets/challenges_sheet.dart';
import '../widgets/plan_habit_editor.dart';
import '../widgets/sleep_dial.dart';
import '../widgets/sleep_schedule_sheet.dart';

/// 睡眠計畫頁（2026-11-19）。由上到下：
///   作息（就寢、起床）→ 這一週（連續準時、作息收斂）→ 量測的三列 → 今天的習慣 → 加一條
///
/// ⚠️ 量測那幾列與進度條**一格都不算**，照抄 `/challenges`（後端判）。
/// ⚠️ 自己勾的只寫事實（連續幾天），**不給 XP、不改心情**、沒勾不打叉不用紅。
class PlanScreen extends StatefulWidget {
  final PlanStore plan;
  final NightlySync? nightly;
  final TimeOfDay bedtime;
  final AlarmSettingsStore alarmSettings;
  final AlarmScheduler alarmScheduler;
  final PlanReminderScheduler reminders;
  final ValueChanged<TimeOfDay>? onBedtimeChanged;

  /// 起床時間改了（轉盤存完）。主程式要補送後端。
  final VoidCallback? onWakeChanged;
  final DateTime Function() clock;

  const PlanScreen({
    super.key,
    required this.plan,
    required this.bedtime,
    required this.alarmSettings,
    required this.alarmScheduler,
    required this.reminders,
    this.nightly,
    this.onBedtimeChanged,
    this.onWakeChanged,
    this.clock = DateTime.now,
  });

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

/// 量測的三列（後端 challenge id）。進度條是另外兩個多晚的。
const List<String> kMeasuredIds = ['on_time_tonight', 'phone_in_bed_tonight', 'up_on_time'];
const List<String> kWeekIds = ['streak_nights', 'bedtime_consistency_7d'];

class _PlanScreenState extends State<PlanScreen> {
  late TimeOfDay _bedtime = widget.bedtime;
  TimeOfDay? _wake;

  @override
  void initState() {
    super.initState();
    widget.plan.addListener(_onChange);
    widget.nightly?.addListener(_onChange);
    if (!widget.plan.loaded) unawaited(widget.plan.load());
    unawaited(_loadWake());
  }

  @override
  void dispose() {
    widget.plan.removeListener(_onChange);
    widget.nightly?.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _loadWake() async {
    final w = await widget.alarmSettings.wakeTime(_bedtime);
    if (mounted) setState(() => _wake = w);
  }

  void _resyncReminders() {
    final wake = _wake;
    if (wake == null) return;
    unawaited(syncPlanReminders(widget.reminders, widget.plan.items,
        now: widget.clock(), bedtime: _bedtime, wake: wake));
  }

  Future<void> _editSchedule() async {
    final result = await showSleepScheduleSheet(
      context,
      bedtime: _bedtime,
      alarmSettings: widget.alarmSettings,
      scheduler: widget.alarmScheduler,
    );
    if (result == null || !mounted) return;
    setState(() {
      _wake = result.wake;
      if (result.bedtime != _bedtime) _bedtime = result.bedtime;
    });
    if (result.bedtime != widget.bedtime) widget.onBedtimeChanged?.call(result.bedtime);
    widget.onWakeChanged?.call();
    _resyncReminders();
  }

  Future<void> _openEditor(PlanItem item) async {
    final wake = _wake;
    if (wake == null) return;
    final out = await openPlanHabitEditor(context, item: item, bedtime: _bedtime, wake: wake);
    if (out == null) return;
    if (out.removed) {
      await widget.plan.remove(item.id);
    } else if (out.item != null) {
      await widget.plan.update(out.item!);
    }
    _resyncReminders();
  }

  Future<void> _add() async {
    final wake = _wake;
    if (wake == null) return;
    final picked = await showPlanAddSheet(context, plan: widget.plan, bedtime: _bedtime, wake: wake);
    if (picked == null) return;
    await widget.plan.add(picked);
    _resyncReminders();
  }

  @override
  Widget build(BuildContext context) {
    final wake = _wake;
    final today = wake == null ? null : planDayOf(widget.clock(), wake);
    final challenges = widget.nightly?.challenges;
    return ReportFont(
      child: Scaffold(
        backgroundColor: ReportColors.bgTop,
        body: Stack(
          children: [
            const Positioned.fill(child: ReportBackground()),
            SafeArea(
              child: ListView(
                key: const Key('plan-list'),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  Row(
                    children: [
                      IconButton(
                        key: const Key('plan-back'),
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 4),
                      const Text('Your sleep plan',
                          style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ScheduleCard(bedtime: _bedtime, wake: wake, onTap: _editSchedule),
                  ..._weekSection(challenges),
                  ..._measuredSection(challenges),
                  const SizedBox(height: 22),
                  _sectionTitle('Your habits', 'Tick them yourself. They never change your score.'),
                  const SizedBox(height: 10),
                  if (today != null) ..._habitRows(today, wake!),
                  const SizedBox(height: 4),
                  _AddButton(onTap: _add, full: widget.plan.items.length >= kMaxPlanItems),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, String? sub) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(color: ReportColors.muted, fontSize: 12.5, height: 1.35)),
          ],
        ],
      );

  List<ChallengeProgress> _pick(ChallengesResult? r, List<String> ids) {
    if (r == null || r.status != ChallengesStatus.ok) return const [];
    return [
      for (final id in ids)
        ...r.challenges.where((c) => c.challengeId == id),
    ];
  }

  List<Widget> _weekSection(ChallengesResult? r) {
    final week = _pick(r, kWeekIds);
    if (week.isEmpty) return const [];
    return [
      const SizedBox(height: 22),
      _sectionTitle('This week', null),
      const SizedBox(height: 10),
      for (final c in week) ...[ChallengeCard(challenge: c), const SizedBox(height: 10)],
    ];
  }

  List<Widget> _measuredSection(ChallengesResult? r) {
    final measured = _pick(r, kMeasuredIds);
    return [
      const SizedBox(height: 22),
      _sectionTitle('Measured', 'Checked by your phone and watch, from your last recorded night.'),
      const SizedBox(height: 10),
      if (measured.isEmpty)
        // ⚠️ 量不到時照實說，不畫成沒做到
        Text(
          r == null || r.status == ChallengesStatus.noBackend
              ? 'These need the Sonnap server.'
              : "Couldn't reach the Sonnap server.",
          key: const Key('plan-measured-unavailable'),
          style: const TextStyle(color: ReportColors.dim, fontSize: 12.5),
        )
      else
        for (final c in measured) _MeasuredRow(challenge: c),
    ];
  }

  List<Widget> _habitRows(DateTime today, TimeOfDay wake) {
    final items = widget.plan.items;
    if (items.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
            'Pick a few small habits to support your schedule.',
            key: Key('plan-empty'),
            style: TextStyle(color: ReportColors.soft, fontSize: 13.5),
          ),
        ),
      ];
    }
    return [
      for (final item in items)
        _HabitRow(
          item: item,
          due: item.onWeekday(today.weekday),
          checked: widget.plan.isChecked(item.id, today),
          streak: widget.plan.streak(item.id, today),
          time: itemTime(item, bedtime: _bedtime, wake: wake),
          onToggle: () => widget.plan.setChecked(item.id, today, !widget.plan.isChecked(item.id, today)),
          onTap: () => _openEditor(item),
        ),
    ];
  }
}

String _hm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class _ScheduleCard extends StatelessWidget {
  final TimeOfDay bedtime;
  final TimeOfDay? wake;
  final VoidCallback onTap;
  const _ScheduleCard({required this.bedtime, required this.wake, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final w = wake;
    final span = w == null ? null : sleepSpan(bedtime, w);
    Widget cell(IconData icon, String label, String value, Key key) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 16, color: ReportColors.lilac),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(color: ReportColors.muted, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 4),
              Text(value, key: key,
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
            ],
          ),
        );
    return Material(
      key: const Key('plan-schedule'),
      color: ReportColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: ReportColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  cell(Icons.bedtime_rounded, 'Bedtime', _hm(bedtime), const Key('plan-bedtime')),
                  cell(Icons.wb_sunny_rounded, 'Wake time', w == null ? '—' : _hm(w), const Key('plan-wake')),
                  const Icon(Icons.chevron_right_rounded, color: ReportColors.accent),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                // 只寫事實：幾小時。不判斷夠不夠（好壞只有後端能判）。
                span == null
                    ? 'The same times every day, weekends too.'
                    : '${reportHm(span.inMinutes)} in bed · the same times every day, weekends too.',
                style: const TextStyle(color: ReportColors.soft, fontSize: 12.5, height: 1.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MeasuredRow extends StatelessWidget {
  final ChallengeProgress challenge;
  const _MeasuredRow({required this.challenge});

  @override
  Widget build(BuildContext context) {
    final c = challenge;
    final done = c.state == ChallengeState.completed;
    final noData = c.state == ChallengeState.insufficientData;
    return Container(
      key: Key('plan-measured-${c.challengeId}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: reportCard(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: noData
                // ⚠️ 沒量到寫「—」，不是空圈（空圈＝沒做到）
                ? const Text('—',
                    key: Key('plan-measured-nodata'),
                    style: TextStyle(color: ReportColors.dim, fontSize: 20, fontWeight: FontWeight.w800))
                : Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    color: done ? ReportColors.down : ReportColors.faint, size: 24),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.title, style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                // ⚠️ 整句照抄後端
                Text(c.detail, style: const TextStyle(color: ReportColors.muted, fontSize: 12, height: 1.35)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Tooltip(
            message: 'Measured',
            child: Icon(Icons.watch_rounded, size: 16, color: ReportColors.dim),
          ),
        ],
      ),
    );
  }
}

class _HabitRow extends StatelessWidget {
  final PlanItem item;
  final bool due;
  final bool checked;
  final int streak;
  final TimeOfDay time;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  const _HabitRow({
    required this.item,
    required this.due,
    required this.checked,
    required this.streak,
    required this.time,
    required this.onToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final sub = due ? '${relativeLabel(item)} · ${_hm(time)}' : 'Not today';
    return Opacity(
      opacity: due ? 1 : 0.55,
      child: Container(
        key: Key('plan-habit-${item.id}'),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: reportCard(),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
              child: Row(
                children: [
                  IconButton(
                    key: Key('plan-check-${item.id}'),
                    onPressed: due ? onToggle : null,
                    tooltip: checked ? 'Done' : 'Mark done',
                    // ⚠️ 沒勾是空心圈，不打叉、不用紅
                    icon: Icon(
                      checked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: checked ? ReportColors.gold : ReportColors.faint,
                      size: 28,
                    ),
                  ),
                  Icon(item.icon, size: 18, color: ReportColors.lilac),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.text,
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700, height: 1.3)),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Flexible(
                              child: Text(sub, style: const TextStyle(color: ReportColors.muted, fontSize: 11.5)),
                            ),
                            if (item.notify) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.notifications_active_rounded, size: 13, color: ReportColors.dim),
                            ],
                          ],
                        ),
                        if (streak >= 2) ...[
                          const SizedBox(height: 3),
                          Text('$streak days in a row',
                              key: Key('plan-streak-${item.id}'),
                              style: const TextStyle(color: ReportColors.gold, fontSize: 11.5, fontWeight: FontWeight.w700)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool full;
  const _AddButton({required this.onTap, required this.full});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const Key('plan-add'),
      onPressed: full ? null : onTap,
      icon: const Icon(Icons.add_rounded),
      label: Text(full ? 'Your plan is full ($kMaxPlanItems)' : 'Add a habit'),
      style: OutlinedButton.styleFrom(
        foregroundColor: ReportColors.accent,
        side: const BorderSide(color: ReportColors.border),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

// ── 首頁小卡 ───────────────────────────────────────────────────────────

/// 首頁「不按也沒關係」那句底下的小卡：今天幾項、勾了幾項（只算自己勾的）。
class TodayPlanCard extends StatefulWidget {
  final PlanStore plan;
  final Future<TimeOfDay> Function() wake;
  final VoidCallback onOpen;
  final DateTime Function() clock;

  const TodayPlanCard({
    super.key,
    required this.plan,
    required this.wake,
    required this.onOpen,
    this.clock = DateTime.now,
  });

  @override
  State<TodayPlanCard> createState() => _TodayPlanCardState();
}

class _TodayPlanCardState extends State<TodayPlanCard> {
  TimeOfDay? _wake;

  @override
  void initState() {
    super.initState();
    widget.plan.addListener(_onChange);
    if (!widget.plan.loaded) unawaited(widget.plan.load());
    unawaited(widget.wake().then((w) {
      if (mounted) setState(() => _wake = w);
    }));
  }

  @override
  void dispose() {
    widget.plan.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    // 從 Plan 頁回來時作息可能改了
    unawaited(widget.wake().then((w) {
      if (mounted) setState(() => _wake = w);
    }));
  }

  @override
  Widget build(BuildContext context) {
    final wake = _wake;
    String line;
    if (!widget.plan.loaded || wake == null) {
      line = ' ';
    } else {
      final today = planDayOf(widget.clock(), wake);
      final due = widget.plan.dueOn(today);
      final done = due.where((i) => widget.plan.isChecked(i.id, today)).length;
      line = widget.plan.items.isEmpty
          ? 'Set up small habits around your schedule'
          : due.isEmpty
              ? 'Nothing planned for today'
              : '$done of ${due.length} done today';
    }
    return Material(
      key: const Key('today-plan-card'),
      color: Colors.white.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0x24FFFFFF)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: widget.onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.checklist_rounded, color: Color(0xFFFFD772), size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Today's plan",
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                    Text(line,
                        key: const Key('today-plan-summary'),
                        style: const TextStyle(color: Color(0xFFB7BEDC), fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFC9B8FF)),
            ],
          ),
        ),
      ),
    );
  }
}
