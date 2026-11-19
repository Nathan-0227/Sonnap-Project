part of 'friend_night_card.dart';

// 完整頁往下捲的區塊（2026-11-16 使用者定，照 Strava 活動頁：一段一段、粗體標題 → 圖 → 左名稱右數字）。
// 順序：Sleep stages → Heart rate → Movement (camera) → Bedtime → Morning → Game。
// 白天的資料（步數、壓力…）不放：跟睡眠無關（使用者定）。
// 每一段只在他有分享對應項目時才出現；沒值的那一列不畫、不畫成 0。
// ⚠️ 只寫事實：不寫 Normal／High、不分好壞、不用紅綠；準時與否照抄後端的 on_time。

const _sectionBand = Color(0xFF0A1028);
const _rowLabel = TextStyle(color: Color(0xB3FFFFFF), fontSize: 15);
const _rowValue = TextStyle(
  color: Colors.white,
  fontSize: 17,
  fontWeight: FontWeight.w800,
);
const _hrColor = Color(0xFF8C9BFF); // 同早晨報告的 Sleeping HR（靛藍）

/// 「23:12」→ 從傍晚起算的分鐘（過了午夜的接在後面），排時間軸用。
int? _clock(dynamic v) {
  if (v is! String) return null;
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(v);
  if (m == null) return null;
  final h = int.parse(m.group(1)!), mi = int.parse(m.group(2)!);
  return (h < 18 ? h + 24 : h) * 60 + mi;
}

List<(double, double)> _curve(dynamic v) => [
  for (final p in (v is List ? v : const []))
    if (p is Map && _n(p['m']) != null && _n(p['v']) != null)
      (_n(p['m'])!.toDouble(), _n(p['v'])!.toDouble()),
];

/// 完整頁的全部區塊（每一段自己帶上方那條粗線與左右留白）。
List<Widget> friendNightSections(Map<String, dynamic> items) {
  Map<String, dynamic> m(String k) =>
      items[k] is Map ? (items[k] as Map).cast<String, dynamic>() : const {};
  final out = <Widget>[];

  // ① Sleep stages
  final stages = _stagesOf(items);
  final segments = _segmentsOf(stages);
  final awake = m('awake');
  if (segments.isNotEmpty || stages != null || awake.isNotEmpty) {
    final remOk = stages?['rem_measured'] != false;
    final parts = [
      for (final (k, name) in const [('deep', 'Deep'), ('light', 'Light'), ('rem', 'REM')])
        if (_n(stages?[k]) != null || (k == 'rem' && !remOk)) (k, name),
    ];
    final total = [
      for (final (k, _) in parts) (_n(stages?[k]) ?? 0).toDouble(),
    ].fold<double>(0, (a, b) => a + b);
    out.add(
      _Section(
        key: const Key('section-stages'),
        title: 'Sleep stages',
        children: [
          if (segments.isNotEmpty) ...[
            _StageChart(
              segments: segments,
              remMeasured: remOk,
              start: stages?['start'] as String?,
              end: stages?['end'] as String?,
              minutes: stages ?? const {},
              showTitle: false,
            ),
            const SizedBox(height: 14),
          ],
          // 像 Strava 的 Splits：一個階段一列，長條是佔整晚睡眠的比例（同一個顏色，不分好壞）
          for (final (k, name) in parts)
            _StageRow(
              key: Key('stage-row-$k'),
              color: _stageColors[k]!,
              name: name,
              minutes: k == 'rem' && !remOk ? null : _n(stages?[k])?.toDouble(),
              // 沒量到 REM：不畫長條、不寫 0%（0% 會被讀成整晚沒有 REM）
              share: !(k == 'rem' && !remOk) && total > 0 && _n(stages?[k]) != null
                  ? _n(stages?[k])! / total
                  : null,
            ),
          if (_n(awake['count']) != null || _n(awake['minutes']) != null)
            _Row(
              key: const Key('stage-row-awake'),
              label: 'Awake',
              value: [
                if (_n(awake['count']) != null)
                  '${_n(awake['count'])!.round()} ${_n(awake['count']) == 1 ? 'time' : 'times'}',
                if (_n(awake['minutes']) != null) _m(awake['minutes']),
              ].join(' · '),
            ),
        ],
      ),
    );
  }

  // ② Heart rate（睡著那段）
  final hr = m('sleeping_hr');
  final resting = _n(items['resting_hr']);
  if (hr.isNotEmpty || resting != null) {
    final pts = _curve(hr['curve']);
    out.add(
      _Section(
        key: const Key('section-hr'),
        title: 'Heart rate',
        children: [
          if (pts.length >= 2) ...[
            SizedBox(
              height: 150,
              width: double.infinity,
              child: CustomPaint(
                key: const Key('hr-chart'),
                painter: _AreaPainter(pts, _hrColor, avg: _n(hr['avg'])?.toDouble()),
              ),
            ),
            _ChartEnds(start: stages?['start'] as String?, end: stages?['end'] as String?),
            const SizedBox(height: 8),
          ],
          if (_n(hr['avg']) != null)
            _Row(label: 'Avg while asleep', value: '${_n(hr['avg'])!.round()} bpm'),
          if (_n(hr['min']) != null)
            _Row(label: 'Lowest', value: '${_n(hr['min'])!.round()} bpm'),
          if (resting != null)
            _Row(label: 'Resting (all day)', value: '${resting.round()} bpm'),
        ],
      ),
    );
  }

  // ③ Movement (camera)
  final perHour = _n(items['camera_moves']);
  final cam = m('camera_timeline');
  if (perHour != null || cam.isNotEmpty) {
    final bars = _curve(cam['points']);
    out.add(
      _Section(
        key: const Key('section-camera'),
        title: 'Movement (camera)',
        children: [
          if (cam['usual'] is String) ...[
            Text(
              cam['usual'] as String,
              style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 14),
            ),
            const SizedBox(height: 12),
          ],
          if (bars.isNotEmpty) ...[
            SizedBox(
              height: 110,
              width: double.infinity,
              child: CustomPaint(
                key: const Key('camera-chart'),
                painter: _BarsPainter(bars),
              ),
            ),
            _ChartEnds(start: cam['start'] as String?, end: cam['end'] as String?),
            const SizedBox(height: 8),
          ],
          if (perHour != null)
            _Row(label: 'Moves per hour', value: '${perHour.round()}'),
          if (_n(cam['total']) != null)
            _Row(label: 'Moves in total', value: '${_n(cam['total'])!.round()}'),
          if (_n(cam['moving_sec']) != null)
            _Row(label: 'Moving time', value: _m(_n(cam['moving_sec'])! / 60)),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Seen by the camera. Not part of the sleep score.',
              style: TextStyle(color: Color(0x80FFFFFF), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ④ Bedtime：照時間排的一條直線時間軸（像 Strava 的配速圖那段，但只有幾個時刻）
  final bed = m('bed_times');
  final events = <(int, String, String, IconData, bool)>[
    if (_clock(items['target_bedtime']) case final t?)
      (t, items['target_bedtime'] as String, 'Target bedtime', Icons.flag_outlined, true),
    if (_clock(items['phone_down_time']) case final t?)
      (
        t,
        items['phone_down_time'] as String,
        items['on_time'] is bool
            ? 'Phone down · ${items['on_time'] == true ? 'On time' : 'Late'}'
            : 'Phone down',
        Icons.phone_android_rounded,
        false,
      ),
    if (_clock(bed['start']) case final t?)
      (t, bed['start'] as String, 'Start Sleep', Icons.bed_rounded, false),
    if (_clock(stages?['start']) case final t?)
      (
        t,
        stages!['start'] as String,
        _n(items['fell_asleep']) != null
            ? 'Fell asleep · ${_m(items['fell_asleep'])} after Start Sleep'
            : 'Fell asleep',
        Icons.nightlight_round,
        false,
      ),
    if (_clock(stages?['end']) case final t?)
      (t, stages!['end'] as String, 'Woke up', Icons.wb_sunny_rounded, false),
    if (_clock(bed['end']) case final t?)
      (t, bed['end'] as String, 'Out of bed', Icons.directions_walk_rounded, false),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final eff = m('efficiency');
  final bedRows = [
    if (events.isEmpty && items['on_time'] is bool)
      _Row(label: 'Bedtime', value: items['on_time'] == true ? 'On time' : 'Late'),
    if (_n(items['time_in_bed']) != null)
      _Row(label: 'Time in bed', value: _m(items['time_in_bed'])),
    if (_n(items['phone_after_start']) != null)
      _Row(label: 'Phone use after Start Sleep', value: _m(items['phone_after_start'])),
    if (_n(items['prebed_phone']) != null)
      _Row(label: 'Phone use in the hour before bed', value: _m(items['prebed_phone'])),
    if (_n(eff['value']) != null)
      _Row(
        label: 'Efficiency',
        sub: eff['label'] as String?,
        value: '${_n(eff['value'])!.round()}%',
      ),
  ];
  if (events.isNotEmpty || bedRows.isNotEmpty) {
    out.add(
      _Section(
        key: const Key('section-bedtime'),
        title: 'Bedtime',
        children: [
          for (final (i, (_, time, label, icon, hollow)) in events.indexed)
            _TimelineStep(
              key: Key('bed-step-$i'),
              time: time,
              label: label,
              icon: icon,
              hollow: hollow,
              first: i == 0,
              last: i == events.length - 1,
            ),
          if (events.isNotEmpty && bedRows.isNotEmpty) const SizedBox(height: 8),
          ...bedRows,
        ],
      ),
    );
  }

  // ⑤ Morning：起床時自己覺得怎樣（只有那個詞）
  final rating = m('morning_rating');
  if (rating['label'] is String) {
    out.add(
      _Section(
        key: const Key('section-morning'),
        title: 'Morning',
        children: [
          _Row(label: 'Felt when waking up', value: rating['label'] as String),
        ],
      ),
    );
  }

  // ⑦ Game
  final level = m('level');
  final outfit = m('outfit');
  final challenges = [
    for (final c in (items['challenges'] is List ? items['challenges'] as List : const []))
      if (c is Map && c['title'] is String) (c['title'] as String, c['completed'] == true),
  ];
  if (level.isNotEmpty || _n(outfit['badges']) != null || challenges.isNotEmpty) {
    out.add(
      _Section(
        key: const Key('section-game'),
        title: 'Game',
        children: [
          if (_n(level['level']) != null)
            _Row(label: 'Level', value: 'Lv ${_n(level['level'])!.round()}'),
          if (_n(level['xp_total']) != null)
            _Row(label: 'Experience', value: '${_int(_n(level['xp_total'])!)} XP'),
          if (_n(outfit['badges']) != null)
            _Row(label: 'Badges', value: '${_n(outfit['badges'])!.round()}'),
          for (final (title, done) in challenges)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                    color: done ? const Color(0xFFC9B8FF) : const Color(0x66FFFFFF),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
  return out;
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(height: 8, color: _sectionBand, margin: const EdgeInsets.only(top: 24)),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    ],
  );
}

class _Row extends StatelessWidget {
  final String label;
  final String? sub;
  final String value;
  const _Row({super.key, required this.label, required this.value, this.sub});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: _rowLabel),
              if (sub != null)
                Text(
                  sub!,
                  style: const TextStyle(color: Color(0x80FFFFFF), fontSize: 12),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(value, style: _rowValue),
      ],
    ),
  );
}

class _StageRow extends StatelessWidget {
  final Color color;
  final String name;
  final double? minutes;
  final double? share;
  const _StageRow({
    super.key,
    required this.color,
    required this.name,
    required this.minutes,
    required this.share,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 52, child: Text(name, style: _rowLabel)),
        SizedBox(
          width: 72,
          child: Text(
            minutes == null ? 'not measured' : _m(minutes),
            style: minutes == null
                ? const TextStyle(color: Color(0x80FFFFFF), fontSize: 13)
                : _rowValue.copyWith(fontSize: 15),
          ),
        ),
        Expanded(
          child: share == null
              ? const SizedBox.shrink()
              : LayoutBuilder(
                  builder: (context, c) => Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: 14,
                      width: c.maxWidth * share!.clamp(0.02, 1.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C7BFF),
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                  ),
                ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            share == null ? '' : '${(share! * 100).round()}%',
            textAlign: TextAlign.right,
            style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 14),
          ),
        ),
      ],
    ),
  );
}

class _ChartEnds extends StatelessWidget {
  final String? start;
  final String? end;
  const _ChartEnds({required this.start, required this.end});

  @override
  Widget build(BuildContext context) {
    const s = TextStyle(color: Color(0xB3FFFFFF), fontSize: 11);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Text(start ?? 'Fell asleep', style: s),
          const Spacer(),
          Text(end ?? 'Woke up', style: s),
        ],
      ),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  final String time;
  final String label;
  final IconData icon;
  final bool hollow;
  final bool first;
  final bool last;
  const _TimelineStep({
    super.key,
    required this.time,
    required this.label,
    required this.icon,
    required this.hollow,
    required this.first,
    required this.last,
  });

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 52,
          child: Padding(
            padding: const EdgeInsets.only(top: 11),
            child: Text(
              time,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        SizedBox(
          width: 34,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                top: first ? 20 : 0,
                bottom: last ? null : 0,
                height: last ? 20 : null,
                child: Container(width: 2, color: const Color(0x40FFFFFF)),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hollow ? const Color(0xFF0E1B4D) : const Color(0xFF7657FF),
                    border: Border.all(color: const Color(0xFFA48BFF), width: 2),
                  ),
                  child: Icon(icon, size: 13, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 15)),
          ),
        ),
      ],
    ),
  );
}

/// 心率：面積線（像 Strava 的 Heart Rate）＋ 虛線＝平均＋左邊刻度。不畫區間顏色帶。
class _AreaPainter extends CustomPainter {
  final List<(double, double)> pts;
  final Color color;
  final double? avg;
  _AreaPainter(this.pts, this.color, {this.avg});

  @override
  void paint(Canvas canvas, Size size) {
    const left = 30.0;
    final w = size.width - left;
    final xs = pts.map((p) => p.$1);
    final ys = pts.map((p) => p.$2);
    final x0 = xs.reduce(math.min), x1 = xs.reduce(math.max);
    var y0 = (ys.reduce(math.min) / 10).floor() * 10.0;
    var y1 = (ys.reduce(math.max) / 10).ceil() * 10.0;
    if (y1 - y0 < 20) y1 = y0 + 20;
    Offset at(double x, double y) => Offset(
      left + (x1 == x0 ? 0 : (x - x0) / (x1 - x0)) * w,
      size.height - (y - y0) / (y1 - y0) * size.height,
    );
    final grid = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 1;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var y = y0; y <= y1; y += 10) {
      final dy = at(x0, y).dy;
      canvas.drawLine(Offset(left, dy), Offset(size.width, dy), grid);
      tp.text = TextSpan(
        text: '${y.round()}',
        style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 10),
      );
      tp.layout();
      tp.paint(canvas, Offset(0, dy - tp.height / 2));
    }
    final line = Path()..moveTo(at(pts.first.$1, pts.first.$2).dx, at(pts.first.$1, pts.first.$2).dy);
    for (final p in pts.skip(1)) {
      final o = at(p.$1, p.$2);
      line.lineTo(o.dx, o.dy);
    }
    final area = Path.from(line)
      ..lineTo(at(pts.last.$1, y0).dx, size.height)
      ..lineTo(at(pts.first.$1, y0).dx, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.75), color.withValues(alpha: 0.15)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    if (avg != null) {
      final dy = at(x0, avg!).dy;
      final dash = Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5;
      for (var x = left; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, dy), Offset(math.min(x + 4, size.width), dy), dash);
      }
    }
  }

  @override
  bool shouldRepaint(_AreaPainter o) => o.pts != pts;
}

/// 攝影機：每 5 分鐘一根光柱，高度＝那 5 分鐘有幾成時間在動（照抄後端，不平滑）。一個色系、不分好壞。
class _BarsPainter extends CustomPainter {
  final List<(double, double)> bars;
  _BarsPainter(this.bars);

  @override
  void paint(Canvas canvas, Size size) {
    final n = bars.length;
    final slot = size.width / n;
    final w = math.max(1.5, slot * 0.62);
    final top = bars.map((b) => b.$2).fold<double>(0.05, math.max);
    for (final (i, (_, v)) in bars.indexed) {
      final f = (v / top).clamp(0.0, 1.0);
      final h = math.max(3.0, f * size.height);
      final x = i * slot + (slot - w) / 2;
      final c = Color.lerp(const Color(0xFFB9A7FF), const Color(0xFFFFD27A), f)!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - h, w, h),
          Radius.circular(w / 2),
        ),
        Paint()..color = v == 0 ? c.withValues(alpha: 0.25) : c,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter o) => o.bars != bars;
}
