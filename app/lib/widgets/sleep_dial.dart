import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/sonnap_colors.dart';

/// 就寢／起床時間的圓環轉盤（2026-11-12 使用者定案，參考使用者給的設計圖）。
///
/// 一整圈 = 24 小時，00:00 在正上方、順時針走。月亮把手是就寢時間、太陽把手是
/// 起床時間；中間顯示睡幾小時（**只有數字，不判斷好壞**——好壞由後端判斷）。
/// 拖動時每 5 分鐘一格。

const int kDialStepMinutes = 5;

/// 時刻 → 角度（弧度，0 在正上方、順時針為正）。
double angleForMinutes(int minutes) => minutes / (24 * 60) * 2 * math.pi;

/// 觸碰點（相對圓心）→ 時刻，對齊到 [kDialStepMinutes]。
int minutesForOffset(Offset fromCenter) {
  // atan2 以正右方為 0、逆時針為正；換成「正上方為 0、順時針為正」。
  var a = math.atan2(fromCenter.dx, -fromCenter.dy);
  if (a < 0) a += 2 * math.pi;
  final raw = a / (2 * math.pi) * 24 * 60;
  final snapped = (raw / kDialStepMinutes).round() * kDialStepMinutes;
  return snapped % (24 * 60);
}

/// 就寢 → 起床隔多久（跨午夜也對）。
Duration sleepSpan(TimeOfDay bed, TimeOfDay wake) {
  final b = bed.hour * 60 + bed.minute;
  final w = wake.hour * 60 + wake.minute;
  return Duration(minutes: (w - b) % (24 * 60));
}

String formatSpan(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

TimeOfDay _tod(int minutes) =>
    TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
int _min(TimeOfDay t) => t.hour * 60 + t.minute;
String _hhmm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class SleepDial extends StatefulWidget {
  final TimeOfDay bedtime;
  final TimeOfDay wake;
  final ValueChanged<TimeOfDay> onBedtimeChanged;
  final ValueChanged<TimeOfDay> onWakeChanged;
  final double size;

  const SleepDial({
    super.key,
    required this.bedtime,
    required this.wake,
    required this.onBedtimeChanged,
    required this.onWakeChanged,
    this.size = 280,
  });

  @override
  State<SleepDial> createState() => _SleepDialState();
}

enum _Handle { bed, wake }

class _SleepDialState extends State<SleepDial> {
  _Handle? _dragging;

  static const double _stroke = 30;

  double get _radius => widget.size / 2 - _stroke / 2 - 4;

  Offset _handleCenter(TimeOfDay t) {
    final a = angleForMinutes(_min(t));
    return Offset(math.sin(a), -math.cos(a)) * _radius +
        Offset(widget.size / 2, widget.size / 2);
  }

  void _start(Offset local) {
    final bed = (local - _handleCenter(widget.bedtime)).distance;
    final wake = (local - _handleCenter(widget.wake)).distance;
    // 只抓得到把手附近；點在別處不動，避免一碰就跳。
    const grab = 34.0;
    if (bed > grab && wake > grab) return;
    _dragging = bed <= wake ? _Handle.bed : _Handle.wake;
  }

  void _move(Offset local) {
    final h = _dragging;
    if (h == null) return;
    final t = _tod(
      minutesForOffset(local - Offset(widget.size / 2, widget.size / 2)),
    );
    if (h == _Handle.bed) {
      if (t != widget.bedtime) widget.onBedtimeChanged(t);
    } else {
      if (t != widget.wake) widget.onWakeChanged(t);
    }
  }

  @override
  Widget build(BuildContext context) {
    final span = sleepSpan(widget.bedtime, widget.wake);
    return GestureDetector(
      key: const Key('sleep-dial'),
      onPanStart: (d) => _start(d.localPosition),
      onPanUpdate: (d) => _move(d.localPosition),
      onPanEnd: (_) => _dragging = null,
      child: SizedBox.square(
        dimension: widget.size,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _DialPainter(
                  bed: _min(widget.bedtime),
                  wake: _min(widget.wake),
                  radius: _radius,
                  stroke: _stroke,
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Bedtime',
                    style: TextStyle(
                      color: SonnapColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    _hhmm(widget.bedtime),
                    key: const Key('dial-bedtime'),
                    style: const TextStyle(
                      color: SonnapColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: widget.size * 0.56,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        formatSpan(span),
                        key: const Key('dial-span'),
                        style: const TextStyle(
                          color: Color(0xFFB9A6FF),
                          fontSize: 44,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Wake up',
                    style: TextStyle(
                      color: SonnapColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    _hhmm(widget.wake),
                    key: const Key('dial-wake'),
                    style: const TextStyle(
                      color: SonnapColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            _handle(
              widget.bedtime,
              Icons.nightlight_round,
              const Color(0xFF5B4BFF),
            ),
            _handle(
              widget.wake,
              Icons.wb_sunny_rounded,
              const Color(0xFFFF7AD9),
            ),
          ],
        ),
      ),
    );
  }

  Widget _handle(TimeOfDay t, IconData icon, Color color) {
    final c = _handleCenter(t);
    const d = 38.0;
    return Positioned(
      left: c.dx - d / 2,
      top: c.dy - d / 2,
      child: IgnorePointer(
        child: Container(
          width: d,
          height: d,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 10),
            ],
          ),
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  final int bed;
  final int wake;
  final double radius;
  final double stroke;

  _DialPainter({
    required this.bed,
    required this.wake,
    required this.radius,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: c, radius: radius);

    // 底圈
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Colors.white.withValues(alpha: 0.10),
    );

    // 刻度：每 3 小時一個小點，00／06／12／18 標字
    for (var h = 0; h < 24; h++) {
      final a = angleForMinutes(h * 60);
      final p =
          c + Offset(math.sin(a), -math.cos(a)) * (radius - stroke / 2 - 12);
      if (h % 6 == 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: h.toString().padLeft(2, '0'),
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
      } else if (h % 3 == 0) {
        canvas.drawCircle(p, 1.5, Paint()..color = Colors.white24);
      }
    }

    // 睡眠那一段：紫 → 粉漸層，從就寢順時針到起床
    final start = angleForMinutes(bed) - math.pi / 2;
    var sweep = angleForMinutes((wake - bed) % (24 * 60));
    if (sweep <= 0) sweep = 0.0001;
    final shader = SweepGradient(
      startAngle: 0,
      endAngle: sweep,
      colors: const [Color(0xFF5B4BFF), Color(0xFFB04BFF), Color(0xFFFF7AD9)],
      transform: GradientRotation(start),
    ).createShader(rect);
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant _DialPainter old) =>
      old.bed != bed || old.wake != wake;
}
