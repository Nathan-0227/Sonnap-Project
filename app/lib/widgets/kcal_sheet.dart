import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'report_sheet.dart';

import '../models/yesterday_activity.dart';
import '../services/night_compare.dart' show kDeltaUp, kDeltaDown, kDeltaFlat;
import 'steps_sheet.dart' show stepsComma;

// 早晨報告 Active kcal 點開（2026-11-15 使用者定，參考圖 My Diary 的版面）：
// - 上半「那一天」：右邊圓環＝一整天總消耗，分兩段（淡＝靜止代謝、亮＝活動），中間「2,304 kcal burned」；
//   左邊兩行 Resting／Active。**參考圖的 Eaten／kcal left 不做**：我們沒有飲食資料，
//   「還剩多少」本身是好壞判斷（紅線 2）——不給目標、不寫剩多少、不寫達標。
//   底下一行：兩個都是 Garmin 估的。舊日子沒有靜止代謝 → 不畫圓環，只畫活動的大數字。
// - 下半「這一週」：7 根活動卡路里（76 天都有；總消耗只有新日子有），Usually＝中間值，
//   跟前一週比只代表方向（上升紅、下降綠），只用一個顏色；0／沒資料寫「—」不算。
// - 不做參考圖下面那排三餐卡片（沒有對應資料；Move IQ 有自己的格子、也不帶熱量）。

class KcalDay {
  final String date;
  final int? active; // null＝沒資料（0 也當沒資料：沒戴錶）
  const KcalDay(this.date, this.active);
}

class KcalWeek {
  final List<KcalDay> days; // 舊 → 新，日曆上 7 天
  final double? usual;
  final double? previousUsual;
  const KcalWeek(this.days, this.usual, this.previousUsual);

  int get daysWithData => days.where((d) => d.active != null).length;
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

/// [endDate] 往回 7 天的活動卡路里。純函式。
KcalWeek kcalWeek(List<ActivityHistoryDay> history, String endDate) {
  final by = {for (final h in history) h.date: h};
  final end = DateTime.parse(endDate);
  List<KcalDay> window(int offset) => [
    for (var i = 6; i >= 0; i--)
      () {
        final key = _iso(
          DateTime.utc(end.year, end.month, end.day - offset - i),
        );
        final v = by[key]?.activeKcal;
        return KcalDay(key, v == null || v <= 0 ? null : v);
      }(),
  ];
  double? usual(List<KcalDay> ds) => _median([
    for (final d in ds)
      if (d.active != null) d.active!.toDouble(),
  ]);
  final days = window(0);
  return KcalWeek(days, usual(days), usual(window(7)));
}

String kcalUsualLine(KcalWeek w) =>
    'Usually ${stepsComma(w.usual!.round())} active kcal';

String kcalCountLine(KcalWeek w) => w.daysWithData == w.days.length
    ? 'all ${w.days.length} days'
    : '${w.daysWithData} of ${w.days.length} days with data';

String? kcalChangeLine(KcalWeek w) {
  final c = w.change;
  if (c == null) return null;
  final r = c.round();
  if (r == 0) return '= same as the week before';
  return '${r > 0 ? '↑' : '↓'} ${stepsComma(r.abs())} kcal vs the week before';
}

/// 圓環要的三個數字都有才畫（總消耗、靜止、活動）。
bool kcalHasRing(YesterdayActivity y) =>
    y.totalKcal != null &&
    y.restingKcal != null &&
    y.activeKcal != null &&
    y.totalKcal! > 0;

Future<void> showKcalSheet(
  BuildContext context, {
  required YesterdayActivity day,
  required Color color,
  String? fontFamily,
}) {
  return showReportSheet<void>(
    context: context,
    builder: (context) => DefaultTextStyle.merge(
      style: TextStyle(fontFamily: fontFamily),
      child: KcalView(day: day, color: color),
    ),
  );
}

class KcalView extends StatelessWidget {
  final YesterdayActivity day;
  final Color color;
  const KcalView({
    super.key,
    required this.day,
    this.color = const Color(0xFFFF8A6B),
  });

  static const _soft = Color(0xB3FFFFFF);

  @override
  Widget build(BuildContext context) {
    final y = day;
    final week = kcalWeek(y.history, y.date);
    final showWeek = week.daysWithData > 0;
    final change = showWeek ? kcalChangeLine(week) : null;
    final c = week.change?.round();
    final ring = kcalHasRing(y);

    return Container(
      key: const Key('kcal-sheet'),
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
                  Icon(
                    Icons.local_fire_department_rounded,
                    size: 20,
                    color: color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Calories',
                      key: const Key('kcal-title'),
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
              const SizedBox(height: 16),
              // ── 那一天 ──
              if (ring)
                Container(
                  key: const Key('kcal-day-card'),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0x14FFFFFF),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0x1FFFFFFF)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Line(
                              key: const Key('kcal-resting'),
                              icon: Icons.bedtime_rounded,
                              color: color.withValues(alpha: 0.45),
                              label: 'Resting',
                              value: y.restingKcal!,
                            ),
                            const SizedBox(height: 16),
                            _Line(
                              key: const Key('kcal-active'),
                              icon: Icons.local_fire_department_rounded,
                              color: color,
                              label: 'Active',
                              value: y.activeKcal!,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 140,
                        height: 140,
                        child: CustomPaint(
                          key: const Key('kcal-ring'),
                          painter: _RingPainter(
                            resting: y.restingKcal!.toDouble(),
                            active: y.activeKcal!.toDouble(),
                            color: color,
                          ),
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    stepsComma(y.totalKcal!),
                                    key: const Key('kcal-total'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const Text(
                                    'kcal burned',
                                    style: TextStyle(
                                      color: _soft,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (y.activeKcal != null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      stepsComma(y.activeKcal!),
                      key: const Key('kcal-active-big'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'active kcal',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 10),
              Text(
                ring
                    ? 'Estimated by Garmin: resting from your profile, active from heart rate and movement.'
                    : 'Estimated by Garmin from heart rate and movement. Only calories burned while moving.',
                key: const Key('kcal-note'),
                style: const TextStyle(
                  color: _soft,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              // ── 這一週 ──
              if (showWeek) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Container(height: 1, color: const Color(0x1FFFFFFF)),
                ),
                if (week.usual != null)
                  Text(
                    kcalUsualLine(week),
                    key: const Key('kcal-week-usual'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                Text(
                  kcalCountLine(week),
                  style: const TextStyle(color: _soft, fontSize: 13),
                ),
                if (change != null)
                  Text(
                    change,
                    key: const Key('kcal-week-change'),
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
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int value;
  const _Line({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 13),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Text(
                  stepsComma(value),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 3),
                const Text(
                  'kcal',
                  style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 整圈＝靜止＋活動；淡的那段是靜止、亮的是活動。從正上方順時針。
class _RingPainter extends CustomPainter {
  final double resting;
  final double active;
  final Color color;
  _RingPainter({
    required this.resting,
    required this.active,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final r = math.min(size.width, size.height) / 2 - stroke / 2;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    final sum = resting + active;
    if (sum <= 0) return;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    const start = -math.pi / 2;
    final restSweep = 2 * math.pi * resting / sum;
    canvas.drawArc(
      rect,
      start,
      restSweep,
      false,
      p..color = color.withValues(alpha: 0.35),
    );
    canvas.drawArc(
      rect,
      start + restSweep,
      2 * math.pi - restSweep,
      false,
      p..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.resting != resting || old.active != active || old.color != color;
}

class _WeekBars extends StatelessWidget {
  final KcalWeek week;
  final Color color;
  const _WeekBars({required this.week, required this.color});

  static const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final days = week.days;
    final hi = math.max(
      1,
      days.fold<int>(0, (m, d) => math.max(m, d.active ?? 0)),
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
                  key: Key('kcal-week-$i'),
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      height: valueH,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          d.active == null ? '—' : stepsComma(d.active!),
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
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: d.active == null
                            ? null
                            : Container(
                                width: 24,
                                height: math.max(2, h * d.active! / hi),
                                decoration: BoxDecoration(
                                  color: i == days.length - 1
                                      ? color
                                      : color.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                              ),
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
