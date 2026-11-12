import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/report_style.dart';
import '../widgets/home_pet.dart';
import '../widgets/sleepy_pet.dart';

/// 起床動畫（2026-11-13 使用者定）：滑完 Slide to get up → **這段** → 起床自評卡 → 報告。
///
/// 三拍、共 [kWakeUpDuration]：
///   ① 夜空轉成清晨、太陽從山後升起，小狗還在睡
///   ② 換成醒著的小狗，伸個懶腰（先壓扁再拉長）
///   ③ 輕輕跳一下，出現「Good morning」，然後自己關掉
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 這段只說「早安、起床了」，不說「你做得很好」
/// ═══════════════════════════════════════════════════════════════════
///
/// - 不放彩帶、金幣、XP、分數、「Great job」：起床那一刻分數幾乎都還沒到，
///   這時候慶祝等於每晚不管好壞都誇（紅線 5）；而且它排在起床自評**之前**，
///   先慶祝再問「你覺得休息夠不夠」，答案會被帶著走。
/// - 醒來的小狗用**首頁那一份心情**（後端的 pet_mood，照抄），不自己挑 happy；
///   讀不到就是 bored（[HomePet] 的規則：不認得的一律 bored）。
/// - 點一下就跳過；系統開「減少動態效果」時**整段不播**（由首頁決定不推這個畫面）。
const Duration kWakeUpDuration = Duration(milliseconds: 2200);

/// 這晚要不要播起床動畫。系統開了「減少動態效果」就不播。
bool shouldPlayWakeUp(BuildContext context) =>
    !MediaQuery.of(context).disableAnimations;

class WakeUpScreen extends StatefulWidget {
  /// 首頁那一份心情（後端的 pet_mood）。null → bored。
  final String? mood;

  /// 按 Out of bed 的時刻，顯示在「Good morning」底下。null 就不顯示時間。
  final DateTime? wakeAt;

  const WakeUpScreen({super.key, this.mood, this.wakeAt});

  @override
  State<WakeUpScreen> createState() => _WakeUpScreenState();
}

/// 用淡入淡出推這個畫面（從下往上滑的話，醒來的感覺會被轉場打斷）。
Route<void> wakeUpRoute({String? mood, DateTime? wakeAt}) => PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => WakeUpScreen(mood: mood, wakeAt: wakeAt),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );

/// 使用者做的起床 GIF（2026-11-13 使用者定：改用 GIF）。
/// **有這個檔就播它、沒有就退回下面程式畫的那一版**——缺檔不會報錯。
/// 畫面會鋪滿（BoxFit.cover），所以 GIF 要是一整個場景、小狗放中間。
const String kWakeUpGif = 'assets/pets/dog01/wake_up.gif';

/// GIF 播一次要多久就播多久，但夾在這個範圍裡：太短看不到，太長會擋路。
const Duration kWakeUpMin = Duration(seconds: 1);
const Duration kWakeUpMax = Duration(seconds: 6);

/// 有些 GIF 每格寫 0 毫秒，瀏覽器一律當成 100 毫秒播；這裡照同一個慣例。
Duration gifFrameDuration(Duration d) =>
    d < const Duration(milliseconds: 20) ? const Duration(milliseconds: 100) : d;

Duration clampWakeUpDuration(Duration d) =>
    d < kWakeUpMin ? kWakeUpMin : (d > kWakeUpMax ? kWakeUpMax : d);

/// 讀 GIF 的總長度。讀不到（沒有檔、壞檔）回 null。
Future<Duration?> wakeUpGifDuration() async {
  try {
    final data = await rootBundle.load(kWakeUpGif);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    var total = Duration.zero;
    for (var i = 0; i < codec.frameCount; i++) {
      final frame = await codec.getNextFrame();
      total += gifFrameDuration(frame.duration);
      frame.image.dispose();
    }
    codec.dispose();
    return clampWakeUpDuration(total);
  } catch (_) {
    return null;
  }
}

class _WakeUpScreenState extends State<WakeUpScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t =
      AnimationController(vsync: this, duration: kWakeUpDuration)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _finish();
        });

  bool _done = false;

  /// 還在查有沒有 GIF（不到一瞬間）。查完才開始播，免得先閃一下程式版。
  bool _ready = false;
  bool _gif = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final gif = await wakeUpGifDuration();
    if (!mounted) return;
    setState(() {
      _ready = true;
      _gif = gif != null;
    });
    _t.duration = gif ?? kWakeUpDuration;
    _t.forward();
  }

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  /// t 在 [a, b] 之間的進度（0–1，前後夾住），套上曲線。
  static double _seg(double t, double a, double b,
      [Curve curve = Curves.easeInOut]) {
    if (t <= a) return 0;
    if (t >= b) return 1;
    return curve.transform((t - a) / (b - a));
  }

  @override
  Widget build(BuildContext context) {
    return ReportFont(
      child: Scaffold(
        backgroundColor: ReportColors.bgTop,
        body: GestureDetector(
          key: const Key('wake-up-skip'),
          behavior: HitTestBehavior.opaque,
          onTap: _finish,
          child: !_ready
              ? const SizedBox.expand()
              : _gif
                  ? _gifScene(context)
                  : AnimatedBuilder(
                      animation: _t,
                      builder: (context, _) => _scene(context, _t.value),
                    ),
        ),
      ),
    );
  }

  Widget _gifScene(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          kWakeUpGif,
          key: const Key('wake-up-gif'),
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 24 + MediaQuery.paddingOf(context).bottom,
          child: const Text(
            'Tap to skip',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
            ),
          ),
        ),
      ],
    );
  }

  Widget _scene(BuildContext context, double t) {
    final size = MediaQuery.sizeOf(context);
    final dawn = _seg(t, 0.0, 0.55);
    final sunUp = _seg(t, 0.08, 0.6, Curves.easeOutCubic);
    final swap = _seg(t, 0.32, 0.42);
    final hello = _seg(t, 0.62, 0.8);
    final petSize = math.min(size.width * 0.62, 260.0);
    final groundTop = size.height * 0.62;

    Color mix(Color night, Color day) => Color.lerp(night, day, dawn)!;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 天空：夜 → 清晨
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                mix(ReportColors.bgTop, const Color(0xFF3B3F8F)),
                mix(ReportColors.bgMid, const Color(0xFF9C7FE0)),
                mix(ReportColors.bgBottom, const Color(0xFFFFB38A)),
              ],
              stops: const [0, 0.5, 1],
            ),
          ),
        ),
        // 星星淡出
        Opacity(
          opacity: 1 - _seg(t, 0.1, 0.5),
          child: CustomPaint(painter: _StarsPainter()),
        ),
        // 太陽：從右邊的山後升起。⚠️ 不放正中間——會正好在小狗身後，
        //    看起來像頭上掛一圈光而不是日出（實機看過）。
        Positioned(
          left: size.width * 0.78 - 90,
          top: groundTop + 30 - 150 * sunUp,
          child: Opacity(
            opacity: sunUp,
            child: Container(
              key: const Key('wake-up-sun'),
              width: 180,
              height: 180,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0xFFFFF1B8), Color(0xFFFFC46B), Color(0x00FFC46B)],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
        ),
        // 山丘
        Positioned(
          left: 0,
          right: 0,
          top: groundTop,
          bottom: 0,
          child: CustomPaint(painter: _GroundPainter(dawn: dawn)),
        ),
        // 小狗：睡著 → 醒來伸懶腰
        Positioned(
          left: 0,
          right: 0,
          // 腳要踩在山稜線上（實機量過：稜線在中間大約低 18 點）
          top: groundTop + 18 - petSize * 0.86,
          child: Center(
            child: SizedBox(
              width: petSize,
              height: petSize,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  if (swap < 1)
                    Opacity(
                      opacity: 1 - swap,
                      child: SleepingPet(
                        key: const Key('wake-up-asleep'),
                        size: petSize,
                      ),
                    ),
                  if (swap > 0)
                    Opacity(
                      opacity: swap,
                      child: _stretch(
                        t,
                        HomePet(
                          key: const Key('wake-up-awake'),
                          mood: widget.mood,
                          size: petSize * 0.9,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        // Good morning
        Positioned(
          left: 0,
          right: 0,
          top: size.height * 0.14,
          child: Opacity(
            opacity: hello,
            child: Transform.translate(
              offset: Offset(0, 12 * (1 - hello)),
              child: Column(
                children: [
                  const Text(
                    'Good morning',
                    key: Key('wake-up-hello'),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (widget.wakeAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      reportClock(widget.wakeAt!),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 24 + MediaQuery.paddingOf(context).bottom,
          child: Opacity(
            opacity: 0.6,
            child: const Text(
              'Tap to skip',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  /// 伸懶腰：先壓扁（蓄力）→ 拉長 → 跳一下落地。以腳底為支點。
  Widget _stretch(double t, Widget child) {
    final squash = _seg(t, 0.42, 0.52);
    final stretch = _seg(t, 0.52, 0.66);
    final settle = _seg(t, 0.66, 0.82);
    final hop = math.sin(math.pi * _seg(t, 0.68, 0.84, Curves.linear));
    // 1 → (1.08, 0.88) → (0.94, 1.1) → 1
    final sx = 1 + 0.08 * squash - 0.14 * stretch + 0.06 * settle;
    final sy = 1 - 0.12 * squash + 0.22 * stretch - 0.10 * settle;
    return Transform.translate(
      offset: Offset(0, -18 * hop),
      child: Transform.scale(
        scaleX: sx,
        scaleY: sy,
        alignment: Alignment.bottomCenter,
        child: child,
      ),
    );
  }
}

class _StarsPainter extends CustomPainter {
  static const _stars = [
    (0.09, 0.08, 2.0), (0.85, 0.11, 3.0), (0.74, 0.22, 2.0), (0.15, 0.27, 2.0),
    (0.92, 0.33, 2.0), (0.36, 0.07, 2.0), (0.55, 0.17, 2.5), (0.27, 0.40, 2.0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.8);
    for (final (x, y, r) in _stars) {
      canvas.drawCircle(Offset(x * size.width, y * size.height), r / 2, paint);
    }
  }

  @override
  bool shouldRepaint(_StarsPainter old) => false;
}

/// 山丘：夜裡是深藍，天亮後轉成暗紫。
class _GroundPainter extends CustomPainter {
  final double dawn;
  const _GroundPainter({required this.dawn});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final path = Path()
      ..moveTo(0, 50)
      ..cubicTo(w * 0.25, 10, w * 0.55, 30, w * 0.7, 28)
      ..cubicTo(w * 0.85, 26, w * 0.95, 18, w, 22)
      ..lineTo(w, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = Color.lerp(ReportColors.hill, const Color(0xFF4A3F8C), dawn)!,
    );
  }

  @override
  bool shouldRepaint(_GroundPainter old) => old.dawn != dawn;
}
