import 'package:flutter/material.dart';

import '../models/night_curve.dart';
import '../theme/sonnap_colors.dart';
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
