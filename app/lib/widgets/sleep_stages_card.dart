import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/sleep_stages.dart';
import '../theme/sonnap_colors.dart';

/// 首頁的 Sleep Stages 卡（2026-11-12 使用者定案，參考 LUNA 的版面）。
///
/// ⚠️ 曲線是**圓角的階梯**，不是平滑波浪：平滑曲線會穿過那一刻沒發生過的階段
///    （例如深睡直接醒來時會畫過淺睡那一層），等於畫出假的資料。
/// ⚠️ 那晚沒量到 REM（[SleepStages.remMeasured] 為 false）時不畫 REM 那一層，
///    圖例寫 not measured——畫成空的一層會讓人以為整晚沒有 REM。
/// ⚠️ 不放警語（2026-11-12 使用者決定）。圖例的分鐘數用手錶自己的總數。
class SleepStagesCard extends StatelessWidget {
  final SleepStages stages;
  final int? totalSleepMinutes;

  const SleepStagesCard({
    super.key,
    required this.stages,
    this.totalSleepMinutes,
  });

  static const awake = Color(0xFFFF8AD8);
  static const rem = Color(0xFFC9A7FF);
  static const light = Color(0xFF6FA8FF);
  static const deep = Color(0xFF4FE0E0);

  static String _hm(int m) {
    final h = m ~/ 60;
    final r = m % 60;
    if (h == 0) return '${r}m';
    return '${h}h ${r}m';
  }

  @override
  Widget build(BuildContext context) {
    final levels = ['awake', if (stages.remMeasured) 'rem', 'light', 'deep'];
    final fmt = DateFormat('h:mm a');
    final span = stages.end.difference(stages.start);
    final ticks = [
      for (var i = 0; i < 4; i++)
        stages.start.add(Duration(seconds: (span.inSeconds * i / 3).round())),
    ];

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
              const Icon(Icons.auto_awesome, color: rem, size: 20),
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
              if (totalSleepMinutes != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _hm(totalSleepMinutes!),
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
            child: CustomPaint(
              painter: _StagePainter(stages: stages, levels: levels),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final t in ticks)
                Text(
                  fmt.format(t),
                  style: const TextStyle(
                    color: SonnapColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _legend('Awake', awake, stages.awakeMinutes),
              _legend(
                'REM',
                rem,
                stages.remMinutes,
                note: stages.remMeasured ? null : 'not measured',
              ),
              _legend('Light', light, stages.lightMinutes),
              _legend('Deep', deep, stages.deepMinutes),
            ],
          ),
        ],
      ),
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

  _StagePainter({required this.stages, required this.levels});

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
    final shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [for (final l in levels) _colors[l]!],
    ).createShader(Offset.zero & size);

    // 光暈
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
      old.stages != stages || old.levels.length != levels.length;
}
