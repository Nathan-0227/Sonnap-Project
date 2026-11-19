// Insights 的 Week／Month／Year：把逐夜（逐天）的數字收成「這段期間」的格子（2026-11-19 grill 定案）。
//
// 純函式、沒有 I/O。只做排版用的加總，**不判斷好壞**：
//   - 大字是中位數（同報告一週頁的「Usually」：平均會被一兩個特別的晚上拉走）
//   - 小圖：Week／Month 一天一欄，Year 一個月一欄（那個月的中位數）
//   - 跟上一期比只給方向與差多少，顏色由畫面決定（上升紅、下降綠，分數也一樣）
//   - 沒資料的日子是 null，不是 0；不算進中位數
//   - 熬夜幾晚照抄後端每一晚的 is_late（跨午夜只在 adherence.py 算）
//   - 效率：所有種類合在一起算（使用者 11-19 定，知情：按按鈕多的週看起來會比較低）
import '../models/sleep_session.dart';
import '../models/wall_clock.dart';
import '../widgets/phone_week_sheet.dart' show PhoneDown;
import 'camera_insights.dart';
import 'morning_report.dart' show reportDateKey;

/// Insights 的四個期間（2026-11-19 grill 定案）。
enum InsightsPeriod { day, week, month, year }

const insightsPeriodLabels = {
  InsightsPeriod.day: 'Day',
  InsightsPeriod.week: 'Week',
  InsightsPeriod.month: 'Month',
  InsightsPeriod.year: 'Year',
};

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _d(DateTime t) => dateOnly(t);

/// [anchor] 落在的那一段期間：[start, end]（都含）。
/// Week＝週一到週日的日曆週；Month、Year＝日曆月、日曆年（使用者定，不用「最近 N 天」）。
({DateTime start, DateTime end}) insightsRange(
    InsightsPeriod period, DateTime anchor) {
  final d = dateOnly(anchor);
  switch (period) {
    case InsightsPeriod.day:
      return (start: d, end: d);
    case InsightsPeriod.week:
      // 用日曆日相減，不減 24 小時（夏令時間那天會差一小時）
      final start = DateTime(d.year, d.month, d.day - (d.weekday - 1));
      return (start: start, end: DateTime(start.year, start.month, start.day + 6));
    case InsightsPeriod.month:
      return (
        start: DateTime(d.year, d.month, 1),
        end: DateTime(d.year, d.month + 1, 0),
      );
    case InsightsPeriod.year:
      return (start: DateTime(d.year, 1, 1), end: DateTime(d.year, 12, 31));
  }
}

/// 往前／往後一段期間。月份從 31 號往前翻時夾到那個月的最後一天（3/31 → 2/28）。
DateTime insightsShift(InsightsPeriod period, DateTime anchor, int step) {
  final d = dateOnly(anchor);
  switch (period) {
    case InsightsPeriod.day:
      return DateTime(d.year, d.month, d.day + step);
    case InsightsPeriod.week:
      return DateTime(d.year, d.month, d.day + 7 * step);
    case InsightsPeriod.month:
      final last = DateTime(d.year, d.month + step + 1, 0).day;
      return DateTime(d.year, d.month + step, d.day > last ? last : d.day);
    case InsightsPeriod.year:
      final last = DateTime(d.year + step, d.month + 1, 0).day;
      return DateTime(d.year + step, d.month, d.day > last ? last : d.day);
  }
}

/// 「Wed, Nov 18」／「Nov 16 – 22」／「November 2026」／「2026」。
/// 自己組而不用 intl：那會跟著手機語言走，而全 App 的輸出是英文。
String insightsLabel(InsightsPeriod period, DateTime anchor) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final r = insightsRange(period, anchor);
  switch (period) {
    case InsightsPeriod.day:
      final d = r.start;
      return '${days[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';
    case InsightsPeriod.week:
      final s = r.start, e = r.end;
      final head = '${_months[s.month - 1]} ${s.day}';
      final tail = s.month == e.month
          ? '${e.day}'
          : '${_months[e.month - 1]} ${e.day}';
      final year = s.year == e.year ? '' : ', ${e.year}';
      return '$head – $tail$year';
    case InsightsPeriod.month:
      return '${_monthsLong[r.start.month - 1]} ${r.start.year}';
    case InsightsPeriod.year:
      return '${r.start.year}';
  }
}

/// 右箭頭到「本期」為止（不能翻到未來）。
bool insightsCanGoNext(InsightsPeriod period, DateTime anchor, DateTime today) =>
    insightsRange(period, anchor).end.isBefore(dateOnly(today));

/// 左箭頭到「帳號有資料的第一天」那一期為止。[first] 是 null（還不知道）就不擋。
bool insightsCanGoPrev(
        InsightsPeriod period, DateTime anchor, DateTime? first) =>
    first == null || insightsRange(period, anchor).start.isAfter(dateOnly(first));


/// 一段期間裡每一天的日期鍵（含頭尾）。
List<String> periodDates(InsightsPeriod period, DateTime anchor) {
  final r = insightsRange(period, anchor);
  return [
    for (var d = r.start; !d.isAfter(r.end); d = DateTime(d.year, d.month, d.day + 1))
      reportDateKey(d),
  ];
}

double? median(Iterable<double?> values) {
  final v = values.whereType<double>().toList()..sort();
  if (v.isEmpty) return null;
  final m = v.length ~/ 2;
  return v.length.isOdd ? v[m] : (v[m - 1] + v[m]) / 2;
}

/// 一項指標在一段期間的樣子。
class PeriodStat {
  /// 這段期間的中位數；一晚都沒有 → null（畫面寫「—」）。
  final double? median;

  /// 有資料的晚上（天）數。
  final int n;

  /// 小圖：Week 7 欄、Month 那個月的天數、Year 12 欄。沒資料的那一欄是 null。
  final List<double?> bars;

  /// 上一期的中位數；上一期沒資料 → null（不畫箭頭）。
  final double? previous;

  const PeriodStat(this.median, this.n, this.bars, this.previous);

  /// 跟上一期差多少（這期 − 上期）。任何一邊沒有 → null。
  double? get delta =>
      median == null || previous == null ? null : median! - previous!;
}

/// [byDate]：日期鍵 → 那一晚（那一天）的值；沒有的日子不要放進來。
PeriodStat periodStat(
  Map<String, double> byDate,
  InsightsPeriod period,
  DateTime anchor,
) {
  List<double?> valuesIn(DateTime a) =>
      [for (final k in periodDates(period, a)) byDate[k]];
  final now = valuesIn(anchor);
  final prev = valuesIn(insightsShift(period, anchor, -1));
  final List<double?> bars;
  if (period == InsightsPeriod.year) {
    final y = insightsRange(period, anchor).start.year;
    bars = [
      for (var m = 1; m <= 12; m++)
        median(periodDates(InsightsPeriod.month, DateTime(y, m, 1))
            .map((k) => byDate[k])),
    ];
  } else {
    bars = now;
  }
  return PeriodStat(
    median(now),
    now.whereType<double>().length,
    bars,
    median(prev),
  );
}

/// 把時刻換成「從中午 12:00 起算幾分鐘」：晚上 23:00 → 660、凌晨 03:00 → 900。
/// 跨午夜的中位數才不會被 23:59 與 00:01 拉成中午。
double clockFromNoon(DateTime t) =>
    ((t.hour * 60 + t.minute - 12 * 60) % (24 * 60)).toDouble();

/// [clockFromNoon] 的反方向，給畫面寫「03:02」。
String clockLabel(double fromNoon) {
  final m = ((fromNoon.round() + 12 * 60) % (24 * 60));
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// 12:00–18:00 的放下手機不算那一晚的就寢（11-15 使用者定，實例 10-05 偵測成 14:07）。
bool _isAfternoon(DateTime t) => t.hour >= 12 && t.hour < 18;

/// 這段期間的「熬夜幾晚」：照抄後端每一晚的 is_late；後端沒判（null）的晚上不進分母。
({int late, int judged}) lateCount(
  Map<String, PhoneDown> downs,
  InsightsPeriod period,
  DateTime anchor,
) {
  var late = 0, judged = 0;
  for (final k in periodDates(period, anchor)) {
    final d = downs[k];
    if (d == null || d.isLate == null || _isAfternoon(d.at)) continue;
    judged++;
    if (d.isLate!) late++;
  }
  return (late: late, judged: judged);
}

/// W/M/Y 的格子要的每一項逐夜數字。全部從 `/insights`（或打包檔退回）照抄。
class PeriodSeries {
  final Map<String, double> score;
  final Map<String, String> quality;
  final Map<String, String> mood;
  final Map<String, double> sleep;
  final Map<String, double> bedIn; // clockFromNoon
  final Map<String, double> bedOut; // clockFromNoon
  final Map<String, double> inBed; // 分鐘
  final Map<String, double> phoneDown; // clockFromNoon
  final Map<String, PhoneDown> phoneDowns;
  final Map<String, double> awake;
  final Map<String, double> efficiency;
  final Map<String, double> sleepingHr;
  final Map<String, double> deep;
  final Map<String, double> rem;
  final Map<String, double> cameraPerHour;
  final Map<String, double> steps;
  final Map<String, double> activeKcal;
  final Map<String, double> activeMinutes;
  final Map<String, double> stress;
  final List<QualityBand> qualityBands;

  const PeriodSeries({
    this.score = const {},
    this.quality = const {},
    this.mood = const {},
    this.sleep = const {},
    this.bedIn = const {},
    this.bedOut = const {},
    this.inBed = const {},
    this.phoneDown = const {},
    this.phoneDowns = const {},
    this.awake = const {},
    this.efficiency = const {},
    this.sleepingHr = const {},
    this.deep = const {},
    this.rem = const {},
    this.cameraPerHour = const {},
    this.steps = const {},
    this.activeKcal = const {},
    this.activeMinutes = const {},
    this.stress = const {},
    this.qualityBands = const [],
  });

  /// 最早有資料的那一天（左箭頭到這一期為止）。
  DateTime? get firstDate {
    DateTime? first;
    for (final m in [score, sleep, phoneDowns, cameraPerHour, steps]) {
      for (final k in m.keys) {
        final d = DateTime.tryParse(k);
        if (d != null && (first == null || d.isBefore(first))) first = d;
      }
    }
    return first;
  }

  factory PeriodSeries.fromInsights(CameraInsightsResult r) {
    final score = <String, double>{};
    final quality = <String, String>{};
    final mood = <String, String>{};
    final sleep = <String, double>{};
    final deep = <String, double>{};
    final rem = <String, double>{};
    r.wearableNights.forEach((k, n) {
      if (n.score != null) score[k] = n.score!;
      if (n.quality != null) quality[k] = n.quality!;
      if (n.petMood != null) mood[k] = n.petMood!;
      if (n.sleepMinutes != null) sleep[k] = n.sleepMinutes!;
      if (n.deepMinutes != null) deep[k] = n.deepMinutes!;
      if (n.remMinutes != null) rem[k] = n.remMinutes!;
    });

    // 上床→起床：按鈕兩個都有才用按鈕，不然退回手錶入睡→醒來（同報告的一週上床圖）
    final bedIn = <String, double>{}, bedOut = <String, double>{}, inBed = <String, double>{};
    final dates = {...r.bedButtons.keys, ...r.watchSleep.keys};
    for (final k in dates) {
      final b = r.bedButtons[k];
      final w = r.watchSleep[k];
      final (DateTime?, DateTime?)? pair =
          (b != null && b.$1 != null && b.$2 != null) ? b : w;
      final s = pair?.$1, e = pair?.$2;
      if (s == null || e == null || !e.isAfter(s)) continue;
      bedIn[k] = clockFromNoon(s);
      bedOut[k] = clockFromNoon(e);
      inBed[k] = e.difference(s).inMinutes.toDouble();
    }

    final phoneDown = <String, double>{
      for (final e in r.phoneDowns.entries)
        if (!_isAfternoon(e.value.at)) e.key: clockFromNoon(e.value.at),
    };

    final steps = <String, double>{}, kcal = <String, double>{};
    final active = <String, double>{}, stress = <String, double>{};
    r.dailies.forEach((k, d) {
      // 0 步＝沒戴錶，不是走了 0 步 → 當作沒資料
      if (d.steps != null && d.steps! > 0) steps[k] = d.steps!.toDouble();
      if (d.activeKcal != null && (d.steps ?? 0) > 0) kcal[k] = d.activeKcal!;
      if (d.activeMinutes != null && (d.steps ?? 0) > 0) active[k] = d.activeMinutes!;
      if (d.stressAvg != null) stress[k] = d.stressAvg!;
    });

    return PeriodSeries(
      score: score,
      quality: quality,
      mood: mood,
      sleep: sleep,
      bedIn: bedIn,
      bedOut: bedOut,
      inBed: inBed,
      phoneDown: phoneDown,
      phoneDowns: r.phoneDowns,
      awake: r.awakeMinutes,
      efficiency: {for (final e in r.efficiencyNights.entries) e.key: e.value.value},
      sleepingHr: {for (final e in r.sleepHeartRates.entries) e.key: e.value.avg},
      deep: deep,
      rem: rem,
      cameraPerHour: {
        for (final n in r.nights)
          if (n.eventsPerHour != null) n.date: n.eventsPerHour!,
      },
      steps: steps,
      activeKcal: kcal,
      activeMinutes: active,
      stress: stress,
      qualityBands: r.qualityBands,
    );
  }
}

/// 連不到後端時，用打包檔的最近 30 晚（只夠畫 Week；Month／Year 畫面會照實說要後端）。
/// 打包檔沒有 REM、手機、攝影機、白天資料，那幾格就是「—」。
PeriodSeries periodSeriesFromBundled(SleepSession session) {
  final score = <String, double>{}, sleep = <String, double>{}, deep = <String, double>{};
  final eff = <String, double>{}, bedIn = <String, double>{}, bedOut = <String, double>{};
  final inBed = <String, double>{};
  final quality = <String, String>{}, mood = <String, String>{};
  for (final e in session.history) {
    final k = e.date;
    if (e.finalScore != null) score[k] = e.finalScore!;
    if (e.finalQuality != null) quality[k] = e.finalQuality!;
    if (e.petMood != null) mood[k] = e.petMood!;
    if (e.sleepDurationHours != null) sleep[k] = e.sleepDurationHours! * 60;
    if (e.deepMinutes != null) deep[k] = e.deepMinutes!.toDouble();
    final v = e.scoredEfficiency ?? e.sleepEfficiency;
    if (v != null) eff[k] = v;
    final s = parseWallClock(e.bedtime), w = parseWallClock(e.wakeTime);
    if (s != null && w != null && w.isAfter(s)) {
      bedIn[k] = clockFromNoon(s);
      bedOut[k] = clockFromNoon(w);
      inBed[k] = w.difference(s).inMinutes.toDouble();
    }
  }
  return PeriodSeries(
    score: score,
    quality: quality,
    mood: mood,
    sleep: sleep,
    deep: deep,
    efficiency: eff,
    bedIn: bedIn,
    bedOut: bedOut,
    inBed: inBed,
  );
}

/// 中位分數 → 等級，照後端給的切點（高到低）。沒有切點（舊版後端）→ null，畫面不換星星。
String? qualityFor(double? score, List<QualityBand> bands) {
  if (score == null || bands.isEmpty) return null;
  final sorted = [...bands]..sort((a, b) => b.min.compareTo(a.min));
  for (final b in sorted) {
    if (score >= b.min) return b.quality;
  }
  return null;
}

/// 等級 → 幾顆星（只是換個畫法：等級本身是後端的）。不認得的 → 0。
int starsFor(String? quality) => switch (quality) {
      'Good' => 4,
      'Normal' => 3,
      'Poor' => 2,
      'Bad' => 1,
      _ => 0,
    };

/// 牆鐘時間字串 → DateTime（給測試與打包檔退回用）。
DateTime? wall(String? s) => parseWallClock(s);

/// 今天之後的日子（還沒到）：Month／Year 的格子畫空，不是「沒資料」。
bool isFuture(String dateKey, DateTime today) {
  final d = DateTime.tryParse(dateKey);
  return d != null && d.isAfter(_d(today));
}
