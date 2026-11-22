// 換分頁：左右滑＋視差（2026-11-22 使用者選）。
//
// 照導覽列順序決定方向：往右邊的分頁，新頁從右邊滑進來、舊頁慢一點往左退（只走 [kTabParallax]），
// 像鏡頭在同一個世界裡移動。各頁背景不用改。
//
// 跟 IndexedStack 一樣：所有分頁一直留著（狀態不會掉），沒顯示的包在 Offstage 裡（不畫、點不到、
// 測試的 finder 預設也找不到）。系統開「減少動態效果」或 [animate] 為 false 時直接換、不滑。
import 'package:flutter/material.dart';

/// 舊頁退出時只走畫面寬的幾成（新頁走滿一整個寬）。
const double kTabParallax = 0.3;

/// 滑多久。
const Duration kTabSlide = Duration(milliseconds: 320);

/// 滑到一半時兩頁的位置（畫面寬的比例；正＝往右）。純函式，`tab_switcher_test.dart` 守著。
/// [t] 0～1（已套緩動），[forward]＝往右邊的分頁。回傳（舊頁, 新頁）。
(double, double) tabSlideOffsets(double t, {required bool forward}) {
  final dir = forward ? 1.0 : -1.0;
  return (-dir * kTabParallax * t, dir * (1 - t));
}

class TabSwitcher extends StatefulWidget {
  final int index;
  final List<Widget> children;

  /// false＝直接換（測試預設、Replay welcome 降落時要立刻停在首頁）。
  final bool animate;

  const TabSwitcher({super.key, required this.index, required this.children, this.animate = true});

  @override
  State<TabSwitcher> createState() => _TabSwitcherState();
}

class _TabSwitcherState extends State<TabSwitcher> with SingleTickerProviderStateMixin {
  late int _from = widget.index;
  late int _to = widget.index;
  AnimationController? _ctl;

  AnimationController get _slide => _ctl ??= AnimationController(vsync: this, duration: kTabSlide)
    ..addListener(() => setState(() {}))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() => _from = _to);
    });

  bool get _sliding => _ctl?.isAnimating ?? false;

  @override
  void didUpdateWidget(TabSwitcher old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _to = widget.index;
    if (!widget.animate || reduce) {
      _ctl?.stop();
      _from = _to;
      return;
    }
    // 滑到一半又換：從畫面上現在那一頁接著滑
    _from = old.index;
    _slide.forward(from: 0);
  }

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sliding = _sliding && _from != _to;
    final t = sliding ? Curves.easeOutCubic.transform(_slide.value) : 1.0;
    final (outX, inX) = tabSlideOffsets(t, forward: _to > _from);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      Widget slot(int i) {
        final shown = i == _to || (sliding && i == _from);
        final dx = !sliding ? 0.0 : (i == _to ? inX : (i == _from ? outX : 0.0));
        return KeyedSubtree(
          key: ValueKey('tab-$i'),
          child: Offstage(
            offstage: !shown,
            child: IgnorePointer(
              // 滑的時候兩頁都不能點（不然點到正在離開的那一頁）
              ignoring: sliding,
              child: Transform.translate(
                offset: Offset(dx * w, 0),
                child: widget.children[i],
              ),
            ),
          ),
        );
      }

      // 新頁畫在最上面（往左邊的分頁時，它的位置比舊頁前面，要另外排到最後）。
      // 每一頁都有固定的 key，換順序不會掉狀態。
      final order = [
        for (var i = 0; i < widget.children.length; i++)
          if (i != _to) i,
        _to,
      ];
      // 大小跟 IndexedStack 一樣撐滿；只有滑的時候裁邊（平常不裁，免得裁掉原本畫出界的東西）
      return SizedBox.expand(
        child: ClipRect(
          clipBehavior: sliding ? Clip.hardEdge : Clip.none,
          child: Stack(
            children: [for (final i in order) slot(i)],
          ),
        ),
      );
    });
  }
}
