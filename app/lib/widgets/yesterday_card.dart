import 'package:flutter/material.dart';

import '../models/yesterday_activity.dart';
import '../screens/morning_report_screen.dart' show reportDateTitle;
import '../theme/report_style.dart';

/// 早晨報告的「Yesterday」：前一天的 Garmin 白天資料（2026-11-13 使用者定）。
///
/// 由上到下：四張小卡（步數、活動卡路里、爬樓、VO2 max）→ 活動時間條 → 壓力時間條
/// → Body Battery 一行 → Move IQ 一天的時間軸。
///
/// ⚠️ **只寫事實**：步數只寫「goal 9,430」，不寫 reached、不變色；壓力只給各程度的時間，
///    不加說明、不用紅黃（使用者定）；VO2 max 只給數字與量到的日期，不分等級。
/// ⚠️ 顏色只用紫色系的深淺：高壓力只是最深的紫，不是警示色。
/// ⚠️ 沒有值的那一項整個不畫，不畫成 0。整塊要不要出現由呼叫端看 [YesterdayActivity] 是不是 null。
class YesterdayCard extends StatelessWidget {
  final YesterdayActivity data;
  const YesterdayCard({super.key, required this.data});

  // 由淺到深（活動：久坐最淡、高強度最深；壓力：休息最淡、高最深）
  static const Color _shade1 = Color(0x52B9A6FF);
  static const Color _shade2 = Color(0xFF9C86F2);
  static const Color _shade3 = Color(0xFF7657FF);
  static const Color _shade4 = Color(0xFF4B2FC9);

  @override
  Widget build(BuildContext context) {
    final y = data;
    final day = DateTime.tryParse(y.date);
    final tiles = <Widget>[
      if (y.steps != null)
        _tile(
          key: 'yesterday-steps',
          label: 'Steps',
          value: _n(y.steps!),
          sub: y.stepGoal == null ? null : 'goal ${_n(y.stepGoal!)}',
        ),
      if (y.activeKcal != null)
        _tile(
          key: 'yesterday-active',
          label: 'Active',
          value: '${_n(y.activeKcal!)} kcal',
          sub: y.distanceM == null ? null : _km(y.distanceM!),
        ),
      if (y.floorsUp != null)
        _tile(
          key: 'yesterday-floors',
          label: 'Floors',
          value: y.floorsUp!.round().toString(),
          sub: 'climbed',
        ),
      if (y.vo2max != null)
        _tile(
          key: 'yesterday-vo2',
          label: 'VO2 max',
          value: y.vo2max!.round().toString(),
          sub: _measured(y.vo2maxMeasuredOn),
        ),
    ];
    final moves = y.moveIq;

    return Container(
      key: const Key('yesterday-card'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: reportCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text(
                'Yesterday',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 8),
              if (day != null)
                Flexible(
                  child: Text(
                    reportDateTitle(day),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ReportColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          if (tiles.isNotEmpty) ...[
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, c) {
                final w = (c.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final t in tiles) SizedBox(width: w, child: t),
                  ],
                );
              },
            ),
          ],
          if (y.hasActivity) ...[
            const SizedBox(height: 16),
            _bar(
              key: 'yesterday-activity',
              title: 'Activity',
              parts: [
                ('Sedentary', y.sedentarySec, _shade1),
                ('Active', y.activeSec, _shade2),
                ('Highly active', y.highlyActiveSec, _shade4),
              ],
            ),
          ],
          if (y.hasStress) ...[
            const SizedBox(height: 14),
            _bar(
              key: 'yesterday-stress',
              title: 'Stress',
              parts: [
                ('Rest', y.stressRestSec, _shade1),
                ('Low', y.stressLowSec, _shade2),
                ('Medium', y.stressMediumSec, _shade3),
                ('High', y.stressHighSec, _shade4),
              ],
            ),
          ],
          if (y.hasBodyBattery) ...[
            const SizedBox(height: 14),
            Text(
              [
                'Body Battery',
                if (y.bodyBatteryCharged != null)
                  '+${y.bodyBatteryCharged} charged',
                if (y.bodyBatteryDrained != null)
                  '−${y.bodyBatteryDrained} drained',
              ].join(' · '),
              key: const Key('yesterday-bb'),
              style: const TextStyle(color: ReportColors.soft, fontSize: 13),
            ),
          ],
          if (moves != null && moves.isNotEmpty) ...[
            const SizedBox(height: 16),
            _moveIq(moves),
          ],
        ],
      ),
    );
  }

  Widget _tile({
    required String key,
    required String label,
    required String value,
    String? sub,
  }) {
    return Container(
      key: Key(key),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ReportColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: ReportColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              key: Key('$key-value'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (sub != null)
            Text(
              sub,
              key: Key('$key-sub'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: ReportColors.faint, fontSize: 12),
            ),
        ],
      ),
    );
  }

  /// 一條依秒數比例分段的橫條＋圖例（每段的時間）。沒有值的段不畫也不列。
  Widget _bar({
    required String key,
    required String title,
    required List<(String, int?, Color)> parts,
  }) {
    final shown = [
      for (final p in parts)
        if (p.$2 != null && p.$2! > 0) p,
    ];
    final total = shown.fold<int>(0, (s, p) => s + p.$2!);
    return Column(
      key: Key(key),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        if (total > 0)
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  for (final p in shown)
                    Expanded(
                      flex: p.$2!,
                      child: ColoredBox(color: p.$3),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final p in shown)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: p.$3,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${p.$1} ${reportHm(p.$2! / 60)}',
                    key: Key('$key-${p.$1.toLowerCase().replaceAll(' ', '-')}'),
                    style: const TextStyle(
                      color: ReportColors.soft,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  /// Move IQ：一整天（0–24 點）的時間軸，走路與騎車用兩種紫；下面列每一段。
  Widget _moveIq(List<MoveIqEvent> moves) {
    Color colorOf(String type) => type == 'cycling' ? _shade4 : _shade2;
    return Column(
      key: const Key('yesterday-moveiq'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Move IQ',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            return SizedBox(
              height: 30,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 5,
                    height: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  for (final m in moves)
                    if (m.startMinuteOfDay case final start?)
                      Positioned(
                        left: w * start / 1440,
                        top: 3,
                        height: 12,
                        // 太短的段至少畫 4 寬，才看得到
                        width: (w * m.minutes / 1440).clamp(4, w).toDouble(),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colorOf(m.type),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                  for (final (i, label) in const [
                    '0',
                    '6',
                    '12',
                    '18',
                    '24',
                  ].indexed)
                    Positioned(
                      left: i == 4 ? null : (w * i / 4 - (i == 0 ? 0 : 6)),
                      right: i == 4 ? 0 : null,
                      top: 17,
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: ReportColors.dim,
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final m in moves)
              Text(
                '${m.start} ${_typeLabel(m.type)} ${reportHm(m.minutes)}',
                style: TextStyle(
                  color: colorOf(m.type) == _shade4
                      ? ReportColors.accent
                      : ReportColors.soft,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ],
    );
  }

  static String _typeLabel(String type) => switch (type) {
    'walking' => 'Walk',
    'cycling' => 'Bike',
    'running' => 'Run',
    _ => type.isEmpty ? '' : type[0].toUpperCase() + type.substring(1),
  };

  /// 1219 → 1,219
  static String _n(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  static String _km(int meters) => '${(meters / 1000).toStringAsFixed(1)} km';

  static String? _measured(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso);
    if (d == null) return null;
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
    return 'measured ${months[d.month - 1]} ${d.day}';
  }
}
