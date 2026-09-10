import 'package:flutter/material.dart';

import '../services/game_service.dart';

/// 衣櫃。每一件衣服、幾級解鎖、現在穿哪一件。
///
/// ⚠️ 「解鎖了沒」照抄後端。不在 Dart 用 `level >= unlockLevel` 判斷——
/// 後端還算上「曾經穿過就不收回」，Dart 自己算會把那件收回去。
///
/// ⚠️ 還沒解鎖的衣服點下去**不發請求**，直接講幾級解鎖。後端也會擋（403），
/// 但讓使用者等一趟網路才知道「還不能穿」沒有意義。
class ClosetScreen extends StatefulWidget {
  final GameService service;

  const ClosetScreen({super.key, required this.service});

  @override
  State<ClosetScreen> createState() => _ClosetScreenState();
}

class _ClosetScreenState extends State<ClosetScreen> {
  GameResult<ClosetState>? _result;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.service.fetchCloset();
    if (!mounted) return;
    setState(() => _result = r);
  }

  Future<void> _tap(ClosetItem item) async {
    if (_busy) return;
    if (!item.unlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.name} unlocks at level ${item.unlockLevel}.')),
      );
      return;
    }
    setState(() => _busy = true);
    // 已經穿著的再點一次 = 脫掉。
    final r = await widget.service.equip(item.equipped ? null : item.itemId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.isOk && r.status != GameStatus.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.message ?? 'Could not reach the backend.')),
      );
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF081326),
      appBar: AppBar(
        backgroundColor: const Color(0xFF081326),
        foregroundColor: Colors.white,
        title: const Text('Closet'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final r = _result;
    if (r == null) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF7657FF)));
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          closet.equipped == null
              ? 'Level ${closet.level} · wearing nothing'
              : 'Level ${closet.level} · wearing ${closet.equipped!.name}',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.85,
          children: [for (final item in closet.items) _tile(item)],
        ),
      ],
    );
  }

  Widget _tile(ClosetItem item) {
    return InkWell(
      key: Key('closet-${item.itemId}'),
      onTap: () => _tap(item),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: item.equipped ? const Color(0xFF233A73) : const Color(0xFF10265A),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: item.equipped ? const Color(0xFFFFD96A) : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Opacity(
              opacity: item.unlocked ? 1 : 0.3,
              child: Text(item.emoji, style: const TextStyle(fontSize: 34)),
            ),
            const SizedBox(height: 6),
            Text(
              item.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                color: item.unlocked ? Colors.white : Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.equipped
                  ? 'Wearing'
                  : item.unlocked
                      ? 'Tap to wear'
                      : 'Level ${item.unlockLevel}',
              style: TextStyle(
                color: item.equipped ? const Color(0xFFFFD96A) : Colors.white38,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
