import 'package:flutter/material.dart';

import '../services/morning_rating.dart';
import '../theme/report_style.dart';
import '../widgets/sleepy_pet.dart';

/// 起床自評卡（2026-11-12 定案，版面照示意圖）。
///
/// 滑完 Slide to get up（或 I already got up）就跳出，**在看到分數之前**——
/// 先看到分數的話，自評會被分數帶著走。首頁起床 6 小時內也能從小卡補填。
///
/// ⚠️ 不進分數、不給 XP、不給好友看；這個畫面也不顯示任何分數。
/// ⚠️ Skip 永遠可以按，不擋報告。
///
/// 回傳存下來的 [MorningRating]；按 Skip 回 null。
class RestedScreen extends StatefulWidget {
  /// 那一晚（起床日）。
  final String date;

  /// 按 Out of bed 的時刻。背景淡淡顯示它，也拿來算「起床後幾分鐘才填」。
  final DateTime? wakeAt;

  final MorningRatingStore store;
  final RestedSender? sender;
  final DateTime Function() clock;

  /// 補填時帶入之前填過的（目前補填只在沒填過時出現，所以通常是 null）。
  final MorningRating? initial;

  const RestedScreen({
    super.key,
    required this.date,
    required this.store,
    this.wakeAt,
    this.sender,
    this.clock = DateTime.now,
    this.initial,
  });

  @override
  State<RestedScreen> createState() => _RestedScreenState();
}

class _RestedScreenState extends State<RestedScreen> {
  late int? _picked = widget.initial?.rested;
  late final Set<String> _tags = {...?widget.initial?.tags};
  bool _saving = false;

  Future<void> _save() async {
    final picked = _picked;
    if (picked == null || _saving) return;
    setState(() => _saving = true);
    final rating = MorningRating(
      date: widget.date,
      rested: picked,
      tags: [
        for (final (id, _) in kRestedTags)
          if (_tags.contains(id)) id,
      ],
      minutesAfterWake: minutesAfterWake(widget.wakeAt, widget.clock()),
    );
    // ⚠️ 等它送完（最多幾秒）再進報告：AI 那段要讀得到「你覺得怎樣」。
    //    送不出去也照樣往下走，下次開首頁會補送。
    await widget.store.save(rating, widget.sender);
    if (mounted) Navigator.of(context).pop(rating);
  }

  @override
  Widget build(BuildContext context) {
    final wake = widget.wakeAt;
    return ReportFont(
      child: Scaffold(
        backgroundColor: ReportColors.bgTop,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const ReportBackground(),
            // 背景淡淡的「早安＋時間＋睡著的小狗」：示意圖的位置
            SafeArea(
              child: Opacity(
                opacity: 0.35,
                child: Padding(
                  padding: const EdgeInsets.only(top: 52),
                  child: Column(
                    children: [
                      const Text(
                        'Good morning',
                        style: TextStyle(color: ReportColors.muted, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      if (wake != null)
                        Text(
                          reportClock(wake),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 72,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 2,
                            height: 1,
                          ),
                        ),
                      const SizedBox(height: 10),
                      const SleepingPet(size: 150),
                    ],
                  ),
                ),
              ),
            ),
            const ColoredBox(color: Color(0x8C05091A)),
            Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.92,
                ),
                child: _sheet(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheet() {
    return Container(
      key: const Key('rested-sheet'),
      width: double.infinity,
      decoration: const BoxDecoration(
        color: ReportColors.sheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: ReportColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                kRestedQuestion,
                key: Key('rested-question'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Before you see your score — just how you feel.',
                textAlign: TextAlign.center,
                style: TextStyle(color: ReportColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in kRestedLabels.entries)
                    Expanded(child: _face(entry.key, entry.value)),
                ],
              ),
              const SizedBox(height: 18),
              const Text.rich(
                TextSpan(
                  text: 'What might have affected it? ',
                  children: [
                    TextSpan(
                      text: '(optional)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: ReportColors.faint,
                      ),
                    ),
                  ],
                ),
                style: TextStyle(
                  color: ReportColors.soft,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (id, text) in kRestedTags) _tag(id, text),
                ],
              ),
              const SizedBox(height: 22),
              FilledButton(
                key: const Key('rested-save'),
                onPressed: _picked == null || _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: ReportColors.purple,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.white.withValues(alpha: 0.12),
                  disabledForegroundColor: ReportColors.dim,
                  minimumSize: const Size.fromHeight(54),
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(
                    fontFamily: kReportFont,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save'),
              ),
              const SizedBox(height: 6),
              TextButton(
                key: const Key('rested-skip'),
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: ReportColors.muted,
                  minimumSize: const Size.fromHeight(44),
                  textStyle: const TextStyle(
                    fontFamily: kReportFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Skip'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _face(int value, String label) {
    final selected = _picked == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        child: InkWell(
          key: Key('rested-face-$value'),
          borderRadius: BorderRadius.circular(18),
          onTap: _saving ? null : () => setState(() => _picked = value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            constraints: const BoxConstraints(minHeight: 112),
            padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
            decoration: BoxDecoration(
              color: selected ? const Color(0x388B6DFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? ReportColors.lilac : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              children: [
                AnimatedScale(
                  scale: selected ? 1.12 : 1.0,
                  duration: const Duration(milliseconds: 150),
                  child: Opacity(
                    opacity: selected ? 1 : 0.8,
                    child: Image.asset(
                      restedFaceAsset(value),
                      width: 54,
                      height: 54,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const SizedBox(
                        width: 54,
                        height: 54,
                        child: Icon(Icons.sentiment_satisfied_rounded,
                            color: ReportColors.lilac, size: 40),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? Colors.white : ReportColors.muted,
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tag(String id, String text) {
    final on = _tags.contains(id);
    return Semantics(
      toggled: on,
      child: InkWell(
        key: Key('rested-tag-$id'),
        borderRadius: BorderRadius.circular(18),
        onTap: _saving
            ? null
            : () => setState(() => on ? _tags.remove(id) : _tags.add(id)),
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: on ? ReportColors.purple : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: on ? ReportColors.purple : const Color(0x73B9A6FF),
              width: 1.5,
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: on ? Colors.white : ReportColors.soft,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
