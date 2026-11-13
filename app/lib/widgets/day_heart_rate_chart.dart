import 'package:flutter/material.dart';

import '../models/night_curve.dart';
import '../theme/sonnap_colors.dart';
import 'chart_probe.dart';
import 'curve_path.dart';

/// 一整天（0–24 點）的心率線（首頁 Activity 卡點整天心率，2026-11-13）。
///
/// 每 10 分鐘一點、單調三次插值（不會畫出比實際最低還低的值）。右邊只寫最高最低的 bpm；
/// **不畫正常範圍、不寫 Normal／High**（沒有文獻門檻）。
class DayHeartRatePainter extends CustomPainter {
  final NightCurve curve;
  DayHeartRatePainter(this.curve);

  static const double _right = 30;
  static const double _bottom = 18;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = curve.points;
    if (pts.length < 2) return;
    final first = pts.first.time;
    final day0 = DateTime.utc(first.year, first.month, first.day);
    final w = size.width - _right;
    final h = size.height - _bottom;
    final lo = ((curve.min - 3) / 5).floor() * 5.0;
    final hi = ((curve.max + 3) / 5).ceil() * 5.0;
    double x(DateTime t) {
      // 時間是牆鐘（isUtc 的牆鐘或本地，兩種都只看時分）
      final minutes = t.hour * 60 + t.minute + (t.day != day0.day ? 1440 : 0);
      return w * (minutes / 1440).clamp(0.0, 1.0);
    }

    double y(double v) => 4 + (h - 8) * (1 - (v - lo) / (hi - lo));

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final gx = w * i / 4;
      canvas.drawLine(Offset(gx, 0), Offset(gx, h), grid);
    }

    final path = monotonePath(
      [for (final p in pts) x(p.time)],
      [for (final p in pts) y(p.value)],
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFF8AB8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    const style = TextStyle(color: SonnapColors.textMuted, fontSize: 10);
    void text(String s, Offset o, {bool alignRight = false}) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, alignRight ? o - Offset(tp.width, 0) : o);
    }

    text(hi.round().toString(), Offset(size.width, 0), alignRight: true);
    text(lo.round().toString(), Offset(size.width, h - 12), alignRight: true);
    for (var i = 0; i <= 4; i++) {
      final label = '${i * 6}';
      final gx = w * i / 4;
      text(label, Offset(i == 0 ? 0 : gx - 6, h + 4));
    }
  }

  @override
  bool shouldRepaint(covariant DayHeartRatePainter old) => old.curve != curve;
}

/// 整天心率圖＋點線看數值（2026-11-13 使用者定，同 Sleep Stages 卡的泡泡）：
/// 點一下或按住滑，吸到最近的真實讀數（每 10 分鐘一點，超過 10 分鐘寫 no reading），
/// 泡泡寫 `14:20 · 96 bpm`。
class DayHeartRateChart extends StatefulWidget {
  final NightCurve curve;
  const DayHeartRateChart(this.curve, {super.key});

  @override
  State<DayHeartRateChart> createState() => _DayHeartRateChartState();
}

class _DayHeartRateChartState extends State<DayHeartRateChart> {
  DateTime? _probe;

  @override
  Widget build(BuildContext context) {
    final c = widget.curve;
    final first = c.points.first.time;
    final day0 = first.isUtc
        ? DateTime.utc(first.year, first.month, first.day)
        : DateTime(first.year, first.month, first.day);
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      final w = size.width - DayHeartRatePainter._right;
      final h = size.height - DayHeartRatePainter._bottom;
      Widget? probe;
      if (_probe != null && w > 0) {
        final p = nearestPoint(c.points, _probe!,
            maxGap: const Duration(minutes: 10));
        final shown = p?.time ?? _probe!;
        final minutes = shown.difference(day0).inMinutes;
        final x = w * (minutes / 1440).clamp(0.0, 1.0);
        final lo = ((c.min - 3) / 5).floor() * 5.0;
        final hi = ((c.max + 3) / 5).ceil() * 5.0;
        final y = p == null
            ? h / 2
            : 4 + (h - 8) * (1 - (p.value - lo) / (hi - lo));
        probe = ProbeLayer(
          dot: Offset(x, y),
          text: probeText(time: shown, kind: ProbeKind.heartRate, point: p),
        );
      }
      return ProbeGestures(
        key: const Key('day-hr-chart'),
        onX: (dx) => setState(() {
          final f = w <= 0 ? 0.0 : (dx / w).clamp(0.0, 1.0);
          _probe = day0.add(Duration(minutes: (1440 * f).round()));
        }),
        onClear: () {
          if (_probe != null) setState(() => _probe = null);
        },
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            CustomPaint(painter: DayHeartRatePainter(c)),
            ?probe,
          ],
        ),
      );
    });
  }
}
