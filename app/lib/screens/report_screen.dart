import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/sleep_session.dart';
import '../services/sleep_repository.dart';

class ReportScreen extends StatefulWidget {
  final SleepRepository repository;

  const ReportScreen({
    super.key,
    this.repository = const AssetSleepRepository(),
  });

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  // ============================================================
  // COLORS
  // ============================================================

  static const Color backgroundColor = Color(0xFF06142D);
  static const Color cardColor = Color(0xFF0A2142);
  static const Color purpleColor = Color(0xFF7657FF);
  static const Color blueColor = Color(0xFF66C7FF);
  static const Color greenColor = Color(0xFF7ED957);
  static const Color yellowColor = Color(0xFFFFC83D);

  // ============================================================
  // STATE
  // ============================================================

  late Future<SleepSession> _sessionFuture;

  int _selectedDays = 30;

  int? _selectedTrendIndex;

  static const List<int> _periodOptions = [
    1,
    7,
    14,
    21,
    30,
  ];

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();
    _sessionFuture = widget.repository.load();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: FutureBuilder<SleepSession>(
          future: _sessionFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState ==
                ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  color: purpleColor,
                ),
              );
            }

            if (snapshot.hasError ||
                !snapshot.hasData) {
              return const Center(
                child: Text(
                  'No sleep data yet',
                  style: TextStyle(
                    color: Colors.white,
                  ),
                ),
              );
            }

            final session = snapshot.data!;

            print('===== REPORT DEBUG =====');
print('finalScore: ${session.scoring.finalScore}');
print('scoreAsInt: ${session.scoring.scoreAsInt}');
print('finalQuality: ${session.scoring.finalQuality}');
print('history length: ${session.history.length}');
print('========================');

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                16,
                12,
                16,
                110,
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  _buildHeader(session),

                  const SizedBox(height: 14),

                  _buildSleepScoreCard(session),

                  const SizedBox(height: 14),

                  _buildSleepTrendCard(session),

                  const SizedBox(height: 14),

                  _buildWeeklyMoodCard(session),

                  const SizedBox(height: 14),

                  LayoutBuilder(
                    builder:
                        (context, constraints) {
                      if (constraints.maxWidth < 650) {
                        return Column(
                          children: [
                            _buildDistractionsCard(
                              session,
                            ),
                            const SizedBox(height: 14),
                            _buildTrackingSourcesCard(
                              session,
                            ),
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child:
                                _buildDistractionsCard(
                              session,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child:
                                _buildTrackingSourcesCard(
                              session,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader(SleepSession session) {
    final message =
        session.display.headerMessage.isNotEmpty
            ? session.display.headerMessage
            : 'Understand your sleep,\nhelp your pet feel better.';

    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              const Row(
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
                    style: TextStyle(
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                message,
                style: const TextStyle(
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
              color:
                  Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: const Center(
            child: Text(
              '🌙',
              style: TextStyle(
                fontSize: 27,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // SLEEP SCORE
  // ============================================================

  Widget _buildSleepScoreCard(
    SleepSession session,
  ) {
    final score = session.scoring.finalScore;
    final quality =
        session.scoring.finalQuality;

    final message =
        session.display.scoreMessage.isNotEmpty
            ? session.display.scoreMessage
            : 'No score message available.';

    final scoreColor =
        Color(session.display.colorValue);

    return _insightCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text(
                'Sleep Score',
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
              SizedBox(
                width: 120,
                height: 120,
                child: CustomPaint(
                  painter: SleepScorePainter(
                    score: score ?? 0,
                    color: scoreColor,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        Text(
                          score == null
                              ? '--'
                              : '${session.scoring.scoreAsInt}',
                          style:
                              const TextStyle(
                            color: Colors.white,
                            fontSize: 33,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                        const Text(
                          '/100',
                          style: TextStyle(
                            color: purpleColor,
                            fontSize: 13,
                            fontWeight:
                                FontWeight.w600,
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
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _qualityEmoji(quality),
                          style:
                              const TextStyle(
                            fontSize: 23,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            quality,
                            style: TextStyle(
                              color: scoreColor,
                              fontSize: 16,
                              fontWeight:
                                  FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    Text(
                      message,
                      style:
                          const TextStyle(
                        color:
                            Color(0xFFC1CEE2),
                        fontSize: 13,
                        height: 1.45,
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

  String _qualityEmoji(
    String quality,
  ) {
    switch (quality.toLowerCase()) {
      case 'good':
        return '🙂';
      case 'normal':
        return '😐';
      case 'poor':
        return '😞';
      case 'bad':
        return '😣';
      default:
        return '😴';
    }
  }

  // ============================================================
  // SLEEP TREND CARD
  // ============================================================

  Widget _buildSleepTrendCard(
    SleepSession session,
  ) {
    final filteredHistory =
        _getFilteredHistory(
      session.history,
    );

    final validHistory =
        filteredHistory
            .where(
              (entry) =>
                  entry.sleepDurationHours !=
                  null,
            )
            .toList();

    // Reset selection when the selected period
    // changes and the old index no longer exists.
    if (_selectedTrendIndex != null &&
        _selectedTrendIndex! >=
            validHistory.length) {
      _selectedTrendIndex = null;
    }

    return _insightCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          // ------------------------------------------------------
          // HEADER
          // ------------------------------------------------------

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
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sleep Trend',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight:
                            FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Daily average sleep duration',
                      style: TextStyle(
                        color:
                            Color(0xFF8FA3C3),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),

              _buildPeriodDropdown(),
            ],
          ),

          const SizedBox(height: 16),

          // ------------------------------------------------------
          // SELECTED POINT INFORMATION
          // ------------------------------------------------------

          if (_selectedTrendIndex != null &&
              _selectedTrendIndex! >= 0 &&
              _selectedTrendIndex! <
                  validHistory.length)
            _buildSelectedTrendInfo(
              validHistory[
                  _selectedTrendIndex!],
            ),

          // ------------------------------------------------------
          // GRAPH
          // ------------------------------------------------------

          GestureDetector(
            behavior:
                HitTestBehavior.opaque,
            onTapDown: (details) {
              if (validHistory.isEmpty) {
                return;
              }

              _selectTrendPoint(
                details.localPosition,
                validHistory.length,
              );
            },
            child: SizedBox(
              height: 165,
              width: double.infinity,
              child: CustomPaint(
                painter: SleepTrendPainter(
                  history: validHistory,
                  selectedIndex:
                      _selectedTrendIndex,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ------------------------------------------------------
          // STATS
          // ------------------------------------------------------

          _buildSleepStats(
            validHistory,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SELECT GRAPH POINT
  // ============================================================

  void _selectTrendPoint(
    Offset tapPosition,
    int pointCount,
  ) {
    if (pointCount == 0) {
      return;
    }

    const leftPadding = 28.0;
    const rightPadding = 8.0;

    final renderBox =
        context.findRenderObject()
            as RenderBox?;

    if (renderBox == null) {
      return;
    }

    final graphContainerWidth =
        renderBox.size.width - 32;

    final graphWidth =
        graphContainerWidth -
        leftPadding -
        rightPadding;

    if (graphWidth <= 0) {
      return;
    }

    final x =
        tapPosition.dx - leftPadding;

    final clampedX =
        x.clamp(0.0, graphWidth);

    int selectedIndex;

    if (pointCount == 1) {
      selectedIndex = 0;
    } else {
      final ratio =
          clampedX / graphWidth;

      selectedIndex =
          (ratio * (pointCount - 1))
              .round();

      selectedIndex =
          selectedIndex.clamp(
        0,
        pointCount - 1,
      );
    }

    setState(() {
      _selectedTrendIndex =
          selectedIndex;
    });
  }

  // ============================================================
  // SELECTED TREND INFO
  // ============================================================

  Widget _buildSelectedTrendInfo(
    HistoryEntry entry,
  ) {
    final duration =
        entry.sleepDurationHours;

    if (duration == null) {
      return const SizedBox.shrink();
    }

    final hours = duration.floor();

    final minutes =
        ((duration - hours) * 60)
            .round();

    final durationText =
        '${hours}h ${minutes}m';

    return Container(
      width: double.infinity,
      margin:
          const EdgeInsets.only(bottom: 12),
      padding:
          const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF101F3B),
        borderRadius:
            BorderRadius.circular(11),
        border: Border.all(
          color: purpleColor
              .withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.nights_stay_rounded,
            color: purpleColor,
            size: 18,
          ),

          const SizedBox(width: 8),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  _formatTrendDate(
                    entry.date,
                  ),
                  style:
                      const TextStyle(
                    color:
                        Color(0xFF8296B7),
                    fontSize: 9,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  durationText,
                  style:
                      const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight:
                        FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          if (entry.finalQuality != null)
            Text(
              entry.finalQuality!,
              style: const TextStyle(
                color: Color(0xFFB9C8E2),
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
  }

  String _formatTrendDate(
    String date,
  ) {
    final parsed =
        DateTime.tryParse(date);

    if (parsed == null) {
      return date;
    }

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

    return '${months[parsed.month - 1]} '
        '${parsed.day}, '
        '${parsed.year}';
  }

  // ============================================================
  // SLEEP STATS
  // ============================================================

  Widget _buildSleepStats(
    List<HistoryEntry> history,
  ) {
    return Row(
      children: [
        Expanded(
          child: _SleepStat(
            emoji: '🌙',
            title: 'Avg. Sleep Duration',
            value:
                _averageSleepDuration(
              history,
            ),
          ),
        ),

        const SizedBox(width: 7),

        Expanded(
          child: _SleepStat(
            emoji: '🛏️',
            title: 'Most Common Bedtime',
            value: _mostCommonTime(
              history
                  .map(
                    (entry) => entry.bedtime,
                  )
                  .toList(),
            ),
          ),
        ),

        const SizedBox(width: 7),

        Expanded(
          child: _SleepStat(
            emoji: '☀️',
            title: 'Most Common Wake Time',
            value: _mostCommonTime(
              history
                  .map(
                    (entry) => entry.wakeTime,
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  String _averageSleepDuration(
    List<HistoryEntry> history,
  ) {
    final values = history
        .map(
          (entry) =>
              entry.sleepDurationHours,
        )
        .whereType<double>()
        .toList();

    if (values.isEmpty) {
      return '--';
    }

    final average =
        values.reduce(
              (a, b) => a + b,
            ) /
            values.length;

    final hours =
        average.floor();

    final minutes =
        ((average - hours) * 60)
            .round();

    return '${hours}h ${minutes}m';
  }

  String _mostCommonTime(List<String?> times) {
  final validTimes = times
      .whereType<String>()
      .map(_timeToMinutes)
      .whereType<int>()
      .toList();

  if (validTimes.isEmpty) {
    return '--';
  }

  // Count how many times each minute appears.
  final frequency = <int, int>{};

  for (final minutes in validTimes) {
    frequency[minutes] =
        (frequency[minutes] ?? 0) + 1;
  }

  // Find the time that appears most often.
  int mostCommonMinutes = validTimes.first;
  int highestCount = 0;

  for (final entry in frequency.entries) {
    if (entry.value > highestCount) {
      highestCount = entry.value;
      mostCommonMinutes = entry.key;
    }
  }

  final hour = mostCommonMinutes ~/ 60;
  final minute = mostCommonMinutes % 60;

  return '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}';
}

  int? _timeToMinutes(String value) {
  // Handle ISO timestamp:
  // 2026-08-09T01:44:00+08:00
  final parsed = DateTime.tryParse(value);

  if (parsed != null) {
    return parsed.hour * 60 + parsed.minute;
  }

  // Handle simple time:
  // 01:44
  final parts = value.split(':');

  if (parts.length < 2) {
    return null;
  }

  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);

  if (hour == null || minute == null) {
    return null;
  }

  if (hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return null;
  }

  return hour * 60 + minute;
}

  // ============================================================
  // PET MOOD / HISTORY
  // ============================================================

  Widget _buildWeeklyMoodCard(
    SleepSession session,
  ) {
    final history =
        session.history;

    return _insightCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
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
                  'Sleep Quality History',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight:
                        FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (history.isEmpty)
            const _NoDataMessage(
              message:
                  'No history data available.',
            )
          else
            SingleChildScrollView(
              scrollDirection:
                  Axis.horizontal,
              child: Row(
                children:
                    history.map(
                  (entry) {
                    return _HistoryQualityItem(
                      entry: entry,
                    );
                  },
                ).toList(),
              ),
            ),

          const SizedBox(height: 13),

          Text(
            session.streak.definition
                    .isNotEmpty
                ? session.streak.definition
                : 'Sleep history is based on recorded sleep sessions.',
            style:
                const TextStyle(
              color:
                  Color(0xFF8296B7),
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DISTRACTIONS
  // ============================================================

  Widget _buildDistractionsCard(
    SleepSession session,
  ) {
    return _insightCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
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
                    fontWeight:
                        FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                Icons.info_outline_rounded,
                color:
                    Color(0xFF8296B7),
                size: 15,
              ),
            ],
          ),

          const SizedBox(height: 12),

          const _NoDataMessage(
            message:
                'No phone activity data is available in this sleep session.',
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TRACKING SOURCES
  // ============================================================

  Widget _buildTrackingSourcesCard(
    SleepSession session,
  ) {
    final sources =
        session.dataSources;

    return _insightCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
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
                    fontWeight:
                        FontWeight.w700,
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

          if (sources.isEmpty)
            const _NoDataMessage(
              message:
                  'No tracking sources available.',
            )
          else
            ...sources.map(
              (source) =>
                  _TrackingSourceRow(
                icon:
                    _sourceIcon(source),
                title: source,
                subtitle:
                    'Data source',
              ),
            ),
        ],
      ),
    );
  }

  IconData _sourceIcon(
    String source,
  ) {
    final lower =
        source.toLowerCase();

    if (lower.contains('garmin') ||
        lower.contains('watch')) {
      return Icons.watch_rounded;
    }

    if (lower.contains('camera')) {
      return Icons.videocam_rounded;
    }

    if (lower.contains('phone')) {
      return Icons.phone_iphone_rounded;
    }

    return Icons.data_usage_rounded;
  }

  // ============================================================
  // PERIOD DROPDOWN
  // ============================================================

  Widget _buildPeriodDropdown() {
    return PopupMenuButton<int>(
      initialValue: _selectedDays,

      onSelected: (days) {
        setState(() {
          _selectedDays = days;
          _selectedTrendIndex = null;
        });
      },

      color:
          const Color(0xFF10284A),

      shape:
          RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(12),
      ),

      itemBuilder: (context) {
        return _periodOptions.map(
          (days) {
            return PopupMenuItem<int>(
              value: days,
              child: Row(
                children: [
                  if (_selectedDays ==
                      days)
                    const Icon(
                      Icons.check_rounded,
                      color:
                          purpleColor,
                      size: 16,
                    )
                  else
                    const SizedBox(
                      width: 16,
                    ),

                  const SizedBox(
                    width: 6,
                  ),

                  Text(
                    '$days '
                    '${days == 1 ? 'Day' : 'Days'}',
                    style:
                        const TextStyle(
                      color:
                          Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          },
        ).toList();
      },

      child: Container(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 11,
          vertical: 7,
        ),
        decoration:
            BoxDecoration(
          color:
              const Color(0xFF0A1934),
          borderRadius:
              BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Text(
              '$_selectedDays '
              '${_selectedDays == 1 ? 'Day' : 'Days'}',
              style:
                  const TextStyle(
                color:
                    Color(0xFFC6D3E8),
                fontSize: 11,
              ),
            ),
            const SizedBox(
              width: 3,
            ),
            const Icon(
              Icons
                  .keyboard_arrow_down_rounded,
              color:
                  Color(0xFFC6D3E8),
              size: 15,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // FILTER HISTORY
  // ============================================================

  List<HistoryEntry>
      _getFilteredHistory(
    List<HistoryEntry> history,
  ) {
    if (history.isEmpty) {
      return [];
    }

    final sortedHistory =
        List<HistoryEntry>.from(
      history,
    );

    sortedHistory.sort(
      (a, b) =>
          a.date.compareTo(b.date),
    );

    if (_selectedDays == 1) {
      return [
        sortedHistory.last,
      ];
    }

    final latestDate =
        DateTime.tryParse(
      sortedHistory.last.date,
    );

    if (latestDate == null) {
      return sortedHistory.length <=
              _selectedDays
          ? sortedHistory
          : sortedHistory.sublist(
              sortedHistory.length -
                  _selectedDays,
            );
    }

    final startDate =
        latestDate.subtract(
      Duration(
        days: _selectedDays - 1,
      ),
    );

    return sortedHistory
        .where(
          (entry) {
            final date =
                DateTime.tryParse(
              entry.date,
            );

            if (date == null) {
              return false;
            }

            return !date.isBefore(
                  startDate,
                ) &&
                !date.isAfter(
                  latestDate,
                );
          },
        )
        .toList();
  }

  // ============================================================
  // CARD
  // ============================================================

  Widget _insightCard({
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(15),
      decoration:
          BoxDecoration(
        color: cardColor,
        borderRadius:
            BorderRadius.circular(17),
        border: Border.all(
          color:
              const Color(0xFF12325A),
        ),
        boxShadow: [
          BoxShadow(
            color:
                Colors.black.withValues(
              alpha: 0.12,
            ),
            blurRadius: 12,
            offset:
                const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ================================================================
// SLEEP STAT
// ================================================================

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
  Widget build(
    BuildContext context,
  ) {
    return Container(
      constraints:
          const BoxConstraints(
        minHeight: 71,
      ),
      padding:
          const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 9,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(0xFF0A1934),
        borderRadius:
            BorderRadius.circular(11),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            emoji,
            style:
                const TextStyle(
              fontSize: 19,
            ),
          ),

          const SizedBox(width: 6),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow:
                      TextOverflow.ellipsis,
                  style:
                      const TextStyle(
                    color:
                        Color(0xFF8296B7),
                    fontSize: 8,
                    height: 1.25,
                  ),
                ),

                const SizedBox(
                  height: 4,
                ),

                Text(
                  value,
                  style:
                      const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight:
                        FontWeight.w700,
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

// ================================================================
// HISTORY QUALITY ITEM
// ================================================================

class _HistoryQualityItem
    extends StatelessWidget {
  final HistoryEntry entry;

  const _HistoryQualityItem({
    required this.entry,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final quality =
        entry.finalQuality ??
            'Unknown';

    return Container(
      width: 65,
      margin:
          const EdgeInsets.only(
        right: 7,
      ),
      padding:
          const EdgeInsets.symmetric(
        horizontal: 5,
        vertical: 9,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(0xFF0A1934),
        borderRadius:
            BorderRadius.circular(13),
      ),
      child: Column(
        children: [
          Text(
            _formatDate(
              entry.date,
            ),
            style:
                const TextStyle(
              color:
                  Color(0xFFB2C0D8),
              fontSize: 9,
            ),
            textAlign:
                TextAlign.center,
          ),

          const SizedBox(
            height: 8,
          ),

          Text(
            _qualityEmoji(
              quality,
            ),
            style:
                const TextStyle(
              fontSize: 25,
            ),
          ),

          const SizedBox(
            height: 5,
          ),

          Text(
            quality,
            style:
                const TextStyle(
              color:
                  Color(0xFF8296B7),
              fontSize: 8,
            ),
            textAlign:
                TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _qualityEmoji(
    String quality,
  ) {
    switch (quality.toLowerCase()) {
      case 'good':
        return '🙂';
      case 'normal':
        return '😐';
      case 'poor':
        return '😞';
      case 'bad':
        return '😣';
      default:
        return '😴';
    }
  }

  String _formatDate(
    String date,
  ) {
    final parsed =
        DateTime.tryParse(date);

    if (parsed == null) {
      return date;
    }

    return '${parsed.month}/${parsed.day}';
  }
}

// ================================================================
// NO DATA MESSAGE
// ================================================================

class _NoDataMessage
    extends StatelessWidget {
  final String message;

  const _NoDataMessage({
    required this.message,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(12),
      decoration:
          BoxDecoration(
        color:
            const Color(0xFF0A1934),
        borderRadius:
            BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style:
            const TextStyle(
          color:
              Color(0xFF8296B7),
          fontSize: 10,
          height: 1.4,
        ),
      ),
    );
  }
}

// ================================================================
// TRACKING SOURCE ROW
// ================================================================

class _TrackingSourceRow
    extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _TrackingSourceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 13,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration:
                BoxDecoration(
              color:
                  const Color(0xFF112D50),
              borderRadius:
                  BorderRadius.circular(
                10,
              ),
            ),
            child: Icon(
              icon,
              color:
                  const Color(0xFFB8C8E5),
              size: 21,
            ),
          ),

          const SizedBox(
            width: 9,
          ),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style:
                      const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
                const SizedBox(
                  height: 2,
                ),
                Text(
                  subtitle,
                  style:
                      const TextStyle(
                    color:
                        Color(0xFF8296B7),
                    fontSize: 8,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),

          const Icon(
            Icons.check_circle_rounded,
            color:
                Color(0xFF7ED957),
            size: 20,
          ),
        ],
      ),
    );
  }
}

// ================================================================
// SLEEP SCORE PAINTER
// ================================================================

class SleepScorePainter
    extends CustomPainter {
  final double score;
  final Color color;

  const SleepScorePainter({
    required this.score,
    required this.color,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final center =
        size.center(Offset.zero);

    final radius =
        math.min(
              size.width,
              size.height,
            ) /
            2 -
            8;

    final backgroundPaint =
        Paint()
          ..color =
              const Color(0xFF173052)
          ..style =
              PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap =
              StrokeCap.round;

    canvas.drawCircle(
      center,
      radius,
      backgroundPaint,
    );

    final rect =
        Rect.fromCircle(
      center: center,
      radius: radius,
    );

    final scorePaint =
        Paint()
          ..color = color
          ..style =
              PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap =
              StrokeCap.round;

    final normalizedScore =
        score.clamp(
      0.0,
      100.0,
    );

    final sweepAngle =
        math.pi *
            2 *
            (normalizedScore / 100);

    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweepAngle,
      false,
      scorePaint,
    );

    if (normalizedScore > 0) {
      final endAngle =
          -math.pi / 2 +
              sweepAngle;

      final endPoint =
          Offset(
        center.dx +
            radius *
                math.cos(
                  endAngle,
                ),
        center.dy +
            radius *
                math.sin(
                  endAngle,
                ),
      );

      canvas.drawCircle(
        endPoint,
        4.5,
        Paint()
          ..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant SleepScorePainter
        oldDelegate,
  ) {
    return oldDelegate.score !=
            score ||
        oldDelegate.color != color;
  }
}

// ================================================================
// SLEEP TREND PAINTER
// ================================================================

class SleepTrendPainter
    extends CustomPainter {
  final List<HistoryEntry> history;
  final int? selectedIndex;

  const SleepTrendPainter({
    required this.history,
    this.selectedIndex,
  });

  static const double leftPadding =
      28.0;

  static const double rightPadding =
      8.0;

  static const double topPadding =
      8.0;

  static const double bottomPadding =
      27.0;

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final graphWidth =
        size.width -
            leftPadding -
            rightPadding;

    final graphHeight =
        size.height -
            topPadding -
            bottomPadding;

    // ==========================================================
    // GRID
    // ==========================================================

    final gridPaint = Paint()
      ..color =
          const Color(0xFF29405F)
      ..strokeWidth = 0.8;

    for (int i = 0; i < 4; i++) {
      final y =
          topPadding +
              graphHeight *
                  i /
                  3;

      canvas.drawLine(
        Offset(
          leftPadding,
          y,
        ),
        Offset(
          size.width -
              rightPadding,
          y,
        ),
        gridPaint,
      );
    }

    // ==========================================================
    // Y AXIS
    // ==========================================================

    const labels = [
      '9h',
      '8h',
      '7h',
      '5h',
    ];

    for (int i = 0;
        i < labels.length;
        i++) {
      final y =
          topPadding +
              graphHeight *
                  i /
                  3;

      _drawText(
        canvas,
        labels[i],
        Offset(
          0,
          y - 5,
        ),
        const TextStyle(
          color:
              Color(0xFF8296B7),
          fontSize: 9,
        ),
      );
    }

    // ==========================================================
    // VALID DATA
    // ==========================================================

    final validHistory =
        history
            .where(
              (entry) =>
                  entry
                      .sleepDurationHours !=
                  null,
            )
            .toList();

    if (validHistory.isEmpty) {
      _drawText(
        canvas,
        'No sleep data',
        Offset(
          leftPadding + 20,
          size.height / 2 - 5,
        ),
        const TextStyle(
          color:
              Color(0xFF8296B7),
          fontSize: 11,
        ),
      );

      return;
    }

    final values =
        validHistory
            .map(
              (entry) =>
                  entry
                      .sleepDurationHours!,
            )
            .toList();

    // ==========================================================
    // POINTS
    // ==========================================================

    final points =
        <Offset>[];

    for (int i = 0;
        i < values.length;
        i++) {
      final x =
          values.length == 1
              ? leftPadding +
                  graphWidth / 2
              : leftPadding +
                  graphWidth *
                      i /
                      (values.length -
                          1);

      const minHours = 5.0;
      const maxHours = 9.0;

      final normalized =
          ((values[i] -
                      minHours) /
                  (maxHours -
                      minHours))
              .clamp(
            0.0,
            1.0,
          );

      final y =
          topPadding +
              graphHeight *
                  (1 -
                      normalized);

      points.add(
        Offset(
          x,
          y,
        ),
      );
    }

    // ==========================================================
    // LINE
    // ==========================================================

    final linePath =
        Path()
          ..moveTo(
            points.first.dx,
            points.first.dy,
          );

    for (int i = 1;
        i < points.length;
        i++) {
      linePath.lineTo(
        points[i].dx,
        points[i].dy,
      );
    }

    // ==========================================================
    // AREA
    // ==========================================================

    final fillPath =
        Path.from(
      linePath,
    )
          ..lineTo(
            points.last.dx,
            topPadding +
                graphHeight,
          )
          ..lineTo(
            points.first.dx,
            topPadding +
                graphHeight,
          )
          ..close();

    final fillPaint =
        Paint()
          ..shader =
              const LinearGradient(
            begin:
                Alignment.topCenter,
            end:
                Alignment.bottomCenter,
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

    canvas.drawPath(
      fillPath,
      fillPaint,
    );

    // ==========================================================
    // LINE
    // ==========================================================

    final linePaint =
        Paint()
          ..color =
              const Color(0xFF8067FF)
          ..style =
              PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap =
              StrokeCap.round
          ..strokeJoin =
              StrokeJoin.round;

    canvas.drawPath(
      linePath,
      linePaint,
    );

    // ==========================================================
    // DATA POINTS
    // ==========================================================

    final pointPaint =
        Paint()
          ..color =
              const Color(0xFF8067FF);

    for (final point in points) {
      canvas.drawCircle(
        point,
        2.5,
        pointPaint,
      );
    }

    // ==========================================================
    // SELECTED POINT
    // ==========================================================

    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! <
            points.length) {
      final selectedPoint =
          points[selectedIndex!];

      final guidePaint =
          Paint()
            ..color =
                const Color(
              0xFF657A9E,
            ).withValues(
              alpha: 0.45,
            )
            ..strokeWidth = 1;

      canvas.drawLine(
        Offset(
          selectedPoint.dx,
          topPadding,
        ),
        Offset(
          selectedPoint.dx,
          topPadding +
              graphHeight,
        ),
        guidePaint,
      );

      canvas.drawCircle(
        selectedPoint,
        7,
        Paint()
          ..color =
              const Color(
            0xFF72C8FF,
          ).withValues(
            alpha: 0.25,
          ),
      );

      canvas.drawCircle(
        selectedPoint,
        4,
        Paint()
          ..color =
              const Color(
            0xFF72C8FF,
          ),
      );

      canvas.drawCircle(
        selectedPoint,
        2,
        Paint()
          ..color =
              Colors.white,
      );
    }

    // ==========================================================
    // X AXIS
    // ==========================================================

    final labelCount =
        math.min(
      5,
      validHistory.length,
    );

    for (int i = 0;
        i < labelCount;
        i++) {
      final index =
          validHistory.length == 1
              ? 0
              : ((validHistory.length -
                              1) *
                          i /
                          (labelCount -
                              1))
                      .round();

      final x =
          validHistory.length == 1
              ? leftPadding +
                  graphWidth / 2
              : leftPadding +
                  graphWidth *
                      index /
                      (validHistory.length -
                          1);

      _drawText(
        canvas,
        _formatDate(
          validHistory[index]
              .date,
        ),
        Offset(
          x - 14,
          size.height - 15,
        ),
        const TextStyle(
          color:
              Color(0xFF8296B7),
          fontSize: 8,
        ),
      );
    }
  }

  String _formatDate(
    String date,
  ) {
    if (date.isEmpty) {
      return '--';
    }

    final parsed =
        DateTime.tryParse(date);

    if (parsed == null) {
      return date;
    }

    return '${parsed.month}/${parsed.day}';
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset position,
    TextStyle style,
  ) {
    final textPainter =
        TextPainter(
      text: TextSpan(
        text: text,
        style: style,
      ),
      textDirection:
          TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      position,
    );
  }

  @override
  bool shouldRepaint(
    covariant SleepTrendPainter
        oldDelegate,
  ) {
    return oldDelegate.history !=
            history ||
        oldDelegate.selectedIndex !=
            selectedIndex;
  }
}