// 送禮的「推門」（2026-11-22 使用者選：放大朋友的房子）。
//
// 點 Send something → 鏡頭在小鎮地圖上往朋友那棟房子推近、窗戶的燈越來越亮，
// 整個畫面被暖光蓋滿之後淡入客廳（送禮頁）。關掉時只淡出，不倒著播。
// 用現成的地圖，不用新圖。系統開「減少動態效果」時只淡入。
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 小鎮地圖（同 friends_town.dart 的 _mapImage）與原圖大小。
const String kTownDoorMap = 'assets/backgrounds/town_map.jpg';
const Size kTownDoorMapSize = Size(1086, 1448);

/// 地圖上的格子（`kTownLots`）是房子右邊那塊草地；房子本身在它左上方一點。
/// 推近時對準房子（窗戶的燈），不是對準草地。量自第二版地圖，換地圖要重量。
const Offset kTownDoorHouseShift = Offset(-95 / 1086, -25 / 1448);

/// 窗戶暖光的顏色（同地圖上路燈與窗戶的黃）。
const Color kTownDoorGlow = Color(0xFFFFD48A);

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
double _prog(double t, double a, double b) => _clamp01((t - a) / (b - a));
double _easeIn(double x) => x * x * x;
double _easeInOut(double x) =>
    x < .5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3).toDouble() / 2;

/// 推門某一刻的樣子（純函式，`town_door_test.dart` 守著）。t 是 0～1。
@immutable
class TownDoorFrame {
  /// 地圖那一層的不透明度（先淡入、最後淡出露出客廳）。
  final double map;

  /// 地圖放大幾倍。
  final double scale;

  /// 房子從原本的位置移到畫面中間，走了多少（0～1）。
  final double center;

  /// 窗戶暖光（0～1）。
  final double glow;

  const TownDoorFrame(this.map, this.scale, this.center, this.glow);

  /// 最大放大倍數。
  static const double maxScale = 5;

  factory TownDoorFrame.at(double t) {
    final fadeIn = _prog(t, 0, .12);
    // 暖光亮滿（.72）之後地圖才開始淡掉
    final fadeOut = 1 - _prog(t, .72, .95);
    final zoom = _easeIn(_prog(t, .05, .72));
    return TownDoorFrame(
      fadeIn * fadeOut,
      1 + (maxScale - 1) * zoom,
      _easeInOut(_prog(t, .05, .55)),
      _prog(t, .3, .72),
    );
  }
}

/// 送禮頁的推門轉場。[focus] 是朋友那塊草地在地圖上的位置（`kTownLots` 的比例）。
Route<T> townDoorRoute<T>({required WidgetBuilder builder, required Offset focus}) {
  return PageRouteBuilder<T>(
    opaque: false,
    barrierColor: const Color(0x66000000),
    barrierDismissible: true,
    barrierLabel: 'Close',
    transitionDuration: const Duration(milliseconds: 1100),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, _, _) => builder(context),
    transitionsBuilder: (context, animation, _, child) {
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      // 關掉、或減少動態效果：只淡入淡出
      if (reduce || animation.status == AnimationStatus.reverse) {
        return FadeTransition(opacity: animation, child: child);
      }
      return AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, page) {
          final t = animation.value;
          if (t >= 1) return page!;
          final f = TownDoorFrame.at(t);
          return Stack(
            children: [
              // 客廳在底下，地圖淡掉時露出來
              Opacity(opacity: _prog(t, .62, .9), child: page),
              if (f.map > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: f.map,
                      child: TownDoorZoom(focus: focus + kTownDoorHouseShift, frame: f),
                    ),
                  ),
                ),
            ],
          );
        },
      );
    },
  );
}

/// 地圖往房子推近＋窗戶暖光。
class TownDoorZoom extends StatelessWidget {
  final Offset focus;
  final TownDoorFrame frame;

  const TownDoorZoom({super.key, required this.focus, required this.frame});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = box.biggest;
      // 地圖用 cover 鋪滿畫面時，房子落在哪裡
      final s = math.max(size.width / kTownDoorMapSize.width, size.height / kTownDoorMapSize.height);
      final w = kTownDoorMapSize.width * s, h = kTownDoorMapSize.height * s;
      final ox = (size.width - w) / 2, oy = (size.height - h) / 2;
      final house = Offset(ox + focus.dx * w, oy + focus.dy * h);
      final mid = size.center(Offset.zero);
      // 房子一邊被放大、一邊移到畫面中間
      final anchor = Offset.lerp(house, mid, frame.center)!;
      final m = Matrix4.identity()
        ..translateByDouble(anchor.dx, anchor.dy, 0, 1)
        ..scaleByDouble(frame.scale, frame.scale, 1, 1)
        ..translateByDouble(-house.dx, -house.dy, 0, 1);
      final radius = size.shortestSide * (.15 + .9 * frame.glow);
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF081326)),
          Transform(
            transform: m,
            child: Image.asset(
              kTownDoorMap,
              key: const Key('town-door-map'),
              fit: BoxFit.cover,
              width: size.width,
              height: size.height,
              errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF101A3F)),
            ),
          ),
          // 窗戶的燈：從房子那裡亮起來，最後蓋滿畫面
          DecoratedBox(
            key: const Key('town-door-glow'),
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(
                  (anchor.dx / size.width) * 2 - 1,
                  (anchor.dy / size.height) * 2 - 1,
                ),
                radius: radius / size.shortestSide,
                colors: [
                  kTownDoorGlow.withValues(alpha: .95 * frame.glow),
                  kTownDoorGlow.withValues(alpha: .55 * frame.glow),
                  kTownDoorGlow.withValues(alpha: 0),
                ],
                stops: const [0, .55, 1],
              ),
            ),
          ),
        ],
      );
    });
  }
}
