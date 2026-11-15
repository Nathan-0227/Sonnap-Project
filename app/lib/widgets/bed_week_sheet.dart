// 一週上床／起床時刻（2026-11-14 使用者定）：早晨報告的 Time in bed 點開。
// 樣子跟 Time asleep 那張一樣（膠囊、標題同外面那張卡），差別是**左邊是時鐘**：
// 每晚一根膠囊從上床畫到起床，看得出每晚幾點睡的高低落差（規律性）。
//
// - 一週＝這一晚往回 7 個日曆晚上；沒資料的晚上空著
// - **按鈕優先、沒按退回手錶**（使用者定）。但兩個不是同一個量：按鈕是上床→下床，
//   手錶是入睡→醒來。所以手錶的晚上畫成**空心**，圖例講清楚，平均也分開數晚數
// - 11-15 使用者覺得太複雜，簡化（使用者定）：**數字放最上面**——「Usually in bed 03:02 → 08:00」
//   （上床、起床各自的**中間值**：一兩個特別早或晚的晚上不會把它拉走；平均會，這週的平均是 02:14），
//   下面一行平均臥床多久；圖上兩條白色虛線就是這兩個數字（usual bed／usual wake，字寫在線上），
//   膠囊在線上面＝那晚比平常早、在下面＝比平常晚。中間值要 ≥3 晚才畫線
// - 拿掉：淡色帶、目標小月亮、四項圖例。只留一行小字說明空心＝手錶
// - 按鈕與手錶的晚上一起算（同長條）。**不說規律好不好**（好壞只有後端能判斷）
// - 11-15 使用者定（grill）：**躺多久才睡著**。按鈕的晚上，從上床到**手錶認定睡著**那一段畫淡、
//   交界一條白線；最上面「This night」寫「Fell asleep 18m after Start Sleep」。
//   當下按的與事後補的都算、不另外標（Q1）；手錶在按鈕之前就睡著（負數）→ 那晚不畫、不寫（Q2）。
//   不跟文獻的 30 分鐘切點比、不說好壞（手錶的入睡判定本身不一定準）
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'report_sheet.dart';

import '../services/night_compare.dart' show formatMinutes;

enum BedSource { button, watch }

/// 一晚的上床→起床。
class BedSpan {
  final DateTime start;
  final DateTime end;
  final BedSource source;

  /// 手錶認定睡著的時刻。只有按鈕的晚上有意義（手錶的晚上起點本來就是入睡）。
  final DateTime? asleepAt;
  const BedSpan(this.start, this.end, this.source, [this.asleepAt]);

  int get minutes => end.difference(start).inMinutes;

  /// 按 Start Sleep 之後幾分鐘手錶才認定睡著。手錶的晚上、沒有入睡時刻、
  /// 手錶在按鈕**之前**就睡著（負數）、入睡不早於下床 → null：那晚不畫、不寫（不寫成 0）。
  ///
  /// ⚠️ 只比**牆鐘**：手錶時刻經 parseWallClock 是 UTC 標記的牆鐘，按鈕時刻是本地 DateTime，
  /// 直接相減會差 8 小時（11-15 用真實資料預覽才抓到：每一晚都被當成「入睡晚於下床」）。
  int? get latencyMinutes {
    final a0 = asleepAt;
    if (source != BedSource.button || a0 == null) return null;
    final a = _wall(a0), s = _wall(start), e = _wall(end);
    if (a.isBefore(s) || !a.isBefore(e)) return null;
    return a.difference(s).inMinutes;
  }

  static DateTime _wall(DateTime x) =>
      DateTime(x.year, x.month, x.day, x.hour, x.minute, x.second);
}

/// 「Fell asleep 18m after Start Sleep」；算不出來 → null。
String? bedLatencyLine(int? minutes) {
  if (minutes == null) return null;
  if (minutes < 1) return 'Fell asleep right after Start Sleep';
  return 'Fell asleep ${formatMinutes(minutes.toDouble())} after Start Sleep';
}

String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class BedWeekNight {
  final String date; // yyyy-MM-dd（起床那天）
  final BedSpan? span;
  const BedWeekNight(this.date, this.span);
}

/// 時刻換成「從傍晚 18:00 起算第幾分鐘」（0–1439）——跨午夜的晚上才排得在同一條軸上。
int minutesFromEvening(DateTime t) =>
    ((t.hour * 60 + t.minute) - 18 * 60 + 24 * 60) % (24 * 60);

/// 「03:12」。
String clockOf(int fromEvening) {
  final m = (fromEvening + 18 * 60) % (24 * 60);
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 一個晚上的時間要合理才收：起床晚於上床、14 小時以內（同睡覺畫面的上限）。
bool _plausible(DateTime? s, DateTime? e) =>
    s != null &&
    e != null &&
    e.isAfter(s) &&
    e.difference(s) <= const Duration(hours: 14);

class BedWeek {
  final List<BedWeekNight> nights; // 舊 → 新，固定 7 格
  const BedWeek(this.nights);

  List<BedSpan> get _spans => [
    for (final n in nights)
      if (n.span != null) n.span!,
  ];

  int get nightsWithData => _spans.length;
  int get watchNights =>
      _spans.where((s) => s.source == BedSource.watch).length;

  List<int> get _starts =>
      _spans.map((s) => minutesFromEvening(s.start)).toList()..sort();
  List<int> get _ends =>
      _spans.map((s) => minutesFromEvening(s.end)).toList()..sort();

  /// 上床／起床的中間值（從 18:00 起算的分鐘，跨午夜也對）；沒有任何一晚 → null。
  int? get medianStart => _median(_starts);
  int? get medianEnd => _median(_ends);

  /// 平均臥床分鐘數（不跨午夜，平均不會失真）。
  int? get averageMinutes => _avg(_spans.map((s) => s.minutes));

  static int? _median(List<int> sorted) {
    if (sorted.isEmpty) return null;
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : ((sorted[mid - 1] + sorted[mid]) / 2).round();
  }

  static int? _avg(Iterable<int> xs) {
    final l = xs.toList();
    if (l.isEmpty) return null;
    return (l.reduce((a, b) => a + b) / l.length).round();
  }
}

/// [endDate] 那一晚往回 7 晚。每一晚：按鈕的上床、下床**兩個都有**才用按鈕，
/// 不然用手錶的入睡→醒來；都沒有就空著。純函式。
BedWeek bedWeek({
  required String endDate,
  Map<String, (DateTime?, DateTime?)> buttons = const {},
  Map<String, (DateTime?, DateTime?)> watch = const {},
  int days = 7,
}) {
  final end = DateTime.parse(endDate);
  return BedWeek([
    for (var i = days - 1; i >= 0; i--)
      () {
        final key = _iso(DateTime.utc(end.year, end.month, end.day - i));
        final b = buttons[key];
        if (b != null && _plausible(b.$1, b.$2)) {
          // 手錶的入睡一起帶著（「躺多久才睡著」）；沒有就 null
          return BedWeekNight(
            key,
            BedSpan(b.$1!, b.$2!, BedSource.button, watch[key]?.$1),
          );
        }
        final w = watch[key];
        if (w != null && _plausible(w.$1, w.$2)) {
          return BedWeekNight(key, BedSpan(w.$1!, w.$2!, BedSource.watch));
        }
        return BedWeekNight(key, null);
      }(),
  ]);
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

Future<void> showBedWeekSheet(
  BuildContext context, {
  required String title,
  required IconData icon,
  required Color color,
  required BedWeek week,
  String? fontFamily,
}) {
  return showReportSheet<void>(
    context: context,
    builder: (context) => DefaultTextStyle.merge(
      style: TextStyle(fontFamily: fontFamily),
      child: BedWeekView(title: title, icon: icon, color: color, week: week),
    ),
  );
}

class BedWeekView extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final BedWeek week;
  const BedWeekView({
    super.key,
    required this.title,
    required this.week,
    this.icon = Icons.bed_rounded,
    this.color = const Color(0xFF8FA8FF),
  });

  static const _soft = Color(0xB3FFFFFF);

  @override
  Widget build(BuildContext context) {
    final medStart = week.medianStart;
    final medEnd = week.medianEnd;
    final avgMin = week.averageMinutes;
    final n = week.nightsWithData;
    final lastSpan = week.nights.isEmpty ? null : week.nights.last.span;
    final latency = bedLatencyLine(lastSpan?.latencyMinutes);
    final anyLatency = week.nights.any(
      (x) => (x.span?.latencyMinutes ?? 0) > 0,
    );

    return Container(
      key: const Key('bed-week-sheet'),
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
        // 加了「This night」等內容後比較長；矮的螢幕要能捲（同 Awake 那張）
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      title,
                      key: const Key('bed-week-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Spacer(),
                  const Text(
                    'Last 7 nights',
                    softWrap: false,
                    style: TextStyle(color: _soft, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (latency != null) ...[
                Container(
                  key: const Key('bed-last-night'),
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: BoxDecoration(
                    color: const Color(0x14FFFFFF),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0x1FFFFFFF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'This night',
                        style: TextStyle(color: _soft, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Start Sleep ${_hm(lastSpan!.start)}  →  '
                        'asleep ${_hm(lastSpan.asleepAt!)}',
                        key: const Key('bed-last-night-times'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        latency,
                        key: const Key('bed-latency'),
                        style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Container(height: 1, color: const Color(0x1FFFFFFF)),
                ),
              ],
              if (medStart == null || medEnd == null || avgMin == null)
                const Text(
                  'No bedtimes this week',
                  key: Key('bed-week-empty'),
                  style: TextStyle(color: _soft, fontSize: 14),
                )
              else ...[
                const Text(
                  'Usually in bed',
                  style: TextStyle(color: _soft, fontSize: 13),
                ),
                Text(
                  '${clockOf(medStart)} → ${clockOf(medEnd)}',
                  key: const Key('bed-week-usual'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'Average ${formatMinutes(avgMin.toDouble())} in bed · '
                  '${n == week.nights.length ? 'all ${week.nights.length} nights' : '$n of ${week.nights.length} nights'}',
                  key: const Key('bed-week-average'),
                  style: const TextStyle(color: _soft, fontSize: 13),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                height: 250,
                child: _ClockChart(week: week, color: color),
              ),
              if (anyLatency) ...[
                const SizedBox(height: 10),
                Row(
                  key: const Key('bed-week-latency-note'),
                  children: [
                    _swatch(color.withValues(alpha: 0.3), hollow: false),
                    const SizedBox(width: 6),
                    const Flexible(
                      child: Text(
                        'Lighter = before your watch saw you asleep',
                        style: TextStyle(
                          color: Color(0x99FFFFFF),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (week.watchNights > 0) ...[
                const SizedBox(height: 10),
                Row(
                  key: const Key('bed-week-watch-note'),
                  children: [
                    _swatch(color, hollow: true),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Hollow = watch',
                        style: const TextStyle(
                          color: Color(0x99FFFFFF),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Widget _swatch(Color c, {required bool hollow}) => Container(
    width: 10,
    height: 14,
    decoration: BoxDecoration(
      color: hollow ? Colors.transparent : c,
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: c, width: 1.5),
    ),
  );
}

/// 左邊時鐘刻度（上早下晚）＋每晚一根從上床到起床的膠囊。
class _ClockChart extends StatelessWidget {
  final BedWeek week;
  final Color color;
  const _ClockChart({required this.week, required this.color});

  static const double _axisW = 40;
  static const double _labelH = 26;

  @override
  Widget build(BuildContext context) {
    // 範圍：涵蓋每一晚與目標，對齊到 2 小時，至少 8 小時高
    final xs = <int>[
      for (final n in week.nights)
        if (n.span != null) ...[
          minutesFromEvening(n.span!.start),
          minutesFromEvening(n.span!.end),
        ],
    ];
    var lo = xs.isEmpty ? 4 * 60 : xs.reduce(math.min);
    var hi = xs.isEmpty ? 14 * 60 : xs.reduce(math.max);
    lo = (lo ~/ 120) * 120;
    hi = ((hi + 119) ~/ 120) * 120;
    if (hi - lo < 8 * 60) hi = math.min(24 * 60, lo + 8 * 60);
    final span = (hi - lo).toDouble();

    return LayoutBuilder(
      builder: (context, box) {
        final h = box.maxHeight - _labelH;
        double y(int fromEvening) => h * (fromEvening - lo) / span;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var t = lo; t <= hi; t += 120)
              Positioned(
                left: 0,
                width: _axisW - 6,
                top: y(t) - 7,
                child: Text(
                  clockOf(t),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Color(0x99FFFFFF),
                    fontSize: 10,
                  ),
                ),
              ),
            Positioned(
              left: _axisW,
              right: 0,
              top: 0,
              bottom: 0,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final n in week.nights)
                    Expanded(
                      child: _Night(
                        night: n,
                        isLast: identical(n, week.nights.last),
                        chartH: h,
                        labelH: _labelH,
                        top: n.span == null
                            ? 0
                            : y(minutesFromEvening(n.span!.start)),
                        bottom: n.span == null
                            ? 0
                            : y(minutesFromEvening(n.span!.end)),
                        color: color,
                      ),
                    ),
                ],
              ),
            ),
            // 兩條中間值虛線（≥3 晚才畫）；時刻寫在圖裡、線的左端，做成實心小膠囊比較顯眼。
            // 刻度照常全部顯示（使用者定：兩個都要）
            if (week.nightsWithData >= 3) ...[
              for (final (key, label, v) in [
                ('bed', 'bed', week.medianStart),
                ('wake', 'wake', week.medianEnd),
              ])
                if (v != null) ...[
                  Positioned(
                    key: Key('bed-week-median-$key'),
                    left: _axisW + 50, // 從字的右邊開始，線不穿過字
                    right: 0,
                    top: y(v),
                    child: IgnorePointer(
                      child: CustomPaint(
                        size: Size(box.maxWidth - _axisW - 50, 1),
                        painter: _DashPainter(color: Colors.white),
                      ),
                    ),
                  ),
                  Positioned(
                    left: _axisW + 2,
                    width: 46,
                    top: y(v) - 10,
                    child: IgnorePointer(
                      child: Container(
                        key: Key('bed-week-median-$key-label'),
                        alignment: Alignment.center,
                        height: 20,
                        // 只有字、不要框（使用者定：框會擋住最左邊那根長條）；加一點陰影讓字在長條上也讀得到
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            clockOf(v),
                            semanticsLabel: 'usual $label ${clockOf(v)}',
                            // 11-15 使用者定：再淡一點（不搶膠囊）
                            style: const TextStyle(
                              color: Color(0x99FFFFFF),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              shadows: [
                                Shadow(color: Color(0xCC0B1030), blurRadius: 4),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
            ],
          ],
        );
      },
    );
  }
}

class _Night extends StatelessWidget {
  final BedWeekNight night;
  final bool isLast;
  final double chartH;
  final double labelH;
  final double top;
  final double bottom;
  final Color color;

  const _Night({
    required this.night,
    required this.isLast,
    required this.chartH,
    required this.labelH,
    required this.top,
    required this.bottom,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final d = DateTime.parse(night.date);
    final s = night.span;
    final watch = s?.source == BedSource.watch;
    final strong = isLast ? 1.0 : 0.75;
    return Semantics(
      label: s == null
          ? '${_weekdays[d.weekday - 1]} ${d.day}: no data'
          : '${_weekdays[d.weekday - 1]} ${d.day}: '
                '${clockOf(minutesFromEvening(s.start))} to '
                '${clockOf(minutesFromEvening(s.end))}'
                '${watch ? ' (watch)' : ''}'
                '${s.latencyMinutes == null ? '' : ', asleep after ${formatMinutes(s.latencyMinutes!.toDouble())}'}',
      child: Padding(
        key: Key('bed-week-bar-${night.date}'),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          children: [
            SizedBox(
              height: chartH,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0x14FFFFFF),
                        borderRadius: BorderRadius.circular(40),
                      ),
                    ),
                  ),
                  if (s != null)
                    Positioned(
                      key: Key(
                        'bed-week-span-${night.date}-${watch ? 'watch' : 'button'}',
                      ),
                      left: 0,
                      right: 0,
                      top: top,
                      height: math.max(8, bottom - top),
                      child: _Capsule(
                        span: s,
                        height: math.max(8, bottom - top),
                        color: color,
                        strong: strong,
                        watch: watch,
                        date: night.date,
                      ),
                    )
                  else
                    const Align(
                      alignment: Alignment.center,
                      child: Text(
                        '—',
                        style: TextStyle(
                          color: Color(0x66FFFFFF),
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: labelH,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FittedBox(
                  child: Text(
                    _weekdays[d.weekday - 1],
                    style: TextStyle(
                      color: isLast ? Colors.white : const Color(0xB3FFFFFF),
                      fontSize: 11,
                      fontWeight: isLast ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一晚的膠囊。按鈕的晚上有手錶入睡時刻時，上床→睡著那一段畫淡、交界一條白線（躺多久才睡著）。
class _Capsule extends StatelessWidget {
  final BedSpan span;
  final double height;
  final Color color;
  final double strong;
  final bool watch;
  final String date;
  const _Capsule({
    required this.span,
    required this.height,
    required this.color,
    required this.strong,
    required this.watch,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.lerp(color, Colors.white, 0.45)!.withValues(alpha: strong),
        color.withValues(alpha: strong),
      ],
    );
    if (watch) {
      // 手錶的晚上空心：入睡→醒來，不是上床→下床
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: color.withValues(alpha: strong), width: 2),
        ),
      );
    }
    final lat = span.latencyMinutes;
    if (lat == null || lat <= 0 || span.minutes <= 0) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          gradient: gradient,
        ),
      );
    }
    final split = (height * lat / span.minutes).clamp(0.0, height - 2);
    return ClipRRect(
      borderRadius: BorderRadius.circular(40),
      child: Column(
        // 要撐滿寬度：沒有 child 的 ColoredBox／DecoratedBox 預設寬度是 0（11-15 預覽抓到只剩白線）
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            key: Key('bed-week-latency-$date'),
            height: split,
            child: ColoredBox(color: color.withValues(alpha: 0.3 * strong)),
          ),
          Container(
            height: 2,
            color: Colors.white.withValues(alpha: 0.9 * strong),
          ),
          Expanded(
            child: DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
          ),
        ],
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  _DashPainter({this.color = const Color(0x99FFFFFF)});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, 0), Offset(x + 4, 0), p);
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter old) => old.color != color;
}
