import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/wall_clock.dart';
import '../services/friends_service.dart';
import '../widgets/mood_filter_bar.dart';
import '../widgets/top_streak_card.dart';

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
class FriendsScreen extends StatefulWidget {
  /// null = 這支 build 沒有後端，畫面會老實講要連上後端。
  final FriendsService? service;

  const FriendsScreen({super.key, this.service});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  String selectedMood = "All";
  FriendsResult<FriendsState>? _result;

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
    if (at == null) return 'No record yet';
    final time = DateFormat('HH:mm').format(at);
    final late = f.lastNightLate == true ? ' · late' : '';
    return 'Phone down $time (${f.lastNightDate ?? ''})$late';
  }

  void _showFriend(FriendSummary f) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF10265A),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(f.displayName,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(lightsOutLine(f), style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 4),
            Text('Streak ${f.currentStreak} · best ${f.bestStreak}',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 4),
            Text(
              // ⚠️ 分母一定要講出來，理由同 Insights 的熬夜比率卡。
              f.recordedNights == 0
                  ? 'No nights recorded yet'
                  : 'Late on ${f.lateNights} of ${f.recordedNights} recorded nights',
              style: const TextStyle(color: Colors.white70),
            ),
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

  void _showFullRanking(List<LeaderboardEntry> board) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF10265A),
      builder: (context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Streak ranking',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          for (final e in board)
            ListTile(
              leading: Text('#${e.rank}', style: const TextStyle(color: Color(0xFFFFD96A))),
              title: Text(e.displayName, style: const TextStyle(color: Colors.white)),
              trailing: Text('${e.currentStreak} nights',
                  style: const TextStyle(color: Colors.white70)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SizedBox(
          width: MediaQuery.of(context).size.width > 650 ? 650 : MediaQuery.of(context).size.width,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Friends ✨",
                  style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  "See how your friends are keeping their bedtimes.",
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
                const SizedBox(height: 24),
                ..._body(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body() {
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
      _inviteCard(state.myInviteCode),
      _circleCard(state.friends),
      if (state.leaderboard.isNotEmpty)
        TopStreakCard(
          users: [
            for (final e in state.leaderboard)
              TopStreakUser(
                rank: e.rank,
                emoji: "🐶",
                name: e.displayName,
                streakDays: e.currentStreak,
                bestDays: e.bestStreak,
              ),
          ],
          onViewAll: () => _showFullRanking(state.leaderboard),
        ),
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
      if (state.notes['what_is_shared'] != null) ...[
        const SizedBox(height: 12),
        Text(state.notes['what_is_shared']!,
            style: const TextStyle(color: Color(0xFF8498B7), fontSize: 11, height: 1.4)),
      ],
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
