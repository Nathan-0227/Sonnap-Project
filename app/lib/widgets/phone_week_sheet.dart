// 一週放下手機的時刻（2026-11-15 使用者定）：早晨報告的 Phone down 點開。
// 跟上面兩張（Total sleep、Time in bed）不一樣：**一晚一列、橫的時間軸**，每晚一個點、右邊寫時刻。
//
// - 一週＝這一晚往回 7 個日曆晚上，**舊的在上、這一晚在最下面**（Q7）
// - 最上面：「Usually phone down 03:26」（中間值，跨午夜也對）＋
//   「N of M nights over 30m past your HH:MM target」（Q2；11-15 使用者定寫出 30m：
//   只寫 later 的話 03:26 明明晚於 03:00 卻沒被算，看起來像算錯）
// - ⚠️ 晚不晚**只照抄後端每一晚的 `is_late`**（Q4）：跨午夜只在 behavior/adherence.py 算，
//   Dart 不拿時刻跟目標比。後端沒給 is_late 的晚上不算進 M
// - 虛線＝現在的目標（Q4、Q6：圖上只有這一條線）。點**全部同一個顏色**、不分紅綠，
//   這一晚亮一點（Q3）——好壞只有後端判斷
// - 沒資料的晚上寫「— no data」、不算（Q5），**不畫成 0**
// - 右邊只寫時刻（Q8）
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'bed_week_sheet.dart' show minutesFromEvening, clockOf;

/// 一晚放下手機：時刻（牆鐘）＋後端判的晚不晚（沒給 → null）。
class PhoneDown {
  final DateTime at;
  final bool? isLate;
  const PhoneDown(this.at, this.isLate);
}

class PhoneWeekNight {
  final String date; // yyyy-MM-dd（起床那天）
  final PhoneDown? down;
  const PhoneWeekNight(this.date, this.down);
}

class PhoneWeek {
  final List<PhoneWeekNight> nights; // 舊 → 新，固定 7 格
  const PhoneWeek(this.nights);

  List<PhoneDown> get _downs => [
    for (final n in nights)
      if (n.down != null) n.down!,
  ];

  int get nightsWithData => _downs.length;

  /// 中間值（從 18:00 起算的分鐘）；沒有任何一晚 → null。
  int? get median {
    final xs = _downs.map((d) => minutesFromEvening(d.at)).toList()..sort();
    if (xs.isEmpty) return null;
    final mid = xs.length ~/ 2;
    return xs.length.isOdd ? xs[mid] : ((xs[mid - 1] + xs[mid]) / 2).round();
  }

  /// 後端說晚了的晚數／後端有判的晚數（照抄 is_late，不重算）。
  int get lateNights => _downs.where((d) => d.isLate == true).length;
  int get judgedNights => _downs.where((d) => d.isLate != null).length;
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// [endDate] 那一晚往回 7 晚。純函式。
PhoneWeek phoneWeek({
  required String endDate,
  Map<String, PhoneDown> downs = const {},
  int days = 7,
}) {
  final end = DateTime.parse(endDate);
  return PhoneWeek([
    for (var i = days - 1; i >= 0; i--)
      () {
        final key = _iso(DateTime.utc(end.year, end.month, end.day - i));
        return PhoneWeekNight(key, downs[key]);
      }(),
  ]);
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
                if (late != null)
                  Text(
                    late,
                    key: const Key('phone-week-late'),
                    style: const TextStyle(color: _soft, fontSize: 13),
                  ),
                const SizedBox(height: 18),
                _RowsChart(
                  week: week,
                  color: color,
                  target: targetFromEvening(target),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 一晚一列：左邊星期、中間橫軸上一個點、右邊時刻；底下時刻刻度；目標一條直虛線。
class _RowsChart extends StatelessWidget {
  final PhoneWeek week;
  final Color color;
  final int? target;
  const _RowsChart({required this.week, required this.color, this.target});

  static const double _dayW = 40;
  static const double _timeW = 48;
  static const double _rowH = 30;
  static const double _axisH = 20;

  @override
  Widget build(BuildContext context) {
    // 範圍：涵蓋每一晚與目標，對齊到整點，至少 4 小時寬
    final xs = <int>[
      for (final n in week.nights)
        if (n.down != null) minutesFromEvening(n.down!.at),
      ?target,
    ];
    var lo = xs.reduce(math.min);
    var hi = xs.reduce(math.max);
    lo = (lo ~/ 60) * 60;
    hi = ((hi + 59) ~/ 60) * 60;
    if (hi - lo < 4 * 60) {
      final pad = (4 * 60 - (hi - lo)) ~/ 2;
      lo = math.max(0, ((lo - pad) ~/ 60) * 60);
      hi = math.min(24 * 60, lo + 4 * 60);
    }
    final span = (hi - lo).toDouble();
    final step = span > 6 * 60 ? 120 : 60;
    final rowsH = _rowH * week.nights.length;

    return SizedBox(
      height: rowsH + _axisH,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth - _dayW - _timeW;
          // 點的半徑留邊，最早／最晚的點不貼出軸外
          double x(int v) => _dayW + 6 + (w - 12) * (v - lo) / span;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < week.nights.length; i++)
                Positioned(
                  left: 0,
                  right: 0,
                  top: i * _rowH,
                  height: _rowH,
                  child: _Row(
                    night: week.nights[i],
                    isLast: i == week.nights.length - 1,
                    color: color,
                    dayW: _dayW,
                    timeW: _timeW,
                    dotX: week.nights[i].down == null
                        ? null
                        : x(minutesFromEvening(week.nights[i].down!.at)),
                  ),
                ),
              if (target != null)
                Positioned(
                  key: const Key('phone-week-target'),
                  left: x(target!) - 0.6,
                  top: 0,
                  height: rowsH,
                  child: IgnorePointer(
                    child: CustomPaint(
                      size: Size(1.2, rowsH),
                      painter: _VDashPainter(),
                    ),
                  ),
                ),
              for (var t = lo; t <= hi; t += step)
                Positioned(
                  left: x(t) - 20,
                  width: 40,
                  top: rowsH + 4,
                  child: Text(
                    clockOf(t),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: t == target
                          ? Colors.white
                          : const Color(0x99FFFFFF),
                      fontSize: 10,
                      fontWeight: t == target ? FontWeight.w800 : null,
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

class _Row extends StatelessWidget {
  final PhoneWeekNight night;
  final bool isLast;
  final Color color;
  final double dayW;
  final double timeW;
  final double? dotX;
  const _Row({
    required this.night,
    required this.isLast,
    required this.color,
    required this.dayW,
    required this.timeW,
    required this.dotX,
  });

  @override
  Widget build(BuildContext context) {
    final d = DateTime.parse(night.date);
    final day = _weekdays[d.weekday - 1];
    final down = night.down;
    final dim = isLast ? 1.0 : 0.7;
    return Semantics(
      label: down == null
          ? '$day ${d.day}: no data'
          : '$day ${d.day}: ${clockOf(minutesFromEvening(down.at))}',
      child: Stack(
        key: Key('phone-week-row-${night.date}'),
        children: [
          // 每一列一條淡淡的軌道
          Positioned(
            left: dayW,
            right: timeW,
            top: 14,
            height: 2,
            child: const DecoratedBox(
              decoration: BoxDecoration(color: Color(0x14FFFFFF)),
            ),
          ),
          Positioned(
            left: 0,
            width: dayW,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                day,
                style: TextStyle(
                  color: isLast ? Colors.white : const Color(0xB3FFFFFF),
                  fontSize: 11,
                  fontWeight: isLast ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
          ),
          if (down != null && dotX != null)
            Positioned(
              key: Key('phone-week-dot-${night.date}'),
              left: dotX! - 6,
              top: 9,
              width: 12,
              height: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: dim),
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
          Positioned(
            right: 0,
            width: down == null ? null : timeW,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                down == null
                    ? '— no data'
                    : clockOf(minutesFromEvening(down.at)),
                key: Key('phone-week-time-${night.date}'),
                softWrap: false,
                style: TextStyle(
                  color: down == null
                      ? const Color(0x66FFFFFF)
                      : (isLast ? Colors.white : const Color(0xCCFFFFFF)),
                  fontSize: down == null ? 11 : 12,
                  fontWeight: down == null ? null : FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VDashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xCCFFFFFF)
      ..strokeWidth = 1.2;
    for (double y = 0; y < size.height; y += 7) {
      canvas.drawLine(Offset(0.6, y), Offset(0.6, y + 3.5), p);
    }
  }

  @override
  bool shouldRepaint(covariant _VDashPainter old) => false;
}
