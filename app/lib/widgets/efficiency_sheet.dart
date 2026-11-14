// 早晨報告 Efficiency 點開（2026-11-15 使用者定，grill Q1–Q12）。
//
// 上半：**這一晚**——大數字是進分數的那一個效率（照抄，不四捨五入掉小數），下面是那一種的名字
//       （後端 composition.efficiency_label，字只在 score_claim.py），再下面一條「算進去的時間」
//       （整條）與「睡著」（亮的那段），寫「5h 59m asleep of 6h 20m counted」與那兩個時刻：
//       ① 按鈕 Start sleep → Out of bed；② Start sleep → 手錶醒來；③ 手錶入睡 → 醒來。
//       ⚠️ 百分比**不在 Dart 重算**——分鐘數只是說明，重算會因為進位多出第二個百分比。
//       ②③ 的晚上多一行提示去按按鈕（不帶好壞字眼）。最下面小字照抄那一種的警語。
//       **不畫 85% 線**（那是判斷，而且 ③ 根本不適用那條門檻）。
// 下半：**這一週**——7 欄、0–100%，每根依那一晚是哪一種畫：① 實心、② 半實心、③ **空心**
//       （同 Time in bed「空心＝手錶」的慣例）；上面寫數字（照抄）；沒資料寫「—」。
//       ⚠️ **不算平均、不比前一週**：三種不是同一個量（③ 幾乎都是 100%），混著平均沒有意義，
//       標題改成各種各幾晚。連不到後端整段不出現。
import 'package:flutter/material.dart';

import '../services/camera_insights.dart' show EfficiencyNight;
import '../services/morning_report.dart' show EfficiencyKind;
import '../services/night_compare.dart' show formatMinutes;

/// 照抄效率數字：不四捨五入，只把「100.0」寫成「100」。
String effNumber(double v) =>
    v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

String _clock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 這一種的分母是哪兩個時刻、各叫什麼。資料不夠 → null。
({DateTime from, DateTime to, String fromName, String toName})? countedSpan(
  EfficiencyKind? kind, {
  DateTime? bedStart,
  DateTime? bedEnd,
  DateTime? asleepAt,
  DateTime? wokeAt,
}) {
  final (DateTime? f, DateTime? t, String fn, String tn) = switch (kind) {
    EfficiencyKind.buttons => (bedStart, bedEnd, 'Start sleep', 'Out of bed'),
    EfficiencyKind.startToWatchWake => (
      bedStart,
      wokeAt,
      'Start sleep',
      'watch wake',
    ),
    EfficiencyKind.watchOnly => (
      asleepAt,
      wokeAt,
      'watch asleep',
      'watch wake',
    ),
    null => (null, null, '', ''),
  };
  if (f == null || t == null || !t.isAfter(f)) return null;
  return (from: f, to: t, fromName: fn, toName: tn);
}

/// 「3 nights · From your sleep buttons」這種，一種一行；照 ①②③ 排，沒有的那種不寫。
/// ⚠️ 名字只照抄後端（score_claim.py）；舊版後端沒給名字的那一種**不寫**，Dart 不自己取名。
List<String> effWeekCountLines(List<EfficiencyNight?> nights) => [
  for (final k in EfficiencyKind.values)
    if (_labelOf(nights, k) case final label?)
      '${nights.where((n) => n?.kind == k).length} '
          'night${nights.where((n) => n?.kind == k).length == 1 ? '' : 's'} · $label',
];

/// 那一種在這一週裡的名字（後端給的）；這一週沒有那一種、或後端沒給名字 → null。
String? _labelOf(List<EfficiencyNight?> nights, EfficiencyKind k) {
  for (final n in nights) {
    if (n?.kind == k && n?.label != null) return n!.label;
  }
  return null;
}

const kEffButtonsHint =
    'Tap Start sleep and Out of bed to measure this from your time in bed.';

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// [endDate] 往回 7 晚（舊 → 新）；沒有的晚上是 null。
List<(String, EfficiencyNight?)> effWeek(
  Map<String, EfficiencyNight> nights,
  String endDate,
) {
  final end = DateTime.parse(endDate);
  return [
    for (var i = 6; i >= 0; i--)
      () {
        final key = _iso(DateTime.utc(end.year, end.month, end.day - i));
        return (key, nights[key]);
      }(),
  ];
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

Future<void> showEfficiencySheet(
  BuildContext context, {
  required Color color,
  required double value,
  required String date,
  String? label,
  EfficiencyKind? kind,
  String? caveat,
  double? asleepMinutes,
  ({DateTime from, DateTime to, String fromName, String toName})? span,
  Map<String, EfficiencyNight>? week,
  String? fontFamily,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => DefaultTextStyle.merge(
      style: TextStyle(fontFamily: fontFamily),
      child: EfficiencyView(
        color: color,
        value: value,
        label: label,
        kind: kind,
        caveat: caveat,
        asleepMinutes: asleepMinutes,
        span: span,
        week: week == null || week.isEmpty ? null : effWeek(week, date),
      ),
    ),
  );
}

class EfficiencyView extends StatelessWidget {
  final Color color;
  final double value;
  final String? label;
  final EfficiencyKind? kind;
  final String? caveat;
  final double? asleepMinutes;
  final ({DateTime from, DateTime to, String fromName, String toName})? span;

  /// 舊 → 新 7 晚；null＝沒有一週資料（連不到後端），下半不出現。
  final List<(String, EfficiencyNight?)>? week;

  const EfficiencyView({
    super.key,
    required this.value,
    this.color = const Color(0xFF7FD3FF),
    this.label,
    this.kind,
    this.caveat,
    this.asleepMinutes,
    this.span,
    this.week,
  });

  static const _soft = Color(0xB3FFFFFF);

  @override
  Widget build(BuildContext context) {
    final sp = span;
    final counted = sp == null
        ? null
        : sp.to.difference(sp.from).inSeconds / 60.0;
    final w = week;
    final showWeek = w != null && w.any((n) => n.$2 != null);

    return Container(
      key: const Key('eff-sheet'),
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
                  Icon(Icons.speed_rounded, size: 20, color: color),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Efficiency',
                      key: const Key('eff-title'),
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
              Text(
                '${effNumber(value)}%',
                key: const Key('eff-value'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (label != null)
                Text(
                  label!,
                  key: const Key('eff-label'),
                  style: TextStyle(
                    color: Color.lerp(color, Colors.white, 0.3),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (sp != null && counted != null && asleepMinutes != null) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  key: const Key('eff-bar'),
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 16,
                    child: LayoutBuilder(
                      builder: (context, box) => Stack(
                        children: [
                          const Positioned.fill(
                            child: ColoredBox(color: Color(0x1FFFFFFF)),
                          ),
                          Positioned(
                            key: const Key('eff-bar-asleep'),
                            left: 0,
                            top: 0,
                            bottom: 0,
                            width:
                                box.maxWidth *
                                (asleepMinutes! / counted).clamp(0.0, 1.0),
                            child: ColoredBox(color: color),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${formatMinutes(asleepMinutes!)} asleep of '
                  '${formatMinutes(counted)} counted',
                  key: const Key('eff-minutes'),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                Text(
                  '${sp.fromName} ${_clock(sp.from)} → '
                  '${sp.toName} ${_clock(sp.to)}',
                  key: const Key('eff-span'),
                  style: const TextStyle(color: _soft, fontSize: 12),
                ),
              ],
              if (kind == EfficiencyKind.startToWatchWake ||
                  kind == EfficiencyKind.watchOnly) ...[
                const SizedBox(height: 10),
                const Text(
                  kEffButtonsHint,
                  key: Key('eff-hint'),
                  style: TextStyle(color: _soft, fontSize: 12),
                ),
              ],
              // ── 這一週 ──
              if (showWeek) ...[
                const SizedBox(height: 22),
                Container(height: 1, color: const Color(0x1FFFFFFF)),
                const SizedBox(height: 14),
                for (final line in effWeekCountLines([for (final n in w) n.$2]))
                  Text(
                    line,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 160,
                  child: _EffBars(week: w, color: color),
                ),
                const SizedBox(height: 8),
                Wrap(
                  key: const Key('eff-legend'),
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    for (final k in EfficiencyKind.values)
                      if (_labelOf([for (final n in w) n.$2], k)
                          case final label?)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _Swatch(kind: k, color: color),
                            const SizedBox(width: 5),
                            Text(
                              label,
                              style: const TextStyle(
                                color: Color(0x99FFFFFF),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                  ],
                ),
              ],
              if (caveat != null) ...[
                const SizedBox(height: 18),
                Text(
                  // 後端那段字是接在「Efficiency - 」後面寫的（同 Insights 頁），照抄
                  'Efficiency - ${caveat!}',
                  key: const Key('eff-caveat'),
                  style: const TextStyle(
                    color: Color(0x99FFFFFF),
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 一根長條的填色：① 實心、② 半實心（淡填色＋邊）、③ 空心（只有邊）。
BoxDecoration _fill(EfficiencyKind k, Color c, double strong) => switch (k) {
  EfficiencyKind.buttons => BoxDecoration(
    borderRadius: BorderRadius.circular(40),
    color: c.withValues(alpha: strong),
  ),
  EfficiencyKind.startToWatchWake => BoxDecoration(
    borderRadius: BorderRadius.circular(40),
    color: c.withValues(alpha: 0.4 * strong),
    border: Border.all(color: c.withValues(alpha: strong), width: 2),
  ),
  EfficiencyKind.watchOnly => BoxDecoration(
    borderRadius: BorderRadius.circular(40),
    border: Border.all(color: c.withValues(alpha: strong), width: 2),
  ),
};

class _Swatch extends StatelessWidget {
  final EfficiencyKind kind;
  final Color color;
  const _Swatch({required this.kind, required this.color});
  @override
  Widget build(BuildContext context) =>
      Container(width: 10, height: 14, decoration: _fill(kind, color, 1));
}

class _EffBars extends StatelessWidget {
  final List<(String, EfficiencyNight?)> week;
  final Color color;
  const _EffBars({required this.week, required this.color});

  static const double _labelH = 22;
  static const double _valueH = 16;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final barH = box.maxHeight - _labelH - _valueH;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < week.length; i++)
              Expanded(
                child: () {
                  final (date, n) = week[i];
                  final isLast = i == week.length - 1;
                  final d = DateTime.parse(date);
                  final fillH = n == null
                      ? 0.0
                      : barH * (n.value / 100).clamp(0.0, 1.0);
                  final strong = isLast ? 1.0 : 0.7;
                  return Semantics(
                    label:
                        '${_weekdays[d.weekday - 1]} ${d.day}: '
                        '${n == null ? 'no data' : '${effNumber(n.value)}%${n.label == null ? '' : ', ${n.label}'}'}',
                    child: Padding(
                      key: Key('eff-week-bar-$date'),
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
                                if (n != null && fillH > 0)
                                  Positioned(
                                    key: Key(
                                      'eff-week-fill-$date-${n.kind.name}',
                                    ),
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    height: fillH,
                                    child: DecoratedBox(
                                      decoration: _fill(n.kind, color, strong),
                                    ),
                                  ),
                                Positioned(
                                  left: -6,
                                  right: -6,
                                  bottom: n == null ? null : fillH + 2,
                                  top: n == null
                                      ? _valueH + barH / 2 - 8
                                      : null,
                                  height: _valueH,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      n == null ? '—' : effNumber(n.value),
                                      key: Key('eff-week-value-$date'),
                                      style: TextStyle(
                                        color: n == null
                                            ? const Color(0x66FFFFFF)
                                            : (isLast
                                                  ? Colors.white
                                                  : const Color(0xCCFFFFFF)),
                                        fontSize: 11,
                                        fontWeight: n == null
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
