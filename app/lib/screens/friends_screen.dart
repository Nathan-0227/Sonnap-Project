import 'package:flutter/material.dart';

import '../services/friends_service.dart';
import '../services/key_value_store.dart';
import '../services/visits_seen.dart';
import '../widgets/visit_gift_sheet.dart';
import '../services/pet_choice.dart';
import '../widgets/friend_live_card.dart';
import '../widgets/friend_live_sheet.dart';
import '../widgets/home_pet.dart';
import '../widgets/invite_postcard_sheet.dart';
import '../widgets/report_sheet.dart';
import '../widgets/friend_night_card.dart';
import '../widgets/friends_town.dart';
import '../widgets/visit_received_scene.dart';
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
/// 2026-11-18：Town 改成**整個畫面都是地圖**（照 Finch），標題與分頁浮在上面，連續晚數、✨ 說明、
/// 誰來看過你收成左下／右下的小圓鈕。載入中、連不到後端時退回一般的版面照實說。
/// 朋友沒公開的值是 null，畫面就不畫那一項，不寫成 0。
/// 好友頁存在手機上的鍵。
abstract final class FriendsScreenKeys {
  /// 「要不要讓好友看到即時狀態」問過了沒（只問一次）。值：'on'／'off'。
  static const liveAsked = 'friends_live_status_asked';
}

class FriendsScreen extends StatefulWidget {
  /// null = 這支 build 沒有後端，畫面會老實講要連上後端。
  final FriendsService? service;

  /// 現在幾點（卡片上「睡了多久」「12m ago」用）。測試注入。
  final DateTime Function() clock;

  /// 「要不要分享即時狀態」只問一次：問過了記在這裡。測試注入記憶體版。
  final KeyValueStore store;

  /// 送禮推門、收禮場景（2026-11-22）。只有正式的 App 打開，測試預設關（同進場動畫）。
  final bool animateScenes;

  const FriendsScreen({
    this.animateScenes = false,
    super.key,
    this.service,
    this.clock = DateTime.now,
    this.store = const PlatformKeyValueStore(),
  });

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  /// 2026-11-17 使用者定：Town · Feed · Friends，打開預設在 Town。
  _Tab _tab = _Tab.town;
  FriendsResult<FriendsState>? _result;
  FriendsResult<TownState>? _town;
  List<FriendNightCard> _feed = const [];

  /// Friends 分頁裡的子分頁（2026-11-19）：All · Asleep · Still up · This Week。
  _LiveTab _live = _LiveTab.all;

  bool _liveAsking = false;

  /// 我的 live_status 有沒有分享（You 卡用）；null＝還不知道（沒問到後端）。
  bool? _liveShared;

  /// 後端記的我是哪一隻（null＝還不知道）。小鎮與動態卡上「你」的寵物照後端畫。
  String? _serverSpecies;

  @override
  void initState() {
    super.initState();
    PetChoice.current.addListener(_onPetChanged);
    _load();
  }

  @override
  void dispose() {
    PetChoice.current.removeListener(_onPetChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final service = widget.service;
    if (service == null) return;
    final r = await service.fetch();
    if (!mounted) return;
    setState(() => _result = r);
    // 寵物原本只存在手機上：跟後端不一樣就送一次，朋友才畫得出你選的那一隻。
    // ⚠️ 要在讀小鎮**之前**送（2026-11-22 實機：先讀小鎮的話，這一次打開看到的還是舊的那一隻）
    _serverSpecies = r.isOk ? r.value?.me?.petSpecies : null;
    await _syncPetSpecies();
    if (!mounted) return;
    await _loadTown();
    if (!mounted) return;
    final feed = await service.fetchFeed();
    if (!mounted) return;
    if (feed.isOk) setState(() => _feed = feed.value!);
  }

  /// 手機上選的跟後端記的不一樣 → 送一次。送成功回 true。
  Future<bool> _syncPetSpecies() async {
    final service = widget.service;
    final mine = PetChoice.current.value.name;
    if (service == null || _serverSpecies == null || _serverSpecies == mine) return false;
    final r = await service.patchSharing(petSpecies: mine);
    if (r.isOk) _serverSpecies = mine;
    return r.isOk;
  }

  /// 在設定頁換了寵物（好友頁一直開在 TabSwitcher 裡）：送給後端，再重讀小鎮與動態牆。
  Future<void> _onPetChanged() async {
    if (!await _syncPetSpecies() || !mounted) return;
    await _loadTown();
    await _loadFeed();
  }

  Future<void> _loadFeed() async {
    final service = widget.service;
    if (service == null) return;
    final feed = await service.fetchFeed();
    if (mounted && feed.isOk) setState(() => _feed = feed.value!);
  }

  /// 按了 🐾、後端還沒回來的人：按鈕當下就變 Sent，不然等重拿動態牆那一下會被連按好幾次
  /// （2026-11-19 實機：一次 201 後面跟三次 409）。送失敗才拿掉。
  final Set<String> _pawPending = {};

  /// 動態卡上的 🐾＝在小鎮摸摸他的寵物（同一件事、一天一次）。
  Future<void> _paw(FriendNightCard c) async {
    final service = widget.service;
    if (service == null || _pawPending.contains(c.handle)) return;
    setState(() => _pawPending.add(c.handle));
    final r = await service.visit(c.handle, 'pet');
    if (!mounted) return;
    if (r.isOk || r.httpStatus == 409) {
      await _loadFeed();
      _loadTown();
    } else {
      setState(() => _pawPending.remove(c.handle));
      _toast(r.message ?? 'Could not reach the backend.');
    }
  }

  /// 自己的卡：是誰給了 🐾（名單只給卡片主人）。
  void _showPawFrom(FriendNightCard c) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF10265A),
      builder: (context) => Padding(
        key: const Key('paw-from-sheet'),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c.paws == 1 ? '1 paw' : '${c.paws} paws',
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            for (final n in c.pawFrom)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.pets_rounded, color: Color(0xFFFFD27A), size: 18),
                    const SizedBox(width: 10),
                    Text(n, style: const TextStyle(color: Colors.white, fontSize: 15)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 今天收到的拜訪裡看過哪幾則（愛心上的數字只算沒看過的，Q12）。
  Set<String> _visitsSeen = const {};

  Future<void> _loadTown() async {
    final service = widget.service;
    if (service == null) return;
    final t = await service.fetchTown();
    if (!mounted) return;
    setState(() => _town = t);
    // ⚠️ 地圖先畫、看過哪幾則晚一點補上：讀手機儲存慢（或測試裡 channel 不回應）時不能拖住整個小鎮
    final day = t.value?.day;
    if (day == null) return;
    final seen = await VisitsSeenStore(widget.store).seen(day);
    if (mounted && _town?.value?.day == day) {
      setState(() => _visitsSeen = {..._visitsSeen, ...seen});
    }
  }

  /// 開送禮頁（2026-11-22）。回傳今天送了他什麼；沒送是 null。
  Future<String?> _openGifts(TownPerson p) async {
    final town = _town?.value;
    String? sent;
    // 推門：對準他在地圖上那一間（我在第 0 間，朋友照順序住進去）
    final lot = town == null ? -1 : town.friends.indexOf(p) + 1;
    await showVisitGiftSheet(
      context,
      door: widget.animateScenes && lot > 0 && lot < kTownLots.length ? kTownLots[lot] : null,
      friend: p,
      me: town?.me,
      kinds: town?.kinds ?? const [],
      invites: town?.invites ?? const {},
      clock: widget.clock,
      onSend: (kind) async {
        final error = await _visit(p, kind);
        if (error == null) sent = kind;
        return error;
      },
    );
    return sent ?? p.sent;
  }

  /// 送出拜訪。null＝成功；否則是要顯示在小卡上的話（後端原文：409 是「今天已經來過了」）。
  Future<String?> _visit(TownPerson p, String kind) async {
    final service = widget.service;
    if (service == null) return 'Could not reach the backend.';
    final r = await service.visit(p.handle, kind);
    if (r.isOk || r.httpStatus == 409) {
      _loadTown();
      _loadFeed(); // 🐾 跟拜訪是同一件事，動態卡上的數字與 Sent 也要跟著變
    }
    if (r.isOk) return null;
    return r.message ?? 'Could not reach the backend.';
  }

  final _townMap = GlobalKey<TownMapState>();

  /// 點小鎮裡的人（2026-11-19 使用者定，照參考圖）：地圖把他移到上面那塊的正中間，
  /// 下半部滑出資訊面板。點自己是同一個面板（朋友看到的你＋今天誰來看過你）。
  void _tapTownie(TownPerson p) {
    final state = _result?.value;
    final h = MediaQuery.sizeOf(context).height;
    final top = MediaQuery.paddingOf(context).top + 120;
    _townMap.currentState?.focusOn(p.handle, (top + h * (1 - kTownSheetSize)) / 2);
    showTownFriendSheet(
      context,
      person: p,
      kinds: _town?.value?.kinds ?? const [],
      onOpenGifts: p.mine ? null : () => _openGifts(p),
      summary: p.mine
          ? state?.me
          : state?.friends.where((f) => f.handle == p.handle).firstOrNull,
      visits: p.mine ? _town?.value?.visits ?? const [] : const [],
    );
  }

  void _openMyWeek(FriendSummary me) {
    // 2026-11-22：只留一層（原本面板裡又包一張有框的卡），底部留系統導覽列的高度
    showReportSheet<void>(
      context: context,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2A2F6E), Color(0xFF1A1F4A)],
          ),
        ),
        child: SingleChildScrollView(
          key: const Key('my-week-sheet'),
          padding: EdgeInsets.fromLTRB(20, 22, 20, 12 + MediaQuery.paddingOf(context).bottom),
          child: StreakCard(summary: me, bare: true),
        ),
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
    // 回來時 You 卡要跟著改（可能剛打開或關掉即時狀態）
    if (mounted && _tab == _Tab.friends) await _maybeAskLiveSharing();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// 標題右邊的「人＋」（2026-11-19 使用者定 Q2）：上面是我的邀請碼（可以複製），下面輸入朋友的。
  /// 11-22 起是小鎮明信片（`InvitePostcardSheet`）。
  Future<void> _addFriend() async {
    final service = widget.service;
    if (service == null) return;
    final myCode = _result?.value?.myInviteCode ?? '';
    final controller = TextEditingController();
    final code = await showReportSheet<String>(
      context: context,
      builder: (context) => InvitePostcardSheet(
        myCode: myCode,
        controller: controller,
        onSubmit: () => Navigator.pop(context, controller.text),
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

  /// 點好友卡片（Q6）：現在的狀態 → 7 晚放下手機 → 最近那張動態卡 → Remove friend。
  void _showFriend(FriendSummary f) {
    final latest = _feed.where((c) => c.handle == f.handle).firstOrNull;
    showReportSheet<void>(
      context: context,
      builder: (context) => FriendLiveSheet(
        friend: f,
        now: widget.clock(),
        lastNight: latest,
        onRemove: () => _removeFriend(f),
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
          if (widget.service != null) ...[
            IconButton(
              key: const Key('open-sharing'),
              tooltip: 'What friends can see',
              onPressed: _openSharing,
              icon: const Icon(Icons.visibility_rounded, color: Colors.white70),
            ),
            const SizedBox(width: 4),
            // 參考圖的圓鈕（2026-11-19 Q2）：我的邀請碼＋輸入朋友的，都在這裡
            Material(
              color: const Color(0xFF2A2F70),
              shape: const CircleBorder(),
              child: IconButton(
                key: const Key('add-friend'),
                tooltip: 'Add a friend',
                onPressed: _addFriend,
                icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
              ),
            ),
          ],
        ],
      );

  @override
  Widget build(BuildContext context) {
    final state = _result?.value;
    final town = _town?.value;
    if (_tab == _Tab.town && widget.service != null && state != null && town != null && _town!.isOk) {
      return _townFull(state, town);
    }
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
        for (final w in _bodyParts()) _pad(w),
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

    final visible = switch (_live) {
      _LiveTab.asleep => state.friends.where((f) => liveFilterOf(f) == 'asleep').toList(),
      _LiveTab.stillUp => state.friends.where((f) => liveFilterOf(f) == 'still_up').toList(),
      _ => state.friends,
    };

    return [
      _tabs(),
      const SizedBox(height: 16),
      ...switch (_tab) {
        _Tab.town => _townTab(state),
        _Tab.feed => _feedTab(state),
        _Tab.friends => _friendsTab(state, visible),
        // 2026-11-19 使用者定：排行榜自成一個大分頁（名次、門檻照抄後端）
        _Tab.ranks => [LeaderboardSection(service: widget.service!)],
      },
      if (state.notes['what_is_shared'] != null) ...[
        const SizedBox(height: 12),
        Text(state.notes['what_is_shared']!,
            style: const TextStyle(color: Color(0xFF8498B7), fontSize: 11, height: 1.4)),
      ],
    ];
  }

  void _selectTab(_Tab t) {
    setState(() => _tab = t);
    if (t == _Tab.friends) _maybeAskLiveSharing();
  }

  /// 第一次進 Friends 分頁時問一次要不要分享即時狀態（2026-11-19 使用者定 Q3：預設關、問一次）。
  /// ⚠️ 不在 initState 問：好友頁在 TabSwitcher 裡，App 一打開就建好了，會在首頁上跳出來。
  /// ⚠️ 連不到後端、舊版後端沒有這一項、按旁邊關掉 → **不記成問過**，下次再問
  ///    （同建帳號那條：暫時的失敗不能記成永久的決定）。
  Future<void> _maybeAskLiveSharing() async {
    final service = widget.service;
    if (service == null || _liveAsking) return;
    _liveAsking = true;
    try {
      // 每次進 Friends 分頁都問一次後端：You 卡要知道好友看不看得到你
      final r = await service.fetchSharing();
      if (!mounted || !r.isOk || r.value == null) return;
      final item = r.value!.groups
          .expand((g) => g.items)
          .where((i) => i.key == 'live_status')
          .firstOrNull;
      if (item == null) return;
      setState(() => _liveShared = item.enabled);
      if (await widget.store.getString(FriendsScreenKeys.liveAsked) != null) return;
      if (!mounted) return;
      if (item.enabled) {
        await widget.store.setString(FriendsScreenKeys.liveAsked, 'on');
        return;
      }
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: const Key('live-ask'),
          backgroundColor: const Color(0xFF1B2350),
          title: const Text("Show friends when you're asleep?",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: const Text(
            "When you tap Start Sleep, friends see \"Asleep since 23:40\". "
            "If you haven't tapped it after your bedtime, they see how long it's been. "
            "You can change this anytime in What friends see.",
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          actions: [
            TextButton(
              key: const Key('live-ask-no'),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              key: const Key('live-ask-yes'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Share'),
            ),
          ],
        ),
      );
      if (!mounted || yes == null) return;
      if (yes) {
        final saved = await service.patchSharing(items: {'live_status': true});
        if (!saved.isOk) return;
        if (mounted) setState(() => _liveShared = true);
      }
      await widget.store.setString(FriendsScreenKeys.liveAsked, yes ? 'on' : 'off');
    } finally {
      _liveAsking = false;
    }
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
    // 2026-11-19 多了 Ranks：四個在窄手機上放不下（測試量到超出 86 px）→ 間距縮小，
    // 還是太窄就整排等比縮小（不換行、不截字）
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, (t, label)) in [
            (_Tab.town, 'Town'),
            (_Tab.feed, 'Feed'),
            (_Tab.friends, 'Friends'),
            (_Tab.ranks, 'Ranks'),
          ].indexed) ...[
            if (i > 0) const SizedBox(width: 14),
            tab(label, _tab == t, () => _selectTab(t), Key('tab-${t.name}')),
          ],
        ],
      ),
    );
  }

  /// 好友小鎮：夜景（整個寬度）→ 連續晚數那一行 → ✨ 的說明 → 今天誰來看過你。
  /// 小鎮還沒好的時候（載入中、連不到後端）。好了之後整頁換成 [_townFull]。
  List<Widget> _townTab(FriendsState state) {
    if (_town == null) {
      return const [Center(child: CircularProgressIndicator(color: Color(0xFF7657FF)))];
    }
    return [
      _card(const Text(
        "The town lives on the backend, and it cannot be reached right now.",
        key: Key('town-unreachable'),
        style: TextStyle(color: Colors.white70),
      )),
    ];
  }

  /// 整個畫面的小鎮：地圖鋪滿，上面浮標題與分頁（底下浮一下誰昨晚準時），左下連續晚數＋這週 7 點，右下誰來看過你。
  Widget _townFull(FriendsState state, TownState town) {
    final pad = MediaQuery.paddingOf(context);
    const headerH = 120.0;
    final me = state.me;
    return Stack(
      children: [
        Positioned.fill(
          child: TownMap(
            key: _townMap,
            town: town,
            onTap: _tapTownie,
            onAddFriend: town.friends.length < kTownMaxFriends
                ? () {
                    _selectTab(_Tab.friends);
                    _addFriend();
                  }
                : null,
            covered: EdgeInsets.only(top: pad.top + headerH, bottom: pad.bottom + 70),
          ),
        ),
        // 標題與分頁：上面一層淡淡的深色，字才看得清楚；不擋地圖的滑動（只有字與按鈕吃點擊）
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(0, pad.top + 12, 0, 18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xE6081326), Color(0x00081326)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.fromLTRB(20, 0, 12, 4), child: _titleRow()),
                _pad(_tabs()),
              ],
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          top: pad.top + headerH + 8,
          child: Center(
            child: TownGlowNote(
              key: ValueKey('town-glow-note-${town.night}'),
              names: [for (final p in town.friends) if (p.glow) p.displayName],
              fade: widget.animateScenes,
            ),
          ),
        ),
        Positioned(
          left: 16,
          bottom: pad.bottom + 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 2026-11-22 使用者選：✨ 說明鈕拿掉（它壓到 ＋ Invite）；說明改成進小鎮時浮出的那一行（TownGlowNote）。
              // 連續晚數膠囊旁邊直接畫這週 7 個點（選 B），點了照舊開這一週。
              if (me?.currentStreak != null) ...[
                TownRoundButton(
                  key: const Key('town-streak'),
                  tooltip: '${me!.currentStreak} nights in a row. Open this week',
                  onTap: () => _openMyWeek(me),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.local_fire_department_rounded, color: Color(0xFFFF8A5C), size: 22),
                      const SizedBox(width: 4),
                      Text('${me.currentStreak}',
                          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                      if (me.streakWeek != null && me.streakWeek!.length == 7) ...[
                        const SizedBox(width: 10),
                        StreakWeekDots(key: const Key('town-streak-week'), week: me.streakWeek!),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          right: 16,
          bottom: pad.bottom + 16,
          child: TownRoundButton(
            key: const Key('town-visits-button'),
            tooltip: 'Who stopped by today',
            badge: unseenVisits(town, _visitsSeen),
            onTap: () => _openVisits(town),
            child: const Icon(Icons.favorite_rounded, color: Color(0xFFFF8FB1), size: 24),
          ),
        ),
      ],
    );
  }

  Future<void> _openVisits(TownState town) async {
    final visits = town.visits;
    final unseen = [for (final v in visits) if (!_visitsSeen.contains(v.seenKey(town.day))) v];
    // 打開就算看過（Q12）：先在畫面上歸零，再記到手機上
    setState(() => _visitsSeen = {..._visitsSeen, for (final v in visits) v.seenKey(town.day)});
    VisitsSeenStore(widget.store).markSeen(town.day, visits);
    // 收禮場景（2026-11-22）：還沒看過的先在客廳播一次，按 See all 才接清單；直接關掉就不開清單
    if (widget.animateScenes && unseen.isNotEmpty) {
      final seeAll = await showVisitReceivedScene(
        context,
        visits: unseen,
        me: town.me,
        friends: {for (final p in town.friends) p.handle: p},
        kinds: town.kinds,
      );
      if (seeAll != true || !mounted) return;
    }
    showReportSheet<void>(
      context: context,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF141A45),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        // 底部留系統導覽列的高度（同加朋友面板）
        padding: EdgeInsets.fromLTRB(18, 26, 18, 20 + MediaQuery.paddingOf(context).bottom),
        child: SingleChildScrollView(
          child: visits.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('No one stopped by yet today.',
                      key: Key('town-no-visits'), style: TextStyle(color: Colors.white70, fontSize: 15)),
                )
              : TownVisitsCard(
                  visits: visits,
                  kinds: town.kinds,
                  alreadySent: {for (final p in town.friends) if (p.sent != null) p.handle},
                  onSendBack: widget.service == null
                      ? null
                      : (v) {
                          final friend = town.friends.where((p) => p.handle == v.handle).firstOrNull;
                          if (friend == null) return;
                          Navigator.of(context).pop();
                          _openGifts(friend);
                        },
                ),
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
            paws: c.paws,
            pawSent: c.pawSent || (c.canPaw && _pawPending.contains(c.handle)),
            onPaw: c.canPaw && !c.pawSent && !c.mine && !_pawPending.contains(c.handle)
                ? () => _paw(c)
                : null,
            onSeeWho: c.mine && c.pawFrom.isNotEmpty ? () => _showPawFrom(c) : null,
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

  /// Friends 分頁（2026-11-19 使用者定，第二輪 Q1–Q8）：加朋友＋看朋友現在的狀態。
  /// You 卡 → All／Asleep／Still up（人數寫在上面）→ 依狀態排好的卡片。
  /// 邀請碼搬進標題右邊的「人＋」按鈕、Sleep Circle 拿掉（它講昨晚）、排行榜搬到 Ranks 分頁。
  List<Widget> _friendsTab(FriendsState state, List<FriendSummary> visible) {
    final now = widget.clock();
    if (state.friends.isEmpty) {
      return [
        if (state.me != null)
          YouLiveCard(me: state.me!, now: now, shared: _liveShared, onOpenSharing: _openSharing),
        _emptyFriends(),
      ];
    }
    return [
      if (state.me != null)
        YouLiveCard(me: state.me!, now: now, shared: _liveShared, onOpenSharing: _openSharing),
      _liveTabs(state.friends),
      const SizedBox(height: 14),
      if (visible.isEmpty)
        _card(Text(
          _live == _LiveTab.asleep
              ? "Nobody has tapped Start Sleep yet."
              : "Nobody here right now.",
          key: const Key('friends-filter-empty'),
          style: const TextStyle(color: Colors.white70),
        ))
      else ...[
        for (final f in sortByLiveState(visible))
          FriendLiveCard(friend: f, now: now, onTap: () => _showFriend(f)),
        // 狀態只來自按鈕：沒按的人不代表醒著（「不按也沒關係」）
        const Padding(
          padding: EdgeInsets.only(top: 2, bottom: 8),
          child: Text(
            "Asleep means they tapped Start Sleep. Friends who skip the button may already be asleep. "
            "Bars: when they put the phone down, last 7 nights — taller is later.",
            key: Key('live-note'),
            style: TextStyle(color: Color(0xFF8498B7), fontSize: 11, height: 1.4),
          ),
        ),
      ],
    ];
  }

  /// 沒有朋友（Q7）：睡覺的小狗＋一句話＋大的 Add friend。
  Widget _emptyFriends() => Container(
        key: const Key('friends-empty'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1F4E),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            const HomePet(mood: 'tired', size: 120, animate: false),
            const SizedBox(height: 12),
            const Text("Add a friend to see who's asleep",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text("Share your invite code, or enter theirs.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('empty-add-friend'),
              onPressed: _addFriend,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add friend'),
            ),
          ],
        ),
      );

  /// 照參考圖的膠囊分頁：選中的是實心紫。人數寫在字後面（Q3）。
  Widget _liveTabs(List<FriendSummary> friends) {
    final asleep = friends.where((f) => liveFilterOf(f) == 'asleep').length;
    final up = friends.where((f) => liveFilterOf(f) == 'still_up').length;
    Widget pill(_LiveTab t, String label, int n) {
      final selected = _live == t;
      return Expanded(
        child: InkWell(
          key: Key('live-tab-${t.name}'),
          onTap: () => setState(() => _live = t),
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: selected
                  ? const LinearGradient(colors: [Color(0xFF8B6CFF), Color(0xFF6A4DF0)])
                  : null,
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: label),
                    TextSpan(
                      text: '  $n',
                      style: TextStyle(
                        color: selected ? const Color(0xCCFFFFFF) : const Color(0x80FFFFFF),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]),
                  key: Key('live-count-${t.name}'),
                  softWrap: false,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xCCFFFFFF),
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF161B45),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          pill(_LiveTab.all, 'All', friends.length),
          pill(_LiveTab.asleep, 'Asleep', asleep),
          pill(_LiveTab.stillUp, 'Still up', up),
        ],
      ),
    );
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
}

enum _Tab { town, feed, friends, ranks }

enum _LiveTab { all, asleep, stillUp }
