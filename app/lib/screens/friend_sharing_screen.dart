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
import '../widgets/settings_list.dart';
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
    return SettingsPage(
      title: 'What friends can see',
      listKey: const Key('sharing-list'),
      loading: s == null && !_failed,
      placeholder: s == null && _failed
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Sharing settings live on the backend, and it cannot be reached right now.',
                  key: Key('sharing-failed'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kSettingsSub, height: 1.4),
                ),
              ),
            )
          : null,
      children: s == null
          ? const []
          : [
              const SettingsNote('All your friends see the same things. Anything off stays on your phone.'),
              if (s.scenes.isNotEmpty) _scenes(s),
              SettingsGroup(title: "WHAT'S SHARED", rows: [for (final g in s.groups) ..._group(g)]),
              _precision(s.timePrecision),
              _never(s.neverShared),
              const Padding(
                padding: EdgeInsets.only(left: 6, bottom: 8),
                child: Text(
                  'YOUR CARD, AS FRIENDS SEE IT',
                  style: TextStyle(color: kSettingsSub, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1),
                ),
              ),
              if (_preview case (final f, final card))
                Column(
                  key: const Key('sharing-preview'),
                  children: [
                    StreakCard(summary: f),
                    if (card != null)
                      FriendNightCardView(card: card)
                    else
                      const Text('No recent night to show yet.', style: TextStyle(color: kSettingsSub)),
                  ],
                )
              else
                const Center(child: CircularProgressIndicator(color: kSettingsAccent)),
            ],
    );
  }

  Widget _scenes(SharingSettings s) => SettingsGroup(
        key: const Key('sharing-scenes'),
        title: "YOUR CARD'S SCENE",
        rows: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                for (final id in s.scenes)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: id == s.scenes.last ? 0 : 8),
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
                                color: id == s.scene ? kSettingsAccent : const Color(0x22FFFFFF),
                                width: id == s.scene ? 3 : 1,
                              ),
                            ),
                            child: Image.asset(
                              sceneAsset(id),
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                              semanticLabel: id,
                              errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF10265A)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );

  static const _groupColors = [
    Color(0xFF7657FF),
    Color(0xFFD2557A),
    Color(0xFF3FA27A),
    Color(0xFFE58A3A),
    Color(0xFF3B7DD8),
  ];

  /// 一組：標題列（點了展開、右邊總開關）＋展開時每一項一列。
  List<Widget> _group(SharingGroup g) {
    final on = g.items.where((i) => i.enabled).length;
    final all = on == g.items.length;
    final open = _open.contains(g.id);
    final index = _settings?.groups.indexOf(g) ?? 0;
    return [
      SettingsRow(
        key: Key('sharing-group-${g.id}'),
        icon: open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
        color: _groupColors[index % _groupColors.length],
        title: g.label,
        subtitle: '$on of ${g.items.length} shared',
        trailing: SettingsSwitch(
          key: Key('sharing-group-switch-${g.id}'),
          value: all,
          onChanged: (v) => _patch(items: {for (final i in g.items) i.key: v}),
        ),
        onTap: () => setState(() => open ? _open.remove(g.id) : _open.add(g.id)),
      ),
      if (open)
        for (final i in g.items)
          Padding(
            padding: const EdgeInsets.only(left: 46),
            child: SettingsRow(
              key: Key('sharing-item-${i.key}'),
              dense: true,
              title: i.label,
              trailing: SettingsSwitch(value: i.enabled, onChanged: (v) => _patch(items: {i.key: v})),
              onTap: () => _patch(items: {i.key: !i.enabled}),
            ),
          ),
    ];
  }

  Widget _precision(String value) => SettingsGroup(
        key: const Key('sharing-precision'),
        title: 'BEDTIMES AND PHONE-DOWN TIME',
        rows: [
          for (final (v, label) in const [('exact', 'Exact time'), ('on_time_only', 'On time or late only')])
            SettingsRow(
              key: Key('sharing-precision-$v'),
              title: label,
              trailing: SettingsRadio(selected: value == v),
              onTap: value == v ? null : () => _patch(precision: v),
            ),
        ],
      );

  Widget _never(List<String> items) => SettingsGroup(
        key: const Key('sharing-never'),
        title: 'NEVER SHARED',
        rows: [
          for (final t in items)
            SettingsRow(
              dense: true,
              icon: Icons.lock_rounded,
              color: const Color(0xFF3A4672),
              title: t,
            ),
        ],
      );
}
