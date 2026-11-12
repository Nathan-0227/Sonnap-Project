import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 首頁夜空上的動態效果：四角星一閃一閃地發亮，偶爾一道流星劃過。
///
/// 全部用程式畫（不用任何圖片素材）。只畫在天空那一塊（[height] 由首頁依
/// 背景圖的山頂高度算出），不會蓋到寵物與卡片。
///
/// ⚠️ 系統開了「減少動態效果」時只畫靜止的星星，不跑動畫。
class NightSkyEffects extends StatefulWidget {
  final double width;
  final double height;

  const NightSkyEffects({super.key, required this.width, required this.height});

  @override
  State<NightSkyEffects> createState() => _NightSkyEffectsState();
}

/// 一顆會閃的星：位置用寬高的比例表示，換手機尺寸也落在天空裡。
class _Sparkle {
  final double x, y, size, phase, speed;
  const _Sparkle(this.x, this.y, this.size, this.phase, this.speed);
}

/// 流星的週期：每 [kShootingStarPeriod] 劃過一次，每次 [kShootingStarFlight]。
const Duration kShootingStarPeriod = Duration(seconds: 7);
const double kShootingStarFlight = 0.16; // 佔週期的比例（約 1.1 秒）

class _NightSkyEffectsState extends State<NightSkyEffects>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // 固定種子：每次打開位置都一樣，畫面不會「跳」。
  static final List<_Sparkle> _sparkles = () {
    final r = math.Random(11);
    final out = <_Sparkle>[];
    while (out.length < 14) {
      final x = 0.04 + r.nextDouble() * 0.92;
      final y = 0.06 + r.nextDouble() * 0.74;
      final size = 5 + r.nextDouble() * 7;
      final phase = r.nextDouble() * math.pi * 2;
      final speed = 0.6 + r.nextDouble() * 1.2;
      // 左上角是問候文字，星星不要閃在字上。
      if (x < 0.62 && y < 0.36) continue;
      out.add(_Sparkle(x, y, size, phase, speed));
    }
    return out;
  }();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: kShootingStarPeriod,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: SizedBox(
          key: const Key('night-sky-effects'),
          width: widget.width,
          height: widget.height,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => CustomPaint(
              painter: _SkyPainter(
                t: _controller.value,
                sparkles: _sparkles,
                animate: _controller.isAnimating,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SkyPainter extends CustomPainter {
  final double t;
  final List<_Sparkle> sparkles;
  final bool animate;

  _SkyPainter({required this.t, required this.sparkles, required this.animate});

  /// 四角星：上下左右四個尖，中間微微內凹。
  static Path _star(Offset c, double r) {
    final inner = r * 0.22;
    final path = Path()..moveTo(c.dx, c.dy - r);
    final pts = [
      Offset(c.dx + inner, c.dy - inner),
      Offset(c.dx + r, c.dy),
      Offset(c.dx + inner, c.dy + inner),
      Offset(c.dx, c.dy + r),
      Offset(c.dx - inner, c.dy + inner),
      Offset(c.dx - r, c.dy),
      Offset(c.dx - inner, c.dy - inner),
    ];
    for (final p in pts) {
      path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    // ── 會閃的星 ──
    for (final s in sparkles) {
      final wave = animate
          ? (math.sin(t * math.pi * 2 * 4 * s.speed + s.phase) + 1) / 2
          : 0.6;
      final alpha = 0.25 + 0.75 * wave;
      final r = s.size * (0.75 + 0.35 * wave);
      final c = Offset(s.x * size.width, s.y * size.height);

      // 外圈光暈
      canvas.drawCircle(
        c,
        r * 1.6,
        Paint()
          ..color = const Color(0xFFFFE9A8).withValues(alpha: 0.18 * alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawPath(
        _star(c, r),
        Paint()..color = const Color(0xFFFFF3C4).withValues(alpha: alpha),
      );
    }

    // ── 流星：每個週期開頭劃過一次 ──
    if (!animate || t > kShootingStarFlight) return;
    final p = Curves.easeOut.transform(t / kShootingStarFlight);
    final fade = p < 0.8 ? 1.0 : (1 - p) / 0.2;
    final start = Offset(size.width * 0.15, size.height * 0.08);
    final end = Offset(size.width * 0.75, size.height * 0.48);
    final head = Offset.lerp(start, end, p)!;
    final dir = (end - start) / (end - start).distance;
    final tail = head - dir * size.width * 0.22;

    canvas.drawLine(
      tail,
      head,
      Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0x00FFFFFF),
            Colors.white.withValues(alpha: 0.9 * fade),
          ],
        ).createShader(Rect.fromPoints(tail, head))
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      head,
      3.2,
      Paint()
        ..color = Colors.white.withValues(alpha: fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  @override
  bool shouldRepaint(covariant _SkyPainter old) =>
      old.t != t || old.animate != animate;
}
