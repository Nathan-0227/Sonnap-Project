import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/night_curve.dart';
import '../models/sleep_stages.dart';
import '../theme/sonnap_colors.dart';
import 'curve_path.dart';

/// 首頁與早晨報告的 Sleep Stages 卡（2026-11-12 使用者定案，參考 LUNA 的版面）。
///
/// ⚠️ 曲線是**圓角的階梯**，不是平滑波浪：平滑曲線會穿過那一刻沒發生過的階段
///    （例如深睡直接醒來時會畫過淺睡那一層），等於畫出假的資料。
/// ⚠️ 那晚沒量到 REM（[SleepStages.remMeasured] 為 false）時不畫 REM 那一層，
///    圖例寫 not measured——畫成空的一層會讓人以為整晚沒有 REM。
/// ⚠️ 不放警語（2026-11-12 使用者決定）。圖例的分鐘數用手錶自己的總數。
///
/// **疊線（2026-11-13 使用者定，照 Garmin Connect 的做法）**：圖下面兩顆 Heart rate／Movement，
/// 點了就把那條線疊在階梯上（階梯變淡），再點一次回到只有階梯；一次只能選一個。
/// - 心率：右邊寫 bpm 數字，虛線是睡著期間的平均，下面一行照抄平均、最低、靜止心率；**不寫 Normal**。
/// - 動作是**手錶的**（不是攝影機），沒有單位，右邊只寫 More／Less，下面註明 from your watch。
/// - 那一晚沒有那條線 → 那顆不出現；兩條都沒有 → 一顆都不出現，就是原本的卡。
/// - 線用單調三次插值（[monotonePath]），不會畫出比實際最低還低的值。
class SleepStagesCard extends StatefulWidget {
  final SleepStages stages;
  final int? totalSleepMinutes;

  /// 睡著期間的心率曲線（後端 metrics.heart_rate_curve）。
  final NightCurve? heartRate;

  /// 睡著期間的手錶動作曲線（後端 metrics.movement_curve）。
  final NightCurve? movement;

  /// 靜止心率（後端 metrics.resting_heart_rate）。只在選了心率時寫在下面那一行。
  final double? restingHeartRate;

  const SleepStagesCard({
    super.key,
    required this.stages,
    this.totalSleepMinutes,
    this.heartRate,
    this.movement,
    this.restingHeartRate,
  });

  static const awake = Color(0xFFFF8AD8);
  static const rem = Color(0xFFC9A7FF);
  static const light = Color(0xFF6FA8FF);
  static const deep = Color(0xFF4FE0E0);

  @override
  State<SleepStagesCard> createState() => _SleepStagesCardState();
}

enum _Overlay { heartRate, movement }

class _SleepStagesCardState extends State<SleepStagesCard> {
  _Overlay? _overlay;

  static String _hm(int m) {
    final h = m ~/ 60;
    final r = m % 60;
    if (h == 0) return '${r}m';
    return '${h}h ${r}m';
  }

  NightCurve? get _curve => switch (_overlay) {
        _Overlay.heartRate => widget.heartRate,
        _Overlay.movement => widget.movement,
        null => null,
      };

  void _toggle(_Overlay o) =>
      setState(() => _overlay = _overlay == o ? null : o);

  @override
  Widget build(BuildContext context) {
    final stages = widget.stages;
    final levels = ['awake', if (stages.remMeasured) 'rem', 'light', 'deep'];
    final fmt = DateFormat('h:mm a');
    final span = stages.end.difference(stages.start);
    final ticks = [
      for (var i = 0; i < 4; i++)
        stages.start.add(Duration(seconds: (span.inSeconds * i / 3).round())),
    ];
    final hasChips = widget.heartRate != null || widget.movement != null;
    final curve = _curve;
    // 右邊留給疊線的刻度（有任何一條線可以選的晚上才留，同一晚不會忽寬忽窄）
    final gutter = hasChips ? 34.0 : 0.0;

    return Container(
      key: const Key('sleep-stages-card'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: sonnapCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.auto_awesome,
                  color: SleepStagesCard.rem, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Sleep Stages',
                  style: TextStyle(
                    color: SonnapColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (widget.totalSleepMinutes != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _hm(widget.totalSleepMinutes!),
                      style: const TextStyle(
                        color: SonnapColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text(
                      'Total Sleep',
                      style: TextStyle(
                        color: SonnapColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 120,
            width: double.infinity,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        painter: _StagePainter(
                          stages: stages,
                          levels: levels,
                          dimmed: curve != null,
                        ),
                      ),
                      if (curve != null)
                        CustomPaint(
                          key: Key('stages-overlay-${_overlay!.name}'),
                          painter: _OverlayPainter(
                            curve: curve,
                            start: stages.start,
                            end: stages.end,
                            heartRate: _overlay == _Overlay.heartRate,
                          ),
                        ),
                    ],
                  ),
                ),
                if (gutter > 0)
                  SizedBox(
                    width: gutter,
                    child: curve == null
                        ? null
                        : _axisLabels(curve, _overlay == _Overlay.heartRate),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.only(right: gutter),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 右邊讓出刻度的空間之後可能放不下四個時間：放不下就縮小，不溢出
                for (final t in ticks)
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        fmt.format(t),
                        style: const TextStyle(
                          color: SonnapColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (hasChips) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.heartRate != null)
                  _chip('Heart rate', _Overlay.heartRate, 'stages-chip-hr'),
                if (widget.movement != null)
                  _chip('Movement', _Overlay.movement, 'stages-chip-move'),
              ],
            ),
            if (curve != null) ...[
              const SizedBox(height: 8),
              Text(
                _info(curve),
                key: const Key('stages-overlay-info'),
                style: const TextStyle(
                  color: SonnapColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              _legend('Awake', SleepStagesCard.awake, stages.awakeMinutes),
              _legend(
                'REM',
                SleepStagesCard.rem,
                stages.remMinutes,
                note: stages.remMeasured ? null : 'not measured',
              ),
              _legend('Light', SleepStagesCard.light, stages.lightMinutes),
              _legend('Deep', SleepStagesCard.deep, stages.deepMinutes),
            ],
          ),
        ],
      ),
    );
  }

  /// 選了那條線之後下面那一行：只寫事實。
  String _info(NightCurve c) {
    if (_overlay == _Overlay.movement) return 'Movement from your watch';
    return [
      '${c.avg.round()} bpm avg while asleep',
      'lowest ${c.min.round()}',
      if (widget.restingHeartRate != null)
        'resting ${widget.restingHeartRate!.round()}',
    ].join(' · ');
  }

  Widget _chip(String label, _Overlay o, String key) {
    final on = _overlay == o;
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        key: Key(key),
        onTap: () => _toggle(o),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: on ? Colors.white.withValues(alpha: 0.22) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: on ? Colors.white : Colors.white.withValues(alpha: 0.45),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: SonnapColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  /// 右邊的刻度：心率寫 bpm 數字；動作沒有單位，只寫 More／Less（不寫 High——會被讀成太高）。
  Widget _axisLabels(NightCurve c, bool heartRate) {
    final range = _OverlayPainter.rangeOf(c, heartRate);
    const style = TextStyle(color: SonnapColors.textSecondary, fontSize: 10);
    return Column(
      key: const Key('stages-overlay-axis'),
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(heartRate ? range.$2.round().toString() : 'More', style: style),
        Text(heartRate ? range.$1.round().toString() : 'Less', style: style),
      ],
    );
  }

  Widget _legend(String label, Color color, int? minutes, {String? note}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: SonnapColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 15),
            child: Text(
              note ?? (minutes == null ? '—' : _hm(minutes)),
              style: TextStyle(
                color: note == null
                    ? SonnapColors.textPrimary
                    : SonnapColors.textMuted,
                fontSize: note == null ? 13 : 11,
                fontWeight: note == null ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 沒有階段資料時（舊版後端、讀 API 的時候）的那張卡：老實講還沒有，不畫假的。
class SleepStagesUnavailableCard extends StatelessWidget {
  const SleepStagesUnavailableCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('sleep-stages-unavailable'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: sonnapCardDecoration(),
      child: const Row(
        children: [
          Icon(Icons.auto_awesome, color: SleepStagesCard.rem, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sleep Stages',
              style: TextStyle(
                color: SonnapColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            'Not available yet',
            style: TextStyle(color: SonnapColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _StagePainter extends CustomPainter {
  final SleepStages stages;
  final List<String> levels;

  /// 疊了心率／動作時，階梯變淡，讓上面那條線看得清楚。
  final bool dimmed;

  _StagePainter({
    required this.stages,
    required this.levels,
    this.dimmed = false,
  });

  static const _colors = {
    'awake': SleepStagesCard.awake,
    'rem': SleepStagesCard.rem,
    'light': SleepStagesCard.light,
    'deep': SleepStagesCard.deep,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final total = stages.end.difference(stages.start).inSeconds.toDouble();
    if (total <= 0) return;
    final rowH = size.height / levels.length;
    double yOf(String stage) {
      final i = levels.indexOf(stage);
      return rowH * (i < 0 ? levels.length - 1 : i) + rowH / 2;
    }

    double xOf(DateTime t) =>
        t.difference(stages.start).inSeconds / total * size.width;

    // 每一層一條很淡的水平線
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (final l in levels) {
      canvas.drawLine(Offset(0, yOf(l)), Offset(size.width, yOf(l)), grid);
    }

    // 圓角階梯：水平走到段尾，轉角用小圓弧接到下一段的高度。
    const r = 6.0;
    final path = Path();
    final segs = stages.segments
        .where((s) => levels.contains(s.stage))
        .toList();
    for (var i = 0; i < segs.length; i++) {
      final s = segs[i];
      final y = yOf(s.stage);
      final x0 = xOf(s.start);
      final x1 = xOf(s.end);
      if (i == 0) path.moveTo(x0, y);
      final next = i + 1 < segs.length ? segs[i + 1] : null;
      if (next == null) {
        path.lineTo(x1, y);
        break;
      }
      final ny = yOf(next.stage);
      if (ny == y) {
        path.lineTo(x1, y);
        continue;
      }
      final dir = ny > y ? 1.0 : -1.0;
      final rr = [
        r,
        (x1 - x0) / 2,
        (ny - y).abs() / 2,
      ].reduce((a, b) => a < b ? a : b);
      path.lineTo(x1 - rr, y);
      path.quadraticBezierTo(x1, y, x1, y + dir * rr);
      path.lineTo(x1, ny - dir * rr);
      final nx1 = xOf(next.end);
      final rr2 = [rr, (nx1 - x1) / 2].reduce((a, b) => a < b ? a : b);
      path.quadraticBezierTo(x1, ny, x1 + rr2, ny);
    }

    // 線的顏色由上（清醒，粉）到下（深睡，青）漸層，跟圖例同色。
    final alpha = dimmed ? 0.35 : 1.0;
    final shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        for (final l in levels) _colors[l]!.withValues(alpha: alpha),
      ],
    ).createShader(Offset.zero & size);

    // 光暈（疊線時不畫，免得搶走上面那條線）
    if (!dimmed) {
      canvas.drawPath(
        path,
        Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _StagePainter old) =>
      old.stages != stages ||
      old.levels.length != levels.length ||
      old.dimmed != dimmed;
}

/// 疊在階梯上的那條線（心率或手錶動作）。x 軸與階梯同一段時間（入睡 → 起床）。
class _OverlayPainter extends CustomPainter {
  final NightCurve curve;
  final DateTime start;
  final DateTime end;
  final bool heartRate;

  _OverlayPainter({
    required this.curve,
    required this.start,
    required this.end,
    required this.heartRate,
  });

  /// y 軸範圍（下, 上）。心率：實際最低最高各留一點空間取整到 5；動作：0 到最大值。
  static (double, double) rangeOf(NightCurve c, bool heartRate) {
    if (heartRate) {
      return (
        ((c.min - 3) / 5).floor() * 5.0,
        ((c.max + 3) / 5).ceil() * 5.0,
      );
    }
    return (0, c.max <= 0 ? 1 : c.max);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final total = end.difference(start).inSeconds.toDouble();
    if (total <= 0) return;
    final (lo, hi) = rangeOf(curve, heartRate);
    if (hi <= lo) return;
    const pad = 4.0;
    double x(DateTime t) =>
        (t.difference(start).inSeconds / total).clamp(0.0, 1.0) * size.width;
    double y(double v) => pad + (size.height - 2 * pad) * (1 - (v - lo) / (hi - lo));

    final pts = [
      for (final p in curve.points)
        if (!p.time.isBefore(start) && !p.time.isAfter(end)) p,
    ];
    if (pts.length < 2) return;
    final path = monotonePath(
      [for (final p in pts) x(p.time)],
      [for (final p in pts) y(p.value)],
    );

    if (heartRate) {
      // 睡著期間的平均：虛線（同下面那一行的平均）
      final avgY = y(curve.avg);
      final dash = Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..strokeWidth = 1;
      for (double dx = 0; dx < size.width; dx += 8) {
        canvas.drawLine(
            Offset(dx, avgY), Offset((dx + 4).clamp(0, size.width), avgY), dash);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) =>
      old.curve != curve || old.heartRate != heartRate;
}
