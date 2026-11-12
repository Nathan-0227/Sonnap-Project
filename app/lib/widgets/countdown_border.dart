import 'package:flutter/material.dart';

import 'bedtime_urgency.dart';

/// 沿著卡片外框走的倒數光條（2026-11-12 使用者定案，取代右邊的圓環）。
///
/// 從上緣正中間出發、順時針繞；[progress] = 1 是整圈，越接近就寢越短。
class CountdownBorder extends StatelessWidget {
  final Widget child;
  final double progress;
  final Color color;
  final double radius;
  final double strokeWidth;

  const CountdownBorder({
    super.key,
    required this.child,
    required this.progress,
    required this.color,
    this.radius = 24,
    this.strokeWidth = 4,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _BorderPainter(
        progress: progress.clamp(0.0, 1.0),
        color: color,
        radius: radius,
        strokeWidth: strokeWidth,
      ),
      child: child,
    );
  }
}

class _BorderPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double radius;
  final double strokeWidth;

  _BorderPainter({
    required this.progress,
    required this.color,
    required this.radius,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final r = radius - inset;

    // 從上緣正中間出發、順時針繞一圈的路徑。
    final path = Path()
      ..moveTo(rect.center.dx, rect.top)
      ..lineTo(rect.right - r, rect.top)
      ..arcToPoint(Offset(rect.right, rect.top + r), radius: Radius.circular(r))
      ..lineTo(rect.right, rect.bottom - r)
      ..arcToPoint(
        Offset(rect.right - r, rect.bottom),
        radius: Radius.circular(r),
      )
      ..lineTo(rect.left + r, rect.bottom)
      ..arcToPoint(
        Offset(rect.left, rect.bottom - r),
        radius: Radius.circular(r),
      )
      ..lineTo(rect.left, rect.top + r)
      ..arcToPoint(Offset(rect.left + r, rect.top), radius: Radius.circular(r))
      ..close();

    // 底軌
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = Colors.white.withValues(alpha: 0.12),
    );
    if (progress <= 0) return;

    final metric = path.computeMetrics().first;
    final part = metric.extractPath(0, metric.length * progress);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    // 一點點光暈
    canvas.drawPath(
      part,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 2.2
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(part, paint);
  }

  @override
  bool shouldRepaint(covariant _BorderPainter old) =>
      old.progress != progress || old.color != color;
}

/// 倒數光條的顏色：時間越短越紅。
///
/// - 剩 [kImminentThreshold]（30 分鐘）以內、或剛過就寢時間：紅
///   ⚠️ 這個 30 分鐘與就寢提醒、守門、[bedtimeUrgencyColor] 同一個，不另訂。
/// - 其餘：8 小時以上是綠，越接近 30 分鐘越往黃、橘漸變。
Color countdownColor(Duration remaining, BedtimeUrgency urgency) {
  const red = Color(0xFFFF6B6B);
  if (urgency == BedtimeUrgency.imminent || urgency == BedtimeUrgency.overdue) {
    return red;
  }
  const green = Color(0xFF7ED957);
  const yellow = Color(0xFFFFD96A);
  const orange = Color(0xFFFF9B4A);
  const full = Duration(hours: 8);
  final span = (full - kImminentThreshold).inMinutes;
  final f = ((remaining - kImminentThreshold).inMinutes / span).clamp(0.0, 1.0);
  return f >= 0.5
      ? Color.lerp(yellow, green, (f - 0.5) * 2)!
      : Color.lerp(orange, yellow, f * 2)!;
}
