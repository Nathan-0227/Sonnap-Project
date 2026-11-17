import 'package:flutter/material.dart';

import '../pet2d/pet_models.dart';
import '../services/game_service.dart';
import '../widgets/home_pet.dart';

/// 衣櫃。每一件衣服、幾級解鎖、現在穿哪一件，以及**穿在寵物身上長什麼樣**。
///
/// 2026-11-18 改版（隊友交來的版面，重做在我們的寵物引擎上）：上面一隻活的寵物戴著
/// 現在選的那一件，下面是真的配件圖，**先試穿、按 Confirm 才送後端**。
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

  const ClosetScreen({
    super.key,
    required this.service,
    this.mood,
    this.growthStage,
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
  'glasses': AccessorySlot.face,
  'scarf': AccessorySlot.neck,
  'bow': AccessorySlot.neck,
};

class _ClosetScreenState extends State<ClosetScreen> {
  GameResult<ClosetState>? _result;
  bool _busy = false;

  /// 試穿中的那一件（null = 什麼都不戴）。後端那一件在 `closet.equippedItemId`。
  String? _selected;
  AccessorySlot? _filter;

  static const _bg = Color(0xFF081326);
  static const _card = Color(0xFF10265A);
  static const _cardOn = Color(0xFF233A73);
  static const _gold = Color(0xFFFFD96A);

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
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text('Closet'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final r = _result;
    if (r == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF7657FF)),
      );
    }
    final closet = r.value;
    if (!r.isOk || closet == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'The closet lives on the backend, and it cannot be reached right now.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    final shown = closet.items
        .where((i) => _filter == null || kClosetSlotFor[i.itemId] == _filter)
        .toList();

    return Column(
      children: [
        _preview(closet),
        _chips(),
        Expanded(
          child: GridView.count(
            key: const Key('closet-grid'),
            crossAxisCount: 3,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.85,
            children: [_noneTile(), for (final item in shown) _tile(item)],
          ),
        ),
        _confirmButton(closet),
      ],
    );
  }

  /// 上面那隻活的寵物，戴著**現在試穿的**那一件。
  Widget _preview(ClosetState closet) {
    final trying = _itemOf(_selected);
    return Container(
      key: const Key('closet-preview'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          HomePet(
            mood: widget.mood,
            size: 168,
            equippedItemId: _selected,
            accessoryEmoji: trying?.emoji,
            growthStage: widget.growthStage,
          ),
          Text(
            trying == null ? 'Nothing on' : trying.name,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            _selected == closet.equippedItemId
                ? 'Level ${closet.level}'
                : 'Trying it on · not saved yet',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  ClosetItem? _itemOf(String? itemId) {
    if (itemId == null) return null;
    for (final item in _result?.value?.items ?? const <ClosetItem>[]) {
      if (item.itemId == itemId) return item;
    }
    return null;
  }

  Widget _chips() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        _chip('All', null),
        _chip('Head', AccessorySlot.head),
        _chip('Face', AccessorySlot.face),
        _chip('Neck', AccessorySlot.neck),
      ],
    ),
  );

  Widget _chip(String label, AccessorySlot? slot) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      key: Key('closet-filter-${slot?.name ?? 'all'}'),
      label: Text(label),
      selected: _filter == slot,
      onSelected: (_) => setState(() => _filter = slot),
      selectedColor: const Color(0xFF7657FF),
      backgroundColor: _card,
      labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
      side: BorderSide.none,
      showCheckmark: false,
    ),
  );

  /// 「什麼都不戴」。⚠️ 不分分類一律放第一格——它不屬於任何一個插槽，
  /// 跟著分類藏起來的話就沒有辦法脫掉衣服。
  Widget _noneTile() {
    final selected = _selected == null;
    return _frame(
      tileKey: const Key('closet-none'),
      selected: selected,
      onTap: () {
        if (!_busy) setState(() => _selected = null);
      },
      art: const Center(
        child: Icon(Icons.block_rounded, color: Colors.white38, size: 30),
      ),
      name: 'None',
      nameColor: Colors.white,
      status: selected ? 'Wearing' : 'Take it off',
      statusColor: selected ? _gold : Colors.white38,
    );
  }

  Widget _tile(ClosetItem item) {
    final art = layeredAccessoryFor(item.itemId);
    final selected = _selected == item.itemId;
    return _frame(
      tileKey: Key('closet-${item.itemId}'),
      selected: selected,
      onTap: () => _tap(item),
      art: Opacity(
        opacity: item.unlocked ? 1 : 0.3,
        // 真圖優先。⚠️ errorBuilder 不能省：圖讀不到時 Image.asset 會丟例外，
        // 而 top_hat／crown 本來就沒有圖，一律退回 emoji。
        child: art == null
            ? Center(
                child: Text(item.emoji, style: const TextStyle(fontSize: 30)),
              )
            : Image.asset(
                art.assetPath,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Center(
                  child: Text(item.emoji, style: const TextStyle(fontSize: 30)),
                ),
              ),
      ),
      name: item.name,
      nameColor: item.unlocked ? Colors.white : Colors.white38,
      status: selected
          ? 'Wearing'
          : item.unlocked
          ? 'Tap to try on'
          : 'Level ${item.unlockLevel}',
      statusColor: selected ? _gold : Colors.white38,
    );
  }

  Widget _frame({
    required Key tileKey,
    required bool selected,
    required VoidCallback onTap,
    required Widget art,
    required String name,
    required Color nameColor,
    required String status,
    required Color statusColor,
  }) {
    return InkWell(
      key: tileKey,
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected ? _cardOn : _card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? _gold : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(child: art),
            const SizedBox(height: 4),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: nameColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(status, style: TextStyle(color: statusColor, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _confirmButton(ClosetState closet) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        key: const Key('closet-confirm'),
        onPressed: _busy ? null : _confirm,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF7657FF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(_busy ? 'Saving…' : 'Confirm outfit'),
      ),
    ),
  );
}
