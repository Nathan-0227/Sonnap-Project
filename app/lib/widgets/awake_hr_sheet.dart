import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/awake_heart_rate.dart';
import '../models/yesterday_activity.dart';
import 'chart_probe.dart' show ProbeLayer;
import 'report_sheet.dart';

// 早晨報告 Yesterday 的 **Awake HR**（2026-11-15 使用者定，參考 Apple Watch 的心率圖示）：
// - 報告上那一格：發光的珊瑚紅愛心，**跟著醒著的平均心率跳**（78 bpm＝每分鐘 78 下；
//   系統開「減少動態效果」時靜止）。大字「78 BPM」、小字「peak 150 at 17:20」。
// - 點開：平均＋最高；整天的線（手錶每 2 分鐘一筆的原始讀數，沒戴錶的空檔斷開、
//   睡著那段畫淡寫 asleep · see Sleeping HR；點／滑看那一刻，離讀數超過 2 分鐘寫 no reading）；
//   各區間幾分鐘（Garmin 的區間，寫明 max 199）；一週醒著的平均與最高。
// 🔴 不寫 Normal／High、**不比平常**、**不放靜止心率與最低**（使用者定）：
//    `Research-Background/心率門檻.md` 查過，醒著的平均心率沒有結果關聯的切點，
//    又主要取決於那天走了多少路；靜止心率在報告上半部已經有了。
//    區間只寫幾分鐘，不說哪一區好。
// ⚠️ 跟上面的 Sleeping HR（睡著那一段）分開：這裡的平均只算醒著的。

const kAwakeHr = Color(0xFFFF7A7A);
const kAwakeHrDeep = Color(0xFFD9304F);
const kAwakeHrLight = Color(0xFFFFC2B5);

String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String awakeHrTileValue(AwakeHeartRate a) => '${a.avg} BPM';

String awakeHrTileLine(AwakeHeartRate a) =>
    a.maxAt == null ? 'peak ${a.max}' : 'peak ${a.max} at ${_hm(a.maxAt!)}';

/// 一整天的線上某個時刻：吸到最近的原始讀數；離最近的讀數超過 2 分鐘 → no reading（不內插）。
/// 睡著那段照樣報數字，後面加 asleep。
String awakeHrProbeText(AwakeHeartRate a, int minuteOfDay) {
  HrReading? best;
  var bestD = 1 << 30;
  for (final r in a.readings) {
    final d = (r.t.hour * 60 + r.t.minute - minuteOfDay).abs();
    if (d < bestD) {
      bestD = d;
      best = r;
    }
  }
  final hh = (minuteOfDay ~/ 60).toString().padLeft(2, '0');
  final mm = (minuteOfDay % 60).toString().padLeft(2, '0');
  if (best == null || bestD > 2) return '$hh:$mm · no reading';
  return '${_hm(best.t)} · ${best.bpm} bpm'
      '${a.isAsleep(best.t) ? ' · asleep' : ''}';
}

/// 區間的名字：低於 1 區寫 Below zone 1，其餘 Zone 1…5（照 Garmin 的叫法，不加好壞）。
String awakeHrZoneLabel(int i) => i == 0 ? 'Below zone 1' : 'Zone $i';

/// 區間的範圍「100–118」；最後一區「179+」；低於 1 區「< 100」。
String awakeHrZoneRange(List<int> floors, int i) {
  if (i == 0) return '< ${floors.first}';
  if (i == floors.length) return '${floors.last}+';
  return '${floors[i - 1]}–${floors[i] - 1}';
}

/// 0 分鐘的區間合成一句：「Zone 4, Zone 5: 0m」。
String awakeHrEmptyZonesLine(List<int> minutes) =>
    '${[for (var i = 0; i < minutes.length; i++)
      if (minutes[i] == 0) awakeHrZoneLabel(i)].join(', ')}: 0m';

String _minutes(int m) =>
    m < 60 ? '${m}m' : (m % 60 == 0 ? '${m ~/ 60}h' : '${m ~/ 60}h ${m % 60}m');

// ── 報告上那一格的愛心 ──

/// 愛心的形狀（單位方框 0–1）。
Path awakeHeartPath(Rect r) {
  final w = r.width, h = r.height;
  Offset p(double x, double y) => Offset(r.left + w * x, r.top + h * y);
  final a = p(0.5, 0.27);
  return Path()
    ..moveTo(a.dx, a.dy)
    ..cubicTo(
      p(0.5, 0.06).dx,
      p(0.5, 0.06).dy,
      p(0.16, -0.03).dx,
      p(0.16, -0.03).dy,
      p(0.04, 0.22).dx,
      p(0.04, 0.22).dy,
    )
    ..cubicTo(
      p(-0.06, 0.46).dx,
      p(-0.06, 0.46).dy,
      p(0.2, 0.7).dx,
      p(0.2, 0.7).dy,
      p(0.5, 0.96).dx,
      p(0.5, 0.96).dy,
    )
    ..cubicTo(
      p(0.8, 0.7).dx,
      p(0.8, 0.7).dy,
      p(1.06, 0.46).dx,
      p(1.06, 0.46).dy,
      p(0.96, 0.22).dx,
      p(0.96, 0.22).dy,
    )
    ..cubicTo(
      p(0.84, -0.03).dx,
      p(0.84, -0.03).dy,
      p(0.5, 0.06).dx,
      p(0.5, 0.06).dy,
      a.dx,
      a.dy,
    )
    ..close();
}

/// 一次心跳的形狀（0–1 的一個週期）：「撲通」兩下，第二下小一點。
double heartBeat(double t) {
  double bump(double c, double w) {
    final d = (t - c) / w;
    return d.abs() >= 1 ? 0 : (1 + math.cos(math.pi * d)) / 2;
  }

  return math.max(bump(0.08, 0.08), 0.55 * bump(0.26, 0.08));
}

/// 發光的愛心，跟著 [bpm] 跳；系統開「減少動態效果」時靜止。
class GlowingHeart extends StatefulWidget {
  final int bpm;
  const GlowingHeart({super.key, required this.bpm});

  @override
  State<GlowingHeart> createState() => _GlowingHeartState();
}

class _GlowingHeartState extends State<GlowingHeart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _period,
  );

  Duration get _period =>
      Duration(milliseconds: (60000 / widget.bpm.clamp(30, 220)).round());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(GlowingHeart old) {
    super.didUpdateWidget(old);
    if (old.bpm != widget.bpm) {
      _c.duration = _period;
      _sync(restart: true);
    }
  }

  void _sync({bool restart = false}) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _c.stop();
      _c.value = 0;
    } else if (restart || !_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: GlowingHeartPainter(heartBeat(_c.value)),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class GlowingHeartPainter extends CustomPainter {
  /// 0＝兩下之間，1＝跳到最大。
  final double beat;
  GlowingHeartPainter(this.beat);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // 11-15 使用者定：愛心置中（標題與底下的字之間）
    final side = math.min(w * 0.58, h * 0.56);
    final c = Offset(w * 0.5, h * 0.44);
    final s = side * (1 + 0.06 * beat);
    final box = Rect.fromCenter(center: c, width: s, height: s * 0.92);
    final heart = awakeHeartPath(box);

    // 外面一圈光：跳的時候亮一點
    canvas.drawPath(
      awakeHeartPath(box.inflate(side * 0.1)),
      Paint()
        ..color = kAwakeHr.withValues(alpha: 0.32 + 0.18 * beat)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, side * 0.16),
    );
    // 本體：左上亮、右下深
    canvas.drawPath(
      heart,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.45, -0.5),
          radius: 1.1,
          colors: const [kAwakeHrLight, kAwakeHr, kAwakeHrDeep],
          stops: const [0, 0.45, 1],
        ).createShader(box),
    );
    // 左上的反光
    canvas.save();
    canvas.clipPath(heart);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(box.left + box.width * 0.3, box.top + box.height * 0.28),
        width: box.width * 0.34,
        height: box.height * 0.2,
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, side * 0.05),
    );
    canvas.restore();
    // 亮邊
    canvas.drawPath(
      heart,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.28),
    );
  }

  @override
  bool shouldRepaint(GlowingHeartPainter old) => old.beat != beat;
}

// ── 點開的頁 ──

Future<void> showAwakeHrSheet(
  BuildContext context, {
  required YesterdayActivity day,
  String? fontFamily,
}) {
  return showReportSheet<void>(
    context: context,
    builder: (context) => DefaultTextStyle.merge(
      style: TextStyle(fontFamily: fontFamily),
      child: AwakeHrView(day: day),
    ),
  );
}

/// 一週：[endDate] 往回 7 天，醒著的平均與最高；沒資料是 null。
List<(String, int?, int?)> awakeHrWeek(
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
        final h = by[key];
        return (key, h?.awakeHrAvg, h?.awakeHrMax);
      }(),
  ];
}

class AwakeHrView extends StatelessWidget {
  final YesterdayActivity day;
  const AwakeHrView({super.key, required this.day});

  static const _soft = Color(0xB3FFFFFF);

  @override
  Widget build(BuildContext context) {
    final a = day.awakeHeartRate!;
    final week = awakeHrWeek(day.history, day.date);
    final showWeek = week.any((d) => d.$2 != null);
    final zones = a.zoneMinutes;
    final floors = a.zoneFloors;
    final zoneTotal = zones?.fold<int>(0, (s, v) => s + v) ?? 0;

    return Container(
      key: const Key('awake-hr-sheet'),
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
                  Icon(Icons.favorite_rounded, size: 20, color: kAwakeHr),
                  SizedBox(width: 8),
                  Text(
                    'Awake HR',
                    style: TextStyle(
                      color: kAwakeHr,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      key: const Key('awake-hr-avg'),
                      value: '${a.avg}',
                      label: 'average while awake',
                    ),
                  ),
                  Expanded(
                    child: _Stat(
                      key: const Key('awake-hr-peak'),
                      value: '${a.max}',
                      label: a.maxAt == null
                          ? 'peak'
                          : 'peak at ${_hm(a.maxAt!)}',
                    ),
                  ),
                ],
              ),
              if (a.readings.isNotEmpty) ...[
                const _Divider(),
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
                  'Tap or slide to see a reading.',
                  style: TextStyle(color: _soft, fontSize: 12),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 170,
                  child: _DayLine(hr: a, moves: day.moveIq),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    if (a.asleep.isNotEmpty)
                      _Key(
                        swatch: const Color(0x1FFFFFFF),
                        text: 'Asleep · see Sleeping HR',
                      ),
                    if (day.moveIq?.isNotEmpty ?? false)
                      _Key(
                        swatch: kAwakeHrLight.withValues(alpha: 0.6),
                        text: 'Move IQ',
                        thin: true,
                      ),
                  ],
                ),
              ],
              if (zones != null && floors != null && zoneTotal > 0) ...[
                const _Divider(),
                const Text(
                  'Time in zones',
                  key: Key('awake-hr-zones-title'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  a.zoneMax == null
                      ? 'Garmin zones · awake only'
                      : 'Garmin zones · max ${a.zoneMax} · awake only',
                  key: const Key('awake-hr-zones-note'),
                  style: const TextStyle(color: _soft, fontSize: 12),
                ),
                const SizedBox(height: 12),
                // 11-15 使用者：資訊太多 → 0 分鐘的區間不列一行，最後一句帶過
                for (var i = zones.length - 1; i >= 0; i--)
                  if (zones[i] > 0)
                    _ZoneRow(
                      key: Key('awake-hr-zone-$i'),
                      label: awakeHrZoneLabel(i),
                      range: awakeHrZoneRange(floors, i),
                      minutes: zones[i],
                      fraction: zones[i] / zoneTotal,
                      color: Color.lerp(
                        const Color(0xFF6F7AB8),
                        kAwakeHr,
                        i / (zones.length - 1),
                      )!,
                    ),
                if (zones.any((m) => m == 0))
                  Text(
                    awakeHrEmptyZonesLine(zones),
                    key: const Key('awake-hr-zones-empty'),
                    style: const TextStyle(color: _soft, fontSize: 12),
                  ),
              ],
              if (showWeek) ...[
                const _Divider(),
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
                  'Dot = average · line = peak',
                  style: TextStyle(color: _soft, fontSize: 12),
                ),
                const SizedBox(height: 12),
                SizedBox(height: 170, child: _WeekChart(week: week)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({super.key, required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w900,
              ),
            ),
            const TextSpan(
              text: ' bpm',
              style: TextStyle(
                color: Color(0xB3FFFFFF),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        softWrap: false,
      ),
      Text(
        label,
        style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 12),
      ),
    ],
  );
}

class _Key extends StatelessWidget {
  final Color swatch;
  final String text;
  final bool thin;
  const _Key({required this.swatch, required this.text, this.thin = false});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: thin ? 3 : 14,
        height: 10,
        decoration: BoxDecoration(
          color: swatch,
          borderRadius: BorderRadius.circular(thin ? 1 : 3),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        text,
        style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 11),
      ),
    ],
  );
}

/// 段落之間的細線（11-15 使用者：資訊之間要有一條線）。
class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Container(height: 1, color: const Color(0x1FFFFFFF)),
  );
}

class _ZoneRow extends StatelessWidget {
  final String label;
  final String range;
  final int minutes;
  final double fraction;
  final Color color;
  const _ZoneRow({
    super.key,
    required this.label,
    required this.range,
    required this.minutes,
    required this.fraction,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        SizedBox(
          width: 150,
          child: Text.rich(
            maxLines: 1,
            TextSpan(
              children: [
                TextSpan(
                  text: '$label  ',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: '$range bpm',
                  style: const TextStyle(
                    color: Color(0x99FFFFFF),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: minutes == 0 ? 2 : math.max(4, box.maxWidth * fraction),
                height: 12,
                decoration: BoxDecoration(
                  color: minutes == 0 ? const Color(0x33FFFFFF) : color,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 66,
          child: Text(
            _minutes(minutes),
            softWrap: false,
            overflow: TextOverflow.visible,
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
  );
}

class _DayLine extends StatefulWidget {
  final AwakeHeartRate hr;
  final List<MoveIqEvent>? moves;
  const _DayLine({required this.hr, this.moves});

  @override
  State<_DayLine> createState() => _DayLineState();
}

class _DayLineState extends State<_DayLine> {
  static const double _labelH = 16;
  int? _minute;

  @override
  Widget build(BuildContext context) {
    final a = widget.hr;
    final (lo, hi) = _range(a);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight - _labelH;
        void pick(double x) =>
            setState(() => _minute = (x / w * 1440).round().clamp(0, 1439));
        final m = _minute;
        HrReading? snap;
        if (m != null) {
          var bestD = 1 << 30;
          for (final r in a.readings) {
            final d = (r.t.hour * 60 + r.t.minute - m).abs();
            if (d < bestD) {
              bestD = d;
              snap = r;
            }
          }
          if (bestD > 2) snap = null;
        }
        final dot = m == null
            ? null
            : snap == null
            ? Offset(w * m / 1440, h)
            : Offset(
                w * (snap.t.hour * 60 + snap.t.minute) / 1440,
                h * (1 - (snap.bpm - lo) / (hi - lo)),
              );
        return TapRegion(
          onTapOutside: (_) {
            if (_minute != null) setState(() => _minute = null);
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: h,
                child: GestureDetector(
                  key: const Key('awake-hr-day-line'),
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => pick(d.localPosition.dx),
                  onHorizontalDragStart: (d) => pick(d.localPosition.dx),
                  onHorizontalDragUpdate: (d) => pick(d.localPosition.dx),
                  child: CustomPaint(
                    painter: _DayLinePainter(a, widget.moves, lo, hi),
                    size: Size.infinite,
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
              if (m != null && dot != null)
                Positioned(
                  left: 0,
                  top: 0,
                  width: w,
                  height: h,
                  child: ProbeLayer(dot: dot, text: awakeHrProbeText(a, m)),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 縱軸範圍：照那天的讀數，上下各留一點、對齊到 20。
(double, double) _range(AwakeHeartRate a) {
  var lo = 1 << 30, hi = 0;
  for (final r in a.readings) {
    lo = math.min(lo, r.bpm);
    hi = math.max(hi, r.bpm);
  }
  if (hi == 0) return (40, 160);
  final l = ((lo - 5) / 20).floor() * 20.0;
  final u = ((hi + 5) / 20).ceil() * 20.0;
  return (l, u <= l ? l + 20 : u);
}

class _DayLinePainter extends CustomPainter {
  final AwakeHeartRate hr;
  final List<MoveIqEvent>? moves;
  final double lo, hi;
  _DayLinePainter(this.hr, this.moves, this.lo, this.hi);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    double x(DateTime t) => w * (t.hour * 60 + t.minute + t.second / 60) / 1440;
    double xm(int minute) => w * minute / 1440;
    double yv(num v) => h * (1 - (v - lo) / (hi - lo));
    final day0 = hr.readings.isEmpty ? null : hr.readings.first.t;

    // 睡著：淡底色
    final sleepPaint = Paint()..color = const Color(0x1FFFFFFF);
    for (final (s, e) in hr.asleep) {
      final left = day0 != null && s.day != day0.day ? 0.0 : x(s);
      final right = day0 != null && e.day != day0.day ? w : x(e);
      canvas.drawRect(Rect.fromLTRB(left, 0, right, h), sleepPaint);
    }
    // Move IQ：底下細細的一段
    final mv = Paint()..color = kAwakeHrLight.withValues(alpha: 0.6);
    for (final m in moves ?? const <MoveIqEvent>[]) {
      final s = m.startMinuteOfDay;
      if (s == null) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            xm(s),
            h - 4,
            math.max(xm(s) + 3, xm(s + m.minutes)),
            h,
          ),
          const Radius.circular(1.5),
        ),
        mv,
      );
    }
    // 刻度：每 20 一條淡線，數字寫在右邊
    final grid = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 1;
    for (var v = lo + 20; v < hi; v += 20) {
      canvas.drawLine(Offset(0, yv(v)), Offset(w, yv(v)), grid);
      final tp = TextPainter(
        text: TextSpan(
          text: '${v.round()}',
          style: const TextStyle(color: Color(0x66FFFFFF), fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(w - tp.width - 2, yv(v) - tp.height - 1));
    }

    // 線：醒著亮、睡著淡；兩筆相隔超過 4 分鐘＝中間沒戴錶 → 斷開
    final awake = Paint()
      ..color = kAwakeHr
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round;
    final asleep = Paint()
      ..color = kAwakeHr.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeJoin = StrokeJoin.round;
    HrReading? prev;
    for (final r in hr.readings) {
      if (prev != null && r.t.difference(prev.t).inSeconds <= 240) {
        canvas.drawLine(
          Offset(x(prev.t), yv(prev.bpm)),
          Offset(x(r.t), yv(r.bpm)),
          hr.isAsleep(r.t) ? asleep : awake,
        );
      }
      prev = r;
    }
    // 最高那一點
    final at = hr.maxAt;
    if (at != null) {
      final p = Offset(x(at), yv(hr.max));
      canvas.drawCircle(p, 4, Paint()..color = Colors.white);
      canvas.drawCircle(p, 2.4, Paint()..color = kAwakeHrDeep);
    }
  }

  @override
  bool shouldRepaint(_DayLinePainter old) =>
      old.hr != hr || old.moves != moves || old.lo != lo || old.hi != hi;
}

/// 7 天：點＝醒著的平均，往上一條細線到那天的最高；數字寫平均；沒資料寫「—」。
class _WeekChart extends StatelessWidget {
  final List<(String, int?, int?)> week;
  const _WeekChart({required this.week});

  static const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final vals = [
      for (final d in week) ...[?d.$2, ?d.$3],
    ];
    final lo = ((vals.reduce(math.min) - 10) / 20).floor() * 20.0;
    final hi = ((vals.reduce(math.max) + 5) / 20).ceil() * 20.0;
    return LayoutBuilder(
      builder: (context, box) {
        const valueH = 16.0, labelH = 18.0;
        final h = box.maxHeight - valueH - labelH;
        double y(int v) => h * (1 - (v - lo) / (hi - lo));
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (i, d) in week.indexed)
              Expanded(
                child: Column(
                  key: Key('awake-hr-week-$i'),
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      height: valueH,
                      child: Text(
                        d.$2 == null ? '—' : '${d.$2}',
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
                      width: 24,
                      child: d.$2 == null
                          ? null
                          : CustomPaint(
                              painter: _WeekDayPainter(
                                y(d.$2!),
                                d.$3 == null ? null : y(d.$3!),
                                i == week.length - 1,
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

class _WeekDayPainter extends CustomPainter {
  final double avgY;
  final double? peakY;
  final bool last;
  _WeekDayPainter(this.avgY, this.peakY, this.last);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final color = kAwakeHr.withValues(alpha: last ? 1 : 0.7);
    if (peakY != null) {
      canvas.drawLine(
        Offset(cx, avgY),
        Offset(cx, peakY!),
        Paint()
          ..color = color.withValues(alpha: last ? 0.6 : 0.4)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(Offset(cx, peakY!), 2.5, Paint()..color = color);
    }
    canvas.drawCircle(Offset(cx, avgY), last ? 7 : 6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_WeekDayPainter old) =>
      old.avgY != avgY || old.peakY != peakY || old.last != last;
}
