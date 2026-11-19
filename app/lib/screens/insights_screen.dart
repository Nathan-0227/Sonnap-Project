import 'package:flutter/material.dart';

import '../models/sleep_session.dart';
import '../services/bed_marks.dart';
import '../services/camera_insights.dart';
import '../services/game_service.dart';
import '../services/key_value_store.dart';
import '../services/morning_rating.dart';
import '../services/morning_report.dart';
import '../services/pet_notes.dart';
import '../services/report_loader.dart';
import '../services/sleep_repository.dart';
import '../theme/report_style.dart';
import 'morning_report_screen.dart';

/// Insights 的四個期間（2026-11-19 grill 定案）。
enum InsightsPeriod { day, week, month, year }

const _periodLabels = {
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

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// [anchor] 落在的那一段期間：[start, end]（都含）。
/// Week＝週一到週日的日曆週；Month、Year＝日曆月、日曆年（使用者定，不用「最近 N 天」）。
({DateTime start, DateTime end}) insightsRange(
    InsightsPeriod period, DateTime anchor) {
  final d = _dateOnly(anchor);
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
  final d = _dateOnly(anchor);
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
    insightsRange(period, anchor).end.isBefore(_dateOnly(today));

/// 左箭頭到「帳號有資料的第一天」那一期為止。[first] 是 null（還不知道）就不擋。
bool insightsCanGoPrev(
        InsightsPeriod period, DateTime anchor, DateTime? first) =>
    first == null || insightsRange(period, anchor).start.isAfter(_dateOnly(first));

/// Insights 頁（2026-11-19 改版）：頂端 Day／Week／Month／Year，底下「‹ 期間 ›」。
///
/// - **Day**＝早晨報告本體，跟起床後看到的是同一個元件（`MorningReportScreen.fromLoader`，
///   embedded：不畫經驗條、關閉鈕、底部兩顆按鈕）。🔴 notes 一律 generate=false：
///   AI 只在起床流程、自評之後生成，Insights 打開絕不花額度。
/// - Week／Month／Year：鏡像格子在下一步（同一條分支）。在那之前 Week 先放舊的卡片，
///   ⚠️ 舊頁 [legacy] **一定要一直掛著**（IndexedStack）：它背後負責偵測就寢時刻、
///   上傳 `POST /nightly`、補傳漏掉的夜晚，不能因為使用者停在 Day 就沒跑。
class InsightsScreen extends StatefulWidget {
  /// 舊的 Insights 頁（含上傳邏輯）。
  final Widget legacy;

  final SleepRepository repository;
  final BedMarkStore bedMarks;
  final CameraInsightsSource? cameraInsights;
  final MorningReportSource? morningReport;
  final GameService? game;

  /// 睡眠目標（分鐘）＝轉盤上「就寢→起床」的長度。
  final Future<int> Function() goalMinutes;

  final DateTime Function() clock;

  const InsightsScreen({
    super.key,
    required this.legacy,
    required this.repository,
    required this.goalMinutes,
    this.bedMarks = const BedMarkStore(PlatformKeyValueStore()),
    this.cameraInsights,
    this.morningReport,
    this.game,
    this.clock = DateTime.now,
  });

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  InsightsPeriod _period = InsightsPeriod.day;

  /// 正在看的那一天（W/M/Y 用它所在的那一期）。預設今天＝昨晚那一晚
  /// （報告的日期是起床那天）；手錶還沒到時報告自己會寫 Waiting for your watch data。
  late DateTime _anchor = _dateOnly(widget.clock());

  /// 帳號有資料的第一晚（打包檔或後端的歷史，取較早的）。左箭頭到這一期為止。
  DateTime? _first;

  late final MorningRatingStore _ratings = MorningRatingStore(widget.bedMarks.store);
  late final NotesReadStore _notesReads = NotesReadStore(widget.bedMarks.store);

  late final ReportLoader _loader = ReportLoader(
    clock: widget.clock,
    bedMarks: widget.bedMarks,
    ratings: _ratings,
    cameraInsights: widget.cameraInsights,
    morningReport: widget.morningReport,
    game: widget.game,
    session: () => _session,
    goalMinutes: widget.goalMinutes,
  );

  late final Future<SleepSession> _session = widget.repository.load();

  final Map<String, Future<ReportInputs>> _inputs = {};

  @override
  void initState() {
    super.initState();
    _findFirst();
  }

  Future<void> _findFirst() async {
    DateTime? first;
    void consider(String? date) {
      final d = date == null ? null : DateTime.tryParse(date);
      if (d != null && (first == null || d.isBefore(first!))) first = d;
    }

    try {
      final s = await _session;
      for (final e in s.history) {
        consider(e.date);
      }
    } catch (_) {}
    final cam = await _loader.camera();
    for (final n in cam?.nights ?? const <CameraNight>[]) {
      consider(n.date);
    }
    for (final d in cam?.phoneDowns.keys ?? const <String>[]) {
      consider(d);
    }
    if (mounted && first != null) setState(() => _first = first);
  }

  void _go(int step) => setState(() {
        _anchor = insightsShift(_period, _anchor, step);
        // 不翻到未來
        final today = _dateOnly(widget.clock());
        if (_anchor.isAfter(today)) _anchor = today;
      });

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(widget.clock());
    return ReportFont(
      child: Scaffold(
        backgroundColor: ReportColors.bgTop,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Insights',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: _tabs(),
              ),
              _nav(today),
              Expanded(
                child: IndexedStack(
                  index: switch (_period) {
                    InsightsPeriod.day => 0,
                    InsightsPeriod.week => 1,
                    _ => 2,
                  },
                  children: [
                    _day(today),
                    // ⚠️ 一直掛著（見 class 註解）
                    widget.legacy,
                    const _ComingNext(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabs() {
    return Container(
      key: const Key('insights-tabs'),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final p in InsightsPeriod.values)
            Expanded(
              child: Semantics(
                selected: p == _period,
                button: true,
                child: InkWell(
                  key: Key('insights-tab-${p.name}'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _period = p),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p == _period
                          ? const Color(0xFF8B7CF6)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _periodLabels[p]!,
                      style: TextStyle(
                        color: p == _period
                            ? Colors.white
                            : ReportColors.muted,
                        fontSize: 14,
                        fontWeight:
                            p == _period ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _nav(DateTime today) {
    final canPrev = insightsCanGoPrev(_period, _anchor, _first);
    final canNext = insightsCanGoNext(_period, _anchor, today);
    Widget arrow(IconData icon, String tip, bool enabled, int step, Key key) =>
        SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            key: key,
            tooltip: tip,
            onPressed: enabled ? () => _go(step) : null,
            icon: Icon(icon),
            color: Colors.white,
            disabledColor: Colors.white24,
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          arrow(Icons.chevron_left_rounded, 'Previous', canPrev, -1,
              const Key('insights-prev')),
          Expanded(
            child: Text(
              insightsLabel(_period, _anchor),
              key: const Key('insights-period-label'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          arrow(Icons.chevron_right_rounded, 'Next', canNext, 1,
              const Key('insights-next')),
        ],
      ),
    );
  }

  Widget _day(DateTime today) {
    final date = reportDateKey(_anchor);
    final inputs = _inputs[date] ??= _loader.inputs(date);
    return FutureBuilder<ReportInputs>(
      key: ValueKey('insights-day-$date'),
      future: inputs,
      builder: (context, snap) {
        final i = snap.data;
        if (i == null) {
          return const Center(
            child: CircularProgressIndicator(color: ReportColors.muted),
          );
        }
        return MorningReportScreen.fromLoader(
          _loader,
          key: ValueKey('insights-report-$date'),
          embedded: true,
          initial: _loader.initial(date, i),
          load: () => _loader.fetch(date, i),
          // 🔴 Insights 絕不觸發 AI（同首頁）
          loadSummary: _loader.notesLoader(date, allowGenerate: false),
          // 今天早上起床的那一晚才說「在等手錶資料」
          pending: date == reportDateKey(today),
          isNotesRead: (version) => _notesReads.isRead(date, version),
          onNotesOpened: (version) => _notesReads.markRead(date, version),
        );
      },
    );
  }
}

class _ComingNext extends StatelessWidget {
  const _ComingNext();

  @override
  Widget build(BuildContext context) => const Center(
        child: Text(
          'Coming next',
          key: Key('insights-coming-next'),
          style: TextStyle(color: ReportColors.muted, fontSize: 14),
        ),
      );
}
