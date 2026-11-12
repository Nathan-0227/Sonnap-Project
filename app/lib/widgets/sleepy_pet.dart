import 'package:flutter/material.dart';
import 'home_pet.dart';

/// 晚上版與睡覺畫面的寵物：睡在一彎月亮上。
///
/// ⚠️ **這不是心情。** 晚上要傳達的是「該睡了」，不是昨晚的成績，所以
/// 固定畫想睡的樣子，而且**不顯示任何心情標籤**（2026-11-12 使用者定案）。
/// 2D 小狗還沒有睡覺的姿勢，暫用 bored 那組、動畫放慢成呼吸的節奏；
/// 隊友畫好睡姿後在 [HomePet] 換上即可。
/// 心情一律照抄後端的規則只管白天版——這裡不碰 `pet_mood`，也就不會跟它衝突。
///
/// 月亮墊子是程式畫的：設計圖參考了別的 App 的版面，但墊子的造型要是我們自己的。
class SleepyPet extends StatelessWidget {
  final double size;

  const SleepyPet({super.key, this.size = 200});

  Widget get _pet => HomePet(mood: 'bored', size: size * 0.72, speed: 0.55);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('sleepy-pet'),
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(child: CustomPaint(painter: _MoonPainter())),
          Positioned(bottom: size * 0.16, child: _pet),
        ],
      ),
    );
  }
}

/// 一彎發光的月亮，開口朝右上，寵物趴在下半部的弧上。
class _MoonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width * 0.46;
    final c = Offset(size.width * 0.5, size.height * 0.52);
    final outer = Path()..addOval(Rect.fromCircle(center: c, radius: r));
    final bite = Path()
      ..addOval(Rect.fromCircle(
          center: c.translate(r * 0.42, -r * 0.42), radius: r * 0.86));
    final moon = Path.combine(PathOperation.difference, outer, bite);

    canvas.drawPath(
      moon,
      Paint()
        ..color = const Color(0x55FFD96A)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawPath(
      moon,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE59A), Color(0xFFFFC567)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 睡覺畫面的寵物（2026-11-12）。有使用者做的睡姿圖就用它（慢慢呼吸、旁邊飄 Zz），
/// 圖還沒放進來就退回上面那隻趴在月亮上的 [SleepyPet]。
///
/// 圖放在 [kSleepingPetAsset]：去背 PNG，寵物連同墊子畫在一起。
const String kSleepingPetAsset = 'assets/pets/dog01/sleeping.png';

class SleepingPet extends StatefulWidget {
  final double size;
  const SleepingPet({super.key, this.size = 240});

  @override
  State<SleepingPet> createState() => _SleepingPetState();
}

class _SleepingPetState extends State<SleepingPet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 系統開「減少動態效果」時靜止，跟首頁的星星一樣。
    if (MediaQuery.of(context).disableAnimations) {
      _breath.stop();
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      key: const Key('sleeping-pet'),
      width: s,
      height: s,
      child: Image.asset(
        kSleepingPetAsset,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => SleepyPet(size: s),
        frameBuilder: (context, child, frame, sync) {
          if (frame == null && !sync) return child;
          return AnimatedBuilder(
            animation: _breath,
            builder: (context, _) {
              final t = Curves.easeInOut.transform(_breath.value);
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Transform.scale(
                      alignment: Alignment.bottomCenter,
                      scaleY: 1 + 0.025 * t,
                      scaleX: 1 + 0.01 * t,
                      child: child,
                    ),
                  ),
                  Positioned(
                    right: s * 0.12,
                    top: s * (0.14 - 0.06 * t),
                    child: Opacity(
                      opacity: 0.35 + 0.5 * t,
                      child: Text(
                        'z Z',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: s * 0.09,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
