import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'report_sheet.dart';
import '../models/night_curve.dart';
import '../models/yesterday_activity.dart';
import '../services/night_compare.dart' show kDeltaUp, kDeltaDown, kDeltaFlat;
import '../theme/report_style.dart' show reportHm;
import 'chart_probe.dart' show ProbeLayer;

// 早晨報告 Stress（2026-11-15 使用者定，參考圖 Stress 卡）：
// - 報告上那一格：圖鋪滿整張卡（同日第四輪，照參考圖）；半圓整個露出來、在卡片上半（第一版右上方露一角、
//   第二版貼底），像打了光的球（左上亮、右下暗、亮邊）；第五輪：佔下半張卡、從底邊長出來、置中，字在半圓裡；
//   由上往下 高 → 中 → 低 → 休息，
//   **每一段的面積＝那天量到的時間裡各程度的比例**（同 Active time 的山，照實際形狀數值積分）。
//   **紫色系，不用紅黃**（11-13 定：紅色會被讀成壓力太大、不好）；邊緣一圈亮光；
//   （第四輪字在左下，第五輪改在半圓裡置中。）
//   大字＝平均壓力（Garmin 的 0–100 分數，**不加 %**——加了會被讀成「56% 的時間有壓力」），
//   **不寫 Elevated**。
// - 點開：圓環（只算量到的時間）＋四行＋「Not measured」；一整天的壓力線（每 3 分鐘一點、
//   量不到的空檔斷開、25／50／75 三條淡線標 Garmin 自己的四個名稱、睡著的時段淡底色；
//   點／滑出「14:21 · 62 · Medium」，離讀數超過 3 分鐘寫 no reading、不內插）；
//   一週（各程度疊起來、高在最下面最亮；Usually avg＝中間值，比前一週只代表方向）。
// ⚠️ 平均是「每 3 分鐘讀數的平均」（後端算）。跟 Garmin App 自己的平均常差 1（14 天實測 11 天
//    少 1，Garmin 的算法對不上四捨五入／進位／不算 0），所以畫面寫明是讀數的平均。
// ⚠️ 不提睡眠分數（睡前壓力有進個人修正，但這一頁只呈現）；不給呼吸練習之類的建議。

const kStressHigh = Color(0xFFEBDDFF);
const kStressMedium = Color(0xFFBBA2FF);
const kStressLow = Color(0xFF8A6CF0);
const kStressRest = Color(0xFF4B3AA6);
const kStressAccent = Color(0xFFA996FF);

const stressLevels = ['high', 'medium', 'low', 'rest'];

Color stressLevelColor(String level) => switch (level) {
  'high' => kStressHigh,
  'medium' => kStressMedium,
  'low' => kStressLow,
  _ => kStressRest,
};

String stressLevelLabel(String level) => switch (level) {
  'high' => 'High',
  'medium' => 'Medium',
  'low' => 'Low',
  _ => 'Rest',
};

/// Garmin 自己的分法：0–25 休息、26–50 低、51–75 中、76–100 高。這是 Garmin 的定義，不是好壞判斷。
String stressLevelOf(num v) => v <= 25
    ? 'rest'
    : v <= 50
    ? 'low'
    : v <= 75
    ? 'medium'
    : 'high';

/// 一天四個程度的秒數（只算量到的時間）。四個都沒有 → null。
class StressParts {
  final int high, medium, low, rest;
  const StressParts(this.high, this.medium, this.low, this.rest);
  int get total => high + medium + low + rest;
  int of(String level) => switch (level) {
    'high' => high,
    'medium' => medium,
    'low' => low,
    _ => rest,
  };
}

StressParts? stressParts(YesterdayActivity y) {
  if (!y.hasStress) return null;
  final p = StressParts(
    y.stressHighSec ?? 0,
    y.stressMediumSec ?? 0,
    y.stressLowSec ?? 0,
    y.stressRestSec ?? 0,
  );
  return p.total > 0 ? p : null;
}

/// 那天的平均壓力：整天壓力線的平均；沒有線就用一週資料裡那天的。都沒有 → null。
int? stressAvgOf(YesterdayActivity y) {
  final c = y.stressCurve;
  if (c != null) return c.avg.round();
  for (final h in y.history) {
    if (h.date == y.date) return h.stressAvg;
  }
  return null;
}

String stressTileLine(StressParts p) =>
    'avg stress · high ${reportHm(p.high / 60)}';

// ── 圓頂的形狀（寬高比 [aspect]＝寬÷高；座標都以高為 1） ──

/// 圓心與半徑（以高為 1）。11-15 第四輪使用者定（照參考圖 Stress 卡）：半圓在卡片**上半**，
/// 平的一邊在 [kStressDomeBase]，整個半圓都在卡片裡（不被左右上切到），下面留給字。
const double kStressDomeBase = 1.0;

({double cx, double cy, double r}) stressDomeCircle(double aspect) {
  // 第五輪：從底邊長出來、置中。第六輪使用者定「再大一點」：半徑到 0.62 個卡片高，
  // 比卡片寬的時候左右兩邊被卡片邊緣切掉（像大圓頂從底下升起來）；寬卡片時也不超過寬度的 0.62
  final r = math.min(0.62, aspect * 0.62);
  return (cx: aspect / 2, cy: kStressDomeBase, r: r);
}

/// 高度 y（0＝頂、1＝底）那一條橫線在半圓裡的寬度；平的那一邊以下是 0。
double stressDomeWidth(double y, double aspect) {
  final c = stressDomeCircle(aspect);
  if (y > c.cy) return 0;
  final dy = y - c.cy;
  if (dy.abs() >= c.r) return 0;
  final half = math.sqrt(c.r * c.r - dy * dy);
  final l = math.max(0.0, c.cx - half), r = math.min(aspect, c.cx + half);
  return math.max(0, r - l);
}

/// 半圓的分段：[(程度, 上緣 y, 下緣 y)]，由上往下 高 → 中 → 低 → 休息，
/// **每一段的面積＝那段佔量到時間的比例**（數值積分）。佔 0 的段不回。純函式。
List<(String, double, double)> stressDomeBands(StressParts p, double aspect) {
  final total = p.total.toDouble();
  if (total <= 0) return const [];
  final c = stressDomeCircle(aspect);
  final top = math.max(0.0, c.cy - c.r), bottom = c.cy;
  const n = 400;
  final ys = [for (var i = 0; i <= n; i++) top + (bottom - top) * i / n];
  final cum = List<double>.filled(n + 1, 0);
  for (var i = 1; i <= n; i++) {
    cum[i] =
        cum[i - 1] +
        (stressDomeWidth(ys[i - 1], aspect) + stressDomeWidth(ys[i], aspect)) /
            2 *
            (ys[i] - ys[i - 1]);
  }
  final whole = cum[n];
  double yFor(double share) {
    if (share <= 0) return top;
    if (share >= 1) return bottom;
    for (var i = 1; i <= n; i++) {
      if (cum[i] / whole >= share) {
        final a = cum[i - 1] / whole, b = cum[i] / whole;
        final f = b == a ? 0.0 : (share - a) / (b - a);
        return ys[i - 1] + (ys[i] - ys[i - 1]) * f;
      }
    }
    return bottom;
  }

  final out = <(String, double, double)>[];
  var acc = 0.0;
  for (final level in stressLevels) {
    final v = p.of(level);
    if (v <= 0) continue;
    final t0 = yFor(acc / total);
    acc += v;
    out.add((level, t0, yFor(math.min(1, acc / total))));
  }
  return out;
}

class StressDome extends StatelessWidget {
  final StressParts parts;
  const StressDome({super.key, required this.parts});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: StressDomePainter(parts), size: Size.infinite);
}

/// 參考圖的質感：像一顆打了光的球——外面一圈光暈、左上亮、右下暗、邊緣一圈亮邊、
/// 平的那一邊慢慢融進背景。色帶（每段面積＝比例）在最底下，光影疊在上面。
class StressDomePainter extends CustomPainter {
  final StressParts parts;
  StressDomePainter(this.parts);

  // 過渡柔一點（參考圖是平滑漸層）；每段的中心仍在原位，面積比例不變
  static const blend = 0.14;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    final aspect = w / h;
    final c = stressDomeCircle(aspect);
    final center = Offset(c.cx * h, c.cy * h);
    final radius = c.r * h;
    final base = c.cy * h;
    final dome = Path.combine(
      PathOperation.intersect,
      Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
      Path()..addRect(Rect.fromLTRB(0, 0, w, base)),
    );
    final bands = stressDomeBands(parts, aspect);
    if (bands.isEmpty) return;

    canvas.saveLayer(Offset.zero & size, Paint());

    // 外面一圈光暈（只在平的那一邊以上）
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, w, base));
    canvas.drawCircle(
      center,
      radius * 1.08,
      Paint()
        ..color = kStressMedium.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.22),
    );
    canvas.restore();

    // 色帶
    final top = bands.first.$2;
    final span = c.cy - top;
    double norm(double y) => ((y - top) / span).clamp(0.0, 1.0);
    final colors = <Color>[];
    final stops = <double>[];
    for (final (i, (level, t0, t1)) in bands.indexed) {
      final col = stressLevelColor(level);
      final first = i == 0, last = i == bands.length - 1;
      final a = first ? 0.0 : math.min(norm(t0) + blend / 2, norm(t1));
      final b = last ? 1.0 : math.max(norm(t1) - blend / 2, a);
      colors
        ..add(col)
        ..add(col);
      stops
        ..add(a)
        ..add(b);
    }
    canvas.drawPath(
      dome,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
          stops: stops,
        ).createShader(Rect.fromLTRB(0, top * h, w, base)),
    );

    canvas.save();
    canvas.clipPath(dome);
    // 左上亮
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.topLeft,
          radius: 1.1,
          colors: [
            Colors.white.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.65],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    // 右下暗
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.9, 0.2),
          radius: 0.9,
          colors: [
            const Color(0xFF120A2E).withValues(alpha: 0.45),
            const Color(0xFF120A2E).withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    // 邊緣一圈亮邊
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.16
        ..color = Colors.white.withValues(alpha: 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.07),
    );
    canvas.restore();

    // ⚠️ 不讓平的那一邊淡出：半圓貼底之後，淡出會吃掉最下面「休息」那一段（通常最大），
    //    畫面上的比例就不準了（第四輪半圓在上半時有淡出，第五輪拿掉）。
    canvas.restore();
  }

  @override
  bool shouldRepaint(StressDomePainter old) =>
      old.parts.high != parts.high ||
      old.parts.medium != parts.medium ||
      old.parts.low != parts.low ||
      old.parts.rest != parts.rest;
}

// ── 泡泡與一週 ──

String _hm(int minuteOfDay) =>
    '${(minuteOfDay ~/ 60).toString().padLeft(2, '0')}:${(minuteOfDay % 60).toString().padLeft(2, '0')}';

/// 一整天的壓力線上某個時刻：吸到最近的真實讀數；離最近的讀數超過 3 分鐘 → no reading（不內插）。
String stressProbeText(List<NightCurvePoint> points, int minuteOfDay) {
  NightCurvePoint? best;
  var bestD = 1 << 30;
  for (final p in points) {
    final d = (p.time.hour * 60 + p.time.minute - minuteOfDay).abs();
    if (d < bestD) {
      bestD = d;
      best = p;
    }
  }
  if (best == null || bestD > 3) return '${_hm(minuteOfDay)} · no reading';
  final v = best.value.round();
  return '${_hm(best.time.hour * 60 + best.time.minute)} · $v · '
      '${stressLevelLabel(stressLevelOf(v))}';
}

class StressDay {
  final String date;
  final Map<String, int?>? minutes; // null＝沒資料
  final int? avg;
  const StressDay(this.date, this.minutes, this.avg);
  int get measured =>
      minutes == null ? 0 : minutes!.values.fold(0, (s, v) => s + (v ?? 0));
}

class StressWeek {
  final List<StressDay> days;
  final double? usual;
  final double? previousUsual;
  const StressWeek(this.days, this.usual, this.previousUsual);
  int get daysWithData => days.where((d) => d.minutes != null).length;
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

/// [endDate] 往回 7 天。量到的時間是 0（沒戴錶）＝沒資料。純函式。
StressWeek stressWeek(List<ActivityHistoryDay> history, String endDate) {
  final by = {for (final h in history) h.date: h};
  final end = DateTime.parse(endDate);
  List<StressDay> window(int offset) => [
    for (var i = 6; i >= 0; i--)
      () {
        final key = _iso(
          DateTime.utc(end.year, end.month, end.day - offset - i),
        );
        final h = by[key];
        final d = StressDay(key, h?.stressMinutes, h?.stressAvg);
        return d.measured <= 0 ? StressDay(key, null, null) : d;
      }(),
  ];
  double? usual(List<StressDay> ds) => _median([
    for (final d in ds)
      if (d.avg != null) d.avg!.toDouble(),
  ]);
  final days = window(0);
  return StressWeek(days, usual(days), usual(window(7)));
}

String stressUsualLine(StressWeek w) => 'Usually avg ${w.usual!.round()}';

String stressCountLine(StressWeek w) => w.daysWithData == w.days.length
    ? 'all ${w.days.length} days'
    : '${w.daysWithData} of ${w.days.length} days with data';

String? stressChangeLine(StressWeek w) {
  final c = w.change;
  if (c == null) return null;
  final r = c.round();
  if (r == 0) return '= same as the week before';
  return '${r > 0 ? '↑' : '↓'} ${r.abs()} vs the week before';
}

// ── 點開的頁 ──

Future<void> showStressSheet(
  BuildContext context, {
  required YesterdayActivity day,
  String? fontFamily,
}) {
  return showReportSheet<void>(
    context: context,
    builder: (context) => DefaultTextStyle.merge(
      style: TextStyle(fontFamily: fontFamily),
      child: StressView(day: day),
    ),
  );
}

class StressView extends StatelessWidget {
  final YesterdayActivity day;
  const StressView({super.key, required this.day});

  static const _soft = Color(0xB3FFFFFF);

  @override
  Widget build(BuildContext context) {
    final y = day;
    final parts = stressParts(y);
    final avg = stressAvgOf(y);
    final curve = y.stressCurve;
    final week = stressWeek(y.history, y.date);
    final showWeek = week.daysWithData > 0;
    final change = showWeek ? stressChangeLine(week) : null;
    final c = week.change?.round();

    return Container(
      key: const Key('stress-sheet'),
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
                  const Icon(Icons.spa_rounded, size: 20, color: kStressAccent),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Stress',
                      style: TextStyle(
                        color: kStressAccent,
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
              if (parts != null)
                Container(
                  key: const Key('stress-day-card'),
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
                            for (final level in stressLevels) ...[
                              _Line(
                                key: Key('stress-$level'),
                                color: stressLevelColor(level),
                                label: stressLevelLabel(level),
                                value: reportHm(parts.of(level) / 60),
                              ),
                              const SizedBox(height: 10),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 140,
                        height: 140,
                        child: CustomPaint(
                          key: const Key('stress-ring'),
                          painter: _RingPainter(parts),
                          child: avg == null
                              ? null
                              : Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '$avg',
                                        key: const Key('stress-avg'),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 30,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const Text(
                                        'avg stress',
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
                    ],
                  ),
                ),
              if (y.stressNotMeasuredSec != null &&
                  y.stressNotMeasuredSec! > 0) ...[
                const SizedBox(height: 10),
                Text(
                  'Not measured ${reportHm(y.stressNotMeasuredSec! / 60)} '
                  '(moving or watch off)',
                  key: const Key('stress-not-measured'),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
              const SizedBox(height: 6),
              const Text(
                'Garmin\'s stress score, 0–100, from heart rate. '
                'The average is of the readings, so it can differ from the '
                'Garmin app by 1.',
                key: Key('stress-note'),
                style: TextStyle(color: _soft, fontSize: 12, height: 1.35),
              ),
              if (curve != null) ...[
                const SizedBox(height: 22),
                const Text(
                  'Through the day',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'A reading every 3 minutes. Gaps are when it could not be '
                  'measured. Tap or slide to see one.',
                  style: TextStyle(color: _soft, fontSize: 12),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 170,
                  child: _DayLine(
                    points: curve.points,
                    quarters: y.activityQuarters,
                  ),
                ),
                if (y.activityQuarters != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        width: 14,
                        height: 10,
                        decoration: BoxDecoration(
                          color: const Color(0x1FFFFFFF),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Asleep',
                        style: TextStyle(
                          color: Color(0x99FFFFFF),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
              if (showWeek) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Container(height: 1, color: const Color(0x1FFFFFFF)),
                ),
                if (week.usual != null)
                  Text(
                    stressUsualLine(week),
                    key: const Key('stress-week-usual'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                Text(
                  stressCountLine(week),
                  style: const TextStyle(color: _soft, fontSize: 13),
                ),
                if (change != null)
                  Text(
                    change,
                    key: const Key('stress-week-change'),
                    style: TextStyle(
                      color: c! > 0
                          ? kDeltaUp
                          : (c < 0 ? kDeltaDown : kDeltaFlat),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 14),
                SizedBox(height: 160, child: _WeekBars(week: week)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  children: [
                    for (final level in stressLevels) _Legend(level: level),
                  ],
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
  final Color color;
  final String label;
  final String value;
  const _Line({
    super.key,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            softWrap: false,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final String level;
  const _Legend({required this.level});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: stressLevelColor(level),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          stressLevelLabel(level),
          style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 11),
        ),
      ],
    );
  }
}

/// 只算量到的時間：從正上方順時針 高 → 中 → 低 → 休息。
class _RingPainter extends CustomPainter {
  final StressParts parts;
  _RingPainter(this.parts);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final r = math.min(size.width, size.height) / 2 - stroke / 2;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    final total = parts.total.toDouble();
    if (total <= 0) return;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    var start = -math.pi / 2;
    for (final level in stressLevels) {
      final v = parts.of(level);
      if (v <= 0) continue;
      final sweep = 2 * math.pi * v / total;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        p..color = stressLevelColor(level),
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.parts.total != parts.total;
}

/// 一整天的壓力線。
class _DayLine extends StatefulWidget {
  final List<NightCurvePoint> points;
  final List<ActivityQuarter?>? quarters;
  const _DayLine({required this.points, this.quarters});

  @override
  State<_DayLine> createState() => _DayLineState();
}

class _DayLineState extends State<_DayLine> {
  static const double _labelH = 16;
  int? _minute;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight - _labelH;
        void pick(double x) =>
            setState(() => _minute = (x / w * 1440).round().clamp(0, 1439));
        final m = _minute;
        NightCurvePoint? snap;
        if (m != null) {
          var bestD = 1 << 30;
          for (final p in widget.points) {
            final d = (p.time.hour * 60 + p.time.minute - m).abs();
            if (d < bestD) {
              bestD = d;
              snap = p;
            }
          }
          if (bestD > 3) snap = null;
        }
        final dot = m == null
            ? null
            : snap == null
            ? Offset(w * m / 1440, h)
            : Offset(
                w * (snap.time.hour * 60 + snap.time.minute) / 1440,
                h * (1 - snap.value / 100),
              );
        return TapRegion(
          onTapOutside: (_) {
            if (_minute != null) setState(() => _minute = null);
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
                  key: const Key('stress-day-line'),
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => pick(d.localPosition.dx),
                  onHorizontalDragStart: (d) => pick(d.localPosition.dx),
                  onHorizontalDragUpdate: (d) => pick(d.localPosition.dx),
                  child: CustomPaint(
                    painter: _DayLinePainter(widget.points, widget.quarters),
                    size: Size.infinite,
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
              if (m != null && dot != null)
                Positioned(
                  left: 0,
                  top: 0,
                  width: w,
                  height: h,
                  child: ProbeLayer(
                    dot: dot,
                    text: stressProbeText(widget.points, m),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DayLinePainter extends CustomPainter {
  final List<NightCurvePoint> points;
  final List<ActivityQuarter?>? quarters;
  _DayLinePainter(this.points, this.quarters);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    double x(int minute) => w * minute / 1440;
    double yv(double v) => h * (1 - v.clamp(0, 100) / 100);

    // 睡著的時段：淡底色
    final q = quarters;
    if (q != null && q.length == 96) {
      final paint = Paint()..color = const Color(0x1FFFFFFF);
      for (var i = 0; i < 96; i++) {
        if (q[i]?.level == 'sleep') {
          canvas.drawRect(
            Rect.fromLTRB(x(i * 15), 0, x(i * 15 + 15) + 0.5, h),
            paint,
          );
        }
      }
    }
    // Garmin 的四個程度：25／50／75 三條很淡的線，名字寫在每一段的右邊
    final grid = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 1;
    for (final v in [25.0, 50.0, 75.0]) {
      canvas.drawLine(Offset(0, yv(v)), Offset(w, yv(v)), grid);
    }
    for (final (lo, level) in [
      (0.0, 'rest'),
      (25.0, 'low'),
      (50.0, 'medium'),
      (75.0, 'high'),
    ]) {
      final tp = TextPainter(
        text: TextSpan(
          text: stressLevelLabel(level),
          style: const TextStyle(color: Color(0x66FFFFFF), fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(w - tp.width - 2, yv(lo + 12.5) - tp.height / 2));
    }

    // 線：每 3 分鐘一點；兩點相隔超過一格半（4.5 分鐘）＝中間量不到 → 斷開
    final line = Paint()
      ..color = kStressAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round;
    Path? path;
    int? prev;
    for (final p in points) {
      final m = p.time.hour * 60 + p.time.minute;
      final pt = Offset(x(m), yv(p.value));
      if (path == null || prev == null || m - prev > 4) {
        if (path != null) canvas.drawPath(path, line);
        path = Path()..moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
      prev = m;
    }
    if (path != null) canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(_DayLinePainter old) =>
      old.points != points || old.quarters != quarters;
}

/// 7 根：各程度的時間疊起來，高（最亮）在最下面；上面寫那天的平均壓力；沒資料寫「—」。
class _WeekBars extends StatelessWidget {
  final StressWeek week;
  const _WeekBars({required this.week});

  static const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final days = week.days;
    final hi = math.max(
      1,
      days.fold<int>(0, (m, d) => math.max(m, d.measured)),
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
                  key: Key('stress-week-$i'),
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      height: valueH,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          d.minutes == null
                              ? '—'
                              : (d.avg == null ? '' : '${d.avg}'),
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
                        child: d.minutes == null
                            ? null
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(7),
                                child: SizedBox(
                                  width: 24,
                                  height: math.max(2, h * d.measured / hi),
                                  child: Column(
                                    children: [
                                      // 由上往下 休息 → 低 → 中 → 高（高在最下面）
                                      for (final level in stressLevels.reversed)
                                        if ((d.minutes![level] ?? 0) > 0)
                                          Expanded(
                                            flex: d.minutes![level]!,
                                            child: Container(
                                              key: Key('stress-week-$level-$i'),
                                              color: stressLevelColor(level)
                                                  .withValues(
                                                    alpha: i == days.length - 1
                                                        ? 1
                                                        : 0.7,
                                                  ),
                                            ),
                                          ),
                                    ],
                                  ),
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
