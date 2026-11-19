import 'package:flutter/material.dart';

import '../services/insights_periods.dart';
import '../theme/report_style.dart';
import 'report_tiles.dart' show reportSectionTitle;
import 'week_mood_strip.dart' show MoodFace, moodColor;

/// Insights 的 Week／Month／Year（2026-11-19 grill 定案）：上面一塊心情、下面鏡像格子。
///
/// 每一格跟 Day 的同一項在同一個位置；大字是中位數、小圖 Week／Month 一天一根、Year 一個月一根。
/// **不判斷好壞**：箭頭只代表方向（上升紅、下降綠，分數也一樣）、不寫 Normal、
/// 熬夜照抄後端每晚的 is_late、攝影機不放常模線。
class InsightsPeriodView extends StatelessWidget {
  final PeriodSeries series;
  final InsightsPeriod period;
  final DateTime anchor;
  final DateTime today;

  /// false＝只有打包檔（連不到後端）。Month／Year 照實說要後端，不拿 30 晚冒充。
  final bool online;

  const InsightsPeriodView({
    super.key,
    required this.series,
    required this.period,
    required this.anchor,
    required this.today,
    this.online = true,
  });

  String get _noun => switch (period) {
        InsightsPeriod.week => 'week',
        InsightsPeriod.month => 'month',
        InsightsPeriod.year => 'year',
        InsightsPeriod.day => 'night',
      };

  @override
  Widget build(BuildContext context) {
    if (!online && period != InsightsPeriod.week) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Needs the backend — only the last 30 nights are bundled with the app.',
            key: Key('insights-needs-backend'),
            textAlign: TextAlign.center,
            style: TextStyle(color: ReportColors.muted, fontSize: 14, height: 1.4),
          ),
        ),
      );
    }
    final s = series;
    PeriodStat st(Map<String, double> m) => periodStat(m, period, anchor);
    final sleep = st(s.sleep);
    final inBed = st(s.inBed);
    final bedIn = st(s.bedIn);
    final bedOut = st(s.bedOut);
    final phone = st(s.phoneDown);
    final late = lateCount(s.phoneDowns, period, anchor);
    final awake = st(s.awake);
    final eff = st(s.efficiency);
    final hr = st(s.sleepingHr);
    final deep = st(s.deep);
    final rem = st(s.rem);
    final cam = st(s.cameraPerHour);
    final steps = st(s.steps);
    final kcal = st(s.activeKcal);
    final active = st(s.activeMinutes);
    final stress = st(s.stress);

    final sleepTiles = <Widget>[
      _Tile(
        key: const Key('period-tile-sleep'),
        title: 'Total sleep',
        stat: sleep,
        big: sleep.median == null ? '—' : reportHm(sleep.median!),
        delta: _hmDelta(sleep.delta),
        sub: 'usually · ${_nights(sleep.n)}',
      ),
      _Tile(
        key: const Key('period-tile-bed'),
        title: 'Time in bed',
        stat: inBed,
        big: bedIn.median == null || bedOut.median == null
            ? '—'
            : '${clockLabel(bedIn.median!)} → ${clockLabel(bedOut.median!)}',
        sub: inBed.median == null ? 'no bedtimes' : 'usually · ${reportHm(inBed.median!)} in bed',
      ),
      _Tile(
        key: const Key('period-tile-phone'),
        title: 'Phone down',
        stat: phone,
        big: phone.median == null ? '—' : clockLabel(phone.median!),
        delta: phone.delta == null || phone.delta!.round() == 0
            ? null
            : (phone.delta! > 0,
                '${reportHm(phone.delta!.abs())} ${phone.delta! > 0 ? 'later' : 'earlier'}'),
        sub: late.judged == 0
            ? 'usually'
            : '${late.late} of ${late.judged} nights late',
      ),
      _Tile(
        key: const Key('period-tile-awake'),
        title: 'Awake',
        stat: awake,
        big: awake.median == null ? '—' : reportHm(awake.median!),
        delta: _hmDelta(awake.delta),
        sub: 'usually',
      ),
      _Tile(
        key: const Key('period-tile-eff'),
        title: 'Efficiency',
        stat: eff,
        big: eff.median == null ? '—' : '${eff.median!.round()}%',
        delta: eff.delta == null || eff.delta!.round() == 0
            ? null
            : (eff.delta! > 0, '${eff.delta!.abs().round()}'),
        sub: 'usually · all nights',
      ),
      _Tile(
        key: const Key('period-tile-hr'),
        title: 'Sleeping HR',
        stat: hr,
        big: hr.median == null ? '—' : '${hr.median!.round()} bpm',
        sub: 'usually',
      ),
      _Tile(
        key: const Key('period-tile-phases'),
        title: 'Sleep phases',
        stat: deep,
        big: deep.median == null ? '—' : 'Deep ${reportHm(deep.median!)}',
        sub: rem.median == null ? 'REM not measured' : 'REM ${reportHm(rem.median!)}',
      ),
    ];

    final dayTiles = <Widget>[
      _Tile(
        key: const Key('period-tile-steps'),
        title: 'Steps',
        stat: steps,
        big: steps.median == null ? '—' : _thousands(steps.median!.round()),
        delta: steps.delta == null || steps.delta!.round() == 0
            ? null
            : (steps.delta! > 0, _thousands(steps.delta!.abs().round())),
        sub: 'usually · ${_days(steps.n)}',
      ),
      _Tile(
        key: const Key('period-tile-kcal'),
        title: 'Active kcal',
        stat: kcal,
        big: kcal.median == null ? '—' : '${kcal.median!.round()}',
        sub: 'usually · active only',
      ),
      _Tile(
        key: const Key('period-tile-active'),
        title: 'Active time',
        stat: active,
        big: active.median == null ? '—' : reportHm(active.median!),
        sub: 'usually',
      ),
      _Tile(
        key: const Key('period-tile-stress'),
        title: 'Stress',
        stat: stress,
        big: stress.median == null ? '—' : '${stress.median!.round()}',
        sub: 'usual daily average',
      ),
    ];

    return ListView(
      key: Key('insights-period-${period.name}'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      children: [
        _MoodCard(
          series: s,
          period: period,
          anchor: anchor,
          today: today,
          noun: _noun,
        ),
        const SizedBox(height: 18),
        reportSectionTitle('Sleep'),
        _grid(sleepTiles),
        const SizedBox(height: 10),
        _Tile(
          key: const Key('period-tile-camera'),
          title: 'Movement (camera)',
          stat: cam,
          big: cam.median == null ? '—' : '${cam.median!.round()} moves / hour',
          delta: cam.delta == null || cam.delta!.round() == 0
              ? null
              : (cam.delta! > 0, '${cam.delta!.abs().round()}'),
          sub: cam.n == 0
              ? 'No recordings this $_noun'
              : 'usually · ${_nights(cam.n)} recorded · not part of your score',
        ),
        const SizedBox(height: 18),
        reportSectionTitle('Days'),
        _grid(dayTiles),
      ],
    );
  }

  static (bool, String)? _hmDelta(double? d) =>
      d == null || d.round() == 0 ? null : (d > 0, reportHm(d.abs()));

  static String _nights(int n) => n == 1 ? '1 night' : '$n nights';
  static String _days(int n) => n == 1 ? '1 day' : '$n days';

  static String _thousands(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  static Widget _grid(List<Widget> tiles) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      final pair = i + 1 < tiles.length
          ? Row(children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: 10),
              Expanded(child: tiles[i + 1]),
            ])
          : tiles[i];
      rows
        ..add(pair)
        ..add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }
}

/// 一格：標題、小長條、大字（中位數）＋方向箭頭、小字。
class _Tile extends StatelessWidget {
  final String title;
  final PeriodStat stat;
  final String big;

  /// (往上?, 差多少)。null＝不畫箭頭（沒有上一期、差不多、或這一項不比）。
  final (bool, String)? delta;
  final String sub;

  const _Tile({
    super.key,
    required this.title,
    required this.stat,
    required this.big,
    required this.sub,
    this.delta,
  });

  @override
  Widget build(BuildContext context) {
    final values = stat.bars.whereType<double>();
    final max = values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b);
    final dense = stat.bars.length > 12;
    return Container(
      height: 132,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReportColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ReportColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: ReportColors.muted, fontSize: 12.5)),
          const SizedBox(height: 8),
          SizedBox(
            height: 30,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final v in stat.bars)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: dense ? 0.5 : 2),
                      child: Container(
                        // 沒資料的那一欄只留一條底線，不畫成 0 高的長條
                        height: v == null ? 2 : (4 + 26 * (max <= 0 ? 0 : v / max)),
                        decoration: BoxDecoration(
                          color: v == null
                              ? Colors.white.withValues(alpha: 0.10)
                              : ReportColors.lilac.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(dense ? 1 : 3),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    big,
                    softWrap: false,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              if (delta != null) ...[
                const SizedBox(width: 6),
                Text(
                  '${delta!.$1 ? '↑' : '↓'} ${delta!.$2}',
                  style: TextStyle(
                    color: delta!.$1 ? ReportColors.up : ReportColors.down,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: ReportColors.faint, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// 上面那一塊：這段期間的中位分數＋星星（等級照後端切點），加上心情
/// （Week 7 顆、Month 月曆、Year 365 格熱圖）。心情照抄後端每晚的 pet_mood。
class _MoodCard extends StatelessWidget {
  final PeriodSeries series;
  final InsightsPeriod period;
  final DateTime anchor;
  final DateTime today;
  final String noun;

  const _MoodCard({
    required this.series,
    required this.period,
    required this.anchor,
    required this.today,
    required this.noun,
  });

  @override
  Widget build(BuildContext context) {
    final score = periodStat(series.score, period, anchor);
    final quality = qualityFor(score.median, series.qualityBands);
    final stars = starsFor(quality);
    final d = score.delta;
    return Container(
      key: const Key('period-mood-card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ReportColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Your buddy this $noun',
                  style: const TextStyle(color: ReportColors.muted, fontSize: 13),
                ),
              ),
              if (stars > 0)
                Text(
                  '${'★' * stars}${'☆' * (4 - stars)} ',
                  key: const Key('period-stars'),
                  style: const TextStyle(color: ReportColors.gold, fontSize: 13),
                ),
              Text(
                score.median == null ? '—' : '${score.median!.round()}',
                key: const Key('period-score'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (d != null && d.round() != 0) ...[
                const SizedBox(width: 4),
                Text(
                  '${d > 0 ? '↑' : '↓'} ${d.abs().round()}',
                  style: TextStyle(
                    color: d > 0 ? ReportColors.up : ReportColors.down,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
          if (quality != null)
            Text(
              'usually $quality · ${score.n == 1 ? '1 scored night' : '${score.n} scored nights'}',
              style: const TextStyle(color: ReportColors.faint, fontSize: 11),
            ),
          const SizedBox(height: 12),
          switch (period) {
            InsightsPeriod.week => _week(),
            InsightsPeriod.month => _month(),
            _ => _year(),
          },
        ],
      ),
    );
  }

  Widget _face(String date, double size) {
    final mood = series.mood[date];
    if (isFuture(date, today)) return SizedBox(width: size, height: size);
    if (mood == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 1.2),
        ),
      );
    }
    return MoodFace(mood: mood, size: size);
  }

  Widget _week() {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dates = periodDates(period, anchor);
    return Row(
      key: const Key('period-mood-week'),
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Column(
              children: [
                _face(dates[i], 34),
                const SizedBox(height: 4),
                Text(days[i], style: const TextStyle(color: ReportColors.faint, fontSize: 11)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _month() {
    final dates = periodDates(period, anchor);
    final lead = DateTime.parse(dates.first).weekday - 1; // 週一起
    final cells = <Widget>[
      for (var i = 0; i < lead; i++) const SizedBox(),
      for (final k in dates)
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _face(k, 20),
            Text(
              '${DateTime.parse(k).day}',
              style: TextStyle(
                color: isFuture(k, today) ? ReportColors.dim : ReportColors.soft,
                fontSize: 10,
              ),
            ),
          ],
        ),
    ];
    return Column(
      key: const Key('period-mood-month'),
      children: [
        Row(
          children: [
            for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Text(d,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: ReportColors.faint, fontSize: 10)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          childAspectRatio: 1.05,
          children: cells,
        ),
      ],
    );
  }

  Widget _year() {
    final dates = periodDates(period, anchor);
    final lead = DateTime.parse(dates.first).weekday - 1;
    final cells = <String?>[for (var i = 0; i < lead; i++) null, ...dates];
    final columns = (cells.length / 7).ceil();
    const months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
    return Column(
      key: const Key('period-mood-year'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(builder: (context, c) {
          final cell = (c.maxWidth - (columns - 1)) / columns;
          return Row(
            children: [
              for (var col = 0; col < columns; col++) ...[
                if (col > 0) const SizedBox(width: 1),
                Column(
                  children: [
                    for (var row = 0; row < 7; row++) ...[
                      if (row > 0) const SizedBox(height: 1),
                      Builder(builder: (_) {
                        final i = col * 7 + row;
                        final k = i < cells.length ? cells[i] : null;
                        final mood = k == null ? null : series.mood[k];
                        final Color color;
                        if (k == null || isFuture(k, today)) {
                          color = Colors.transparent;
                        } else if (mood == null) {
                          color = Colors.white.withValues(alpha: 0.06);
                        } else {
                          color = moodColor(mood);
                        }
                        return Container(
                          width: cell,
                          height: cell,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ],
            ],
          );
        }),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final m in months)
              Expanded(
                child: Text(m, style: const TextStyle(color: ReportColors.faint, fontSize: 9)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          children: [
            for (final m in const ['happy', 'bored', 'tired', 'anxious'])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: moodColor(m), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text(m, style: const TextStyle(color: ReportColors.faint, fontSize: 11)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
