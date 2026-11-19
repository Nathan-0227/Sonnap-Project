import 'dart:math' as math;

import 'package:flutter/material.dart';

// 早晨報告「Last night」的圖（2026-11-15 使用者定 Q1–Q7）：每一格整張是圖、標題左上、字左下，
// 跟 Yesterday 同一套（`ReportArtTile`）。**圖就是那個數字**，不是裝飾：
// - Total sleep：極光光帶從左往右填，亮的長度＝睡了多久÷目標（超過就滿、不變色）；不放月亮（使用者定）
// - Time in bed：12 小時鐘面（使用者給參考圖），上床（月亮圖示）到下床（鬧鐘圖示）那段亮、多久寫在圓心
// - Phone down：半圓鐘面，空心圈＝目標、亮點＝實際放下手機，中間一道淡光（不分好壞，同一色）
// - Awake：一條星河，醒著的那幾段亮起琥珀色光點（位置＝整晚的哪裡）
// - Sleeping HR：靛藍色的慢線，**不跳、不用紅**（跟會跳的珊瑚紅 Awake HR 分開）；不放月亮（使用者定）
// - Movement (camera)：光柱（使用者給參考圖），每 5 分鐘一根、高度＝那 5 分鐘有幾成在動，高的轉金色（只呈現、不算分）
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
  }

  @override
  bool shouldRepaint(AuroraFillPainter old) =>
      old.fraction != fraction || old.color != color;
}

// ── Time in bed：12 小時鐘面（11-15 使用者給參考圖）──
// 一圈＝12 小時（12 在上），上床到下床那一段亮；起點是月亮圖示、終點是鬧鐘圖示。
// 字（多久）寫在圓心，時刻寫在底下。

/// 時刻在 12 小時鐘面上的角度（12 點在正上方、順時針）。
double bedClockAngle(int hour, int minute) =>
    -math.pi / 2 + 2 * math.pi * ((hour % 12) + minute / 60) / 12;

class BedClockPainter extends CustomPainter {
  /// 上床、下床的 (時, 分)；start 為 null＝沒按（只畫空的錶面）。
  final (int, int)? start;
  final (int, int)? end;

  /// 上床到下床幾分鐘（超過 12 小時畫滿一圈）。
  final double? minutes;
  final Color color;
  BedClockPainter(this.start, this.end, this.minutes, this.color);

  /// 圓心（相對格子大小），字也照這個位置擺。
  static const double centerY = 0.47;

  static double radius(Size s) => math.min(s.width * 0.34, s.height * 0.3);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width * 0.5, size.height * centerY);
    final r = radius(size);
    final stroke = r * 0.2;
    final rect = Rect.fromCircle(center: c, radius: r);

    // 錶面：底圈（淡紫）＋內圈細線＋ 12／3／6／9
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = color.withValues(alpha: 0.22),
    );
    canvas.drawCircle(
      c,
      r - stroke * 0.75,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x22FFFFFF),
    );
    for (final (h, label) in [(0, '12'), (3, '3'), (6, '6'), (9, '9')]) {
      final a = bedClockAngle(h, 0);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 8),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final at = c + Offset(math.cos(a), math.sin(a)) * (r - stroke * 1.45);
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }

    final s = start;
    if (s == null) return;
    final a0 = bedClockAngle(s.$1, s.$2);
    final e = end;
    final m = minutes;
    if (e != null && m != null && m > 0) {
      final sweep = math.min(2 * math.pi * m / 720, 2 * math.pi - 0.001);
      canvas.drawArc(
        rect,
        a0,
        sweep,
        false,
        _glow(color, stroke * 1.3, stroke * 0.5),
      );
      canvas.drawArc(
        rect,
        a0,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            startAngle: 0,
            endAngle: 2 * math.pi,
            transform: GradientRotation(a0),
            colors: [
              Color.lerp(color, Colors.white, 0.1)!,
              color,
              Color.lerp(color, const Color(0xFF5B6CFF), 0.4)!,
            ],
            stops: [0, (sweep / (2 * math.pi)) * 0.6, sweep / (2 * math.pi)],
          ).createShader(rect),
      );
      _knob(
        canvas,
        c,
        r,
        bedClockAngle(e.$1, e.$2),
        stroke,
        Icons.alarm_rounded,
      );
    }
    _knob(canvas, c, r, a0, stroke, Icons.bedtime_rounded);
  }

  /// 弧上的小白圓＋圖示（參考圖的月亮與鬧鐘）。
  void _knob(
    Canvas canvas,
    Offset c,
    double r,
    double a,
    double stroke,
    IconData icon,
  ) {
    final at = c + Offset(math.cos(a), math.sin(a)) * r;
    final kr = stroke * 0.95;
    canvas.drawCircle(
      at,
      kr * 1.4,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, kr * 0.5),
    );
    canvas.drawCircle(at, kr, Paint()..color = const Color(0xFFEDEBFF));
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: kr * 1.3,
          color: const Color(0xFF3A3F8F),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(BedClockPainter old) =>
      old.start != start ||
      old.end != end ||
      old.minutes != minutes ||
      old.color != color;
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

// ── Movement (camera)：光柱（11-15 使用者給參考圖）──
// 每 5 分鐘一根柱子，高度＝那 5 分鐘裡有幾成時間在動（後端的 motion_curve，照抄不平滑）；
// 越高越從淡紫轉成金色、帶光暈。底下一條時間軸（整點刻度），兩個下角淡淡的雲。
// 0＝那 5 分鐘沒動（是真的值）：畫成很淡的短柱，不是空著。只呈現、不算分。

class CameraBarsPainter extends CustomPainter {
  /// (時刻, 0–1)；空的＝沒有曲線（只畫星星與雲）。
  final List<(DateTime, double)> points;

  /// 給了就**不標整點**，時間軸兩端改寫這兩個字（例如 Fell asleep／Woke up）。
  /// 朋友選了「只寫準時與否」時用：光柱照畫，但不露幾點（2026-11-19 使用者定）。
  final (String, String)? endLabels;
  CameraBarsPainter(this.points, {this.endLabels});

  static const lavender = Color(0xFF8C7BEA);
  static const gold = Color(0xFFFFD96A);

  /// 柱子底線的位置（相對高度）；時刻標在它下面。
  static const double baseY = 0.47;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    _drawStars(
      canvas,
      Rect.fromLTWH(w * 0.3, h * 0.08, w * 0.68, h * 0.4),
      22,
      13,
      0.6,
    );
    // 兩個下角的雲
    final cloud = Paint()
      ..color = const Color(0xFF7B6CE0).withValues(alpha: 0.35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.06);
    for (final (x, y, r) in [
      (0.02, 0.96, 0.2),
      (0.1, 1.02, 0.16),
      (0.86, 0.94, 0.2),
      (0.96, 0.86, 0.16),
      (0.75, 1.02, 0.18),
    ]) {
      canvas.drawCircle(Offset(w * x, h * y), h * r, cloud);
    }
    if (points.length < 2) return;

    final x0 = w * 0.06, x1 = w * 0.94;
    final base = h * baseY;
    final maxH = h * 0.26;
    final t0 = points.first.$1, t1 = points.last.$1;
    final span = t1.difference(t0).inSeconds.toDouble();
    if (span <= 0) return;
    double xOf(DateTime t) =>
        x0 + (x1 - x0) * t.difference(t0).inSeconds / span;
    var hi = 0.0;
    for (final p in points) {
      hi = math.max(hi, p.$2);
    }
    final step = (x1 - x0) / (points.length - 1);
    final barW = (step * 0.62).clamp(1.5, 7.0);

    // 時間軸＋整點刻度（夜長 ≥ 4 小時每 3 小時一格，不然每小時）
    canvas.drawLine(
      Offset(x0, base + 6),
      Offset(x1, base + 6),
      Paint()
        ..color = lavender.withValues(alpha: 0.55)
        ..strokeWidth = 1.2,
    );
    if (endLabels case (final left, final right)) {
      for (final (text, atLeft) in [(left, true), (right, false)]) {
        final tp = TextPainter(
          text: TextSpan(
            text: text,
            style: const TextStyle(
              color: Color(0xB3C9C0FF),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(atLeft ? x0 : x1 - tp.width, base + 12));
      }
    }
    final every = span >= 4 * 3600 ? 3 : 1;
    var tick = DateTime(
      t0.year,
      t0.month,
      t0.day,
      t0.hour,
    ).add(const Duration(hours: 1));
    while (endLabels == null && !tick.isAfter(t1)) {
      if (tick.hour % every == 0) {
        final x = xOf(tick);
        canvas.drawLine(
          Offset(x, base + 3),
          Offset(x, base + 10),
          Paint()
            ..color = lavender.withValues(alpha: 0.7)
            ..strokeWidth = 1.2,
        );
        final tp = TextPainter(
          text: TextSpan(
            text: tick.hour.toString().padLeft(2, '0'),
            style: const TextStyle(
              color: Color(0xB3C9C0FF),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, base + 12));
      }
      tick = tick.add(const Duration(hours: 1));
    }

    // 柱子
    for (final (t, v) in points) {
      final f = hi <= 0 ? 0.0 : (v / hi).clamp(0.0, 1.0);
      final x = xOf(t);
      final bh = math.max(3.0, maxH * f);
      final color = Color.lerp(
        lavender,
        gold,
        ((f - 0.35) / 0.5).clamp(0.0, 1.0),
      )!;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x - barW / 2, base - bh, barW, bh),
        Radius.circular(barW / 2),
      );
      if (f > 0.5) {
        canvas.drawRRect(
          rect.inflate(barW * 0.8),
          Paint()
            ..color = gold.withValues(alpha: 0.35 * f)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, barW * 1.6),
        );
      }
      canvas.drawRRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              color.withValues(alpha: v <= 0 ? 0.25 : 0.55),
              color.withValues(alpha: v <= 0 ? 0.3 : 0.6 + 0.4 * f),
            ],
          ).createShader(rect.outerRect),
      );
    }
  }

  @override
  bool shouldRepaint(CameraBarsPainter old) =>
      old.points != points || old.endLabels != endLabels;
}

/// Movement (camera) 的大字：「18 moves / hour」（後端的 events_per_hour，四捨五入到整數；1 次寫 move）。
String cameraPerHourText(double perHour) {
  final n = perHour.round();
  return '$n move${n == 1 ? '' : 's'} / hour';
}

/// 鋪滿整張卡的 CustomPaint。
Widget lastNightArt(CustomPainter painter, {Key? key}) =>
    CustomPaint(key: key, painter: painter, size: Size.infinite);
