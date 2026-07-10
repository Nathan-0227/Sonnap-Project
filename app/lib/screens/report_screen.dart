import 'dart:math' as math;
import 'package:flutter/material.dart';

class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key});

  static const Color backgroundColor = Color(0xFF06142D);
  static const Color cardColor = Color(0xFF0A2142);
  static const Color secondaryCardColor = Color(0xFF0D274B);
  static const Color purpleColor = Color(0xFF7657FF);
  static const Color blueColor = Color(0xFF66C7FF);
  static const Color greenColor = Color(0xFF7ED957);
  static const Color yellowColor = Color(0xFFFFC83D);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 18),
              _buildPeriodSelector(),
              const SizedBox(height: 14),
              _buildSleepScoreCard(),
              const SizedBox(height: 14),
              _buildSleepTrendCard(),
              const SizedBox(height: 14),
              _buildWeeklyMoodCard(),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 650) {
                    return Column(
                      children: [
                        _buildDistractionsCard(),
                        const SizedBox(height: 14),
                        _buildTrackingSourcesCard(),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildDistractionsCard()),
                      const SizedBox(width: 14),
                      Expanded(child: _buildTrackingSourcesCard()),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Insights',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 29,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 6),
                  Text(
                    '✨',
                    style: TextStyle(fontSize: 18),
                  ),
                ],
              ),
              SizedBox(height: 5),
              Text(
                'Understand your sleep,\nhelp your pet feel better.',
                style: TextStyle(
                  color: Color(0xFFB9C8E2),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF10284A),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: const Center(
            child: Text(
              '🌙',
              style: TextStyle(fontSize: 27),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.calendar_month_rounded,
            color: purpleColor,
            size: 18,
          ),
          SizedBox(width: 8),
          Text(
            'This Week',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(width: 8),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFFB9C8E2),
            size: 18,
          ),
        ],
      ),
    );
  }

  Widget _buildSleepScoreCard() {
    return _insightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text(
                'Weekly Sleep Score',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(width: 6),
              Icon(
                Icons.info_outline_rounded,
                color: Color(0xFF8296B7),
                size: 16,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const SizedBox(
                width: 120,
                height: 120,
                child: CustomPaint(
                  painter: SleepScorePainter(score: 82),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '82',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 33,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '/100',
                          style: TextStyle(
                            color: purpleColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Text(
                          '🙂',
                          style: TextStyle(fontSize: 23),
                        ),
                        SizedBox(width: 7),
                        Text(
                          'Great!',
                          style: TextStyle(
                            color: greenColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "You're doing great!\nKeep maintaining your\ngood sleep routine.",
                      style: TextStyle(
                        color: Color(0xFFC1CEE2),
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '↑ 8 pts vs. last week',
                      style: TextStyle(
                        color: greenColor.withValues(alpha: 0.95),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSleepTrendCard() {
    return _insightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.show_chart_rounded,
                color: purpleColor,
                size: 21,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sleep Trend',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Daily average sleep duration',
                      style: TextStyle(
                        color: Color(0xFF8FA3C3),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1934),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Text(
                      '30 Days',
                      style: TextStyle(
                        color: Color(0xFFC6D3E8),
                        fontSize: 11,
                      ),
                    ),
                    SizedBox(width: 3),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFFC6D3E8),
                      size: 15,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const SizedBox(
            height: 165,
            width: double.infinity,
            child: CustomPaint(
              painter: SleepTrendPainter(),
            ),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(
                child: _SleepStat(
                  emoji: '🌙',
                  title: 'Avg. Sleep Duration',
                  value: '7h 12m',
                ),
              ),
              SizedBox(width: 7),
              Expanded(
                child: _SleepStat(
                  emoji: '🛏️',
                  title: 'Avg. Bedtime',
                  value: '23:26',
                ),
              ),
              SizedBox(width: 7),
              Expanded(
                child: _SleepStat(
                  emoji: '☀️',
                  title: 'Avg. Wake Time',
                  value: '06:52',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyMoodCard() {
    final moods = [
      const MoodData('Mon', '5/12', '🙂', 'Happy'),
      const MoodData('Tue', '5/13', '🙂', 'Happy'),
      const MoodData('Wed', '5/14', '😐', 'Normal'),
      const MoodData('Thu', '5/15', '😞', 'Tired'),
      const MoodData('Fri', '5/16', '🤒', 'Sick'),
      const MoodData('Sat', '5/17', '😞', 'Tired'),
      const MoodData('Sun', '5/18', '🙂', 'Happy'),
    ];

    return _insightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.pets_rounded,
                color: purpleColor,
                size: 19,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Weekly Pet Mood',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                'How it works?',
                style: TextStyle(
                  color: Color(0xFF9DB1D0),
                  fontSize: 11,
                ),
              ),
              SizedBox(width: 3),
              Icon(
                Icons.help_outline_rounded,
                color: Color(0xFF9DB1D0),
                size: 15,
              ),
              SizedBox(width: 3),
              Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF9DB1D0),
                size: 17,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: moods.map((mood) {
                return Container(
                  width: 52,
                  margin: const EdgeInsets.only(right: 7),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A1934),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Column(
                    children: [
                      Text(
                        mood.day,
                        style: const TextStyle(
                          color: Color(0xFFB2C0D8),
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        mood.date,
                        style: const TextStyle(
                          color: Color(0xFF7F93B4),
                          fontSize: 9,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        mood.emoji,
                        style: const TextStyle(fontSize: 25),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 13),
          const Wrap(
            alignment: WrapAlignment.center,
            spacing: 13,
            runSpacing: 7,
            children: [
              _MoodLegend(
                color: greenColor,
                label: 'Happy',
              ),
              _MoodLegend(
                color: yellowColor,
                label: 'Normal',
              ),
              _MoodLegend(
                color: Color(0xFFFF9518),
                label: 'Tired',
              ),
              _MoodLegend(
                color: Color(0xFFFF4F63),
                label: 'Sick',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDistractionsCard() {
    return _insightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.phone_iphone_rounded,
                color: purpleColor,
                size: 19,
              ),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Top Sleep Distractions',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                Icons.info_outline_rounded,
                color: Color(0xFF8296B7),
                size: 15,
              ),
            ],
          ),
          const SizedBox(height: 3),
          const Text(
            'Apps used in the hour before bedtime',
            style: TextStyle(
              color: Color(0xFF8498B7),
              fontSize: 9,
            ),
          ),
          const SizedBox(height: 15),
          const _DistractionRow(
            icon: '▶️',
            name: 'YouTube',
            minutes: '52 min',
            percentage: 0.90,
          ),
          const _DistractionRow(
            icon: '📸',
            name: 'Instagram',
            minutes: '38 min',
            percentage: 0.70,
          ),
          const _DistractionRow(
            icon: '🟥',
            name: 'Netflix',
            minutes: '24 min',
            percentage: 0.46,
          ),
          const _DistractionRow(
            icon: '🎵',
            name: 'TikTok',
            minutes: '19 min',
            percentage: 0.36,
          ),
          const SizedBox(height: 8),
          _viewButton('View All Apps'),
        ],
      ),
    );
  }

  Widget _buildTrackingSourcesCard() {
    return _insightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.shield_outlined,
                color: purpleColor,
                size: 19,
              ),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Sleep Tracking Sources',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          const Text(
            'Your sleep data comes from multiple sources',
            style: TextStyle(
              color: Color(0xFF8498B7),
              fontSize: 9,
            ),
          ),
          const SizedBox(height: 15),
          const _TrackingSourceRow(
            icon: Icons.watch_rounded,
            title: 'Garmin Watch',
            subtitle: 'Primary Source\nLast synced 22:45',
          ),
          const _TrackingSourceRow(
            icon: Icons.videocam_rounded,
            title: 'Camera Assist',
            subtitle: 'Supporting Source\nActive',
          ),
          const _TrackingSourceRow(
            icon: Icons.phone_iphone_rounded,
            title: 'Phone Activity',
            subtitle: 'Supporting Source\nLast updated 22:50',
          ),
          const SizedBox(height: 8),
          _viewButton('View All Data Sources'),
        ],
      ),
    );
  }

  Widget _viewButton(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF102B52),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFFB9C7FF),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.chevron_right_rounded,
            color: Color(0xFFB9C7FF),
            size: 16,
          ),
        ],
      ),
    );
  }

  Widget _insightCard({
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: const Color(0xFF12325A),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SleepStat extends StatelessWidget {
  final String emoji;
  final String title;
  final String value;

  const _SleepStat({
    required this.emoji,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 71),
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1934),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            emoji,
            style: const TextStyle(fontSize: 19),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8296B7),
                    fontSize: 8,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DistractionRow extends StatelessWidget {
  final String icon;
  final String name;
  final String minutes;
  final double percentage;

  const _DistractionRow({
    required this.icon,
    required this.name,
    required this.minutes,
    required this.percentage,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            icon,
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                minHeight: 5,
                value: percentage,
                backgroundColor: const Color(0xFF173050),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  ReportScreen.purpleColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 38,
            child: Text(
              minutes,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFFB7C4D9),
                fontSize: 9,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackingSourceRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _TrackingSourceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF112D50),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: const Color(0xFFB8C8E5),
              size: 21,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF8296B7),
                    fontSize: 8,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: ReportScreen.greenColor,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Color(0xFF09203A),
              size: 14,
            ),
          ),
          const SizedBox(width: 5),
          const Icon(
            Icons.chevron_right_rounded,
            color: Color(0xFF8498B7),
            size: 18,
          ),
        ],
      ),
    );
  }
}

class _MoodLegend extends StatelessWidget {
  final Color color;
  final String label;

  const _MoodLegend({
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFAFC0DB),
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}

class MoodData {
  final String day;
  final String date;
  final String emoji;
  final String mood;

  const MoodData(
    this.day,
    this.date,
    this.emoji,
    this.mood,
  );
}

class SleepScorePainter extends CustomPainter {
  final double score;

  const SleepScorePainter({
    required this.score,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 8;

    final backgroundPaint = Paint()
      ..color = const Color(0xFF173052)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, backgroundPaint);

    final rect = Rect.fromCircle(
      center: center,
      radius: radius,
    );

    final gradient = const SweepGradient(
      startAngle: -math.pi / 2,
      endAngle: math.pi * 1.5,
      colors: [
        Color(0xFF7657FF),
        Color(0xFF536DFF),
        Color(0xFF66C7FF),
      ],
    );

    final scorePaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    final sweepAngle = math.pi * 2 * (score / 100);

    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweepAngle,
      false,
      scorePaint,
    );

    final endAngle = -math.pi / 2 + sweepAngle;

    final endPoint = Offset(
      center.dx + radius * math.cos(endAngle),
      center.dy + radius * math.sin(endAngle),
    );

    canvas.drawCircle(
      endPoint,
      4.5,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant SleepScorePainter oldDelegate) {
    return oldDelegate.score != score;
  }
}

class SleepTrendPainter extends CustomPainter {
  const SleepTrendPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const leftPadding = 28.0;
    const rightPadding = 8.0;
    const topPadding = 8.0;
    const bottomPadding = 27.0;

    final graphWidth = size.width - leftPadding - rightPadding;
    final graphHeight = size.height - topPadding - bottomPadding;

    final gridPaint = Paint()
      ..color = const Color(0xFF29405F)
      ..strokeWidth = 0.8;

    for (int i = 0; i < 4; i++) {
      final y = topPadding + graphHeight * i / 3;

      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(size.width - rightPadding, y),
        gridPaint,
      );
    }

    final labels = ['9h', '8h', '7h', '5h'];

    for (int i = 0; i < labels.length; i++) {
      final y = topPadding + graphHeight * i / 3;

      _drawText(
        canvas,
        labels[i],
        Offset(0, y - 5),
        const TextStyle(
          color: Color(0xFF8296B7),
          fontSize: 9,
        ),
      );
    }

    final values = [
      0.30,
      0.38,
      0.35,
      0.54,
      0.67,
      0.49,
      0.41,
      0.47,
      0.52,
      0.61,
      0.70,
      0.75,
      0.83,
      0.80,
      0.69,
      0.56,
      0.49,
      0.64,
      0.78,
      0.71,
      0.66,
      0.79,
      0.91,
      0.86,
      0.78,
      0.70,
      0.61,
      0.59,
      0.60,
      0.53,
    ];

    final points = <Offset>[];

    for (int i = 0; i < values.length; i++) {
      final x = leftPadding + graphWidth * i / (values.length - 1);
      final y = topPadding + graphHeight * (1 - values[i]);

      points.add(Offset(x, y));
    }

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);

    for (int i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }

    final fillPath = Path.from(linePath)
      ..lineTo(points.last.dx, topPadding + graphHeight)
      ..lineTo(points.first.dx, topPadding + graphHeight)
      ..close();

    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x557657FF),
          Color(0x057657FF),
        ],
      ).createShader(
        Rect.fromLTWH(
          leftPadding,
          topPadding,
          graphWidth,
          graphHeight,
        ),
      );

    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = const Color(0xFF8067FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(linePath, linePaint);

    final pointPaint = Paint()
      ..color = const Color(0xFF8067FF);

    for (final point in points) {
      canvas.drawCircle(point, 2, pointPaint);
    }

    canvas.drawCircle(
      points.last,
      4,
      Paint()..color = const Color(0xFF72C8FF),
    );

    canvas.drawCircle(
      points.last,
      2.5,
      Paint()..color = Colors.white,
    );

    final xLabels = ['Apr 20', 'Apr 27', 'May 4', 'May 11', 'May 18'];

    for (int i = 0; i < xLabels.length; i++) {
      final x = leftPadding + graphWidth * i / (xLabels.length - 1);

      _drawText(
        canvas,
        xLabels[i],
        Offset(x - 14, size.height - 15),
        const TextStyle(
          color: Color(0xFF8296B7),
          fontSize: 8,
        ),
      );
    }

    final tooltipPosition = points[23];

    final tooltipRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        tooltipPosition.dx - 15,
        tooltipPosition.dy - 33,
        46,
        27,
      ),
      const Radius.circular(8),
    );

    canvas.drawRRect(
      tooltipRect,
      Paint()..color = const Color(0xFFBDAEFF),
    );

    _drawText(
      canvas,
      '7h 42m',
      Offset(
        tooltipPosition.dx - 7,
        tooltipPosition.dy - 28,
      ),
      const TextStyle(
        color: Color(0xFF1A1740),
        fontSize: 8,
        fontWeight: FontWeight.bold,
      ),
    );

    _drawText(
      canvas,
      'May 18',
      Offset(
        tooltipPosition.dx - 5,
        tooltipPosition.dy - 17,
      ),
      const TextStyle(
        color: Color(0xFF413A70),
        fontSize: 7,
      ),
    );
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset position,
    TextStyle style,
  ) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: style,
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(canvas, position);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}