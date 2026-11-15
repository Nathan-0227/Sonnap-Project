import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/yesterday_activity.dart';
import 'report_sheet.dart';

// 早晨報告 Yesterday 的 **Move IQ**（2026-11-15 使用者定）：
// - Garmin 自動偵測到的一段段活動（類型、開始時刻、幾分鐘；沒有距離、速度、路線）。
// - 🔴 **騎車（cycling）不顯示**：使用者多半騎機車，而手錶分不出機車與腳踏車——
//   實測 08-28 起 79 段騎車，每分鐘步數中間值 22、多數時段 Garmin 標「坐著」（走路是 90）。
//   放進活動那一段會把騎機車讀成運動。資料照存、後端照給，**只在畫面上濾掉**（[moveIqShown]，一處）。
//   代價：78 天裡 52 天剩不到一段 → 那天整格不畫（同「沒有就不畫」）。改回來只要改 [moveIqShown]。
// - 其他類型**照 Garmin 寫**，不用步數去改（例：一段每分鐘 156 步的 swimming 照寫 Swim）。
// - 報告上那一格：24 小時鐘面，有動的時段亮起一段弧（00 在上）。大字「2 walks」、小字總分鐘數。
// - 點開：那天的清單（17:42–17:56 · 14m）＋最近 7 天各類型幾分鐘。
//   **不放每段走了幾步**（只有 15 分鐘的格子，會把前後沒在動的時間算進去）、**不比平常**。

const kMoveIq = Color(0xFF7ED957);
const kMoveIqOther = Color(0xFF5CC8E8);

/// 畫面上要放的段：拿掉騎車（見檔頭）。
List<MoveIqEvent> moveIqShown(List<MoveIqEvent>? events) => [
  for (final e in events ?? const <MoveIqEvent>[])
    if (e.type != 'cycling') e,
];

/// Garmin 的類型 → 畫面上的名字（不認得的照寫、首字大寫）。
String moveIqLabel(String type) => switch (type) {
  'walking' => 'Walk',
  'running' => 'Run',
  'swimming' => 'Swim',
  'hiking' => 'Hike',
  'elliptical' => 'Elliptical',
  _ =>
    type.isEmpty
        ? 'Other'
        : '${type[0].toUpperCase()}${type.substring(1).replaceAll('_', ' ')}',
};

Color moveIqColor(String type) => type == 'walking' ? kMoveIq : kMoveIqOther;

IconData moveIqIcon(String type) => switch (type) {
  'walking' => Icons.directions_walk_rounded,
  'running' => Icons.directions_run_rounded,
  'swimming' => Icons.pool_rounded,
  'hiking' => Icons.hiking_rounded,
  _ => Icons.route_rounded,
};

/// 大字：全是走路寫「2 walks」，混了別的寫「3 moves」。
String moveIqTileValue(List<MoveIqEvent> shown) {
  final n = shown.length;
  if (shown.every((e) => e.type == 'walking')) {
    return '$n walk${n == 1 ? '' : 's'}';
  }
  return '$n move${n == 1 ? '' : 's'}';
}

String _dur(int m) =>
    m < 60 ? '${m}m' : (m % 60 == 0 ? '${m ~/ 60}h' : '${m ~/ 60}h ${m % 60}m');

/// 小字：總共幾分鐘；混了別的類型時列出各幾段。
String moveIqTileLine(List<MoveIqEvent> shown) {
  final total = shown.fold<int>(0, (s, e) => s + e.minutes);
  if (shown.every((e) => e.type == 'walking')) return '${_dur(total)} in total';
  final counts = <String, int>{};
  for (final e in shown) {
    counts[moveIqLabel(e.type)] = (counts[moveIqLabel(e.type)] ?? 0) + 1;
  }
  return '${counts.entries.map((c) => '${c.value} ${c.key.toLowerCase()}').join(' · ')}'
      ' · ${_dur(total)}';
}

String _hm(int minuteOfDay) {
  final m = minuteOfDay % 1440;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// 清單那一行的時間：「17:42–17:56」。
String moveIqSpan(MoveIqEvent e) {
  final s = e.startMinuteOfDay;
  if (s == null) return e.start;
  return '${_hm(s)}–${_hm(s + e.minutes)}';
}

// ── 報告上那一格：24 小時鐘面 ──

class MoveIqDial extends StatelessWidget {
  final List<MoveIqEvent> events;
  const MoveIqDial({super.key, required this.events});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: MoveIqDialPainter(events), size: Size.infinite);
}

class MoveIqDialPainter extends CustomPainter {
  final List<MoveIqEvent> events;
  MoveIqDialPainter(this.events);

  /// 午夜在正上方、順時針。
  static double angleOf(int minuteOfDay) =>
      -math.pi / 2 + 2 * math.pi * minuteOfDay / 1440;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final c = Offset(w * 0.5, h * 0.41);
    final r = math.min(w * 0.25, h * 0.22);
    final stroke = r * 0.2;
    final rect = Rect.fromCircle(center: c, radius: r);

    // 底圈＋淡淡的光
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = const Color(0x1FFFFFFF),
    );
    // 00／06／12／18 的小刻度
    final tick = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final a = angleOf(i * 360);
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        c + d * (r - stroke * 0.95),
        c + d * (r - stroke * 0.6),
        tick,
      );
    }
    // 每一段：一段亮弧＋光暈（太短的至少畫 4 度，免得看不到）
    for (final e in events) {
      final s = e.startMinuteOfDay;
      if (s == null) continue;
      final sweep = math.max(2 * math.pi * e.minutes / 1440, math.pi / 45);
      final color = moveIqColor(e.type);
      canvas.drawArc(
        rect,
        angleOf(s),
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 1.6
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.35)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 0.6),
      );
      canvas.drawArc(
        rect,
        angleOf(s),
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
    // 中間的人形
    final icon = events.every((e) => e.type == 'walking')
        ? Icons.directions_walk_rounded
        : Icons.route_rounded;
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: r * 0.9,
          color: const Color(0xCCFFFFFF),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(MoveIqDialPainter old) => old.events != events;
}

// ── 點開的頁 ──

Future<void> showMoveIqSheet(
  BuildContext context, {
  required YesterdayActivity day,
  String? fontFamily,
}) {
  return showReportSheet<void>(
    context: context,
    builder: (context) => DefaultTextStyle.merge(
      style: TextStyle(fontFamily: fontFamily),
      child: MoveIqView(day: day),
    ),
  );
}

/// 一週：[endDate] 往回 7 天，各類型幾分鐘（已拿掉騎車）。null＝那天沒資料。
List<(String, Map<String, int>?)> moveIqWeek(
  List<ActivityHistoryDay> history,
  String endDate,
) {
  final by = {for (final h in history) h.date: h};
  final end = DateTime.parse(endDate);
  return [
    for (var i = 6; i >= 0; i--)
      () {
        final d = DateTime.utc(end.year, end.month, end.day - i);
        final key =
            '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        final events = by[key]?.moveIq;
        if (events == null) return (key, null);
        final m = <String, int>{};
        for (final e in moveIqShown(events)) {
          m[e.type] = (m[e.type] ?? 0) + e.minutes;
        }
        return (key, m);
      }(),
  ];
}

class MoveIqView extends StatelessWidget {
  final YesterdayActivity day;
  const MoveIqView({super.key, required this.day});

  static const _soft = Color(0xB3FFFFFF);

  @override
  Widget build(BuildContext context) {
    final shown = moveIqShown(day.moveIq)
      ..sort(
        (a, b) => (a.startMinuteOfDay ?? 0).compareTo(b.startMinuteOfDay ?? 0),
      );
    final week = moveIqWeek(day.history, day.date);
    final showWeek = week.any((d) => d.$2 != null);

    return Container(
      key: const Key('moveiq-sheet'),
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
              const Row(
                children: [
                  Icon(Icons.route_rounded, size: 20, color: kMoveIq),
                  SizedBox(width: 8),
                  Text(
                    'Move IQ',
                    style: TextStyle(
                      color: kMoveIq,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Detected by your watch. Rides are left out — most are '
                'scooter trips.',
                key: Key('moveiq-note'),
                style: TextStyle(color: _soft, fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 14),
              for (final (i, e) in shown.indexed)
                Padding(
                  key: Key('moveiq-row-$i'),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: moveIqColor(e.type).withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          moveIqIcon(e.type),
                          size: 19,
                          color: moveIqColor(e.type),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${moveIqLabel(e.type)}  ${moveIqSpan(e)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        _dur(e.minutes),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              if (showWeek) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Container(height: 1, color: const Color(0x1FFFFFFF)),
                ),
                const Text(
                  'Last 7 days',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Minutes per day',
                  style: TextStyle(color: _soft, fontSize: 12),
                ),
                const SizedBox(height: 12),
                SizedBox(height: 150, child: _WeekBars(week: week)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekBars extends StatelessWidget {
  final List<(String, Map<String, int>?)> week;
  const _WeekBars({required this.week});

  static const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    int total(Map<String, int>? m) =>
        m == null ? 0 : m.values.fold(0, (s, v) => s + v);
    final hi = math.max(
      1,
      week.fold<int>(0, (s, d) => math.max(s, total(d.$2))),
    );
    return LayoutBuilder(
      builder: (context, box) {
        const valueH = 16.0, labelH = 18.0;
        final h = box.maxHeight - valueH - labelH;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (i, d) in week.indexed)
              Expanded(
                child: Column(
                  key: Key('moveiq-week-$i'),
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      height: valueH,
                      child: Text(
                        d.$2 == null ? '—' : '${total(d.$2)}',
                        softWrap: false,
                        style: TextStyle(
                          color: i == week.length - 1
                              ? Colors.white
                              : const Color(0xB3FFFFFF),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: h,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: total(d.$2) == 0
                            ? null
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(7),
                                child: SizedBox(
                                  width: 24,
                                  height: math.max(3, h * total(d.$2) / hi),
                                  child: Column(
                                    children: [
                                      for (final t
                                          in d.$2!.keys.toList()..sort(
                                            (a, b) => a == 'walking' ? 1 : -1,
                                          ))
                                        Expanded(
                                          flex: d.$2![t]!,
                                          child: Container(
                                            color: moveIqColor(t).withValues(
                                              alpha: i == week.length - 1
                                                  ? 1
                                                  : 0.7,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                    ),
                    SizedBox(
                      height: labelH,
                      child: Center(
                        child: Text(
                          _wd[DateTime.parse(d.$1).weekday - 1],
                          style: const TextStyle(
                            color: Color(0x99FFFFFF),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
