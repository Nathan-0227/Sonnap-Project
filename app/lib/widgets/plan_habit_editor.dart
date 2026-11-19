import 'package:flutter/material.dart';

import '../services/sleep_plan.dart';
import '../theme/report_style.dart';
import 'report_sheet.dart';

/// 單一習慣的設定頁（2026-11-19，照使用者給的參考圖：一格一張圓角卡、底部按鈕）。
/// 新加一條也先開這一頁（[PlanHabitEditor.isNew]），按了 Add to my plan 才真的加進去。
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

/// 習慣的插圖：`assets/plan/<id>.png`（透明背景）。沒有就畫 Material 圖示。
String planIconAsset(String id) => 'assets/plan/${id.startsWith('custom_') ? 'custom' : id}.png';

Future<PlanEditResult?> openPlanHabitEditor(
  BuildContext context, {
  required PlanItem item,
  required TimeOfDay bedtime,
  required TimeOfDay wake,
  bool isNew = false,
}) {
  return Navigator.of(context).push<PlanEditResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PlanHabitEditor(item: item, bedtime: bedtime, wake: wake, isNew: isNew),
    ),
  );
}

class PlanHabitEditor extends StatefulWidget {
  final PlanItem item;
  final TimeOfDay bedtime;
  final TimeOfDay wake;

  /// 還沒加進計畫：按鈕寫 Add to my plan、沒有 Remove。
  final bool isNew;
  const PlanHabitEditor({
    super.key,
    required this.item,
    required this.bedtime,
    required this.wake,
    this.isNew = false,
  });

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

String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class _PlanHabitEditorState extends State<PlanHabitEditor> {
  late PlanItem _item = widget.item;
  late final TextEditingController _text = TextEditingController(text: widget.item.text)
    ..addListener(() => setState(() {}));

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  TimeOfDay get _time => itemTime(_item, bedtime: widget.bedtime, wake: widget.wake);

  /// 一天都沒選、自己寫的沒寫字 → 按鈕不能按。
  bool get _canSave => (_item.days & kEveryDay) != 0 && (!_item.isCustom || _text.text.trim().isNotEmpty);

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t == null) return;
    setState(() => _item = _item.copyWith(
        offsetMinutes: offsetFor(t, _item.anchor, bedtime: widget.bedtime, wake: widget.wake)));
  }

  void _save() {
    if (!_canSave) return;
    final text = _text.text.trim();
    Navigator.of(context).pop(PlanEditResult.saved(_item.isCustom ? _item.copyWith(text: text) : _item));
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return ReportFont(
      child: Scaffold(
        backgroundColor: ReportColors.bgTop,
        body: Stack(
          children: [
            const Positioned.fill(child: ReportBackground()),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _topBar(),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      children: [
                        _hero(),
                        const SizedBox(height: 26),
                        const _SectionLabel('WHEN'),
                        _timeCard(),
                        const SizedBox(height: 12),
                        _notifyCard(),
                        const SizedBox(height: 22),
                        const _SectionLabel('REPEAT'),
                        _repeatCard(),
                        if (!widget.isNew) ...[
                          const SizedBox(height: 22),
                          Center(
                            child: TextButton.icon(
                              key: const Key('plan-editor-remove'),
                              onPressed: () => Navigator.of(context).pop(const PlanEditResult.removed()),
                              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: ReportColors.muted),
                              label: const Text('Remove from my plan',
                                  style: TextStyle(color: ReportColors.muted, fontSize: 14, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _saveBar(pad.bottom),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() => Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
        child: Row(
          children: [
            IconButton(
              key: const Key('plan-editor-close'),
              onPressed: () => Navigator.of(context).pop(),
              style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.08)),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
            Expanded(
              child: Text(
                widget.isNew ? 'New habit' : 'Edit habit',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
      );

  Widget _hero() => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 116,
            height: 116,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                ReportColors.lilac.withValues(alpha: 0.35),
                ReportColors.purple.withValues(alpha: 0.10),
                Colors.transparent,
              ], stops: const [0, 0.6, 1]),
            ),
            alignment: Alignment.center,
            child: Image.asset(
              planIconAsset(_item.id),
              width: 86,
              height: 86,
              errorBuilder: (_, _, _) => Icon(_item.icon, size: 52, color: ReportColors.gold),
            ),
          ),
          const SizedBox(height: 12),
          if (_item.isCustom)
            TextField(
              key: const Key('plan-editor-text'),
              controller: _text,
              autofocus: widget.isNew && widget.item.text.isEmpty,
              maxLength: 80,
              maxLines: null,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, height: 1.3),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'Name your habit',
                hintStyle: const TextStyle(color: ReportColors.dim),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
              ),
            )
          else
            // 建議的那幾句照抄研究文件，不給改（改措辭要先審）
            Text(_item.text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, height: 1.3)),
          const SizedBox(height: 10),
          _Pill(
            icon: _item.isCustom ? Icons.phone_android_rounded : Icons.menu_book_rounded,
            text: _item.isCustom ? 'Your own · stays on this phone' : 'From the sleep research',
          ),
        ],
      );

  Widget _timeCard() => _Card(
        child: InkWell(
          key: const Key('plan-editor-time'),
          borderRadius: BorderRadius.circular(24),
          onTap: _pickTime,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
            child: Row(
              children: [
                const _Badge(icon: Icons.schedule_rounded, color: ReportColors.down),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_hhmm(_time),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900, height: 1.1)),
                      const SizedBox(height: 4),
                      Text('${relativeLabel(_item)} · moves with your schedule',
                          style: const TextStyle(color: ReportColors.muted, fontSize: 12.5)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), shape: BoxShape.circle),
                  child: const Icon(Icons.edit_rounded, size: 18, color: ReportColors.soft),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _notifyCard() => _Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
          child: Row(
            children: [
              const _Badge(icon: Icons.notifications_rounded, color: ReportColors.gold),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Remind me',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(_item.notify ? 'A notification at ${_hhmm(_time)}' : 'Off',
                        style: const TextStyle(color: ReportColors.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              Switch(
                key: const Key('plan-editor-notify'),
                value: _item.notify,
                activeThumbColor: Colors.white,
                activeTrackColor: ReportColors.purple,
                onChanged: (v) => setState(() => _item = _item.copyWith(notify: v)),
              ),
            ],
          ),
        ),
      );

  Widget _repeatCard() {
    final d = _item.days & kEveryDay;
    return _Card(
      key: const Key('plan-editor-repeat'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, mask) in const [('Daily', kEveryDay), ('Weekdays', 0x1F), ('Weekends', 0x60)])
                  _Preset(
                    key: Key('plan-preset-$label'),
                    label: label,
                    on: d == mask,
                    onTap: () => setState(() => _item = _item.copyWith(days: mask)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < 7; i++)
                  _DayChip(
                    key: Key('plan-day-$i'),
                    letter: _dayLetters[i],
                    on: (d >> i) & 1 == 1,
                    onTap: () => setState(() => _item = _item.copyWith(days: _item.days ^ (1 << i))),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(d == 0 ? 'Pick at least one day' : repeatLabel(d),
                style: TextStyle(color: d == 0 ? ReportColors.gold : ReportColors.muted, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }

  Widget _saveBar(double bottomInset) => Padding(
        padding: EdgeInsets.fromLTRB(20, 10, 20, 14 + bottomInset),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('plan-editor-save'),
            onPressed: _canSave ? _save : null,
            style: FilledButton.styleFrom(
              backgroundColor: ReportColors.purple,
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.10),
              padding: const EdgeInsets.symmetric(vertical: 17),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: Text(widget.isNew ? 'Add to my plan' : 'Save',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          ),
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 6, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                color: ReportColors.dim, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
      );
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2F3578), Color(0xFF242A62)],
          ),
          border: Border.all(color: ReportColors.border),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Material(color: Colors.transparent, child: child),
      );
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Pill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: ReportColors.lilac),
            const SizedBox(width: 6),
            Text(text, style: const TextStyle(color: ReportColors.soft, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _Badge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
        child: Icon(icon, color: color, size: 24),
      );
}

class _Preset extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _Preset({super.key, required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: on ? ReportColors.purple.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: on ? ReportColors.lilac : Colors.transparent),
          ),
          child: Text(label,
              style: TextStyle(
                  color: on ? Colors.white : ReportColors.soft, fontSize: 13, fontWeight: FontWeight.w800)),
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? ReportColors.purple : Colors.white.withValues(alpha: 0.04),
            border: Border.all(color: on ? ReportColors.lilac : ReportColors.border),
          ),
          child: Text(letter,
              style: TextStyle(color: on ? Colors.white : ReportColors.muted, fontWeight: FontWeight.w900)),
        ),
      );
}

// ── 加一條 ─────────────────────────────────────────────────────────────

/// 建議清單（還沒加的）＋自己寫一條。回傳的是**草稿**：呼叫端接著開 [openPlanHabitEditor]，
/// 在設定頁按 Add to my plan 才真的加進去。
Future<PlanItem?> showPlanAddSheet(
  BuildContext context, {
  required PlanStore plan,
  required TimeOfDay bedtime,
  required TimeOfDay wake,
}) {
  return showReportSheet<PlanItem>(
    context: context,
    builder: (context) => _AddSheet(plan: plan),
  );
}

class _AddSheet extends StatelessWidget {
  final PlanStore plan;
  const _AddSheet({required this.plan});

  @override
  Widget build(BuildContext context) {
    final left = [for (final s in kPlanSuggestions) if (!plan.contains(s.id)) s];
    return Container(
      key: const Key('plan-add-sheet'),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        color: ReportColors.sheet,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: ReportFont(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Add a habit',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                const Text('Small ones are fine. Each suggestion has a study behind it.',
                    style: TextStyle(color: ReportColors.muted, fontSize: 12.5)),
                const SizedBox(height: 16),
                _choice(
                  context,
                  key: const Key('plan-custom-add'),
                  asset: planIconAsset('custom_'),
                  fallback: Icons.edit_rounded,
                  text: 'Write your own',
                  sub: 'Stays on this phone only',
                  draft: () => PlanItem(
                    id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
                    text: '',
                    anchor: PlanAnchor.bedtime,
                    offsetMinutes: -30,
                  ),
                ),
                if (left.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 12, 0, 8),
                    child: Text('SUGGESTED',
                        style: TextStyle(
                            color: ReportColors.dim, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
                  ),
                for (final s in left)
                  _choice(
                    context,
                    key: Key('plan-suggest-${s.id}'),
                    asset: planIconAsset(s.id),
                    fallback: s.icon,
                    text: s.text,
                    draft: () => PlanItem.fromSuggestion(s),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _choice(
    BuildContext context, {
    required Key key,
    required String asset,
    required IconData fallback,
    required String text,
    String? sub,
    required PlanItem Function() draft,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: ReportColors.card,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.of(context).pop(draft()),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Image.asset(asset,
                        width: 38,
                        height: 38,
                        errorBuilder: (_, _, _) => Icon(fallback, color: ReportColors.lilac, size: 22)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(text,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800, height: 1.3)),
                        if (sub != null) Text(sub, style: const TextStyle(color: ReportColors.muted, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: ReportColors.faint),
                ],
              ),
            ),
          ),
        ),
      );
}
