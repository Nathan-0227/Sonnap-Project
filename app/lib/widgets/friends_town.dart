import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/friends_service.dart';
import 'friend_night_card.dart' show openFriendNight;
import 'home_pet.dart';
import 'streak_card.dart' show speciesOf;

/// 好友小鎮（2026-11-17 使用者定，照 Finch 的做法：朋友之間只看到寵物）。
///
/// 一張很寬的夜景（使用者生成的 `town_night.jpg`），我在正中間，朋友照加好友的先後
/// 一右一左往外排，左右滑著看。**昨晚準時放下手機、而且有分享 On time 的人頭上一顆星、
/// 腳下一圈金光**；其他人一律不亮——晚了、沒資料、沒分享看起來**完全一樣**，不變暗、不說原因
/// （後端也只給 glow: false）。
///
/// ⚠️ 小鎮裡**不畫心情**（所有寵物同一個樣子）；心情只在點開的小卡上、而且要他有分享。
/// ⚠️ 拜訪不給 XP、不影響分數、不推播；按鈕上的字照抄後端（social/town.py）。
/// ⚠️ 這個檔案一格都不算：誰亮、送過沒，全部照抄後端。

const kTownGold = Color(0xFFFFD27A);
const _townImage = 'assets/backgrounds/town_night.jpg';
const _imageAspect = 2172 / 724;

/// 腳踩在圖高的哪裡（那張圖的草地從約 75% 開始）。
const _groundAt = 0.86;

/// 小寵物（使用者生成的兩張，柴犬與灰色虎斑貓，一個姿勢）。還沒放進來之前退回首頁那隻寵物縮小。
/// 小鎮裡不畫心情，所以退路一律畫 bored（中性），**絕不畫 happy**。
class TownPetSprite extends StatelessWidget {
  final String? species;
  final double size;
  const TownPetSprite({super.key, required this.species, this.size = 58});

  @override
  Widget build(BuildContext context) {
    final kind = species == 'cat' ? 'cat' : 'dog';
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/pets/town/$kind.png',
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => HomePet(
          mood: 'bored',
          species: speciesOf(species),
          size: size * 0.92,
        ),
      ),
    );
  }
}

/// 頭上那顆星：慢慢閃；系統開「減少動態效果」時靜止。
class TownStar extends StatefulWidget {
  final double size;
  const TownStar({super.key, this.size = 18});

  @override
  State<TownStar> createState() => _TownStarState();
}

class _TownStarState extends State<TownStar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c
        ..stop()
        ..value = 1;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_c.value);
        return Opacity(
          opacity: 0.6 + 0.4 * t,
          child: Transform.scale(
            scale: 0.88 + 0.12 * t,
            child: SizedBox(
              width: s * 2.2,
              height: s * 2.2,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          kTownGold.withValues(alpha: 0.55),
                          kTownGold.withValues(alpha: 0),
                        ],
                      ),
                    ),
                    child: SizedBox(width: s * 2.2, height: s * 2.2),
                  ),
                  Icon(Icons.star_rounded, color: kTownGold, size: s),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 腳下那圈金光（扁的橢圓）。
class TownHalo extends StatelessWidget {
  final double width;
  const TownHalo({super.key, required this.width});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: width * 0.24,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.all(
          Radius.elliptical(width / 2, width * 0.12),
        ),
        gradient: RadialGradient(
          colors: [
            kTownGold.withValues(alpha: 0.55),
            kTownGold.withValues(alpha: 0),
          ],
        ),
      ),
    ),
  );
}

class TownNameTag extends StatelessWidget {
  final TownPerson person;
  const TownNameTag({super.key, required this.person});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0x99101634),
      borderRadius: BorderRadius.circular(12),
      border: person.mine ? Border.all(color: const Color(0xFFB9A6FF)) : null,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            person.mine ? 'You' : person.displayName.replaceAll(' (demo)', ''),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: person.mine ? const Color(0xFFD9CCFF) : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (person.demo) ...[
          const SizedBox(width: 4),
          const Text(
            'Demo',
            style: TextStyle(color: Color(0x99FFFFFF), fontSize: 10),
          ),
        ],
      ],
    ),
  );
}

/// 誰站在哪一格：我在 0，朋友照後端順序 +1、−1、+2、−2…（一右一左往外排）。
List<int> townSlots(int friends) => [
  0,
  for (var i = 0; i < friends; i++) (i.isEven ? 1 : -1) * (i ~/ 2 + 1),
];

/// 夜景本身：可以左右滑，一開始把我放在畫面正中間。
class TownScene extends StatefulWidget {
  final TownState town;
  final double height;
  final void Function(TownPerson person) onTap;

  /// 兩個人之間隔多寬。
  final double spacing;

  const TownScene({
    super.key,
    required this.town,
    required this.onTap,
    this.height = 300,
    this.spacing = 92,
  });

  @override
  State<TownScene> createState() => _TownSceneState();
}

class _TownSceneState extends State<TownScene> {
  ScrollController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final tileW = h * _imageAspect;
    final me = widget.town.me;
    final friends = widget.town.friends;
    final ordered = [?me, ...friends];
    final slots = townSlots(friends.length);
    final reach = slots.isEmpty
        ? 0
        : slots.map((s) => s.abs()).reduce(math.max);
    // 兩邊都要留半個間隔＋邊距；人多到一張圖放不下就左右翻轉接著鋪
    final needed = (reach + 1) * widget.spacing * 2;
    final width = math.max(tileW, needed);
    final center = width / 2;
    final tiles = (width / tileW).ceil() + 1;
    final groundY = h * _groundAt;

    return LayoutBuilder(
      builder: (context, box) {
        final view = box.maxWidth;
        _controller ??= ScrollController(
          initialScrollOffset: math.max(0, center - view / 2),
        );
        return SizedBox(
          height: h,
          child: SingleChildScrollView(
            key: const Key('town-scroll'),
            controller: _controller,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(width, view),
              height: h,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  // 圖從中間往兩邊鋪（中間那張不翻），我永遠站在原圖的正中間
                  for (var i = -(tiles ~/ 2); i <= tiles ~/ 2; i++)
                    Positioned(
                      left: center - tileW / 2 + i * tileW,
                      top: 0,
                      width: tileW,
                      height: h,
                      child: Transform.flip(
                        flipX: i.isOdd,
                        child: Image.asset(
                          _townImage,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const ColoredBox(color: Color(0xFF101A3F)),
                        ),
                      ),
                    ),
                  for (var i = 0; i < ordered.length; i++)
                    _townie(
                      ordered[i],
                      center + slots[i] * widget.spacing,
                      groundY,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _townie(TownPerson p, double x, double groundY) {
    final pet = p.mine ? 66.0 : 56.0;
    const boxW = 96.0;
    return Positioned(
      left: x - boxW / 2,
      top: groundY - pet - 34,
      width: boxW,
      child: GestureDetector(
        key: Key('town-${p.handle}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onTap(p),
        child: Semantics(
          button: true,
          label: p.mine ? 'You' : p.displayName,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 34,
                child: p.glow
                    ? TownStar(key: Key('town-glow-${p.handle}'), size: 16)
                    : null,
              ),
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  if (p.glow)
                    Positioned(
                      bottom: -pet * 0.1,
                      child: TownHalo(width: pet * 1.5),
                    ),
                  // 首頁那隻寵物自己可以點（會有反應），會把點擊吃掉 → 小鎮裡交給外層
                  IgnorePointer(
                    child: TownPetSprite(species: p.petSpecies, size: pet),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TownNameTag(person: p),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「今天誰來看過你」。訊息照抄後端；沒有人來就整張不出現。
class TownVisitsCard extends StatelessWidget {
  final List<TownVisit> visits;
  const TownVisitsCard({super.key, required this.visits});

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('town-visits'),
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF10265A),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Stopped by today',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        for (final v in visits)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              v.message,
              style: const TextStyle(color: Color(0xDDFFFFFF), fontSize: 14),
            ),
          ),
      ],
    ),
  );
}

/// 點小鎮裡的朋友：名字、（他有分享就）心情的寵物、昨晚準時就一行 ✨、四個拜訪按鈕、See last night。
///
/// [onVisit] 回傳 null＝送出成功；否則是要顯示的那句話（後端的原文）。
Future<void> showTownFriendSheet(
  BuildContext context, {
  required TownPerson person,
  required List<(String, String)> kinds,
  required Future<String?> Function(String kind) onVisit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF161F48),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (context) =>
        _TownFriendSheet(person: person, kinds: kinds, onVisit: onVisit),
  );
}

class _TownFriendSheet extends StatefulWidget {
  final TownPerson person;
  final List<(String, String)> kinds;
  final Future<String?> Function(String kind) onVisit;
  const _TownFriendSheet({
    required this.person,
    required this.kinds,
    required this.onVisit,
  });

  @override
  State<_TownFriendSheet> createState() => _TownFriendSheetState();
}

class _TownFriendSheetState extends State<_TownFriendSheet> {
  late String? _sent = widget.person.sent;
  bool _busy = false;
  String? _error;

  Future<void> _send(String kind) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onVisit(kind);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error == null) {
        _sent = kind;
      } else {
        _error = error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.person;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        key: const Key('town-sheet'),
        padding: EdgeInsets.fromLTRB(22, 12, 22, 20 + (bottom > 0 ? 0 : 8)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0x44FFFFFF),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  // 心情只有他有分享才有；沒有就是 null → HomePet 畫 bored（不畫 happy）
                  child: HomePet(
                    mood: p.petMood,
                    species: speciesOf(p.petSpecies),
                    size: 64,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              p.displayName.replaceAll(' (demo)', ''),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (p.demo) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0x66FFFFFF),
                                ),
                              ),
                              child: const Text(
                                'Demo',
                                style: TextStyle(
                                  color: Color(0xAAFFFFFF),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (p.glow) ...[
                        const SizedBox(height: 4),
                        const Text(
                          'On time last night ✨',
                          key: Key('town-sheet-glow'),
                          style: TextStyle(
                            color: kTownGold,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (i, (key, label)) in widget.kinds.indexed)
                  _chip(key, label, primary: i == 0),
              ],
            ),
            if (_sent != null) ...[
              const SizedBox(height: 10),
              const Text(
                'You can visit again tomorrow.',
                style: TextStyle(color: Color(0x99FFFFFF), fontSize: 13),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                key: const Key('town-sheet-error'),
                style: const TextStyle(color: Color(0xFFFFB4A8), fontSize: 13),
              ),
            ],
            if (p.card != null) ...[
              const SizedBox(height: 14),
              TextButton(
                key: const Key('town-see-night'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor: const Color(0xFFB9A6FF),
                ),
                onPressed: () {
                  final card = p.card!;
                  Navigator.of(context).pop();
                  openFriendNight(context, card);
                },
                child: const Text(
                  'See last night ›',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String key, String label, {required bool primary}) {
    final sentThis = _sent == key;
    final disabled = _busy || _sent != null;
    return Material(
      color: sentThis
          ? const Color(0x22FFFFFF)
          : disabled
          ? const Color(0x14FFFFFF)
          : primary
          ? const Color(0xFF7B61FF)
          : const Color(0xFF2A3570),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: Key('town-visit-$key'),
        borderRadius: BorderRadius.circular(18),
        onTap: disabled ? null : () => _send(key),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            sentThis ? '$label · Sent ✓' : label,
            style: TextStyle(
              color: disabled && !sentThis
                  ? const Color(0x66FFFFFF)
                  : Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
