import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/wall_clock.dart';
import '../services/friends_service.dart';
import '../services/pet_choice.dart';
import '../widgets/friend_night_card.dart';
import '../widgets/friends_town.dart';
import '../widgets/mood_filter_bar.dart';
import '../widgets/streak_card.dart';
import '../widgets/leaderboard_section.dart';
import 'friend_sharing_screen.dart';

/// 好友。資料來自 `GET /friends`。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 這個畫面原本是四筆寫死的假朋友與假排行
/// ═══════════════════════════════════════════════════════════════════
///
/// 那些名字與「Asleep / Online now」全部拿掉了，換成後端真的資料。兩個理由：
///   1. 不要拿任何人的名字當佔位符（CLAUDE.md：首頁曾經對 Nathan 說
///      「Good morning Jeremy」）。
///   2. 「現在睡著了沒」「在線上」這種即時狀態，後端根本沒有——我們只知道
///      每一晚幾點放下手機。畫面上講我們不知道的事就是編造。所以「Sleep Circle」
///      改成講「最近一晚準時／熬夜」，那是真的量得到的。
///
/// ⚠️ 朋友只看得到行為（幾點放下手機、連續幾晚），看不到分數、深睡、心率。
///    心情也是行為版，所以篩選列拿掉了「Sick」——那個選項永遠篩不出任何人。
///
/// ⚠️ 這個畫面一格都不算。連續夜數、排名都照抄後端，排行不在 Dart 重排。
///
/// 2026-11-15（使用者定，grill）：每個人自己選公開什麼（右上角 → What friends can see）；
/// 最上面是**我的 Streak 大卡**，下面多一段朋友最近 7 天的**動態卡**（只有他公開的項目）。
/// 2026-11-16：Streak 大卡底下分 **Feed**（動態牆，預設）與 **Friends**（邀請碼、名單、排行）兩個分頁。
/// 2026-11-17（使用者定）：最前面多一個 **Town**（好友小鎮，預設），Streak 大卡換成小鎮底下的一行
/// 「🔥 3 nights in a row · Best 5 · This week ›」（點了才看那張大卡）。小鎮的規則見 widgets/friends_town.dart。
/// 朋友沒公開的值是 null，畫面就不畫那一項，不寫成 0。
class FriendsScreen extends StatefulWidget {
  /// null = 這支 build 沒有後端，畫面會老實講要連上後端。
  final FriendsService? service;

  const FriendsScreen({super.key, this.service});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  String selectedMood = "All";

  /// 2026-11-17 使用者定：Town · Feed · Friends，打開預設在 Town。
  _Tab _tab = _Tab.town;
  FriendsResult<FriendsState>? _result;
  FriendsResult<TownState>? _town;
  List<FriendNightCard> _feed = const [];

  /// 好友畫面的篩選選項。⚠️ 沒有「Sick」，理由見類別說明。
  static const List<Map<String, String>> moodOptions = [
    {"label": "All", "emoji": ""},
    {"label": "Happy", "emoji": "🙂"},
    {"label": "Normal", "emoji": "😐"},
    {"label": "Tired", "emoji": "😟"},
    {"label": "No record", "emoji": "❔"},
  ];

  /// 後端的心情值 → 篩選列的標籤。純查表，判斷在後端（pet_state.py）。
  static String moodLabel(String? mood) {
    switch (mood) {
      case 'happy':
        return 'Happy';
      case 'bored':
        return 'Normal';
      case 'tired':
        return 'Tired';
      default:
        return 'No record';
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = widget.service;
    if (service == null) return;
    final r = await service.fetch();
    if (!mounted) return;
    setState(() => _result = r);
    await _loadTown();
    if (!mounted) return;
    // 寵物原本只存在手機上：跟後端不一樣就送一次，朋友才畫得出你選的那一隻
    final mine = PetChoice.current.value.name;
    final server = r.value?.me?.petSpecies;
    if (r.isOk && server != null && server != mine) {
      await service.patchSharing(petSpecies: mine);
    }
    final feed = await service.fetchFeed();
    if (!mounted) return;
    if (feed.isOk) setState(() => _feed = feed.value!);
  }

  Future<void> _loadTown() async {
    final service = widget.service;
    if (service == null) return;
    final t = await service.fetchTown();
    if (mounted) setState(() => _town = t);
  }

  /// 送出拜訪。null＝成功；否則是要顯示在小卡上的話（後端原文：409 是「今天已經來過了」）。
  Future<String?> _visit(TownPerson p, String kind) async {
    final service = widget.service;
    if (service == null) return 'Could not reach the backend.';
    final r = await service.visit(p.handle, kind);
    if (r.isOk || r.httpStatus == 409) _loadTown();
    if (r.isOk) return null;
    return r.message ?? 'Could not reach the backend.';
  }

  void _tapTownie(TownPerson p) {
    if (p.mine) {
      // 點自己＝看自己昨晚（朋友看到的那張）
      final card = p.card;
      if (card != null) {
        openFriendNight(context, card);
      } else {
        _toast('Nothing to show for last night yet.');
      }
      return;
    }
    showTownFriendSheet(
      context,
      person: p,
      kinds: _town?.value?.kinds ?? const [],
      onVisit: (kind) => _visit(p, kind),
    );
  }

  void _openMyWeek(FriendSummary me) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF10265A),
      builder: (context) => SingleChildScrollView(
        key: const Key('my-week-sheet'),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: StreakCard(summary: me),
      ),
    );
  }

  Future<void> _openSharing() async {
    final service = widget.service;
    if (service == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => FriendSharingScreen(service: service)),
    );
    await _load();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _addFriend() async {
    final service = widget.service;
    if (service == null) return;
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a friend'),
        content: TextField(
          key: const Key('invite-field'),
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: "Their 6-character invite code"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            key: const Key('invite-submit'),
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (code == null || code.trim().isEmpty) return;

    final r = await service.add(code);
    if (!mounted) return;
    // ⚠️ 失敗時照抄後端的話：404 沒有這個碼、409 已經是朋友、422 那是你自己的碼。
    _toast(r.isOk ? 'Added ${r.value!.displayName}.' : (r.message ?? 'Could not reach the backend.'));
    await _load();
  }

  Future<void> _removeFriend(FriendSummary friend) async {
    final service = widget.service;
    if (service == null) return;
    Navigator.of(context).pop();
    final r = await service.remove(friend.handle);
    if (!mounted) return;
    _toast(r.isOk ? 'Removed ${friend.displayName}.' : (r.message ?? 'Could not reach the backend.'));
    await _load();
  }

  /// 「幾點放下手機」那一行。⚠️ 一律走 parseWallClock()：
  /// `DateTime.tryParse("...+08:00")` 回的是 UTC，`.hour` 會早 8 小時。
  static String lightsOutLine(FriendSummary f) {
    final at = parseWallClock(f.lastLightsOutAt);
    if (at == null) {
      // 時刻沒公開（或只公開準時與否）：有準時就寫準時
      if (f.lastNightLate != null) return f.lastNightLate! ? 'Late last night' : 'On time last night';
      return 'No record yet';
    }
    final time = DateFormat('HH:mm').format(at);
    final late = f.lastNightLate == true ? ' · late' : '';
    return 'Phone down $time (${f.lastNightDate ?? ''})$late';
  }

  void _showFriend(FriendSummary f) {
    final latest = _feed.where((c) => c.handle == f.handle).firstOrNull;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF10265A),
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(f.displayName,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            // 他的 Streak 卡（他沒公開的部分後端已經遮掉）
            StreakCard(summary: f, species: speciesOf(f.petSpecies)),
            Text(lightsOutLine(f), style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 4),
            if (f.lateNights != null)
              Text(
                // ⚠️ 分母一定要講出來，理由同 Insights 的熬夜比率卡。
                f.recordedNights == 0
                    ? 'No nights recorded yet'
                    : 'Late on ${f.lateNights} of ${f.recordedNights} recorded nights',
                style: const TextStyle(color: Colors.white70),
              ),
            if (latest != null) ...[
              const SizedBox(height: 12),
              FriendNightCardView(card: latest),
            ],
            const SizedBox(height: 16),
            TextButton.icon(
              key: const Key('remove-friend'),
              onPressed: () => _removeFriend(f),
              icon: const Icon(Icons.person_remove_rounded, color: Color(0xFFFF6B6B)),
              label: const Text('Remove friend', style: TextStyle(color: Color(0xFFFF6B6B))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _titleRow() => Row(
        children: [
          const Expanded(
            child: Text(
              "Friends ✨",
              style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold),
            ),
          ),
          if (widget.service != null)
            IconButton(
              key: const Key('open-sharing'),
              tooltip: 'What friends can see',
              onPressed: _openSharing,
              icon: const Icon(Icons.visibility_rounded, color: Colors.white70),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    // ⚠️ 靠上對齊，不能用 Center：內容比螢幕短時（小鎮分頁）Center 會把整頁垂直置中，
    //    上面空一大塊（2026-11-18 實機）。以前頁首有很高的 Streak 大卡才看不出來。
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: MediaQuery.of(context).size.width > 650 ? 650 : MediaQuery.of(context).size.width,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(20, top + 12, 12, 12),
                child: _titleRow(),
              ),
              ..._body(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _pad(Widget child) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: child);

  List<Widget> _body() => [
        for (final w in _bodyParts()) w is _FullWidth ? w.child : _pad(w),
      ];

  List<Widget> _bodyParts() {
    if (widget.service == null) {
      return [
        _card(const Text(
          "Friends need the Sonnap backend. Connect to the server to add friends "
          "with an invite code.",
          key: Key('friends-no-backend'),
          style: TextStyle(color: Colors.white70, height: 1.4),
        )),
      ];
    }
    final r = _result;
    if (r == null) {
      return const [Center(child: CircularProgressIndicator(color: Color(0xFF7657FF)))];
    }
    final state = r.value;
    if (!r.isOk || state == null) {
      return [
        _card(const Text(
          "Friends live on the backend, and it cannot be reached right now.",
          style: TextStyle(color: Colors.white70),
        )),
      ];
    }

    final visible = selectedMood == "All"
        ? state.friends
        : state.friends.where((f) => moodLabel(f.petMood) == selectedMood).toList();

    return [
      _tabs(),
      const SizedBox(height: 16),
      ...switch (_tab) {
        _Tab.town => _townTab(state),
        _Tab.feed => _feedTab(state),
        _Tab.friends => _friendsTab(state, visible),
      },
      if (state.notes['what_is_shared'] != null) ...[
        const SizedBox(height: 12),
        Text(state.notes['what_is_shared']!,
            style: const TextStyle(color: Color(0xFF8498B7), fontSize: 11, height: 1.4)),
      ],
    ];
  }

  Widget _tabs() {
    Widget tab(String label, bool selected, VoidCallback onTap, Key key) => InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0x99FFFFFF),
                      fontSize: 17,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    )),
                const SizedBox(height: 4),
                Container(
                  width: 22,
                  height: 3,
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFF7657FF) : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        );
    return Row(
      children: [
        for (final (t, label) in [(_Tab.town, 'Town'), (_Tab.feed, 'Feed'), (_Tab.friends, 'Friends')]) ...[
          tab(label, _tab == t, () => setState(() => _tab = t), Key('tab-${t.name}')),
          const SizedBox(width: 20),
        ],
      ],
    );
  }

  /// 好友小鎮：夜景（整個寬度）→ 連續晚數那一行 → ✨ 的說明 → 今天誰來看過你。
  List<Widget> _townTab(FriendsState state) {
    final t = _town;
    if (t == null) {
      return const [Center(child: CircularProgressIndicator(color: Color(0xFF7657FF)))];
    }
    final town = t.value;
    if (!t.isOk || town == null) {
      return [
        _card(const Text(
          "The town lives on the backend, and it cannot be reached right now.",
          key: Key('town-unreachable'),
          style: TextStyle(color: Colors.white70),
        )),
      ];
    }
    final me = state.me;
    return [
      _FullWidth(TownScene(town: town, onTap: _tapTownie)),
      if (me?.currentStreak != null) _streakRow(me!),
      const Padding(
        padding: EdgeInsets.only(top: 6, bottom: 14),
        child: Text('✨ = put the phone down on time last night',
            key: Key('town-legend'), style: TextStyle(color: Color(0x88FFFFFF), fontSize: 12)),
      ),
      if (town.friends.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: FilledButton.icon(
            key: const Key('town-invite'),
            onPressed: () => setState(() => _tab = _Tab.friends),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Invite friends'),
          ),
        ),
      if (town.visits.isNotEmpty) TownVisitsCard(visits: town.visits),
    ];
  }

  Widget _streakRow(FriendSummary me) {
    final n = me.currentStreak!;
    return InkWell(
      key: const Key('town-streak'),
      onTap: () => _openMyWeek(me),
      child: Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(
          children: [
            const Icon(Icons.local_fire_department_rounded, color: Color(0xFFFF8A5C), size: 22),
            const SizedBox(width: 6),
            Flexible(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: '$n ${n == 1 ? 'night' : 'nights'} in a row',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  if (me.bestStreak != null)
                    TextSpan(
                      text: '  ·  Best ${me.bestStreak}',
                      style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 14),
                    ),
                ]),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            const Text('This week',
                style: TextStyle(color: Color(0xFFB9A6FF), fontSize: 14, fontWeight: FontWeight.w600)),
            const Icon(Icons.chevron_right, color: Color(0xFFB9A6FF), size: 20),
          ],
        ),
      ),
    );
  }

  /// 動態牆：朋友最近 7 天每一晚一張卡（新的在前，順序照後端）。
  List<Widget> _feedTab(FriendsState state) {
    if (_feed.isEmpty) {
      return [
        _card(Text(
          state.friends.isEmpty
              ? "No friends yet. Open Friends to share your invite code."
              : "No nights from you or your friends in the last 7 days yet.",
          key: const Key('feed-empty'),
          style: const TextStyle(color: Colors.white70, height: 1.4),
        )),
      ];
    }
    return [
      for (final (i, c) in _feed.indexed) ...[
        // 換一天就插一條分隔線（2026-11-16 使用者要求）：──── Last night ────
        if (i == 0 || _feed[i - 1].date != c.date)
          feedDayDivider(c.date, key: Key('feed-day-$i')),
        Builder(builder: (context) {
          // 我自己的卡：連續天數與這週用我自己的摘要；點開最下面是分享設定
          final f = c.mine
              ? state.me
              : state.friends.where((x) => x.handle == c.handle).firstOrNull;
          return FriendNightCardView(
            card: c,
            // 連續天數的橫幅只放在他最近那一晚的卡上
            streak: f != null && f.lastNightDate == c.date ? f.currentStreak : null,
            week: f != null && f.lastNightDate == c.date ? f.streakWeek : null,
            // 點卡片＝See all：同一張卡的完整版（每一項一個小格）；下面可以再看他的 Streak 與解除好友
            onTap: () => openFriendNight(context, c,
                streak: f != null && f.lastNightDate == c.date ? f.currentStreak : null,
                week: f != null && f.lastNightDate == c.date ? f.streakWeek : null),
          );
        }),
      ],
    ];
  }

  List<Widget> _friendsTab(FriendsState state, List<FriendSummary> visible) {
    return [
      _inviteCard(state.myInviteCode),
      _circleCard(state.friends),
      // 七個排行榜（第二批）：名次、門檻都照抄後端（舊的只有連續天數那張換掉了）
      if (widget.service != null) LeaderboardSection(service: widget.service!),
      MoodFilterBar(
        options: moodOptions,
        selectedMood: selectedMood,
        onMoodSelected: (mood) => setState(() => selectedMood = mood),
      ),
      if (state.friends.isEmpty)
        _card(const Text(
          "No friends yet. Share your invite code, or add a friend with theirs.",
          key: Key('friends-empty'),
          style: TextStyle(color: Colors.white70, height: 1.4),
        ))
      else if (visible.isEmpty)
        _card(const Text("No friends found with this mood.",
            style: TextStyle(color: Colors.white70)))
      else
        for (final f in visible) _friendRow(f),
    ];
  }

  Widget _card(Widget child) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF10265A),
          borderRadius: BorderRadius.circular(24),
        ),
        child: child,
      );

  Widget _inviteCard(String code) => _card(Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Your invite code", style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                SelectableText(
                  code,
                  key: const Key('my-invite-code'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            key: const Key('add-friend'),
            onPressed: _addFriend,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Add'),
          ),
        ],
      ));

  /// 最近一晚準時／熬夜各幾人。⚠️ 用後端的 last_night_late，不在 Dart 判斷幾分鐘算晚。
  Widget _circleCard(List<FriendSummary> friends) {
    final onTime = friends.where((f) => f.lastNightLate == false).length;
    final late = friends.where((f) => f.lastNightLate == true).length;
    Widget half(IconData icon, Color bg, int n, String label, Key key) => Expanded(
          child: Row(
            children: [
              CircleAvatar(radius: 22, backgroundColor: bg, child: Icon(icon, color: Colors.white)),
              const SizedBox(width: 12),
              // ⚠️ Expanded 不能省：標籤比原本的「Friends asleep」長，一半只有
              //    約 285px（650 寬的版面），手機上更窄——少了它就溢位（測試抓到的）。
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("$n",
                        key: key,
                        style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                    Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        );
    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.groups_rounded, color: Color(0xFF7C6DFF)),
            SizedBox(width: 8),
            Text("Sleep Circle",
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            half(Icons.nightlight_round, const Color(0xFF3546B8), onTime, "On time, latest night",
                const Key('circle-on-time')),
            half(Icons.phone_android_rounded, const Color(0xFF7C6DFF), late, "Late, latest night",
                const Key('circle-late')),
          ],
        ),
      ],
    ));
  }

  Widget _friendRow(FriendSummary f) => InkWell(
        key: Key('friend-${f.handle}'),
        onTap: () => _showFriend(f),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF10265A),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 24,
                backgroundColor: Color(0xFF233A73),
                child: Text("🐶", style: TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.displayName,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(lightsOutLine(f), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    if (f.currentStreak != null)
                      Text('Streak ${f.currentStreak}',
                          style: const TextStyle(color: Color(0xFF8498B7), fontSize: 12)),
                  ],
                ),
              ),
              Text(moodLabel(f.petMood), style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
      );
}

enum _Tab { town, feed, friends }

/// 不要左右留白的那一塊（小鎮的夜景要整個寬度）。
class _FullWidth extends StatelessWidget {
  final Widget child;
  const _FullWidth(this.child);
  @override
  Widget build(BuildContext context) => child;
}
