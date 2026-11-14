// 一週放下手機的時刻（2026-11-15 使用者定）：早晨報告的 Phone down 點開。
// 11-15 第一版是一晚一列、橫的時間軸；使用者覺得不好看，改成 **B：跟上面兩張（Total sleep、
// Time in bed）同一套**——7 欄、左邊時鐘刻度（上早下晚）、每欄一條底槽。每晚一個點，
// 點到目標虛線之間一根細棒（離目標多遠），點的時刻寫在點旁邊（遠離目標那一側）。
//
// - 一週＝這一晚往回 7 個日曆晚上，**舊的在左、這一晚在最右邊**（Q7）
// - 最上面：「Usually phone down 03:26」（中間值，跨午夜也對）＋
//   「N of M nights over 30m past your HH:MM target」（Q2；11-15 使用者定寫出 30m：
//   只寫 later 的話 03:26 明明晚於 03:00 卻沒被算，看起來像算錯）
// - ⚠️ 晚不晚**只照抄後端每一晚的 `is_late`**（Q4）：跨午夜只在 behavior/adherence.py 算，
//   Dart 不拿時刻跟目標比。後端沒給 is_late 的晚上不算進 M
// - 虛線＝現在的目標（Q4、Q6：圖上只有這一條線）。點**全部同一個顏色**、不分紅綠，
//   這一晚亮一點（Q3）——好壞只有後端判斷
// - 沒資料的晚上寫「— no data」、不算（Q5），**不畫成 0**
// - 點旁邊只寫時刻（Q8）
// - **12:00–18:00 的放下手機不算那一晚的就寢**（11-15 使用者定）：報告格子的時間軸本來就是
//   18:00→12:00。實例 10-05 偵測成 14:07（晚 607 分鐘），一晚就把整週拉歪。畫成 no data、不進中間值與晚幾晚
// - 11-15 使用者選 A＋C：
//   A. 星期底下小字「+7m」＝按了 Start Sleep 之後手機還在用多久（後端的
//      phone_in_bed_minutes，照抄不重算）。只有按了上床按鈕的晚上才有，沒有就不寫（不寫 0）。
//      ⚠️ 不畫成點上方的一段線：實際多半只有幾分鐘，在圖上是 2–3 px，整段藏在點後面
//   C. 標題下面「↑ 23m later than the week before」：這週中間值 vs 前 7 晚中間值，
//      同 Total sleep 那張：**只代表方向**，晚了紅、早了綠，不說好壞；前一週沒資料就不寫
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/night_compare.dart'
    show formatMinutes, kDeltaUp, kDeltaDown, kDeltaFlat;
import 'bed_week_sheet.dart' show minutesFromEvening, clockOf;

/// 一晚放下手機：時刻（牆鐘）＋後端判的晚不晚（沒給 → null）＋
/// 按了 Start Sleep 之後手機還用了幾分鐘（後端的 phone_in_bed_minutes；沒按上床 → null）。
class PhoneDown {
  final DateTime at;
  final bool? isLate;
  final double? inBedMinutes;
  const PhoneDown(this.at, this.isLate, [this.inBedMinutes]);
}

class PhoneWeekNight {
  final String date; // yyyy-MM-dd（起床那天）
  final PhoneDown? down;
  const PhoneWeekNight(this.date, this.down);
}

class PhoneWeek {
  final List<PhoneWeekNight> nights; // 舊 → 新，固定 7 格

  /// 前 7 晚的中間值（從 18:00 起算）；前一週沒資料 → null。
  final int? previousMedian;
  const PhoneWeek(this.nights, [this.previousMedian]);

  /// 這週比前一週晚了幾分鐘（負＝早了）；任一週沒資料 → null。
  int? get change {
    final m = median;
    final p = previousMedian;
    return m == null || p == null ? null : m - p;
  }

  static int? medianOf(Iterable<PhoneDown> downs) {
    final xs = downs.map((d) => minutesFromEvening(d.at)).toList()..sort();
    if (xs.isEmpty) return null;
    final mid = xs.length ~/ 2;
    return xs.length.isOdd ? xs[mid] : ((xs[mid - 1] + xs[mid]) / 2).round();
  }

  List<PhoneDown> get _downs => [
    for (final n in nights)
      if (n.down != null) n.down!,
  ];

  int get nightsWithData => _downs.length;

  /// 中間值（從 18:00 起算的分鐘）；沒有任何一晚 → null。
  int? get median => medianOf(_downs);

  /// 後端說晚了的晚數／後端有判的晚數（照抄 is_late，不重算）。
  int get lateNights => _downs.where((d) => d.isLate == true).length;
  int get judgedNights => _downs.where((d) => d.isLate != null).length;
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 12:00–18:00：不是就寢的時段（見檔頭）。
bool isDaytime(DateTime t) => t.hour >= 12 && t.hour < 18;

/// [endDate] 那一晚往回 7 晚。純函式。
PhoneWeek phoneWeek({
  required String endDate,
  Map<String, PhoneDown> downs = const {},
  int days = 7,
}) {
  final end = DateTime.parse(endDate);
  PhoneDown? on(int daysBack) {
    final d =
        downs[_iso(DateTime.utc(end.year, end.month, end.day - daysBack))];
    return d == null || isDaytime(d.at) ? null : d;
  }

  return PhoneWeek([
    for (var i = days - 1; i >= 0; i--)
      PhoneWeekNight(
        _iso(DateTime.utc(end.year, end.month, end.day - i)),
        on(i),
      ),
  ], PhoneWeek.medianOf([for (var i = days; i < 2 * days; i++) ?on(i)]));
}

/// 「↑ 23m later than the week before」；算不出來 → null。只代表方向。
String? phoneWeekChangeLine(PhoneWeek w) {
  final c = w.change;
  if (c == null) return null;
  if (c == 0) return '= same as the week before';
  final m = formatMinutes(c.abs().toDouble());
  return c > 0
      ? '↑ $m later than the week before'
      : '↓ $m earlier than the week before';
}

/// 「+7m in bed」：按了 Start Sleep 之後手機還在用多久；沒有 → null。
String? inBedLabel(double? minutes) {
  if (minutes == null || minutes < 0) return null;
  if (minutes < 1) return '+<1m in bed';
  return '+${formatMinutes(minutes.roundToDouble())} in bed';
}

/// 「HH:MM」→ 從 18:00 起算的分鐘；格式不對 → null。
int? targetFromEvening(String? hhmm) {
  final p = hhmm?.split(':');
  if (p == null || p.length != 2) return null;
  final h = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
  return minutesFromEvening(DateTime(2000, 1, 1, h, m));
}

/// 後端算「熬夜」的門檻（behavior/adherence.py 的 LATE_THRESHOLD_MINUTES）。
/// ⚠️ **只用來寫那句話，Dart 不拿它判斷任何一晚**——晚不晚照抄後端的 is_late。
/// 後端沒回傳這個數字，所以這裡抄一份；phone_week_test.dart 直接讀那支 Python 比對，改一邊另一邊會紅。
const int kLateThresholdMinutes = 30;

/// 「4 of 6 nights over 30m past your 03:00 target」；後端一晚都沒判、或沒有目標 → null。
String? phoneLateLine(PhoneWeek w, String? target) {
  if (target == null || w.judgedNights == 0) return null;
  final m = w.judgedNights;
  return '${w.lateNights} of $m night${m == 1 ? '' : 's'} '
      'over ${kLateThresholdMinutes}m past your $target target';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

Future<void> showPhoneWeekSheet(
  BuildContext context, {
  required String title,
  required IconData icon,
  required Color color,
  required PhoneWeek week,
  String? target,
  String? fontFamily,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => DefaultTextStyle.merge(
      style: TextStyle(fontFamily: fontFamily),
      child: PhoneWeekView(
        title: title,
        icon: icon,
        color: color,
        week: week,
        target: target,
      ),
    ),
  );
}

class PhoneWeekView extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final PhoneWeek week;
  final String? target;
  const PhoneWeekView({
    super.key,
    required this.title,
    required this.week,
    this.target,
    this.icon = Icons.phone_android_rounded,
    this.color = const Color(0xFFFFC97A),
  });

  static const _soft = Color(0xB3FFFFFF);

  @override
  Widget build(BuildContext context) {
    final med = week.median;
    final late = phoneLateLine(week, target);
    final change = phoneWeekChangeLine(week);
    final c = week.change;
    final hasInBed = week.nights.any(
      (n) => inBedLabel(n.down?.inBedMinutes) != null,
    );
    return Container(
      key: const Key('phone-week-sheet'),
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
        child: Padding(
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
                      key: const Key('phone-week-title'),
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
              if (med == null)
                const Text(
                  'No phone-down times this week',
                  key: Key('phone-week-empty'),
                  style: TextStyle(color: _soft, fontSize: 14),
                )
              else ...[
                const Text(
                  'Usually phone down',
                  style: TextStyle(color: _soft, fontSize: 13),
                ),
                Text(
                  clockOf(med),
                  key: const Key('phone-week-usual'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (change != null)
                  Text(
                    change,
                    key: const Key('phone-week-change'),
                    style: TextStyle(
                      color: c! > 0
                          ? kDeltaUp
                          : (c < 0 ? kDeltaDown : kDeltaFlat),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (late != null)
                  Text(
                    late,
                    key: const Key('phone-week-late'),
                    style: const TextStyle(color: _soft, fontSize: 13),
                  ),
                const SizedBox(height: 18),
                _ColumnsChart(
                  week: week,
                  color: color,
                  target: targetFromEvening(target),
                ),
                if (hasInBed) ...[
                  const SizedBox(height: 10),
                  const Text(
                    '+7m = phone use after Start Sleep',
                    key: Key('phone-week-inbed-note'),
                    style: TextStyle(color: Color(0x99FFFFFF), fontSize: 11),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 7 欄（舊 → 新、左 → 右），左邊時鐘刻度（上早下晚），同 Total sleep／Time in bed 那兩張。
class _ColumnsChart extends StatelessWidget {
  final PhoneWeek week;
  final Color color;
  final int? target;
  const _ColumnsChart({required this.week, required this.color, this.target});

  static const double _axisW = 40;
  static const double _labelH = 40;

  @override
  Widget build(BuildContext context) {
    // 範圍：涵蓋每一晚與目標，上下各留 30 分鐘給時刻字，對齊到 2 小時，至少 6 小時高
    final xs = <int>[
      for (final n in week.nights)
        if (n.down != null) ...[minutesFromEvening(n.down!.at)],
      ?target,
    ];
    var lo = math.max(0, (xs.reduce(math.min) - 30) ~/ 120 * 120);
    var hi = math.min(24 * 60, ((xs.reduce(math.max) + 30 + 119) ~/ 120) * 120);
    if (hi - lo < 6 * 60) hi = math.min(24 * 60, lo + 6 * 60);
    final span = (hi - lo).toDouble();

    return SizedBox(
      height: 250,
      child: LayoutBuilder(
        builder: (context, box) {
          final h = box.maxHeight - _labelH;
          double y(num v) => h * (v - lo) / span;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // 刻度；離目標 40 分鐘以內的刻度讓位給目標的時刻（不然兩個字疊在一起）
              for (var t = lo; t <= hi; t += 120)
                if (target == null || (t - target!).abs() >= 40)
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
              if (target != null) ...[
                Positioned(
                  left: 0,
                  width: _axisW - 6,
                  top: y(target!) - 7,
                  child: Text(
                    clockOf(target!),
                    key: const Key('phone-week-target-label'),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
              Positioned(
                left: _axisW,
                right: 0,
                top: 0,
                bottom: 0,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < week.nights.length; i++)
                      Expanded(
                        child: _Column(
                          night: week.nights[i],
                          isLast: i == week.nights.length - 1,
                          color: color,
                          chartH: h,
                          labelH: _labelH,
                          y: y,
                          targetY: target == null ? null : y(target!),
                        ),
                      ),
                  ],
                ),
              ),
              // 目標虛線畫在欄的上面（底槽不會蓋住它）
              if (target != null)
                Positioned(
                  key: const Key('phone-week-target'),
                  left: _axisW,
                  right: 0,
                  top: y(target!),
                  child: IgnorePointer(
                    child: CustomPaint(
                      size: Size(box.maxWidth - _axisW, 1),
                      painter: _HDashPainter(),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Column extends StatelessWidget {
  final PhoneWeekNight night;
  final bool isLast;
  final Color color;
  final double chartH;
  final double labelH;
  final double Function(num) y;
  final double? targetY;

  const _Column({
    required this.night,
    required this.isLast,
    required this.color,
    required this.chartH,
    required this.labelH,
    required this.y,
    required this.targetY,
  });

  static const double _dot = 14;

  @override
  Widget build(BuildContext context) {
    final d = DateTime.parse(night.date);
    final day = _weekdays[d.weekday - 1];
    final down = night.down;
    final strong = isLast ? 1.0 : 0.75;

    final children = <Widget>[
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x14FFFFFF),
            borderRadius: BorderRadius.circular(40),
          ),
        ),
      ),
    ];

    if (down == null) {
      children.add(
        Align(
          alignment: Alignment.center,
          child: Text(
            '—',
            key: Key('phone-week-time-${night.date}'),
            style: const TextStyle(color: Color(0x66FFFFFF), fontSize: 12),
          ),
        ),
      );
    } else {
      final m = minutesFromEvening(down.at);
      final dy = y(m);

      // 點到目標的細棒：離目標多遠
      if (targetY != null && (dy - targetY!).abs() > 1) {
        final top = math.min(dy, targetY!);
        children.add(
          Positioned(
            key: Key('phone-week-stick-${night.date}'),
            left: 0,
            right: 0,
            top: top,
            height: (dy - targetY!).abs(),
            child: Center(
              child: Container(
                width: 2,
                color: color.withValues(alpha: 0.35 * strong),
              ),
            ),
          ),
        );
      }
      children.add(
        Positioned(
          key: Key('phone-week-dot-${night.date}'),
          left: 0,
          right: 0,
          top: dy - _dot / 2,
          height: _dot,
          child: Center(
            child: Container(
              width: _dot,
              height: _dot,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: strong),
                boxShadow: isLast
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.6),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      );
      // 時刻寫在遠離目標那一側；上面放不下就放下面
      final above = targetY == null || dy <= targetY!;
      var labelTop = above ? dy - _dot / 2 - 15 : dy + _dot / 2 + 2;
      if (labelTop < 0) labelTop = dy + _dot / 2 + 2;
      if (labelTop > chartH - 13) {
        labelTop = dy - _dot / 2 - 15;
      }
      children.add(
        Positioned(
          left: -4,
          right: -4,
          top: labelTop,
          height: 13,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              clockOf(m),
              key: Key('phone-week-time-${night.date}'),
              softWrap: false,
              style: TextStyle(
                color: isLast ? Colors.white : const Color(0xCCFFFFFF),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );
    }

    final inBedSpoken = inBedLabel(down?.inBedMinutes);
    return Semantics(
      label: down == null
          ? '$day ${d.day}: no data'
          : '$day ${d.day}: ${clockOf(minutesFromEvening(down.at))}'
                '${inBedSpoken == null ? '' : ', $inBedSpoken'}',
      child: Padding(
        key: Key('phone-week-col-${night.date}'),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            SizedBox(
              height: chartH,
              child: Stack(clipBehavior: Clip.none, children: children),
            ),
            SizedBox(
              height: labelH,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FittedBox(
                    child: Text(
                      day,
                      style: TextStyle(
                        color: isLast ? Colors.white : const Color(0xB3FFFFFF),
                        fontSize: 11,
                        fontWeight: isLast ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ),
                  // A：上床後還用手機多久；沒有就留空（高度照留，星期對齊）
                  SizedBox(
                    height: 14,
                    child: inBedSpoken == null
                        ? null
                        : FittedBox(
                            child: Text(
                              inBedSpoken.replaceAll(' in bed', ''),
                              key: Key('phone-week-inbed-${night.date}'),
                              style: const TextStyle(
                                color: Color(0x99FFFFFF),
                                fontSize: 10,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HDashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xCCFFFFFF)
      ..strokeWidth = 1.2;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, 0), Offset(x + 4, 0), p);
    }
  }

  @override
  bool shouldRepaint(covariant _HDashPainter old) => false;
}
