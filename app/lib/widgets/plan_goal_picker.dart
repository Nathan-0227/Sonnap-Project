import 'package:flutter/material.dart';

import '../theme/app_accent.dart';
import '../services/plan_goals.dart';
import '../services/sleep_plan.dart';
import 'plan_habit_editor.dart' show planIconAsset;

/// 「想改善什麼」→「A few to start with」兩頁（2026-11-22）。第一次登入流程與計畫頁的 Help me pick 共用。
///
/// 第 1 頁：4 個目標，最多選 2 個；Not sure — skip。
/// 第 2 頁：推薦（最多 3 條、預設打勾、可以取消），按 Add N habits 才算數。
/// ⚠️ 推薦的句子是建議清單那一整句，逐字照抄；這裡不加任何「會讓你…」的話。
/// ⚠️ 提醒照舊預設關：加進去的 PlanItem 用 fromSuggestion（notify: false）。
class PlanGoalPicker extends StatefulWidget {
  /// 已經在計畫裡的（不再推薦）。
  final Set<String> alreadyInPlan;

  /// Journey 進行中就不提 Journey。
  final bool journeyActive;

  /// 點 Journey 那一行。null＝只寫字、不能點（第一次登入流程裡沒有地方可以帶過去）。
  final VoidCallback? onTryJourney;

  /// 選完（或跳過）。goals 是空的＝跳過；habits 是勾著的那幾條。
  final void Function(List<String> goals, List<String> habits) onDone;

  const PlanGoalPicker({
    super.key,
    this.alreadyInPlan = const {},
    this.journeyActive = false,
    this.onTryJourney,
    required this.onDone,
  });

  @override
  State<PlanGoalPicker> createState() => _PlanGoalPickerState();
}

const _dim = Color(0xFF9AA8C7);

class _PlanGoalPickerState extends State<PlanGoalPicker> {
  final List<String> _goals = [];
  List<String>? _recs; // null＝還在第 1 頁
  final Set<String> _checked = {};

  void _toggleGoal(String id) => setState(() {
        if (_goals.contains(id)) {
          _goals.remove(id);
        } else if (_goals.length < kMaxPlanGoals) {
          _goals.add(id);
        }
      });

  void _toRecs() => setState(() {
        _recs = recommendHabits(_goals, already: widget.alreadyInPlan);
        _checked
          ..clear()
          ..addAll(_recs!);
      });

  @override
  Widget build(BuildContext context) => _recs == null ? _goalsPage() : _recsPage(_recs!);

  Widget _title(String title, String sub) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, height: 1.2)),
          const SizedBox(height: 8),
          Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: _dim, fontSize: 15, height: 1.35)),
          const SizedBox(height: 20),
        ],
      );

  Widget _primary(String label, VoidCallback? onPressed, Key key) => SizedBox(
        height: 54,
        child: FilledButton(
          key: key,
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: accentOf(context),
            disabledBackgroundColor: const Color(0x337657FF),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          child: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
      );

  Widget _goalsPage() => Column(
        key: const Key('goal-page'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _title(kGoalQuestion, kGoalSubtitle),
          for (final g in kPlanGoals) _goalCard(g),
          const SizedBox(height: 16),
          _primary('Next', _goals.isEmpty ? null : _toRecs, const Key('goal-next')),
          TextButton(
            key: const Key('goal-skip'),
            onPressed: () => widget.onDone(const [], const []),
            child: const Text(kGoalSkip, style: TextStyle(color: _dim, fontSize: 15)),
          ),
        ],
      );

  Widget _goalCard(PlanGoal g) {
    final on = _goals.contains(g.id);
    final full = !on && _goals.length >= kMaxPlanGoals;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: full ? 0.45 : 1,
        child: Semantics(
          button: true,
          selected: on,
          label: g.label,
          child: GestureDetector(
            key: Key('goal-${g.id}'),
            onTap: full ? null : () => _toggleGoal(g.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: on ? const Color(0x337657FF) : const Color(0x14FFFFFF),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: on ? accentOf(context) : const Color(0x22FFFFFF), width: on ? 2 : 1),
              ),
              child: Row(
                children: [
                  Icon(g.icon, color: const Color(0xFFC9B8FF)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(g.label,
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                  Icon(on ? Icons.check_circle_rounded : Icons.circle_outlined,
                      color: on ? accentOf(context) : const Color(0x55FFFFFF)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _recsPage(List<String> recs) {
    final n = _checked.length;
    final journey = _goals.contains('earlier') && !widget.journeyActive;
    final tracked = _goals.contains('less_phone');
    return Column(
      key: const Key('goal-recs'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _title(kGoalRecTitle, kGoalRecSubtitle),
        for (final id in recs) _recRow(suggestionById(id)!),
        if (tracked)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(kGoalTrackedLine,
                key: const Key('goal-tracked'), style: const TextStyle(color: _dim, fontSize: 13.5, height: 1.4)),
          ),
        if (journey)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: widget.onTryJourney == null
                ? const Text(kGoalJourneyLine,
                    key: Key('goal-journey'), style: TextStyle(color: _dim, fontSize: 13.5, height: 1.4))
                : TextButton(
                    key: const Key('goal-journey'),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                    onPressed: widget.onTryJourney,
                    child: Text(kGoalJourneyLine,
                        style: TextStyle(color: accentSoftOf(context), fontSize: 13.5, fontWeight: FontWeight.w700)),
                  ),
          ),
        const SizedBox(height: 16),
        _primary(
          goalAddLabel(n),
          () => widget.onDone(List.of(_goals), [for (final id in recs) if (_checked.contains(id)) id]),
          const Key('goal-add'),
        ),
      ],
    );
  }

  Widget _recRow(PlanSuggestion s) {
    final on = _checked.contains(s.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        key: Key('goal-rec-${s.id}'),
        onTap: () => setState(() => on ? _checked.remove(s.id) : _checked.add(s.id)),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0x14FFFFFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: on ? accentOf(context) : const Color(0x22FFFFFF)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: Image.asset(planIconAsset(s.id),
                    errorBuilder: (context, e, st) => Icon(s.icon, color: const Color(0xFFC9B8FF))),
              ),
              const SizedBox(width: 12),
              // 建議清單那一整句，逐字照抄
              Expanded(child: Text(s.text, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35))),
              const SizedBox(width: 8),
              Icon(on ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                  color: on ? accentOf(context) : const Color(0x77FFFFFF)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 加進計畫：照順序、已經有的跳過、提醒預設關。回傳實際加了幾條。
Future<int> addGoalHabits(PlanStore plan, List<String> habits) async {
  var added = 0;
  for (final id in habits) {
    final s = suggestionById(id);
    if (s != null && await plan.add(PlanItem.fromSuggestion(s))) added++;
  }
  return added;
}
