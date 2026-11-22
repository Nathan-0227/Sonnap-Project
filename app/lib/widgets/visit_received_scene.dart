// 收禮的場景（2026-11-22 使用者選：點愛心先播）。
//
// 點小鎮右下的愛心，今天有還沒看過的拜訪時：先進客廳（送禮頁同一個房間），
// 你的寵物坐左邊坐墊、送的人的寵物從右邊走進來坐上右邊坐墊，泡泡是他送的那句話（後端原文）。
// 好幾則就點一下換下一位；最後一則按 See all 接原本的 Stopped by today 清單（Send back 在那裡）。
// 看過的不再播（「看過」照舊在打開時就記，`visits_seen.dart`）。
//
// 規則同送禮頁：不評判、不催促；寵物沒分享心情時畫 bored；減少動態效果時不走、不跳。
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../screens/plan_screen.dart' show petJumpPose;
import '../services/friends_service.dart';
import 'home_pet.dart';
import 'streak_card.dart' show speciesOf;
import 'visit_gift_sheet.dart';

/// 播完：true＝按了 See all（接著開清單），false／null＝直接關掉。
Future<bool?> showVisitReceivedScene(
  BuildContext context, {
  required List<TownVisit> visits,
  TownPerson? me,
  Map<String, TownPerson> friends = const {},
  List<(String, String)> kinds = const [],
}) {
  return Navigator.of(context).push<bool>(PageRouteBuilder<bool>(
    opaque: false,
    barrierColor: const Color(0x99000000),
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    // ⚠️ 另外一頁要自己包 Material，不然字是等寬字＋黃色雙底線
    pageBuilder: (context, _, _) => Material(
      type: MaterialType.transparency,
      child: VisitReceivedScene(
        visits: visits,
        me: me,
        friends: friends,
        kinds: kinds,
      ),
    ),
    transitionsBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  ));
}

class VisitReceivedScene extends StatefulWidget {
  final List<TownVisit> visits;
  final TownPerson? me;

  /// 朋友（邀請碼 → 人），拿他的心情與衣服；找不到就只畫他選的狗／貓。
  final Map<String, TownPerson> friends;
  final List<(String, String)> kinds;

  const VisitReceivedScene({
    super.key,
    required this.visits,
    this.me,
    this.friends = const {},
    this.kinds = const [],
  });

  @override
  State<VisitReceivedScene> createState() => _VisitReceivedSceneState();
}

class _VisitReceivedSceneState extends State<VisitReceivedScene> with SingleTickerProviderStateMixin {
  int _index = 0;

  /// 送的人走進來（0→1）：前 60% 走、後面跳上坐墊。
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_enter.status == AnimationStatus.dismissed) {
      if (_still) {
        _enter.value = 1;
      } else {
        _enter.forward();
      }
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  bool get _last => _index >= widget.visits.length - 1;

  void _next() {
    if (_last) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _index++);
    if (_still) {
      _enter.value = 1;
    } else {
      _enter.forward(from: 0);
    }
  }

  String _emojiOf(String kind) => splitVisitLabel(
        widget.kinds.where((k) => k.$1 == kind).firstOrNull?.$2 ?? '',
      ).$1;

  @override
  Widget build(BuildContext context) {
    final v = widget.visits[_index];
    final friend = v.handle == null ? null : widget.friends[v.handle];
    final pad = MediaQuery.paddingOf(context);
    return GestureDetector(
      key: const Key('visit-received-scene'),
      behavior: HitTestBehavior.opaque,
      onTap: _next,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF5A3A6E), kVisitPanel],
          ),
        ),
        child: LayoutBuilder(builder: (context, box) {
          final size = box.biggest;
          final pet = visitPetSize(size);
          final mine = visitSeatAt(size, kVisitSeatMine);
          final theirs = visitSeatAt(size, kVisitSeatFriend);
          const feet = 0.12;
          Rect seat(Offset s) => Rect.fromLTWH(s.dx - pet / 2, s.dy - pet * (1 - feet), pet, pet);
          return AnimatedBuilder(
            animation: _enter,
            builder: (context, _) {
              final t = _enter.value;
              final walk = Curves.easeOut.transform(_clamp01(t / .6));
              final hop = petJumpPose(_clamp01((t - .55) / .45));
              final bubble = Curves.easeOutBack.transform(_clamp01((t - .7) / .3));
              final r = seat(theirs);
              final walkX = (1 - walk) * (size.width - r.left + 20);
              return Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      kVisitGiftBackground,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                  // 你的寵物（左邊坐墊）
                  Positioned.fromRect(
                    rect: seat(mine),
                    child: HomePet(
                      mood: widget.me?.petMood,
                      species: speciesOf(widget.me?.petSpecies),
                      size: pet,
                      animate: false,
                      equippedItemId: widget.me?.equippedItemId,
                    ),
                  ),
                  // 送的人的寵物：從右邊走進來、跳上右邊坐墊
                  Positioned.fromRect(
                    rect: r,
                    child: Transform.translate(
                      offset: Offset(walkX, -pet * .35 * hop.lift - (walk < 1 ? math.sin(walk * 18) .abs() * 4 : 0)),
                      child: Transform(
                        alignment: Alignment.bottomCenter,
                        transform: Matrix4.diagonal3Values(hop.scaleX, hop.scaleY, 1),
                        child: HomePet(
                          key: const Key('visit-received-pet'),
                          // 心情他有分享才有；沒有 → HomePet 畫 bored
                          mood: friend?.petMood,
                          species: speciesOf(friend?.petSpecies ?? v.petSpecies),
                          size: pet,
                          animate: false,
                          equippedItemId: friend?.equippedItemId,
                        ),
                      ),
                    ),
                  ),
                  // 泡泡：他送的那句（後端原文）＋那一種的圖示，尾巴指向他的寵物
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: size.height - (r.top + pet * .06),
                    child: Opacity(
                      opacity: _clamp01(bubble),
                      child: Transform.scale(
                        scale: .6 + .4 * bubble,
                        alignment: Alignment.bottomRight,
                        child: _speech(v, tailX: ((theirs.dx - 20) / (size.width - 40) * 2 - 1).clamp(-.9, .9)),
                      ),
                    ),
                  ),
                  // 上面：關掉、第幾位
                  Positioned(
                    left: 12,
                    right: 16,
                    top: pad.top + 8,
                    child: Row(
                      children: [
                        IconButton(
                          key: const Key('visit-received-close'),
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).pop(false),
                          icon: const Icon(Icons.close_rounded, color: Colors.white),
                        ),
                        const Spacer(),
                        if (widget.visits.length > 1)
                          Text(
                            '${_index + 1} / ${widget.visits.length}',
                            key: const Key('visit-received-count'),
                            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
                          ),
                      ],
                    ),
                  ),
                  // 下面：標題＋下一位／See all
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: EdgeInsets.fromLTRB(24, 22, 24, 20 + pad.bottom),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            kVisitPanel.withValues(alpha: 0),
                            kVisitPanel.withValues(alpha: kVisitPanelAlpha),
                            kVisitPanel.withValues(alpha: .95),
                          ],
                          stops: const [0, .3, 1],
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${v.displayName.replaceAll(' (demo)', '')} stopped by today',
                            key: const Key('visit-received-title'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton(
                              key: const Key('visit-received-next'),
                              onPressed: _next,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF7657FF),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                              ),
                              child: Text(
                                _last ? 'See all' : 'Next',
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        }),
      ),
    );
  }

  Widget _speech(TownVisit v, {required double tailX}) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            key: const Key('visit-received-bubble'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(dimension: 40, child: VisitIcon(kind: v.kind, emoji: _emojiOf(v.kind))),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    v.message,
                    style: const TextStyle(color: Color(0xFF2A1F3D), fontSize: 17, fontWeight: FontWeight.w700, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment(tailX, 0),
            child: CustomPaint(size: const Size(22, 12), painter: _Tail()),
          ),
        ],
      );
}

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

class _Tail extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
