// 早晨報告 Awake 點開（2026-11-15 使用者定，grill Q1–Q11）：
//
// 上半：**這一晚**——大數字是手錶自己的總數（同 Sleep Stages 圖例：還原的段落有 2 晚對不上，
//       以手錶為準），下面一條入睡→起床的時間軸、清醒的段落亮起來，再下面每一段一個小標籤
//       「03:41 · 6m」（照時間排、多了就換行、不藏）。**不寫醒了幾次**（手錶有很多 1–2 分鐘的段落，
//       次數聽起來比實際嚇人；要訂最短多久才算又沒有文獻）。段落長度**不加總成第二個總數**。
//       沒有時間軸的晚上（Health Connect）只寫總數＋「No timeline for this night」，不編段落。
// 下半：**這一週**——7 欄、同 Total sleep 那張的膠囊；「Average 8m awake」＋幾晚有資料＋
//       「↑ 5m vs the week before」（只代表方向，紅升綠降）。平均、晚數、跟前一週比
//       **直接用 sleep_week_sheet 的函式**（同一個定義）。**0 分鐘是真的值**：寫「0m」、算進平均；
//       沒資料寫「—」、不算。沒有目標線。連不到後端（沒有一週資料）就整段不出現。
// - 不判斷好壞、不掛手錶準確度的警語（10-22 使用者定，警語只放報告書）。
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/sleep_stages.dart';
import '../services/night_compare.dart'
    show NightValue, formatMinutes, kDeltaUp, kDeltaDown, kDeltaFlat;
import 'sleep_week_sheet.dart'
    show SleepWeek, sleepWeek, sleepWeekCountLine, sleepWeekChangeLine;

/// 一段清醒。
class AwakeSpan {
  final DateTime start;
  final DateTime end;
  const AwakeSpan(this.start, this.end);
  double get minutes => end.difference(start).inSeconds / 60;
}

/// 時間軸上清醒的段落，照時間排。沒有時間軸 → 空。純函式。
List<AwakeSpan> awakeSpans(SleepStages? stages) {
  if (stages == null) return const [];
  final out = [
    for (final s in stages.segments)
      if (s.stage == 'awake') AwakeSpan(s.start, s.end),
  ]..sort((a, b) => a.start.compareTo(b.start));
  return out;
}

String _clock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 「03:41 · 6m」；不到 1 分鐘寫「<1m」（不寫 0m，那一段確實有醒）。
String awakeSpanLabel(AwakeSpan s) =>
    '${_clock(s.start)} · ${s.minutes < 1 ? '<1m' : formatMinutes(s.minutes)}';

/// 「Average 8m awake」。
String awakeAverageLine(SleepWeek w) =>
    'Average ${formatMinutes(w.averageMinutes!)} awake';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

Future<void> showAwakeSheet(
  BuildContext context, {
  required String title,
  required IconData icon,
  required Color color,
  required String date,
  required double totalMinutes,
  SleepStages? stages,
  List<NightValue>? series,
  String? fontFamily,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => DefaultTextStyle.merge(
      style: TextStyle(fontFamily: fontFamily),
      child: AwakeView(
        title: title,
        icon: icon,
        color: color,
        totalMinutes: totalMinutes,
        stages: stages,
        week: series == null ? null : sleepWeek(series, date),
      ),
    ),
  );
}

class AwakeView extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final double totalMinutes;
  final SleepStages? stages;

  /// null＝沒有一週資料（連不到後端），下半整段不出現。
  final SleepWeek? week;

  const AwakeView({
    super.key,
    required this.title,
    required this.totalMinutes,
    this.stages,
    this.week,
    this.icon = Icons.visibility_rounded,
    this.color = const Color(0xFFFF8AD8),
  });

  static const _soft = Color(0xB3FFFFFF);

  @override
  Widget build(BuildContext context) {
    final spans = awakeSpans(stages);
    final w = week;
    final showWeek = w != null && w.nightsWithData > 0;
    final change = showWeek ? sleepWeekChangeLine(w) : null;
    final c = w?.change?.round();

    return Container(
      key: const Key('awake-sheet'),
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
        child: SingleChildScrollView(
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
                      key: const Key('awake-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (showWeek)
                    const Text(
                      'Last 7 nights',
                      softWrap: false,
                      style: TextStyle(color: _soft, fontSize: 12),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // ── 這一晚 ──
              const Text(
                'Awake during the night',
                style: TextStyle(color: _soft, fontSize: 13),
              ),
              Text(
                formatMinutes(totalMinutes),
                key: const Key('awake-total'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              if (stages == null)
                const Text(
                  'No timeline for this night',
                  key: Key('awake-no-timeline'),
                  style: TextStyle(color: _soft, fontSize: 13),
                )
              else ...[
                _NightStrip(stages: stages!, spans: spans, color: color),
                const SizedBox(height: 10),
                Wrap(
                  key: const Key('awake-spans'),
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in spans)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          awakeSpanLabel(s),
                          style: TextStyle(
                            color: Color.lerp(color, Colors.white, 0.55),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              // ── 這一週 ──
              if (showWeek) ...[
                const SizedBox(height: 24),
                Container(height: 1, color: const Color(0x1FFFFFFF)),
                const SizedBox(height: 16),
                Text(
                  awakeAverageLine(w),
                  key: const Key('awake-week-average'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  sleepWeekCountLine(w),
                  key: const Key('awake-week-count'),
                  style: const TextStyle(color: _soft, fontSize: 13),
                ),
                if (change != null)
                  Text(
                    change,
                    key: const Key('awake-week-change'),
                    style: TextStyle(
                      color: c! > 0
                          ? kDeltaUp
                          : (c < 0 ? kDeltaDown : kDeltaFlat),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 170,
                  child: _WeekBars(week: w, color: color),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 入睡 → 起床一條，清醒的段落亮起來；兩端寫時刻，中間每個整點一條細刻度。
class _NightStrip extends StatelessWidget {
  final SleepStages stages;
  final List<AwakeSpan> spans;
  final Color color;
  const _NightStrip({
    required this.stages,
    required this.spans,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final start = stages.start;
    final end = stages.end;
    final total = end.difference(start).inSeconds.toDouble();
    if (total <= 0) return const SizedBox.shrink();
    final hours = <DateTime>[];
    var h = DateTime(start.year, start.month, start.day, start.hour + 1);
    while (h.isBefore(end)) {
      hours.add(h);
      h = h.add(const Duration(hours: 1));
    }
    return Column(
      key: const Key('awake-strip'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 26,
          child: LayoutBuilder(
            builder: (context, box) {
              double x(DateTime t) =>
                  box.maxWidth * t.difference(start).inSeconds / total;
              return Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0x1AFFFFFF),
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                  for (final t in hours)
                    Positioned(
                      left: x(t),
                      top: 8,
                      bottom: 8,
                      width: 1,
                      child: const ColoredBox(color: Color(0x26FFFFFF)),
                    ),
                  for (var i = 0; i < spans.length; i++)
                    Positioned(
                      key: Key('awake-strip-span-$i'),
                      left: x(spans[i].start),
                      // 太短的段落至少 3 px，不然在圖上看不到
                      width: math.max(3, x(spans[i].end) - x(spans[i].start)),
                      top: 2,
                      bottom: 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.5),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              _clock(start),
              key: const Key('awake-strip-start'),
              style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 11),
            ),
            const Spacer(),
            Text(
              _clock(end),
              key: const Key('awake-strip-end'),
              style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
}

/// 7 欄膠囊（同 Total sleep 那張）：長條＝那晚清醒幾分鐘，上面寫數字；0 寫「0m」不畫條；沒資料寫「—」。
class _WeekBars extends StatelessWidget {
  final SleepWeek week;
  final Color color;
  const _WeekBars({required this.week, required this.color});

  static const double _labelH = 22;
  static const double _valueH = 16;

  @override
  Widget build(BuildContext context) {
    final maxV = math.max(
      30.0,
      week.nights.fold<double>(0, (m, n) => math.max(m, n.minutes ?? 0)),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final barH = box.maxHeight - _labelH - _valueH;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < week.nights.length; i++)
              Expanded(
                child: () {
                  final n = week.nights[i];
                  final isLast = i == week.nights.length - 1;
                  final d = DateTime.parse(n.date);
                  final v = n.minutes;
                  final fillH = v == null || v <= 0
                      ? 0.0
                      : math.max(6.0, barH * v / maxV);
                  final strong = isLast ? 1.0 : 0.7;
                  return Semantics(
                    label:
                        '${_weekdays[d.weekday - 1]} ${d.day}: '
                        '${v == null ? 'no data' : '${formatMinutes(v)} awake'}',
                    child: Padding(
                      key: Key('awake-week-bar-${n.date}'),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Column(
                        children: [
                          SizedBox(
                            height: _valueH + barH,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  top: _valueH,
                                  bottom: 0,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: const Color(0x14FFFFFF),
                                      borderRadius: BorderRadius.circular(40),
                                    ),
                                  ),
                                ),
                                if (fillH > 0)
                                  Positioned(
                                    key: Key('awake-week-fill-${n.date}'),
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    height: fillH,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(40),
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Color.lerp(
                                              color,
                                              Colors.white,
                                              0.4,
                                            )!.withValues(alpha: strong),
                                            color.withValues(alpha: strong),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  left: -6,
                                  right: -6,
                                  bottom: v == null ? null : fillH + 2,
                                  top: v == null
                                      ? _valueH + barH / 2 - 8
                                      : null,
                                  height: _valueH,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      v == null ? '—' : formatMinutes(v),
                                      key: Key('awake-week-value-${n.date}'),
                                      style: TextStyle(
                                        color: v == null
                                            ? const Color(0x66FFFFFF)
                                            : (isLast
                                                  ? Colors.white
                                                  : const Color(0xCCFFFFFF)),
                                        fontSize: 11,
                                        fontWeight: v == null
                                            ? null
                                            : FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: _labelH,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FittedBox(
                                child: Text(
                                  _weekdays[d.weekday - 1],
                                  style: TextStyle(
                                    color: isLast
                                        ? Colors.white
                                        : const Color(0xB3FFFFFF),
                                    fontSize: 11,
                                    fontWeight: isLast
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }(),
              ),
          ],
        );
      },
    );
  }
}
