// 動態卡（2026-11-15 使用者定，參考 Strava）：朋友那一晚的資料上傳後出現一張卡，
// **只放他公開的項目**＋寵物。key 與值的形狀在 social/sharing.py。
//
// - 這裡一格都不算：數字照抄後端（後端從他自己的 /home 挑的，跟他的報告同一份）
// - 沒給的項目不畫，不寫成 0
// - 不判斷好壞：不寫 good／bad、分數不變色、晚了只寫 Late（不用紅色）
// - 2026-11-16 改版（使用者定 B 版）：每張卡是他自己選的場景（像大頭貼，不依心情換），
//   寵物直接站在畫面裡、不放圓框；不再是一堆小膠囊，其他項目合成一行小字
import 'package:flutter/material.dart';

import '../services/friends_service.dart';
import '../services/night_compare.dart' show formatMinutes;
import 'streak_card.dart' show PetWithFlames, StreakWeekRow, speciesOf;

const _nightKeys = [
  'phone_down_time',
  'on_time',
  'target_bedtime',
  'phone_after_start',
  'prebed_phone',
  'score',
  'sleep_duration',
  'bed_times',
  'time_in_bed',
  'fell_asleep',
  'awake',
  'stages',
  'efficiency',
  'camera_moves',
  'morning_rating',
  'sleeping_hr',
  'resting_hr',
];
const _dayKeys = [
  'steps',
  'calories',
  'active_time',
  'move_iq',
  'stress',
  'awake_hr',
  'body_battery',
  'vo2max',
];
const _gameKeys = ['level', 'outfit', 'challenges'];

num? _n(dynamic v) => v is num ? v : null;
String _m(dynamic v) => formatMinutes((_n(v) ?? 0).toDouble());
String _int(num v) {
  final s = v.round().toString();
  return s.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
}

/// 一項 → 一行字；值的形狀不對或沒值 → null（不畫）。
String? friendItemLine(String key, dynamic v) {
  if (v == null) return null;
  Map<String, dynamic> m() => (v as Map).cast<String, dynamic>();
  switch (key) {
    case 'phone_down_time':
      return 'Phone down $v';
    case 'on_time':
      return v == true ? 'On time' : 'Late';
    case 'target_bedtime':
      return 'Target $v';
    case 'phone_after_start':
      return 'Phone ${_m(v)} after Start Sleep';
    case 'prebed_phone':
      return 'Phone ${_m(v)} in the hour before bed';
    case 'score':
      final s = _n(m()['score']);
      final q = m()['quality'];
      return s == null
          ? null
          : 'Score ${s.round()}${q is String ? ' · $q' : ''}';
    case 'sleep_duration':
      return 'Asleep ${_m(v)}';
    case 'bed_times':
      return 'In bed ${m()['start'] ?? '—'} → ${m()['end'] ?? '—'}';
    case 'time_in_bed':
      return '${_m(v)} in bed';
    case 'fell_asleep':
      return 'Fell asleep in ${_m(v)}';
    case 'awake':
      final c = _n(m()['count']);
      final mins = _n(m()['minutes']);
      return [
        if (c != null) 'Woke up ${c.round()} ${c == 1 ? 'time' : 'times'}',
        if (mins != null) '${_m(mins)} awake',
      ].join(' · ');
    case 'stages':
      return [
        for (final k in ['deep', 'light', 'rem'])
          if (_n(m()[k]) != null)
            '${k == 'rem' ? 'REM' : '${k[0].toUpperCase()}${k.substring(1)}'} ${_m(m()[k])}',
      ].join(' · ');
    case 'efficiency':
      final e = _n(m()['value']);
      final l = m()['label'];
      if (e == null) return null;
      final s = e == e.roundToDouble() ? e.round().toString() : e.toString();
      return 'Efficiency $s%${l is String ? ' ($l)' : ''}';
    case 'camera_moves':
      return '${(_n(v) ?? 0).round()} moves / hour (camera)';
    case 'morning_rating':
      final l = m()['label'];
      return l is String ? 'Felt: $l' : null;
    case 'sleeping_hr':
      final a = _n(m()['avg']);
      final lo = _n(m()['min']);
      return a == null
          ? null
          : 'Sleeping HR ${a.round()} bpm${lo == null ? '' : ' · low ${lo.round()}'}';
    case 'resting_hr':
      return 'Resting HR ${(_n(v) ?? 0).round()} bpm';
    case 'steps':
      final st = _n(m()['steps']);
      final d = _n(m()['distance_m']);
      final f = _n(m()['floors']);
      return [
        if (st != null) '${_int(st)} steps',
        if (d != null) '${(d / 1000).toStringAsFixed(1)} km',
        if (f != null) '${f.round()} floors',
      ].join(' · ');
    case 'calories':
      final a = _n(m()['active']);
      final t = _n(m()['total']);
      return [
        if (a != null) '${_int(a)} active kcal',
        if (t != null) '${_int(t)} total',
      ].join(' · ');
    case 'active_time':
      final hi = _n(m()['highly_active']);
      final ac = _n(m()['active']);
      if (hi == null && ac == null) return null;
      return 'Active ${_m(((hi ?? 0) + (ac ?? 0)) / 60)}${hi == null ? '' : ' · high ${_m(hi / 60)}'}';
    case 'move_iq':
      final c = _n(m()['count']) ?? 0;
      return '${c.round()} ${c == 1 ? 'walk' : 'walks'} · ${_m(m()['minutes'])}';
    case 'stress':
      final parts = [
        for (final k in ['rest', 'low', 'medium', 'high'])
          if (_n(m()[k]) != null) '$k ${_m(_n(m()[k])! / 60)}',
      ];
      return parts.isEmpty ? null : 'Stress · ${parts.join(' · ')}';
    case 'awake_hr':
      final a = _n(m()['avg']);
      final mx = _n(m()['max']);
      return a == null
          ? null
          : 'Awake HR ${a.round()} bpm${mx == null ? '' : ' · peak ${mx.round()}'}';
    case 'body_battery':
      final c = _n(m()['charged']);
      final d = _n(m()['drained']);
      return 'Body Battery${c == null ? '' : ' +${c.round()}'}${d == null ? '' : ' −${d.round()}'}';
    case 'vo2max':
      return 'VO2 max ${_n(v)?.round()}';
    case 'level':
      final l = _n(m()['level']);
      final xp = _n(m()['xp_total']);
      return [
        if (l != null) 'Lv ${l.round()}',
        if (xp != null) '${_int(xp)} XP',
      ].join(' · ');
    case 'outfit':
      final b = _n(m()['badges']);
      return b == null || b == 0
          ? null
          : '${b.round()} ${b == 1 ? 'badge' : 'badges'}';
    case 'challenges':
      if (v is! List) return null;
      final all = v
          .whereType<Map>()
          .where((c) => c['title'] is String)
          .toList();
      final done = [
        for (final c in all)
          if (c['completed'] == true) c['title'] as String,
      ];
      final open = all.length - done.length;
      return [
        if (done.isNotEmpty) 'Done: ${done.join(', ')}',
        if (open > 0) '$open in progress',
      ].join(' · ');
  }
  return null;
}

String friendCardDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}';
}

/// 卡片上方的三個大數字：照這個順序挑他有公開的前三個。
/// 卡上的大數字（2026-11-16 使用者定）：只放這三個（預設分享、可以關），有公開哪個放哪個，
/// 其他的點進去看。效率試過放第四個，太擠，拿掉了。
const _statOrder = ['sleep_duration', 'camera_moves', 'score'];

/// 三個都被關掉時，卡上不能一個數字都沒有 → 退回行為那兩項（也是預設分享的）。
const _statFallback = ['phone_down_time', 'on_time'];

/// 一項 → 大數字（標籤, 值）；沒值 → null。
(String, String)? friendStat(String key, dynamic v) {
  if (v == null) return null;
  switch (key) {
    case 'sleep_duration':
      return _n(v) == null ? null : ('Asleep', _m(v));
    case 'time_in_bed':
      return _n(v) == null ? null : ('In bed', _m(v));
    case 'phone_down_time':
      return v is String ? ('Phone down', v) : null;
    case 'on_time':
      return v is bool ? ('Bedtime', v ? 'On time' : 'Late') : null;
    case 'score':
      final s = v is Map ? _n(v['score']) : null;
      return s == null ? null : ('Score', '${s.round()}');
    case 'camera_moves':
      return _n(v) == null ? null : ('Moves/hr', '${_n(v)!.round()}');
    case 'steps':
      final s = v is Map ? _n(v['steps']) : null;
      return s == null ? null : ('Steps', _int(s));
  }
  return null;
}

/// 大數字底下那排小格：照這個順序挑他有公開、而且沒變成大數字的前三個（2026-11-16 使用者定 B 版）。
/// 其他的不畫在卡上，點卡片（See all）看全部。
const _tileOrder = [
  'awake',
  'sleeping_hr',
  'steps',
  'stress',
  'score',
  'fell_asleep',
  'efficiency',
  'resting_hr',
  'body_battery',
  'active_time',
  'calories',
  'move_iq',
  'prebed_phone',
  'phone_after_start',
  'level',
  'outfit',
  'challenges',
];
const kMaxTiles = 3;

/// 一項 → 小格（圖示, 數字, 小標籤）；沒值 → null。不判斷好壞、不變色。
(IconData, String, String)? friendTile(String key, dynamic v) {
  if (v == null) return null;
  Map<String, dynamic> m() => v is Map ? v.cast<String, dynamic>() : const {};
  switch (key) {
    case 'phone_down_time':
      return v is String
          ? (Icons.phone_android_rounded, v, 'phone down')
          : null;
    case 'on_time':
      return v is bool
          ? (Icons.schedule_rounded, v ? 'On time' : 'Late', 'bedtime')
          : null;
    case 'target_bedtime':
      return v is String ? (Icons.flag_outlined, v, 'target bedtime') : null;
    case 'sleep_duration':
      return _n(v) == null ? null : (Icons.nightlight_round, _m(v), 'asleep');
    case 'time_in_bed':
      return _n(v) == null ? null : (Icons.bed_rounded, _m(v), 'in bed');
    case 'bed_times':
      final a = m()['start'], b = m()['end'];
      return a is! String && b is! String
          ? null
          : (Icons.bed_rounded, '${a ?? '—'}–${b ?? '—'}', 'in bed');
    case 'stages':
      final d = _n(m()['deep']);
      return d == null ? null : (Icons.water_drop_rounded, _m(d), 'deep sleep');
    case 'awake_hr':
      final a = _n(m()['avg']);
      return a == null
          ? null
          : (Icons.monitor_heart_rounded, '${a.round()}', 'awake bpm');
    case 'vo2max':
      return _n(v) == null
          ? null
          : (Icons.air_rounded, '${_n(v)!.round()}', 'VO2 max');
    case 'camera_moves':
      return _n(v) == null
          ? null
          : (Icons.videocam_rounded, '${_n(v)!.round()}', 'moves / hour');
    case 'morning_rating':
      final l = m()['label'];
      return l is String
          ? (Icons.sentiment_satisfied_rounded, l, 'felt')
          : null;
    case 'awake':
      final c = _n(m()['count']);
      final mins = _n(m()['minutes']);
      if (c != null) return (Icons.bedtime_rounded, '${c.round()}×', 'woke up');
      return mins == null ? null : (Icons.bedtime_rounded, _m(mins), 'awake');
    case 'sleeping_hr':
      final a = _n(m()['avg']);
      return a == null
          ? null
          : (Icons.favorite_rounded, '${a.round()}', 'sleeping bpm');
    case 'steps':
      final st = _n(m()['steps']);
      return st == null
          ? null
          : (Icons.directions_walk_rounded, _int(st), 'steps');
    case 'stress':
      final hi = _n(m()['high']);
      return hi == null
          ? null
          : (Icons.waves_rounded, _m(hi / 60), 'high stress');
    case 'score':
      final sc = _n(m()['score']);
      return sc == null ? null : (Icons.star_rounded, '${sc.round()}', 'score');
    case 'fell_asleep':
      return _n(v) == null
          ? null
          : (Icons.hourglass_bottom_rounded, _m(v), 'to fall asleep');
    case 'efficiency':
      final e = _n(m()['value']);
      return e == null
          ? null
          : (Icons.pie_chart_rounded, '${e.round()}%', 'efficiency');
    case 'resting_hr':
      return _n(v) == null
          ? null
          : (Icons.favorite_border_rounded, '${_n(v)!.round()}', 'resting bpm');
    case 'body_battery':
      final c = _n(m()['charged']);
      return c == null
          ? null
          : (
              Icons.battery_charging_full_rounded,
              '+${c.round()}',
              'body battery',
            );
    case 'active_time':
      final hi = _n(m()['highly_active']) ?? 0;
      final ac = _n(m()['active']);
      return ac == null
          ? null
          : (Icons.bolt_rounded, _m((hi + ac) / 60), 'active');
    case 'calories':
      final a = _n(m()['active']);
      return a == null
          ? null
          : (Icons.local_fire_department_outlined, _int(a), 'active kcal');
    case 'move_iq':
      final c = _n(m()['count']);
      return c == null
          ? null
          : (Icons.hiking_rounded, '${c.round()}', c == 1 ? 'walk' : 'walks');
    case 'prebed_phone':
      return _n(v) == null
          ? null
          : (Icons.phone_iphone_rounded, _m(v), 'phone before bed');
    case 'phone_after_start':
      return _n(v) == null
          ? null
          : (Icons.phone_iphone_rounded, _m(v), 'phone in bed');
    case 'level':
      final l = _n(m()['level']);
      return l == null
          ? null
          : (Icons.military_tech_rounded, 'Lv ${l.round()}', 'level');
    case 'outfit':
      final b = _n(m()['badges']);
      return b == null || b == 0
          ? null
          : (
              Icons.workspace_premium_rounded,
              '${b.round()}',
              b == 1 ? 'badge' : 'badges',
            );
    case 'challenges':
      if (v is! List) return null;
      final all = v
          .whereType<Map>()
          .where((c) => c['title'] is String)
          .toList();
      if (all.isEmpty) return null;
      final done = all.where((c) => c['completed'] == true).length;
      return (Icons.flag_rounded, '$done/${all.length}', 'challenges');
  }
  return null;
}

/// 卡片上的大數字、小格、還沒畫出來的項目。卡片與「See all」共用同一份挑法。
({
  List<(String, String, String)> stats,
  List<(String, IconData, String, String)> tiles,
  int more,
})
friendCardLayout(
  Map<String, dynamic> items, {
  bool hasChart = false,
  bool expanded = false,
}) {
  final stats = <(String, String, String)>[];
  for (final k in _statOrder) {
    if (friendStat(k, items[k]) case (final label, final value)) {
      stats.add((k, label, value));
    }
  }
  if (stats.isEmpty) {
    for (final k in _statFallback) {
      if (friendStat(k, items[k]) case (final label, final value)) {
        stats.add((k, label, value));
      }
    }
  }
  final used = {for (final s in stats) s.$1};
  final tiles = <(String, IconData, String, String)>[];
  final order = expanded
      ? [..._nightKeys, ..._dayKeys, ..._gameKeys]
      : _tileOrder;
  for (final k in order) {
    if (!expanded) break;
    if (k == 'stages' && hasChart) {
      // 完整頁：圖上看不出幾分鐘，深睡／淺睡／REM 各一格（卡片上不放，避免太擠）
      if (expanded && items['stages'] is Map) {
        final st = (items['stages'] as Map).cast<String, dynamic>();
        for (final (part, icon, label) in [
          ('deep', Icons.water_drop_rounded, 'deep sleep'),
          ('light', Icons.cloud_rounded, 'light sleep'),
          if (st['rem_measured'] != false)
            ('rem', Icons.auto_awesome_rounded, 'REM'),
        ]) {
          if (_n(st[part]) != null) {
            tiles.add(('stages-$part', icon, _m(st[part]), label));
          }
        }
      }
      continue;
    }
    if (used.contains(k)) continue;
    if (friendTile(k, items[k]) case (final icon, final value, final label)) {
      tiles.add((k, icon, value, label));
    }
  }
  final shown = {
    ...used,
    for (final t in tiles) t.$1,
    if (hasChart) 'stages',
    'pet_mood',
  };
  final more = [
    for (final k in [..._nightKeys, ..._dayKeys, ..._gameKeys])
      if (!shown.contains(k) &&
          (friendItemLine(k, items[k])?.isNotEmpty ?? false))
        k,
  ].length;
  return (stats: stats, tiles: tiles, more: more);
}

/// 每個場景的地面在圖的多高（0–1，從上往下量），寵物的腳踩在這條線上。
/// 圖是使用者生成的（`assets/backgrounds/scene_<id>.jpg`，4:5），換圖時要重量。
const kSceneGround = {
  'campfire': 0.455,
  'rooftop': 0.455,
  'lake': 0.475,
  'treehouse': 0.47,
};
const kDefaultScene = 'campfire';

String sceneAsset(String? scene) =>
    'assets/backgrounds/scene_${kSceneGround.containsKey(scene) ? scene : kDefaultScene}.jpg';

const _sceneBottom = Color(0xFF061A6B); // 卡比圖長時接著圖底部的顏色
const _shadow = [Shadow(blurRadius: 8, color: Colors.black54)];
const _stageColors = {
  'awake': Color(0xFFFF8AD8),
  'rem': Color(0xFFC9A7FF),
  'light': Color(0xFF6FA8FF),
  'deep': Color(0xFF4FE0E0),
};

/// 動態卡（2026-11-16 使用者定 B 版）：整張卡是他選的場景，寵物站在右邊的地上，
/// 名字在天空；下半部（圖本來就暗）放三個大數字 → 連續天數的橫幅 → Sleep Stages 階梯 → 其他一行小字。
Map<String, dynamic>? _stagesOf(Map<String, dynamic> items) =>
    items['stages'] is Map
    ? (items['stages'] as Map).cast<String, dynamic>()
    : null;

List<(String, double, double)> _segmentsOf(Map<String, dynamic>? stages) => [
  for (final s in (stages?['segments'] as List?) ?? const [])
    if (s is Map &&
        _stageColors.containsKey(s['stage']) &&
        _n(s['from']) != null &&
        _n(s['to']) != null)
      (
        s['stage'] as String,
        _n(s['from'])!.toDouble(),
        _n(s['to'])!.toDouble(),
      ),
];

class FriendNightCardView extends StatelessWidget {
  final FriendNightCard card;
  final VoidCallback? onTap;

  /// 他現在連續幾晚準時（摘要裡的，他沒公開是 null）。3 晚以上才出現那條橫幅，只寫事實。
  final int? streak;

  /// See all 那一頁：同一張卡，但他公開的每一項都排成小格（一排三個），不收起來。
  final bool expanded;

  /// 他這週每晚準不準時（摘要裡的）。跟 streak 一樣只放在他最近那一晚的卡上；不是 7 天就不畫。
  final List<StreakDay>? week;

  /// 完整頁用：場景鋪到狀態列底下，名字要往下讓出狀態列＋返回鍵的高度。
  final double topInset;

  const FriendNightCardView({
    super.key,
    required this.card,
    this.onTap,
    this.streak,
    this.week,
    this.expanded = false,
    this.topInset = 0,
  });

  @override
  Widget build(BuildContext context) {
    final items = card.items;
    final stages = _stagesOf(items);
    final segments = _segmentsOf(stages);
    final layout = friendCardLayout(
      items,
      hasChart: segments.isNotEmpty,
      expanded: expanded,
    );
    final stats = layout.stats;

    // 自己的卡在動態牆上要一眼認得出來（2026-11-16 使用者要求）：紫色外框＋一圈光
    final glow = card.mine && !expanded;
    // 完整頁（2026-11-16 使用者定）：整頁就是場景，不是一張卡放在頁面中間——不留邊、不圓角
    return Padding(
      padding: EdgeInsets.only(bottom: expanded ? 0 : 20),
      child: Container(
        key: glow ? const Key('card-mine-glow') : null,
        decoration: glow
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(color: Color(0x887657FF), blurRadius: 22, spreadRadius: 1),
                ],
              )
            : null,
        child: Material(
        color: _sceneBottom,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(expanded ? 0 : 24),
          side: glow
              ? const BorderSide(color: Color(0xFFA48BFF), width: 2)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key(
            '${expanded ? 'night-detail' : 'feed-card'}-${card.handle}-${card.date}',
          ),
          onTap: onTap,
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final imgH = w * 5 / 4;
              final ground =
                  imgH *
                  (kSceneGround[card.scene] ?? kSceneGround[kDefaultScene]!);
              const petSize = 120.0;
              return Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: imgH,
                    child: Image.asset(
                      sceneAsset(card.scene),
                      key: const Key('card-scene'),
                      fit: BoxFit.fitWidth,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                  // 卡比圖長時，圖的底緣淡進卡片底色（不然看得到一條接縫）
                  Positioned(
                    top: imgH - 90,
                    left: 0,
                    right: 0,
                    height: 91,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00061A6B), _sceneBottom],
                        ),
                      ),
                    ),
                  ),
                  // 上緣稍微壓暗，名字才看得清楚
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: imgH * 0.25,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x55000000), Color(0x00000000)],
                        ),
                      ),
                    ),
                  ),
                  // 火焰直接在場景裡、寵物正後面（2026-11-16 使用者定）。外框 1.25 倍、寵物貼底，
                  // 所以腳還是踩在同一個地面上
                  Positioned(
                    top: ground + petSize * 0.08 - petSize * 1.25,
                    right: 18 - petSize * 0.125,
                    child: PetWithFlames(
                      mood: items['pet_mood'] as String?,
                      species: speciesOf(card.petSpecies),
                      streak: streak,
                      size: petSize,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(18, 16 + topInset, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              card.mine ? 'You' : card.displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                shadows: _shadow,
                              ),
                            ),
                            if (card.mine) ...[
                              const SizedBox(width: 8),
                              Container(
                                key: const Key('card-mine-pill'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7657FF),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'What friends see',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        // 動態牆上換一天有分隔線寫日期，卡上不再寫；完整頁沒有分隔線，照寫
                        if (expanded)
                        Text(
                          'Night of ${friendCardDate(card.date)}',
                          style: const TextStyle(
                            color: Color(0xDDFFFFFF),
                            fontSize: 12,
                            shadows: _shadow,
                          ),
                        ),
                        // 數字從地面下面開始（名字＋日期約 40 高，只有名字約 24）
                        SizedBox(
                          height: ground - 16 - topInset - (expanded ? 40 : 24) + 20,
                        ),
                        if (stats.isNotEmpty)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final (k, label, value) in stats)
                                Expanded(
                                  key: Key('card-stat-$k'),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        label,
                                        style: const TextStyle(
                                          color: Color(0xB3FFFFFF),
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          value,
                                          softWrap: false,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        if (streak != null && streak! >= 3) ...[
                          const SizedBox(height: 14),
                          Row(
                            key: const Key('card-streak'),
                            children: [
                              const Icon(
                                Icons.local_fire_department_rounded,
                                color: Color(0xFFFF8A5C),
                                size: 24,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${card.mine ? 'You' : card.displayName.split(' ').first} reached a $streak-night streak',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (week != null && week!.length == 7) ...[
                          const SizedBox(height: 12),
                          StreakWeekRow(key: const Key('card-week'), week: week!),
                        ],
                        if (segments.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _StageChart(
                            segments: segments,
                            remMeasured: stages?['rem_measured'] != false,
                            start: stages?['start'] as String?,
                            end: stages?['end'] as String?,
                            minutes: stages ?? const {},
                          ),
                        ],
                        if (layout.tiles.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          for (
                            var r = 0;
                            r < layout.tiles.length;
                            r += kMaxTiles
                          )
                            Padding(
                              padding: EdgeInsets.only(top: r == 0 ? 0 : 8),
                              child: Row(
                                children: [
                                  for (var i = 0; i < kMaxTiles; i++)
                                    Expanded(
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          right: i == kMaxTiles - 1 ? 0 : 8,
                                        ),
                                        // 不滿三格也照三格的寬度排（每張卡長得一樣）
                                        child: r + i < layout.tiles.length
                                            ? _Tile(
                                                key: Key(
                                                  'card-tile-${layout.tiles[r + i].$1}',
                                                ),
                                                icon: layout.tiles[r + i].$2,
                                                value: layout.tiles[r + i].$3,
                                                label: layout.tiles[r + i].$4,
                                              )
                                            : const SizedBox.shrink(),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                        if (!expanded && layout.more > 0) ...[
                          const SizedBox(height: 10),
                          Row(
                            key: const Key('card-more'),
                            children: [
                              Text(
                                '+${layout.more} more',
                                style: const TextStyle(
                                  color: Color(0xB3FFFFFF),
                                  fontSize: 13,
                                ),
                              ),
                              const Spacer(),
                              const Text(
                                'See all  ›',
                                style: TextStyle(
                                  color: Color(0xFFC9B8FF),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        ),
      ),
    );
  }
}

/// 動態牆上換一天的分隔線：「──── Last night ────」「──── Sat, Nov 14 ────」。
/// 卡片的日期是起床那天（同後端 night_date），所以今天的日期＝昨晚。
String feedDayLabel(String iso, {DateTime? now}) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final t = now ?? DateTime.now();
  final today = DateTime(t.year, t.month, t.day);
  final day = DateTime(d.year, d.month, d.day);
  if (day == today) return 'Last night';
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${wd[day.weekday - 1]}, ${friendCardDate(iso)}';
}

Widget feedDayDivider(String iso, {Key? key, DateTime? now}) => Padding(
  key: key,
  padding: const EdgeInsets.fromLTRB(0, 6, 0, 16),
  child: Row(
    children: [
      const Expanded(child: Divider(color: Color(0x40FFFFFF), thickness: 1)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          feedDayLabel(iso, now: now),
          style: const TextStyle(
            color: Color(0xCCFFFFFF),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
      const Expanded(child: Divider(color: Color(0x40FFFFFF), thickness: 1)),
    ],
  ),
);

class _Tile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _Tile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
    decoration: BoxDecoration(
      color: const Color(0x1AFFFFFF),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        Icon(icon, size: 20, color: const Color(0xFFC9B8FF)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            softWrap: false,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 10),
        ),
      ],
    ),
  );
}

/// 「See all」（2026-11-16 使用者定，照 Strava 活動頁）：上面是他的場景＋寵物（像 Strava 的地圖），
/// 下面一張資訊卡，一開始停在寵物腳下、往上拉看全部：名字 → 連續天數 → 大數字 → 這週 → 睡眠圖 →
/// 他公開的每一項（一排三格）。**不連到好友頁**（使用者定），返回鍵疊在場景上。
/// ⚠️ 資訊卡最底下要留系統按鍵列的高度——實機上那一列會蓋住最後一排。
Future<void> openFriendNight(
  BuildContext context,
  FriendNightCard card, {
  int? streak,
  List<StreakDay>? week,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => FriendNightPage(card: card, streak: streak, week: week),
    ),
  );
}

class FriendNightPage extends StatelessWidget {
  final FriendNightCard card;
  final int? streak;
  final List<StreakDay>? week;
  const FriendNightPage({
    super.key,
    required this.card,
    this.streak,
    this.week,
  });

  static const _page = Color(0xFF081326);
  static const _sheet = Color(0xFF111A3A);

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final inset = mq.padding;
    final w = mq.size.width;
    final h = mq.size.height;
    final imgH = w * 5 / 4;
    final ground =
        imgH * (kSceneGround[card.scene] ?? kSceneGround[kDefaultScene]!);
    const petSize = 150.0;
    // 資訊卡一開始的上緣：寵物腳下再往下一點，場景（含寵物）整個看得到
    final sheetTop = ground + petSize * 0.08 + 28;
    final sheetMin = ((h - sheetTop) / h).clamp(0.3, 0.7).toDouble();

    final items = card.items;
    final stages = _stagesOf(items);
    final segments = _segmentsOf(stages);
    final layout = friendCardLayout(
      items,
      hasChart: segments.isNotEmpty,
      expanded: true,
    );
    final name = card.mine ? 'You' : card.displayName;
    final statCols = layout.stats.length <= 3 ? layout.stats.length : 2;

    return Scaffold(
      backgroundColor: _page,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: imgH,
            child: Image.asset(
              sceneAsset(card.scene),
              key: const Key('night-scene'),
              fit: BoxFit.fitWidth,
              alignment: Alignment.topCenter,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
          // 圖的底緣淡進頁面底色（螢幕比圖長時不會看到一條接縫）
          Positioned(
            top: imgH - 120,
            left: 0,
            right: 0,
            height: 121,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00081326), _page],
                ),
              ),
            ),
          ),
          Positioned(
            top: ground + petSize * 0.08 - petSize * 1.25,
            left: (w - petSize * 1.25) / 2,
            child: PetWithFlames(
              mood: items['pet_mood'] as String?,
              species: speciesOf(card.petSpecies),
              streak: streak,
              size: petSize,
            ),
          ),
          DraggableScrollableSheet(
            key: const Key('night-sheet'),
            initialChildSize: sheetMin,
            minChildSize: sheetMin,
            // 拉到最上面也停在返回鍵下面（不頂到狀態列、不蓋住名字）
            maxChildSize: ((h - inset.top - 64) / h).clamp(sheetMin, 1.0).toDouble(),
            builder: (context, controller) => DecoratedBox(
              decoration: const BoxDecoration(
                color: _sheet,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 16)],
              ),
              child: ListView(
                key: const Key('night-detail'),
                controller: controller,
                padding: EdgeInsets.fromLTRB(20, 10, 20, inset.bottom + 32),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0x55FFFFFF),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (card.mine) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7657FF),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'What friends see',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Night of ${friendCardDate(card.date)}',
                    style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 13),
                  ),
                  if (streak != null && streak! >= 3) ...[
                    const SizedBox(height: 18),
                    Container(
                      key: const Key('card-streak'),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0x14FFFFFF),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 34,
                            height: 34,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                const Icon(
                                  Icons.local_fire_department_rounded,
                                  color: Color(0xFFFF8A5C),
                                  size: 34,
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    '$streak',
                                    style: const TextStyle(
                                      color: Color(0xFF3A1A00),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${card.mine ? 'You' : card.displayName.split(' ').first} reached a $streak-night streak',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (layout.stats.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    // 大數字置中；三個以內排一排，多了一排兩個（同 Strava）
                    for (var r = 0; r < layout.stats.length; r += statCols)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Row(
                          children: [
                            for (var c = r; c < r + statCols; c++)
                              Expanded(
                                child: c < layout.stats.length
                                    ? Column(
                                        key: Key('card-stat-${layout.stats[c].$1}'),
                                        children: [
                                          Text(
                                            layout.stats[c].$2,
                                            style: const TextStyle(
                                              color: Color(0xB3FFFFFF),
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            layout.stats[c].$3,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 26,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      )
                                    : const SizedBox.shrink(),
                              ),
                          ],
                        ),
                      ),
                  ],
                  if (week != null && week!.length == 7) ...[
                    const SizedBox(height: 4),
                    StreakWeekRow(key: const Key('card-week'), week: week!),
                  ],
                  if (segments.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    _StageChart(
                      segments: segments,
                      remMeasured: stages?['rem_measured'] != false,
                      start: stages?['start'] as String?,
                      end: stages?['end'] as String?,
                      minutes: stages ?? const {},
                    ),
                  ],
                  if (layout.tiles.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    for (var r = 0; r < layout.tiles.length; r += kMaxTiles)
                      Padding(
                        padding: EdgeInsets.only(top: r == 0 ? 0 : 8),
                        child: Row(
                          children: [
                            for (var i = 0; i < kMaxTiles; i++)
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    right: i == kMaxTiles - 1 ? 0 : 8,
                                  ),
                                  child: r + i < layout.tiles.length
                                      ? _Tile(
                                          key: Key(
                                            'card-tile-${layout.tiles[r + i].$1}',
                                          ),
                                          icon: layout.tiles[r + i].$2,
                                          value: layout.tiles[r + i].$3,
                                          label: layout.tiles[r + i].$4,
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          // 返回鍵疊在場景上（圓形深色底，跟 Strava 一樣）
          Positioned(
            top: inset.top + 8,
            left: 12,
            child: Material(
              color: const Color(0x99000000),
              shape: const CircleBorder(),
              child: IconButton(
                key: const Key('night-back'),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 動態卡裡的 Sleep Stages 階梯（同首頁那張的顏色，但沒有疊線、沒有點選）。
/// ⚠️ 兩端：準確時刻的人寫時刻，只寫準時與否的人只寫 Fell asleep／Woke up（後端已經拿掉時刻）。
class _StageChart extends StatelessWidget {
  final List<(String, double, double)> segments;
  final bool remMeasured;
  final String? start;
  final String? end;
  final Map<String, dynamic> minutes;
  const _StageChart({
    required this.segments,
    required this.remMeasured,
    required this.start,
    required this.end,
    required this.minutes,
  });

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(color: Color(0xB3FFFFFF), fontSize: 11);
    return Column(
      key: const Key('card-stages'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sleep stages',
          key: Key('card-stages-title'),
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 96,
          width: double.infinity,
          child: CustomPaint(painter: _StagePainter(segments, remMeasured)),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              start ?? 'Fell asleep',
              key: const Key('card-stages-start'),
              style: label,
            ),
            const Spacer(),
            Text(
              end ?? 'Woke up',
              key: const Key('card-stages-end'),
              style: label,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          key: const Key('card-stages-legend'),
          spacing: 14,
          runSpacing: 4,
          children: [
            for (final (k, name) in const [
              ('deep', 'Deep'),
              ('light', 'Light'),
              ('rem', 'REM'),
              ('awake', 'Awake'),
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _stageColors[k],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    // 沒量到 REM 的晚上不畫那一層，圖例照實寫
                    k == 'rem' && !remMeasured ? 'REM not measured' : name,
                    style: label,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _StagePainter extends CustomPainter {
  final List<(String, double, double)> segments;
  final bool remMeasured;
  _StagePainter(this.segments, this.remMeasured);

  @override
  void paint(Canvas canvas, Size size) {
    final levels = ['awake', if (remMeasured) 'rem', 'light', 'deep'];
    final total = segments
        .map((s) => s.$3)
        .fold<double>(0, (a, b) => b > a ? b : a);
    if (total <= 0) return;
    final rowH = size.height / levels.length;
    double? prevY;
    for (final (stage, from, to) in segments) {
      final i = levels.indexOf(stage);
      if (i < 0) continue;
      final x = from / total * size.width;
      final w = (to - from) / total * size.width;
      final y = rowH * i + rowH / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y - rowH * 0.32, w < 1.5 ? 1.5 : w, rowH * 0.64),
          const Radius.circular(4),
        ),
        Paint()..color = _stageColors[stage]!,
      );
      if (prevY != null && prevY != y) {
        canvas.drawLine(
          Offset(x, prevY),
          Offset(x, y),
          Paint()
            ..color = Colors.white24
            ..strokeWidth = 1.5,
        );
      }
      prevY = y;
    }
  }

  @override
  bool shouldRepaint(_StagePainter old) => old.segments != segments;
}
