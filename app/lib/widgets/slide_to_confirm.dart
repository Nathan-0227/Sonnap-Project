import 'package:flutter/material.dart';

/// 滑動確認（2026-11-12 使用者要求：Out of bed 用滑的結束）。
///
/// 把手拖過 [threshold] 才算數，放手不到就彈回去。**點一下不會觸發**——
/// 半夜手機在枕頭邊被碰到，不該就這樣記成下床（下床是攝影機的標準答案）。
/// 讀螢幕的使用者拖不動，所以語意上仍是一顆按鈕，點兩下就觸發。
class SlideToConfirm extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onConfirmed;
  final double height;

  /// 拖到軌道的幾成才算數。
  final double threshold;

  const SlideToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.icon = Icons.wb_sunny_rounded,
    this.height = 60,
    this.threshold = 0.85,
  });

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm>
    with SingleTickerProviderStateMixin {
  // ⚠️ 不能用 `late final ... = AnimationController(...)` 的寫法：從沒拖過的話，
  //    第一次碰到它是在 dispose()，那時才建 ticker 會丟例外，連帶外層畫面收不乾淨。
  late final AnimationController _back;

  @override
  void initState() {
    super.initState();
    _back = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() => setState(() => _dx = _from * (1 - _back.value)));
  }

  double _dx = 0;
  double _from = 0;
  bool _done = false;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const pad = 4.0;
    final knob = widget.height - pad * 2;
    return Semantics(
      button: true,
      label: widget.label,
      onTap: widget.onConfirmed,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, box) {
          final maxDx = box.maxWidth - 4 - knob - 4;
          final t = maxDx <= 0 ? 0.0 : (_dx / maxDx).clamp(0.0, 1.0);
          return Container(
            height: widget.height,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06 + 0.10 * t),
              borderRadius: BorderRadius.circular(widget.height / 2),
              border: Border.all(color: const Color(0xFFB9A6FF), width: 2),
            ),
            child: Stack(
              children: [
                Center(
                  child: Opacity(
                    opacity: (1 - t * 1.6).clamp(0.0, 1.0),
                    child: Padding(
                      padding: EdgeInsets.only(left: knob * 0.6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.keyboard_double_arrow_right_rounded,
                            color: Colors.white54,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  // 外框 2 像素會把內容往內縮，所以這裡左右上下各留 2。
                  left: 2 + _dx,
                  top: 2,
                  child: GestureDetector(
                    key: const Key('slide-knob'),
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (_) => _back.stop(),
                    onHorizontalDragUpdate: (d) {
                      if (_done) return;
                      setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, maxDx));
                    },
                    onHorizontalDragEnd: (_) {
                      if (_done) return;
                      if (maxDx > 0 && _dx / maxDx >= widget.threshold) {
                        setState(() {
                          _done = true;
                          _dx = maxDx;
                        });
                        widget.onConfirmed();
                      } else {
                        _from = _dx;
                        _back.forward(from: 0);
                      }
                    },
                    child: Container(
                      width: knob,
                      height: knob,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Color(0x99FF7AD9), blurRadius: 10),
                        ],
                      ),
                      child: Icon(widget.icon, color: const Color(0xFFFF7AD9)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
