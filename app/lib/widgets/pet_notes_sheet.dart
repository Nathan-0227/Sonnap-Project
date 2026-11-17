import 'package:flutter/material.dart';

import '../screens/morning_report_screen.dart' show reportDateTitle;
import '../services/pet_notes.dart';
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
Future<void> showPetNotes(
  BuildContext context, {
  required PetNotes notes,
  String? mood,
}) {
  return showReportSheet<void>(
    context: context,
    builder: (context) => ReportFont(
      child: PetNotesView(notes: notes, mood: mood),
    ),
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
  const PetNotesView({super.key, required this.notes, this.mood});

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
            child: Text(
              tip.text,
              style: const TextStyle(
                color: ReportColors.soft,
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
