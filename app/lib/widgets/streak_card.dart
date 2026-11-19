// 好友頁的 Streak 大卡（2026-11-15 使用者定，照參考圖 My Habits Tracker）：
// 寵物冒著火＋「N Days Streak」＋週一到週日一排。
//
// - 寵物是隊友的 2D 小狗／貓（他選的那一隻），**不另外畫參考圖那隻生氣的熊**
// - 火：連續 0 晚沒有火、1–2 晚小火、3 晚以上大火；程式畫的，減少動態效果時不動
// - 那一排：準時打勾、晚了空心圈（**不打叉、不用紅色**）、沒資料淡灰「—」、還沒到只寫日期
// - 底下一行只寫事實「4 of 7 nights on time this week」；參考圖的「Rise and Good」那種評語不照做
// - 沒公開連續天數（null）→ 不畫大字與火；沒公開準時（streakWeek null）→ 不畫那一排
// - 2026-11-16 使用者定：自己那張（好友頁最上面）寵物站在場景圖裡（`scene`，使用者生成的樹屋），
//   不包框、字直接排在頁面上；讀不到圖退回漸層。朋友的卡（底部面板、預覽）照舊有框
// - 那一排改成一條紫色軌道：連續準時的晚上之間連起來（參考圖），火維持橘色
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/friends_service.dart';
import '../services/pet_choice.dart';
import 'home_pet.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const kStreakTrackColor = Color(0xFF7657FF);
const kFriendsScene = 'assets/backgrounds/friends_treehouse.jpg';

/// 連續幾晚 → 火的大小：0 沒有、1 小、2 大。
int flameLevel(int? streak) {
  if (streak == null || streak <= 0) return 0;
  return streak >= 3 ? 2 : 1;
}

/// 「4 Days Streak」；單數寫 Day。
String streakTitle(int streak) =>
    '$streak ${streak == 1 ? 'Day' : 'Days'} Streak';

/// 「4 of 7 nights on time this week」。
String streakWeekLine(List<StreakDay> week) {
  final n = week.where((d) => d.status == 'on_time').length;
  return '$n of ${week.length} nights on time this week';
}

PetSpecies speciesOf(String? id) => PetChoice.fromId(id);

class StreakCard extends StatelessWidget {
  final FriendSummary summary;

  /// 畫哪一隻：自己的卡用 null（照自己選的），朋友的用他公開的。
  final PetSpecies? species;
  final Color color;

  /// 場景圖：給了就是好友頁最上面那種——圖直接當頁面背景（整個寬度、沒有框），
  /// 底部淡進頁面底色，寵物站在圖裡的草地上。
  final String? scene;

  /// 疊在場景上方的東西（好友頁的標題列）。只有 scene 模式用。
  final Widget? header;

  /// 場景底部要淡進去的顏色＝頁面底色。
  final Color pageColor;

  const StreakCard({
    super.key,
    required this.summary,
    this.species,
    this.color = const Color(0xFFFF8A5C),
    this.scene,
    this.header,
    this.pageColor = const Color(0xFF081326),
  });

  Widget _petWithFlames(int? streak, double size) => PetWithFlames(
    mood: summary.petMood,
    species: species,
    streak: streak,
    size: size,
    color: color,
  );

  Widget _sceneHeader(int? streak) => AspectRatio(
    key: const Key('streak-scene'),
    aspectRatio: 1.4,
    child: Stack(
      fit: StackFit.expand,
      children: [
        // 圖提早 2 像素結束：高度不是整數時，最底下一列像素會露在淡出外面變成一條線
        Positioned.fill(
          bottom: 2,
          child: Image.asset(
            scene!,
            fit: BoxFit.cover,
            alignment: Alignment.bottomCenter,
            errorBuilder: (_, _, _) => const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF2A2F6E), Color(0xFF1A1F4A)],
                ),
              ),
            ),
          ),
        ),
        // 上緣稍微壓暗（標題要看得清楚），下緣淡進頁面底色（沒有框線）
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                pageColor.withValues(alpha: 0.55),
                pageColor.withValues(alpha: 0),
                pageColor.withValues(alpha: 0),
                pageColor,
              ],
              stops: const [0, 0.3, 0.7, 0.97],
            ),
          ),
        ),
        // 寵物站在草地正中間（圖的地面約在 65% 以下）
        LayoutBuilder(
          builder: (context, c) => Align(
            alignment: const Alignment(0.12, 0.82),
            child: _petWithFlames(streak, c.maxHeight * 0.42),
          ),
        ),
        if (header != null)
          Positioned(top: 0, left: 0, right: 0, child: header!),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final streak = summary.currentStreak;
    final week = summary.streakWeek;
    final framed = scene == null;
    return Container(
      key: const Key('streak-card'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: framed
          ? const EdgeInsets.fromLTRB(16, 18, 16, 18)
          : EdgeInsets.zero,
      decoration: framed
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF2A2F6E), Color(0xFF1A1F4A)],
              ),
              border: Border.all(color: const Color(0x22FFFFFF)),
            )
          : null,
      child: Column(
        children: [
          if (framed)
            SizedBox(
              height: 150,
              child: Center(child: _petWithFlames(streak, 120)),
            )
          else
            _sceneHeader(streak),
          SizedBox(height: framed ? 8 : 0),
          if (streak != null) ...[
            Text(
              streakTitle(streak),
              key: const Key('streak-title'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (summary.bestStreak != null)
              Text(
                'Best ${summary.bestStreak}',
                key: const Key('streak-best'),
                style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 12),
              ),
          ],
          if (week != null && week.length == 7) ...[
            const SizedBox(height: 14),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: framed ? 0 : 20),
              child: StreakWeekRow(week: week),
            ),
            const SizedBox(height: 10),
            Text(
              streakWeekLine(week),
              key: const Key('streak-week-line'),
              style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

/// 週一 → 週日一排。今天（最後一個不是 future 的那天）亮起來。
class StreakWeekRow extends StatelessWidget {
  final List<StreakDay> week;
  final Color color;
  const StreakWeekRow({
    super.key,
    required this.week,
    this.color = kStreakTrackColor,
  });

  bool _on(int i) => i >= 0 && i < week.length && week[i].status == 'on_time';

  @override
  Widget build(BuildContext context) {
    final todayIndex = week.lastIndexWhere((d) => d.status != 'future');
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    _weekdays[i],
                    style: TextStyle(
                      color: i == todayIndex ? color : const Color(0x99FFFFFF),
                      fontSize: 11,
                      fontWeight: i == todayIndex
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0x14FFFFFF),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 連續準時的晚上之間連成一段亮的軌道
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 12,
                              color: _on(i) && _on(i - 1)
                                  ? color.withValues(alpha: 0.45)
                                  : null,
                            ),
                          ),
                          Expanded(
                            child: Container(
                              height: 12,
                              color: _on(i) && _on(i + 1)
                                  ? color.withValues(alpha: 0.45)
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      _Day(
                        key: Key('streak-day-${week[i].date}'),
                        day: week[i],
                        color: color,
                        isToday: i == todayIndex,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Day extends StatelessWidget {
  final StreakDay day;
  final Color color;
  final bool isToday;
  const _Day({
    super.key,
    required this.day,
    required this.color,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    const size = 24.0;
    switch (day.status) {
      case 'on_time':
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: isToday ? Border.all(color: Colors.white, width: 2) : null,
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 16,
            color: Colors.white,
            semanticLabel: 'on time',
          ),
        );
      case 'late':
        // 晚了：空心圈，不打叉、不用紅色
        return Semantics(
          label: 'late',
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.7), width: 2),
            ),
          ),
        );
      case 'none':
        return const Text(
          '—',
          semanticsLabel: 'no data',
          style: TextStyle(color: Color(0x55FFFFFF), fontSize: 13),
        );
      default: // future：只寫日期
        final d = DateTime.tryParse(day.date);
        return Text(
          d == null ? '' : '${d.day}',
          style: const TextStyle(color: Color(0x55FFFFFF), fontSize: 11),
        );
    }
  }
}

/// 寵物後面的火。level 1 小、2 大；減少動態效果時靜止。
class StreakFlames extends StatefulWidget {
  final int level;
  final Color color;
  const StreakFlames({super.key, required this.level, required this.color});

  @override
  State<StreakFlames> createState() => _StreakFlamesState();
}

class _StreakFlamesState extends State<StreakFlames>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _c.stop();
      _c.value = 0.3;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => CustomPaint(
      painter: FlamePainter(
        t: _c.value,
        level: widget.level,
        color: widget.color,
      ),
    ),
  );
}

class FlamePainter extends CustomPainter {
  final double t;
  final int level;
  final Color color;
  FlamePainter({required this.t, required this.level, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final base = size.height * 0.92;
    final scale = level >= 2 ? 1.0 : 0.62;
    final glow = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.height * 0.12);
    canvas.drawCircle(
      Offset(cx, size.height * 0.62),
      size.height * 0.38 * scale,
      glow,
    );
    // 幾條火舌，各自搖一點
    final tongues = level >= 2 ? 7 : 5;
    for (var i = 0; i < tongues; i++) {
      final f = i / (tongues - 1); // 0..1
      final x = cx + (f - 0.5) * size.height * 0.95 * scale;
      final mid = 1 - (f - 0.5).abs() * 1.4; // 中間高
      final wobble = math.sin((t + i * 0.17) * 2 * math.pi);
      final h = size.height * (0.45 + 0.4 * mid) * scale * (1 + 0.06 * wobble);
      final w = size.height * 0.2 * scale;
      final tip = Offset(x + wobble * w * 0.25, base - h);
      final path = Path()
        ..moveTo(x - w / 2, base)
        ..quadraticBezierTo(x - w * 0.7, base - h * 0.55, tip.dx, tip.dy)
        ..quadraticBezierTo(x + w * 0.7, base - h * 0.55, x + w / 2, base)
        ..close();
      final rect = Rect.fromLTRB(x - w, tip.dy, x + w, base);
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              color.withValues(alpha: 0.85),
              Color.lerp(
                color,
                const Color(0xFFFFD96A),
                0.6,
              )!.withValues(alpha: 0.6),
              const Color(0x00FFD96A),
            ],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(FlamePainter old) =>
      old.t != t || old.level != level || old.color != color;
}

/// 背景－火焰－寵物：火焰在寵物正後面（連續天數 0 就沒有火）。好友頁最上面與動態卡共用。
/// 外框是寵物的 1.25 倍，寵物貼著底邊站，所以腳的位置跟單獨畫寵物一樣。
class PetWithFlames extends StatelessWidget {
  final String? mood;
  final PetSpecies? species;
  final int? streak;
  final double size;
  final Color color;
  const PetWithFlames({
    super.key,
    required this.mood,
    required this.species,
    required this.streak,
    required this.size,
    this.color = const Color(0xFFFF8A5C),
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size * 1.25,
    height: size * 1.25,
    child: Stack(
      alignment: Alignment.bottomCenter,
      children: [
        if (flameLevel(streak) > 0)
          Positioned.fill(
            // 邊緣淡出成一圈光，不留平平的底邊（放在場景裡時像一塊橘色方塊）
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => const RadialGradient(
                center: Alignment(0, -0.1),
                radius: 0.5,
                colors: [Colors.white, Colors.white, Color(0x00FFFFFF)],
                stops: [0, 0.4, 1],
              ).createShader(r),
              // 火舌會畫出框外，框外的部分遮罩管不到，先裁掉
              child: ClipRect(
                child: StreakFlames(
                  key: Key('streak-flames-${flameLevel(streak)}'),
                  level: flameLevel(streak),
                  color: color,
                ),
              ),
            ),
          ),
        HomePet(mood: mood, size: size, species: species),
      ],
    ),
  );
}
