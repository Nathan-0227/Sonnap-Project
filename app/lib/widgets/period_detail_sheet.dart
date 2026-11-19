import 'package:flutter/material.dart';

import '../services/insights_periods.dart';
import '../services/morning_report.dart' show reportDateKey;
import '../theme/report_style.dart';
import 'report_sheet.dart';

/// Insights W/M/Y 的格子點開的詳細頁（PR 3，2026-11-19 grill 定案）。
///
/// 開在同一個期間，頁裡也有 Day／Week／Month／Year 與「‹ 期間 ›」。
/// 跟格子同一套規矩：大字是中位數（Day 是那一晚）、沒資料寫「—」不寫 0、
/// 跟上一期比只代表方向（上升紅、下降綠，分數也一樣）、不寫 Normal、不畫常模線。
/// 分數那一頁**不呈現組成**、App 上**不放警語**（11-19 使用者定，只留書面報告）。
class PeriodMetric {
  final String id;
  final String title;
  final IconData icon;

  /// 從 [PeriodSeries] 取逐夜（逐天）的數字。
  final Map<String, double> Function(PeriodSeries s) values;

  /// 數字 → 畫面上的字。
  final String Function(double v) format;

  /// 跟上一期差多少 → 字（null＝差不多，不畫箭頭）。
  final String? Function(double delta) deltaLabel;

  /// true＝時刻（[clockFromNoon]）：畫成點、上早下晚，不畫長條。
  final bool clock;

  /// true＝白天的量（步數、卡路里…），寫 days；false 寫 nights。
  final bool daytime;

  /// 圖下面那一行事實（可為 null）。
  final String? Function(PeriodSeries s, InsightsPeriod p, DateTime anchor)?
  note;

  const PeriodMetric({
    required this.id,
    required this.title,
    required this.icon,
    required this.values,
    required this.format,
    required this.deltaLabel,
    this.clock = false,
    this.daytime = false,
    this.note,
  });

  static PeriodMetric byId(String id) =>
      kPeriodMetrics.firstWhere((m) => m.id == id);
}

String? _hmDelta(double d) => d.round() == 0 ? null : reportHm(d.abs());
String? _intDelta(double d) => d.round() == 0 ? null : '${d.abs().round()}';

/// 1219 → 1,219
String groupThousands(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

final List<PeriodMetric> kPeriodMetrics = [
  PeriodMetric(
    id: 'score',
    title: 'Sleep score',
    icon: Icons.star_rounded,
    values: (s) => s.score,
    format: (v) => '${v.round()}',
    deltaLabel: _intDelta,
    note: (s, p, a) {
      if (p == InsightsPeriod.day) return null;
      final q = qualityFor(periodStat(s.score, p, a).median, s.qualityBands);
      return q == null ? null : 'Usually $q';
    },
  ),
  PeriodMetric(
    id: 'sleep',
    title: 'Total sleep',
    icon: Icons.nightlight_round,
    values: (s) => s.sleep,
    format: reportHm,
    deltaLabel: _hmDelta,
  ),
  PeriodMetric(
    id: 'bed',
    title: 'Time in bed',
    icon: Icons.bed_rounded,
    values: (s) => s.inBed,
    format: reportHm,
    deltaLabel: _hmDelta,
    note: (s, p, a) {
      final i = p == InsightsPeriod.day
          ? s.bedIn[reportDateKey(a)]
          : periodStat(s.bedIn, p, a).median;
      final o = p == InsightsPeriod.day
          ? s.bedOut[reportDateKey(a)]
          : periodStat(s.bedOut, p, a).median;
      if (i == null || o == null) return null;
      final lead = p == InsightsPeriod.day ? 'In bed' : 'Usually in bed';
      return '$lead ${clockLabel(i)} → ${clockLabel(o)} · sleep buttons when both were tapped, otherwise the watch';
    },
  ),
  PeriodMetric(
    id: 'phone',
    title: 'Phone down',
    icon: Icons.phone_android_rounded,
    values: (s) => s.phoneDown,
    format: clockLabel,
    deltaLabel: (d) => d.round() == 0
        ? null
        : '${reportHm(d.abs())} ${d > 0 ? 'later' : 'earlier'}',
    clock: true,
    note: (s, p, a) {
      final l = lateCount(s.phoneDowns, p, a);
      if (l.judged == 0) return null;
      // 晚不晚照抄後端每一晚的 is_late（跨午夜只在 adherence.py 算）
      return '${l.late} of ${l.judged} ${l.judged == 1 ? 'night' : 'nights'} late, as judged by the backend';
    },
  ),
  PeriodMetric(
    id: 'awake',
    title: 'Awake',
    icon: Icons.visibility_rounded,
    values: (s) => s.awake,
    format: reportHm,
    deltaLabel: _hmDelta,
  ),
  PeriodMetric(
    id: 'eff',
    title: 'Efficiency',
    icon: Icons.battery_charging_full_rounded,
    values: (s) => s.efficiency,
    format: (v) => '${v.round()}%',
    deltaLabel: _intDelta,
    // 11-19 使用者定：所有種類合在一起（知情：按按鈕多的期間看起來會比較低）
    note: (s, p, a) => 'All nights together, with or without the sleep button',
  ),
  PeriodMetric(
    id: 'hr',
    title: 'Sleeping heart rate',
    icon: Icons.favorite_rounded,
    values: (s) => s.sleepingHr,
    format: (v) => '${v.round()} bpm',
    deltaLabel: _intDelta,
  ),
  PeriodMetric(
    id: 'phases',
    title: 'Deep sleep',
    icon: Icons.waves_rounded,
    values: (s) => s.deep,
    format: reportHm,
    deltaLabel: _hmDelta,
    note: (s, p, a) {
      final rem = p == InsightsPeriod.day
          ? s.rem[reportDateKey(a)]
          : periodStat(s.rem, p, a).median;
      return rem == null
          ? 'REM not measured'
          : '${p == InsightsPeriod.day ? 'REM' : 'REM usually'} ${reportHm(rem)}';
    },
  ),
  PeriodMetric(
    id: 'camera',
    title: 'Movement (camera)',
    icon: Icons.videocam_rounded,
    values: (s) => s.cameraPerHour,
    format: (v) => '${v.round()} moves / hour',
    deltaLabel: _intDelta,
    // 🔴 不放文獻常模（事件率跨夜不穩 3.1 倍、構念不同）
    note: (s, p, a) => 'Not part of your score',
  ),
  PeriodMetric(
    id: 'steps',
    title: 'Steps',
    icon: Icons.directions_walk_rounded,
    values: (s) => s.steps,
    format: (v) => groupThousands(v.round()),
    deltaLabel: (d) => d.round() == 0 ? null : groupThousands(d.abs().round()),
    daytime: true,
    note: (s, p, a) => 'Days without the watch are left out',
  ),
  PeriodMetric(
    id: 'kcal',
    title: 'Active kcal',
    icon: Icons.local_fire_department_rounded,
    values: (s) => s.activeKcal,
    format: (v) => '${v.round()} kcal',
    deltaLabel: _intDelta,
    daytime: true,
    note: (s, p, a) => 'Active only, not total burn',
  ),
  PeriodMetric(
    id: 'active',
    title: 'Active time',
    icon: Icons.bolt_rounded,
    values: (s) => s.activeMinutes,
    format: reportHm,
    deltaLabel: _hmDelta,
    daytime: true,
  ),
  PeriodMetric(
    id: 'stress',
    title: 'Stress',
    icon: Icons.spa_rounded,
    values: (s) => s.stress,
    // Garmin 的 0–100 分數，不加 %（會被讀成「56% 的時間有壓力」）
    format: (v) => '${v.round()}',
    deltaLabel: _intDelta,
    daytime: true,
    note: (s, p, a) => 'Daily average of Garmin\'s stress readings',
  ),
];

Future<void> showPeriodDetailSheet(
  BuildContext context, {
  required PeriodMetric metric,
  required PeriodSeries series,
  required InsightsPeriod period,
  required DateTime anchor,
  required DateTime today,
  bool online = true,
}) => showReportSheet<void>(
  context: context,
  builder: (_) => PeriodDetailView(
    metric: metric,
    series: series,
    period: period,
    anchor: anchor,
    today: today,
    online: online,
  ),
);

/// 從 W/M/Y 切到 Day 時停在哪一晚：這段期間裡最後一個有資料的日子（不晚於今天），
/// 都沒有就停在期間的最後一天（或今天）。
DateTime dayAnchorFor(
  Map<String, double> values,
  InsightsPeriod period,
  DateTime anchor,
  DateTime today,
) {
  final r = insightsRange(period, anchor);
  final t = dateOnly(today);
  final end = r.end.isAfter(t) ? t : r.end;
  for (
    var d = end;
    !d.isBefore(r.start);
    d = DateTime(d.year, d.month, d.day - 1)
  ) {
    if (values.containsKey(reportDateKey(d))) return d;
  }
  return end;
}

/// 上一個有資料的晚上（Day 的「跟上一晚比」）。
double? previousWithData(Map<String, double> values, String date) {
  String? best;
  for (final k in values.keys) {
    if (k.compareTo(date) < 0 && (best == null || k.compareTo(best) > 0)) {
      best = k;
    }
  }
  return best == null ? null : values[best];
}

class PeriodDetailView extends StatefulWidget {
  final PeriodMetric metric;
  final PeriodSeries series;
  final InsightsPeriod period;
  final DateTime anchor;
  final DateTime today;
  final bool online;

  const PeriodDetailView({
    super.key,
    required this.metric,
    required this.series,
    required this.period,
    required this.anchor,
    required this.today,
    this.online = true,
  });

  @override
  State<PeriodDetailView> createState() => _PeriodDetailViewState();
}

class _PeriodDetailViewState extends State<PeriodDetailView> {
  late InsightsPeriod _period = widget.period;
  late DateTime _anchor = dateOnly(widget.anchor);
  int? _selected;

  Map<String, double> get _values => widget.metric.values(widget.series);

  void _setPeriod(InsightsPeriod p) {
    if (p == _period) return;
    setState(() {
      if (p == InsightsPeriod.day) {
        _anchor = dayAnchorFor(_values, _period, _anchor, widget.today);
      } else if (_anchor.isAfter(dateOnly(widget.today))) {
        _anchor = dateOnly(widget.today);
      }
      _period = p;
      _selected = null;
    });
  }

  void _shift(int step) => setState(() {
    _anchor = insightsShift(_period, _anchor, step);
    _selected = null;
  });

  @override
  Widget build(BuildContext context) {
    final m = widget.metric;
    final first = widget.series.firstDate;
    final canPrev = insightsCanGoPrev(_period, _anchor, first);
    final canNext = insightsCanGoNext(_period, _anchor, widget.today);
    return Container(
      key: Key('period-detail-${m.id}'),
      decoration: const BoxDecoration(
        color: ReportColors.sheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
          child: ReportFont(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(m.icon, color: ReportColors.lilac, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      m.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _tabs(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      key: const Key('period-detail-prev'),
                      onPressed: canPrev ? () => _shift(-1) : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                      color: Colors.white,
                      disabledColor: Colors.white24,
                    ),
                    Expanded(
                      child: Text(
                        insightsLabel(_period, _anchor),
                        key: const Key('period-detail-label'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('period-detail-next'),
                      onPressed: canNext ? () => _shift(1) : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                      color: Colors.white,
                      disabledColor: Colors.white24,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (!widget.online &&
                    (_period == InsightsPeriod.month ||
                        _period == InsightsPeriod.year))
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Text(
                      'Needs the backend — only the last 30 nights are bundled with the app.',
                      key: Key('period-detail-needs-backend'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: ReportColors.muted,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  )
                else
                  ..._body(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabs() => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        for (final p in InsightsPeriod.values)
          Expanded(
            child: GestureDetector(
              key: Key('period-detail-tab-${p.name}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _setPeriod(p),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: p == _period
                      ? ReportColors.purple
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  insightsPeriodLabels[p]!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: p == _period ? Colors.white : ReportColors.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  List<Widget> _body() {
    final m = widget.metric;
    final values = _values;
    final today = dateOnly(widget.today);

    // 大字、方向、幾晚有資料
    final double? big;
    final double? delta;
    final String countLine;
    final String noun = m.daytime ? 'day' : 'night';
    final List<double?> bars;
    final List<String> labels;
    final List<String> keys; // 每一欄是哪一天（Year 是那個月的第一天）
    int? highlight;

    if (_period == InsightsPeriod.day) {
      final k = reportDateKey(_anchor);
      big = values[k];
      final prev = previousWithData(values, k);
      delta = big == null || prev == null ? null : big - prev;
      countLine = big == null
          ? 'No data for this $noun'
          : (prev == null ? 'This $noun' : 'vs the previous $noun with data');
      // Day 底下的圖：那一晚所在的那一週，這一晚亮一點
      keys = periodDates(InsightsPeriod.week, _anchor);
      bars = [for (final d in keys) values[d]];
      labels = const ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
      highlight = keys.indexOf(k);
    } else {
      final st = periodStat(values, _period, _anchor);
      big = st.median;
      delta = st.delta;
      final dates = periodDates(_period, _anchor);
      final possible = dates.where((d) => !isFuture(d, today)).length;
      countLine = st.n == 0
          ? 'No data this ${insightsPeriodLabels[_period]!.toLowerCase()}'
          : 'Usually · ${st.n} of $possible ${possible == 1 ? noun : '${noun}s'} with data';
      bars = st.bars;
      if (_period == InsightsPeriod.year) {
        final y = insightsRange(_period, _anchor).start.year;
        keys = [
          for (var mo = 1; mo <= 12; mo++) reportDateKey(DateTime(y, mo, 1)),
        ];
        labels = const [
          'J',
          'F',
          'M',
          'A',
          'M',
          'J',
          'J',
          'A',
          'S',
          'O',
          'N',
          'D',
        ];
      } else if (_period == InsightsPeriod.week) {
        keys = dates;
        labels = const ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
      } else {
        keys = dates;
        labels = [
          for (final d in dates)
            {1, 8, 15, 22, 29}.contains(DateTime.parse(d).day)
                ? '${DateTime.parse(d).day}'
                : '',
        ];
      }
    }

    final dl = delta == null ? null : m.deltaLabel(delta);
    final note = m.note?.call(widget.series, _period, _anchor);
    final median = _period == InsightsPeriod.day ? null : big;

    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Text(
              big == null ? '—' : m.format(big),
              key: const Key('period-detail-big'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (dl != null) ...[
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text(
                '${delta! > 0 ? '↑' : '↓'} $dl',
                key: const Key('period-detail-delta'),
                // 只代表方向：上升紅、下降綠（分數也一樣）
                style: TextStyle(
                  color: delta > 0 ? ReportColors.up : ReportColors.down,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
      Text(
        dl == null || _period == InsightsPeriod.day
            ? countLine
            : '$countLine · vs the ${insightsPeriodLabels[_period]!.toLowerCase()} before',
        key: const Key('period-detail-count'),
        style: const TextStyle(color: ReportColors.faint, fontSize: 12.5),
      ),
      const SizedBox(height: 18),
      SizedBox(
        height: 18,
        child: _selected == null || _selected! >= keys.length
            ? const SizedBox()
            : Text(
                _readout(keys[_selected!], bars[_selected!]),
                key: const Key('period-detail-readout'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
      const SizedBox(height: 6),
      _Chart(
        values: bars,
        labels: labels,
        clock: m.clock,
        highlight: highlight ?? _selected,
        median: median,
        future: [for (final k in keys) isFuture(k, today)],
        onTap: (i) => setState(() => _selected = i),
      ),
      if (_period == InsightsPeriod.year)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Each bar is that month\'s usual value',
            style: TextStyle(color: ReportColors.dim, fontSize: 11),
          ),
        ),
      if (note != null) ...[
        const SizedBox(height: 14),
        Text(
          note,
          key: const Key('period-detail-note'),
          style: const TextStyle(
            color: ReportColors.muted,
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
      ],
    ];
  }

  String _readout(String key, double? v) {
    final d = DateTime.parse(key);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final when = _period == InsightsPeriod.year
        ? months[d.month - 1]
        : insightsLabel(InsightsPeriod.day, d);
    if (v == null) return '$when · no data';
    final prefix = _period == InsightsPeriod.year ? 'usually ' : '';
    return '$when · $prefix${widget.metric.format(v)}';
  }
}

/// 長條（或時刻的點）。沒資料的欄只留一條底線，不畫成 0；未來的日子整欄空著。
class _Chart extends StatelessWidget {
  final List<double?> values;
  final List<String> labels;
  final bool clock;
  final int? highlight;
  final double? median;
  final List<bool> future;
  final ValueChanged<int> onTap;

  const _Chart({
    required this.values,
    required this.labels,
    required this.clock,
    required this.highlight,
    required this.median,
    required this.future,
    required this.onTap,
  });

  static const double _h = 150;

  @override
  Widget build(BuildContext context) {
    final present = values.whereType<double>().toList();
    final dense = values.length > 12;
    double lo = 0, hi = 1;
    if (present.isNotEmpty) {
      hi = present.reduce((a, b) => a > b ? a : b);
      if (clock) {
        lo = present.reduce((a, b) => a < b ? a : b) - 30;
        hi = hi + 30;
      } else {
        lo = 0;
        if (hi <= 0) hi = 1;
      }
    }
    double frac(double v) => ((v - lo) / (hi - lo)).clamp(0.0, 1.0);

    return Column(
      key: const Key('period-detail-chart'),
      children: [
        SizedBox(
          height: _h,
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < values.length; i++)
                    Expanded(
                      child: GestureDetector(
                        key: Key('period-detail-bar-$i'),
                        behavior: HitTestBehavior.opaque,
                        onTap: future[i] ? null : () => onTap(i),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: dense ? 1 : 4,
                          ),
                          child: _cell(values[i], i, frac, dense),
                        ),
                      ),
                    ),
                ],
              ),
              if (median != null)
                Positioned(
                  left: 0,
                  right: 0,
                  // 時刻上早下晚：數字越大越下面；長條從底下長
                  top: clock ? frac(median!) * (_h - 8) + 3 : null,
                  bottom: clock ? null : frac(median!) * (_h - 4),
                  child: IgnorePointer(
                    child: CustomPaint(
                      key: const Key('period-detail-median'),
                      size: const Size(double.infinity, 1.5),
                      painter: _DashPainter(),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final l in labels)
              Expanded(
                child: Text(
                  l,
                  textAlign: TextAlign.center,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: const TextStyle(
                    color: ReportColors.faint,
                    fontSize: 10.5,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _cell(double? v, int i, double Function(double) frac, bool dense) {
    if (future[i]) return const SizedBox();
    final on = highlight == i;
    final color = on
        ? ReportColors.gold
        : ReportColors.lilac.withValues(alpha: 0.75);
    if (v == null) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: 2,
          color: Colors.white.withValues(alpha: 0.12),
        ),
      );
    }
    if (clock) {
      return Align(
        alignment: Alignment(0, -1 + 2 * frac(v)),
        child: Container(
          width: dense ? 5 : 10,
          height: dense ? 5 : 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      );
    }
    return Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: 0.03 + 0.97 * frac(v),
        widthFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(dense ? 1.5 : 6),
          ),
        ),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.2;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, 0), Offset(x + 4, 0), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
