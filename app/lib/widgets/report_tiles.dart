import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/report_style.dart';
import 'curve_path.dart';

/// 早晨報告的圖形格子（2026-11-14 使用者定，參考圖：每一格的圖形就是那個數字）。
///
/// ⚠️ 規則：
/// - **圖形一定是那個數字本身**，不是裝飾（光帶長度＝睡了多久÷目標、圓環＝效率……）。
/// - 底下那行**只寫事實**：不寫 Elevated／Perfect day／Fairly rested 這種判斷（參考圖有、我們不照做）。
/// - 沒有值的格子整格不畫，**不畫成 0**；壓力**不用紅黃**（同一色系深淺）。
/// - Body Battery **不畫成電池**：Garmin 只給充了多少、用掉多少，沒有「剩幾 %」。

/// 一格。[graphic] 是那個數字的圖，[lines] 是底下的小字。
class ReportTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;

  /// 大字。null＝不放大字（例如壓力只有圖＋各段時間）。
  final String? value;
  final Key? valueKey;
  final Widget? valueTrailing;
  final Widget? graphic;
  final double graphicHeight;
  final List<Widget> lines;
  final VoidCallback? onTap;

  /// 還沒有資料（例如手錶還沒到）：虛線、灰字。
  final bool dashed;

  const ReportTile({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.value,
    this.valueKey,
    this.valueTrailing,
    this.graphic,
    this.graphicHeight = 46,
    this.lines = const [],
    this.onTap,
    this.dashed = false,
  });

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: reportCard(dashed: dashed).copyWith(
        gradient: dashed
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withValues(alpha: 0.26), ReportColors.card],
                stops: const [0, 0.75],
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (onTap != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: ReportColors.dim,
                ),
            ],
          ),
          if (value != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value!,
                      key: valueKey,
                      softWrap: false,
                      style: TextStyle(
                        color: dashed ? ReportColors.dim : Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                ?valueTrailing,
              ],
            ),
          ],
          if (graphic != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: graphicHeight,
              width: double.infinity,
              child: graphic,
            ),
          ],
          if (lines.isNotEmpty) const SizedBox(height: 6),
          for (final l in lines)
            DefaultTextStyle.merge(
              style: const TextStyle(
                color: ReportColors.muted,
                fontSize: 12,
                height: 1.35,
              ),
              child: l,
            ),
        ],
      ),
    );
    return onTap == null
        ? body
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: body,
          );
  }
}

/// 兩欄排：有的才放，兩個一列、一樣高；單數的最後一個佔整列。
Widget reportTileGrid(List<Widget?> tiles, {double gap = 12}) {
  final present = [for (final t in tiles) ?t];
  final rows = <Widget>[];
  for (var i = 0; i < present.length; i += 2) {
    if (rows.isNotEmpty) rows.add(SizedBox(height: gap));
    if (i + 1 < present.length) {
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: present[i]),
              SizedBox(width: gap),
              Expanded(child: present[i + 1]),
            ],
          ),
        ),
      );
    } else {
      rows.add(present[i]);
    }
  }
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
}

/// 段落標題：「Last night」「Yesterday · Thu, Nov 12」。
Widget reportSectionTitle(String text, {Key? key}) => Padding(
  padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
  child: Text(
    text,
    key: key,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 17,
      fontWeight: FontWeight.w900,
    ),
  ),
);

// ── 圖形 ───────────────────────────────────────────────────────────

Paint _glow(Color c, double w) => Paint()
  ..color = c.withValues(alpha: 0.55)
  ..style = PaintingStyle.stroke
  ..strokeWidth = w + 6
  ..strokeCap = StrokeCap.round
  ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

Paint _stroke(Color c, double w) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

Paint get _track => Paint()
  ..color = Colors.white.withValues(alpha: 0.12)
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round;

void _label(
  Canvas canvas,
  String s,
  Offset at, {
  Color color = ReportColors.dim,
  double size = 9,
  bool center = true,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(color: color, fontSize: size),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, center ? at - Offset(tp.width / 2, 0) : at);
}

/// 睡多久：一條發光的波浪，長度＝[fraction]（睡了多久÷目標，超過目標就畫滿）。
class WaveBarPainter extends CustomPainter {
  final double fraction;
  final Color color;
  WaveBarPainter(this.fraction, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final amp = size.height * 0.18;
    double y(double x) => mid + math.sin(x / size.width * math.pi * 3) * amp;
    final track = Path()..moveTo(0, y(0));
    for (double x = 2; x <= size.width; x += 2) {
      track.lineTo(x, y(x));
    }
    canvas.drawPath(track, _track..strokeWidth = 6);
    final end = size.width * fraction.clamp(0.0, 1.0);
    if (end <= 0) return;
    final p = Path()..moveTo(0, y(0));
    for (double x = 2; x <= end; x += 2) {
      p.lineTo(x, y(x));
    }
    canvas.drawPath(p, _glow(color, 6));
    canvas.drawPath(
      p,
      _stroke(color, 6)
        ..shader = LinearGradient(
          colors: [color.withValues(alpha: 0.7), Colors.white],
        ).createShader(Offset.zero & Size(math.max(end, 1), size.height)),
    );
  }

  @override
  bool shouldRepaint(covariant WaveBarPainter old) =>
      old.fraction != fraction || old.color != color;
}

/// 晚上的分鐘數：從 18:00 起算（18:00＝0、00:00＝360、12:00＝1080）。
double nightMinute(int hour, int minute) {
  final m = (hour * 60 + minute - 18 * 60) % 1440;
  return m < 0 ? m + 1440.0 : m.toDouble();
}

/// 臥床：18:00 → 12:00 的時間軸，上床、下床兩個點，中間那段亮起來。
class NightTimelinePainter extends CustomPainter {
  final double start; // nightMinute
  final double? end;
  final Color color;
  NightTimelinePainter(this.start, this.end, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const span = 1080.0;
    final w = size.width;
    final lineY = size.height * 0.42;
    double x(double m) => w * (m.clamp(0, span) / span);
    canvas.drawLine(
      Offset(0, lineY),
      Offset(w, lineY),
      _track..strokeWidth = 4,
    );
    for (final (m, s) in [
      (0.0, '18'),
      (360.0, '00'),
      (720.0, '06'),
      (1080.0, '12'),
    ]) {
      final px = x(m).clamp(6.0, w - 6);
      _label(canvas, s, Offset(px, lineY + 9));
    }
    final e = end;
    if (e != null && e > start) {
      canvas.drawLine(
        Offset(x(start), lineY),
        Offset(x(e), lineY),
        _glow(color, 4),
      );
      canvas.drawLine(
        Offset(x(start), lineY),
        Offset(x(e), lineY),
        _stroke(color, 4),
      );
      canvas.drawCircle(
        Offset(x(e), lineY),
        4.5,
        Paint()..color = Colors.white,
      );
    }
    canvas.drawCircle(
      Offset(x(start), lineY),
      4.5,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant NightTimelinePainter old) =>
      old.start != start || old.end != end;
}

/// 放下手機：半圓時鐘弧，「目標」與「實際」兩個點，中間那段上色（不分好壞，一律同一色）。
class ClockArcPainter extends CustomPainter {
  final double target; // nightMinute
  final double actual;
  final Color color;
  ClockArcPainter(this.target, this.actual, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    var lo = math.min(target, actual) - 60;
    var hi = math.max(target, actual) + 60;
    if (hi - lo < 180) {
      final pad = (180 - (hi - lo)) / 2;
      lo -= pad;
      hi += pad;
    }
    final r = math.min(size.width / 2, size.height) - 6;
    final c = Offset(size.width / 2, size.height - 2);
    final rect = Rect.fromCircle(center: c, radius: r);
    double ang(double m) => math.pi + math.pi * ((m - lo) / (hi - lo));
    canvas.drawArc(rect, math.pi, math.pi, false, _track..strokeWidth = 7);
    final a0 = ang(math.min(target, actual));
    final a1 = ang(math.max(target, actual));
    if (a1 - a0 > 0.01) {
      canvas.drawArc(rect, a0, a1 - a0, false, _glow(color, 7));
      canvas.drawArc(rect, a0, a1 - a0, false, _stroke(color, 7));
    }
    Offset at(double m) => c + Offset(math.cos(ang(m)), math.sin(ang(m))) * r;
    canvas.drawCircle(at(target), 5.5, Paint()..color = ReportColors.accent);
    canvas.drawCircle(at(actual), 5.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant ClockArcPainter old) =>
      old.target != target || old.actual != actual;
}

/// 效率：圓環，填滿的比例＝百分比。
class RingPainter extends CustomPainter {
  final double percent;
  final Color color;
  RingPainter(this.percent, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2 - 6;
    final c = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(c, r, _track..strokeWidth = 8);
    final sweep = 2 * math.pi * (percent / 100).clamp(0.0, 1.0);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, _glow(color, 8));
    canvas.drawArc(rect, -math.pi / 2, sweep, false, _stroke(color, 8));
  }

  @override
  bool shouldRepaint(covariant RingPainter old) => old.percent != percent;
}

/// 一段時間裡的幾個區段（入睡 → 起床那條上的清醒段、白天的 Move IQ）：整條是淡的，區段亮起來。
class SegmentStripPainter extends CustomPainter {
  /// 每一段：開始、結束（0–1 的比例）。
  final List<(double, double)> segments;
  final Color color;
  final List<(double, String)> ticks;
  SegmentStripPainter(this.segments, this.color, {this.ticks = const []});

  @override
  void paint(Canvas canvas, Size size) {
    final y = ticks.isEmpty ? size.height / 2 : size.height * 0.4;
    final w = size.width;
    canvas.drawLine(Offset(0, y), Offset(w, y), _track..strokeWidth = 10);
    for (final (a, b) in segments) {
      final x0 = w * a.clamp(0.0, 1.0);
      final x1 = math.max(w * b.clamp(0.0, 1.0), x0 + 3);
      canvas.drawLine(Offset(x0, y), Offset(x1, y), _glow(color, 10));
      canvas.drawLine(Offset(x0, y), Offset(x1, y), _stroke(color, 10));
    }
    for (final (f, s) in ticks) {
      _label(canvas, s, Offset((w * f).clamp(6.0, w - 6), y + 10));
    }
  }

  @override
  bool shouldRepaint(covariant SegmentStripPainter old) => true;
}

/// 一條小折線（心率、攝影機）；[fill] 畫線底下的漸層面積。x 照時間。
class SparklinePainter extends CustomPainter {
  final List<(double, double)> points; // (x 0–1, value)
  final Color color;
  final double? lo;
  final double? hi;
  SparklinePainter(this.points, this.color, {this.lo, this.hi});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final vs = [for (final p in points) p.$2];
    final mn = lo ?? vs.reduce(math.min);
    var mx = hi ?? vs.reduce(math.max);
    if (mx <= mn) mx = mn + 1;
    const pad = 4.0;
    final xs = [for (final p in points) size.width * p.$1.clamp(0.0, 1.0)];
    final ys = [
      for (final p in points)
        pad + (size.height - 2 * pad) * (1 - (p.$2 - mn) / (mx - mn)),
    ];
    final line = monotonePath(xs, ys);
    final area = Path.from(line)
      ..lineTo(xs.last, size.height)
      ..lineTo(xs.first, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(line, _stroke(color, 2));
  }

  @override
  bool shouldRepaint(covariant SparklinePainter old) => true;
}

/// 步數：最近幾天連成一座山，最後一天（昨天）亮一個點。
class MountainPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  MountainPainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final mx = values.reduce(math.max);
    if (mx <= 0) return;
    final n = values.length;
    final xs = [
      for (var i = 0; i < n; i++)
        n == 1 ? size.width / 2 : size.width * i / (n - 1),
    ];
    final ys = [for (final v in values) 6 + (size.height - 8) * (1 - v / mx)];
    final line = n == 1
        ? (Path()
            ..moveTo(0, ys[0])
            ..lineTo(size.width, ys[0]))
        : monotonePath(xs, ys);
    final area = Path.from(line)
      ..lineTo(n == 1 ? size.width : xs.last, size.height)
      ..lineTo(n == 1 ? 0 : xs.first, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.75),
            color.withValues(alpha: 0.08),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(line, _stroke(Colors.white.withValues(alpha: 0.7), 1.5));
    final last = Offset(n == 1 ? size.width / 2 : xs.last, ys.last);
    canvas.drawCircle(
      last,
      7,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(last, 4, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant MountainPainter old) => true;
}

/// 一條橫條切成幾段（活動時間：高強度／活動／久坐）。
class StackedBarPainter extends CustomPainter {
  final List<(double, Color)> parts;
  StackedBarPainter(this.parts);

  @override
  void paint(Canvas canvas, Size size) {
    final total = parts.fold<double>(0, (s, p) => s + p.$1);
    if (total <= 0) return;
    const h = 14.0;
    final y = (size.height - h) / 2;
    final clip = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, y, size.width, h),
      const Radius.circular(7),
    );
    canvas.save();
    canvas.clipRRect(clip);
    var x = 0.0;
    for (final (v, c) in parts) {
      final w = size.width * v / total;
      canvas.drawRect(Rect.fromLTWH(x, y, w, h), Paint()..color = c);
      x += w;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant StackedBarPainter old) => true;
}

/// 半圓刻度切成幾段（壓力：休息／低／中／高的時間）。**同一色系深淺，不用紅黃。**
class GaugePainter extends CustomPainter {
  final List<(double, Color)> parts;
  GaugePainter(this.parts);

  @override
  void paint(Canvas canvas, Size size) {
    final total = parts.fold<double>(0, (s, p) => s + p.$1);
    final r = math.min(size.width / 2, size.height) - 8;
    final c = Offset(size.width / 2, size.height - 2);
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(rect, math.pi, math.pi, false, _track..strokeWidth = 12);
    if (total <= 0) return;
    var a = math.pi;
    for (final (v, col) in parts) {
      final sweep = math.pi * v / total;
      if (sweep > 0.02) {
        canvas.drawArc(
          rect,
          a + 0.02,
          sweep - 0.04,
          false,
          _stroke(col, 12)..strokeCap = StrokeCap.butt,
        );
      }
      a += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant GaugePainter old) => true;
}

/// 兩根柱子（Body Battery：充了多少、用掉多少）。
class TwoBarsPainter extends CustomPainter {
  final double up;
  final double down;
  final Color upColor;
  final Color downColor;
  TwoBarsPainter(this.up, this.down, this.upColor, this.downColor);

  @override
  void paint(Canvas canvas, Size size) {
    final mx = math.max(up, down);
    if (mx <= 0) return;
    const bw = 22.0;
    final gap = size.width / 3;
    for (final (i, v, c) in [(0, up, upColor), (1, down, downColor)]) {
      final h = (size.height - 2) * v / mx;
      final x = gap * (i + 1) - bw / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - h, bw, h),
          const Radius.circular(6),
        ),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c, c.withValues(alpha: 0.35)],
          ).createShader(Rect.fromLTWH(x, size.height - h, bw, h)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant TwoBarsPainter old) => true;
}

/// 有圖的格子用的 CustomPaint，畫在整格寬度上。
Widget paintBox(CustomPainter painter, {Key? key}) =>
    CustomPaint(key: key, painter: painter, size: Size.infinite);

/// 「最近 7 天」長條圖的面板（點步數、活動時間）。只畫數字，不判斷、不畫目標線。
void showReportBarsSheet(
  BuildContext context, {
  required String id,
  required String title,
  required List<(String, double)> bars, // (日期標籤, 值)，最後一個是那一天
  required String Function(double) format,
}) {
  final maxV = bars.fold<double>(0, (m, b) => b.$2 > m ? b.$2 : m);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: ReportColors.sheet,
    builder: (context) => SafeArea(
      child: Padding(
        key: Key('report-sheet-$id'),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$title · last 7 days',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final (i, b) in bars.indexed)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            FittedBox(
                              child: Text(
                                format(b.$2),
                                style: const TextStyle(
                                  color: ReportColors.muted,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: maxV <= 0 ? 0 : 100 * b.$2 / maxV,
                              decoration: BoxDecoration(
                                color: ReportColors.accent.withValues(
                                  alpha: i == bars.length - 1 ? 1 : 0.45,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              b.$1,
                              style: const TextStyle(
                                color: ReportColors.dim,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
