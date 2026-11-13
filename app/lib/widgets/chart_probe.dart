import 'package:flutter/material.dart';

import '../models/night_curve.dart';
import '../models/sleep_stages.dart';

/// 點圖上的線 → 那一刻的泡泡（2026-11-13 使用者定，照參考圖：白點＋小標籤）。
///
/// 規則（使用者逐題定）：
/// - 點一下或按住左右滑，泡泡跟著走；放開後留著，點圖以外的地方才收。
/// - **吸到最近的真實資料點**，不用線上內插的值（內插的數字手錶沒量過）。
/// - 那一刻附近沒有讀數（離最近的點超過一個取樣間隔）→ 寫 `no reading`，不吸到遠處、不寫 0。
/// - 只寫事實：不寫 Normal／High、不判斷好壞。
/// - 手錶動作沒有單位 → 只寫 Moving／Still（0 是真的沒動）。
/// - 攝影機是那 5 分鐘裡有幾成時間在動 → 換成動了多久：`moving 12 sec`。
enum ProbeKind { heartRate, watchMovement, camera }

const stageNames = {
  'awake': 'Awake',
  'rem': 'REM',
  'light': 'Light',
  'deep': 'Deep',
};

/// 那一刻的睡眠階段；不在任何一段裡回 null。
String? stageAt(SleepStages s, DateTime t) {
  for (final seg in s.segments) {
    if (!t.isBefore(seg.start) && t.isBefore(seg.end)) return seg.stage;
  }
  return null;
}

/// 離 [t] 最近的真實讀數；最近的也超過 [maxGap] 就回 null（＝那一刻沒有讀數）。
NightCurvePoint? nearestPoint(
  List<NightCurvePoint> points,
  DateTime t, {
  Duration maxGap = const Duration(minutes: 5),
}) {
  NightCurvePoint? best;
  Duration? bestD;
  for (final p in points) {
    final d = p.time.difference(t).abs();
    if (bestD == null || d < bestD) {
      best = p;
      bestD = d;
    }
  }
  if (best == null || bestD! > maxGap) return null;
  return best;
}

String hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 數值那一段的字；沒有讀數寫 no reading。
String probeValue(ProbeKind kind, NightCurvePoint? p) {
  if (p == null) return 'no reading';
  return switch (kind) {
    ProbeKind.heartRate => '${p.value.round()} bpm',
    ProbeKind.watchMovement => p.value > 0 ? 'Moving' : 'Still',
    ProbeKind.camera => 'moving ${_cameraSeconds(p.value)}',
  };
}

/// 攝影機那 5 分鐘裡在動的比例 → 動了多久（使用者 2026-11-13：「moving 12 sec」比「4% of 5 min」好懂）。
String _cameraSeconds(double fraction) {
  final sec = (fraction.clamp(0.0, 1.0) * 300).round();
  if (sec < 60) return '$sec sec';
  final m = sec ~/ 60, r = sec % 60;
  return r == 0 ? '$m min' : '$m min $r sec';
}

/// 泡泡整句：`02:41 · 58 bpm · Deep`（沒選線時 `02:41 · Deep`）。
String probeText({
  required DateTime time,
  ProbeKind? kind,
  NightCurvePoint? point,
  String? stage,
}) =>
    [
      hhmm(time),
      if (kind != null) probeValue(kind, point),
      if (stage != null) stageNames[stage] ?? stage,
    ].join(' · ');

/// 疊在圖上的那一層：白點＋泡泡。泡泡放在白點上方，上面放不下就放下方；左右不超出圖。
class ProbeLayer extends StatelessWidget {
  final Offset dot;
  final String text;
  const ProbeLayer({super.key, required this.dot, required this.text});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          CustomPaint(painter: _DotPainter(dot)),
          CustomSingleChildLayout(
            delegate: _BubbleLayout(dot),
            child: Container(
              key: const Key('chart-probe'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                text,
                key: const Key('chart-probe-text'),
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(
                  color: Color(0xFF3A3F6B),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  final Offset dot;
  _DotPainter(this.dot);

  @override
  void paint(Canvas canvas, Size size) {
    // 一條很淡的直線標出那一刻，再一個白圈
    canvas.drawLine(
      Offset(dot.dx, 0),
      Offset(dot.dx, size.height),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(dot, 6, Paint()..color = Colors.white);
    canvas.drawCircle(dot, 3, Paint()..color = const Color(0xFF6B6FA8));
  }

  @override
  bool shouldRepaint(covariant _DotPainter old) => old.dot != dot;
}

class _BubbleLayout extends SingleChildLayoutDelegate {
  final Offset dot;
  _BubbleLayout(this.dot);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) => c.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    var x = dot.dx - child.width / 2;
    x = x.clamp(0.0, (size.width - child.width).clamp(0.0, double.infinity));
    var y = dot.dy - child.height - 10;
    if (y < 0) y = dot.dy + 10;
    if (y + child.height > size.height) {
      y = (size.height - child.height).clamp(0.0, double.infinity);
    }
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(covariant _BubbleLayout old) => old.dot != dot;
}

/// 把點／滑的手勢變成「圖上的 x」：點一下、按住左右滑都算；點圖以外的地方 → [onClear]。
class ProbeGestures extends StatelessWidget {
  final ValueChanged<double> onX;
  final VoidCallback onClear;
  final Widget child;

  /// 同一個 groupId 的 [TapRegion] 不算「圖外面」（Sleep Stages 卡下面那幾顆切換線的按鈕）。
  final Object? groupId;
  const ProbeGestures({
    super.key,
    required this.onX,
    required this.onClear,
    required this.child,
    this.groupId,
  });

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: groupId,
      onTapOutside: (_) => onClear(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => onX(d.localPosition.dx),
        onHorizontalDragStart: (d) => onX(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => onX(d.localPosition.dx),
        child: child,
      ),
    );
  }
}
