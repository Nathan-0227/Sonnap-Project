// 一週睡眠（2026-11-14 使用者定）：早晨報告的 Time asleep 與首頁的 Sleep 小卡點開都是這一張。
//
// - 一週＝**這一晚往回 7 晚**（日曆上的 7 個晚上，不是「最近 7 個有資料的晚上」）
// - 沒資料的晚上**跳過**：長條空著寫「—」，平均只算有資料的晚上，並寫出是幾晚
//   （沒戴錶不等於睡了 0 小時）
// - 睡眠目標畫一條虛線，**不依達標變色**（好壞只有後端能判斷）
import 'package:flutter/material.dart';

import '../services/night_compare.dart';

/// 日曆上的一個晚上。[minutes] 是 null＝那一晚沒資料。
class SleepWeekNight {
  final String date; // yyyy-MM-dd
  final double? minutes;
  const SleepWeekNight(this.date, this.minutes);
}

class SleepWeek {
  final List<SleepWeekNight> nights; // 舊 → 新，固定 7 格
  final double? averageMinutes; // 沒有任何一晚有資料 → null
  final int nightsWithData;
  const SleepWeek(this.nights, this.averageMinutes, this.nightsWithData);
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// [endDate] 那一晚往回共 [days] 晚；[series] 裡沒有的晚上是 null。純函式。
SleepWeek sleepWeek(List<NightValue> series, String endDate, {int days = 7}) {
  final end = DateTime.parse(endDate);
  final byDate = {for (final n in series) n.date: n.value};
  final nights = <SleepWeekNight>[
    for (var i = days - 1; i >= 0; i--)
      () {
        // 用 UTC 日期加減，不受夏令時間影響
        final d = DateTime.utc(end.year, end.month, end.day - i);
        final key = _iso(d);
        return SleepWeekNight(key, byDate[key]);
      }(),
  ];
  final have = [
    for (final n in nights)
      if (n.minutes != null) n.minutes!,
  ];
  final avg = have.isEmpty ? null : have.reduce((a, b) => a + b) / have.length;
  return SleepWeek(nights, avg, have.length);
}

/// 「Average 6h 42m」底下那一行：幾晚有資料。
String sleepWeekCountLine(SleepWeek w) => w.nightsWithData == w.nights.length
    ? 'all ${w.nights.length} nights'
    : '${w.nightsWithData} of ${w.nights.length} nights with data';

const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

Future<void> showSleepWeekSheet(
  BuildContext context, {
  required String title,
  required List<NightValue> series,
  required String endDate,
  int? goalMinutes,
}) {
  final week = sleepWeek(series, endDate);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1B2350),
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SleepWeekView(title: title, week: week, goalMinutes: goalMinutes),
    ),
  );
}

class SleepWeekView extends StatelessWidget {
  final String title;
  final SleepWeek week;
  final int? goalMinutes;

  const SleepWeekView({
    super.key,
    required this.title,
    required this.week,
    this.goalMinutes,
  });

  static const _bar = Color(0xFFB9A6FF);
  static const _soft = Color(0xB3FFFFFF);

  @override
  Widget build(BuildContext context) {
    final avg = week.averageMinutes;
    final goal = goalMinutes != null && goalMinutes! > 0
        ? goalMinutes!.toDouble()
        : null;
    var top = goal ?? 0;
    for (final n in week.nights) {
      if (n.minutes != null && n.minutes! > top) top = n.minutes!;
    }
    top = top <= 0 ? 1 : top * 1.12;

    return Padding(
      key: const Key('sleep-week-sheet'),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title · last 7 nights',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          if (avg == null)
            const Text(
              'No watch data this week',
              key: Key('sleep-week-empty'),
              style: TextStyle(color: _soft, fontSize: 14),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Text(
                  'Average ',
                  style: TextStyle(color: _soft, fontSize: 14),
                ),
                Text(
                  formatMinutes(avg),
                  key: const Key('sleep-week-average'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            Text(
              sleepWeekCountLine(week),
              key: const Key('sleep-week-count'),
              style: const TextStyle(color: _soft, fontSize: 12),
            ),
          ],
          if (goal != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                CustomPaint(size: const Size(20, 1), painter: _DashPainter()),
                const SizedBox(width: 6),
                Text(
                  '${formatMinutes(goal)} goal',
                  key: const Key('sleep-week-goal-label'),
                  style: const TextStyle(color: _soft, fontSize: 12),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 170,
            child: LayoutBuilder(
              builder: (context, box) {
                const labelTop = 16.0; // 長條上方的數字
                const labelBottom = 34.0; // 底下的星期＋日期
                final chartH = box.maxHeight - labelTop - labelBottom;
                double y(double v) => labelTop + chartH * (1 - v / top);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (goal != null)
                      Positioned(
                        key: const Key('sleep-week-goal'),
                        left: 0,
                        right: 0,
                        top: y(goal),
                        child: IgnorePointer(
                          child: CustomPaint(
                            size: Size(box.maxWidth, 1),
                            painter: _DashPainter(),
                          ),
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final n in week.nights)
                          Expanded(
                            child: _NightBar(
                              night: n,
                              isLast: n == week.nights.last,
                              barHeight: n.minutes == null
                                  ? 0
                                  : chartH * (n.minutes! / top),
                              labelBottom: labelBottom,
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NightBar extends StatelessWidget {
  final SleepWeekNight night;
  final bool isLast;
  final double barHeight;
  final double labelBottom;

  const _NightBar({
    required this.night,
    required this.isLast,
    required this.barHeight,
    required this.labelBottom,
  });

  @override
  Widget build(BuildContext context) {
    final d = DateTime.parse(night.date);
    final m = night.minutes;
    return Padding(
      key: Key('sleep-week-bar-${night.date}'),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FittedBox(
            child: Text(
              m == null ? '—' : formatMinutes(m),
              style: TextStyle(
                color: m == null
                    ? const Color(0x66FFFFFF)
                    : const Color(0xCCFFFFFF),
                fontSize: 10,
                fontWeight: isLast ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Container(
            height: barHeight,
            decoration: BoxDecoration(
              // 這一晚亮一點、其他淡一點——只標「是哪一晚」，不分好壞
              color: SleepWeekView._bar.withValues(alpha: isLast ? 1 : 0.55),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          SizedBox(
            height: labelBottom,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  _weekdays[d.weekday - 1],
                  style: const TextStyle(
                    color: Color(0x99FFFFFF),
                    fontSize: 10,
                  ),
                ),
                Text(
                  '${d.day}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: isLast ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x99FFFFFF)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, 0), Offset(x + 4, 0), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
