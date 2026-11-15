import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/yesterday_activity.dart';
import '../services/night_compare.dart' show kDeltaUp, kDeltaDown, kDeltaFlat;
import 'chart_probe.dart' show ProbeLayer;

// 早晨報告 Steps（2026-11-15 使用者定，照參考圖 Step Counter）：
// - **格子**：一圈弧線，填多少＝步數 ÷ 那天的目標；**超過就滿圈，不變色、不打勾、不寫 reached**
//   （步數只寫目標、不判斷）。中間人形＋大字步數，下面「Goal 9,540」、最底「3.7 km · 10 floors」。
// - **點開**上半「那一天」：大圓弧、「Goal set by Garmin, changes daily」（Garmin 每天自己調目標）、
//   距離／活動卡路里／活動時間／爬樓，**每個鐘頭走幾步**（24 根，點／滑看「14:00 · 1,230 steps」；
//   沒戴錶的鐘頭空著不畫、有戴走 0 步畫一條貼底細線；不寫加總——大數字已是官方總數；實抓 30 天兩者逐天相同）。
//   下半「這一週」：7 根長條＋每根上面那天自己的目標（小橫線），「Usually」＝中間值，
//   跟前一週比只代表方向（上升紅、下降綠）；**只用一個顏色**；0 步＝沒戴錶 → 「—」不算。
// - 不放 Move IQ（有自己的格子）、不放步頻配速（這支錶沒給）。

String stepsComma(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// 弧線填多少（0–1）。超過目標＝1（滿圈），沒有目標＝null（只畫軌道）。
double? stepsFraction(int? steps, int? goal) {
  if (steps == null || goal == null || goal <= 0) return null;
  return math.min(1.0, steps / goal);
}

/// 「3.7 km · 10 floors」；哪一項沒值就不寫。都沒有 → null。
String? stepsStatsLine(int? distanceM, double? floorsUp) {
  final parts = [
    if (distanceM != null) '${(distanceM / 1000).toStringAsFixed(1)} km',
    if (floorsUp != null) '${floorsUp.round()} floors',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// 每小時那根的泡泡：「14:00 · 1,230 steps」；沒戴錶「09:00 · no data」。
String stepsHourText(int hour, int? steps) {
  final h = '${hour.toString().padLeft(2, '0')}:00';
  if (steps == null) return '$h · no data';
  return '$h · ${stepsComma(steps)} ${steps == 1 ? 'step' : 'steps'}';
}

class StepsDay {
  final String date;

  /// null＝沒資料（沒戴錶：0 步也算沒資料）。
  final int? steps;
  final int? goal;
  const StepsDay(this.date, this.steps, this.goal);
}

class StepsWeek {
  final List<StepsDay> days; // 舊 → 新，固定 7 格（日曆上的 7 天）
  final double? usual; // 這 7 天有資料的中間值
  final double? previousUsual; // 再往前 7 天
  const StepsWeek(this.days, this.usual, this.previousUsual);

  int get daysWithData => days.where((d) => d.steps != null).length;
  double? get change =>
      usual == null || previousUsual == null ? null : usual! - previousUsual!;
}

double? _median(List<double> xs) {
  if (xs.isEmpty) return null;
  final s = [...xs]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// [endDate] 往回 7 天。⚠️ 0 步＝沒戴錶（Garmin 沒戴錶的那天回 0），當作沒資料。純函式。
StepsWeek stepsWeek(List<ActivityHistoryDay> history, String endDate) {
  final by = {for (final h in history) h.date: h};
  final end = DateTime.parse(endDate);
  List<StepsDay> window(int offset) => [
    for (var i = 6; i >= 0; i--)
      () {
        final key = _iso(
          DateTime.utc(end.year, end.month, end.day - offset - i),
        );
        final h = by[key];
        final s = h?.steps;
        return StepsDay(key, s == null || s <= 0 ? null : s, h?.stepGoal);
      }(),
  ];
  double? usual(List<StepsDay> ds) => _median([
    for (final d in ds)
      if (d.steps != null) d.steps!.toDouble(),
  ]);
  final days = window(0);
  return StepsWeek(days, usual(days), usual(window(7)));
}

String stepsUsualLine(StepsWeek w) =>
    'Usually ${stepsComma(w.usual!.round())} steps';

String stepsCountLine(StepsWeek w) => w.daysWithData == w.days.length
    ? 'all ${w.days.length} days'
    : '${w.daysWithData} of ${w.days.length} days with data';

/// 「↑ 1,200 steps vs the week before」；只代表方向，不判斷好壞。
String? stepsChangeLine(StepsWeek w) {
  final c = w.change;
  if (c == null) return null;
  final r = c.round();
  if (r == 0) return '= same as the week before';
  return '${r > 0 ? '↑' : '↓'} ${stepsComma(r.abs())} steps vs the week before';
}

/// 圓弧（格子與點開共用）：270°，從左下順時針到右下；填的部分＝[fraction]。
class StepsArc extends StatelessWidget {
  final int steps;
  final double? fraction;
  final Color color;
  final double stroke;
  final double numberSize;
  final Key? valueKey;
  const StepsArc({
    super.key,
    required this.steps,
    required this.fraction,
    required this.color,
    this.stroke = 9,
    this.numberSize = 24,
    this.valueKey,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ArcPainter(fraction, color, stroke),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(stroke + 6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.directions_walk_rounded,
                  color: color,
                  size: numberSize * 0.8,
                ),
                Text(
                  stepsComma(steps),
                  key: valueKey,
                  softWrap: false,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: numberSize,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                Text(
                  'steps',
                  softWrap: false,
                  style: TextStyle(
                    color: const Color(0xB3FFFFFF),
                    fontSize: numberSize * 0.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double? fraction;
  final Color color;
  final double stroke;
  _ArcPainter(this.fraction, this.color, this.stroke);

  static const _start = math.pi * 0.75; // 左下
  static const _sweep = math.pi * 1.5; // 270°

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2 - stroke / 2;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      _start,
      _sweep,
      false,
      p..color = const Color(0x26FFFFFF),
    );
    final f = fraction;
    if (f != null && f > 0) {
      canvas.drawArc(rect, _start, _sweep * f, false, p..color = color);
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.fraction != fraction || old.color != color;
}

Future<void> showStepsSheet(
  BuildContext context, {
  required YesterdayActivity day,
  required Color color,
  String? fontFamily,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => DefaultTextStyle.merge(
      style: TextStyle(fontFamily: fontFamily),
      child: StepsView(day: day, color: color),
    ),
  );
}

class StepsView extends StatelessWidget {
  final YesterdayActivity day;
  final Color color;
  const StepsView({
    super.key,
    required this.day,
    this.color = const Color(0xFFFFB37A),
  });

  static const _soft = Color(0xB3FFFFFF);

  @override
  Widget build(BuildContext context) {
    final y = day;
    final week = stepsWeek(y.history, y.date);
    final showWeek = week.daysWithData > 0;
    final change = showWeek ? stepsChangeLine(week) : null;
    final c = week.change?.round();
    final hours = y.stepsHourly;

    return Container(
      key: const Key('steps-sheet'),
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
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.directions_walk_rounded, size: 20, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Steps',
                      key: const Key('steps-title'),
                      style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (showWeek)
                    const Text(
                      'Last 7 days',
                      softWrap: false,
                      style: TextStyle(color: _soft, fontSize: 12),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              // ── 那一天 ──
              if (y.steps != null)
                Center(
                  child: SizedBox(
                    width: 190,
                    height: 190,
                    child: StepsArc(
                      key: const Key('steps-arc'),
                      steps: y.steps!,
                      fraction: stepsFraction(y.steps, y.stepGoal),
                      color: color,
                      stroke: 14,
                      numberSize: 34,
                      valueKey: const Key('steps-value'),
                    ),
                  ),
                ),
              if (y.stepGoal != null) ...[
                Center(
                  child: Text(
                    'Goal ${stepsComma(y.stepGoal!)}',
                    key: const Key('steps-goal'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Center(
                  child: Text(
                    'Goal set by Garmin, changes daily',
                    key: Key('steps-goal-note'),
                    style: TextStyle(color: _soft, fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _StatsRow(day: y, color: color),
              if (hours != null) ...[
                _divider(),
                const Text(
                  'Steps each hour',
                  style: TextStyle(color: _soft, fontSize: 13),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 130,
                  child: _HourBars(hours: hours, color: color),
                ),
              ],
              // ── 這一週 ──
              if (showWeek) ...[
                _divider(),
                if (week.usual != null)
                  Text(
                    stepsUsualLine(week),
                    key: const Key('steps-week-usual'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                Text(
                  stepsCountLine(week),
                  key: const Key('steps-week-count'),
                  style: const TextStyle(color: _soft, fontSize: 13),
                ),
                if (change != null)
                  Text(
                    change,
                    key: const Key('steps-week-change'),
                    style: TextStyle(
                      color: c! > 0
                          ? kDeltaUp
                          : (c < 0 ? kDeltaDown : kDeltaFlat),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 150,
                  child: _WeekBars(week: week, color: color),
                ),
                const SizedBox(height: 6),
                Row(
                  key: const Key('steps-week-legend'),
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0x14FFFFFF),
                        border: Border.all(color: const Color(0x33FFFFFF)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      "that day's goal",
                      style: TextStyle(color: Color(0x99FFFFFF), fontSize: 11),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Widget _divider() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Container(height: 1, color: const Color(0x1FFFFFFF)),
  );
}

/// 距離、活動卡路里、活動時間、爬樓：一排四項，沒值的不畫。
class _StatsRow extends StatelessWidget {
  final YesterdayActivity day;
  final Color color;
  const _StatsRow({required this.day, required this.color});

  @override
  Widget build(BuildContext context) {
    final y = day;
    final am = y.activeMinutes;
    final items = [
      if (y.distanceM != null)
        (Icons.place_rounded, (y.distanceM! / 1000).toStringAsFixed(1), 'km'),
      if (y.activeKcal != null)
        (
          Icons.local_fire_department_rounded,
          stepsComma(y.activeKcal!),
          'active kcal',
        ),
      if (am != null)
        (
          Icons.timer_rounded,
          am >= 60 ? '${am ~/ 60}h ${am % 60}m' : '${am}m',
          'active',
        ),
      if (y.floorsUp != null)
        (Icons.stairs_rounded, '${y.floorsUp!.round()}', 'floors'),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Row(
      key: const Key('steps-stats'),
      children: [
        for (final (icon, v, unit) in items)
          Expanded(
            child: Column(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    v,
                    softWrap: false,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    unit,
                    softWrap: false,
                    style: const TextStyle(
                      color: Color(0x99FFFFFF),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 24 根每小時長條；點／滑出泡泡。沒戴錶的鐘頭空著（不畫成 0）。
class _HourBars extends StatefulWidget {
  final List<int?> hours;
  final Color color;
  const _HourBars({required this.hours, required this.color});

  @override
  State<_HourBars> createState() => _HourBarsState();
}

class _HourBarsState extends State<_HourBars> {
  static const double _labelH = 16;
  int? _sel;

  @override
  Widget build(BuildContext context) {
    final hours = widget.hours;
    final hi = math.max(
      1,
      hours.fold<int>(0, (m, v) => v != null && v > m ? v : m),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight - _labelH;
        final slot = w / 24;
        int hourAt(double x) => (x / slot).floor().clamp(0, 23);
        double barH(int? v) => v == null ? 0 : math.max(2, h * v / hi);
        void pick(double x) => setState(() => _sel = hourAt(x));
        final sel = _sel;
        return TapRegion(
          onTapOutside: (_) {
            if (_sel != null) setState(() => _sel = null);
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: h,
                child: GestureDetector(
                  key: const Key('steps-hours'),
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => pick(d.localPosition.dx),
                  onHorizontalDragStart: (d) => pick(d.localPosition.dx),
                  onHorizontalDragUpdate: (d) => pick(d.localPosition.dx),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < 24; i++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 1.2,
                            ),
                            child: hours[i] == null
                                ? const SizedBox.shrink()
                                : Container(
                                    key: Key('steps-hour-$i'),
                                    height: barH(hours[i]),
                                    decoration: BoxDecoration(
                                      color: sel == null || sel == i
                                          ? widget.color
                                          : widget.color.withValues(
                                              alpha: 0.45,
                                            ),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              for (final (frac, label) in [
                (0.0, '00'),
                (0.25, '06'),
                (0.5, '12'),
                (0.75, '18'),
              ])
                Positioned(
                  left: w * frac,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Color(0x99FFFFFF),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              if (sel != null)
                Positioned(
                  left: 0,
                  top: 0,
                  width: w,
                  height: h,
                  child: ProbeLayer(
                    dot: Offset(slot * (sel + 0.5), h - barH(hours[sel])),
                    text: stepsHourText(sel, hours[sel]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 7 根長條＋每根上面那天自己的目標（白色小橫線）。只用一個顏色。
class _WeekBars extends StatelessWidget {
  final StepsWeek week;
  final Color color;
  const _WeekBars({required this.week, required this.color});

  static const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final days = week.days;
    final hi = math.max(
      1,
      days.fold<int>(
        0,
        (m, d) => math.max(m, math.max(d.steps ?? 0, d.goal ?? 0)),
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        const valueH = 16.0, labelH = 18.0;
        final h = box.maxHeight - valueH - labelH;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (i, d) in days.indexed)
              Expanded(
                child: Column(
                  key: Key('steps-week-$i'),
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      height: valueH,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          d.steps == null ? '—' : stepsComma(d.steps!),
                          softWrap: false,
                          style: TextStyle(
                            color: i == days.length - 1
                                ? Colors.white
                                : const Color(0xB3FFFFFF),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: h,
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          // 那天的目標＝一根淡色的空長條（11-15 使用者：只有一條線太空），
                          // 走了多少從底下往上填；超過目標就長出空條上緣，不變色
                          if (d.goal != null)
                            Container(
                              key: Key('steps-week-goal-$i'),
                              width: 24,
                              height: h * d.goal! / hi,
                              decoration: BoxDecoration(
                                color: const Color(0x14FFFFFF),
                                border: Border.all(
                                  color: const Color(0x33FFFFFF),
                                ),
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                          if (d.steps != null)
                            Container(
                              key: Key('steps-week-bar-$i'),
                              width: 24,
                              height: math.max(2, h * d.steps! / hi),
                              decoration: BoxDecoration(
                                color: i == days.length - 1
                                    ? color
                                    : color.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: labelH,
                      child: Center(
                        child: Text(
                          _wd[DateTime.parse(d.date).weekday - 1],
                          style: const TextStyle(
                            color: Color(0x99FFFFFF),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
