import 'dart:math' as math;

import 'package:flutter/material.dart';

// 早晨報告「Last night」的圖（2026-11-15 使用者定 Q1–Q7）：每一格整張是圖、標題左上、字左下，
// 跟 Yesterday 同一套（`ReportArtTile`）。**圖就是那個數字**，不是裝飾：
// - Total sleep：極光光帶從左往右填，亮的長度＝睡了多久÷目標（超過就滿、不變色），月亮停在填到的地方
// - Time in bed：夜空弧 18:00（月亮）→ 12:00（日出），上床到下床那段亮
// - Phone down：半圓鐘面，空心圈＝目標、亮點＝實際放下手機，中間一道淡光（不分好壞，同一色）
// - Awake：一條星河，醒著的那幾段亮起琥珀色光點（位置＝整晚的哪裡）
// - Sleeping HR：靛藍色的慢線＋月亮，**不跳、不用紅**（跟會跳的珊瑚紅 Awake HR 分開）
// - Movement (camera)：床的輪廓＋動作曲線，動得多的那幾刻泛出漣漪（只呈現、不算分）
// （Efficiency 維持使用者喜歡的「從底下填滿」，另外加了水面的動態：report_tiles.dart LiquidFill。）
// 字寫在底下，所以圖都放在中間偏上、底下 40% 留給字。

/// 每次畫都一樣的星星（固定種子）：不同晚上不會因為重畫而亂跳。
List<Offset> _stars(int n, int seed) {
  final r = math.Random(seed);
  return [for (var i = 0; i < n; i++) Offset(r.nextDouble(), r.nextDouble())];
}

void _drawStars(Canvas canvas, Rect area, int n, int seed, double alpha) {
  final p = Paint();
  for (final (i, s) in _stars(n, seed).indexed) {
    p.color = Colors.white.withValues(
      alpha: alpha * (0.4 + 0.6 * ((i * 37) % 10) / 10),
    );
    canvas.drawCircle(
      Offset(area.left + s.dx * area.width, area.top + s.dy * area.height),
      0.6 + (i % 3) * 0.35,
      p,
    );
  }
}

/// 一彎月亮（用兩個圓相減）。
void _drawMoon(Canvas canvas, Offset c, double r, Color color) {
  canvas.drawCircle(
    c,
    r * 1.9,
    Paint()
      ..color = color.withValues(alpha: 0.25)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r),
  );
  final moon = Path.combine(
    PathOperation.difference,
    Path()..addOval(Rect.fromCircle(center: c, radius: r)),
    Path()..addOval(
      Rect.fromCircle(center: c + Offset(r * 0.45, -r * 0.3), radius: r * 0.85),
    ),
  );
  canvas.drawPath(moon, Paint()..color = const Color(0xFFFFF4D6));
}

Paint _glow(Color c, double width, double blur) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..color = c.withValues(alpha: 0.45)
  ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);

Paint _line(Color c, double width) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..color = c;

const _dim = Color(0x1FFFFFFF);

// ── Total sleep：極光光帶 ──

class AuroraFillPainter extends CustomPainter {
  /// 睡了多久÷目標；null＝手錶還沒到（只畫暗的光帶）。超過 1 畫滿。
  final double? fraction;
  final Color color;
  AuroraFillPainter(this.fraction, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final x0 = w * 0.08, x1 = w * 0.92;
    double cy(double x) =>
        h * 0.42 +
        h * 0.055 * math.sin((x - x0) / (x1 - x0) * 2 * math.pi * 1.1);
    final thick = h * 0.13;
    Path band(double from, double to) {
      final p = Path();
      var first = true;
      for (var x = from; x <= to; x += 2) {
        final y = cy(x) - thick / 2;
        first ? p.moveTo(x, y) : p.lineTo(x, y);
        first = false;
      }
      for (var x = to; x >= from; x -= 2) {
        p.lineTo(x, cy(x) + thick / 2);
      }
      return p..close();
    }

    canvas.drawPath(band(x0, x1), Paint()..color = _dim);
    final f = fraction;
    if (f == null) return;
    final xf = x0 + (x1 - x0) * f.clamp(0.0, 1.0);
    if (xf - x0 > 2) {
      final lit = band(x0, xf);
      canvas.drawPath(
        lit,
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, thick * 0.6),
      );
      canvas.drawPath(
        lit,
        Paint()
          ..shader = LinearGradient(
            colors: [
              color.withValues(alpha: 0.55),
              color,
              Color.lerp(color, Colors.white, 0.45)!,
            ],
          ).createShader(Rect.fromLTRB(x0, 0, xf, h)),
      );
      canvas.save();
      canvas.clipPath(lit);
      _drawStars(canvas, Rect.fromLTRB(x0, 0, xf, h), 26, 7, 0.9);
      canvas.restore();
    }
    _drawMoon(canvas, Offset(xf, cy(xf) - thick * 1.25), h * 0.055, color);
  }

  @override
  bool shouldRepaint(AuroraFillPainter old) =>
      old.fraction != fraction || old.color != color;
}

// ── Time in bed：夜空弧 18:00 → 12:00 ──

class NightArcPainter extends CustomPainter {
  /// 從 18:00 起算的分鐘數（0–1080）；null＝沒按上床（只畫空的弧）。
  final double? start;
  final double? end;
  final Color color;
  NightArcPainter(this.start, this.end, this.color);

  static const span = 1080.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final c = Offset(w * 0.5, h * 0.66);
    final r = math.min(w * 0.4, h * 0.44);
    final rect = Rect.fromCircle(center: c, radius: r);
    double ang(double m) => math.pi + math.pi * (m.clamp(0, span) / span);
    Offset at(double m) => c + Offset(math.cos(ang(m)), math.sin(ang(m))) * r;

    _drawStars(canvas, Rect.fromLTWH(0, h * 0.12, w, h * 0.5), 18, 3, 0.5);
    canvas.drawArc(rect, math.pi, math.pi, false, _line(_dim, 6));
    // 兩端：左邊月亮（傍晚）、右邊日出的光
    _drawMoon(canvas, at(0) + const Offset(0, 10), 5, color);
    canvas.drawCircle(
      at(span) + const Offset(0, 8),
      9,
      Paint()
        ..color = const Color(0xFFFFC98A).withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    final s = start;
    if (s == null) return;
    final e = end;
    if (e != null && e > s) {
      canvas.drawArc(rect, ang(s), ang(e) - ang(s), false, _glow(color, 10, 5));
      canvas.drawArc(rect, ang(s), ang(e) - ang(s), false, _line(color, 6));
      canvas.drawCircle(at(e), 4.5, Paint()..color = Colors.white);
    }
    canvas.drawCircle(at(s), 4.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(NightArcPainter old) =>
      old.start != start || old.end != end || old.color != color;
}

// ── Phone down：半圓鐘面 ──

class PhoneDialPainter extends CustomPainter {
  /// 從 18:00 起算的分鐘數；target 可能沒有。
  final double? target;
  final double actual;
  final Color color;
  PhoneDialPainter(this.target, this.actual, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final t = target ?? actual;
    var lo = math.min(t, actual) - 60;
    var hi = math.max(t, actual) + 60;
    if (hi - lo < 180) {
      final pad = (180 - (hi - lo)) / 2;
      lo -= pad;
      hi += pad;
    }
    final c = Offset(w * 0.5, h * 0.56);
    final r = math.min(w * 0.36, h * 0.36);
    final rect = Rect.fromCircle(center: c, radius: r);
    double ang(double m) => math.pi + math.pi * ((m - lo) / (hi - lo));
    Offset at(double m) => c + Offset(math.cos(ang(m)), math.sin(ang(m))) * r;

    // 鐘面：底弧＋刻度
    canvas.drawArc(rect, math.pi, math.pi, false, _line(_dim, 8));
    final tick = Paint()
      ..color = const Color(0x40FFFFFF)
      ..strokeWidth = 1.2;
    for (var i = 0; i <= 8; i++) {
      final a = math.pi + math.pi * i / 8;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (r - 14), c + d * (r - 9), tick);
    }
    // 中間一支淡淡的手機
    final phone = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: c - Offset(0, r * 0.28),
        width: r * 0.32,
        height: r * 0.52,
      ),
      const Radius.circular(5),
    );
    canvas.drawRRect(
      phone,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0x40FFFFFF),
    );
    if (target != null) {
      final a0 = ang(math.min(t, actual)), a1 = ang(math.max(t, actual));
      if (a1 - a0 > 0.01) {
        canvas.drawArc(rect, a0, a1 - a0, false, _glow(color, 12, 6));
        canvas.drawArc(
          rect,
          a0,
          a1 - a0,
          false,
          _line(color.withValues(alpha: 0.7), 8),
        );
      }
      // 目標：空心圈
      canvas.drawCircle(
        at(t),
        6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: 0.85),
      );
    }
    // 實際：亮點
    canvas.drawCircle(
      at(actual),
      9,
      Paint()
        ..color = color.withValues(alpha: 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(at(actual), 5.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(PhoneDialPainter old) =>
      old.target != target || old.actual != actual || old.color != color;
}

// ── Awake：星河 ──

class StarRiverPainter extends CustomPainter {
  /// 醒著的那幾段（入睡 → 起床的 0–1）；null＝沒有逐段資料（只畫河）。
  final List<(double, double)>? segments;
  final Color color;
  StarRiverPainter(this.segments, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final x0 = w * 0.06, x1 = w * 0.94;
    double cy(double x) =>
        h * 0.42 +
        h * 0.04 * math.sin((x - x0) / (x1 - x0) * 2 * math.pi * 0.8 + 0.6);
    final thick = h * 0.16;
    final river = Path();
    for (var x = x0; x <= x1; x += 2) {
      final y = cy(x) - thick / 2;
      x == x0 ? river.moveTo(x, y) : river.lineTo(x, y);
    }
    for (var x = x1; x >= x0; x -= 2) {
      river.lineTo(x, cy(x) + thick / 2);
    }
    river.close();
    canvas.drawPath(
      river,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x664A5BC4), Color(0x99223079), Color(0x664A5BC4)],
        ).createShader(Rect.fromLTRB(x0, 0, x1, h)),
    );
    canvas.save();
    canvas.clipPath(river);
    _drawStars(canvas, Rect.fromLTRB(x0, 0, x1, h), 40, 11, 0.55);
    canvas.restore();
    for (final (a, b) in segments ?? const <(double, double)>[]) {
      final xa = x0 + (x1 - x0) * a.clamp(0.0, 1.0);
      final xb = math.max(xa + 3, x0 + (x1 - x0) * b.clamp(0.0, 1.0));
      final mid = (xa + xb) / 2;
      final spark = Rect.fromCenter(
        center: Offset(mid, cy(mid)),
        width: xb - xa + 6,
        height: thick * 0.75,
      );
      canvas.drawOval(
        spark.inflate(5),
        Paint()
          ..color = color.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(spark, Radius.circular(thick)),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(StarRiverPainter old) =>
      old.segments != segments || old.color != color;
}

// ── Sleeping HR：靛藍的慢線＋月亮 ──

class SleepHrWavePainter extends CustomPainter {
  /// (x 0–1, bpm)；空的＝沒有曲線（只畫月亮）。
  final List<(double, double)> points;
  final Color color;
  SleepHrWavePainter(this.points, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    _drawStars(canvas, Rect.fromLTWH(0, h * 0.12, w, h * 0.45), 16, 5, 0.45);
    _drawMoon(canvas, Offset(w * 0.8, h * 0.24), h * 0.06, color);
    if (points.length < 2) return;
    var lo = points.first.$2, hi = points.first.$2;
    for (final p in points) {
      lo = math.min(lo, p.$2);
      hi = math.max(hi, p.$2);
    }
    if (hi - lo < 6) {
      final m = (hi + lo) / 2;
      lo = m - 3;
      hi = m + 3;
    }
    final top = h * 0.3, bottom = h * 0.58;
    Offset at((double, double) p) => Offset(
      w * 0.06 + w * 0.88 * p.$1,
      bottom - (bottom - top) * (p.$2 - lo) / (hi - lo),
    );
    // 平滑：相鄰兩點的中點當轉折（不衝出最高最低之外）
    final pts = [for (final p in points) at(p)];
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final mid = (pts[i - 1] + pts[i]) / 2;
      line.quadraticBezierTo(pts[i - 1].dx, pts[i - 1].dy, mid.dx, mid.dy);
    }
    line.lineTo(pts.last.dx, pts.last.dy);
    final area = Path.from(line)
      ..lineTo(pts.last.dx, h * 0.66)
      ..lineTo(pts.first.dx, h * 0.66)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0)],
        ).createShader(Rect.fromLTRB(0, top, w, h * 0.66)),
    );
    canvas.drawPath(line, _glow(color, 6, 4));
    canvas.drawPath(line, _line(Color.lerp(color, Colors.white, 0.25)!, 2));
  }

  @override
  bool shouldRepaint(SleepHrWavePainter old) =>
      old.points != points || old.color != color;
}

// ── Movement (camera)：床＋動作曲線＋漣漪 ──

class BedRipplePainter extends CustomPainter {
  /// (x 0–1, 那 5 分鐘有幾成時間在動 0–1)；空的＝沒有曲線。
  final List<(double, double)> points;
  final Color color;
  BedRipplePainter(this.points, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // 床（從上往下看）：右半邊淡淡的輪廓＋枕頭
    final bed = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.58, h * 0.12, w * 0.34, h * 0.56),
      const Radius.circular(14),
    );
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0x33FFFFFF);
    canvas.drawRRect(bed, outline);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.63, h * 0.16, w * 0.24, h * 0.1),
        const Radius.circular(8),
      ),
      outline,
    );
    if (points.length < 2) return;
    var hi = 0.0;
    for (final p in points) {
      hi = math.max(hi, p.$2);
    }
    if (hi <= 0) hi = 1;
    final base = h * 0.6, top = h * 0.24;
    Offset at((double, double) p) =>
        Offset(w * 0.04 + w * 0.92 * p.$1, base - (base - top) * p.$2 / hi);
    final pts = [for (final p in points) at(p)];
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    final area = Path.from(line)
      ..lineTo(pts.last.dx, base)
      ..lineTo(pts.first.dx, base)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.4), color.withValues(alpha: 0.02)],
        ).createShader(Rect.fromLTRB(0, top, w, base)),
    );
    canvas.drawPath(line, _line(color, 1.6)..strokeJoin = StrokeJoin.round);
    // 動得最多的三刻：漣漪
    final ranked = [...pts.indexed]
      ..sort((a, b) => points[b.$1].$2.compareTo(points[a.$1].$2));
    for (final (i, p) in ranked.take(3)) {
      if (points[i].$2 <= 0) continue;
      for (var k = 1; k <= 3; k++) {
        canvas.drawCircle(
          p,
          4.0 * k,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = color.withValues(alpha: 0.5 / k),
        );
      }
      canvas.drawCircle(p, 2.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(BedRipplePainter old) =>
      old.points != points || old.color != color;
}

/// 鋪滿整張卡的 CustomPaint。
Widget lastNightArt(CustomPainter painter, {Key? key}) =>
    CustomPaint(key: key, painter: painter, size: Size.infinite);
