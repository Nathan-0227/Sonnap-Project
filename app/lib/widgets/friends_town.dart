import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/friends_service.dart';
import 'friend_night_card.dart'
    show friendCheckIn, friendStagesStrip, openFriendNight;
import 'last_night_art.dart';
import 'steps_sheet.dart' show StepsArc, stepsFraction;
import 'home_pet.dart';
import 'report_tiles.dart';
import '../theme/report_style.dart';
import 'streak_card.dart' show StreakWeekRow, speciesOf;

/// 好友小鎮（2026-11-17 使用者定，照 Finch 的做法：朋友之間只看到寵物）。
///
/// 2026-11-18 改成**整個畫面都是小鎮、上下左右都能滑**（使用者給 Finch 的截圖）：一張從斜上方看的
/// 卡通的夜晚村莊（使用者生成的 `town_map.jpg`，有河、橋、池塘），十間房子，正中間有柵欄那間是你家，
/// 朋友照加好友的先後住進離你家近的房子，寵物站在房子右邊那塊亮草地上。**昨晚準時放下手機、而且有分享 On time 的人
/// 頭頂一圈會閃的閃光**（腳下的金光 11-18 拿掉：那塊草地本來就亮，看不出來）；其他人一律不亮——晚了、沒資料、沒分享看起來**完全一樣**，
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

/// 頭頂一圈閃光（2026-11-18 使用者給 Finch 的截圖：一顆小星星不夠明顯）。
/// 三顆白色四角閃光圍著頭（左、上、右），各自錯開時間一閃一閃，外面一圈白色光暈。
/// 寵物本身另有 [TownOutlineGlow] 的金邊。
/// 系統開「減少動態效果」時靜止。[size]＝整圈的寬度。
class TownStar extends StatefulWidget {
  final double size;
  const TownStar({super.key, this.size = 60});

  @override
  State<TownStar> createState() => _TownStarState();
}

class _TownStarState extends State<TownStar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c
        ..stop()
        ..value = 0.25;
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
  Widget build(BuildContext context) {
    final w = widget.size;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Opacity(
        opacity: 0.8 + 0.2 * math.sin(2 * math.pi * _c.value),
        child: CustomPaint(
          size: Size(w, w * 0.55),
          painter: _SparklePainter(_c.value),
        ),
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  final double t;
  _SparklePainter(this.t);

  /// (x, y, 半徑, 錯開的相位)，以整圈的寬高為比例。
  static const _sparkles = [
    (0.10, 0.80, 0.14, 0.0),
    (0.50, 0.20, 0.19, 0.33),
    (0.90, 0.78, 0.13, 0.66),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final (fx, fy, fr, phase) in _sparkles) {
      final c = Offset(fx * size.width, fy * size.height);
      final pulse = 0.5 + 0.5 * math.sin(2 * math.pi * (t + phase));
      final r = fr * size.width * (0.75 + 0.25 * pulse);
      // 白色光暈（2026-11-19：金色在夜景裡跟暖色燈光混在一起，看不出來）
      canvas.drawCircle(
        c,
        r * 1.3,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.8 * (0.6 + 0.4 * pulse)),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: r * 1.3)),
      );
      final path = Path()
        ..moveTo(c.dx, c.dy - r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
        ..close();
      canvas.drawPath(path, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.t != t;
}

/// 寵物整隻描一圈金色外光（2026-11-19 使用者從五種做法裡選的）。
/// 同一隻寵物染成金色、模糊兩層，墊在寵物後面；地圖縮放時跟著一起縮。
class TownOutlineGlow extends StatelessWidget {
  final String? species;
  final double size;
  const TownOutlineGlow({super.key, required this.species, required this.size});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Stack(
      children: [
        for (final sigma in [size * 0.12, size * 0.05])
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Color(0xFFFFE08A),
                BlendMode.srcIn,
              ),
              child: TownPetSprite(species: species, size: size),
            ),
          ),
      ],
    ),
  );
}

/// 名牌：沒有框、只有字，像地圖上的地名（2026-11-18 使用者：深色膠囊框太突兀）。
/// 白字加一圈柔和的深色陰影才讀得到；你自己用淡紫色。
/// 2026-11-18 使用者定：小鎮的名牌不寫 demo（點開的小卡、Feed、排行榜仍然標 Demo）。
class TownNameTag extends StatelessWidget {
  final TownPerson person;
  const TownNameTag({super.key, required this.person});

  static const _shadow = [
    Shadow(color: Color(0xCC0B1024), blurRadius: 4),
    Shadow(color: Color(0x990B1024), blurRadius: 8),
  ];

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: person.mine
              ? 'You'
              : person.displayName.replaceAll(' (demo)', ''),
          style: TextStyle(
            color: person.mine ? const Color(0xFFE2D8FF) : Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            shadows: _shadow,
          ),
        ),
      ],
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: TextAlign.center,
  );
}

/// 整個畫面的小鎮地圖：上下左右滑、兩指縮放，一開始讓你家出現在看得到的那塊正中間。
/// 縮放（2026-11-19 使用者定）：最小＝整張地圖的寬剛好塞進螢幕、最大 2.5 倍；
/// 名牌與寵物跟著縮；點兩下空地回到原本大小、你家回到中間。
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
  State<TownMap> createState() => TownMapState();
}

/// 外面（好友頁）要拿到它：點開資訊面板時把那個人移到面板上面那塊的正中間。
class TownMapState extends State<TownMap> with SingleTickerProviderStateMixin {
  TransformationController? _controller;

  /// 一打開的位置，點兩下回到這裡。
  Matrix4? _home;
  late final AnimationController _back;
  Animation<Matrix4>? _backAnim;

  @override
  void initState() {
    super.initState();
    _back = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..addListener(_onBack);
  }

  static const maxScale = 2.5;

  void _onBack() {
    final a = _backAnim;
    if (a != null) _controller?.value = a.value;
  }

  void _goHome() {
    final home = _home;
    if (home != null) _animateTo(home);
  }

  void _animateTo(Matrix4 target) {
    final c = _controller;
    if (c == null) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      c.value = target.clone();
      return;
    }
    _backAnim = Matrix4Tween(
      begin: c.value.clone(),
      end: target,
    ).animate(CurvedAnimation(parent: _back, curve: Curves.easeOutCubic));
    _back
      ..reset()
      ..forward();
  }

  /// 每個人寵物身體的中心（地圖座標），上一次 build 時記下來。
  final Map<String, Offset> _spotOf = {};
  Size? _view;
  double _mapW = 0, _boardH = 0;

  /// 把 [handle] 那隻寵物移到畫面寬度正中間、高度 [midY] 的地方（縮放倍數不變；
  /// 到了地圖邊緣就停在邊緣，不露出空白）。2026-11-19：點開資訊面板時，面板蓋住下半部。
  void focusOn(String handle, double midY) {
    final at = _spotOf[handle], view = _view, c = _controller;
    if (at == null || view == null || c == null) return;
    final s = c.value.getMaxScaleOnAxis();
    final tx = (view.width / 2 - at.dx * s).clamp(view.width - _mapW * s, 0.0);
    final ty = (midY - at.dy * s).clamp(view.height - _boardH * s, 0.0);
    _animateTo(Matrix4.diagonal3Values(s, s, 1)..setTranslationRaw(tx, ty, 0));
  }

  @override
  void dispose() {
    _back.dispose();
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
        // 縮到最小時地圖的寬＝畫面寬。地圖比手機矮胖，上下不夠的那段補一圈模糊的夜色，
        // 不然縮小時會露出一塊空白
        final minScale = view.width / mapW;
        final boardH = math.max(mapH, view.height / minScale);
        final oy = (boardH - mapH) / 2;
        _view = view;
        _mapW = mapW;
        _boardH = boardH;
        final me = kTownLots[0];
        if (_controller == null) {
          final c = widget.covered;
          final seenMidY = c.top + (view.height - c.top - c.bottom) / 2;
          final dx = (view.width / 2 - me.dx * mapW).clamp(
            view.width - mapW,
            0.0,
          );
          final dy = (seenMidY - (oy + me.dy * mapH)).clamp(
            view.height - boardH,
            0.0,
          );
          _home = Matrix4.translationValues(dx, dy, 0);
          _controller = TransformationController(_home!.clone());
        }
        final people = [
          ?widget.town.me,
          ...widget.town.friends.take(kTownMaxFriends),
        ];
        Widget map(BoxFit fit) => Image.asset(
          _mapImage,
          fit: fit,
          errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF101A3F)),
        );
        return InteractiveViewer(
          key: const Key('town-map'),
          transformationController: _controller,
          constrained: false,
          minScale: minScale,
          maxScale: maxScale,
          boundaryMargin: EdgeInsets.zero,
          child: SizedBox(
            width: mapW,
            height: boardH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 空地：點兩下回家。寵物與 Invite 疊在上面，點它們不會走到這裡
                Positioned.fill(
                  child: GestureDetector(
                    key: const Key('town-board'),
                    behavior: HitTestBehavior.opaque,
                    onDoubleTap: _goHome,
                    child: Stack(
                      children: [
                        if (oy > 0) ...[
                          Positioned.fill(
                            child: ImageFiltered(
                              imageFilter: ui.ImageFilter.blur(
                                sigmaX: 18,
                                sigmaY: 18,
                              ),
                              child: map(BoxFit.cover),
                            ),
                          ),
                          const Positioned.fill(
                            child: ColoredBox(color: Color(0x99081326)),
                          ),
                        ],
                        Positioned(
                          left: 0,
                          top: oy,
                          width: mapW,
                          height: mapH,
                          child: oy > 0
                              ? ShaderMask(
                                  blendMode: BlendMode.dstIn,
                                  shaderCallback: (r) => const LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0x00000000),
                                      Color(0xFF000000),
                                      Color(0xFF000000),
                                      Color(0x00000000),
                                    ],
                                    stops: [0, 0.04, 0.96, 1],
                                  ).createShader(r),
                                  child: map(BoxFit.cover),
                                )
                              : map(BoxFit.cover),
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.onAddFriend != null &&
                    people.length < kTownLots.length)
                  _inviteSpot(
                    kTownLots[people.length].dx * mapW,
                    oy + kTownLots[people.length].dy * mapH,
                    mapW,
                  ),
                for (final (i, p) in people.indexed)
                  _townie(
                    p,
                    kTownLots[i].dx * mapW,
                    oy + kTownLots[i].dy * mapH,
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
                  border: Border.all(
                    color: const Color(0xAAFFFFFF),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: d * 0.6,
                ),
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
    _spotOf[p.handle] = Offset(x, y - pet * 0.4);
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
              SizedBox(height: starBox),
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  if (p.glow)
                    TownOutlineGlow(
                      key: Key('town-outline-${p.handle}'),
                      species: p.petSpecies,
                      size: pet,
                    ),
                  // 首頁那隻寵物自己可以點（會有反應），會把點擊吃掉 → 小鎮裡交給外層
                  IgnorePointer(
                    child: TownPetSprite(species: p.petSpecies, size: pet),
                  ),
                  // 閃光圍著頭：從頭頂上方一點開始，兩側往下到耳朵旁；畫在寵物前面才不會被擋住
                  if (p.glow)
                    Positioned(
                      top: -pet * 0.32,
                      child: TownStar(
                        key: Key('town-glow-${p.handle}'),
                        size: pet * 1.35,
                      ),
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

/// 資訊面板一打開佔螢幕多高（2026-11-19 使用者定，照參考圖：上面還看得到地圖）。
const kTownSheetSize = 0.6;

/// 點小鎮裡的人 → 下半部滑出資訊面板（2026-11-19 使用者定，照參考圖）：
/// 名字＋寵物 → 這週每晚準不準時 → 連續 3 晚以上一行 🔥 → 昨晚他有分享的格子（最多 6 格）
/// → See last night ›；最下面固定是四個拜訪按鈕。
/// 點自己：同一個面板（朋友看到的你），最下面換成「今天誰來看過你」。
///
/// [onVisit] 回傳 null＝送出成功；否則是要顯示的那句話（後端的原文）。點自己時不用給。
Future<void> showTownFriendSheet(
  BuildContext context, {
  required TownPerson person,
  required List<(String, String)> kinds,
  Future<String?> Function(String kind)? onVisit,
  FriendSummary? summary,
  List<TownVisit> visits = const [],
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x22000000),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: kTownSheetSize,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      builder: (context, scroll) => _TownFriendSheet(
        person: person,
        kinds: kinds,
        onVisit: onVisit,
        summary: summary,
        visits: visits,
        scroll: scroll,
      ),
    ),
  );
}

class _TownFriendSheet extends StatefulWidget {
  final TownPerson person;
  final List<(String, String)> kinds;
  final Future<String?> Function(String kind)? onVisit;
  final FriendSummary? summary;
  final List<TownVisit> visits;
  final ScrollController scroll;
  const _TownFriendSheet({
    required this.person,
    required this.kinds,
    required this.onVisit,
    required this.summary,
    required this.visits,
    required this.scroll,
  });

  @override
  State<_TownFriendSheet> createState() => _TownFriendSheetState();
}

class _TownFriendSheetState extends State<_TownFriendSheet> {
  late String? _sent = widget.person.sent;
  bool _busy = false;
  String? _error;

  Future<void> _send(String kind) async {
    final onVisit = widget.onVisit;
    if (onVisit == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await onVisit(kind);
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

  static const _dim = Color(0x99FFFFFF);

  @override
  Widget build(BuildContext context) {
    final p = widget.person;
    final week = widget.summary?.streakWeek;
    final streak = widget.summary?.currentStreak;
    final best = widget.summary?.bestStreak;
    final tiles = friendCheckIn(p.card?.items ?? const {});
    // 背景與字型照早晨報告（2026-11-19 使用者：原本的平塗深藍不好看，格子參考 sleep report）
    return Container(
      key: const Key('town-sheet'),
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 16)],
      ),
      child: ReportFont(
        child: Stack(
          children: [
            const Positioned.fill(child: ReportBackground()),
            Column(
        children: [
          Expanded(
            child: ListView(
              controller: widget.scroll,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
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
                const SizedBox(height: 12),
                _header(p),
                if (week != null && week.length == 7) ...[
                  const SizedBox(height: 16),
                  StreakWeekRow(key: const Key('town-sheet-week'), week: week),
                ],
                if (streak != null && streak >= 3) ...[
                  const SizedBox(height: 14),
                  _streakBanner(streak, best),
                ],
                const SizedBox(height: 20),
                const Text(
                  'Last night',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                if (tiles.isEmpty)
                  const Text(
                    'Nothing to show for last night.',
                    key: Key('town-sheet-empty'),
                    style: TextStyle(color: _dim, fontSize: 14),
                  )
                else
                  // 攝影機那格（光柱）跟早晨報告一樣獨佔最後一整列：放半格太窄
                  reportTileGrid([
                    for (final t in tiles)
                      if (t.$1 != 'camera_moves')
                        townCheckInTile(t, p.card?.items ?? const {}),
                  ]),
                for (final t in tiles)
                  if (t.$1 == 'camera_moves') ...[
                    const SizedBox(height: 12),
                    townCheckInTile(t, p.card?.items ?? const {}),
                  ],
                if (p.card != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const Key('town-see-night'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.only(top: 8),
                        foregroundColor: const Color(0xFFB9A6FF),
                      ),
                      onPressed: () {
                        final card = p.card!;
                        Navigator.of(context).pop();
                        openFriendNight(context, card);
                      },
                      child: const Text(
                        'See last night ›',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 最下面固定：朋友是拜訪按鈕，自己是今天誰來看過你
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
              ),
              child: p.mine ? _visitors() : _visitButtons(),
            ),
          ),
        ],
      ),
          ],
        ),
      ),
    );
  }

  Widget _streakBanner(int streak, int? best) => Container(
    key: const Key('town-sheet-streak'),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0x14FFFFFF),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.local_fire_department_rounded,
          color: Color(0xFFFF8A5C),
          size: 26,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$streak nights in a row',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                if (best != null)
                  TextSpan(
                    text: '  ·  Best $best',
                    style: const TextStyle(color: _dim, fontSize: 13),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _header(TownPerson p) => Row(
    children: [
      SizedBox(
        width: 64,
        height: 64,
        // 心情只有他有分享才有；沒有就是 null → HomePet 畫 bored（不畫 happy）
        child: HomePet(
          mood: p.petMood,
          species: speciesOf(p.petSpecies),
          size: 58,
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
                    p.mine ? 'You' : p.displayName.replaceAll(' (demo)', ''),
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
                      border: Border.all(color: const Color(0x66FFFFFF)),
                    ),
                    child: const Text(
                      'Demo',
                      style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 11),
                    ),
                  ),
                ],
              ],
            ),
            if (p.mine)
              const Text(
                'What friends see',
                style: TextStyle(color: _dim, fontSize: 13),
              ),
            if (p.glow) ...[
              const SizedBox(height: 2),
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
  );

  Widget _visitButtons() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (i, (key, label)) in widget.kinds.indexed)
            _chip(key, label, primary: i == 0),
        ],
      ),
      if (_sent != null) ...[
        const SizedBox(height: 8),
        const Text(
          'You can visit again tomorrow.',
          style: TextStyle(color: _dim, fontSize: 13),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(
          _error!,
          key: const Key('town-sheet-error'),
          style: const TextStyle(color: Color(0xFFFFB4A8), fontSize: 13),
        ),
      ],
    ],
  );

  Widget _visitors() => Column(
    key: const Key('town-sheet-visitors'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Stopped by today',
        style: TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 6),
      if (widget.visits.isEmpty)
        const Text(
          'No one yet today.',
          style: TextStyle(color: _dim, fontSize: 14),
        )
      else
        for (final v in widget.visits)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              v.message,
              style: const TextStyle(color: Color(0xDDFFFFFF), fontSize: 14),
            ),
          ),
    ],
  );

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

/// 面板裡的一格：照早晨報告的格子（2026-11-19 使用者定）——每一項自己的顏色、
/// 左上圖示＋名稱、大數字，底下的小圖跟報告同一套。**小圖只畫他有分享的資料**：
/// - Total sleep：他有分享 Sleep stages 才畫那條階梯（睡眠目標只存在他手機上，後端沒有，
///   所以不畫報告那條「睡了多久÷目標」的極光）
/// - Phone down：他也分享了目標時間才畫半圓鐘（不然「目標」那一點是編的）
/// - Score、Efficiency：圓環
/// - Steps：圓弧＝步數÷那天 Garmin 的目標，超過就滿、不變色，只寫 Goal
/// - Sleeping HR：整晚那條慢線（同一個開關，後端本來就給）
/// - Movement：他有分享 Movement through the night 才畫光柱；時間軸要知道幾點睡著，
///   他選了「只寫準時與否」（沒有時刻）就不畫，不然底下的鐘點是編的
/// 不判斷好壞、不變色。
Widget townCheckInTile(
  (String, IconData, String, String) tile,
  Map<String, dynamic> items,
) {
  final (key, icon, value, label) = tile;
  final (title, color, unit) = switch (key) {
    'sleep_duration' => ('Total sleep', const Color(0xFFB9A6FF), null),
    'phone_down_time' => ('Phone down', const Color(0xFF6FE3D0), null),
    'score' => ('Score', const Color(0xFFFFD27A), null),
    'camera_moves' => ('Movement', const Color(0xFFFFD96A), 'moves / hour'),
    'steps' => ('Steps', const Color(0xFFFFB37A), null),
    'sleeping_hr' => ('Sleeping HR', const Color(0xFF8C9BFF), 'bpm'),
    'awake' => ('Awake', const Color(0xFFFFC27A), label),
    'efficiency' => ('Efficiency', const Color(0xFF7EC8FF), null),
    'time_in_bed' => ('Time in bed', const Color(0xFF8FA8FF), null),
    'fell_asleep' => ('Fell asleep', const Color(0xFFB9A6FF), 'to fall asleep'),
    'stress' => ('Stress', const Color(0xFFA996FF), 'high stress'),
    'resting_hr' => ('Resting HR', const Color(0xFFFF8AB8), 'bpm'),
    'active_time' => ('Active', const Color(0xFFFFD96A), null),
    'calories' => ('Calories', const Color(0xFFFF8A6B), 'active kcal'),
    _ => (
      label.isEmpty ? label : label[0].toUpperCase() + label.substring(1),
      const Color(0xFFC9B8FF),
      null,
    ),
  };
  Widget? graphic;
  double? n(dynamic v) => v is num ? v.toDouble() : null;
  int? nightMinute(dynamic v) {
    if (v is! String) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(v);
    if (m == null) return null;
    return ((int.parse(m[1]!) * 60 + int.parse(m[2]!)) - 18 * 60) % 1440;
  }

  Map<String, dynamic> m(String k) =>
      items[k] is Map ? (items[k] as Map).cast<String, dynamic>() : const {};
  List<(double, double)> offsets(dynamic pts) => [
    for (final p in (pts as List?) ?? const [])
      if (p is Map && n(p['m']) != null && n(p['v']) != null)
        (n(p['m'])!, n(p['v'])!),
  ];
  var graphicHeight = 52.0;
  switch (key) {
    case 'sleep_duration':
      graphic = friendStagesStrip(items, height: 40);
      graphicHeight = 40;
    case 'sleeping_hr':
      final pts = offsets(m('sleeping_hr')['curve']);
      if (pts.length >= 2) {
        final last = pts.last.$1;
        graphic = paintBox(
          SleepHrWavePainter([for (final (x, v) in pts) (last > 0 ? x / last : 0, v)], color),
        );
        graphicHeight = 64;
      }
    case 'camera_moves':
      final pts = offsets(m('camera_timeline')['points']);
      final start = m('stages')['start'];
      final hm = start is String
          ? RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(start)
          : null;
      if (pts.isNotEmpty && hm != null) {
        final t0 = DateTime(2000, 1, 1, int.parse(hm[1]!), int.parse(hm[2]!));
        graphic = paintBox(
          CameraBarsPainter([
            for (final (min, v) in pts)
              (t0.add(Duration(seconds: (min * 60).round())), v),
          ]),
        );
        graphicHeight = 110;
      }
    case 'steps':
      final st = n(m('steps')['steps']);
      if (st != null) {
        graphic = StepsArc(
          steps: st.round(),
          fraction: stepsFraction(st.round(), n(m('steps')['goal'])?.round()),
          color: color,
        );
        graphicHeight = 118;
      }
    case 'score':
      final sc = n((items['score'] as Map?)?['score']);
      if (sc != null) graphic = paintBox(RingPainter(sc, color));
    case 'efficiency':
      final e = n((items['efficiency'] as Map?)?['value']);
      if (e != null) graphic = paintBox(RingPainter(e, color));
    case 'phone_down_time':
      final actual = nightMinute(items['phone_down_time']);
      final target = nightMinute(items['target_bedtime']);
      if (actual != null && target != null) {
        graphic = paintBox(
          ClockArcPainter(target.toDouble(), actual.toDouble(), color),
        );
      }
  }
  return ReportTile(
    key: Key('town-sheet-tile-$key'),
    icon: icon,
    color: color,
    title: title,
    // 步數的數字已經在圓弧中間，大字不再寫一次（同早晨報告）
    value: key == 'steps' && graphic != null ? null : value,
    graphic: graphic,
    graphicHeight: graphicHeight,
    lines: [
      if (unit != null) Text(unit),
      if (key == 'steps' && n(m('steps')['goal']) != null)
        Text('Goal ${_comma(n(m('steps')['goal'])!.round())}'),
    ],
  );
}

String _comma(int v) => v.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]},',
);
