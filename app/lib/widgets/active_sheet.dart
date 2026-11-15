import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/yesterday_activity.dart';
import '../services/night_compare.dart' show kDeltaUp, kDeltaDown, kDeltaFlat;
import '../theme/report_style.dart' show reportHm;
import 'chart_probe.dart' show ProbeLayer;
import 'steps_sheet.dart' show stepsComma;

// 早晨報告 Active time（2026-11-15 使用者定）：
// - 報告上那一格是一座山（參考圖 Activity / Perfect day）：山＝一整天 24 小時，漸層由下往上
//   睡（深藍）→ 坐（淺藍）→ 活動（橘）→ 高強度（山尖）。**每一段佔的面積＝那天的比例**
//   （照面積切不照高度切：山越往上越尖，照高度切的話活動 5% 只剩一個點）。段與段之間只留很短的過渡。
//   太陽只是裝飾。參考圖的「Perfect day」不照做（那是評好壞），小字只寫事實。
// - 點開：24 小時圓環（四段）＋左邊四行時間；一整天的時間軸（每 15 分鐘一格，Move IQ 標在上面，
//   點一下看那 15 分鐘）；一週（高強度疊在下面、活動在上面，Usually＝中間值，比前一週只代表方向）。
// ⚠️ 「睡」是 Garmin 以**日曆日**切的睡著時間，跟報告上方「昨晚睡多久」不是同一個數字——
//    所以只當山底與圓環那段顏色、四行裡標 asleep (this day)，不在別處寫出來。
// ⚠️ 不放強度分鐘與 150 分鐘週目標：這支錶給 0，而且那是 WHO 對中高強度運動的建議，
//    Garmin 的「活動時間」不是同一個量（拿錯尺）。久坐只寫時間，不寫坐太久、不提醒。

const kActiveHigh = Color(0xFFFF6B4A);
const kActiveActive = Color(0xFFFFA24C);
const kActiveStill = Color(0xFF7FB2E5);
const kActiveSleep = Color(0xFF2E4A9E);
const kActiveOther = Color(0x66FFFFFF);

Color activeLevelColor(String level) => switch (level) {
  'high' => kActiveHigh,
  'active' => kActiveActive,
  'still' => kActiveStill,
  'sleep' => kActiveSleep,
  _ => kActiveOther,
};

String activeLevelLabel(String level) => switch (level) {
  'high' => 'High',
  'active' => 'Active',
  'still' => 'Still',
  'sleep' => 'Asleep',
  _ => 'Unlabeled',
};

/// 一天四種的秒數。高強度、活動、久坐三個都要有；睡著沒有當 0。
class ActiveParts {
  final int high, active, still, sleep;
  const ActiveParts(this.high, this.active, this.still, this.sleep);

  int get total => high + active + still + sleep;
  int get activeMinutes => ((high + active) / 60).round();
}

ActiveParts? activeParts(YesterdayActivity y) {
  final h = y.highlyActiveSec, a = y.activeSec, s = y.sedentarySec;
  if (h == null || a == null || s == null) return null;
  final p = ActiveParts(h, a, s, y.sleepingSec ?? 0);
  return p.total > 0 ? p : null;
}

/// 山的分段：從山尖往下，每一段的下緣在山高的哪裡（0＝山尖、1＝山腳）。
/// 照**面積**切：三角形從山尖往下 t 的面積是全部的 t²，所以累積面積 A 的分界在 √A。
/// 回傳 [(程度, 上緣, 下緣)]，順序高強度 → 活動 → 坐 → 睡；佔 0 的段不回。純函式。
List<(String, double, double)> mountainBands(ActiveParts p) {
  final total = p.total.toDouble();
  if (total <= 0) return const [];
  final out = <(String, double, double)>[];
  var cum = 0.0;
  for (final (level, v) in [
    ('high', p.high),
    ('active', p.active),
    ('still', p.still),
    ('sleep', p.sleep),
  ]) {
    if (v <= 0) continue;
    final top = math.sqrt(cum / total);
    cum += v;
    out.add((level, top, math.sqrt(math.min(1, cum / total))));
  }
  return out;
}

/// 報告上那一格的小字：只寫事實。
String activeTileLine(ActiveParts p) =>
    'high ${reportHm(p.high / 60)} · still ${reportHm(p.still / 60)}';

/// 時間軸泡泡：「09:00–09:15 · Active · 736 steps」；沒戴錶「09:00–09:15 · no data」。
String activeQuarterText(int i, ActivityQuarter? q) {
  String hm(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  final span = '${hm(i * 15)}–${hm(i * 15 + 15)}';
  if (q == null) return '$span · no data';
  return '$span · ${activeLevelLabel(q.level)} · ${stepsComma(q.steps)} '
      '${q.steps == 1 ? 'step' : 'steps'}';
}

// ── 一週 ──

class ActiveDay {
  final String date;
  final int? minutes; // 高強度＋活動；0／沒資料＝null（沒戴錶）
  final int? highMinutes;
  const ActiveDay(this.date, this.minutes, this.highMinutes);
}

class ActiveWeek {
  final List<ActiveDay> days; // 舊 → 新，日曆上 7 天
  final double? usual;
  final double? previousUsual;
  const ActiveWeek(this.days, this.usual, this.previousUsual);

  int get daysWithData => days.where((d) => d.minutes != null).length;
  double? get change =>
      usual == null || previousUsual == null ? null : usual! - previousUsual!;
}

double? _median(List<double> xs) {
  if (xs.isEmpty) return null;
  final s = [...xs]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// [endDate] 往回 7 天的活動時間（分鐘）。純函式。
ActiveWeek activeWeek(List<ActivityHistoryDay> history, String endDate) {
  final by = {for (final h in history) h.date: h};
  final end = DateTime.parse(endDate);
  List<ActiveDay> window(int offset) => [
    for (var i = 6; i >= 0; i--)
      () {
        final key = _iso(
          DateTime.utc(end.year, end.month, end.day - offset - i),
        );
        final h = by[key];
        final m = h?.activeMinutes;
        if (m == null || m <= 0) return ActiveDay(key, null, null);
        return ActiveDay(key, m, h?.highlyActiveMinutes);
      }(),
  ];
  double? usual(List<ActiveDay> ds) => _median([
    for (final d in ds)
      if (d.minutes != null) d.minutes!.toDouble(),
  ]);
  final days = window(0);
  return ActiveWeek(days, usual(days), usual(window(7)));
}

String activeUsualLine(ActiveWeek w) => 'Usually ${reportHm(w.usual!)} active';

String activeCountLine(ActiveWeek w) => w.daysWithData == w.days.length
    ? 'all ${w.days.length} days'
    : '${w.daysWithData} of ${w.days.length} days with data';

String? activeChangeLine(ActiveWeek w) {
  final c = w.change;
  if (c == null) return null;
  final r = c.round();
  if (r == 0) return '= same as the week before';
  return '${r > 0 ? '↑' : '↓'} ${reportHm(r.abs())} vs the week before';
}

// ── 山（報告上那一格） ──

class ActivityMountain extends StatelessWidget {
  final ActiveParts parts;
  const ActivityMountain({super.key, required this.parts});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: MountainPainter(parts), size: Size.infinite);
}

class MountainPainter extends CustomPainter {
  final ActiveParts parts;
  MountainPainter(this.parts);

  /// 段與段之間的過渡（山高的比例）：很短，不要整片糊在一起。
  static const blend = 0.02;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final apex = Offset(w * 0.44, h * 0.04);
    final left = Offset(w * 0.02, h), right = Offset(w * 0.98, h);

    // 太陽：只是裝飾
    final sun = Offset(w * 0.8, h * 0.2);
    final sr = math.min(w, h) * 0.1;
    canvas.drawCircle(
      sun,
      sr * 1.9,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sr * 0.8),
    );
    canvas.drawCircle(sun, sr, Paint()..color = const Color(0xFFFFF6E0));

    // 山：直邊三角形，山尖稍微圓一點（面積比例照三角形算，圓角只吃掉山尖一點點）
    final path = Path()
      ..moveTo(left.dx, left.dy)
      ..lineTo(apex.dx - w * 0.03, apex.dy + h * 0.05)
      ..quadraticBezierTo(
        apex.dx,
        apex.dy,
        apex.dx + w * 0.03,
        apex.dy + h * 0.05,
      )
      ..lineTo(right.dx, right.dy)
      ..close();

    final bands = mountainBands(parts);
    if (bands.isEmpty) return;
    final colors = <Color>[];
    final stops = <double>[];
    for (final (i, (level, top, bottom)) in bands.indexed) {
      final c = activeLevelColor(level);
      final isFirst = i == 0, isLast = i == bands.length - 1;
      final a = isFirst ? 0.0 : math.min(top + blend / 2, bottom);
      final b = isLast ? 1.0 : math.max(bottom - blend / 2, a);
      colors
        ..add(c)
        ..add(c);
      stops
        ..add(a)
        ..add(b);
    }
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
          stops: stops,
        ).createShader(Rect.fromLTRB(0, apex.dy, w, h)),
    );
  }

  @override
  bool shouldRepaint(MountainPainter old) =>
      old.parts.high != parts.high ||
      old.parts.active != parts.active ||
      old.parts.still != parts.still ||
      old.parts.sleep != parts.sleep;
}

// ── 點開的頁 ──

Future<void> showActiveSheet(
  BuildContext context, {
  required YesterdayActivity day,
  String? fontFamily,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => DefaultTextStyle.merge(
      style: TextStyle(fontFamily: fontFamily),
      child: ActiveView(day: day),
    ),
  );
}

class ActiveView extends StatelessWidget {
  final YesterdayActivity day;
  const ActiveView({super.key, required this.day});

  static const _soft = Color(0xB3FFFFFF);

  @override
  Widget build(BuildContext context) {
    final y = day;
    final parts = activeParts(y);
    final week = activeWeek(y.history, y.date);
    final showWeek = week.daysWithData > 0;
    final change = showWeek ? activeChangeLine(week) : null;
    final c = week.change?.round();
    final quarters = y.activityQuarters;

    return Container(
      key: const Key('active-sheet'),
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
                  const Icon(
                    Icons.bolt_rounded,
                    size: 20,
                    color: kActiveActive,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Active time',
                      style: TextStyle(
                        color: kActiveActive,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (showWeek)
                    const Text(
                      'Last 7 days',
                      softWrap: false,
                      style: TextStyle(color: _soft, fontSize: 12),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (parts != null) ...[
                Container(
                  key: const Key('active-day-card'),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0x14FFFFFF),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0x1FFFFFFF)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final (k, level, label, sec) in [
                              ('active-high', 'high', 'High', parts.high),
                              (
                                'active-active',
                                'active',
                                'Active',
                                parts.active,
                              ),
                              ('active-still', 'still', 'Still', parts.still),
                              if (y.sleepingSec != null)
                                (
                                  'active-sleep',
                                  'sleep',
                                  'Asleep (this day)',
                                  parts.sleep,
                                ),
                            ]) ...[
                              _Line(
                                key: Key(k),
                                color: activeLevelColor(level),
                                label: label,
                                value: reportHm(sec / 60),
                              ),
                              const SizedBox(height: 10),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 140,
                        height: 140,
                        child: CustomPaint(
                          key: const Key('active-ring'),
                          painter: _DayRingPainter(parts),
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    reportHm(parts.activeMinutes),
                                    key: const Key('active-total'),
                                    softWrap: false,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 26,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const Text(
                                    'active',
                                    style: TextStyle(
                                      color: _soft,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'From Garmin. The ring is the whole day, 24 hours. '
                  'Asleep counts only this calendar day, so it is not '
                  'the same as last night\'s sleep.',
                  key: Key('active-note'),
                  style: TextStyle(color: _soft, fontSize: 12, height: 1.35),
                ),
              ],
              // ── 一整天的時間軸 ──
              if (quarters != null) ...[
                const SizedBox(height: 22),
                const Text(
                  'Through the day',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Every 15 minutes. Tap or slide to see one.',
                  style: TextStyle(color: _soft, fontSize: 12),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 92,
                  child: _Timeline(quarters: quarters, moveIq: y.moveIq),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    for (final level in [
                      'high',
                      'active',
                      'still',
                      'sleep',
                      if (quarters.any((q) => q?.level == 'other')) 'other',
                    ])
                      _Legend(level: level),
                    if (y.moveIq?.isNotEmpty ?? false) const _MoveIqLegend(),
                  ],
                ),
              ],
              // ── 這一週 ──
              if (showWeek) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Container(height: 1, color: const Color(0x1FFFFFFF)),
                ),
                if (week.usual != null)
                  Text(
                    activeUsualLine(week),
                    key: const Key('active-week-usual'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                Text(
                  activeCountLine(week),
                  style: const TextStyle(color: _soft, fontSize: 13),
                ),
                if (change != null)
                  Text(
                    change,
                    key: const Key('active-week-change'),
                    style: TextStyle(
                      color: c! > 0
                          ? kDeltaUp
                          : (c < 0 ? kDeltaDown : kDeltaFlat),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 14),
                SizedBox(height: 150, child: _WeekBars(week: week)),
                const SizedBox(height: 6),
                const Wrap(
                  spacing: 12,
                  children: [
                    _Legend(level: 'high'),
                    _Legend(level: 'active'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  const _Line({
    super.key,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            softWrap: false,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final String level;
  const _Legend({required this.level});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: activeLevelColor(level),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          activeLevelLabel(level),
          style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 11),
        ),
      ],
    );
  }
}

class _MoveIqLegend extends StatelessWidget {
  const _MoveIqLegend();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 3,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        const Text(
          'Move IQ',
          style: TextStyle(color: Color(0x99FFFFFF), fontSize: 11),
        ),
      ],
    );
  }
}

/// 24 小時圓環：從正上方順時針 高強度 → 活動 → 坐 → 睡。
class _DayRingPainter extends CustomPainter {
  final ActiveParts parts;
  _DayRingPainter(this.parts);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final r = math.min(size.width, size.height) / 2 - stroke / 2;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    final total = parts.total.toDouble();
    if (total <= 0) return;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    var start = -math.pi / 2;
    for (final (level, v) in [
      ('high', parts.high),
      ('active', parts.active),
      ('still', parts.still),
      ('sleep', parts.sleep),
    ]) {
      if (v <= 0) continue;
      final sweep = 2 * math.pi * v / total;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        p..color = activeLevelColor(level),
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DayRingPainter old) =>
      old.parts.total != parts.total ||
      old.parts.high != parts.high ||
      old.parts.active != parts.active;
}

/// 一整天：96 格，每格 15 分鐘依程度上色；Move IQ 是上面的白線；點一下或滑動出泡泡。
class _Timeline extends StatefulWidget {
  final List<ActivityQuarter?> quarters;
  final List<MoveIqEvent>? moveIq;
  const _Timeline({required this.quarters, this.moveIq});

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
  static const double _labelH = 16, _moveH = 10, _barH = 30;
  int? _sel;

  @override
  Widget build(BuildContext context) {
    final q = widget.quarters;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final barTop = box.maxHeight - _labelH - _barH;
        final cell = w / 96;
        void pick(double x) =>
            setState(() => _sel = (x / cell).floor().clamp(0, 95));
        final sel = _sel;
        return TapRegion(
          onTapOutside: (_) {
            if (_sel != null) setState(() => _sel = null);
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Move IQ：時間軸上面一條白線（幾點開始、走了幾分鐘）
              for (final (i, e) in (widget.moveIq ?? const []).indexed)
                if (e.startMinuteOfDay != null)
                  Positioned(
                    key: Key('active-moveiq-$i'),
                    left: w * e.startMinuteOfDay! / 1440,
                    top: barTop - _moveH,
                    width: math.max(3, w * e.minutes / 1440),
                    height: 3,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              Positioned(
                left: 0,
                right: 0,
                top: barTop,
                height: _barH,
                child: GestureDetector(
                  key: const Key('active-timeline'),
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => pick(d.localPosition.dx),
                  onHorizontalDragStart: (d) => pick(d.localPosition.dx),
                  onHorizontalDragUpdate: (d) => pick(d.localPosition.dx),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Row(
                      children: [
                        for (var i = 0; i < 96; i++)
                          Expanded(
                            child: Container(
                              key: Key('active-q-$i'),
                              color: q[i] == null
                                  ? const Color(0x0FFFFFFF)
                                  : activeLevelColor(q[i]!.level).withValues(
                                      alpha: sel == null || sel == i ? 1 : 0.55,
                                    ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              for (final (frac, label) in [
                (0.0, '00'),
                (0.25, '06'),
                (0.5, '12'),
                (0.75, '18'),
              ])
                Positioned(
                  left: w * frac,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Color(0x99FFFFFF),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              if (sel != null)
                Positioned(
                  left: 0,
                  top: 0,
                  width: w,
                  height: barTop + _barH,
                  child: ProbeLayer(
                    dot: Offset(cell * (sel + 0.5), barTop + _barH / 2),
                    text: activeQuarterText(sel, q[sel]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 7 根：高強度（亮）疊在下面，活動在上面；沒資料寫「—」。
class _WeekBars extends StatelessWidget {
  final ActiveWeek week;
  const _WeekBars({required this.week});

  static const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final days = week.days;
    final hi = math.max(
      1,
      days.fold<int>(0, (m, d) => math.max(m, d.minutes ?? 0)),
    );
    return LayoutBuilder(
      builder: (context, box) {
        const valueH = 16.0, labelH = 18.0;
        final h = box.maxHeight - valueH - labelH;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (i, d) in days.indexed)
              Expanded(
                child: Column(
                  key: Key('active-week-$i'),
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      height: valueH,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          d.minutes == null ? '—' : reportHm(d.minutes!),
                          softWrap: false,
                          style: TextStyle(
                            color: i == days.length - 1
                                ? Colors.white
                                : const Color(0xB3FFFFFF),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: h,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: d.minutes == null
                            ? null
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(7),
                                child: SizedBox(
                                  width: 24,
                                  height: math.max(2, h * d.minutes! / hi),
                                  child: Column(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          key: Key('active-week-bar-$i'),
                                          color: kActiveActive.withValues(
                                            alpha: i == days.length - 1
                                                ? 1
                                                : 0.6,
                                          ),
                                        ),
                                      ),
                                      if ((d.highMinutes ?? 0) > 0)
                                        Container(
                                          key: Key('active-week-high-$i'),
                                          height: math.min(
                                            math.max(2, h * d.minutes! / hi),
                                            math.max(
                                              2,
                                              h * d.highMinutes! / hi,
                                            ),
                                          ),
                                          color: kActiveHigh.withValues(
                                            alpha: i == days.length - 1
                                                ? 1
                                                : 0.6,
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
                          _wd[DateTime.parse(d.date).weekday - 1],
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
