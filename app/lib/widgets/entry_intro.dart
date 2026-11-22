// 進場動畫（2026-11-22 使用者定，原型見 claude.ai 上的「Sonnap 進場動畫」）。
//
// 鏡頭從夜空往下降到首頁的山頂：
// - 短版（冷啟動）：寵物先睡在山頂，鏡頭停下才醒來、換成首頁那一份心情（B 案）。
//   醒之前畫睡姿，所以不會先露一張可能是錯的臉。
// - 長版（第一次登入流程、設定頁的 Replay welcome）：流程停在天空裡，按 Let's go 才降落；
//   寵物從完成頁那個位置飄下來，落地蹲一下、跳一下（第一次開還沒有任何一晚，所以醒著）。
//
// 規則：
// - 只在冷啟動播；從背景回到前景不播。
// - 點一下就跳過；系統開「減少動態效果」時只淡入。
// - 不等網路：帳號、最近一晚照原本的方式在背景讀。
// - 時間軸只在 [EntryFrame] 一份（純函式，`entry_intro_test.dart` 守著）。
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 天空最上面的顏色；往下漸層到首頁背景圖最上緣的 #010B2E（`kHomeBackgroundTop`）。
/// ⚠️ Android 啟動畫面的底色（`res/values*/` 的 `sonnap_sky`）要跟 [kEntrySkyBottom] 一樣，
///    從系統畫面接進來才不會閃一下別的顏色。
const Color kEntrySkyTop = Color(0xFF000419);

/// 漸層的下緣＝首頁背景圖最上緣（`home_screen.kHomeBackgroundTop`，實測整列 #010B2E）。
const Color kEntrySkyBottom = Color(0xFF010B2E);

/// 星星跟著鏡頭移動的比例（越小越遠）。
const double kEntryParallax = 0.45;

/// 淡入的介面有幾組：0 問候＋時鐘、1 寵物身邊的東西（等級、心情標籤、日記）、2 底下的卡片、3 導覽列。
const int kEntryUiGroups = 4;

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
double _prog(double t, double a, double b) => _clamp01((t - a) / (b - a));
double _easeInOut(double x) =>
    x < .5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3).toDouble() / 2;
double _easeOut(double x) => 1 - math.pow(1 - x, 3).toDouble();

/// 動畫某一刻的樣子。全部由 (時間, 長版或短版) 算出來，沒有狀態。
@immutable
class EntryFrame {
  /// 鏡頭：0＝還在天空、1＝停在首頁原本的位置（已經套過緩動）。
  final double camera;

  /// 進場那一層星星的不透明度（首頁自己有星星，鏡頭快到時淡掉）。
  final double stars;

  /// 0＝睡姿、1＝醒來（只有短版會小於 1）。
  final double awake;

  /// 寵物往上跳多高（邏輯像素）。
  final double hop;

  /// 落地壓扁：寬、高的縮放。
  final double squashX, squashY;

  /// 每一組介面的進度（0 看不到、1 原位），長度 [kEntryUiGroups]。
  final List<double> ui;

  /// 播完了。
  final bool done;

  /// 第幾秒、介面從第幾秒開始進場（[item] 用）。
  final double t, uiStart;

  /// 一個介面元件的進度：鏡頭快停時開始，[delay] 秒後才輪到它（首頁一張張卡片錯開進場）。
  double item(double delay) =>
      done ? 1 : _easeOut(_prog(t, uiStart + delay, uiStart + delay + kEntryItemSeconds));

  const EntryFrame({
    required this.camera,
    required this.stars,
    required this.awake,
    required this.hop,
    required this.squashX,
    required this.squashY,
    required this.ui,
    required this.done,
    this.t = 0,
    this.uiStart = 0,
  });

  /// 停在首頁原本的樣子（沒有在播、或播完）。
  static const EntryFrame rest = EntryFrame(
    camera: 1, stars: 0, awake: 1, hop: 0, squashX: 1, squashY: 1,
    ui: [1, 1, 1, 1], done: true,
  );

  /// 短版多長（秒）。
  static const double shortSeconds = 1.95;

  /// 長版（按 Let's go 之後）多長（秒）。
  static const double longSeconds = 2.0;

  static double totalSeconds({required bool long}) => long ? longSeconds : shortSeconds;

  /// 鏡頭停下的那一刻（秒）。
  static double landAt({required bool long}) => long ? 1.3 : 1.2;

  factory EntryFrame.at(double t, {required bool long}) {
    final total = totalSeconds(long: long);
    if (t >= total) return rest;
    final land = landAt(long: long);
    final camStart = long ? 0.0 : 0.3;
    final camera = _easeInOut(_prog(t, camStart, land));

    // 星星：短版先亮起來；兩版都在鏡頭快到時淡掉（首頁有自己的）
    final starsIn = long ? 1.0 : _easeOut(_prog(t, 0, .6));
    final stars = starsIn * (1 - _prog(camera, .6, 1));

    // 寵物
    double awake = 1, hop = 0, sx = 1, sy = 1;
    final since = t - land;
    if (!long) {
      awake = _prog(since, .1, .35);
      if (since > .15) {
        final h = _prog(since, .15, .6);
        hop = math.sin(h * math.pi) * 22;
        if (h < .15) {
          final k = math.sin(h / .15 * math.pi);
          sy = 1 - .06 * k;
          sx = 1 + .03 * k;
        }
      }
    } else if (since >= 0) {
      final h = _prog(since, 0, .4);
      if (h < .2) {
        final k = math.sin(h / .2 * math.pi);
        sy = 1 - .08 * k;
        sx = 1 + .04 * k;
      } else {
        hop = math.sin((h - .2) / .8 * math.pi) * 20;
      }
    }

    // 介面：鏡頭快停時依序進來（導覽列跟寵物身邊那組差不多同時）
    final uiStart = land + .05;
    const delays = [0.0, .16, .1, .12];
    final ui = [for (final d in delays) _easeOut(_prog(t, uiStart + d, uiStart + d + kEntryItemSeconds))];

    return EntryFrame(
      camera: camera,
      stars: stars,
      awake: awake,
      hop: hop,
      squashX: sx,
      squashY: sy,
      ui: ui,
      done: false,
      t: t,
      uiStart: uiStart,
    );
  }
}

/// 一個介面元件從看不到到原位要多久（秒）。
const double kEntryItemSeconds = .35;

/// 首頁底下第 [index] 張卡片的延遲：一張晚 0.05 秒，最晚 0.3 秒（不然播完時還有卡片沒到位、最後一下跳到原位）。
double entryCardDelay(int index) => math.min(.14 + .05 * index, .3);

/// 要求播一次。首頁聽它；導覽列聽 [ui]。
class EntryIntro extends ChangeNotifier {
  int _serial = 0;
  bool _long = false;
  Rect? _petFrom;

  /// 第幾次要求（首頁用來分辨是不是新的一次）。
  int get serial => _serial;
  bool get long => _long;

  /// 長版：寵物從哪裡飄下來（完成頁那隻寵物在螢幕上的位置）；null＝從首頁的位置上方開始。
  Rect? get petFrom => _petFrom;

  /// 導覽列那一組的進度（沒在播時是 1）。
  final ValueNotifier<double> ui = ValueNotifier<double>(1);

  /// 還沒開始播、正在播都算（首頁讀資料時先畫天空用）。
  bool get pending => _pending;
  bool _pending = false;

  void play({bool long = false, Rect? petFrom}) {
    _serial++;
    _long = long;
    _petFrom = petFrom;
    _pending = true;
    ui.value = 0;
    notifyListeners();
  }

  /// 首頁播完（或跳過）時呼叫。
  void finish() {
    _pending = false;
    ui.value = 1;
  }

  @override
  void dispose() {
    ui.dispose();
    super.dispose();
  }
}

/// 一片天空：漸層＋程式畫的星星。第一次登入流程的背景、開 App 還在認帳號那一下、
/// 首頁進場時上面那段，都是這一片——所以從一個畫面換到下一個看不出接縫。
class EntrySky extends StatelessWidget {
  /// 星星往上移了多少（邏輯像素；鏡頭往下時由首頁給）。
  final double starShift;

  /// 星星的不透明度。
  final double starOpacity;

  /// 要不要畫漸層（首頁進場時漸層另外畫在世界裡，這裡只畫星星）。
  final bool gradient;

  const EntrySky({super.key, this.starShift = 0, this.starOpacity = 1, this.gradient = true});

  @override
  Widget build(BuildContext context) {
    final stars = IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: EntryStarsPainter(shift: starShift, opacity: starOpacity),
      ),
    );
    if (!gradient) return stars;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kEntrySkyTop, kEntrySkyBottom],
        ),
      ),
      child: stars,
    );
  }
}

/// 固定種子的星星：每次畫都在同一個位置，換畫面時才對得上。
class EntryStarsPainter extends CustomPainter {
  final double shift;
  final double opacity;

  EntryStarsPainter({required this.shift, required this.opacity});

  /// （x, y, 半徑, 亮度, 亮起來的先後）。先後讓星星一顆一顆亮，不是整片一起出現。
  static final List<(double, double, double, double, double)> _stars = () {
    final r = math.Random(7);
    return [
      for (var i = 0; i < 70; i++)
        (r.nextDouble(), r.nextDouble() * 1.4, r.nextDouble() * 1.2 + .5, .35 + r.nextDouble() * .65,
            r.nextDouble() * .4),
    ];
  }();

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final paint = Paint()..color = Colors.white;
    for (final (x, y, radius, alpha, delay) in _stars) {
      final dy = y * size.height + shift;
      if (dy < -4 || dy > size.height + 4) continue;
      final a = _clamp01(opacity * 1.4 - delay);
      if (a <= 0) continue;
      paint.color = Colors.white.withValues(alpha: alpha * a);
      canvas.drawCircle(Offset(x * size.width, dy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(EntryStarsPainter old) => old.shift != shift || old.opacity != opacity;
}

/// 第一次登入流程的開場（只有歡迎頁、只播一次）：星星一顆顆亮起來 → 寵物浮上來 → 標題、說明、按鈕依序進來。
/// 跟 [EntryFrame] 一樣是純函式。
@immutable
class WelcomeOpening {
  final double stars, topBar, pet, title, subtitle, body, button;

  const WelcomeOpening._(this.stars, this.topBar, this.pet, this.title, this.subtitle, this.body, this.button);

  static const WelcomeOpening rest = WelcomeOpening._(1, 1, 1, 1, 1, 1, 1);

  /// 多長（秒）。
  static const double seconds = 1.6;

  factory WelcomeOpening.at(double t) {
    if (t >= seconds) return rest;
    double p(double a, double b) => _easeOut(_prog(t, a, b));
    return WelcomeOpening._(
      _prog(t, 0, .9),
      p(.5, .9),
      p(.6, 1.1),
      p(.8, 1.2),
      p(.9, 1.3),
      p(1.0, 1.4),
      p(1.2, 1.6),
    );
  }
}
