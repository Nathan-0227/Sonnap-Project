// 「What friends can see」（2026-11-15 使用者定，grill）：每個人自己選讓好友看到什麼。
//
// - 四組（睡眠／心率與壓力／白天活動／遊戲），每組一個總開關，點開才逐項
// - 有時刻的（放下手機、上床起床）可以選「準確時刻」或「只寫準時與否」，預設準確
// - 永遠不給的三項列在最下面當說明，**不是選項**
// - 最下面是「朋友看到的你」預覽（後端照設定遮過的，跟朋友實際看到的同一份）
// - 項目、預設、遮蔽全在後端（social/sharing.py）；這裡只畫、只送改了哪幾個
// - 對所有好友同一組設定
// - 2026-11-16：最上面選動態卡的場景（像換大頭貼；清單由後端給，Dart 不寫死有哪幾張）
import 'package:flutter/material.dart';

import '../services/friends_service.dart';
import '../services/pet_choice.dart';
import '../widgets/friend_night_card.dart';
import '../widgets/streak_card.dart';

class FriendSharingScreen extends StatefulWidget {
  final FriendsService service;
  const FriendSharingScreen({super.key, required this.service});

  @override
  State<FriendSharingScreen> createState() => _FriendSharingScreenState();
}

class _FriendSharingScreenState extends State<FriendSharingScreen> {
  SharingSettings? _settings;
  bool _failed = false;
  final _open = <String>{};
  (FriendSummary, FriendNightCard?)? _preview;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.service.fetchSharing();
    if (!mounted) return;
    var s = r.value;
    // 寵物原本只存在手機上：跟後端不一樣就送一次，朋友才畫得出你選的那一隻
    final mine = PetChoice.current.value.name;
    if (s != null && s.petSpecies != mine) {
      s = (await widget.service.patchSharing(petSpecies: mine)).value ?? s;
    }
    if (!mounted) return;
    setState(() {
      _settings = s;
      _failed = !r.isOk;
    });
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    final p = await widget.service.fetchPreview();
    if (mounted && p.isOk) setState(() => _preview = p.value);
  }

  Future<void> _patch({
    Map<String, bool>? items,
    String? precision,
    String? scene,
  }) async {
    final r = await widget.service.patchSharing(
      items: items,
      timePrecision: precision,
      scene: scene,
    );
    if (!mounted) return;
    if (r.isOk) {
      setState(() => _settings = r.value);
      _loadPreview();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(r.message ?? 'Could not save. Check the connection.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1638),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1638),
        foregroundColor: Colors.white,
        title: const Text('What friends can see'),
      ),
      body: s == null
          ? Center(
              child: _failed
                  ? const Text(
                      'Sharing settings live on the backend, and it cannot be reached right now.',
                      key: Key('sharing-failed'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    )
                  : const CircularProgressIndicator(color: Color(0xFF7657FF)),
            )
          : ListView(
              key: const Key('sharing-list'),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                const Text(
                  'All your friends see the same things. Anything off stays on your phone.',
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 16),
                if (s.scenes.isNotEmpty) ...[
                  _scenes(s),
                  const SizedBox(height: 20),
                ],
                for (final g in s.groups) _group(g),
                const SizedBox(height: 8),
                _precision(s.timePrecision),
                const SizedBox(height: 20),
                _never(s.neverShared),
                const SizedBox(height: 24),
                const Text(
                  'Your card, as friends see it',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                if (_preview case (final f, final card))
                  Column(
                    key: const Key('sharing-preview'),
                    children: [
                      StreakCard(summary: f),
                      if (card != null)
                        FriendNightCardView(card: card)
                      else
                        const Text(
                          'No recent night to show yet.',
                          style: TextStyle(color: Colors.white54),
                        ),
                    ],
                  )
                else
                  const Center(
                    child: CircularProgressIndicator(color: Color(0xFF7657FF)),
                  ),
              ],
            ),
    );
  }

  Widget _scenes(SharingSettings s) => Column(
    key: const Key('sharing-scenes'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        "Your card's scene",
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          for (final id in s.scenes)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  key: Key('sharing-scene-$id'),
                  onTap: id == s.scene ? null : () => _patch(scene: id),
                  child: AspectRatio(
                    aspectRatio: 4 / 5,
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: id == s.scene
                              ? const Color(0xFF7657FF)
                              : const Color(0x22FFFFFF),
                          width: id == s.scene ? 3 : 1,
                        ),
                      ),
                      child: Image.asset(
                        sceneAsset(id),
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        semanticLabel: id,
                        errorBuilder: (_, _, _) =>
                            const ColoredBox(color: Color(0xFF10265A)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ],
  );

  Widget _group(SharingGroup g) {
    final on = g.items.where((i) => i.enabled).length;
    final all = on == g.items.length;
    final open = _open.contains(g.id);
    // Material 不是 Container：開關列的漣漪要畫在它上面，被有底色的盒子擋住會看不到（debug 會報錯）
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFF10265A),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            ListTile(
              key: Key('sharing-group-${g.id}'),
              onTap: () =>
                  setState(() => open ? _open.remove(g.id) : _open.add(g.id)),
              title: Text(
                g.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                '$on of ${g.items.length} shared',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              leading: Icon(
                open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                color: Colors.white54,
              ),
              trailing: Switch(
                key: Key('sharing-group-switch-${g.id}'),
                value: all,
                onChanged: (v) =>
                    _patch(items: {for (final i in g.items) i.key: v}),
              ),
            ),
            if (open)
              for (final i in g.items)
                SwitchListTile(
                  key: Key('sharing-item-${i.key}'),
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 56, right: 16),
                  title: Text(
                    i.label,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  value: i.enabled,
                  onChanged: (v) => _patch(items: {i.key: v}),
                ),
          ],
        ),
      ),
    );
  }

  Widget _precision(String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Bedtimes and phone-down time',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      SegmentedButton<String>(
        key: const Key('sharing-precision'),
        segments: const [
          ButtonSegment(value: 'exact', label: Text('Exact time')),
          ButtonSegment(
            value: 'on_time_only',
            label: Text('On time or late only'),
          ),
        ],
        selected: {value},
        onSelectionChanged: (v) => _patch(precision: v.first),
      ),
    ],
  );

  Widget _never(List<String> items) => Column(
    key: const Key('sharing-never'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Never shared',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      for (final t in items)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              const Icon(Icons.lock_rounded, size: 14, color: Colors.white38),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
