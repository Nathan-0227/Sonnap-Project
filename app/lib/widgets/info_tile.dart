import 'package:flutter/material.dart';

import '../theme/sonnap_colors.dart';

/// 首頁那四張數據卡共用的樣式：左上小圖示＋標題，下面一個大數字＋單位。
///
/// ⚠️ 沒有數據時傳 [value] = null：顯示「—」與 [missingNote]，**不畫成 0**——
///    「0 min」會被讀成「整晚沒睡著」，真相是沒量到。
class InfoTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;

  /// 大數字的部分，例如 [('7', 'hr'), ('12', 'min')]。null = 沒有數據。
  final List<(String, String)>? value;
  final String missingNote;

  const InfoTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    this.missingNote = 'No watch data',
  });

  @override
  Widget build(BuildContext context) {
    final parts = value;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: sonnapCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: iconColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (parts == null) ...[
            const Text('—',
                style: TextStyle(
                    color: SonnapColors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w800)),
            Text(missingNote,
                style: const TextStyle(
                    color: SonnapColors.textMuted, fontSize: 11)),
          ] else
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(TextSpan(children: [
                for (final (number, unit) in parts) ...[
                  TextSpan(
                      text: number,
                      style: const TextStyle(
                          color: SonnapColors.textPrimary,
                          fontSize: 26,
                          fontWeight: FontWeight.w800)),
                  TextSpan(
                      text: unit.isEmpty ? ' ' : ' $unit ',
                      style: const TextStyle(
                          color: SonnapColors.textMuted, fontSize: 13)),
                ],
              ])),
            ),
        ],
      ),
    );
  }
}
