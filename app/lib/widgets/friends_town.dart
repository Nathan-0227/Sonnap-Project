import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/friends_service.dart';
import 'friend_night_card.dart' show openFriendNight;
import 'home_pet.dart';
import 'streak_card.dart' show speciesOf;

/// 好友小鎮（2026-11-17 使用者定，照 Finch 的做法：朋友之間只看到寵物）。
///
/// 2026-11-18 改成**整個畫面都是小鎮、上下左右都能滑**（使用者給 Finch 的截圖）：一張從斜上方看的
/// 卡通的夜晚村莊（使用者生成的 `town_map.jpg`，有河、橋、池塘），十間房子，正中間有柵欄那間是你家，
/// 朋友照加好友的先後住進離你家近的房子，寵物站在房子右邊那塊亮草地上。**昨晚準時放下手機、而且有分享 On time 的人
/// 頭上一顆會閃的星星**（腳下的金光 11-18 拿掉：那塊草地本來就亮，看不出來）；其他人一律不亮——晚了、沒資料、沒分享看起來**完全一樣**，
/// 不變暗、不說原因（後端也只給 glow: false）。
///
/// ⚠️ 小鎮裡**不畫心情**（所有寵物同一個樣子）；心情只在點開的小卡上、而且要他有分享。
/// ⚠️ 拜訪不給 XP、不影響分數、不推播；按鈕上的字照抄後端（social/town.py）。
/// ⚠️ 這個檔案一格都不算：誰亮、送過沒，全部照抄後端。

const kTownGold = Color(0xFFFFD27A);
const _mapImage = 'assets/backgrounds/town_map.jpg';

/// 原圖 1086 × 1448（寬 ÷ 高）。
const _mapAspect = 1086 / 1448;

/// 十間房子右邊那塊空草地（寵物腳踩的地方），用原圖的比例表示。2026-11-18 在第二版地圖上量的。
/// 0＝正中間有柵欄那間（你家）；其餘照離你家的距離由近到遠排，朋友照加好友的先後住進去。
/// ⚠️ 換地圖就要重量這些點。
const kTownLots = <Offset>[
  Offset(650 / 1086, 712 / 1448),
  Offset(885 / 1086, 478 / 1448),
  Offset(980 / 1086, 828 / 1448),
  Offset(290 / 1086, 868 / 1448),
  Offset(885 / 1086, 1033 / 1448),
  Offset(265 / 1086, 610 / 1448),
  Offset(900 / 1086, 308 / 1448),
  Offset(325 / 1086, 1078 / 1448),
  Offset(300 / 1086, 278 / 1448),
  Offset(395 / 1086, 1243 / 1448),
];

/// 地圖住得下幾個朋友（十間扣掉你家）。
const kTownMaxFriends = 9;

/// 小鎮裡的寵物：就是首頁那一隻（小狗或貓，2026-11-18 使用者定不另外生小寵物圖）。
/// 小鎮裡不畫心情，所以一律畫 bored（中性），**絕不畫 happy**。
class TownPetSprite extends StatelessWidget {
  final String? species;
  final double size;
  const TownPetSprite({super.key, required this.species, this.size = 58});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: HomePet(
      mood: 'bored',
      species: speciesOf(species),
      size: size * 0.92,
    ),
  );
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

/// 名牌：沒有框、只有字，像地圖上的地名（2026-11-18 使用者：深色膠囊框太突兀）。
/// 白字加一圈柔和的深色陰影才讀得到；你自己用淡紫色。
class TownNameTag extends StatelessWidget {
  final TownPerson person;
  const TownNameTag({super.key, required this.person});

  static const _shadow = [
    Shadow(color: Color(0xCC0B1024), blurRadius: 4),
    Shadow(color: Color(0x990B1024), blurRadius: 8),
  ];

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(children: [
      TextSpan(
        text: person.mine ? 'You' : person.displayName.replaceAll(' (demo)', ''),
        style: TextStyle(
          color: person.mine ? const Color(0xFFE2D8FF) : Colors.white,
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          shadows: _shadow,
        ),
      ),
      if (person.demo)
        const TextSpan(
          text: ' · demo',
          style: TextStyle(color: Color(0xBBFFFFFF), fontSize: 10, fontWeight: FontWeight.w600, shadows: _shadow),
        ),
    ]),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: TextAlign.center,
  );
}

/// 整個畫面的小鎮地圖：上下左右滑、不能縮放，一開始讓你家出現在看得到的那塊正中間。
class TownMap extends StatefulWidget {
  final TownState town;
  final void Function(TownPerson person) onTap;

  /// 點木牌。null＝不插木牌（地圖住滿了）。
  final VoidCallback? onAddFriend;

  /// 上面被分頁蓋住、下面被導覽列與小圓鈕蓋住的高度。一開始置中時要扣掉，不然你家會被蓋住。
  final EdgeInsets covered;

  const TownMap({
    super.key,
    required this.town,
    required this.onTap,
    this.onAddFriend,
    this.covered = EdgeInsets.zero,
  });

  @override
  State<TownMap> createState() => _TownMapState();
}

class _TownMapState extends State<TownMap> {
  TransformationController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final view = box.biggest;
        // 地圖要比畫面寬也比畫面高，兩個方向才滑得動
        final mapW = math.max(
          view.width * 1.5,
          view.height * _mapAspect * 1.08,
        );
        final mapH = mapW / _mapAspect;
        final me = kTownLots[0];
        if (_controller == null) {
          final c = widget.covered;
          final seenMidY = c.top + (view.height - c.top - c.bottom) / 2;
          final dx = (view.width / 2 - me.dx * mapW).clamp(
            view.width - mapW,
            0.0,
          );
          final dy = (seenMidY - me.dy * mapH).clamp(view.height - mapH, 0.0);
          _controller = TransformationController(
            Matrix4.translationValues(dx, dy, 0),
          );
        }
        final people = [
          ?widget.town.me,
          ...widget.town.friends.take(kTownMaxFriends),
        ];
        return InteractiveViewer(
          key: const Key('town-map'),
          transformationController: _controller,
          constrained: false,
          scaleEnabled: false,
          minScale: 1,
          maxScale: 1,
          boundaryMargin: EdgeInsets.zero,
          child: SizedBox(
            width: mapW,
            height: mapH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Image.asset(
                    _mapImage,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: Color(0xFF101A3F)),
                  ),
                ),
                if (widget.onAddFriend != null && people.length < kTownLots.length)
                  _inviteSpot(kTownLots[people.length].dx * mapW, kTownLots[people.length].dy * mapH, mapW),
                for (final (i, p) in people.indexed)
                  _townie(
                    p,
                    kTownLots[i].dx * mapW,
                    kTownLots[i].dy * mapH,
                    mapW,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 下一間空房子門口：半透明的「＋」圓圈＋「Invite」（2026-11-18 使用者：木牌太突兀）。
  /// 意思是「這間還沒人住，邀朋友來」，所以放在下一個朋友會住的那塊草地上。
  Widget _inviteSpot(double x, double y, double mapW) {
    final d = mapW * 0.06;
    const boxW = 90.0;
    return Positioned(
      left: x - boxW / 2,
      top: y - d * 0.75,
      width: boxW,
      child: GestureDetector(
        key: const Key('town-invite'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onAddFriend,
        child: Semantics(
          button: true,
          label: 'Invite a friend',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: d,
                height: d,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x33FFFFFF),
                  border: Border.all(color: const Color(0xAAFFFFFF), width: 1.5),
                ),
                child: Icon(Icons.add_rounded, color: Colors.white, size: d * 0.6),
              ),
              const SizedBox(height: 2),
              const Text(
                'Invite',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  shadows: TownNameTag._shadow,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 腳踩在 (x, y)：上面一格放星星，下面是名牌。
  Widget _townie(TownPerson p, double x, double y, double mapW) {
    final pet = mapW * (p.mine ? 0.09 : 0.08);
    final starBox = pet * 0.55;
    const boxW = 110.0;
    return Positioned(
      left: x - boxW / 2,
      // 往下 0.2 隻：寵物圖腳下有留白，不往下的話看起來浮在草地上緣（11-18 使用者）
      top: y - pet - starBox + pet * 0.2,
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
                height: starBox,
                child: p.glow
                    ? TownStar(
                        key: Key('town-glow-${p.handle}'),
                        size: starBox * 0.8,
                      )
                    : null,
              ),
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  // 首頁那隻寵物自己可以點（會有反應），會把點擊吃掉 → 小鎮裡交給外層
                  IgnorePointer(
                    child: TownPetSprite(species: p.petSpecies, size: pet),
                  ),
                ],
              ),
              TownNameTag(person: p),
            ],
          ),
        ),
      ),
    );
  }
}

/// 浮在地圖上的小圓鈕（連續晚數、✨ 說明、誰來看過你）。
class TownRoundButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final String tooltip;

  /// 右上角的紅點數字；0＝不畫。
  final int badge;

  const TownRoundButton({
    super.key,
    required this.child,
    required this.onTap,
    required this.tooltip,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tooltip,
    child: GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xE6161F48),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0x55FFFFFF)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: child,
          ),
          if (badge > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5A5F),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// 「今天誰來看過你」（右下角小圓鈕點開）。訊息照抄後端。
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
