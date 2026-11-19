import 'dart:async';

import 'package:flutter/material.dart';

import '../services/sleep_plan.dart';

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
