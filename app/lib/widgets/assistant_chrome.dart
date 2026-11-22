import 'package:flutter/material.dart';

import '../models/wall_clock.dart';
import '../services/pet_choice.dart';
import 'home_pet.dart';
import 'night_sky_effects.dart';

/// 助理頁的聊天室外觀（2026-11-22 使用者 grill 定，設計稿 D）：
/// 會動的背景、寵物頭像、狀態列、打招呼那一則、日期膠囊。
///
/// ⚠️ 這裡全部只是「呈現」：心情照抄後端、打招呼的數字照抄 `/home`，Dart 不判斷好壞。

// ═══════════════════════════════════════════════════════════════════
// 背景：深藍漸層 → 往上飄的塗鴉 → 會閃的星星與流星
// ═══════════════════════════════════════════════════════════════════

/// 塗鴉往上飄一圈要多久（一圈＝一個圖塊的高度，所以頭尾接得上）。
const Duration kDoodleDriftPeriod = Duration(seconds: 40);

/// 流星多久一次（首頁 7 秒；這頁是聊天，要更少）。
const Duration kChatShootingStarPeriod = Duration(seconds: 28);

/// 塗鴉圖塊（`assets/backgrounds/chat_doodle.png`，320 px，畫成 160 邏輯像素）。
const String kChatDoodle = 'assets/backgrounds/chat_doodle.png';
const double kDoodleTile = 160;

/// 背景。[thinking]＝寵物在想答案：星星閃快一點、亮一點。
///
/// ⚠️ 系統開「減少動態效果」時全部靜止；不在畫面上的分頁由外層的 TickerMode 停掉
///    （App 的分頁疊在 IndexedStack 裡，看不到的頁也還在，不停會在背後一直跑）。
class ChatBackdrop extends StatefulWidget {
  final bool thinking;
  const ChatBackdrop({super.key, this.thinking = false});

  @override
  State<ChatBackdrop> createState() => _ChatBackdropState();
}

class _ChatBackdropState extends State<ChatBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _drift =
      AnimationController(vsync: this, duration: kDoodleDriftPeriod);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      return IgnorePointer(
        child: Stack(key: const Key('chat-backdrop'), children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF131D5C), Color(0xFF0D164D), Color(0xFF0A1240)],
                  stops: [0, 0.45, 1],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: ClipRect(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _drift,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(0, -kDoodleTile * _drift.value),
                    child: child,
                  ),
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: c.maxHeight + kDoodleTile,
                    maxHeight: c.maxHeight + kDoodleTile,
                    child: Container(
                      decoration: const BoxDecoration(
                        image: DecorationImage(
                          image: AssetImage(kChatDoodle),
                          repeat: ImageRepeat.repeat,
                          alignment: Alignment.topLeft,
                          scale: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: NightSkyEffects(
              width: c.maxWidth,
              height: c.maxHeight,
              period: kChatShootingStarPeriod,
              avoidTopLeft: false,
              excited: widget.thinking,
            ),
          ),
        ]),
      );
    });
  }
}

// ═══════════════════════════════════════════════════════════════════
// 頭像與狀態
// ═══════════════════════════════════════════════════════════════════

const Set<String> kBuddyMoods = {'happy', 'bored', 'tired', 'anxious'};

/// 不認得的心情一律當 bored（同 `HomePet`）。⚠️ 絕不退回 happy：焦慮的夜晚畫成開心的寵物＝紅線 5。
String buddyMood(String? mood) => kBuddyMoods.contains(mood) ? mood! : 'bored';

/// 使用者生成的頭像：`assets/avatars/<dog|cat>_<心情>.png`。
String buddyAvatarAsset(PetSpecies species, String? mood) =>
    'assets/avatars/${species.name}_${buddyMood(mood)}.png';

/// 狀態列那行字。照後端的心情；想答案時一律 thinking…（2026-11-22 使用者定）。
String buddyStatus(String? mood, {bool thinking = false}) {
  if (thinking) return 'thinking…';
  return switch (buddyMood(mood)) {
    'happy' => 'Feeling happy',
    'tired' => 'Feeling sleepy',
    'anxious' => 'Feeling a little uneasy',
    _ => 'Feeling a bit bored',
  };
}

/// 圓形頭像。順序：那個心情的生成頭像 → 同一隻的 bored 頭像 → 程式裁切的寵物（整隻縮進圓裡，**不漫出來**）。
/// [tilt]＝想答案中：歪頭晃一晃（減少動態效果時不動）。
class BuddyAvatar extends StatefulWidget {
  final String? mood;
  final double size;
  final bool tilt;
  const BuddyAvatar({super.key, this.mood, this.size = 46, this.tilt = false});

  @override
  State<BuddyAvatar> createState() => _BuddyAvatarState();
}

class _BuddyAvatarState extends State<BuddyAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  void _sync() {
    final reduce = MediaQuery.of(context).disableAnimations;
    if (widget.tilt && !reduce) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(BuddyAvatar old) {
    super.didUpdateWidget(old);
    if (old.tilt != widget.tilt) _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return ValueListenableBuilder<PetSpecies>(
      valueListenable: PetChoice.current,
      builder: (context, species, _) {
        Widget fallback() => FittedBox(
              key: const Key('buddy-avatar-fallback'),
              child: HomePet(mood: buddyMood(widget.mood), size: s, animate: false),
            );
        final face = Image.asset(
          buddyAvatarAsset(species, widget.mood),
          key: const Key('buddy-avatar-image'),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Image.asset(
            buddyAvatarAsset(species, 'bored'),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => fallback(),
          ),
        );
        return AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            // 0 → -12° → 0（同設計稿：歪頭想事情）
            final t = _c.value;
            final angle = -0.21 * (t < 0.5 ? t * 2 : (1 - t) * 2);
            return Transform.rotate(angle: angle, child: child);
          },
          child: Container(
            key: const Key('buddy-avatar'),
            width: s,
            height: s,
            padding: EdgeInsets.all(s * 0.08),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF2B3C82),
              border: Border.all(color: const Color(0xB37B61FF), width: 1.5),
            ),
            // 圓裡面一律裁掉：頭像或寵物都不准畫到圓外（原本 OverflowBox 1.7 倍漫出來）
            child: ClipOval(child: face),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 打招呼那一則（App 用固定句型組，不呼叫 AI）
// ═══════════════════════════════════════════════════════════════════

/// 時段：05–12 Morning、12–18 Afternoon、其他 Evening（2026-11-22 使用者定）。
String greetingWord(DateTime now) {
  final h = now.hour;
  if (h >= 5 && h < 12) return 'Morning';
  if (h >= 12 && h < 18) return 'Afternoon';
  return 'Evening';
}

/// 這一晚的鍵：起床那天（同後端 night_date、早晨報告）。
String _dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _hm(num minutes) {
  final m = minutes.round();
  return m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '${m}m';
}

/// 打招呼那一則。[night] 是 `/home?date=今天` 的回應（今天起床的那一晚＝昨晚）；
/// 拿不到、不是今天那一晚、或什麼都沒有 → 只打招呼，不講舊的晚上。
///
/// ⚠️ 數字照抄後端（分數四捨五入成整數，同 App 其他地方）；不寫好壞。
String buildGreeting({required String name, required DateTime now, Map<String, dynamic>? night}) {
  final hello = '${greetingWord(now)}, $name!';
  const ask = 'Ask me anything about your sleep.';
  if (night == null || night['date'] != _dayKey(now)) return '$hello $ask';

  final scoring = (night['scoring'] as Map?)?.cast<String, dynamic>();
  final metrics = (night['metrics'] as Map?)?.cast<String, dynamic>();
  final behavior = (night['behavior'] as Map?)?.cast<String, dynamic>();
  final score = (scoring?['final_score'] as num?);
  final minutes = (metrics?['sleep_duration_minutes'] as num?);
  if (score != null && minutes != null && minutes > 0) {
    return '$hello You slept ${_hm(minutes)} last night, and your sleep score was ${score.round()}. '
        'Want to look at it together?';
  }
  final lightsOut = parseWallClock(behavior?['lights_out_at']);
  if (lightsOut != null) {
    final t = '${lightsOut.hour.toString().padLeft(2, '0')}:${lightsOut.minute.toString().padLeft(2, '0')}';
    return '$hello You put your phone down at $t last night. Want to look at it together?';
  }
  return '$hello $ask';
}

/// 置中的日期膠囊（「Today」、「Wednesday, Nov 18」、「Nov 9 – Nov 15」）。
class ChatDateChip extends StatelessWidget {
  final String text;
  const ChatDateChip(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xD9121A47),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Color(0xFFC9CFEE), fontSize: 11.5, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// 泡泡的小尾巴（[left]＝寵物那一側）。
class BubbleTail extends StatelessWidget {
  final Color color;
  final bool left;
  const BubbleTail({super.key, required this.color, required this.left});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(10, 10), painter: _TailPainter(color, left));
}

class _TailPainter extends CustomPainter {
  final Color color;
  final bool left;
  _TailPainter(this.color, this.left);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path();
    if (left) {
      p..moveTo(size.width, 0)..lineTo(size.width, size.height)..lineTo(0, size.height);
    } else {
      p..moveTo(0, 0)..lineTo(size.width, size.height)..lineTo(0, size.height);
    }
    canvas.drawPath(p..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TailPainter old) => old.color != color || old.left != left;
}
