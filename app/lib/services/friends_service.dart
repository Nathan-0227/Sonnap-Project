import 'live_sleep_status.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'user_identity.dart';

/// 好友：`GET /friends`、`POST /friends`、`DELETE /friends/{邀請碼}`，
/// 以及 2026-11-15 的分享設定（`GET`／`PATCH /sharing`、`/sharing/preview`）與動態卡（`/friends/feed`）。
///
/// ⚠️ 每個人自己選讓好友看到什麼，**選擇與遮蔽全在後端**（social/sharing.py）。
///    App 只畫後端給的；沒給的（None）就不畫，不寫成 0。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 這裡拿到的只有行為指標，而且沒有任何一個別人的 user_id
/// ═══════════════════════════════════════════════════════════════════
///
/// 後端刻意只分享「幾點放下手機」這一類（白名單在 social/friends.py），
/// 不分享分數、深睡、心率——跨裝置不能比，而且是健康資訊。
/// 好友之間的名牌是**邀請碼**（[FriendSummary.handle]），不是 user_id：
/// user_id 本身就是憑證，拿到別人的等於能冒充他。
///
/// ⚠️ 這個檔案一格都不算。連續夜數、熬夜比率、排名，全部照抄後端。

enum FriendsStatus { ok, noBackend, noUser, failed }

@immutable
class FriendsResult<T> {
  final FriendsStatus status;
  final T? value;
  final int? httpStatus;

  /// 後端 `detail` 的原文（英文）。404「沒有這個碼」、409「已經是朋友」、
  /// 422「那是你自己的碼」講的是不同的事，直接顯示、不在 Dart 重寫。
  final String? message;

  const FriendsResult(this.status, {this.value, this.httpStatus, this.message});

  bool get isOk => status == FriendsStatus.ok && value != null;
}

@immutable
class FriendSummary {
  /// 邀請碼。好友之間的名牌。
  final String handle;
  final String displayName;

  /// 行為版心情：'happy' / 'bored' / 'tired'，或 null（最近沒有記錄）。
  final String? petMood;
  final String? lastNightDate;

  /// ISO8601（含 +08:00）。⚠️ 顯示時一律走 parseWallClock()。
  final String? lastLightsOutAt;
  final bool? lastNightLate;

  /// null＝他沒公開連續天數（不是 0）。
  final int? currentStreak;
  final int? bestStreak;

  /// null = 還沒有任何一晚有記錄，或沒公開，不是 0。
  final double? lateNightRatio;
  final int? lateNights;
  final int recordedNights;

  /// 'dog'／'cat'；null＝沒公開（畫小狗）。
  final String? petSpecies;

  /// 這一週（週一→週日）每天的狀態；null＝沒公開準時與否。
  final List<StreakDay>? streakWeek;

  /// 即時狀態（2026-11-19，後端 social/live_status.py 判的，Dart 不重判）：
  /// 'asleep'／'up'／'past_bedtime'／'awake'；null＝他沒打開分享（預設關）。
  final String? liveState;

  /// 那個狀態從幾點開始（牆鐘 ISO，⚠️ 一律 parseWallClock）；awake 是 null。
  final String? liveSince;

  /// 只有 past_bedtime 有：過了他自己的目標幾分鐘（後端算好，目標時刻不分享）。
  final int? minutesPastBedtime;

  /// 最近 7 晚每晚幾點放下手機（舊的在前）；null＝沒公開時刻。
  final List<LightsOutDay>? recentLightsOut;

  const FriendSummary({
    required this.handle,
    required this.displayName,
    required this.petMood,
    required this.lastNightDate,
    required this.lastLightsOutAt,
    required this.lastNightLate,
    required this.currentStreak,
    required this.bestStreak,
    required this.lateNightRatio,
    required this.lateNights,
    required this.recordedNights,
    this.petSpecies,
    this.streakWeek,
    this.liveState,
    this.liveSince,
    this.minutesPastBedtime,
    this.recentLightsOut,
  });

  factory FriendSummary.fromJson(Map<String, dynamic> json) => FriendSummary(
        handle: (json['handle'] as String?) ?? '',
        displayName: (json['display_name'] as String?) ?? '',
        petMood: json['pet_mood'] as String?,
        lastNightDate: json['last_night_date'] as String?,
        lastLightsOutAt: json['last_lights_out_at'] as String?,
        lastNightLate: json['last_night_late'] as bool?,
        currentStreak: (json['current_streak'] as num?)?.toInt(),
        bestStreak: (json['best_streak'] as num?)?.toInt(),
        lateNightRatio: (json['late_night_ratio'] as num?)?.toDouble(),
        lateNights: (json['late_nights'] as num?)?.toInt(),
        recordedNights: (json['recorded_nights'] as num?)?.toInt() ?? 0,
        petSpecies: json['pet_species'] as String?,
        streakWeek: json['streak_week'] is List
            ? [
                for (final d in (json['streak_week'] as List)
                    .whereType<Map<String, dynamic>>())
                  StreakDay(
                    (d['date'] as String?) ?? '',
                    (d['status'] as String?) ?? 'none',
                  ),
              ]
            : null,
        liveState: json['live_state'] as String?,
        liveSince: json['live_since'] as String?,
        minutesPastBedtime: (json['minutes_past_bedtime'] as num?)?.toInt(),
        recentLightsOut: json['recent_lights_out'] is List
            ? [
                for (final d in (json['recent_lights_out'] as List)
                    .whereType<Map<String, dynamic>>())
                  LightsOutDay((d['date'] as String?) ?? '', d['time'] as String?),
              ]
            : null,
      );
}

/// 好友卡右邊那排小長條的一晚：time 是 "HH:MM"，null＝那晚沒資料（不畫成 0）。
class LightsOutDay {
  final String date;
  final String? time;
  const LightsOutDay(this.date, this.time);
}

/// Streak 卡那一排的一天：'on_time'／'late'／'none'（沒資料）／'future'（還沒到）。
@immutable
class StreakDay {
  final String date;
  final String status;
  const StreakDay(this.date, this.status);
}

/// 動態卡：某位朋友某一晚，只有他公開的項目（key 見 social/sharing.py）。
@immutable
class FriendNightCard {
  final String handle;
  final String displayName;
  final String? petSpecies;
  final String date;
  final Map<String, dynamic> items;

  /// 他選的場景（social/sharing.SCENES）；null／不認得 → 畫預設那張。
  final String? scene;

  /// 我自己的卡（後端標的）。內容照我的分享設定＝朋友看到的我。
  final bool mine;

  /// 那一晚收到幾個 🐾（＝那天的拜訪數，2026-11-19）。大家都看得到。
  final int paws;

  /// 這張卡能不能按 🐾（只有朋友「今天」那張；後端判斷）。
  final bool canPaw;

  /// 我今天已經拜訪過他（小鎮或這裡）。
  final bool pawSent;

  /// 是誰給的。**只有我自己的卡有**（後端只給卡片主人）。
  final List<String> pawFrom;

  const FriendNightCard({
    required this.handle,
    required this.displayName,
    required this.date,
    required this.items,
    this.petSpecies,
    this.scene,
    this.mine = false,
    this.paws = 0,
    this.canPaw = false,
    this.pawSent = false,
    this.pawFrom = const [],
  });

  factory FriendNightCard.fromJson(Map<String, dynamic> json) => FriendNightCard(
        handle: (json['handle'] as String?) ?? '',
        displayName: (json['display_name'] as String?) ?? '',
        petSpecies: json['pet_species'] as String?,
        date: (json['date'] as String?) ?? '',
        items: ((json['items'] as Map?) ?? const {}).cast<String, dynamic>(),
        scene: json['scene'] as String?,
        mine: json['mine'] == true,
        paws: (json['paws'] as num?)?.toInt() ?? 0,
        canPaw: json['can_paw'] == true,
        pawSent: json['paw_sent'] == true,
        pawFrom: [
          for (final n in (json['paw_from'] as List?) ?? const [])
            if (n is String) n,
        ],
      );
}

@immutable
class SharingItem {
  final String key;
  final String label;
  final bool enabled;
  const SharingItem(this.key, this.label, this.enabled);
}

@immutable
class SharingGroup {
  final String id;
  final String label;
  final List<SharingItem> items;
  const SharingGroup(this.id, this.label, this.items);
}

/// GET／PATCH /sharing 的回應。
@immutable
class SharingSettings {
  final List<SharingGroup> groups;

  /// 'exact'／'on_time_only'
  final String timePrecision;
  final String petSpecies;

  /// 動態卡的場景與可選的清單（後端定，Dart 不寫死有哪幾張）。
  final String scene;
  final List<String> scenes;

  /// 永遠不給的三項（只是說明，不是選項）。
  final List<String> neverShared;

  const SharingSettings({
    required this.groups,
    required this.timePrecision,
    required this.petSpecies,
    required this.neverShared,
    this.scene = 'campfire',
    this.scenes = const [],
  });

  factory SharingSettings.fromJson(Map<String, dynamic> json) => SharingSettings(
        groups: [
          for (final g in ((json['groups'] as List?) ?? const [])
              .whereType<Map<String, dynamic>>())
            SharingGroup(
              (g['id'] as String?) ?? '',
              (g['label'] as String?) ?? '',
              [
                for (final i in ((g['items'] as List?) ?? const [])
                    .whereType<Map<String, dynamic>>())
                  SharingItem(
                    (i['key'] as String?) ?? '',
                    (i['label'] as String?) ?? '',
                    i['enabled'] == true,
                  ),
              ],
            ),
        ],
        timePrecision: (json['time_precision'] as String?) ?? 'exact',
        scene: (json['scene'] as String?) ?? 'campfire',
        scenes: [for (final x in (json['scenes'] as List?) ?? const []) if (x is String) x],
        petSpecies: (json['pet_species'] as String?) ?? 'dog',
        neverShared: [
          for (final s in ((json['never_shared'] as List?) ?? const []))
            if (s is String) s,
        ],
      );
}

@immutable
class LeaderboardEntry {
  final int rank;
  final String handle;
  final String displayName;
  final int currentStreak;
  final int bestStreak;

  const LeaderboardEntry({
    required this.rank,
    required this.handle,
    required this.displayName,
    required this.currentStreak,
    required this.bestStreak,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) => LeaderboardEntry(
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        handle: (json['handle'] as String?) ?? '',
        displayName: (json['display_name'] as String?) ?? '',
        currentStreak: (json['current_streak'] as num?)?.toInt() ?? 0,
        bestStreak: (json['best_streak'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class FriendsState {
  final String myInviteCode;

  /// 我自己（不遮），好友頁最上面那張 Streak 卡用。
  final FriendSummary? me;
  final List<FriendSummary> friends;

  /// ⚠️ 已經由後端排好。Dart 不重排——同分怎麼排是後端的規則。
  final List<LeaderboardEntry> leaderboard;
  final Map<String, String> notes;

  const FriendsState({
    required this.myInviteCode,
    this.me,
    required this.friends,
    required this.leaderboard,
    required this.notes,
  });

  factory FriendsState.fromJson(Map<String, dynamic> json) => FriendsState(
        myInviteCode: (json['my_invite_code'] as String?) ?? '',
        me: json['me'] is Map<String, dynamic>
            ? FriendSummary.fromJson(json['me'] as Map<String, dynamic>)
            : null,
        friends: ((json['friends'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(FriendSummary.fromJson)
            .toList(),
        leaderboard: ((json['leaderboard'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LeaderboardEntry.fromJson)
            .toList(),
        notes: {
          for (final e in ((json['notes'] as Map?) ?? const {}).entries)
            if (e.value is String) '${e.key}': e.value as String,
        },
      );
}

/// 排行榜上的一個人（上榜的有名次；不到門檻的 rank 是 null）。
@immutable
class RankedFriend {
  final String handle;
  final String displayName;
  final bool mine;
  final bool demo;
  final String? petSpecies;
  final String? petMood;
  final int? rank;
  final String? display;
  final int nights;

  /// 跟上一個時段比：正＝名次往上、負＝往下、0＝不變、null＝上個時段沒上榜。
  final int? change;

  const RankedFriend({
    required this.handle,
    required this.displayName,
    this.mine = false,
    this.demo = false,
    this.petSpecies,
    this.petMood,
    this.rank,
    this.display,
    this.nights = 0,
    this.change,
  });

  factory RankedFriend.fromJson(Map<String, dynamic> j) => RankedFriend(
        handle: (j['handle'] as String?) ?? '',
        displayName: (j['display_name'] as String?) ?? '',
        mine: j['mine'] == true,
        demo: j['demo'] == true,
        petSpecies: j['pet_species'] as String?,
        petMood: j['pet_mood'] as String?,
        rank: (j['rank'] as num?)?.toInt(),
        display: j['display'] as String?,
        nights: (j['nights'] as num?)?.toInt() ?? 0,
        change: (j['change'] as num?)?.toInt(),
      );
}

/// 一張排行榜（一個指標 × 一個時段）。
@immutable
class LeaderboardBoard {
  final String metric;
  final String period;
  final String label;
  final String title;
  final int need;

  /// 'night' 或 'day'（步數、壓力數天）。照抄後端，舊版後端沒給就當 night。
  final String unit;
  final List<(String, String)> metrics;
  final List<(String, String)> periods;
  final List<RankedFriend> entries;
  final List<RankedFriend> below;

  /// 我自己：ranked／below／not_sharing。
  final String meStatus;
  final RankedFriend? me;
  final String? shareLabel;

  const LeaderboardBoard({
    required this.metric,
    required this.period,
    required this.label,
    required this.title,
    required this.need,
    this.unit = 'night',
    required this.metrics,
    required this.periods,
    required this.entries,
    required this.below,
    required this.meStatus,
    this.me,
    this.shareLabel,
  });

  factory LeaderboardBoard.fromJson(Map<String, dynamic> j) {
    List<(String, String)> pairs(dynamic v) => [
          for (final m in (v as List? ?? const []).whereType<Map>())
            ((m['key'] as String?) ?? '', (m['label'] as String?) ?? ''),
        ];
    List<RankedFriend> people(dynamic v) => [
          for (final e in (v as List? ?? const []).whereType<Map<String, dynamic>>())
            RankedFriend.fromJson(e),
        ];
    final me = (j['me'] as Map?)?.cast<String, dynamic>() ?? const {};
    final status = (me['status'] as String?) ?? 'not_sharing';
    return LeaderboardBoard(
      metric: (j['metric'] as String?) ?? '',
      period: (j['period'] as String?) ?? '',
      label: (j['label'] as String?) ?? '',
      title: (j['title'] as String?) ?? '',
      need: (j['need'] as num?)?.toInt() ?? 1,
      unit: (j['unit'] as String?) == 'day' ? 'day' : 'night',
      metrics: pairs(j['metrics']),
      periods: pairs(j['periods']),
      entries: people(j['entries']),
      below: people(j['below']),
      meStatus: status,
      me: status == 'not_sharing' ? null : RankedFriend.fromJson(me),
      shareLabel: me['share_label'] as String?,
    );
  }
}

/// 好友小鎮的一個人（`GET /friends/town`，2026-11-17）。
///
/// ⚠️ 沒發光的三種情況（晚了、沒資料、沒分享）後端給的一模一樣——只有 `glow: false`，
///    不給原因。畫面也就畫得一模一樣，不要在這裡加任何能分辨它們的東西。
@immutable
class TownPerson {
  final String handle;
  final String displayName;
  final bool mine;
  final bool demo;

  /// 'dog'／'cat'；null＝畫小狗。
  final String? petSpecies;

  /// 只有他有分享心情才有（自己的照給）；只用在點開的小卡上，小鎮裡不畫心情。
  final String? petMood;
  final bool glow;

  /// 我今天送過他什麼（'pet'…）；null＝還沒送。自己永遠是 null。
  final String? sent;

  /// 他今天送過我什麼；null＝沒送。地圖上他頭頂冒那個小圖示（只是裝飾，2026-11-22）。
  final String? visitedMe;

  /// 他昨晚的卡（只有他打開的項目）；null＝不畫「See last night」。
  final FriendNightCard? card;

  const TownPerson({
    required this.handle,
    required this.displayName,
    this.mine = false,
    this.demo = false,
    this.petSpecies,
    this.petMood,
    this.glow = false,
    this.sent,
    this.visitedMe,
    this.card,
  });

  factory TownPerson.fromJson(Map<String, dynamic> j) {
    final handle = (j['handle'] as String?) ?? '';
    final name = (j['display_name'] as String?) ?? '';
    final species = j['pet_species'] as String?;
    final mine = j['mine'] == true;
    final c = j['card'];
    return TownPerson(
      handle: handle,
      displayName: name,
      mine: mine,
      demo: j['demo'] == true,
      petSpecies: species,
      petMood: j['pet_mood'] as String?,
      glow: j['glow'] == true,
      sent: j['sent'] as String?,
      visitedMe: j['visited_me'] as String?,
      card: c is Map
          ? FriendNightCard.fromJson({
              'handle': handle,
              'display_name': name,
              'pet_species': species,
              'mine': mine,
              ...c.cast<String, dynamic>(),
            })
          : null,
    );
  }
}

/// 今天來看過我的人。message 照抄後端（字只在 social/town.py）。
@immutable
class TownVisit {
  final String displayName;
  final String kind;
  final String message;

  /// 送的人的邀請碼（Send back 用）；舊版後端沒給是 null → 不畫 Send back。
  final String? handle;

  /// 送的人的寵物（列表上畫他的頭）。
  final String? petSpecies;

  const TownVisit(this.displayName, this.kind, this.message, {this.handle, this.petSpecies});

  /// 「看過了沒」的鍵：一個人一天只能送一次，所以 起床日＋送的人 就分得開。
  String seenKey(String day) => '$day|${handle ?? displayName}';
}

@immutable
class TownState {
  final String night;

  /// 拜訪算哪一天（起床日，後端 social/town.visit_day）。「看過了沒」用它分天。
  final String day;

  /// 我＋朋友，順序照後端（我第一個、朋友照加好友的先後）。誰放哪裡由畫面決定。
  final List<TownPerson> people;
  final List<TownVisit> visits;

  /// 拜訪的動作：(key, 按鈕上的字)，順序與字都照抄後端（2026-11-22 起 9 種）。
  final List<(String, String)> kinds;

  /// 送禮頁上你的寵物說的那句，{friend} 換成朋友的名字（照抄後端 social/town.KINDS）。
  /// 舊版後端沒給 → 空的，送禮頁的泡泡退回朋友的名字。
  final Map<String, String> invites;

  const TownState({
    required this.night,
    required this.people,
    this.day = '',
    this.visits = const [],
    this.kinds = const [],
    this.invites = const {},
  });

  TownPerson? get me => people.where((p) => p.mine).firstOrNull;
  List<TownPerson> get friends => [for (final p in people) if (!p.mine) p];

  factory TownState.fromJson(Map<String, dynamic> j) => TownState(
        night: (j['night'] as String?) ?? '',
        day: (j['day'] as String?) ?? '',
        people: [
          for (final p in ((j['people'] as List?) ?? const []).whereType<Map<String, dynamic>>())
            TownPerson.fromJson(p),
        ],
        visits: [
          for (final v in ((j['visits'] as List?) ?? const []).whereType<Map<String, dynamic>>())
            TownVisit((v['display_name'] as String?) ?? '', (v['kind'] as String?) ?? '',
                (v['message'] as String?) ?? '',
                handle: v['handle'] as String?, petSpecies: v['pet_species'] as String?),
        ],
        kinds: [
          for (final k in ((j['kinds'] as List?) ?? const []).whereType<Map<String, dynamic>>())
            ((k['key'] as String?) ?? '', (k['label'] as String?) ?? ''),
        ],
        invites: {
          for (final k in ((j['kinds'] as List?) ?? const []).whereType<Map<String, dynamic>>())
            if (k['key'] is String && k['invite'] is String) k['key'] as String: k['invite'] as String,
        },
      );
}

class FriendsService {
  final String baseUrl;
  final UserIdentity identity;
  final Duration timeout;

  const FriendsService({
    required this.baseUrl,
    required this.identity,
    this.timeout = const Duration(seconds: 3),
  });

  Future<FriendsResult<FriendsState>> fetch() async {
    final r = await _request('GET', '/friends');
    if (!r.isOk) return FriendsResult(r.status, httpStatus: r.httpStatus, message: r.message);
    return FriendsResult(FriendsStatus.ok, value: FriendsState.fromJson(r.value!));
  }

  /// 朋友們最近 7 天每一晚的卡（新的在前）。
  /// 動態牆比別的端點慢（每位朋友每一晚都要組一次 /home），3 秒常常不夠——
  /// 2026-11-16 實機：後端 6.3 秒、App 3 秒就放棄，畫面只說「沒有動態」，看起來像沒有朋友的資料。
  static const feedTimeout = Duration(seconds: 15);

  Future<FriendsResult<List<FriendNightCard>>> fetchFeed() async {
    final r = await _request('GET', '/friends/feed', wait: feedTimeout);
    if (!r.isOk) return FriendsResult(r.status, httpStatus: r.httpStatus, message: r.message);
    return FriendsResult(FriendsStatus.ok, value: [
      for (final c in ((r.value!['cards'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>())
        FriendNightCard.fromJson(c),
    ]);
  }

  /// 好友排行榜（第二批）。名次、門檻、並列、名次變化全在後端算，Dart 照抄、不重排。
  /// period 給 null＝那個指標預設的時段。比別的端點慢（每個人要撈一年的資料），用動態牆的等待時間。
  Future<FriendsResult<LeaderboardBoard>> fetchLeaderboard(
    String metric, {
    String? period,
  }) async {
    final r = await _request(
      'GET',
      '/friends/leaderboard',
      query: {'metric': metric, 'period': ?period},
      wait: feedTimeout,
    );
    if (!r.isOk) return FriendsResult(r.status, httpStatus: r.httpStatus, message: r.message);
    return FriendsResult(FriendsStatus.ok, value: LeaderboardBoard.fromJson(r.value!));
  }

  /// 好友小鎮。比一般端點慢（每個人要組一次昨晚的卡），用動態牆的等待時間。
  Future<FriendsResult<TownState>> fetchTown() async {
    final r = await _request('GET', '/friends/town', wait: feedTimeout);
    if (!r.isOk) return FriendsResult(r.status, httpStatus: r.httpStatus, message: r.message);
    return FriendsResult(FriendsStatus.ok, value: TownState.fromJson(r.value!));
  }

  /// 拜訪朋友（摸摸或一句話）。一天一次：第二次後端回 409，message 照抄後端那句。
  Future<FriendsResult<String>> visit(String handle, String kind) async {
    final r = await _request('POST', '/friends/${Uri.encodeComponent(handle)}/visit', body: {'kind': kind});
    if (!r.isOk) return FriendsResult(r.status, httpStatus: r.httpStatus, message: r.message);
    return FriendsResult(FriendsStatus.ok, value: (r.value!['sent'] as String?) ?? kind);
  }

  /// 一位朋友：摘要＋最近一晚的卡（可能沒有）。
  Future<FriendsResult<(FriendSummary, FriendNightCard?)>> fetchFriend(String handle) async {
    final r = await _request('GET', '/friends/${Uri.encodeComponent(handle)}');
    if (!r.isOk) return FriendsResult(r.status, httpStatus: r.httpStatus, message: r.message);
    return FriendsResult(FriendsStatus.ok, value: _summaryAndCard(r.value!));
  }

  /// 我讓好友看到什麼。
  Future<FriendsResult<SharingSettings>> fetchSharing() async {
    final r = await _request('GET', '/sharing');
    if (!r.isOk) return FriendsResult(r.status, httpStatus: r.httpStatus, message: r.message);
    return FriendsResult(FriendsStatus.ok, value: SharingSettings.fromJson(r.value!));
  }

  /// 改分享設定（只送有改的）。
  Future<FriendsResult<SharingSettings>> patchSharing({
    Map<String, bool>? items,
    String? timePrecision,
    String? petSpecies,
    String? scene,
  }) async {
    final r = await _request('PATCH', '/sharing', body: {
      'items': ?items,
      'time_precision': ?timePrecision,
      'pet_species': ?petSpecies,
      'scene': ?scene,
    });
    if (!r.isOk) return FriendsResult(r.status, httpStatus: r.httpStatus, message: r.message);
    return FriendsResult(FriendsStatus.ok, value: SharingSettings.fromJson(r.value!));
  }

  /// 朋友看到的我（設定頁的預覽）。
  Future<FriendsResult<(FriendSummary, FriendNightCard?)>> fetchPreview() async {
    final r = await _request('GET', '/sharing/preview');
    if (!r.isOk) return FriendsResult(r.status, httpStatus: r.httpStatus, message: r.message);
    return FriendsResult(FriendsStatus.ok, value: _summaryAndCard(r.value!));
  }

  static (FriendSummary, FriendNightCard?) _summaryAndCard(Map<String, dynamic> v) {
    final f = FriendSummary.fromJson((v['friend'] as Map?)?.cast<String, dynamic>() ?? const {});
    final c = v['card'];
    return (
      f,
      c is Map
          ? FriendNightCard.fromJson({
              'handle': f.handle,
              'display_name': f.displayName,
              'pet_species': f.petSpecies,
              ...c.cast<String, dynamic>(),
            })
          : null,
    );
  }

  /// 用邀請碼加好友。成功時 value 是那位朋友的摘要。
  Future<FriendsResult<FriendSummary>> add(String inviteCode) async {
    final r = await _request('POST', '/friends', body: {'invite_code': inviteCode.trim()});
    if (!r.isOk) return FriendsResult(r.status, httpStatus: r.httpStatus, message: r.message);
    final friend = r.value!['friend'];
    if (friend is! Map<String, dynamic>) return const FriendsResult(FriendsStatus.failed);
    return FriendsResult(FriendsStatus.ok, value: FriendSummary.fromJson(friend));
  }

  Future<FriendsResult<String>> remove(String handle) async {
    final r = await _request('DELETE', '/friends/${Uri.encodeComponent(handle)}');
    if (!r.isOk) return FriendsResult(r.status, httpStatus: r.httpStatus, message: r.message);
    return FriendsResult(FriendsStatus.ok, value: (r.value!['removed'] as String?) ?? handle);
  }

  /// 即時狀態（[SleepStatusSink] 的實作）。只試一次、不補送。
  /// 回應裡的攝影機狀態放進 [cameraStatusBoard]（睡覺畫面讀它）。
  /// ⚠️ start 的逾時比較長：後端開錄之後要等錄影程式接上攝影機（最多約 8 秒）。
  /// ⚠️ 簽名不要加參數：測試裡有假的服務覆寫這個方法。
  Future<void> sendSleepStatus(String event, DateTime? at) async {
    final target = cameraStatusBoard;
    if (event == 'start') target.value = null; // 不顯示上一晚的
    final r = await _request(
      'POST',
      '/sleep-status',
      body: {'event': event, if (at != null) 'at': wallClockIso(at)},
      wait: Duration(seconds: event == 'start' ? 12 : 5),
    );
    target.value = r.isOk ? CameraStatus.fromJson(r.value!['camera']) : null;
  }

  /// ⚠️ user_id：GET／DELETE 放 query、POST 放 body（後端定的介面）。
  ///    它本身就是憑證——不印進 log、不放進錯誤訊息。
  Future<FriendsResult<Map<String, dynamic>>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration? wait,
    Map<String, String>? query,
  }) async {
    final timeout = wait ?? this.timeout;
    if (baseUrl.trim().isEmpty) return const FriendsResult(FriendsStatus.noBackend);
    final userId = await identity.currentUserId();
    if (userId == null) return const FriendsResult(FriendsStatus.noUser);

    final base = Uri.parse('$baseUrl$path');
    final hasBody = method == 'POST' || method == 'PATCH';
    final uri = hasBody
        ? base
        : base.replace(queryParameters: {...?query, 'user_id': userId});
    final client = HttpClient()..connectionTimeout = timeout;

    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      if (hasBody) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({'user_id': userId, ...?body}));
      }
      final response = await request.close().timeout(timeout);
      final text = await response.transform(utf8.decoder).join();
      final decoded = text.isEmpty ? null : jsonDecode(text);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = decoded is Map ? decoded['detail'] : null;
        return FriendsResult(
          FriendsStatus.failed,
          httpStatus: response.statusCode,
          message: detail is String ? detail : null,
        );
      }
      if (decoded is! Map<String, dynamic>) {
        return FriendsResult(FriendsStatus.failed, httpStatus: response.statusCode);
      }
      return FriendsResult(FriendsStatus.ok, value: decoded, httpStatus: response.statusCode);
    } catch (error) {
      debugPrint('Friends: $method $path failed - $error');
      return const FriendsResult(FriendsStatus.failed);
    } finally {
      client.close(force: true);
    }
  }
}
