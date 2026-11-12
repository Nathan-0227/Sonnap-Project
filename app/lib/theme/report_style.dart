import 'package:flutter/material.dart';

/// 早晨報告與起床自評的樣式（2026-11-13 依示意圖定案）。
///
/// 字用 Nunito（使用者定：圓一點、比較可愛），**只用在這兩個畫面**，
/// 其他畫面維持原樣。字型檔在 assets/fonts/nunito/（SIL OFL 1.1）。
const String kReportFont = 'Nunito';

class ReportColors {
  ReportColors._();

  static const bgTop = Color(0xFF0B1636);
  static const bgMid = Color(0xFF131D4A);
  static const bgBottom = Color(0xFF0E1638);

  /// 卡片底色：rgba(58,54,114,0.55)
  static const card = Color(0x8C3A3672);
  static const border = Color(0x24FFFFFF);

  static const muted = Color(0xFFB7BEDC);
  static const soft = Color(0xFFDCE0F5);
  static const faint = Color(0xFF9FA7CC);
  static const dim = Color(0xFF7F87AE);

  static const accent = Color(0xFFC9B8FF);
  static const purple = Color(0xFF8B6DFF);
  static const lilac = Color(0xFFB9A6FF);
  static const gold = Color(0xFFFFD772);
  static const hill = Color(0xFF1D2860);
  static const sheet = Color(0xFF1A1F4C);
  static const navy = Color(0xFF1B2152);

  /// 「跟上一晚比」：上升紅、下降綠。**只代表方向**（使用者定，台灣股市慣例）。
  static const up = Color(0xFFFF7B7B);
  static const down = Color(0xFF4FE0A0);
}

/// 卡片外框。
BoxDecoration reportCard({double radius = 22, bool dashed = false}) =>
    BoxDecoration(
      color: dashed ? const Color(0x403A3672) : ReportColors.card,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: dashed ? const Color(0x38FFFFFF) : ReportColors.border,
      ),
    );

/// 把整個子樹換成 Nunito。Theme（按鈕的字）與 DefaultTextStyle（一般 Text）都要換：
/// Scaffold 會把 DefaultTextStyle 重設成 theme 的 bodyMedium，所以兩個都得包。
class ReportFont extends StatelessWidget {
  final Widget child;
  const ReportFont({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: kReportFont),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: kReportFont),
        child: child,
      ),
    );
  }
}

/// 背景：深藍漸層＋幾顆小星星（示意圖的位置）。
class ReportBackground extends StatelessWidget {
  const ReportBackground({super.key});

  static const _stars = [
    (34.0, 92.0, 2.0, 0.7),
    (330.0, 120.0, 3.0, 0.8),
    (290.0, 200.0, 2.0, 0.5),
    (60.0, 250.0, 2.0, 0.6),
    (356.0, 300.0, 2.0, 0.5),
    (140.0, 74.0, 2.0, 0.5),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final scale = width / 390;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [ReportColors.bgTop, ReportColors.bgMid, ReportColors.bgBottom],
          stops: [0, 0.38, 1],
        ),
      ),
      child: Stack(
        children: [
          for (final (x, y, s, o) in _stars)
            Positioned(
              left: x * scale,
              top: y,
              child: Container(
                width: s,
                height: s,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: o),
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 215 → 3h 35m；45 → 45m；120 → 2h。
String reportHm(num minutes) {
  final m = minutes.round().abs();
  final h = m ~/ 60;
  final r = m % 60;
  if (h == 0) return '${r}m';
  if (r == 0) return '${h}h';
  return '${h}h ${r}m';
}

String reportClock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
