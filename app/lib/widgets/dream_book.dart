// 夢境日記本（2026-11-14 報告先用，11-15 首頁也改用）：還沒看過就抖一抖＋右上角紅點，
// 看過就靜止；系統開「減少動態效果」時不抖、紅點照樣在。看過沒看過由呼叫端給（DreamReadStore）。
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'dream_diary.dart';

/// 夢境入口：草地上一本攤開的日記（使用者生成）。讀不到圖時退回小雲。
/// 早晨報告與首頁共用（2026-11-15 使用者定：首頁不用雲朵了，跟報告一樣）。
const String kDreamBookAsset = 'assets/moods/dream_book.png';

class DreamBook extends StatefulWidget {
  final VoidCallback onTap;

  /// 還沒看過這一晚的夢 → 每隔一下抖一抖（2026-11-14 使用者定）。看過就靜止。
  final bool unread;
  const DreamBook({super.key, required this.onTap, required this.unread});

  @override
  State<DreamBook> createState() => _DreamBookState();
}

class _DreamBookState extends State<DreamBook>
    with SingleTickerProviderStateMixin {
  /// 抖一次多久、兩次之間停多久。停的時候不排畫面，測試的 pumpAndSettle 才停得下來。
  static const _shake = Duration(milliseconds: 700);
  static const _pause = Duration(milliseconds: 2600);

  late final AnimationController _c =
      AnimationController(vsync: this, duration: _shake)
        ..addStatusListener((st) {
          if (st == AnimationStatus.completed) _schedule();
        });
  Timer? _next;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant DreamBook old) {
    super.didUpdateWidget(old);
    _sync();
  }

  bool get _animate =>
      widget.unread &&
      !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);

  void _sync() {
    if (_animate) {
      if (_next == null && !_c.isAnimating) _schedule(first: true);
    } else {
      _next?.cancel();
      _next = null;
      _c.stop();
      _c.value = 0;
    }
  }

  void _schedule({bool first = false}) {
    _next?.cancel();
    _next = Timer(first ? const Duration(milliseconds: 600) : _pause, () {
      _next = null;
      if (mounted && _animate) _c.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _next?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open dream diary',
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            final t = _c.value;
            // 左右搖三下、越搖越小
            final angle = math.sin(t * math.pi * 6) * 0.14 * (1 - t);
            return Transform.rotate(
              key: const Key('dream-book-shake'),
              angle: angle,
              alignment: Alignment.bottomCenter,
              child: child,
            );
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Image.asset(
                kDreamBookAsset,
                key: const Key('dream-book'),
                width: 66,
                // 高度也要給：圖還沒讀進來時高度是 0，點不到（測試抓到的）
                height: 64,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    DreamBubble(compact: true, onTap: widget.onTap),
              ),
              // 沒看過 → 右上角一個紅點（2026-11-14 使用者定）。減少動態效果時不抖，紅點照樣在。
              if (widget.unread)
                Positioned(
                  key: const Key('dream-book-unread-dot'),
                  // 圖的上半是透明的，書落在下半——紅點貼在書的右上角
                  right: 6,
                  top: 16,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF4D5E),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: const [
                        BoxShadow(color: Color(0x66000000), blurRadius: 3),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
