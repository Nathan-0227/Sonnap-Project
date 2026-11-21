import 'package:flutter/material.dart';

import '../models/sleep_stages.dart';
import '../models/night_curve.dart';
import '../theme/report_style.dart' show reportHm;
import 'heart_rate_sheet.dart' show stageHeartRates;
import 'night_week.dart';
import 'report_sheet.dart';

/// 深睡點開（2026-11-21 grill 定，使用者看過預覽）：首頁的深睡格開這一頁。
///
/// - 這一晚：幾分鐘＋佔總睡眠幾成（兩個都是手錶的數字）＋幾段；入睡→起床一條時間軸只亮深睡，
///   每段一個「開始時刻 · 多久」（段落跟 Sleep Stages 同一份）
/// - 睡著時各階段的平均心率（跟心率頁同一支 [stageHeartRates]）；**不寫正常範圍**；沒量到 REM 不列 REM
/// - 這一週：一個顏色、Usually＝中間值、跟前一週比只代表方向；**不畫「建議幾分鐘」的線**（不放常模）
/// - 不放警語（11-19 定：警語只留在書面報告）
const Color kDeepColor = Color(0xFF4FE0E0);
const Color _lightColor = Color(0xFF6FA8FF);
const Color _remColor = Color(0xFFC9A7FF);

/// 這一晚的深睡段落（照時間排）。沒有階段資料 → 空。
List<StageSegment> deepStretches(SleepStages? stages) => [
  for (final s in stages?.segments ?? const <StageSegment>[])
    if (s.stage == 'deep') s,
];

/// 「24% of your sleep · 5 stretches」。總睡眠沒有就只寫段數；段數沒有就只寫比例。
String? deepShareLine(double deep, double? sleepMinutes, int stretches) {
  final parts = [
    if (sleepMinutes != null && sleepMinutes > 0)
      '${(deep / sleepMinutes * 100).round()}% of your sleep',
    if (stretches > 0) '$stretches stretch${stretches == 1 ? '' : 'es'}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// 「↓ 2m vs the week before」；只代表方向。
String? deepChangeLine(MedianWeek w) {
  final c = w.change;
  if (c == null) return null;
  final r = c.round();
  if (r == 0) return '= same as the week before';
  return '${r > 0 ? '↑' : '↓'} ${reportHm(r.abs())} vs the week before';
}

String _clock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

Future<void> showDeepSheet(
  BuildContext context, {
  required String dateTitle,
  required double deepMinutes,
  double? sleepMinutes,
  SleepStages? stages,
  NightCurve? heartRate,
  MedianWeek? week,
  String? fontFamily,
}) {
  return showReportSheet<void>(
    context: context,
    builder: (context) => DefaultTextStyle.merge(
      style: TextStyle(fontFamily: fontFamily),
      child: DeepView(
        dateTitle: dateTitle,
        deepMinutes: deepMinutes,
        sleepMinutes: sleepMinutes,
        stages: stages,
        heartRate: heartRate,
        week: week,
      ),
    ),
  );
}

class DeepView extends StatelessWidget {
  final String dateTitle;
  final double deepMinutes;
  final double? sleepMinutes;
  final SleepStages? stages;
  final NightCurve? heartRate;

  /// null＝沒有一週資料（連不到後端），下半整段不出現。
  final MedianWeek? week;

  const DeepView({
    super.key,
    required this.dateTitle,
    required this.deepMinutes,
    this.sleepMinutes,
    this.stages,
    this.heartRate,
    this.week,
  });

  static const _soft = Color(0xB3FFFFFF);
  static const _faint = Color(0xFF9FA7CC);
  static const _up = Color(0xFFFF7B7B);
  static const _down = Color(0xFF4FE0A0);

  @override
  Widget build(BuildContext context) {
    final stretches = deepStretches(stages);
    final share = deepShareLine(deepMinutes, sleepMinutes, stretches.length);
    final hr = heartRate;
    final byStage = hr == null
        ? const <(String, double)>[]
        : [
            for (final s in stageHeartRates(hr, stages))
              if (s.$1 == 'deep' || s.$1 == 'light' || s.$1 == 'rem') s,
          ];
    final w = week;
    final showWeek = w != null && w.nightsWithData > 0;
    final change = showWeek ? deepChangeLine(w) : null;
    final c = w?.change?.round();

    return Container(
      key: const Key('deep-sheet'),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF151A3C), Color(0xFF1B1F48), Color(0xFF2B3470)],
          stops: [0, 0.6, 1],
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.waves_rounded, size: 20, color: kDeepColor),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Deep sleep',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: kDeepColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    dateTitle,
                    softWrap: false,
                    style: const TextStyle(color: _soft, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // ── 這一晚 ──
              Text(
                reportHm(deepMinutes),
                key: const Key('deep-total'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
              if (share != null)
                Text(
                  share,
                  key: const Key('deep-share'),
                  style: const TextStyle(color: _soft, fontSize: 13),
                ),
              if (stages != null && stretches.isNotEmpty) ...[
                const SizedBox(height: 14),
                SizedBox(
                  key: const Key('deep-timeline'),
                  height: 50,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _TimelinePainter(stages!, stretches),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in stretches)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: kDeepColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${_clock(s.start)} · ${reportHm(s.end.difference(s.start).inMinutes)}',
                          style: const TextStyle(
                            color: kDeepColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              if (byStage.isNotEmpty) ...[
                const SizedBox(height: 22),
                const Text(
                  'Heart rate while asleep',
                  style: TextStyle(color: _soft, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Container(
                  key: const Key('deep-hr'),
                  decoration: BoxDecoration(
                    color: const Color(0x8C3A3672),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x24FFFFFF)),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < byStage.length; i++) ...[
                        if (i > 0)
                          Container(height: 1, color: const Color(0x1FFFFFFF)),
                        _hrRow(byStage[i]),
                      ],
                    ],
                  ),
                ),
              ],
              if (showWeek) ...[
                const SizedBox(height: 22),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'This week',
                      style: TextStyle(color: _soft, fontSize: 13),
                    ),
                    const Spacer(),
                    if (change != null)
                      Text(
                        change,
                        key: const Key('deep-week-change'),
                        style: TextStyle(
                          color: c == null || c == 0
                              ? _soft
                              : (c > 0 ? _up : _down),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
                if (w.usual != null)
                  Text.rich(
                    key: const Key('deep-week-usual'),
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Usually ',
                          style: TextStyle(color: _soft, fontSize: 13),
                        ),
                        TextSpan(
                          text: reportHm(w.usual!),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                WeekBars(
                  nights: w.nights,
                  // 刻度跟著這一週最多那晚走（至少 1 小時），不畫任何「建議」線
                  max: [
                    60.0,
                    for (final n in w.nights)
                      if (n.$2 != null) n.$2!,
                  ].reduce((a, b) => a > b ? a : b),
                  colorOf: (_) => kDeepColor,
                  label: (v) => reportHm(v),
                ),
                const SizedBox(height: 6),
                Text(
                  medianWeekCountLine(w),
                  style: const TextStyle(color: _faint, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _hrRow((String, double) s) {
    final (stage, bpm) = s;
    final (name, color) = switch (stage) {
      'deep' => ('Deep', kDeepColor),
      'rem' => ('REM', _remColor),
      _ => ('Light', _lightColor),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(color: Color(0xFFDCE0F5), fontSize: 14),
            ),
          ),
          Text(
            '${bpm.round()}',
            key: Key('deep-hr-$stage'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 6),
          const Text('bpm avg', style: TextStyle(color: _faint, fontSize: 11)),
        ],
      ),
    );
  }
}

/// 入睡→起床一條，淺色底、深睡那幾段亮；底下寫開頭、中間、結尾三個時刻。
class _TimelinePainter extends CustomPainter {
  final SleepStages stages;
  final List<StageSegment> deep;
  _TimelinePainter(this.stages, this.deep);

  @override
  void paint(Canvas canvas, Size size) {
    final start = stages.start, end = stages.end;
    final total = end.difference(start).inSeconds;
    if (total <= 0) return;
    double x(DateTime t) =>
        (t.difference(start).inSeconds / total).clamp(0.0, 1.0) * size.width;
    const top = 4.0, h = 22.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, top, size.width, h), const Radius.circular(11)),
      Paint()..color = _lightColor.withValues(alpha: 0.18),
    );
    final on = Paint()..color = kDeepColor;
    for (final s in deep) {
      final l = x(s.start);
      final w = (x(s.end) - l).clamp(3.0, size.width);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(l, top, w, h), const Radius.circular(5)),
        on,
      );
    }
    final mid = start.add(Duration(seconds: total ~/ 2));
    for (final (t, align) in [(start, 0.0), (mid, 0.5), (end, 1.0)]) {
      final tp = TextPainter(
        text: TextSpan(
          text: _clock(t),
          style: const TextStyle(
            color: Color(0xFF9FA7CC),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x(t) - tp.width * align, top + h + 6));
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.stages != stages || old.deep != deep;
}
