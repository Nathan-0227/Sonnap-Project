import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/plan_screen.dart' show petJumpPose;
import '../services/friends_service.dart';
import 'home_pet.dart';
import 'streak_card.dart' show speciesOf;

/// 送禮頁（2026-11-22 使用者定，照 Finch 的做法；共識摘要見對話 Q1–Q15）。
///
/// 點小鎮裡的朋友 → 資料卡 → 「Send something」→ 這一頁：
/// 上面你的寵物＋朋友的寵物站在一起、你的寵物說一句話（依選中的那一格換）；
/// 下面 3×3 格子，**先選再按 Send**（一天只能送一次，點錯收不回來）。
///
/// ⚠️ 字全部照抄後端（social/town.KINDS）：按鈕上的字、泡泡那句。這裡只把 {friend} 換成名字。
/// ⚠️ 不鎖格子、不扣能量、不給 XP（Q5：等級反映睡眠品質，睡不好的人能送的關心不該比較少）。
/// ⚠️ 不推播；送出去對方下次打開 Sonnap 才看到——泡泡照實這樣說。
/// ⚠️ 減少動態效果：圖示不飛、寵物不跳，只換字。

/// 上半部的背景（使用者生成）。讀不到就是原本的藍色漸層。下緣是草地，兩隻寵物站在上面。
const String kVisitGiftBackground = 'assets/backgrounds/visit_gift.jpg';

/// 圖示（使用者生成的 3×3 圖示表切的）。讀不到就退回按鈕字裡的 emoji。
String visitIconAsset(String kind) => 'assets/visits/$kind.png';

/// 圓圈的底色，只是裝飾（照圖示的主色調淡一點）。不認得的種類用紫色。
const Map<String, Color> kVisitCircle = {
  'pet': Color(0xFFE4DAFF),
  'good_night': Color(0xFF2B3A78),
  'sleep_well': Color(0xFFDCEBFF),
  'proud': Color(0xFFFFF1C4),
  'good_morning': Color(0xFFFFE3C2),
  'hugs': Color(0xFFFFDCE3),
  'you_got_this': Color(0xFFFFE6D8),
  'thanks': Color(0xFFFFF4CC),
  'outfit': Color(0xFFD9F3E6),
};

/// 按鈕上的字（"Good night 🌙"）拆成 (emoji, 名字)：最後一段不是字母就當 emoji。
(String, String) splitVisitLabel(String label) {
  final parts = label.trim().split(RegExp(r'\s+'));
  if (parts.length > 1 && !RegExp(r'[A-Za-z0-9]').hasMatch(parts.last)) {
    return (parts.last, parts.sublist(0, parts.length - 1).join(' '));
  }
  return (label.isEmpty ? '?' : label.characters.first, label);
}

/// 一打開預設選哪一格（Q9：只看自己手機的時間，不碰朋友的狀態）：
/// 晚上 18:00–04:59 → good_night，早上 05:00–10:59 → good_morning，其他 → 第一格。
/// 後端沒有那一種就退回第一格。
String? defaultVisitKind(DateTime now, List<String> keys) {
  if (keys.isEmpty) return null;
  final h = now.hour;
  final want = (h >= 18 || h < 5)
      ? 'good_night'
      : h < 11
      ? 'good_morning'
      : keys.first;
  return keys.contains(want) ? want : keys.first;
}

/// 泡泡那句：後端的 {friend} 換成名字；舊版後端沒給 → 一句中性的。
String visitInvite(String? template, String friend) =>
    template == null ? "Let's send $friend something nice!" : template.replaceAll('{friend}', friend);

/// [onSend] 回傳 null＝送出成功；否則是要顯示的那句話（後端原文，409 是今天已經來過了）。
Future<void> showVisitGiftSheet(
  BuildContext context, {
  required TownPerson friend,
  TownPerson? me,
  required List<(String, String)> kinds,
  Map<String, String> invites = const {},
  required Future<String?> Function(String kind) onSend,
  DateTime Function() clock = DateTime.now,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.92,
      child: VisitGiftSheet(
        friend: friend,
        me: me,
        kinds: kinds,
        invites: invites,
        onSend: onSend,
        clock: clock,
      ),
    ),
  );
}

class VisitGiftSheet extends StatefulWidget {
  final TownPerson friend;
  final TownPerson? me;
  final List<(String, String)> kinds;
  final Map<String, String> invites;
  final Future<String?> Function(String kind) onSend;
  final DateTime Function() clock;

  const VisitGiftSheet({
    super.key,
    required this.friend,
    this.me,
    required this.kinds,
    this.invites = const {},
    required this.onSend,
    this.clock = DateTime.now,
  });

  @override
  State<VisitGiftSheet> createState() => _VisitGiftSheetState();
}

class _VisitGiftSheetState extends State<VisitGiftSheet> with TickerProviderStateMixin {
  late String? _sent = widget.friend.sent;

  /// 打開時就已經送過了（跟剛剛送出去的分開：泡泡的字不一樣）。
  late final bool _sentBefore = widget.friend.sent != null;
  late String? _picked =
      widget.friend.sent ?? defaultVisitKind(widget.clock(), [for (final k in widget.kinds) k.$1]);
  bool _busy = false;
  String? _error;

  /// 圖示飛過去（0→1），飛到之後寵物跳一下（0→1）。
  late final AnimationController _fly = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final AnimationController _hop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  final _stackKey = GlobalKey();
  final _friendPetKey = GlobalKey();
  final Map<String, GlobalKey> _tileKeys = {};
  Offset? _flyFrom, _flyTo;

  String get _name => widget.friend.displayName.replaceAll(' (demo)', '');

  @override
  void dispose() {
    _fly.dispose();
    _hop.dispose();
    super.dispose();
  }

  Offset? _centerOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || stack == null || !box.hasSize) return null;
    return stack.globalToLocal(box.localToGlobal(box.size.center(Offset.zero)));
  }

  Future<void> _send() async {
    final kind = _picked;
    if (kind == null || _busy || _sent != null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSend(kind);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error == null) {
        _sent = kind;
      } else {
        _error = error;
      }
    });
    if (error != null) return;
    HapticFeedback.lightImpact();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) return;
    final tile = _tileKeys[kind];
    _flyFrom = tile == null ? null : _centerOf(tile);
    _flyTo = _centerOf(_friendPetKey);
    if (_flyFrom != null && _flyTo != null) {
      await _fly.forward(from: 0);
    }
    if (mounted) _hop.forward(from: 0);
  }

  String get _bubble {
    if (_error != null) return _error!;
    if (_sent != null && !_sentBefore) {
      return 'Sent! $_name will see it next time they open Sonnap.';
    }
    if (_sentBefore) return 'We already stopped by $_name today. Come back tomorrow!';
    return visitInvite(widget.invites[_picked], _name);
  }

  String _labelOf(String? kind) =>
      splitVisitLabel(widget.kinds.where((k) => k.$1 == kind).firstOrNull?.$2 ?? '').$2;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Container(
        key: const Key('visit-gift-sheet'),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3B4FB8), Color(0xFF2A3A8F)],
          ),
        ),
        child: Stack(
          key: _stackKey,
          children: [
            Column(
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // 背景鋪滿上半部、貼著下緣（草地在下面），讀不到就留原本的漸層
                      Image.asset(
                        kVisitGiftBackground,
                        key: const Key('visit-gift-background'),
                        fit: BoxFit.cover,
                        alignment: Alignment.bottomCenter,
                        errorBuilder: (context, error, stack) => const SizedBox.shrink(),
                      ),
                      _stage(),
                    ],
                  ),
                ),
                _panel(pad.bottom),
              ],
            ),
            Positioned(
              left: 12,
              top: 12,
              child: IconButton(
                key: const Key('visit-gift-close'),
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
              ),
            ),
            _flyingIcon(),
          ],
        ),
      ),
    );
  }

  /// 上半部：泡泡＋兩隻寵物。高度不夠時寵物跟著縮。
  Widget _stage() => LayoutBuilder(
    builder: (context, box) {
      final pet = (box.maxHeight * 0.42).clamp(56.0, 120.0);
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 56, 20, 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(child: _speech()),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  key: const Key('visit-gift-my-pet'),
                  width: pet,
                  height: pet,
                  child: HomePet(
                    mood: widget.me?.petMood,
                    species: speciesOf(widget.me?.petSpecies),
                    size: pet * 0.95,
                    animate: false,
                    equippedItemId: widget.me?.equippedItemId,
                  ),
                ),
                SizedBox(width: pet * 0.15),
                AnimatedBuilder(
                  animation: _hop,
                  builder: (context, child) {
                    final j = petJumpPose(_hop.isAnimating ? _hop.value : 0.0);
                    return Transform.translate(
                      offset: Offset(0, -pet * 0.35 * j.lift),
                      child: Transform(
                        alignment: Alignment.bottomCenter,
                        transform: Matrix4.diagonal3Values(j.scaleX, j.scaleY, 1),
                        child: child,
                      ),
                    );
                  },
                  child: SizedBox(
                    key: _friendPetKey,
                    width: pet * 0.85,
                    height: pet * 0.85,
                    // 朋友的心情只有他有分享才有；沒有 → HomePet 畫 bored（不畫 happy）
                    child: HomePet(
                      key: const Key('visit-gift-friend-pet'),
                      mood: widget.friend.petMood,
                      species: speciesOf(widget.friend.petSpecies),
                      size: pet * 0.8,
                      animate: false,
                      // 他有分享 Pet outfit 才有（後端判斷），沒有就畫沒穿
                      equippedItemId: widget.friend.equippedItemId,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );

  Widget _speech() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 3))],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Text(
            _bubble,
            key: ValueKey(_bubble),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _error != null ? const Color(0xFFB3261E) : const Color(0xFF1E2550),
              fontSize: 17,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ),
      ),
      // 泡泡的尾巴，指向左邊你的寵物
      Align(
        alignment: const Alignment(-0.35, 0),
        child: CustomPaint(size: const Size(22, 12), painter: _TailPainter()),
      ),
    ],
  );

  /// 下半部：3×3 格子＋Send。
  Widget _panel(double bottomInset) {
    final done = _sent != null;
    return Container(
      padding: EdgeInsets.fromLTRB(14, 16, 14, 14 + bottomInset),
      decoration: const BoxDecoration(
        color: Color(0xFF26338A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 1.15,
            children: [for (final (key, label) in widget.kinds) _tile(key, label)],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              key: const Key('visit-gift-send'),
              onPressed: done || _busy || _picked == null ? null : _send,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF3B4FB8),
                disabledBackgroundColor: const Color(0x33FFFFFF),
                disabledForegroundColor: const Color(0xAAFFFFFF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              child: Text(
                done
                    ? 'Sent today · Visit again tomorrow'
                    : _busy
                    ? 'Sending…'
                    : 'Send ${_labelOf(_picked)}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(String key, String label) {
    final (emoji, name) = splitVisitLabel(label);
    final picked = _picked == key;
    final sentThis = _sent == key;
    final dim = _sent != null && !sentThis;
    final tileKey = _tileKeys.putIfAbsent(key, GlobalKey.new);
    return Opacity(
      opacity: dim ? 0.4 : 1,
      child: Semantics(
        button: true,
        selected: picked,
        label: name,
        child: GestureDetector(
          key: Key('visit-kind-$key'),
          behavior: HitTestBehavior.opaque,
          onTap: _sent != null || _busy ? null : () => setState(() {
            _picked = key;
            _error = null;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: picked ? const Color(0x33FFFFFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              border: sentThis ? Border.all(color: const Color(0xFFFFD27A), width: 2) : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  key: tileKey,
                  width: 58,
                  height: 58,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kVisitCircle[key] ?? const Color(0xFFE4DAFF),
                    border: Border.all(color: Colors.white, width: 2.5),
                  ),
                  child: VisitIcon(kind: key, emoji: emoji),
                ),
                const SizedBox(height: 6),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: sentThis ? const Color(0xFFFFD27A) : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 送出去那一刻：選中那顆圖示從格子飛到朋友的寵物身上，邊飛邊變小。
  Widget _flyingIcon() => AnimatedBuilder(
    animation: _fly,
    builder: (context, _) {
      final from = _flyFrom, to = _flyTo, kind = _sent;
      if (!_fly.isAnimating || from == null || to == null || kind == null) {
        return const SizedBox.shrink();
      }
      final t = Curves.easeInOutCubic.transform(_fly.value);
      // 弧線往上拋一點
      final at = Offset.lerp(from, to, t)! - Offset(0, 80 * 4 * t * (1 - t));
      final size = 58 * (1 - 0.45 * t);
      final emoji = splitVisitLabel(widget.kinds.where((k) => k.$1 == kind).firstOrNull?.$2 ?? '').$1;
      return Positioned(
        left: at.dx - size / 2,
        top: at.dy - size / 2,
        child: IgnorePointer(
          child: SizedBox(
            key: const Key('visit-gift-flying'),
            width: size,
            height: size,
            child: VisitIcon(kind: kind, emoji: emoji),
          ),
        ),
      );
    },
  );
}

/// 圖示：有使用者生成的圖就用圖，讀不到就是 emoji。
class VisitIcon extends StatelessWidget {
  final String kind;
  final String emoji;
  const VisitIcon({super.key, required this.kind, required this.emoji});

  @override
  Widget build(BuildContext context) => Image.asset(
    visitIconAsset(kind),
    fit: BoxFit.contain,
    errorBuilder: (context, error, stack) => FittedBox(
      child: Text(emoji, key: Key('visit-emoji-$kind'), style: const TextStyle(fontSize: 28)),
    ),
  );
}

class _TailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width * 0.3, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
