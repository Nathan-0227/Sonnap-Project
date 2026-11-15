// 早晨報告 Movement (camera) 點開（2026-11-15 使用者定，grill Q1–Q7，照參考圖的監視器 App 版面）：
//
// 由上到下：
// - 後端那句「About the same as usual」＋「105 movements · 25m moving in total」＋not part of your score。
//   次數照抄 events_total（11-15 使用者改：原本 11-09 定不寫）；總共動多久是每段秒數加起來。
//   **不寫每小時平均、不跟文獻常模並列**（跨夜差到 3.1 倍）。
// - **動作線**（11-15 使用者改回：線比膠囊好看）：每 5 分鐘有幾成在動，片段的時刻標成點，
//   白色直線＝正在看的那一段；點線上任一處選最近的那段動作。沒有線（舊版後端）才退回膠囊時間軸。
// - 段落之間有細線分隔（11-15 使用者定）。
// - **每個鐘頭動幾次**：一個鐘頭一根，數字在上面；頭尾不滿一小時的那兩根畫淡、寫涵蓋幾分鐘
//   （不然「6 次」會被讀成「那時幾乎沒動」）。
// - **播放器**：選到的那段循環播放，點畫面全螢幕、兩指放大；⏮ ⏭ 跳上一段／下一段片段。
//   選到沒有片段的動作 → 「No clip for this movement」＋那段的時間與長度（**不跳去播別段**，那是別的時刻）。
// - **片段列表**（一晚最多 10 段，照時間排）：縮圖＋大的時刻＋「moved for 21 s · Light」，點了換播放器。
//   標籤照抄後端，後面接那一刻**手錶的睡眠階段**。
// - **這一週**：7 欄，每晚跟它自己的「平常」比多幾 %，灰帶＝「差不多」（寬度照抄後端）；只用一個顏色。
// - 不放整夜錄影（一晚約 460 MB、只在電腦上）。
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/night_curve.dart';
import '../models/sleep_stages.dart';
import '../services/camera_insights.dart'
    show CameraClip, CameraEpisode, CameraNight;
import '../services/night_compare.dart' show formatMinutes;
import 'chart_probe.dart'
    show ProbeKind, ProbeLayer, nearestPoint, probeText, stageNames;

/// 換成 isUtc 的牆鐘（Sleep Stages、片段、動作三種時間基準不同，混著比會差 8 小時）。
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

/// 後端那句照抄，後面接手錶那一刻的睡眠階段（不在睡著範圍內、或那晚沒量到 REM 就不接）。
String withStage(String label, DateTime? at, SleepStages? stages) {
  final st = _stageAt(stages, at);
  if (st == null) return label;
  if (st == 'rem' && stages?.remMeasured == false) return label;
  return '$label · ${stageNames[st] ?? st}';
}

String clipLabel(CameraClip c, SleepStages? stages) =>
    withStage(c.label, c.startAt, stages);

/// 「105 movements · 25m moving in total」；沒有每段資料（舊夜晚）就只寫次數。
String movementCountLine(int? total, List<CameraEpisode>? episodes) {
  if (total == null) return '';
  final head = '$total ${total == 1 ? 'movement' : 'movements'}';
  if (episodes == null || episodes.isEmpty) return '$head seen by the camera';
  final sec = episodes.fold<double>(0, (s, e) => s + e.seconds);
  final moving = sec < 60 ? '${sec.round()} s' : formatMinutes(sec / 60);
  return '$head · $moving moving in total';
}

/// 一個鐘頭一格：(那個鐘頭的開始, 次數, 這一格涵蓋幾分鐘)。[from]–[to] 是錄影的開始與結束。純函式。
List<(DateTime, int, int)> hourlyCounts(
  List<CameraEpisode> episodes,
  DateTime from,
  DateTime to,
) {
  final out = <(DateTime, int, int)>[];
  var h = DateTime(from.year, from.month, from.day, from.hour);
  while (h.isBefore(to)) {
    final next = h.add(const Duration(hours: 1));
    final a = from.isAfter(h) ? from : h;
    final b = to.isBefore(next) ? to : next;
    final n = episodes
        .where((e) => !e.start.isBefore(h) && e.start.isBefore(next))
        .length;
    out.add((h, n, b.difference(a).inMinutes));
    h = next;
  }
  return out;
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _clock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

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

  /// 那一晚的動作線（每 5 分鐘有幾成在動，手錶入睡 → 起床那段）。最上面畫它（11-15 使用者：
  /// 線比膠囊時間軸好看）；沒有才退回膠囊時間軸。
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
  final _playerKey = GlobalKey();

  /// 正在看的那一段動作的開始時刻（片段的 start_at 跟動作的開始是同一個時刻）。
  DateTime? _sel;

  /// 片段照時間排（⏮ ⏭ 與列表用）。
  late final List<CameraClip> _clips = [
    ...widget.night.clips.where((c) => c.startAt != null),
  ]..sort((a, b) => a.startAt!.compareTo(b.startAt!));

  @override
  void initState() {
    super.initState();
    // 一打開先播動作最大的那段（後端的第一段）
    _sel = widget.night.clips.isEmpty ? null : widget.night.clips.first.startAt;
  }

  CameraClip? get _selClip {
    for (final c in _clips) {
      if (c.startAt == _sel) return c;
    }
    return null;
  }

  CameraEpisode? get _selEpisode {
    for (final e in widget.night.episodes ?? const <CameraEpisode>[]) {
      if (e.start == _sel) return e;
    }
    return null;
  }

  void _select(DateTime? at, {bool reveal = false}) {
    setState(() => _sel = at);
    if (reveal && _playerKey.currentContext != null) {
      Scrollable.ensureVisible(
        _playerKey.currentContext!,
        duration: const Duration(milliseconds: 300),
        alignment: 0.1,
      );
    }
  }

  void _step(int dir) {
    if (_clips.isEmpty) return;
    final at = _sel;
    CameraClip? target;
    if (dir > 0) {
      target = _clips.firstWhere(
        (c) => at == null || c.startAt!.isAfter(at),
        orElse: () => _clips.first,
      );
    } else {
      target = _clips.lastWhere(
        (c) => at == null || c.startAt!.isBefore(at),
        orElse: () => _clips.last,
      );
    }
    _select(target.startAt);
  }

  void _fullScreen(CameraClip c) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) =>
            _FullScreenClip(clip: c, label: clipLabel(c, widget.stages)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.night;
    final color = widget.color;
    final eps = n.episodes;
    final from = n.bedStartAt == null ? null : DateTime.tryParse(n.bedStartAt!);
    final to = n.bedEndAt == null ? null : DateTime.tryParse(n.bedEndAt!);
    final hasTimeline =
        eps != null && eps.isNotEmpty && from != null && to != null && to.isAfter(from);
    final w = widget.week;
    final showWeek = w != null && w.any((e) => e.$2?.usualDeltaPct != null);
    final clip = _selClip;
    final ep = _selEpisode;
    final selLabel = clip != null
        ? clipLabel(clip, widget.stages)
        : (ep == null ? null : withStage(ep.label, ep.start, widget.stages));

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
              if (n.eventsTotal != null)
                Text(
                  movementCountLine(n.eventsTotal, eps),
                  key: const Key('mv-count'),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              const Text(
                'Camera data is not part of your score.',
                style: TextStyle(color: _soft, fontSize: 12),
              ),
              // 11-15 使用者定的順序：摘要 → 播放器 → 動作線 → 每小時 → 一週 → 片段列表
              _divider(),
              // ── 播放器 ──
              if (_clips.isEmpty && n.clipsNote != null)
                Text(
                  n.clipsNote!,
                  key: const Key('mv-clips-note'),
                  style: const TextStyle(color: _soft, fontSize: 13, height: 1.4),
                )
              else if (_sel != null) ...[
                ClipRRect(
                  key: _playerKey,
                  borderRadius: BorderRadius.circular(18),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ColoredBox(
                      color: const Color(0xFF0E1230),
                      child: clip == null
                          ? Center(
                              child: Column(
                                key: const Key('mv-no-clip'),
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(
                                    Icons.videocam_off_rounded,
                                    color: Color(0x80FFFFFF),
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    'No clip for this movement',
                                    style: TextStyle(color: _soft, fontSize: 13),
                                  ),
                                ],
                              ),
                            )
                          : GestureDetector(
                              key: const Key('mv-clip-enlarge'),
                              onTap: () => _fullScreen(clip),
                              child: Image.network(
                                clip.url,
                                key: const Key('mv-clip-player'),
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                                errorBuilder: (_, _, _) => const Center(
                                  child: Text(
                                    'Clip could not be loaded',
                                    style: TextStyle(color: _soft, fontSize: 12),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (selLabel != null)
                  Text(
                    selLabel,
                    key: const Key('mv-clip-label'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (_clips.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _RoundButton(
                        key: const Key('mv-prev'),
                        icon: Icons.skip_previous_rounded,
                        onTap: () => _step(-1),
                      ),
                      const SizedBox(width: 22),
                      _RoundButton(
                        key: const Key('mv-full'),
                        icon: Icons.open_in_full_rounded,
                        big: true,
                        onTap: clip == null ? null : () => _fullScreen(clip),
                      ),
                      const SizedBox(width: 22),
                      _RoundButton(
                        key: const Key('mv-next'),
                        icon: Icons.skip_next_rounded,
                        onTap: () => _step(1),
                      ),
                    ],
                  ),
                ],
              ],
              if ((n.motionCurve ?? widget.curve) != null) ...[
                _divider(),
                const Text(
                  'Movement through the night',
                  style: TextStyle(color: _soft, fontSize: 13),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 120,
                  child: _MotionLine(
                    curve: (n.motionCurve ?? widget.curve)!,
                    episodes: eps ?? const [],
                    clips: _clips,
                    selected: _sel,
                    stages: widget.stages,
                    color: color,
                    onSelect: (at) => _select(at),
                  ),
                ),
              ] else if (hasTimeline) ...[
                _divider(),
                SizedBox(
                  height: 54,
                  child: _Timeline(
                    episodes: eps,
                    from: from,
                    to: to,
                    clipStarts: {for (final c in _clips) c.startAt!},
                    selected: _sel,
                    color: color,
                    onSelect: (at) => _select(at),
                  ),
                ),
              ],
              if (hasTimeline) ...[
                _divider(),
                const Text(
                  'Movements each hour',
                  style: TextStyle(color: _soft, fontSize: 13),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 92,
                  child: _HourBars(
                    hours: hourlyCounts(eps, from, to),
                    color: color,
                  ),
                ),
              ],
              // ── 這一週 ──
              if (showWeek) ...[
                _divider(),
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
              // ── 片段列表 ──
              if (_clips.isNotEmpty) ...[
                _divider(),
                Text(
                  'Clips · ${_clips.length} biggest movements',
                  style: const TextStyle(color: _soft, fontSize: 13),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < _clips.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ClipRow(
                      key: Key('mv-clip-row-$i'),
                      clip: _clips[i],
                      stages: widget.stages,
                      color: color,
                      selected: _clips[i].startAt == _sel,
                      onTap: () => _select(_clips[i].startAt, reveal: true),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 段落之間的細線（11-15 使用者：數據之間要有線區分）。
Widget _divider() => Padding(
  padding: const EdgeInsets.symmetric(vertical: 16),
  child: Container(height: 1, color: const Color(0x1FFFFFFF)),
);

/// 最上面那條動作線（每 5 分鐘有幾成在動）＋片段時刻的點＋白色直線＝正在看的那段。
/// - 片段的點**畫在線上**那一刻的位置（11-15 使用者：原本貼在底線上看不出是哪一段）。
/// - 按住左右滑 → 泡泡跟著走：「03:42 · moving 12 sec · Light」（同 Sleep Stages 卡的點線看那一刻，
///   規則在 chart_probe.dart：吸到最近的真實讀數、不內插；附近沒讀數寫 no reading）。
/// - 點一下 → 也選離那一刻最近的動作來播（3 分鐘內；沒有每段資料就只找片段）。點圖外面泡泡收起來。
class _MotionLine extends StatefulWidget {
  final NightCurve curve;
  final List<CameraEpisode> episodes;
  final List<CameraClip> clips;
  final DateTime? selected;
  final SleepStages? stages;
  final Color color;
  final ValueChanged<DateTime> onSelect;
  const _MotionLine({
    required this.curve,
    required this.episodes,
    required this.clips,
    required this.selected,
    required this.stages,
    required this.color,
    required this.onSelect,
  });

  @override
  State<_MotionLine> createState() => _MotionLineState();
}

class _MotionLineState extends State<_MotionLine> {
  static const double _timeH = 16;
  double? _probeX;

  /// 線上那一刻的值（兩個點之間直線內插，只用來把片段的點放在線上，不拿來顯示數字）。
  double _valueAt(DateTime t) {
    final pts = widget.curve.points;
    final w = _wall(t);
    if (!w.isAfter(_wall(pts.first.time))) return pts.first.value;
    for (var i = 0; i < pts.length - 1; i++) {
      final a = _wall(pts[i].time), b = _wall(pts[i + 1].time);
      if (!w.isBefore(a) && !w.isAfter(b)) {
        final span = b.difference(a).inSeconds;
        if (span <= 0) return pts[i].value;
        final f = w.difference(a).inSeconds / span;
        return pts[i].value + (pts[i + 1].value - pts[i].value) * f;
      }
    }
    return pts.last.value;
  }

  @override
  Widget build(BuildContext context) {
    final curve = widget.curve, clips = widget.clips, selected = widget.selected;
    final color = widget.color;
    final t0 = _wall(curve.points.first.time);
    final t1 = _wall(curve.points.last.time);
    final span = math.max(1, t1.difference(t0).inSeconds);
    final hi = math.max(0.05, curve.points.map((p) => p.value).reduce(math.max));
    bool inRange(DateTime t) => !_wall(t).isBefore(t0) && !_wall(t).isAfter(t1);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight - _timeH;
        double xOf(DateTime t) => w * _wall(t).difference(t0).inSeconds / span;
        double yOf(double v) => h * (1 - (v / hi).clamp(0.0, 1.0));
        DateTime timeAt(double x) =>
            t0.add(Duration(seconds: (span * (x / w).clamp(0.0, 1.0)).round()));

        void selectNear(double x) {
          final t = timeAt(x);
          final starts = [
            for (final e in widget.episodes) e.start,
            if (widget.episodes.isEmpty)
              for (final c in clips) c.startAt!,
          ];
          DateTime? best;
          Duration? bestD;
          for (final s in starts) {
            final dd = _wall(s).difference(t).abs();
            if (bestD == null || dd < bestD) {
              best = s;
              bestD = dd;
            }
          }
          if (best != null && bestD! <= const Duration(minutes: 3)) {
            widget.onSelect(best);
          }
        }

        Widget? probe;
        if (_probeX != null) {
          final t = timeAt(_probeX!);
          final p = nearestPoint(curve.points, t);
          final at = p?.time ?? t;
          probe = ProbeLayer(
            dot: Offset(xOf(at), p == null ? h : yOf(p.value)),
            text: probeText(
              time: at,
              kind: ProbeKind.camera,
              point: p,
              stage: _stageAt(widget.stages, at),
            ),
          );
        }

        return TapRegion(
          onTapOutside: (_) {
            if (_probeX != null) setState(() => _probeX = null);
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
                  key: const Key('mv-line'),
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    setState(() => _probeX = d.localPosition.dx.clamp(0.0, w));
                    selectNear(d.localPosition.dx);
                  },
                  onHorizontalDragStart: (d) =>
                      setState(() => _probeX = d.localPosition.dx.clamp(0.0, w)),
                  onHorizontalDragUpdate: (d) =>
                      setState(() => _probeX = d.localPosition.dx.clamp(0.0, w)),
                  child: CustomPaint(
                    painter: _LinePainter(curve, color, xOf, yOf, h),
                  ),
                ),
              ),
              if (selected != null && inRange(selected))
                Positioned(
                  key: const Key('mv-playhead'),
                  left: xOf(selected) - 1.5,
                  top: 0,
                  height: h,
                  width: 3,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              for (var i = 0; i < clips.length; i++)
                if (inRange(clips[i].startAt!))
                  Positioned(
                    left: xOf(clips[i].startAt!) - 12,
                    top: yOf(_valueAt(clips[i].startAt!)) - 12,
                    width: 24,
                    height: 24,
                    child: GestureDetector(
                      key: Key('mv-marker-$i'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onSelect(clips[i].startAt!),
                      child: Center(
                        child: Container(
                          width: clips[i].startAt == selected ? 14 : 10,
                          height: clips[i].startAt == selected ? 14 : 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: clips[i].startAt == selected ? Colors.white : color,
                            border: Border.all(color: const Color(0xFF1B1F48), width: 2),
                          ),
                        ),
                      ),
                    ),
                  ),
              // 時刻字不接手勢：不然會擋住剛好在頭尾的片段點（11-15 測試抓到）
              Positioned(
                left: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Text(
                    _clock(t0),
                    style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 11),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Text(
                    _clock(t1),
                    style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 11),
                  ),
                ),
              ),
              if (probe != null)
                Positioned(left: 0, top: 0, width: w, height: h, child: probe),
            ],
          ),
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
    final pts = [for (final p in curve.points) Offset(xOf(p.time), yOf(p.value))];
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

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool big;
  const _RoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = big ? 58.0 : 44.0;
    return Material(
      color: big ? const Color(0x26FFFFFF) : const Color(0x14FFFFFF),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            color: onTap == null ? const Color(0x55FFFFFF) : Colors.white,
            size: big ? 26 : 24,
          ),
        ),
      ),
    );
  }
}

/// 參考圖那條：開始 → 結束錄影，每段動作一顆膠囊（寬＝動多久，最窄 4 px），
/// 有片段的亮、沒有的暗，白色直線＝正在看的那段。點一下選最近的那段。
class _Timeline extends StatelessWidget {
  final List<CameraEpisode> episodes;
  final DateTime from, to;
  final Set<DateTime> clipStarts;
  final DateTime? selected;
  final Color color;
  final ValueChanged<DateTime> onSelect;
  const _Timeline({
    required this.episodes,
    required this.from,
    required this.to,
    required this.clipStarts,
    required this.selected,
    required this.color,
    required this.onSelect,
  });

  static const double _timeH = 16;

  @override
  Widget build(BuildContext context) {
    final span = math.max(1, to.difference(from).inSeconds);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight - _timeH;
        double xOf(DateTime t) =>
            (w * t.difference(from).inSeconds / span).clamp(0.0, w);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: h,
              child: GestureDetector(
                key: const Key('mv-timeline'),
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) {
                  CameraEpisode? best;
                  var bestD = double.infinity;
                  for (final e in episodes) {
                    final x0 = xOf(e.start);
                    final x1 = math.max(x0 + 4, xOf(e.start.add(
                        Duration(milliseconds: (e.seconds * 1000).round()))));
                    final dx = d.localPosition.dx < x0
                        ? x0 - d.localPosition.dx
                        : (d.localPosition.dx > x1 ? d.localPosition.dx - x1 : 0.0);
                    if (dx < bestD) {
                      bestD = dx;
                      best = e;
                    }
                  }
                  if (best != null && bestD <= 14) onSelect(best.start);
                },
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0x14FFFFFF),
                    borderRadius: BorderRadius.circular(h / 2),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final e in episodes)
                        Positioned(
                          left: xOf(e.start),
                          top: 7,
                          bottom: 7,
                          width: math.max(
                            4,
                            xOf(e.start.add(Duration(
                                milliseconds: (e.seconds * 1000).round()))) -
                                xOf(e.start),
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: clipStarts.contains(e.start)
                                  ? color
                                  : color.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      if (selected != null)
                        Positioned(
                          key: const Key('mv-playhead'),
                          left: xOf(selected!) - 1.5,
                          top: -4,
                          bottom: -4,
                          width: 3,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              bottom: 0,
              child: Text(
                _clock(from),
                style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 11),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Text(
                _clock(to),
                style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 11),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 每個鐘頭一根：數字在上、鐘點在下；頭尾不滿一小時的畫淡、寫涵蓋幾分鐘。
class _HourBars extends StatelessWidget {
  final List<(DateTime, int, int)> hours;
  final Color color;
  const _HourBars({required this.hours, required this.color});

  static const double _valueH = 16;
  static const double _labelH = 32;

  @override
  Widget build(BuildContext context) {
    final maxN = math.max(1, hours.map((h) => h.$2).fold(0, math.max));
    return LayoutBuilder(
      builder: (context, box) {
        final barH = box.maxHeight - _valueH - _labelH - 2;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (start, n, minutes) in hours)
              Expanded(
                child: Padding(
                  key: Key('mv-hour-${start.hour}'),
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        height: _valueH,
                        child: Text(
                        '$n',
                        key: Key('mv-hour-count-${start.hour}'),
                        style: TextStyle(
                          color: minutes < 60
                              ? const Color(0x99FFFFFF)
                              : Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        height: math.max(3, barH * n / maxN),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: minutes < 60 ? 0.35 : 0.85),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      SizedBox(
                        height: _labelH,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              start.hour.toString().padLeft(2, '0'),
                              style: const TextStyle(
                                color: Color(0x99FFFFFF),
                                fontSize: 11,
                              ),
                            ),
                            if (minutes < 60)
                              Text(
                                '${minutes}m',
                                key: Key('mv-hour-partial-${start.hour}'),
                                style: const TextStyle(
                                  color: Color(0x66FFFFFF),
                                  fontSize: 9,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
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
/// 列表的一列（參考圖）：左邊縮圖、中間大的時刻＋「moved for 21 s · Light」、右邊播放鍵。
/// 時刻用片段的 start_at；後半照抄後端那句、去掉開頭的「03:42 · 」，再接手錶階段。
class _ClipRow extends StatelessWidget {
  final CameraClip clip;
  final SleepStages? stages;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _ClipRow({
    super.key,
    required this.clip,
    required this.stages,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final full = clipLabel(clip, stages);
    final at = clip.startAt;
    final time = at == null ? null : _clock(at);
    final hasTime = time != null && full.startsWith('$time · ');
    final rest = hasTime ? full.substring(time.length + 3) : full;
    return Material(
      color: selected ? color.withValues(alpha: 0.16) : const Color(0x14FFFFFF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? color : Colors.transparent,
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: SizedBox(
                  width: 96,
                  height: 56,
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
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    Text(
                      rest,
                      key: const Key('mv-clip-row-text'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.graphic_eq_rounded : Icons.play_circle_fill_rounded,
                color: color,
                size: 26,
              ),
              const SizedBox(width: 4),
            ],
          ),
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
