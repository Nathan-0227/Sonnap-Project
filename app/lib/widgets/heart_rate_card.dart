import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/heart_rate_curve.dart';
import '../theme/report_style.dart';

/// 早晨報告的 Heart rate 卡：睡著期間的心率曲線（2026-11-13 使用者定，照參考圖改成線條）。
///
/// - 大字是**睡著期間的平均**（照抄後端），旁邊照實寫最低、靜止心率。**不寫 Normal**（紅線 2）。
/// - 線：每 5 分鐘一點，畫成平滑但**不超出**實際最高最低的曲線（單調三次插值，不會畫出沒發生的值）。
/// - 虛線是同一個平均；**不畫「正常範圍」色帶**（那也是判斷）。
/// - 沒有曲線的晚上整張卡不畫（呼叫端決定）。
class HeartRateCard extends StatelessWidget {
  final HeartRateCurve curve;

  /// 靜止心率（後端的 metrics.resting_heart_rate，每天一個數字）。
  final double? restingHeartRate;

  const HeartRateCard({super.key, required this.curve, this.restingHeartRate});

  @override
  Widget build(BuildContext context) {
    final facts = [
      'lowest ${curve.min}',
      if (restingHeartRate != null) 'resting ${restingHeartRate!.round()}',
    ].join(' · ');
    return Container(
      key: const Key('heart-rate-card'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: reportCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Heart rate',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${curve.avg}',
                key: const Key('heart-rate-avg'),
                style: const TextStyle(
                  color: ReportColors.lilac,
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 6),
              const Flexible(
                child: Text(
                  'bpm avg while asleep',
                  style: TextStyle(color: ReportColors.muted, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            facts,
            key: const Key('heart-rate-facts'),
            style: const TextStyle(color: ReportColors.soft, fontSize: 13),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 150,
            width: double.infinity,
            child: CustomPaint(
              key: const Key('heart-rate-chart'),
              painter: HeartRateChartPainter(curve),
            ),
          ),
        ],
      ),
    );
  }
}

/// 心率曲線。左邊留給 y 軸刻度，下面留給起訖時刻。
class HeartRateChartPainter extends CustomPainter {
  final HeartRateCurve curve;
  HeartRateChartPainter(this.curve);

  static const double _left = 30;
  static const double _bottom = 20;
  static const double _top = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = curve.points;
    if (pts.length < 2) return;
    final t0 = pts.first.time;
    final span = pts.last.time.difference(t0).inSeconds.toDouble();
    if (span <= 0) return;

    // y 軸範圍：實際最低最高各留一點空間，取整到 5
    final lo = ((curve.min - 3) / 5).floor() * 5.0;
    final hi = ((curve.max + 3) / 5).ceil() * 5.0;
    final w = size.width - _left;
    final h = size.height - _bottom - _top;
    double x(DateTime t) => _left + w * t.difference(t0).inSeconds / span;
    double y(double bpm) => _top + h * (1 - (bpm - lo) / (hi - lo));

    final xs = [for (final p in pts) x(p.time)];
    final ys = [for (final p in pts) y(p.bpm)];

    // 刻度：最低、平均、最高附近三條字（不畫格線，只畫平均那條虛線）
    final labelStyle = const TextStyle(color: ReportColors.dim, fontSize: 10);
    for (final v in {lo, hi}) {
      _text(canvas, v.round().toString(), Offset(0, y(v) - 6), labelStyle);
    }

    // 平均：虛線
    final avgY = y(curve.avg.toDouble());
    final dash = Paint()
      ..color = ReportColors.muted.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    for (double dx = _left; dx < size.width; dx += 8) {
      canvas.drawLine(
        Offset(dx, avgY),
        Offset((dx + 4).clamp(0, size.width), avgY),
        dash,
      );
    }
    _text(
      canvas,
      curve.avg.toString(),
      Offset(0, avgY - 6),
      labelStyle.copyWith(color: ReportColors.muted),
    );

    // 線下的漸層
    final path = monotonePath(xs, ys);
    final fill = Path.from(path)
      ..lineTo(xs.last, _top + h)
      ..lineTo(xs.first, _top + h)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x55B9A6FF), Color(0x00B9A6FF)],
        ).createShader(Rect.fromLTWH(_left, _top, w, h)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = ReportColors.lilac
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );

    // 起訖時刻
    _text(
      canvas,
      _hm(pts.first.time),
      Offset(_left, size.height - 14),
      labelStyle,
    );
    final endLabel = _hm(pts.last.time);
    final tp = _layout(endLabel, labelStyle);
    tp.paint(canvas, Offset(size.width - tp.width, size.height - 14));
  }

  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static TextPainter _layout(String s, TextStyle style) => TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
  )..layout();

  static void _text(Canvas c, String s, Offset o, TextStyle style) =>
      _layout(s, style).paint(c, o);

  @override
  bool shouldRepaint(covariant HeartRateChartPainter old) => old.curve != curve;
}

/// 平滑但**不超出**相鄰兩點範圍的曲線（Fritsch–Carlson 單調三次插值）。
///
/// 一般的平滑曲線（Catmull-Rom、二次貝茲）在轉折處會衝過頭，畫出比實際最低還低的心率——
/// 那是沒發生的值（同 Sleep Stages「不畫平滑波浪」的理由）。這個寫法保證每一段都夾在兩端點之間。
Path monotonePath(List<double> xs, List<double> ys) {
  final n = xs.length;
  final path = Path()..moveTo(xs[0], ys[0]);
  if (n == 2) {
    path.lineTo(xs[1], ys[1]);
    return path;
  }
  final d = List<double>.filled(n - 1, 0);
  for (var i = 0; i < n - 1; i++) {
    final dx = xs[i + 1] - xs[i];
    d[i] = dx == 0 ? 0 : (ys[i + 1] - ys[i]) / dx;
  }
  final m = List<double>.filled(n, 0);
  m[0] = d[0];
  m[n - 1] = d[n - 2];
  for (var i = 1; i < n - 1; i++) {
    m[i] = (d[i - 1] * d[i] <= 0) ? 0 : (d[i - 1] + d[i]) / 2;
  }
  for (var i = 0; i < n - 1; i++) {
    if (d[i] == 0) {
      m[i] = 0;
      m[i + 1] = 0;
      continue;
    }
    final a = m[i] / d[i];
    final b = m[i + 1] / d[i];
    final s = a * a + b * b;
    if (s > 9) {
      final t = 3 / math.sqrt(s);
      m[i] = t * a * d[i];
      m[i + 1] = t * b * d[i];
    }
  }
  for (var i = 0; i < n - 1; i++) {
    final dx = xs[i + 1] - xs[i];
    path.cubicTo(
      xs[i] + dx / 3,
      ys[i] + m[i] * dx / 3,
      xs[i + 1] - dx / 3,
      ys[i + 1] - m[i + 1] * dx / 3,
      xs[i + 1],
      ys[i + 1],
    );
  }
  return path;
}
