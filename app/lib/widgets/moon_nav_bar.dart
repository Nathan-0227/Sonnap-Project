import 'dart:async';

import 'package:flutter/material.dart';

import '../services/bedtime_guard.dart' show guardWindow;
import '../theme/app_accent.dart';

/// 底部導覽列（2026-11-13 使用者定，參考圖：只有圖示、中間一顆發光的月亮凸出來）。
///
/// - 左右各兩個分頁：Home、Friends ｜ ☾ ｜ Insights、Assistant。Settings 搬到首頁右上角。
/// - **中間那顆＝開始睡覺**（原本首頁那顆 Start Sleep），哪個分頁都按得到。
///   2026-11-22 使用者定：圓鈕裡畫**月亮＋「Sleep」**（原本是睡著的寵物頭，看不出是開始睡覺）；
///   **目標就寢前 30 分到目標後 6 小時**（＝守門那一窗，`guardWindow`）光暈呼吸提醒，
///   系統開「減少動態效果」時不動、只變亮。
/// - 四個分頁沒有文字：選中的那個用紫色＋底下一個小點；每個圖示仍有朗讀用的名稱。
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
    this.bedtime,
    this.clock = DateTime.now,
  });

  /// 目標就寢時間；null＝不知道，就不提醒。
  final TimeOfDay? bedtime;

  /// 現在幾點（測試注入）。
  final DateTime Function() clock;

  /// 中間那顆要不要發亮提醒：跟守門同一窗（目標前 30 分 → 目標後 6 小時）。
  static bool bedtimeNear(DateTime now, TimeOfDay? bedtime) =>
      bedtime != null && guardWindow(now, bedtime).contains(now);

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
                    color: on ? accentSoftOf(context) : Colors.white54,
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
          // 中間的「開始睡覺」：凸出導覽列上緣，月亮＋Sleep，快到就寢時光暈呼吸
          Positioned(
            top: 0,
            child: _SleepButton(
              onTap: onMoon,
              bedtime: bedtime,
              clock: clock,
            ),
          ),
        ],
      ),
    );
  }
}

class _SleepButton extends StatefulWidget {
  final VoidCallback onTap;
  final TimeOfDay? bedtime;
  final DateTime Function() clock;
  const _SleepButton({required this.onTap, required this.bedtime, required this.clock});

  @override
  State<_SleepButton> createState() => _SleepButtonState();
}

class _SleepButtonState extends State<_SleepButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  Timer? _tick;
  bool _near = false;

  @override
  void initState() {
    super.initState();
    // 這裡還不能 setState、也不能讀 MediaQuery；脈動在 didChangeDependencies 才排
    _near = MoonNavBar.bedtimeNear(widget.clock(), widget.bedtime);
    // 時間會自己走過那一窗的起點／終點：每 30 秒看一次
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  @override
  void didUpdateWidget(covariant _SleepButton old) {
    super.didUpdateWidget(old);
    _check(); // 目標改了、或上層重畫（時間可能走過那一窗的邊界）
  }

  void _check() {
    if (!mounted) return;
    final near = MoonNavBar.bedtimeNear(widget.clock(), widget.bedtime);
    if (near != _near) setState(() => _near = near);
    _syncPulse();
  }

  void _syncPulse() {
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_near && !still) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = _near ? 1 : 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse(); // 減少動態效果開關改了
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = accentOf(context);
    final soft = accentSoftOf(context);
    return Semantics(
      button: true,
      label: 'Start sleep',
      child: GestureDetector(
        key: const Key('start-sleep'),
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (_, child) {
            final t = Curves.easeInOut.transform(_pulse.value);
            return Container(
              key: Key(_near ? 'start-sleep-near' : 'start-sleep-calm'),
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [soft, accent],
                ),
                border: _near
                    ? Border.all(color: Colors.white.withValues(alpha: 0.35 + 0.45 * t), width: 2)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.6 + 0.35 * t),
                    blurRadius: 24 + 18 * t,
                    spreadRadius: 2 + 7 * t,
                  ),
                ],
              ),
              child: child,
            );
          },
          child: const ExcludeSemantics(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.nightlight_round,
                  key: Key('start-sleep-moon'),
                  color: Colors.white,
                  size: 26,
                ),
                SizedBox(height: 1),
                Text(
                  'Sleep',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
