// 早晨報告 Sleeping heart rate 點開（2026-11-15 使用者定，grill Q1–Q7＋①②③）：
//
// 上半：**這一晚**——大數字＝睡著那一段的平均（後端從原始讀數算的，同格子），
//       「Lowest 46 at 03:48 · 15m after falling asleep」＋「Resting 55 (all day)」。
//       線每 5 分鐘一點、**依那一刻的睡眠階段上色**（同 Sleep Stages 的顏色；參考圖的運動心率區間
//       不照做——那是最大心率的百分比，睡著的心率全落在最低一區以下，而且沒有睡眠的文獻門檻）。
//       虛線＝平均、白點＝最低（原始讀數那一刻）。點／滑看那一刻（同 chart_probe）。
//       線下面每個階段的平均心率（Deep 51 · Light 55…）。
// 下半：**這一週**——7 欄，實心點＝平均（上面寫數字）、空心小點＝最低，中間一條細線；沒資料寫「—」。
//       「Usually 56 bpm」＝7 晚平均的**中間值**，「↑ 2 bpm vs the week before」只代表方向（紅升綠降）。
// - **不寫 Normal／High、不畫區間、不寫最高**（最高多半是短暫醒來，單獨列會被讀成問題）。
// - 靜止心率是手錶一整天的值、另一個量 → 只放在這一晚那一行，不進一週圖。
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/night_curve.dart';
import '../models/sleep_stages.dart';
import '../services/camera_insights.dart' show SleepHeartRate;
import '../services/night_compare.dart'
    show formatMinutes, kDeltaUp, kDeltaDown, kDeltaFlat;
import 'chart_probe.dart';
import 'sleep_stages_card.dart' show SleepStagesCard;

/// 階段的顏色（同 Sleep Stages 卡）。
const kStageColors = {
  'deep': SleepStagesCard.deep,
  'light': SleepStagesCard.light,
  'rem': SleepStagesCard.rem,
  'awake': SleepStagesCard.awake,
};

/// 照 Sleep Stages 圖例的順序（深 → 淺 → REM → 醒）。
const _stageOrder = ['deep', 'light', 'rem', 'awake'];

/// 換成 isUtc 的牆鐘（曲線與 Sleep Stages 都用這個基準；沒時區的字串會是本地時間，混著比會差 8 小時）。
DateTime _wall(DateTime t) => t.isUtc
    ? t
    : DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second);

/// 那一刻的階段（兩邊都換成同一個基準再比）。
String? _stageOf(SleepStages s, DateTime t) {
  final w = _wall(t);
  for (final seg in s.segments) {
    if (!w.isBefore(_wall(seg.start)) && w.isBefore(_wall(seg.end))) {
      return seg.stage;
    }
  }
  return null;
}

/// 每個階段的平均心率：線上每一點（5 分鐘平均）照那一刻的階段分組再平均。
/// 那一晚沒量到 REM → 不給 REM。照 Deep → Light → REM → Awake 排；沒有點的階段不給。純函式。
List<(String, double)> stageHeartRates(NightCurve curve, SleepStages? stages) {
  if (stages == null) return const [];
  final by = <String, List<double>>{};
  for (final p in curve.points) {
    final st = _stageOf(stages, p.time);
    if (st == null) continue;
    if (st == 'rem' && !stages.remMeasured) continue;
    by.putIfAbsent(st, () => []).add(p.value);
  }
  return [
    for (final st in _stageOrder)
      if (by[st] case final vs? when vs.isNotEmpty)
        (st, vs.reduce((a, b) => a + b) / vs.length),
  ];
}

String _clock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 「Lowest 46 at 03:48 · 15m after falling asleep」。入睡＝線的第一點（後端從入睡那一刻起算）。
/// 舊版後端沒有最低那一刻 → 只寫「Lowest 46」。
String lowestLine(NightCurve c) {
  final at = c.minAt;
  if (at == null) return 'Lowest ${c.min.round()}';
  final after = _wall(at).difference(_wall(c.points.first.time)).inMinutes;
  return 'Lowest ${c.min.round()} at ${_clock(at)}'
      '${after >= 0 ? ' · ${formatMinutes(after.toDouble())} after falling asleep' : ''}';
}

/// 一週裡的一晚；[hr] 是 null＝沒資料。
class HeartRateNight {
  final String date;
  final SleepHeartRate? hr;
  const HeartRateNight(this.date, this.hr);
}

class HeartRateWeek {
  final List<HeartRateNight> nights; // 舊 → 新，固定 7 格
  final double? usual; // 這 7 晚平均的中間值
  final double? previousUsual; // 再往前 7 晚的中間值
  const HeartRateWeek(this.nights, this.usual, this.previousUsual);

  int get nightsWithData => nights.where((n) => n.hr != null).length;
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

/// [endDate] 往回 7 晚（日曆上的 7 個晚上）。純函式。
HeartRateWeek heartRateWeek(Map<String, SleepHeartRate> byDate, String endDate) {
  final end = DateTime.parse(endDate);
  List<HeartRateNight> window(int offset) => [
    for (var i = 6; i >= 0; i--)
      () {
        final key = _iso(DateTime.utc(end.year, end.month, end.day - offset - i));
        return HeartRateNight(key, byDate[key]);
      }(),
  ];
  double? usual(List<HeartRateNight> ns) => _median([
    for (final n in ns)
      if (n.hr != null) n.hr!.avg,
  ]);
  final nights = window(0);
  return HeartRateWeek(nights, usual(nights), usual(window(7)));
}

/// 「Usually 56 bpm」。
String heartRateUsualLine(HeartRateWeek w) => 'Usually ${w.usual!.round()} bpm';

/// 幾晚有資料（同其他一週圖）。
String heartRateCountLine(HeartRateWeek w) => w.nightsWithData == w.nights.length
    ? 'all ${w.nights.length} nights'
    : '${w.nightsWithData} of ${w.nights.length} nights with data';

/// 「↑ 2 bpm vs the week before」；只代表方向。
String? heartRateChangeLine(HeartRateWeek w) {
  final c = w.change;
  if (c == null) return null;
  final r = c.round();
  if (r == 0) return '= same as the week before';
  return '${r > 0 ? '↑' : '↓'} ${r.abs()} bpm vs the week before';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

Future<void> showHeartRateSheet(
  BuildContext context, {
  required Color color,
  required NightCurve curve,
  required String date,
  SleepStages? stages,
  double? restingHeartRate,
  Map<String, SleepHeartRate>? week,
  String? fontFamily,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => DefaultTextStyle.merge(
      style: TextStyle(fontFamily: fontFamily),
      child: HeartRateView(
        color: color,
        curve: curve,
        stages: stages,
        restingHeartRate: restingHeartRate,
        week: week == null ? null : heartRateWeek(week, date),
      ),
    ),
  );
}

class HeartRateView extends StatelessWidget {
  final Color color;
  final NightCurve curve;
  final SleepStages? stages;
  final double? restingHeartRate;

  /// null＝沒有一週資料（連不到後端），下半整段不出現。
  final HeartRateWeek? week;

  const HeartRateView({
    super.key,
    required this.curve,
    this.stages,
    this.restingHeartRate,
    this.week,
    this.color = const Color(0xFFFF8AB8),
  });

  static const _soft = Color(0xB3FFFFFF);

  @override
  Widget build(BuildContext context) {
    final w = week;
    final showWeek = w != null && w.nightsWithData > 0;
    final change = showWeek ? heartRateChangeLine(w) : null;
    final c = w?.change?.round();
    final byStage = stageHeartRates(curve, stages);

    return Container(
      key: const Key('hr-sheet'),
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
                  Icon(Icons.favorite_rounded, size: 20, color: color),
                  const SizedBox(width: 8),
                  // Expanded（不是 Flexible＋Spacer）：兩者會平分剩下的寬度，標題被切成「Sleeping he…」（11-15 實機）
                  Expanded(
                    child: Text(
                      'Sleeping heart rate',
                      key: const Key('hr-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (showWeek)
                    const Text(
                      'Last 7 nights',
                      softWrap: false,
                      style: TextStyle(color: _soft, fontSize: 12),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // ── 這一晚 ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${curve.avg.round()}',
                    key: const Key('hr-avg'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'bpm average',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Text(
                lowestLine(curve),
                key: const Key('hr-lowest'),
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              if (restingHeartRate != null)
                Text(
                  'Resting ${restingHeartRate!.round()} (all day)',
                  key: const Key('hr-resting'),
                  style: const TextStyle(color: _soft, fontSize: 12),
                ),
              const SizedBox(height: 14),
              SizedBox(
                height: 190,
                child: NightHeartRateChart(
                  curve: curve,
                  stages: stages,
                  color: color,
                ),
              ),
              if (byStage.isNotEmpty) ...[
                const SizedBox(height: 16),
                _StageRows(rows: byStage, curve: curve),
              ],
              // ── 這一週 ──
              if (showWeek) ...[
                const SizedBox(height: 24),
                Container(height: 1, color: const Color(0x1FFFFFFF)),
                const SizedBox(height: 16),
                Text(
                  heartRateUsualLine(w),
                  key: const Key('hr-week-usual'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  heartRateCountLine(w),
                  key: const Key('hr-week-count'),
                  style: const TextStyle(color: _soft, fontSize: 13),
                ),
                if (change != null)
                  Text(
                    change,
                    key: const Key('hr-week-change'),
                    style: TextStyle(
                      color: c! > 0
                          ? kDeltaUp
                          : (c < 0 ? kDeltaDown : kDeltaFlat),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 14),
                SizedBox(
                  // 11-15 使用者：原本 170 太空，壓矮並加一條 Usually 的虛線
                  height: 130,
                  child: _WeekDots(week: w, color: color),
                ),
                const SizedBox(height: 6),
                Row(
                  key: const Key('hr-week-legend'),
                  children: [
                    _dot(color, filled: true),
                    const SizedBox(width: 5),
                    const Text('average', style: _legend),
                    const SizedBox(width: 14),
                    _dot(color, filled: false),
                    const SizedBox(width: 5),
                    const Text('lowest', style: _legend),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static const _legend = TextStyle(color: Color(0x99FFFFFF), fontSize: 11);

  static Widget _dot(Color c, {required bool filled}) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: filled ? c : null,
      border: filled ? null : Border.all(color: c, width: 1.6),
    ),
  );
}

/// 每個階段一列：名字、一條「這一晚最低 → 最高」的軌道上亮到那個階段的平均、右邊數字。
class _StageRows extends StatelessWidget {
  final List<(String, double)> rows;
  final NightCurve curve;
  const _StageRows({required this.rows, required this.curve});

  @override
  Widget build(BuildContext context) {
    final lo = curve.min, hi = math.max(curve.max, curve.min + 1);
    return Column(
      key: const Key('hr-stages'),
      children: [
        for (final (st, v) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    stageNames[st] ?? st,
                    style: const TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0x14FFFFFF),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor:
                          (0.08 + 0.92 * ((v - lo) / (hi - lo))).clamp(0.08, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: kStageColors[st],
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 62,
                  child: Text(
                    '${v.round()} bpm',
                    key: Key('hr-stage-$st'),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 這一晚的心率線：依階段上色、虛線平均、白點最低；點／滑看那一刻。
class NightHeartRateChart extends StatefulWidget {
  final NightCurve curve;
  final SleepStages? stages;
  final Color color;
  const NightHeartRateChart({
    super.key,
    required this.curve,
    required this.color,
    this.stages,
  });

  @override
  State<NightHeartRateChart> createState() => _NightHeartRateChartState();
}

class _NightHeartRateChartState extends State<NightHeartRateChart> {
  double? _probeX;

  static const double _axisW = 30; // 右邊刻度
  static const double _timeH = 18; // 底下時刻

  @override
  Widget build(BuildContext context) {
    final c = widget.curve;
    final t0 = _wall(c.points.first.time), t1 = _wall(c.points.last.time);
    final span = math.max(1, t1.difference(t0).inSeconds);
    final lo = (c.min - 4).floorToDouble(), hi = (c.max + 4).ceilToDouble();
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth - _axisW, h = box.maxHeight - _timeH;
        double xOf(DateTime t) => w * _wall(t).difference(t0).inSeconds / span;
        double yOf(double v) => h * (1 - (v - lo) / (hi - lo));

        Widget? probe;
        if (_probeX != null) {
          final t = t0.add(
            Duration(seconds: (span * (_probeX! / w).clamp(0.0, 1.0)).round()),
          );
          final p = nearestPoint(c.points, t);
          final at = p?.time ?? t;
          probe = ProbeLayer(
            dot: Offset(xOf(at), p == null ? h / 2 : yOf(p.value)),
            text: probeText(
              time: at,
              kind: ProbeKind.heartRate,
              point: p,
              stage: widget.stages == null
                  ? null
                  : _stageOf(widget.stages!, at),
            ),
          );
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ProbeGestures(
                onX: (x) => setState(() => _probeX = x.clamp(0.0, w)),
                onClear: () => setState(() => _probeX = null),
                child: CustomPaint(
                  key: const Key('hr-chart'),
                  painter: _HrPainter(
                    curve: c,
                    stages: widget.stages,
                    color: widget.color,
                    xOf: xOf,
                    yOf: yOf,
                    w: w,
                    h: h,
                  ),
                ),
              ),
            ),
            // 右邊刻度：上下界與平均
            for (final v in [hi, lo])
              Positioned(
                left: w + 6,
                top: yOf(v) - 7,
                child: Text(
                  '${v.round()}',
                  style: const TextStyle(color: Color(0x66FFFFFF), fontSize: 10),
                ),
              ),
            Positioned(
              left: w + 6,
              top: yOf(c.avg) - 7,
              child: Text(
                'avg',
                key: const Key('hr-avg-label'),
                style: TextStyle(
                  color: widget.color.withValues(alpha: 0.9),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            // 最低那一點的數字
            if (c.minAt != null)
              Positioned(
                left: (xOf(c.minAt!) - 14).clamp(0.0, w - 28),
                top: yOf(c.min) + 6,
                width: 28,
                child: Text(
                  '${c.min.round()}',
                  key: const Key('hr-lowest-label'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            Positioned(
              left: 0,
              bottom: 0,
              child: Text(
                _clock(t0),
                style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 11),
              ),
            ),
            Positioned(
              left: w - 40,
              width: 40,
              bottom: 0,
              child: Text(
                _clock(t1),
                textAlign: TextAlign.right,
                style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 11),
              ),
            ),
            if (probe != null) Positioned(left: 0, top: 0, width: w, height: h, child: probe),
          ],
        );
      },
    );
  }
}

class _HrPainter extends CustomPainter {
  final NightCurve curve;
  final SleepStages? stages;
  final Color color;
  final double Function(DateTime) xOf;
  final double Function(double) yOf;
  final double w, h;
  _HrPainter({
    required this.curve,
    required this.stages,
    required this.color,
    required this.xOf,
    required this.yOf,
    required this.w,
    required this.h,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 底線與平均虛線
    canvas.drawLine(
      Offset(0, h),
      Offset(w, h),
      Paint()
        ..color = const Color(0x1FFFFFFF)
        ..strokeWidth = 1,
    );
    final ya = yOf(curve.avg);
    final dash = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 1.4;
    for (var x = 0.0; x < w; x += 9) {
      canvas.drawLine(Offset(x, ya), Offset(math.min(x + 5, w), ya), dash);
    }
    // 線：每一小段用起點那一刻的階段上色；不在任何一段 → 心率色
    final pts = curve.points;
    for (var i = 0; i < pts.length - 1; i++) {
      final st = stages == null ? null : _stageOf(stages!, pts[i].time);
      final col = (st == 'rem' && stages?.remMeasured == false)
          ? color
          : (kStageColors[st] ?? color);
      canvas.drawLine(
        Offset(xOf(pts[i].time), yOf(pts[i].value)),
        Offset(xOf(pts[i + 1].time), yOf(pts[i + 1].value)),
        Paint()
          ..color = col
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round,
      );
    }
    // 最低那一刻（原始讀數）：白點
    if (curve.minAt != null) {
      final o = Offset(xOf(curve.minAt!).clamp(0.0, w), yOf(curve.min));
      canvas.drawCircle(o, 5, Paint()..color = Colors.white);
      canvas.drawCircle(
        o,
        5,
        Paint()
          ..color = const Color(0xFF1B1F48)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_HrPainter old) =>
      old.curve != curve || old.stages != stages || old.w != w || old.h != h;
}

/// 7 欄：實心點＝平均（上面寫數字）、空心小點＝最低、中間細線；沒資料寫「—」。
class _WeekDots extends StatelessWidget {
  final HeartRateWeek week;
  final Color color;
  const _WeekDots({required this.week, required this.color});

  static const double _labelH = 22;
  static const double _valueH = 16;

  @override
  Widget build(BuildContext context) {
    final have = [
      for (final n in week.nights)
        if (n.hr != null) n.hr!,
    ];
    final lo = have.map((x) => x.min).reduce(math.min) - 3;
    final hi = have.map((x) => x.avg).reduce(math.max) + 3;
    return LayoutBuilder(
      builder: (context, box) {
        final plotH = box.maxHeight - _labelH - _valueH;
        double yOf(double v) => _valueH + plotH * (1 - (v - lo) / (hi - lo));
        return Stack(
          children: [
            // Usually（中間值）的虛線，穿過七欄
            if (week.usual != null)
              Positioned(
                key: const Key('hr-week-usual-line'),
                left: 0,
                right: 0,
                top: yOf(week.usual!) - 1,
                height: 2,
                child: CustomPaint(painter: _DashPainter(color)),
              ),
            Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < week.nights.length; i++)
              Expanded(
                child: () {
                  final n = week.nights[i];
                  final isLast = i == week.nights.length - 1;
                  final d = DateTime.parse(n.date);
                  final hr = n.hr;
                  final strong = isLast ? 1.0 : 0.7;
                  return Semantics(
                    label:
                        '${_weekdays[d.weekday - 1]} ${d.day}: '
                        '${hr == null ? 'no data' : 'average ${hr.avg.round()}, lowest ${hr.min.round()}'}',
                    child: Column(
                      key: Key('hr-week-col-${n.date}'),
                      children: [
                        SizedBox(
                          height: _valueH + plotH,
                          child: LayoutBuilder(
                            builder: (context, col) {
                              final cx = col.maxWidth / 2;
                              if (hr == null) {
                                return Center(
                                  child: Text(
                                    '—',
                                    key: Key('hr-week-value-${n.date}'),
                                    style: const TextStyle(
                                      color: Color(0x66FFFFFF),
                                      fontSize: 11,
                                    ),
                                  ),
                                );
                              }
                              final ya = yOf(hr.avg), yl = yOf(hr.min);
                              return Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned(
                                    left: cx - 1,
                                    width: 2,
                                    top: ya,
                                    height: math.max(0, yl - ya),
                                    child: ColoredBox(
                                      color: color.withValues(alpha: 0.35 * strong),
                                    ),
                                  ),
                                  Positioned(
                                    key: Key('hr-week-min-${n.date}'),
                                    left: cx - 4,
                                    top: yl - 4,
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: const Color(0xFF1B1F48),
                                        border: Border.all(
                                          color: color.withValues(alpha: strong),
                                          width: 1.6,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    key: Key('hr-week-avg-${n.date}'),
                                    left: cx - 6,
                                    top: ya - 6,
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: color.withValues(alpha: strong),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    top: ya - 6 - _valueH,
                                    height: _valueH,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        '${hr.avg.round()}',
                                        key: Key('hr-week-value-${n.date}'),
                                        style: TextStyle(
                                          color: isLast
                                              ? Colors.white
                                              : const Color(0xCCFFFFFF),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        SizedBox(
                          height: _labelH,
                          child: Center(
                            child: Text(
                              _weekdays[d.weekday - 1],
                              style: TextStyle(
                                color: isLast
                                    ? Colors.white
                                    : const Color(0x99FFFFFF),
                                fontSize: 11,
                                fontWeight: isLast ? FontWeight.w800 : null,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }(),
              ),
          ],
        ),
          ],
        );
      },
    );
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  _DashPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..strokeWidth = 1.2;
    final y = size.height / 2;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, size.width), y), p);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}
