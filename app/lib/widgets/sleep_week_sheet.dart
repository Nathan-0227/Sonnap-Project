// 一週睡眠（2026-11-14 使用者定，參考圖：膠囊長條＋左邊時數刻度＋底下圓環）：
// 早晨報告的 Time asleep 與首頁的 Sleep 小卡點開都是這一張。
//
// - 一週＝**這一晚往回 7 晚**（日曆上的 7 個晚上，不是「最近 7 個有資料的晚上」）
// - 沒資料的晚上**跳過**：只剩空的底槽，平均只算有資料的晚上，並寫出是幾晚
//   （沒戴錶不等於睡了 0 小時）
// - 睡眠目標畫一條虛線，**不依達標變色**（好壞只有後端能判斷）
// - 參考圖底下那句「Your sleep improved by 6%」**不照做**：improved 是判斷。
//   改成只寫事實——圓環＝平均÷目標，旁邊「↑ 23m vs the week before」，箭頭只代表方向
//   （上升紅、下降綠，同首頁「跟上一晚比」）
// - 標題跟外面那張卡一樣：同一個圖示、同一個顏色（使用者定）
import 'dart:math' as math;

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

  /// 再往前那 7 晚的平均（一樣只算有資料的晚上）；那一週一晚都沒有 → null。
  final double? previousAverageMinutes;

  const SleepWeek(
    this.nights,
    this.averageMinutes,
    this.nightsWithData, [
    this.previousAverageMinutes,
  ]);

  /// 這一週減上一週（分鐘）；任一邊沒有 → null。
  double? get change => averageMinutes == null || previousAverageMinutes == null
      ? null
      : averageMinutes! - previousAverageMinutes!;
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// [endDate] 那一晚往回共 [days] 晚；[series] 裡沒有的晚上是 null。純函式。
SleepWeek sleepWeek(List<NightValue> series, String endDate, {int days = 7}) {
  final end = DateTime.parse(endDate);
  final byDate = {for (final n in series) n.date: n.value};
  List<SleepWeekNight> window(int endOffset) => [
    for (var i = days - 1; i >= 0; i--)
      () {
        // 用 UTC 日期加減，不受夏令時間影響
        final d = DateTime.utc(end.year, end.month, end.day - endOffset - i);
        final key = _iso(d);
        return SleepWeekNight(key, byDate[key]);
      }(),
  ];
  double? avg(List<SleepWeekNight> ns) {
    final have = [
      for (final n in ns)
        if (n.minutes != null) n.minutes!,
    ];
    return have.isEmpty ? null : have.reduce((a, b) => a + b) / have.length;
  }

  final nights = window(0);
  return SleepWeek(
    nights,
    avg(nights),
    nights.where((n) => n.minutes != null).length,
    avg(window(days)),
  );
}

/// 幾晚有資料。
String sleepWeekCountLine(SleepWeek w) => w.nightsWithData == w.nights.length
    ? 'all ${w.nights.length} nights'
    : '${w.nightsWithData} of ${w.nights.length} nights with data';

/// 「↑ 23m vs the week before」；只代表方向。
String? sleepWeekChangeLine(SleepWeek w) {
  final c = w.change;
  if (c == null) return null;
  final r = c.round();
  if (r == 0) return '= same as the week before';
  return '${r > 0 ? '↑' : '↓'} ${formatMinutes(r.abs().toDouble())} vs the week before';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

Future<void> showSleepWeekSheet(
  BuildContext context, {
  required String title,
  required IconData icon,
  required Color color,
  required List<NightValue> series,
  required String endDate,
  int? goalMinutes,
  String? fontFamily,
}) {
  final week = sleepWeek(series, endDate);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    // 彈窗掛在最外層，不會繼承報告的字型——外面那張卡用什麼字，這裡就用什麼字
    builder: (context) => DefaultTextStyle.merge(
      style: TextStyle(fontFamily: fontFamily),
      child: SleepWeekView(
        title: title,
        icon: icon,
        color: color,
        week: week,
        goalMinutes: goalMinutes,
      ),
    ),
  );
}

class SleepWeekView extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final SleepWeek week;
  final int? goalMinutes;

  const SleepWeekView({
    super.key,
    required this.title,
    required this.week,
    this.icon = Icons.nightlight_round,
    this.color = const Color(0xFFB9A6FF),
    this.goalMinutes,
  });

  static const _soft = Color(0xB3FFFFFF);

  @override
  Widget build(BuildContext context) {
    final avg = week.averageMinutes;
    final goal = goalMinutes != null && goalMinutes! > 0
        ? goalMinutes!.toDouble()
        : null;
    final change = sleepWeekChangeLine(week);
    final c = week.change;
    final changeColor = c == null || c.round() == 0
        ? kDeltaFlat
        : (c > 0 ? kDeltaUp : kDeltaDown);

    return Container(
      key: const Key('sleep-week-sheet'),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF151A3C), Color(0xFF1B1F48), Color(0xFF3A2E6E)],
          stops: [0, 0.6, 1],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 標題：跟外面那張卡同一個圖示、同一個顏色
              Row(
                children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      title,
                      key: const Key('sleep-week-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Spacer(),
                  const Text(
                    'Last 7 nights',
                    softWrap: false,
                    style: TextStyle(color: _soft, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 230,
                child: _WeekChart(week: week, goal: goal, color: color),
              ),
              if (goal != null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    CustomPaint(
                      size: const Size(20, 1),
                      painter: _DashPainter(),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${formatMinutes(goal)} goal',
                      key: const Key('sleep-week-goal-label'),
                      style: const TextStyle(color: _soft, fontSize: 11),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              if (avg == null)
                const Text(
                  'No watch data this week',
                  key: Key('sleep-week-empty'),
                  style: TextStyle(color: _soft, fontSize: 14),
                )
              else
                Row(
                  children: [
                    if (goal != null) ...[
                      _GoalRing(fraction: avg / goal, color: color),
                      const SizedBox(width: 16),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                                  fontSize: 24,
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
                          if (change != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              change,
                              key: const Key('sleep-week-change'),
                              style: TextStyle(
                                color: changeColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 左邊時數刻度＋七根膠囊（底槽到頂、亮的部分＝睡了多久）。
class _WeekChart extends StatelessWidget {
  final SleepWeek week;
  final double? goal;
  final Color color;
  const _WeekChart({
    required this.week,
    required this.goal,
    required this.color,
  });

  static const double _axisW = 30;
  static const double _labelH = 26; // 底下的星期

  @override
  Widget build(BuildContext context) {
    // 刻度：每 2 小時一格，至少到 12 小時（參考圖），睡更久就往上加
    var most = goal ?? 0;
    for (final n in week.nights) {
      if (n.minutes != null) most = math.max(most, n.minutes!);
    }
    final topHours = math.max(12, ((most / 60) / 2).ceil() * 2);
    final top = topHours * 60.0;

    return LayoutBuilder(
      builder: (context, box) {
        final chartH = box.maxHeight - _labelH;
        double y(double minutes) => chartH * (1 - minutes / top);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var h = 0; h <= topHours; h += 2)
              Positioned(
                left: 0,
                width: _axisW - 6,
                top: y(h * 60.0) - 7,
                child: Text(
                  '$h h',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Color(0x99FFFFFF),
                    fontSize: 10,
                  ),
                ),
              ),
            Positioned(
              left: _axisW,
              right: 0,
              top: 0,
              bottom: 0,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final n in week.nights)
                    Expanded(
                      child: _Capsule(
                        night: n,
                        isLast: identical(n, week.nights.last),
                        fill: n.minutes == null
                            ? 0
                            : (chartH * n.minutes! / top).clamp(0.0, chartH),
                        chartH: chartH,
                        labelH: _labelH,
                        color: color,
                      ),
                    ),
                ],
              ),
            ),
            if (goal != null)
              Positioned(
                key: const Key('sleep-week-goal'),
                left: _axisW,
                right: 0,
                top: y(goal!),
                child: IgnorePointer(
                  child: CustomPaint(
                    size: Size(box.maxWidth - _axisW, 1),
                    painter: _DashPainter(),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Capsule extends StatelessWidget {
  final SleepWeekNight night;
  final bool isLast;
  final double fill;
  final double chartH;
  final double labelH;
  final Color color;

  const _Capsule({
    required this.night,
    required this.isLast,
    required this.fill,
    required this.chartH,
    required this.labelH,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final d = DateTime.parse(night.date);
    final m = night.minutes;
    return Semantics(
      label:
          '${_weekdays[d.weekday - 1]} ${d.day}: '
          '${m == null ? 'no data' : formatMinutes(m)}',
      child: Padding(
        key: Key('sleep-week-bar-${night.date}'),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          children: [
            SizedBox(
              height: chartH,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  // 底槽：一直到頂
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0x1FFFFFFF),
                        borderRadius: BorderRadius.circular(40),
                      ),
                    ),
                  ),
                  if (m != null)
                    Container(
                      key: Key('sleep-week-fill-${night.date}'),
                      height: fill,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(40),
                        // 這一晚亮一點——只標「是哪一晚」，不分好壞
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color.lerp(
                              color,
                              Colors.white,
                              0.45,
                            )!.withValues(alpha: isLast ? 1 : 0.8),
                            color.withValues(alpha: isLast ? 1 : 0.7),
                          ],
                        ),
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        '—',
                        style: TextStyle(
                          color: Color(0x66FFFFFF),
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: labelH,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FittedBox(
                  child: Text(
                    _weekdays[d.weekday - 1],
                    style: TextStyle(
                      color: isLast ? Colors.white : const Color(0xB3FFFFFF),
                      fontSize: 11,
                      fontWeight: isLast ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 平均÷目標的圓環（只是比例，不變色、不寫 reached）。
class _GoalRing extends StatelessWidget {
  final double fraction;
  final Color color;
  const _GoalRing({required this.fraction, required this.color});

  @override
  Widget build(BuildContext context) {
    final pct = (fraction * 100).round();
    return SizedBox(
      width: 70,
      height: 70,
      child: CustomPaint(
        painter: _RingPainter(fraction.clamp(0.0, 1.0), color),
        child: Center(
          child: Text(
            '$pct%',
            key: const Key('sleep-week-ring'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;
  _RingPainter(this.value, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    canvas.drawArc(
      r,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = const Color(0x24FFFFFF),
    );
    canvas.drawArc(
      r,
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: math.pi * 1.5,
          colors: [Color.lerp(color, Colors.white, 0.5)!, color],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.color != color;
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
