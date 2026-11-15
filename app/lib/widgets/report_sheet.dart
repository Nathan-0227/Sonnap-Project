import 'package:flutter/material.dart';

// 早晨報告點格子開的詳細頁（Steps、Calories、Active time、Movement、心率、效率…）共用的開法。
// 2026-11-15 使用者實機發現：內容一長，頁面撐滿整個螢幕、標題頂到狀態列（沒有空隙），
// 而且頁裡的捲動吃掉了往下拉的手勢，拉不下來關掉。所以：
// - 最高 [kReportSheetMaxHeight] 的螢幕、避開狀態列，上面永遠看得到一截報告
// - 頂端一條拉桿（只是提示，拉桿那一截本來就能拖）
// - 捲到最上面之後繼續往下拉 → 關掉（[PullDownToClose]）
const double kReportSheetMaxHeight = 0.88;

/// 往下拉超過這麼多就關（邏輯像素）。
const double kPullDownCloseDistance = 56;

Future<T?> showReportSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * kReportSheetMaxHeight,
    ),
    builder: (context) => PullDownToClose(
      child: Stack(
        children: [
          builder(context),
          const Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: SizedBox(
                  key: Key('report-sheet-handle'),
                  width: 40,
                  height: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0x66FFFFFF),
                      borderRadius: BorderRadius.all(Radius.circular(2)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// 頁裡的捲動已經在最上面、手指還繼續往下拉 → 關掉這一頁。
/// Android（夾住不回彈）收到的是 overscroll；iOS（會回彈）是捲到負的位置，兩種都接。
class PullDownToClose extends StatefulWidget {
  final Widget child;
  const PullDownToClose({super.key, required this.child});

  @override
  State<PullDownToClose> createState() => _PullDownToCloseState();
}

class _PullDownToCloseState extends State<PullDownToClose> {
  double _pulled = 0;
  bool _closed = false;

  void _close() {
    if (_closed) return;
    _closed = true;
    Navigator.of(context).maybePop();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is OverscrollNotification &&
        n.dragDetails != null &&
        n.overscroll < 0) {
      _pulled += -n.overscroll;
      if (_pulled >= kPullDownCloseDistance) _close();
    } else if (n is ScrollUpdateNotification &&
        n.dragDetails != null &&
        n.metrics.pixels <= -kPullDownCloseDistance) {
      _close();
    } else if (n is ScrollEndNotification ||
        (n is ScrollUpdateNotification && n.metrics.pixels > 0)) {
      _pulled = 0;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: widget.child,
      );
}
