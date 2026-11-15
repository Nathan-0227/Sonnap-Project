// 動態卡（2026-11-15 使用者定，參考 Strava）：朋友那一晚的資料上傳後出現一張卡，
// **只放他公開的項目**＋寵物。key 與值的形狀在 social/sharing.py。
//
// - 這裡一格都不算：數字照抄後端（後端從他自己的 /home 挑的，跟他的報告同一份）
// - 沒給的項目不畫，不寫成 0
// - 不判斷好壞：不寫 good／bad、分數不變色、晚了只寫 Late（不用紅色）
import 'package:flutter/material.dart';

import '../services/friends_service.dart';
import '../services/night_compare.dart' show formatMinutes;
import 'home_pet.dart';
import 'streak_card.dart' show speciesOf;

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
      final all = v.whereType<Map>().where((c) => c['title'] is String).toList();
      final done = [for (final c in all) if (c['completed'] == true) c['title'] as String];
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

class FriendNightCardView extends StatelessWidget {
  final FriendNightCard card;
  final VoidCallback? onTap;
  const FriendNightCardView({super.key, required this.card, this.onTap});

  Widget _section(String title, List<String> keys) {
    final lines = [
      for (final k in keys)
        if (card.items.containsKey(k))
          if (friendItemLine(k, card.items[k]) case final l? when l.isNotEmpty)
            (k, l),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 11),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (k, l) in lines)
                Container(
                  key: Key('card-item-$k'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x1AFFFFFF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    l,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mood = card.items['pet_mood'] as String?;
    return InkWell(
      key: Key('feed-card-${card.handle}-${card.date}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF10265A),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipOval(
                  child: Container(
                    width: 44,
                    height: 44,
                    color: const Color(0xFF233A73),
                    child: OverflowBox(
                      maxWidth: 70,
                      maxHeight: 70,
                      child: HomePet(
                        mood: mood,
                        size: 64,
                        species: speciesOf(card.petSpecies),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Night of ${friendCardDate(card.date)}',
                        style: const TextStyle(
                          color: Color(0x99FFFFFF),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            _section('Last night', _nightKeys),
            _section('Yesterday', _dayKeys),
            _section('Game', _gameKeys),
          ],
        ),
      ),
    );
  }
}
