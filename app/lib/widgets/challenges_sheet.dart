import 'package:flutter/material.dart';

import '../services/challenges_service.dart';
import '../theme/report_style.dart';
import 'report_sheet.dart';

/// Insights 最底下那一行「Challenges」，點開是挑戰清單（2026-11-19 從舊 Insights 頁搬來）。
///
/// ⚠️ 三條紅線照舊，違反了都不會報錯：
///   1. **一格數字都不算**：進度、達成與否、那句 detail 全部照抄 `behavior/challenges.py`
///   2. **資料不足是第三種狀態，不是 0%**：不畫進度條，寫 not enough data yet
///   3. **recorded nights 要當分母顯示**：沒有它「達成 3 晚」看不出是 3/3 還是 3/14
class ChallengesRow extends StatelessWidget {
  final ChallengesResult? result;
  const ChallengesRow({super.key, required this.result});

  /// 拿不到、沒有挑戰 → 整行不出現（不畫一個空的）。
  static bool shows(ChallengesResult? r) =>
      r != null && r.status == ChallengesStatus.ok && r.challenges.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (!shows(r)) return const SizedBox.shrink();
    final done = r!.challenges.where((c) => c.state == ChallengeState.completed).length;
    return Material(
      key: const Key('challenges-row'),
      color: Colors.white.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: ReportColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => showChallengesSheet(context, r),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.flag_rounded, color: ReportColors.gold, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Challenges',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      // 只數後端判「達成」的，不自己判「快達成」
                      '$done of ${r.challenges.length} completed',
                      key: const Key('challenges-row-summary'),
                      style: const TextStyle(color: ReportColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: ReportColors.accent),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showChallengesSheet(BuildContext context, ChallengesResult result) {
  return showReportSheet<void>(
    context: context,
    builder: (context) => Container(
      key: const Key('challenges-sheet'),
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
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
          child: ChallengesList(result: result),
        ),
      ),
    ),
  );
}

/// 挑戰清單本體（詳細頁裡那一塊）。
class ChallengesList extends StatelessWidget {
  final ChallengesResult result;
  const ChallengesList({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Challenges',
          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        const Text(
          'Every target here is a behaviour you control - when you put the '
          'phone down or get up - never a sleep outcome.',
          style: TextStyle(color: ReportColors.muted, fontSize: 12.5, height: 1.4),
        ),
        const SizedBox(height: 16),
        for (final c in result.challenges) ...[
          ChallengeCard(challenge: c),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// 一個挑戰的卡片（Insights 的清單與睡眠計畫頁共用）。
/// 一個挑戰的卡片（Insights 的清單與睡眠計畫頁共用）。
class ChallengeCard extends StatelessWidget {
  final ChallengeProgress challenge;
  const ChallengeCard({super.key, required this.challenge});

  @override
  Widget build(BuildContext context) {
    final c = challenge;
    final enough = c.state != ChallengeState.insufficientData;
    final done = c.state == ChallengeState.completed;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ReportColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ReportColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                done
                    ? Icons.check_circle_rounded
                    : enough
                        ? Icons.radio_button_unchecked_rounded
                        : Icons.help_outline_rounded,
                size: 18,
                color: done ? ReportColors.down : (enough ? ReportColors.gold : ReportColors.dim),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              // ⚠️ 分母
              Text(
                '${c.recordedNights}/${c.windowDays} nights',
                style: const TextStyle(color: ReportColors.faint, fontSize: 11.5),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _bar(c),
          const SizedBox(height: 8),
          Text(
            // ⚠️ 整句都是後端寫的，不要在這裡重組
            c.detail,
            style: TextStyle(
              color: enough ? ReportColors.soft : ReportColors.dim,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  /// ⚠️ 資料不足時不畫進度條。不需要為 lower_is_better 反轉：後端的 progress 已經是越高越好。
  Widget _bar(ChallengeProgress c) {
    final progress = c.progress;
    if (progress == null) {
      return Row(
        children: [
          Expanded(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'not enough data yet',
            style: TextStyle(color: ReportColors.dim, fontSize: 11.5),
          ),
        ],
      );
    }
    final done = c.state == ChallengeState.completed;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(
                done ? ReportColors.down : ReportColors.lilac,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${(progress * 100).round()}%',
          style: TextStyle(
            color: done ? ReportColors.down : ReportColors.soft,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
