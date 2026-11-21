import 'package:flutter/material.dart';

import '../services/insights_periods.dart' show median;

/// 分數頁、深睡頁共用的「這一週」（2026-11-21）：這一晚往回 7 個日曆晚上、Usually＝有資料那幾晚的
/// **中間值**（平均會被一兩晚拉走，同 heart_rate_sheet／steps_sheet）、跟再往前 7 晚的中間值比。
/// 沒資料的晚上是 null，寫「—」、**不算進中間值**、不畫成 0。純函式。
class MedianWeek {
  /// 舊 → 新，固定 7 格：(日期, 值或 null)
  final List<(String, double?)> nights;
  final double? usual;
  final double? previousUsual;

  const MedianWeek(this.nights, this.usual, this.previousUsual);

  int get nightsWithData => nights.where((n) => n.$2 != null).length;

  /// 這一週減上一週；任一邊沒有 → null。
  double? get change =>
      usual == null || previousUsual == null ? null : usual! - previousUsual!;
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

MedianWeek medianWeek(Map<String, double> values, String endDate) {
  final end = DateTime.parse(endDate);
  List<(String, double?)> window(int offset) => [
    for (var i = 6; i >= 0; i--)
      () {
        // 用 UTC 日期加減，不受夏令時間影響（同 sleepWeek）
        final key = _iso(DateTime.utc(end.year, end.month, end.day - offset - i));
        return (key, values[key]);
      }(),
  ];
  final now = window(0);
  return MedianWeek(
    now,
    median(now.map((n) => n.$2)),
    median(window(7).map((n) => n.$2)),
  );
}

/// 「6 of 7 nights with data」。
String medianWeekCountLine(MedianWeek w) => w.nightsWithData == 7
    ? 'all 7 nights'
    : '${w.nightsWithData} of 7 nights with data';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// 7 欄膠囊長條：底槽到頂、值從底下長上來、數字寫在柱頂；沒資料寫「—」。
/// 這一晚（最右邊）亮一點、字粗一點。顏色由呼叫端給（分數頁照每晚的等級、深睡頁一個顏色）。
class WeekBars extends StatelessWidget {
  final List<(String, double?)> nights;
  final double max;
  final Color Function(int index) colorOf;
  final String Function(double value) label;

  const WeekBars({
    super.key,
    required this.nights,
    required this.max,
    required this.colorOf,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 168,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < nights.length; i++)
            Expanded(child: _column(i, i == nights.length - 1)),
        ],
      ),
    );
  }

  Widget _column(int i, bool last) {
    final (date, value) = nights[i];
    final d = DateTime.parse(date);
    final color = colorOf(i);
    return Column(
      key: Key('week-bar-$date'),
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              const labelH = 18.0;
              final track = c.maxHeight - labelH;
              final h = value == null
                  ? 0.0
                  : (track * (value.clamp(0, max) / max)).clamp(10.0, track);
              return Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  // 底槽
                  Positioned(
                    bottom: 0,
                    top: labelH,
                    child: Container(
                      width: 22,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                  ),
                  if (value != null) ...[
                    Positioned(
                      bottom: 0,
                      child: Container(
                        width: 22,
                        height: h,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: last ? 1 : 0.78),
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: h + 4,
                      child: Text(
                        label(value),
                        softWrap: false,
                        style: TextStyle(
                          color: last ? Colors.white : const Color(0xFFB7BEDC),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ] else
                    const Positioned(
                      bottom: 6,
                      child: Text(
                        '—',
                        style: TextStyle(
                          color: Color(0xFF7F87AE),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _weekdays[d.weekday - 1],
          softWrap: false,
          style: TextStyle(
            color: last ? Colors.white : const Color(0xFF9FA7CC),
            fontSize: 11,
            fontWeight: last ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
        Text(
          '${d.month}/${d.day}',
          softWrap: false,
          style: const TextStyle(color: Color(0xFF7F87AE), fontSize: 9),
        ),
      ],
    );
  }
}
