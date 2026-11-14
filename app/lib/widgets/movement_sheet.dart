// 早晨報告 Movement (camera) 點開（2026-11-15 使用者定，grill Q1–Q7）：
//
// 上半：**這一晚**——後端那句「About the same as usual」＋「not part of your score」，
//       這一晚的動作次數（11-15 使用者改，原本 11-09 定不寫）；**不寫每小時幾次、不跟常模並列**（跨夜差到 3.1 倍）。
//       片段：照參考圖一段一列（縮圖＋大的時刻＋「moved for 5 s · Light」＋播放鍵），點了跳出大的循環播放，再點影片全螢幕、兩指放大；
//       每段標籤照抄後端，後面接那一刻**手錶的睡眠階段**（「03:42 · moved for 5 s · Light」）。
//       沒錄影的晚上照抄後端那句原因。下面是那一晚的動作線（每 5 分鐘有幾成在動），
//       三個片段的時刻標成點，點了一樣跳出播放（在線的範圍外的片段不標）。
// 下半：**這一週**——7 欄，每晚跟它自己的「平常」比多幾 %（後端 delta_pct，照抄），
//       中間灰帶＝「差不多」的範圍（寬度照抄後端 same_as_usual_pct）；沒錄影或基線不夠寫「—」。
//       **不分好壞**：動得多不代表睡不好（攝影機動作率跟手錶的清醒量測沒有相關），所以只用一個顏色。
// - 不做「最長靜止多久」（Q7：又要訂一個「多久算靜止」，而攝影機動作本身跨夜就很不穩）。
// - 整夜錄影（一晚約 460 MB、只在電腦上）不放。
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/night_curve.dart';
import '../models/sleep_stages.dart';
import '../services/camera_insights.dart' show CameraClip, CameraNight;
import 'chart_probe.dart' show stageNames;

/// 換成 isUtc 的牆鐘（曲線、Sleep Stages、片段時刻三種基準不同，混著比會差 8 小時）。
DateTime _wall(DateTime t) => t.isUtc
    ? t
    : DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second);

String? _stageAt(SleepStages? s, DateTime? t) {
  if (s == null || t == null) return null;
  final w = _wall(t);
  for (final seg in s.segments) {
    if (!w.isBefore(_wall(seg.start)) && w.isBefore(_wall(seg.end))) {
      return seg.stage;
    }
  }
  return null;
}

/// 片段標籤：後端那句照抄，後面接手錶那一刻的睡眠階段（不在睡著範圍內就不接）。
String clipLabel(CameraClip c, SleepStages? stages) {
  final st = _stageAt(stages, c.startAt);
  if (st == null) return c.label;
  if (st == 'rem' && stages?.remMeasured == false) return c.label;
  return '${c.label} · ${stageNames[st] ?? st}';
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// [endDate] 往回 7 晚（舊 → 新）；沒錄影的晚上是 null。純函式。
List<(String, CameraNight?)> movementWeek(
  List<CameraNight> nights,
  String endDate,
) {
  final by = {for (final n in nights) n.date: n};
  final end = DateTime.parse(endDate);
  return [
    for (var i = 6; i >= 0; i--)
      () {
        final key = _iso(DateTime.utc(end.year, end.month, end.day - i));
        return (key, by[key]);
      }(),
  ];
}

/// 一週那一欄的字：「+12%」「−27%」「0%」；沒錄影或基線不夠 → 「—」。
String movementWeekValue(CameraNight? n) {
  final d = n?.usualDeltaPct;
  if (d == null) return '—';
  final r = d.round();
  if (r == 0) return '0%';
  return r > 0 ? '+$r%' : '−${r.abs()}%';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

Future<void> showMovementSheet(
  BuildContext context, {
  required Color color,
  required CameraNight night,
  required String date,
  NightCurve? curve,
  SleepStages? stages,
  List<CameraNight>? week,
  String? fontFamily,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => DefaultTextStyle.merge(
      style: TextStyle(fontFamily: fontFamily),
      child: MovementView(
        color: color,
        night: night,
        curve: curve,
        stages: stages,
        week: week == null ? null : movementWeek(week, date),
      ),
    ),
  );
}

class MovementView extends StatefulWidget {
  final Color color;
  final CameraNight night;
  final NightCurve? curve;
  final SleepStages? stages;

  /// null＝沒有一週資料（連不到後端），下半整段不出現。
  final List<(String, CameraNight?)>? week;

  const MovementView({
    super.key,
    required this.night,
    this.curve,
    this.stages,
    this.week,
    this.color = const Color(0xFFFFD96A),
  });

  @override
  State<MovementView> createState() => _MovementViewState();
}

class _MovementViewState extends State<MovementView> {
  static const _soft = Color(0xB3FFFFFF);

  /// 點一列（或線上的點）→ 大的播放（2026-11-15 使用者定，照參考圖：列表＋點進去看）。
  void _play(CameraClip c) {
    showDialog<void>(
      context: context,
      barrierColor: const Color(0xE6080A1C),
      builder: (context) => _ClipViewer(
        clip: c,
        label: clipLabel(c, widget.stages),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.night;
    final clips = n.clips;
    final color = widget.color;
    final w = widget.week;
    final showWeek = w != null && w.any((e) => e.$2?.usualDeltaPct != null);

    return Container(
      key: const Key('mv-sheet'),
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
                  Icon(Icons.videocam_rounded, size: 20, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Movement (camera)',
                      key: const Key('mv-title'),
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
              if (n.usualLabel != null)
                Text(
                  n.usualLabel!,
                  key: const Key('mv-usual'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              // 2026-11-15 使用者改（原本 11-09 定不寫次數）：只寫這一晚的次數，照抄後端 events_total；
              // **不寫每小時幾次、不跟文獻常模並列**（跨夜差到 3.1 倍，比常模沒有意義）
              if (n.eventsTotal != null)
                Text(
                  '${n.eventsTotal} ${n.eventsTotal == 1 ? 'movement' : 'movements'} seen by the camera',
                  key: const Key('mv-count'),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              const Text(
                'Camera data is not part of your score.',
                style: TextStyle(color: _soft, fontSize: 12),
              ),
              const SizedBox(height: 16),
              if (clips.isNotEmpty) ...[
                const Text(
                  'Biggest movements',
                  style: TextStyle(color: _soft, fontSize: 13),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < clips.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ClipRow(
                      key: Key('mv-clip-row-$i'),
                      clip: clips[i],
                      stages: widget.stages,
                      color: color,
                      onTap: () => _play(clips[i]),
                    ),
                  ),
              ] else if (n.clipsNote != null)
                Text(
                  n.clipsNote!,
                  key: const Key('mv-clips-note'),
                  style: const TextStyle(color: _soft, fontSize: 13, height: 1.4),
                ),
              if (widget.curve != null) ...[
                const SizedBox(height: 18),
                const Text(
                  'Movement through the night',
                  style: TextStyle(color: _soft, fontSize: 13),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 110,
                  child: _NightLine(
                    curve: widget.curve!,
                    clips: clips,
                    color: color,
                    onSelect: (i) => _play(clips[i]),
                  ),
                ),
              ],
              // ── 這一週 ──
              if (showWeek) ...[
                const SizedBox(height: 24),
                Container(height: 1, color: const Color(0x1FFFFFFF)),
                const SizedBox(height: 16),
                const Text(
                  'Compared with your usual',
                  key: Key('mv-week-title'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Text(
                  'Each night against your own recent nights',
                  style: TextStyle(color: _soft, fontSize: 13),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 150,
                  child: _WeekBars(week: w, color: color),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 那一晚的動作線＋片段時刻的點（點了播那一段）。
class _NightLine extends StatelessWidget {
  final NightCurve curve;
  final List<CameraClip> clips;
  final Color color;
  final ValueChanged<int> onSelect;
  const _NightLine({
    required this.curve,
    required this.clips,
    required this.color,
    required this.onSelect,
  });

  static const double _timeH = 16;

  @override
  Widget build(BuildContext context) {
    final t0 = _wall(curve.points.first.time);
    final t1 = _wall(curve.points.last.time);
    final span = math.max(1, t1.difference(t0).inSeconds);
    final hi = math.max(0.05, curve.points.map((p) => p.value).reduce(math.max));
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight - _timeH;
        double xOf(DateTime t) => w * _wall(t).difference(t0).inSeconds / span;
        double yOf(double v) => h * (1 - (v / hi).clamp(0.0, 1.0)) ;
        String clock(DateTime t) =>
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              bottom: _timeH,
              child: CustomPaint(
                key: const Key('mv-line'),
                painter: _LinePainter(curve, color, xOf, yOf, h),
              ),
            ),
            for (var i = 0; i < clips.length; i++)
              if (clips[i].startAt case final at?
                  when !_wall(at).isBefore(t0) && !_wall(at).isAfter(t1))
                Positioned(
                  left: xOf(at) - 14,
                  top: h - 14,
                  width: 28,
                  height: 28,
                  child: GestureDetector(
                    key: Key('mv-marker-$i'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelect(i),
                    child: Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                          border: Border.all(
                            color: const Color(0xFF1B1F48),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            Positioned(
              left: 0,
              bottom: 0,
              child: Text(
                clock(t0),
                style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 11),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Text(
                clock(t1),
                style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 11),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LinePainter extends CustomPainter {
  final NightCurve curve;
  final Color color;
  final double Function(DateTime) xOf;
  final double Function(double) yOf;
  final double h;
  _LinePainter(this.curve, this.color, this.xOf, this.yOf, this.h);

  @override
  void paint(Canvas canvas, Size size) {
    final pts = [
      for (final p in curve.points) Offset(xOf(p.time), yOf(p.value)),
    ];
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    final area = Path.from(line)
      ..lineTo(pts.last.dx, h)
      ..lineTo(pts.first.dx, h)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, h)),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawLine(
      Offset(0, h),
      Offset(size.width, h),
      Paint()
        ..color = const Color(0x1FFFFFFF)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.curve != curve || old.h != h;
}

/// 7 欄：從中線往上（比平常多）或往下（比平常少），中間灰帶＝「差不多」；單一顏色、不分好壞。
class _WeekBars extends StatelessWidget {
  final List<(String, CameraNight?)> week;
  final Color color;
  const _WeekBars({required this.week, required this.color});

  static const double _labelH = 22;

  @override
  Widget build(BuildContext context) {
    // 灰帶寬度照抄後端；那一週任何一晚有給就用它
    final same = week
        .map((e) => e.$2?.usualSamePct)
        .whereType<double>()
        .firstOrNull;
    final maxAbs = [
      50.0,
      if (same != null) same * 2,
      for (final e in week)
        if (e.$2?.usualDeltaPct case final d?) d.abs() + 10,
    ].reduce(math.max);
    return LayoutBuilder(
      builder: (context, box) {
        final h = box.maxHeight - _labelH;
        final mid = h / 2;
        double y(double pct) => mid - (pct / maxAbs) * (h / 2 - 14);
        return Stack(
          children: [
            if (same != null)
              Positioned(
                key: const Key('mv-week-band'),
                left: 0,
                right: 0,
                top: y(same),
                height: y(-same) - y(same),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0x14FFFFFF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: mid,
              height: 1,
              child: const ColoredBox(color: Color(0x33FFFFFF)),
            ),
            if (same != null)
              const Positioned(
                right: 2,
                top: 0,
                child: Text(
                  'grey = about the same',
                  style: TextStyle(color: Color(0x80FFFFFF), fontSize: 10),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < week.length; i++)
                  Expanded(
                    child: () {
                      final (date, n) = week[i];
                      final d = DateTime.parse(date);
                      final isLast = i == week.length - 1;
                      final pct = n?.usualDeltaPct;
                      final strong = isLast ? 1.0 : 0.7;
                      final top = pct == null ? mid : math.min(y(pct), mid);
                      final bh = pct == null ? 0.0 : (y(pct) - mid).abs();
                      return Semantics(
                        label:
                            '${_weekdays[d.weekday - 1]} ${d.day}: ${movementWeekValue(n)}',
                        child: Column(
                          key: Key('mv-week-col-$date'),
                          children: [
                            SizedBox(
                              height: h,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  if (pct != null)
                                    Positioned(
                                      key: Key('mv-week-bar-$date'),
                                      left: 10,
                                      right: 10,
                                      top: top,
                                      height: math.max(3, bh),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: strong),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                      ),
                                    ),
                                  Positioned(
                                    left: -4,
                                    right: -4,
                                    top: pct == null
                                        ? mid - 8
                                        : (pct >= 0 ? top - 16 : top + bh + 2),
                                    height: 14,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        movementWeekValue(n),
                                        key: Key('mv-week-value-$date'),
                                        style: TextStyle(
                                          color: pct == null
                                              ? const Color(0x66FFFFFF)
                                              : (isLast
                                                    ? Colors.white
                                                    : const Color(0xCCFFFFFF)),
                                          fontSize: 11,
                                          fontWeight: pct == null
                                              ? null
                                              : FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
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

/// 參考圖的一列：左邊縮圖、中間大的時刻＋「moved for 5 s · Awake」、右邊播放鍵。
/// 時刻用片段的 start_at；後半照抄後端那句、去掉開頭的「03:42 · 」，再接手錶階段。
/// 舊版後端沒有 start_at → 整句照抄、不放大時刻。
class _ClipRow extends StatelessWidget {
  final CameraClip clip;
  final SleepStages? stages;
  final Color color;
  final VoidCallback onTap;
  const _ClipRow({
    super.key,
    required this.clip,
    required this.stages,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final full = clipLabel(clip, stages);
    final at = clip.startAt;
    final time = at == null
        ? null
        : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final hasTime = time != null && full.startsWith('$time · ');
    final rest = hasTime ? full.substring(time.length + 3) : full;
    return Material(
      color: const Color(0x14FFFFFF),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 104,
                  height: 64,
                  child: ColoredBox(
                    color: const Color(0xFF0E1230),
                    child: Image.network(
                      clip.url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.videocam_off_rounded,
                        color: Color(0x66FFFFFF),
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasTime)
                      Text(
                        time,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    Text(
                      rest,
                      key: const Key('mv-clip-row-text'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xB3FFFFFF),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.play_circle_fill_rounded, color: color, size: 28),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// 點進去：大的、循環播放，下面一行標籤，右上角關掉。
class _ClipViewer extends StatelessWidget {
  final CameraClip clip;
  final String label;
  const _ClipViewer({required this.clip, required this.label});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('mv-clip-viewer'),
      backgroundColor: const Color(0xFF1B1F48),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                key: const Key('mv-clip-close'),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ColoredBox(
                  color: const Color(0xFF0E1230),
                  // 點影片 → 全螢幕、可以兩指放大（2026-11-15 使用者定）
                  child: GestureDetector(
                    key: const Key('mv-clip-enlarge'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        fullscreenDialog: true,
                        builder: (_) => _FullScreenClip(clip: clip, label: label),
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          clip.url,
                          key: const Key('mv-clip-player'),
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Center(
                            child: Text(
                              'Clip could not be loaded',
                              style: TextStyle(
                                color: Color(0xB3FFFFFF),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        const Positioned(
                          right: 8,
                          top: 8,
                          child: Icon(
                            Icons.open_in_full_rounded,
                            color: Color(0xCCFFFFFF),
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                key: const Key('mv-clip-label'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 全螢幕：黑底、影片置中，兩指放大／拖動；左上關掉、底下一行標籤。
class _FullScreenClip extends StatelessWidget {
  final CameraClip clip;
  final String label;
  const _FullScreenClip({required this.clip, required this.label});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('mv-clip-fullscreen'),
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: Image.network(
                    clip.url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Text(
                      'Clip could not be loaded',
                      style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 4,
              top: 4,
              child: IconButton(
                key: const Key('mv-clip-fullscreen-close'),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
