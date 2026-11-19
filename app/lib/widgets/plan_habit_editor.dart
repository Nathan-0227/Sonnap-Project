import 'package:flutter/material.dart';

import '../services/sleep_plan.dart';
import '../theme/report_style.dart';
import 'report_sheet.dart';

/// 單一習慣的編輯頁（2026-11-19，照使用者給的參考圖：一格一張圓角卡、底部 Save）。
///
/// 參考圖有、這裡刻意沒有的（使用者定）：
///   - Times per day：睡眠習慣幾乎都是一天一次
///   - Keep this goal until complete：睡眠習慣綁「今天」，延到明天就不是同一件事
///   - Link an exercise：建議清單裡沒有一條適合連到現成畫面，先不做
class PlanEditResult {
  final PlanItem? item;
  final bool removed;
  const PlanEditResult.saved(PlanItem this.item) : removed = false;
  const PlanEditResult.removed()
      : item = null,
        removed = true;
}

Future<PlanEditResult?> openPlanHabitEditor(
  BuildContext context, {
  required PlanItem item,
  required TimeOfDay bedtime,
  required TimeOfDay wake,
}) {
  return Navigator.of(context).push<PlanEditResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PlanHabitEditor(item: item, bedtime: bedtime, wake: wake),
    ),
  );
}

class PlanHabitEditor extends StatefulWidget {
  final PlanItem item;
  final TimeOfDay bedtime;
  final TimeOfDay wake;
  const PlanHabitEditor({super.key, required this.item, required this.bedtime, required this.wake});

  @override
  State<PlanHabitEditor> createState() => _PlanHabitEditorState();
}

const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

String repeatLabel(int days) {
  final d = days & kEveryDay;
  if (d == kEveryDay) return 'Daily';
  if (d == 0x1F) return 'Weekdays';
  if (d == 0x60) return 'Weekends';
  if (d == 0) return 'Never';
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return [for (var i = 0; i < 7; i++) if ((d >> i) & 1 == 1) names[i]].join(', ');
}

class _PlanHabitEditorState extends State<PlanHabitEditor> {
  late PlanItem _item = widget.item;
  late final TextEditingController _text = TextEditingController(text: widget.item.text);
  bool _repeatOpen = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  TimeOfDay get _time => itemTime(_item, bedtime: widget.bedtime, wake: widget.wake);

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t == null) return;
    setState(() => _item = _item.copyWith(
        offsetMinutes: offsetFor(t, _item.anchor, bedtime: widget.bedtime, wake: widget.wake)));
  }

  void _save() {
    final text = _text.text.trim();
    if (_item.isCustom && text.isEmpty) return;
    Navigator.of(context).pop(PlanEditResult.saved(_item.isCustom ? _item.copyWith(text: text) : _item));
  }

  @override
  Widget build(BuildContext context) {
    final t = _time;
    return ReportFont(
      child: Scaffold(
        backgroundColor: ReportColors.bgTop,
        body: Stack(
          children: [
            const Positioned.fill(child: ReportBackground()),
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 76,
                              height: 76,
                              decoration: reportCard(radius: 24),
                              child: Icon(_item.icon, size: 38, color: ReportColors.gold),
                            ),
                            const Spacer(),
                            IconButton(
                              key: const Key('plan-editor-close'),
                              onPressed: () => Navigator.of(context).pop(),
                              style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.08)),
                              icon: const Icon(Icons.close_rounded, color: Colors.white),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                          decoration: reportCard(),
                          child: _item.isCustom
                              ? TextField(
                                  key: const Key('plan-editor-text'),
                                  controller: _text,
                                  maxLength: 80,
                                  maxLines: null,
                                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    counterText: '',
                                    hintText: 'Your habit',
                                    hintStyle: TextStyle(color: ReportColors.dim),
                                  ),
                                )
                              // 建議的那幾句照抄研究文件，不給改（改措辭要先審）
                              : Text(_item.text,
                                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, height: 1.3)),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: reportCard(),
                          child: Column(
                            children: [
                              _Row(
                                key: const Key('plan-editor-time'),
                                icon: Icons.schedule_rounded,
                                iconColor: ReportColors.down,
                                label: 'TIME',
                                value: '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
                                sub: '${relativeLabel(_item)} · moves with your schedule',
                                onTap: _pickTime,
                              ),
                              const Divider(height: 1, color: ReportColors.border),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
                                child: Row(
                                  children: [
                                    const _Badge(icon: Icons.notifications_rounded, color: ReportColors.gold),
                                    const SizedBox(width: 14),
                                    const Expanded(
                                      child: Text('Notify me',
                                          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                                    ),
                                    Switch(
                                      key: const Key('plan-editor-notify'),
                                      value: _item.notify,
                                      activeThumbColor: ReportColors.purple,
                                      onChanged: (v) => setState(() => _item = _item.copyWith(notify: v)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: reportCard(),
                          child: Column(
                            children: [
                              _Row(
                                key: const Key('plan-editor-repeat'),
                                icon: Icons.repeat_rounded,
                                iconColor: ReportColors.lilac,
                                label: 'REPEAT',
                                value: repeatLabel(_item.days),
                                onTap: () => setState(() => _repeatOpen = !_repeatOpen),
                                open: _repeatOpen,
                              ),
                              if (_repeatOpen)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      for (var i = 0; i < 7; i++)
                                        _DayChip(
                                          key: Key('plan-day-$i'),
                                          letter: _dayLetters[i],
                                          on: (_item.days >> i) & 1 == 1,
                                          onTap: () => setState(
                                              () => _item = _item.copyWith(days: _item.days ^ (1 << i))),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Center(
                          child: TextButton(
                            key: const Key('plan-editor-remove'),
                            onPressed: () => Navigator.of(context).pop(const PlanEditResult.removed()),
                            child: const Text('Remove from my plan',
                                style: TextStyle(color: ReportColors.muted, fontSize: 14)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      key: const Key('plan-editor-save'),
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: ReportColors.purple,
                        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      child: const Text('Save', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _Badge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 22),
      );
}

class _Row extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String? sub;
  final VoidCallback onTap;
  final bool open;
  const _Row({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.onTap,
    this.sub,
    this.open = false,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              _Badge(icon: icon, color: iconColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            color: ReportColors.dim, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                    const SizedBox(height: 2),
                    Text(value, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                    if (sub != null)
                      Text(sub!, style: const TextStyle(color: ReportColors.muted, fontSize: 12)),
                  ],
                ),
              ),
              Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: ReportColors.faint),
            ],
          ),
        ),
      );
}

class _DayChip extends StatelessWidget {
  final String letter;
  final bool on;
  final VoidCallback onTap;
  const _DayChip({super.key, required this.letter, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) => InkResponse(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? ReportColors.purple : Colors.transparent,
            border: Border.all(color: on ? ReportColors.purple : ReportColors.border),
          ),
          child: Text(letter,
              style: TextStyle(color: on ? Colors.white : ReportColors.muted, fontWeight: FontWeight.w800)),
        ),
      );
}

// ── 加一條 ─────────────────────────────────────────────────────────────

/// 建議清單（還沒加的）＋自己寫一條。回傳要加的那一條。
Future<PlanItem?> showPlanAddSheet(
  BuildContext context, {
  required PlanStore plan,
  required TimeOfDay bedtime,
  required TimeOfDay wake,
}) {
  return showReportSheet<PlanItem>(
    context: context,
    builder: (context) => _AddSheet(plan: plan, bedtime: bedtime, wake: wake),
  );
}

class _AddSheet extends StatefulWidget {
  final PlanStore plan;
  final TimeOfDay bedtime;
  final TimeOfDay wake;
  const _AddSheet({required this.plan, required this.bedtime, required this.wake});

  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _addCustom() {
    final text = _custom.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(PlanItem(
      id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
      text: text,
      anchor: PlanAnchor.bedtime,
      offsetMinutes: -30,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final left = [for (final s in kPlanSuggestions) if (!widget.plan.contains(s.id)) s];
    return Container(
      key: const Key('plan-add-sheet'),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        color: ReportColors.sheet,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(22, 24, 22, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: ReportFont(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Add a habit',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                const Text('Small ones are fine. Each of these has a study behind it.',
                    style: TextStyle(color: ReportColors.muted, fontSize: 12.5)),
                const SizedBox(height: 14),
                for (final s in left)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: ReportColors.card,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        key: Key('plan-suggest-${s.id}'),
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.of(context).pop(PlanItem.fromSuggestion(s)),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                          child: Row(
                            children: [
                              Icon(s.icon, color: ReportColors.lilac, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(s.text,
                                    style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.3)),
                              ),
                              const Icon(Icons.add_circle_outline_rounded, color: ReportColors.accent),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                const Text('Or write your own',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                const Text('Stays on this phone only.',
                    style: TextStyle(color: ReportColors.muted, fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('plan-custom-text'),
                        controller: _custom,
                        maxLength: 80,
                        style: const TextStyle(color: Colors.white),
                        onSubmitted: (_) => _addCustom(),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: 'e.g. Stretch for 5 minutes',
                          hintStyle: const TextStyle(color: ReportColors.dim),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.06),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      key: const Key('plan-custom-add'),
                      onPressed: _addCustom,
                      style: IconButton.styleFrom(backgroundColor: ReportColors.purple),
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
