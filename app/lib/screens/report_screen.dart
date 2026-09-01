import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../models/sleep_session.dart';
import '../models/wall_clock.dart';
import '../services/sleep_repository.dart';
import '../services/usage_stats.dart';
import '../widgets/pet_mood_animation.dart';

class ReportScreen extends StatefulWidget {
  final SleepRepository repository;

  /// 手機使用時間的來源。可以注入，測試才不必依賴真的原生 channel。
  final UsageStatsService usageStats;

  const ReportScreen({
    super.key,
    this.usageStats = const UsageStatsService(),
    this.repository = const AssetSleepRepository(),
  });

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen>
    with WidgetsBindingObserver {
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

  /// 趨勢圖可選的期間。**0 代表「全部」**。
  ///
  /// ⚠️ 沒有「全部」這個選項時，payload 裡有 30 晚、卻只有最近 30 個**日曆天**
  /// 之內的看得到——實測那是 12 晚，另外 18 晚在 App 裡永遠打不開。
  /// 而 `anxious` 的四晚全部落在那 18 晚裡，所以那個心情根本無法被看見。
  ///
  /// 這是「資料在 payload 裡但使用者到不了」的缺口，不只是 demo 不方便。
  static const List<int> _periodOptions = [
    1,
    7,
    14,
    21,
    30,
    0,
  ];

  /// 0 是「全部」的哨兵值，不要印成「0 Days」。
  static String _periodLabel(int days) {
    if (days == 0) return 'All nights';
    return '$days ${days == 1 ? 'Day' : 'Days'}';
  }

  // ============================================================
  // INIT
  // ============================================================

  /// 手機使用時間。與睡眠資料完全獨立——它可能失敗（沒授權、非 Android），
  /// 但那不該影響整頁的其他區塊，所以不併進 `_sessionFuture`。
  UsageStatsResult? _usage;

  @override
  void initState() {
    super.initState();
    // 監聽 App 回到前景。理由見 didChangeAppLifecycleState。
    WidgetsBinding.instance.addObserver(this);
    _sessionFuture = widget.repository.load();
    _loadUsage();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// App 回到前景時重新查一次手機使用時間。
  ///
  /// ⚠️ **這一段是必要的，不是最佳化。** 授權「使用情況存取」一定要跳出 App
  /// 到系統設定頁，而 `openSettings()` 送出 intent 之後**立刻返回**——它不會
  /// 等使用者操作完，也拿不到使用者按了什麼。
  ///
  /// 第一版就是在 `openSettings()` 之後直接重查，結果實機上授權完回到 App，
  /// 卡片還是顯示「需要權限」——因為那次重查發生在使用者還沒點下去的時候。
  /// 單元測試看不出這個問題（測試裡沒有「離開 App 再回來」這件事），
  /// 是插上手機實際跑一遍才發現的。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _loadUsage();
    }
  }

  Future<void> _loadUsage() async {
    final result = await widget.usageStats.queryYesterday();
    if (!mounted) return;
    setState(() => _usage = result);
  }

  /// 只負責把使用者帶到系統設定頁。**重查交給 [didChangeAppLifecycleState]**。
  Future<void> _requestUsageAccess() => widget.usageStats.openSettings();

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

            // ⚠️ 這裡原本有一組 print()。它們在 build() 裡面，所以**每次重繪
            // 都會印一次**——捲動、切分頁、改期間都會觸發，logcat 會被洗掉。
            // 資料載入的摘要現在由 sleep_repository.dart 印一行就好。

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

  /// 選到趨勢圖上某一晚時顯示的資訊條。
  ///
  /// ## 為什麼這裡要放寵物
  ///
  /// 首頁只顯示**最新一晚**的心情，所以四種心情裡使用者一次只看得到一種。
  /// 把寵物放進這條資訊，點趨勢圖上任何一晚就能看到那一晚的寵物——
  /// 「睡得好不好 → 寵物的狀態」這個對應關係因此變得可以直接感受，
  /// 而不只是首頁上一個靜態的結果。
  ///
  /// ⚠️ **心情來自 payload 的 `history[].pet_mood`，不是在這裡從
  /// `final_quality` 推出來的。** `anxious` 是 Tier3 生理修正值的覆寫，
  /// 那些欄位不在 history 裡；照品質推會把 anxious 的夜晚畫成 happy。
  /// 詳見 `HistoryEntry.petMood` 的說明。
  Widget _buildSelectedTrendInfo(
    HistoryEntry entry,
  ) {
    final duration = entry.sleepDurationHours;
    final durationText = duration == null
        ? null
        : '${duration.floor()}h '
            '${((duration - duration.floor()) * 60).round()}m';

    final mood = entry.petMood;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF101F3B),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: purpleColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          if (mood != null)
            _HistoryPet(mood: mood)
          else
            const Icon(
              Icons.nights_stay_rounded,
              color: purpleColor,
              size: 18,
            ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatTrendDate(entry.date),
                  style: const TextStyle(
                    color: Color(0xFF8296B7),
                    fontSize: 9,
                  ),
                ),
                const SizedBox(height: 2),
                if (durationText != null)
                  Text(
                    durationText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (mood != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Your buddy was ${_moodLabel(mood)}',
                    style: TextStyle(
                      color: _moodColor(mood),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  // 心情要能追溯到依據。這一行是後端算心情時記下的規則，
                  // 不是這裡編出來的說法——與評分系統「數字要能講出理由」
                  // 是同一個要求。
                  if (entry.moodReason != null)
                    Text(
                      entry.moodReason!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF6C7FA0),
                        fontSize: 8.5,
                      ),
                    ),
                ],
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

  /// 只是查表把後端給的字串轉成顯示用的樣子，不做任何判斷。
  static String _moodLabel(String mood) =>
      mood.isEmpty ? 'Unknown' : mood[0].toUpperCase() + mood.substring(1);

  /// 與 `home_screen.dart` 的 `_moodColor()` 同一組顏色。
  static Color _moodColor(String mood) {
    switch (mood) {
      case 'happy':
        return const Color(0xFF7ED957);
      case 'bored':
        return const Color(0xFFFFC83D);
      case 'tired':
        return const Color(0xFFFF9518);
      case 'anxious':
        return const Color(0xFFFF4F63);
      default:
        return const Color(0xFFFFC83D);
    }
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
  //
  // ⚠️ 用 parseWallClock 不是 DateTime.tryParse。tryParse 會把帶偏移量的
  //    字串轉成 UTC，`.hour` 讀出來會早 8 小時——圖表上每一晚的就寢時間
  //    都會畫錯位置。理由與作法見 models/wall_clock.dart。
  final parsed = parseWallClock(value);

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

  /// 手機使用時間。
  ///
  /// ⚠️ **標題刻意不寫「Sleep Distractions」。** 原生端用的是
  /// `queryUsageStats(INTERVAL_DAILY)`，拿到的是**整天的前景總時間**，
  /// 不是睡前那一小時——日彙總沒有時間軸，切不出來。把整天的數字放在
  /// 「睡前分心」的標題底下，就是拿一個量去冒充另一個量。
  ///
  /// 要真的做到睡前歸因得改用 `queryEvents()` 讀逐筆事件（那同時也是
  /// `lights_out_at` 的來源）。在那之前，這張卡誠實地講它是什麼。
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
                  'Phone Use Yesterday',
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
            'Daily totals. Not yet narrowed to the hour before bed.',
            style: TextStyle(
              color: Color(0xFF8498B7),
              fontSize: 9,
            ),
          ),

          const SizedBox(height: 12),

          _buildUsageBody(),
        ],
      ),
    );
  }

  Widget _buildUsageBody() {
    final usage = _usage;

    if (usage == null) {
      return const _NoDataMessage(message: 'Reading phone usage...');
    }

    switch (usage.status) {
      case UsageStatsStatus.unsupported:
        return const _NoDataMessage(
          message: 'Phone usage tracking is only available on Android.',
        );

      case UsageStatsStatus.permissionRequired:
        // ⚠️ PACKAGE_USAGE_STATS 是特殊權限，跳不出系統的授權對話框——
        // 使用者一定要自己走一趟設定頁，所以這裡要給一個按鈕帶路，
        // 不能只寫「沒有權限」然後把人丟在原地。
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _NoDataMessage(
              message:
                  'Sonnap needs Usage Access to see which apps keep you up. '
                  'Android asks for this in system settings, not in the app.',
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _requestUsageAccess,
                icon: const Icon(Icons.settings_rounded, size: 16),
                label: const Text('Open Usage Access settings'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: purpleColor),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        );

      case UsageStatsStatus.empty:
        return const _NoDataMessage(
          message: 'No app activity was recorded yesterday.',
        );

      case UsageStatsStatus.failed:
        return _NoDataMessage(
          message: 'Could not read phone usage: ${usage.error ?? "unknown error"}',
        );

      case UsageStatsStatus.ok:
        final busiest = usage.apps.first.minutes;
        return Column(
          children: [
            for (final app in usage.apps)
              _UsageRow(app: app, busiestMinutes: busiest),
          ],
        );
    }
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

          _buildDeliveryRow(),
        ],
      ),
    );
  }

  /// 這份資料是「即時從後端拿的」還是「打包在 App 裡的」。
  ///
  /// ⚠️ **這一列不能省。** App 在後端連不上時會自動退回打包的 asset
  /// （見 `FallbackSleepRepository`），那份資料是真的、但可能已經過期。
  /// 不講出來的話，使用者會以為看到的是即時資料——「安靜地顯示過期資料」
  /// 比「明確地報錯」更糟，那正是本專案一路以來最想避免的失敗模式。
  ///
  /// 完全沒設定 API（沒給 `--dart-define=SONNAP_API_BASE`）時不顯示這一列：
  /// 那是預期中的單機模式，不是降級。
  Widget _buildDeliveryRow() {
    final repo = widget.repository;
    if (repo is! FallbackSleepRepository) return const SizedBox.shrink();

    final live = repo.lastSource == SleepDataSource.api;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: _TrackingSourceRow(
        icon: live
            ? Icons.cloud_done_rounded
            : Icons.cloud_off_rounded,
        title: live ? 'Live from backend' : 'Bundled with the app',
        subtitle: live
            ? 'Fetched just now'
            : 'Backend unreachable - this data may be out of date',
        // ⚠️ 降級狀態不能掛綠色勾勾。實機看到「Backend unreachable」旁邊
        // 一個綠勾，讀起來像「一切正常」，把那句話的意思整個抵消掉。
        healthy: live,
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
                    _periodLabel(days),
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
              _periodLabel(_selectedDays),
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

    // 0 = 全部。history 只有 30 晚，全畫出來不會有效能問題。
    if (_selectedDays == 0) {
      return sortedHistory;
    }

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

  /// 右邊那個狀態圖示要不要顯示成「正常」。
  ///
  /// ⚠️ 實機看到「Backend unreachable」旁邊掛著一個綠色勾勾——那讀起來像
  /// 「一切正常」，把旁邊那句話的意思整個抵消掉。降級狀態就要看起來像降級，
  /// 否則「顯示來源」這件事等於白做。
  final bool healthy;

  const _TrackingSourceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.healthy = true,
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

          Icon(
            healthy
                ? Icons.check_circle_rounded
                : Icons.error_outline_rounded,
            color: healthy
                ? const Color(0xFF7ED957)
                : const Color(0xFFFFC83D),
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
/// 一列 App 使用時間：名稱、長條、分鐘數。
///
/// 長條長度是「相對於當天用最久的那個 App」，不是相對於 24 小時——
/// 後者會讓所有長條都短到看不出差別。這是相對比較，不是絕對比例。
class _UsageRow extends StatelessWidget {
  final AppUsage app;
  final int busiestMinutes;

  const _UsageRow({required this.app, required this.busiestMinutes});

  String _format(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final ratio = busiestMinutes <= 0
        ? 0.0
        : (app.minutes / busiestMinutes).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  app.appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                _format(app.minutes),
                style: const TextStyle(
                  color: Color(0xFF8296B7),
                  fontSize: 10,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 5,
              backgroundColor: const Color(0xFF0A1934),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF7657FF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 趨勢圖上選到某一晚時，顯示那一晚的寵物。
///
/// 三層退路與首頁的 PetCard 相同：
///   ① 該心情專屬的 Lottie 檔
///   ② 檔案讀不到 → happy_dog.json + 該心情的濾鏡
///   ③ 連退路都讀不到 → 靜態的爪印 icon
///
/// 尺寸刻意比首頁小很多——這裡是一條資訊列的配角，不是主角。
class _HistoryPet extends StatelessWidget {
  final String mood;

  const _HistoryPet({required this.mood});

  static const double _size = 46;

  @override
  Widget build(BuildContext context) {
    final visual = petMoodVisual(mood);

    Widget fallback() {
      final animation = Lottie.asset(
        kPetFallbackAnimation,
        width: _size,
        height: _size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => const Icon(
          Icons.pets_rounded,
          color: Colors.white54,
          size: 22,
        ),
      );
      return visual.fallbackFilter == null
          ? animation
          : ColorFiltered(
              colorFilter: visual.fallbackFilter!,
              child: animation,
            );
    }

    return SizedBox(
      width: _size,
      height: _size,
      child: Lottie.asset(
        visual.assetPath,
        width: _size,
        height: _size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => fallback(),
      ),
    );
  }
}
