import 'package:flutter/material.dart';

/// 底部導覽列（2026-11-13 使用者定，參考圖：只有圖示、中間一顆發光的月亮凸出來）。
///
/// - 左右各兩個分頁：Home、Friends ｜ ☾ ｜ Insights、Assistant。Settings 搬到首頁右上角。
/// - **中間那顆＝開始睡覺**（原本首頁那顆 Start Sleep），哪個分頁都按得到；畫睡著的狗頭表情。
/// - 沒有文字：選中的那個用紫色＋底下一個小點；每個圖示仍有朗讀用的名稱。
class MoonNavBar extends StatelessWidget {
  /// 目前在哪個分頁（0 Home、1 Friends、2 Insights、3 Assistant）
  final int currentIndex;
  final ValueChanged<int> onTab;
  final VoidCallback onMoon;

  const MoonNavBar({
    super.key,
    required this.currentIndex,
    required this.onTab,
    required this.onMoon,
  });

  /// 導覽列本體的高度（不含月亮凸出的那一塊、不含系統手勢列）。頁面內容排到這裡為止。
  static const double barHeight = 64;

  /// 中間那顆凸出導覽列上緣多少。頁面延伸到這一塊後面，凸出處兩側看到的是頁面本身。
  static const double moonRise = 22;

  static const accent = Color(0xFF7657FF);
  static const _bar = Color(0xFF1B2548);

  static const _tabs = [
    (Icons.home_rounded, 'Home', 'nav-home'),
    (Icons.groups_rounded, 'Friends', 'nav-friends'),
    (Icons.bar_chart_rounded, 'Insights', 'nav-insights'),
    (Icons.auto_awesome_rounded, 'Assistant', 'nav-assistant'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    Widget tab(int i) {
      final (icon, label, key) = _tabs[i];
      final on = currentIndex == i;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          child: InkResponse(
            key: Key(key),
            onTap: () => onTab(i),
            radius: 28,
            child: SizedBox(
              height: 64,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 26,
                    color: on ? const Color(0xFFB9A6FF) : Colors.white54,
                  ),
                  const SizedBox(height: 5),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: on ? 5 : 0,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: Color(0xFFB9A6FF),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: barHeight + bottom + moonRise,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // 導覽列本體（上方圓角），月亮那一格空著
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.only(bottom: bottom),
              decoration: const BoxDecoration(
                color: _bar,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
              ),
              child: Row(
                children: [
                  tab(0),
                  tab(1),
                  const SizedBox(width: 84),
                  tab(2),
                  tab(3),
                ],
              ),
            ),
          ),
          // 中間的月亮：凸出導覽列上緣，紫色漸層＋柔和光暈
          Positioned(
            top: 0,
            child: Semantics(
              button: true,
              label: 'Start sleep',
              child: GestureDetector(
                key: const Key('start-sleep'),
                onTap: onMoon,
                child: Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFB9A6FF), accent],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.6),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  // 睡著的狗頭表情（使用者 2026-11-13：「emoji 就好」）；缺圖退回月亮
                  padding: const EdgeInsets.all(9),
                  child: Image.asset(
                    'assets/moods/dog_tired.png',
                    key: const Key('start-sleep-dog'),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.nightlight_round,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
