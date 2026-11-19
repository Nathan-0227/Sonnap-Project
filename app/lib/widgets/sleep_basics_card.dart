import 'package:flutter/material.dart';

import '../content/sleep_basics.dart';

/// 「Sleep basics」小知識（2026-11-19 從舊 Insights 搬到助理頁，預設收合）。
///
/// 內容照 `content/sleep_basics.dart` 一字不改；每一條都附出處（第一作者＋年份，
/// `sleep_basics_test.dart` 對著已驗證的書目檢查）。
class SleepBasicsCard extends StatelessWidget {
  final bool initiallyExpanded;
  const SleepBasicsCard({super.key, this.initiallyExpanded = false});

  @override
  Widget build(BuildContext context) {
    // ⚠️ 底色要用 Material，不能用 Container 的 decoration：ExpansionTile 的點擊波紋
    //    畫在最近的 Material 上，被有底色的盒子蓋住時 Flutter 會直接丟錯（測試裡踩到）
    return Material(
      key: const Key('sleep-basics-card'),
      color: const Color(0xFF0A2142),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // 拿掉 ExpansionTile 展開時上下那兩條分隔線
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          iconColor: Colors.white70,
          collapsedIconColor: Colors.white70,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: const Icon(Icons.menu_book_rounded, color: Color(0xFF7657FF)),
          title: const Text(
            'Sleep basics',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
          ),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final b in kSleepBasics) ...[
              Text(
                b.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                b.summary,
                style: const TextStyle(color: Color(0xFF9FB3D1), fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 3),
              Text(
                b.source,
                style: const TextStyle(color: Color(0xFF7F92B0), fontSize: 10),
              ),
              if (b != kSleepBasics.last) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}
