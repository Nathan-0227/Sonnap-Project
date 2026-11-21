import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/insights_periods.dart' show starsFor;
import 'night_week.dart';
import 'report_sheet.dart';

/// 分數點開（2026-11-21 grill 定，使用者看過預覽）：首頁的分數卡與早晨報告的分數圓弧都開這一頁。
///
/// - 這一晚：大數字＋等級＋星星（Good＝4 顆，同 Insights）＋右上圓環，**全部照抄後端**
/// - 五個量：睡多久、效率、醒著、深睡、REM。**只寫數字、不寫各得幾分**——分數組成 11-19 定了不上 App
///   （不然就是第二份配分表）。有自己詳細頁的可以點；REM 沒量到寫 N/A、不能點
/// - 這一週：7 晚長條**照每晚的等級上色**（顏色是後端 `score_color`，Dart 沒有等級→顏色的表）；
///   Usually＝中間值；跟前一週比只代表方向，上升紅、下降綠（分數也一樣，同 Insights）
/// - **不放警語**（11-19 定：警語只留在書面報告）
class ScoreRow {
  final String name;
  final Color color;

  /// null＝這一晚沒有這個數字，寫「—」（例如沒有後端時打包檔沒有醒著時間）
  final String? value;

  /// 手錶沒量到（只有 REM 會這樣），寫 N/A。跟「—」不同：「—」是沒資料，N/A 是那一晚量不到
  final bool notMeasured;
  final String? note;
  final VoidCallback? onTap;
  final String id;

  const ScoreRow({
    required this.id,
    required this.name,
    required this.color,
    required this.value,
    this.notMeasured = false,
    this.note,
    this.onTap,
  });
}

/// 「↑ 3 vs the week before」；只代表方向。
String? scoreChangeLine(MedianWeek w) {
  final c = w.change;
  if (c == null) return null;
  final r = c.round();
  if (r == 0) return '= same as the week before';
  return '${r > 0 ? '↑' : '↓'} ${r.abs()} vs the week before';
}

Future<void> showScoreSheet(
  BuildContext context, {
  required String dateTitle,
  required double score,
  String? quality,
  Color? qualityColor,
  required List<ScoreRow> rows,
  MedianWeek? week,
  List<Color?> weekColors = const [],
  String? fontFamily,
}) {
  return showReportSheet<void>(
    context: context,
    builder: (context) => DefaultTextStyle.merge(
      style: TextStyle(fontFamily: fontFamily),
      child: ScoreView(
        dateTitle: dateTitle,
        score: score,
        quality: quality,
        qualityColor: qualityColor,
        rows: rows,
        week: week,
        weekColors: weekColors,
      ),
    ),
  );
}

class ScoreView extends StatelessWidget {
  final String dateTitle;
  final double score;
  final String? quality;
  final Color? qualityColor;
  final List<ScoreRow> rows;

  /// null＝沒有一週資料（連不到後端），下半整段不出現。
  final MedianWeek? week;

  /// 每一欄的顏色（舊 → 新，跟 [week] 的 nights 對齊）；null 的欄用 [_fallback]。
  final List<Color?> weekColors;

  const ScoreView({
    super.key,
    required this.dateTitle,
    required this.score,
    required this.rows,
    this.quality,
    this.qualityColor,
    this.week,
    this.weekColors = const [],
  });

  static const _soft = Color(0xB3FFFFFF);
  static const _faint = Color(0xFF9FA7CC);
  static const _fallback = Color(0xFFC9B8FF);
  static const _up = Color(0xFFFF7B7B);
  static const _down = Color(0xFF4FE0A0);

  @override
  Widget build(BuildContext context) {
    final color = qualityColor ?? _fallback;
    final stars = starsFor(quality);
    final w = week;
    final showWeek = w != null && w.nightsWithData > 0;
    final change = showWeek ? scoreChangeLine(w) : null;
    final c = w?.change?.round();

    return Container(
      key: const Key('score-sheet'),
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
                  Icon(Icons.star_rounded, size: 20, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sleep score',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    dateTitle,
                    softWrap: false,
                    style: const TextStyle(color: _soft, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // ── 這一晚 ──
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${score.round()}',
                          key: const Key('score-value'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (quality != null)
                              Container(
                                key: const Key('score-quality'),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  quality!,
                                  style: const TextStyle(
                                    color: Color(0xFF1A1F4C),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            // 星星：等級的另一種寫法（同 Insights 的 starsFor），不是另一個判斷
                            if (stars > 0)
                              Semantics(
                                label: '$stars of 4 stars',
                                child: Row(
                                  key: const Key('score-stars'),
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (var i = 0; i < 4; i++)
                                      Icon(
                                        Icons.star_rounded,
                                        size: 18,
                                        color: i < stars
                                            ? const Color(0xFFFFD772)
                                            : Colors.white.withValues(alpha: 0.18),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 96,
                    height: 96,
                    child: CustomPaint(
                      key: const Key('score-ring'),
                      painter: _RingPainter(score / 100, color),
                      child: Center(
                        child: Text(
                          '${score.round()}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'This night',
                style: TextStyle(color: _soft, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0x8C3A3672),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x24FFFFFF)),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0)
                        Container(height: 1, color: const Color(0x1FFFFFFF)),
                      _row(rows[i]),
                    ],
                  ],
                ),
              ),
              if (showWeek) ...[
                const SizedBox(height: 22),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'This week',
                      style: TextStyle(color: _soft, fontSize: 13),
                    ),
                    const Spacer(),
                    if (change != null)
                      Text(
                        change,
                        key: const Key('score-week-change'),
                        style: TextStyle(
                          color: c == null || c == 0
                              ? _soft
                              : (c > 0 ? _up : _down),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
                if (w.usual != null)
                  Text.rich(
                    key: const Key('score-week-usual'),
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Usually ',
                          style: TextStyle(color: _soft, fontSize: 13),
                        ),
                        TextSpan(
                          text: '${w.usual!.round()}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                WeekBars(
                  nights: w.nights,
                  max: 100,
                  colorOf: (i) =>
                      (i < weekColors.length ? weekColors[i] : null) ?? _fallback,
                  label: (v) => '${v.round()}',
                ),
                const SizedBox(height: 6),
                Text(
                  medianWeekCountLine(w),
                  style: const TextStyle(color: _faint, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(ScoreRow r) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: r.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              r.name,
              style: const TextStyle(color: Color(0xFFDCE0F5), fontSize: 14),
            ),
          ),
          Text(
            r.notMeasured ? 'N/A' : (r.value ?? '—'),
            key: Key('score-row-${r.id}'),
            style: TextStyle(
              color: r.notMeasured || r.value == null
                  ? const Color(0xFF7F87AE)
                  : Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          if (r.note != null) ...[
            const SizedBox(width: 6),
            Text(
              r.note!,
              style: const TextStyle(color: _faint, fontSize: 11),
            ),
          ],
          SizedBox(
            width: 18,
            child: r.onTap == null
                ? null
                : const Icon(Icons.chevron_right_rounded,
                    size: 18, color: Color(0xFF7F87AE)),
          ),
        ],
      ),
    );
    if (r.onTap == null) return content;
    return InkWell(
      key: Key('score-open-${r.id}'),
      onTap: r.onTap,
      child: content,
    );
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  final Color color;
  _RingPainter(this.fraction, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2 - 6;
    final c = size.center(Offset.zero);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..color = Colors.white.withValues(alpha: 0.12);
    canvas.drawCircle(c, r, base);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2,
        2 * math.pi * fraction.clamp(0.0, 1.0), false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color;
}
