import 'package:flutter/material.dart';

import '../screens/morning_report_screen.dart' show reportDateTitle;
import '../services/pet_notes.dart';
import '../services/sleep_plan.dart';
import '../theme/report_style.dart';
import 'home_pet.dart';
import 'report_sheet.dart';

/// 點草地上那本日記打開的頁（2026-11-17 起取代夢境日記）：總結＋建議，**全部照抄後端**。
///
/// - 建議分兩種圖示：tip（下次可以怎麼做，燈泡）與 note（只解釋這一晚，i）。
/// - 手錶資料還沒到（waiting）時說一句「資料到了會多寫一點」，不寫總結。
/// - 只有 AI 真的寫了（source = llm）才放「AI 寫的」那行小字。
///
/// [mood]：那一晚的寵物心情，畫成小頭像（不認得的一律 bored，同 [HomePet]）。
///
/// [writing]：首頁點日記本時叫 AI 寫的那一份（2026-11-21 使用者定）。頁面先照現在的內容開，
/// 底下一行「正在寫」；寫好就換成新的那份（並呼叫 [onWritten]），沒寫出來就留著原本的、拿掉那一行。
Future<void> showPetNotes(
  BuildContext context, {
  required PetNotes notes,
  String? mood,
  Future<PetNotes?>? writing,
  ValueChanged<PetNotes>? onWritten,
}) {
  return showReportSheet<void>(
    context: context,
    builder: (context) => ReportFont(
      child: writing == null
          ? PetNotesView(notes: notes, mood: mood, plan: PlanStore.shared)
          : _WritingNotes(
              notes: notes,
              mood: mood,
              writing: writing,
              onWritten: onWritten,
            ),
    ),
  );
}

/// 這一晚什麼都沒有（AI 沒寫出來、也沒有適用的建議）時那一行。
const String kNotesEmptyLine = 'Nothing to add for this night.';

/// AI 正在寫的那一行（固定的畫面文字）。
const String kNotesWritingLine = 'Writing your notes…';

class _WritingNotes extends StatefulWidget {
  final PetNotes notes;
  final String? mood;
  final Future<PetNotes?> writing;
  final ValueChanged<PetNotes>? onWritten;
  const _WritingNotes({
    required this.notes,
    required this.mood,
    required this.writing,
    this.onWritten,
  });

  @override
  State<_WritingNotes> createState() => _WritingNotesState();
}

class _WritingNotesState extends State<_WritingNotes> {
  late PetNotes _notes = widget.notes;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    widget.writing.then((n) {
      if (n != null) widget.onWritten?.call(n);
      if (!mounted) return;
      setState(() {
        if (n != null) _notes = n;
        _busy = false;
      });
    }, onError: (Object _) {
      if (mounted) setState(() => _busy = false);
    });
  }

  @override
  Widget build(BuildContext context) => PetNotesView(
        notes: _notes,
        mood: widget.mood,
        plan: PlanStore.shared,
        writing: _busy,
      );
}

/// 手錶還沒到時那一句（固定的畫面文字，不是建議）。
const String kNotesWaitingLine =
    "Your watch data isn't here yet. I'll write more once it arrives.";

/// AI 寫的那一份的小字。
const String kNotesAiLine =
    'Written with AI from your sleep data. Suggestions come from a reviewed list. Not medical advice.';

class PetNotesView extends StatelessWidget {
  final PetNotes notes;
  final String? mood;

  /// 睡眠計畫。有的話，對得上計畫清單的建議旁邊放「Add to my plan」（2026-11-19）。
  final PlanStore? plan;

  /// AI 正在寫：多一行 [kNotesWritingLine]。
  final bool writing;
  const PetNotesView({
    super.key,
    required this.notes,
    this.mood,
    this.plan,
    this.writing = false,
  });

  @override
  Widget build(BuildContext context) {
    final day = DateTime.tryParse(notes.date);
    return Container(
      key: const Key('pet-notes'),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF151A3C), Color(0xFF1B1F48), Color(0xFF2B3470)],
          stops: [0, 0.6, 1],
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: HomePet(mood: mood, size: 56),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          kNotesTitle,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (day != null)
                          Text(
                            reportDateTitle(day),
                            key: const Key('pet-notes-date'),
                            style: const TextStyle(
                              color: ReportColors.muted,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (notes.summary != null) ...[
                const SizedBox(height: 16),
                Text(
                  notes.summary!,
                  key: const Key('pet-notes-summary'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.55,
                  ),
                ),
              ],
              if (writing) ...[
                const SizedBox(height: 16),
                const Row(
                  key: Key('pet-notes-writing'),
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ReportColors.muted,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      kNotesWritingLine,
                      style: TextStyle(color: ReportColors.muted, fontSize: 14),
                    ),
                  ],
                ),
              ],
              if (!writing && !notes.waiting && !notes.hasContent) ...[
                const SizedBox(height: 16),
                const Text(
                  kNotesEmptyLine,
                  key: Key('pet-notes-empty'),
                  style: TextStyle(color: ReportColors.muted, fontSize: 14),
                ),
              ],
              if (notes.waiting) ...[
                const SizedBox(height: 16),
                const Text(
                  kNotesWaitingLine,
                  key: Key('pet-notes-waiting'),
                  style: TextStyle(
                    color: ReportColors.muted,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ],
              for (final tip in notes.tips) ...[
                const SizedBox(height: 12),
                _tip(tip),
              ],
              if (notes.source == 'llm') ...[
                const SizedBox(height: 18),
                const Text(
                  kNotesAiLine,
                  key: Key('pet-notes-ai-line'),
                  style: TextStyle(color: ReportColors.dim, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tip(PetNote tip) {
    return Container(
      key: Key('pet-notes-tip-${tip.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
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
              key: Key(tip.isNote ? 'pet-notes-kind-note' : 'pet-notes-kind-tip'),
              size: 18,
              color: ReportColors.gold,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tip.text,
                  style: const TextStyle(
                    color: ReportColors.soft,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                if (plan != null && kTipToPlan[tip.id] != null)
                  _AddToPlan(plan: plan!, planId: kTipToPlan[tip.id]!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 建議底下那一顆。加進去的是**清單上那一句**（研究文件審過的），不是 AI 改寫的那句——
/// AI 那句是寵物口吻、每晚不一樣，放進每天的清單會變成一句看不懂的話。
class _AddToPlan extends StatefulWidget {
  final PlanStore plan;
  final String planId;
  const _AddToPlan({required this.plan, required this.planId});

  @override
  State<_AddToPlan> createState() => _AddToPlanState();
}

class _AddToPlanState extends State<_AddToPlan> {
  @override
  void initState() {
    super.initState();
    widget.plan.addListener(_changed);
    if (!widget.plan.loaded) widget.plan.load();
  }

  @override
  void dispose() {
    widget.plan.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = suggestionById(widget.planId);
    if (s == null || !widget.plan.loaded) return const SizedBox.shrink();
    final inPlan = widget.plan.contains(s.id);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: inPlan
          ? const Row(
              key: Key('pet-notes-in-plan'),
              children: [
                Icon(Icons.check_rounded, size: 16, color: ReportColors.down),
                SizedBox(width: 4),
                Text('In your plan', style: TextStyle(color: ReportColors.muted, fontSize: 12.5)),
              ],
            )
          : TextButton.icon(
              key: Key('pet-notes-add-${widget.planId}'),
              onPressed: () => widget.plan.add(PlanItem.fromSuggestion(s)),
              style: TextButton.styleFrom(
                foregroundColor: ReportColors.accent,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add to my plan', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
    );
  }
}
