import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_accent.dart';
import '../pet2d/pet_catalog.dart' show accessories;
import '../pet2d/pet_models.dart';
import '../services/account_service.dart' show kFallbackDisplayName;
import '../services/game_service.dart';
import '../widgets/home_pet.dart';

/// 衣櫃。每一件衣服、幾級解鎖、現在穿哪一件，以及**穿在寵物身上長什麼樣**。
///
/// 2026-11-18 改版（隊友交來的版面，重做在我們的寵物引擎上）：上面一隻活的寵物戴著
/// 現在選的那一件，下面是真的配件圖，**先試穿、按 Confirm 才送後端**。
///
/// 2026-11-19 第二版（使用者給參考圖，遊戲換裝畫面）：上半是使用者生成的更衣室
/// （`assets/backgrounds/closet_room.jpg`），寵物站在中間的地毯上；最上面大字是**暱稱**
/// （寵物沒有名字）、底下 Lv；左上 ‹＝不存離開、右上 ✓＝存起來（取代底部的 Confirm 長鈕）；
/// 分類是一排菱形鈕（All · 頭 · 臉 · 脖子，圖示用那一類的配件圖）；格子選中的金框＋勾、
/// 身上那件底下一個小點、沒解鎖的變暗＋鎖＋Lv。**一次只穿一件**（後端只存一件）。
///
/// ⚠️ 隊友原版直接用 `LayeredPet` 並自帶一份 `PetAppearance`（選哪隻寵物）。這裡改用
/// [HomePet]：選小狗或貓（`PetChoice`，存在手機上）、缺圖的心情退回 **bored** 不是 happy、
/// 沒有真圖的衣服疊 emoji——那三條規則只在 `HomePet` 裡一份，衣櫃不另外寫。
/// 另開一份「現在選哪隻寵物」的狀態，漂移時不會有任何錯誤訊息。
///
/// ⚠️ 「解鎖了沒」照抄後端。不在 Dart 用 `level >= unlockLevel` 判斷——
/// 後端還算上「曾經穿過就不收回」，Dart 自己算會把那件收回去。
///
/// ⚠️ 還沒解鎖的衣服點下去**不試穿、也不發請求**，直接講幾級解鎖。後端也會擋（403），
/// 但讓使用者等一趟網路才知道「還不能穿」沒有意義。
///
/// ⚠️ 試穿只改畫面，**只有 Confirm 才送後端**。所以沒按 Confirm 就離開 = 什麼都沒變；
/// 選的跟身上那件一樣時 Confirm 也不發請求。
class ClosetScreen extends StatefulWidget {
  final GameService service;

  /// 預覽那隻寵物的心情與成長階段，由首頁給（與首頁那隻同一份後端資料）。
  /// 沒給的話心情走 `HomePet` 的預設（bored），不會空掉。
  final String? mood;
  final String? growthStage;

  /// 最上面那行大字：帳號的暱稱（寵物沒有名字）。
  final String displayName;

  const ClosetScreen({
    super.key,
    required this.service,
    this.mood,
    this.growthStage,
    this.displayName = kFallbackDisplayName,
  });

  @override
  State<ClosetScreen> createState() => _ClosetScreenState();
}

/// 衣櫃分類用：後端的 item_id（`game/inventory.py`）→ 分在哪一格。
///
/// ⚠️ 這張表只管「分到哪一個分類」，不管畫在身上哪個位置——那個由
/// `pet_catalog.dart` 的錨點決定。
/// ⚠️ **沒有真圖的那兩件（top_hat、crown）也要在這裡**，否則點了分類它們會整件消失。
/// 表上沒有的新衣服只會出現在 All，不會不見。
const Map<String, AccessorySlot> kClosetSlotFor = {
  'cap': AccessorySlot.head,
  'top_hat': AccessorySlot.head,
  'crown': AccessorySlot.head,
  'beret': AccessorySlot.head,
  'glasses': AccessorySlot.face,
  'sunglasses': AccessorySlot.face,
  'scarf': AccessorySlot.neck,
  'bow': AccessorySlot.neck,
};

class _ClosetScreenState extends State<ClosetScreen> {
  GameResult<ClosetState>? _result;
  bool _busy = false;

  /// 試穿中的那一件（null = 什麼都不戴）。後端那一件在 `closet.equippedItemId`。
  String? _selected;
  AccessorySlot? _filter;

  // 跟更衣室圖最底下的顏色接起來（圖下 40% 淡成深藍）
  static const _bg = Color(0xFF0F1745);
  static const _card = Color(0xFF1B2A66);
  static const _cardOn = Color(0xFF2B3C82);
  static const _gold = Color(0xFFFFD96A);
  static const _room = 'assets/backgrounds/closet_room.jpg';

  /// 圖的長寬比（941×1672）；寵物要站在地毯上，位置照圖算。
  static const _roomAspect = 1672 / 941;

  /// 地毯中心在圖高的哪裡（量過：約 0.555）。
  static const _rugY = 0.555;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.service.fetchCloset();
    if (!mounted) return;
    setState(() {
      _result = r;
      if (r.isOk) _selected = r.value!.equippedItemId;
    });
  }

  /// 點一件衣服 = 試穿。沒解鎖的連試穿都不行（後端說了才算）。
  void _tap(ClosetItem item) {
    if (_busy) return;
    if (!item.unlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${item.name} unlocks at level ${item.unlockLevel}.'),
        ),
      );
      return;
    }
    setState(() => _selected = item.itemId);
  }

  Future<void> _confirm() async {
    if (_busy) return;
    final closet = _result?.value;
    if (closet == null) return;
    // 選的就是身上那件：不發請求，直接關掉。
    if (_selected == closet.equippedItemId) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _busy = true);
    final r = await widget.service.equip(_selected);
    if (!mounted) return;
    setState(() => _busy = false);
    // ⚠️ 脫掉時後端回的 equipped_item_id 是 null，`isOk` 會是 false
    //    （它要求 value 不為 null）。成功與否看 status。
    if (r.status != GameStatus.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.message ?? 'Could not reach the backend.')),
      );
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final imgH = w * _roomAspect;
          return Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: imgH,
                child: Image.asset(
                  _room,
                  key: const Key('closet-room'),
                  fit: BoxFit.fitWidth,
                  alignment: Alignment.topCenter,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              _buildBody(imgH),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(double imgH) {
    final r = _result;
    final top = MediaQuery.paddingOf(context).top;
    if (r == null) {
      return Stack(
        children: [
          _topBar(top),
          const Center(child: CircularProgressIndicator()),
        ],
      );
    }
    final closet = r.value;
    if (!r.isOk || closet == null) {
      return Stack(
        children: [
          _topBar(top),
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'The closet lives on the backend, and it cannot be reached right now.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ],
      );
    }

    final shown = closet.items
        .where((i) => _filter == null || kClosetSlotFor[i.itemId] == _filter)
        .toList();
    // 寵物腳踩在地毯中心；下半的面板從地毯下緣開始
    const petSize = 190.0;
    final rugY = imgH * _rugY;
    final panelTop = math.min(rugY + 40, imgH * 0.66);

    return Stack(
      children: [
        Positioned(
          top: rugY - petSize * 0.80,
          left: 0,
          right: 0,
          child: Center(
            child: SizedBox(
              key: const Key('closet-preview'),
              width: petSize,
              height: petSize,
              child: HomePet(
                mood: widget.mood,
                size: petSize,
                equippedItemId: _selected,
                accessoryEmoji: _itemOf(_selected)?.emoji,
                growthStage: widget.growthStage,
              ),
            ),
          ),
        ),
        _topBar(top),
        Positioned(
          top: top + 64,
          left: 24,
          right: 24,
          child: _header(closet),
        ),
        Positioned(
          top: panelTop,
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            children: [
              _tabs(),
              Expanded(
                child: GridView.count(
                  key: const Key('closet-grid'),
                  crossAxisCount: 3,
                  padding: EdgeInsets.fromLTRB(
                    20,
                    6,
                    20,
                    MediaQuery.paddingOf(context).bottom + 20,
                  ),
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.92,
                  children: [
                    _noneTile(closet),
                    for (final item in shown) _tile(item, closet),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 左上 ‹＝不存直接離開；右上 ✓＝存起來（沒改就直接關、不發請求）。
  Widget _topBar(double top) {
    final closet = _result?.value;
    final changed = closet != null && _selected != closet.equippedItemId;
    return Positioned(
      top: top + 8,
      left: 16,
      right: 16,
      child: Row(
        children: [
          _roundButton(
            key: const Key('closet-back'),
            icon: Icons.chevron_left_rounded,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const Expanded(
            child: Text(
              'Closet',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _roundButton(
            key: const Key('closet-confirm'),
            icon: Icons.check_rounded,
            highlight: changed,
            busy: _busy,
            onTap: closet == null || _busy ? null : _confirm,
          ),
        ],
      ),
    );
  }

  Widget _roundButton({
    required Key key,
    required IconData icon,
    required VoidCallback? onTap,
    bool highlight = false,
    bool busy = false,
  }) => Semantics(
    button: true,
    child: GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: highlight ? accentOf(context) : const Color(0xCC1B2A66),
          border: Border.all(
            color: highlight ? _gold : const Color(0x33FFFFFF),
            width: highlight ? 2 : 1,
          ),
        ),
        child: busy
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon, color: Colors.white, size: 26),
      ),
    ),
  );

  /// 大字暱稱＋Lv；試穿中多一行「還沒存」。
  Widget _header(ClosetState closet) {
    const shadow = [Shadow(color: Color(0xAA000000), blurRadius: 8)];
    return Column(
      children: [
        Text(
          widget.displayName,
          key: const Key('closet-name'),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w900,
            shadows: shadow,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xCC1B2A66),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0x55FFD96A)),
          ),
          child: Text(
            'Lv. ${closet.level}',
            style: const TextStyle(
              color: _gold,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (_selected != closet.equippedItemId) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xB30F1745),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Trying it on · not saved yet',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  ClosetItem? _itemOf(String? itemId) {
    if (itemId == null) return null;
    for (final item in _result?.value?.items ?? const <ClosetItem>[]) {
      if (item.itemId == itemId) return item;
    }
    return null;
  }

  /// 一排菱形鈕：All · 頭 · 臉 · 脖子。圖示用那一類的配件圖（讀不到退回圖示）。
  Widget _tabs() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _tab('All', null, null),
        _tab('Head', AccessorySlot.head, 'sleep_hat'),
        _tab('Face', AccessorySlot.face, 'round_glasses'),
        _tab('Neck', AccessorySlot.neck, 'night_scarf'),
      ],
    ),
  );

  Widget _tab(String label, AccessorySlot? slot, String? artId) {
    final on = _filter == slot;
    final size = on ? 58.0 : 50.0;
    final art = artId == null
        ? null
        : accessories.where((a) => a.id == artId).firstOrNull;
    final fallback = Icon(
      slot == null ? Icons.grid_view_rounded : Icons.checkroom_rounded,
      color: Colors.white,
      size: on ? 24 : 20,
    );
    return Semantics(
      button: true,
      selected: on,
      label: label,
      child: GestureDetector(
        key: Key('closet-filter-${slot?.name ?? 'all'}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _filter = slot),
        child: SizedBox(
          width: 72,
          height: 72,
          child: Center(
            child: SizedBox(
              width: size,
              height: size,
              child: Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                  decoration: BoxDecoration(
                    color: on ? accentOf(context) : _card,
                    borderRadius: BorderRadius.circular(on ? 14 : 12),
                    border: Border.all(
                      color: on ? _gold : const Color(0x33FFFFFF),
                      width: on ? 2 : 1,
                    ),
                    boxShadow: on
                        ? const [
                            BoxShadow(color: Color(0x667B61FF), blurRadius: 14),
                          ]
                        : null,
                  ),
                  child: Transform.rotate(
                    angle: -math.pi / 4,
                    child: Padding(
                      padding: EdgeInsets.all(on ? 6 : 5),
                      child: art == null
                          ? fallback
                          : Image.asset(
                              art.assetPath,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => fallback,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 「什麼都不戴」。⚠️ 不分分類一律放第一格——它不屬於任何一個插槽，
  /// 跟著分類藏起來的話就沒有辦法脫掉衣服。
  Widget _noneTile(ClosetState closet) => _frame(
    tileKey: const Key('closet-none'),
    selected: _selected == null,
    wornNow: closet.equippedItemId == null,
    onTap: () {
      if (!_busy) setState(() => _selected = null);
    },
    art: const Center(
      child: Icon(Icons.block_rounded, color: Colors.white38, size: 34),
    ),
    name: 'None',
  );

  Widget _tile(ClosetItem item, ClosetState closet) {
    final art = layeredAccessoryFor(item.itemId);
    // 真圖優先。⚠️ errorBuilder 不能省：圖讀不到時 Image.asset 會丟例外，退回 emoji。
    final emoji = Center(
      child: Text(item.emoji, style: const TextStyle(fontSize: 34)),
    );
    return _frame(
      tileKey: Key('closet-${item.itemId}'),
      selected: _selected == item.itemId,
      wornNow: closet.equippedItemId == item.itemId,
      locked: item.unlocked ? null : item.unlockLevel,
      onTap: () => _tap(item),
      art: art == null
          ? emoji
          : Image.asset(
              art.assetPath,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => emoji,
            ),
      name: item.name,
    );
  }

  /// 一格：深色圓角方塊、配件圖、名字。
  /// 選中＝金框＋右上金色勾；身上那件＝名字底下一個小點；沒解鎖＝變暗＋鎖＋Lv。
  Widget _frame({
    required Key tileKey,
    required bool selected,
    required bool wornNow,
    required VoidCallback onTap,
    required Widget art,
    required String name,
    int? locked,
  }) {
    final lockedNow = locked != null;
    return GestureDetector(
      key: tileKey,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: selected
                      ? const [_cardOn, Color(0xFF1F2E6E)]
                      : const [_card, Color(0xFF131F52)],
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: selected ? _gold : const Color(0x22FFFFFF),
                  width: selected ? 3 : 1,
                ),
                boxShadow: selected
                    ? const [BoxShadow(color: Color(0x55FFD96A), blurRadius: 14)]
                    : const [BoxShadow(color: Color(0x55000000), blurRadius: 8)],
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Opacity(opacity: lockedNow ? 0.3 : 1, child: art),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: lockedNow ? Colors.white38 : Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  // 身上現在穿的那件（還沒換之前）：一個小點
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: wornNow ? _gold : Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (lockedNow)
            Positioned.fill(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_rounded, color: Colors.white70, size: 22),
                    const SizedBox(height: 2),
                    Text(
                      'Lv $locked',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (selected)
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _gold,
                  border: Border.all(color: _bg, width: 2),
                ),
                child: const Icon(Icons.check_rounded, size: 15, color: _bg),
              ),
            ),
        ],
      ),
    );
  }
}
