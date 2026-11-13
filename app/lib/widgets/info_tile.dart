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

  /// 大數字下面的一行小字（例如攝影機的「跟你平常比」，照抄後端）。
  final String? note;

  /// 「跟上一晚比」那一行與它的顏色（上升紅、下降綠，只代表方向）。
  final (String, Color)? compare;

  /// true：有卡片外框，但高度照內容（首頁兩欄左邊一格一格往下疊，2026-11-13）。
  final bool compact;

  const InfoTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    this.missingNote = 'No watch data',
    this.note,
    this.compare,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final parts = value;
    if (compact) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: sonnapCardDecoration(),
        child: _flat(parts),
      );
    }
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
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: iconColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 卡片高度固定，下半部放不下時整塊等比縮小，不溢出。
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _body(parts),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// compact 的內容：標題、大字（太寬才縮）、小字各一行（超出就截掉），不溢出也不撐高。
  Widget _flat(List<(String, String)>? parts) {
    final body = _body(parts);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, color: iconColor, size: 17),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: iconColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: body.first,
        ),
        for (final line in body.skip(1))
          DefaultTextStyle.merge(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: line,
          ),
      ],
    );
  }

  List<Widget> _body(List<(String, String)>? parts) {
    if (parts == null) {
      return [
        const Text(
          '—',
          softWrap: false,
          style: TextStyle(
            color: SonnapColors.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          missingNote,
          style: const TextStyle(color: SonnapColors.textMuted, fontSize: 11),
        ),
      ];
    }
    return [
      // 不折行：放在 FittedBox 裡，量高度時才不會被當成兩行（兩欄要量高度對齊）
      Text.rich(
        softWrap: false,
        TextSpan(
          children: [
            for (final (number, unit) in parts) ...[
              TextSpan(
                text: number,
                style: const TextStyle(
                  color: SonnapColors.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              TextSpan(
                text: unit.isEmpty ? ' ' : ' $unit ',
                style: const TextStyle(
                  color: SonnapColors.textMuted,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
      if (note != null)
        Text(
          note!,
          style: const TextStyle(color: SonnapColors.textMuted, fontSize: 11),
        ),
      if (compare != null)
        Text(
          compare!.$1,
          key: const Key('tile-compare'),
          style: TextStyle(
            color: compare!.$2,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
    ];
  }
}
