import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/report_style.dart';

/// 睡眠計畫的大方形勾勾（2026-11-19 使用者 grill 定，Q36／Q41–Q46）。
///
/// 勾下去的那一下**只有當下的回饋，不累積任何東西**（沒有點數、沒有 XP）：
///   - 方格縮一下再彈大，冒一圈金色光點（約半秒）
///   - 方格上方浮出「Nice!」往上飄、淡掉——**只用這一個詞**，不輪換成 Great job／Amazing
///     （越誇張越像在誇睡得好，而打勾只代表「你說你做了」）
///   - 手機輕震一下
///   - 通知外面（[onChecked]）讓寵物跳一下
/// 取消勾選：什麼都沒有（不彈、不提示）。
/// 系統開「減少動態效果」：不彈、不飄、不冒光點；變色、Nice! 文字、震動照留。
class PlanCheckButton extends StatefulWidget {
  final bool checked;
  final bool enabled;
  final VoidCallback onToggle;

  /// 從沒勾變成勾的那一下（取消勾選不會呼叫）。
  final VoidCallback? onChecked;
  final double size;

  const PlanCheckButton({
    super.key,
    required this.checked,
    required this.enabled,
    required this.onToggle,
    this.onChecked,
    this.size = 54,
  });

  @override
  State<PlanCheckButton> createState() => _PlanCheckButtonState();
}

/// 「Nice!」留在畫面上多久（減少動態效果時也一樣，只是不飄）。
const Duration kNiceDuration = Duration(milliseconds: 900);

class _PlanCheckButtonState extends State<PlanCheckButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: kNiceDuration);
  bool _showNice = false;
  Timer? _niceTimer;

  @override
  void dispose() {
    _niceTimer?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _tap() {
    final becomingChecked = !widget.checked;
    widget.onToggle();
    if (!becomingChecked) return; // 取消勾選：沒有任何回饋
    HapticFeedback.lightImpact();
    widget.onChecked?.call();
    _niceTimer?.cancel();
    setState(() => _showNice = true);
    _niceTimer = Timer(kNiceDuration, () {
      if (mounted) setState(() => _showNice = false);
    });
    if (!MediaQuery.disableAnimationsOf(context)) _c.forward(from: 0);
  }

  /// 0→0.25 縮到 0.82、→0.6 彈到 1.12、→1 回到 1。
  double _scale(double t) {
    if (t <= 0 || t >= 1) return 1;
    if (t < 0.25) return 1 - 0.18 * (t / 0.25);
    if (t < 0.6) return 0.82 + 0.30 * ((t - 0.25) / 0.35);
    return 1.12 - 0.12 * ((t - 0.6) / 0.4);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      label: widget.checked ? 'Done' : 'Mark done',
      child: SizedBox(
        width: s,
        height: s,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (context, child) {
                final t = _c.isAnimating ? _c.value : 1.0;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (_c.isAnimating && t < 0.7)
                      Positioned(
                        left: -s,
                        top: -s,
                        width: s * 3,
                        height: s * 3,
                        child: IgnorePointer(child: CustomPaint(painter: _Sparkles(t / 0.7))),
                      ),
                    Transform.scale(scale: _scale(t), child: child),
                  ],
                );
              },
              child: InkWell(
                onTap: widget.enabled ? _tap : null,
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: still ? Duration.zero : const Duration(milliseconds: 160),
                  width: s,
                  height: s,
                  decoration: BoxDecoration(
                    color: widget.checked ? ReportColors.gold : Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: widget.checked ? ReportColors.gold : ReportColors.border, width: 1.5),
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    size: s * 0.56,
                    color: widget.checked ? ReportColors.navy : Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ),
            if (_showNice)
              Positioned(
                left: -20,
                right: -20,
                bottom: s + 2,
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) {
                      final t = still ? 0.0 : _c.value;
                      return Opacity(
                        opacity: still ? 1 : (1 - math.max(0, t - 0.55) / 0.45).clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, -26 * t),
                          child: const Text(
                            'Nice!',
                            key: Key('plan-nice'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: ReportColors.gold,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 一圈 8 顆金色小光點，從方格邊往外飛、淡掉。t：0→1。
class _Sparkles extends CustomPainter {
  final double t;
  _Sparkles(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final base = size.width / 6;
    final p = Paint()..color = ReportColors.gold.withValues(alpha: (1 - t).clamp(0.0, 1.0));
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4 + math.pi / 8;
      final r = base * (0.9 + 0.9 * t);
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r, 3.2 * (1 - 0.5 * t), p);
    }
  }

  @override
  bool shouldRepaint(_Sparkles old) => old.t != t;
}
