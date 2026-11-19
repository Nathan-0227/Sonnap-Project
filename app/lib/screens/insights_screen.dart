import 'package:flutter/material.dart';

import '../models/sleep_session.dart';
import '../services/bed_marks.dart';
import '../services/camera_insights.dart';
import '../services/game_service.dart';
import '../services/insights_periods.dart';
import '../services/key_value_store.dart';
import '../services/morning_rating.dart';
import '../services/morning_report.dart';
import '../services/pet_notes.dart';
import '../services/report_loader.dart';
import '../services/sleep_repository.dart';
import '../theme/report_style.dart';
import '../services/nightly_sync.dart';
import '../widgets/before_bed_apps.dart';
import '../widgets/challenges_sheet.dart';
import '../widgets/insights_period_view.dart';
import 'morning_report_screen.dart';

export '../services/insights_periods.dart'
    show
        InsightsPeriod,
        insightsRange,
        insightsShift,
        insightsLabel,
        insightsCanGoNext,
        insightsCanGoPrev;

/// Insights 頁（2026-11-19 改版）：頂端 Day／Week／Month／Year，底下「‹ 期間 ›」。
///
/// - **Day**＝早晨報告本體，跟起床後看到的是同一個元件（`MorningReportScreen.fromLoader`，
///   embedded：不畫經驗條、關閉鈕、底部兩顆按鈕）。🔴 notes 一律 generate=false：
///   AI 只在起床流程、自評之後生成，Insights 打開絕不花額度。
/// - Week／Month／Year：上面一塊心情、下面鏡像格子（`widgets/insights_period_view.dart`）。
/// - 偵測就寢與上傳不在這一頁：在 App 層的 [NightlySync]（舊 Insights 頁拆掉時搬出去的），
///   這一頁只讀它的挑戰與睡前 App。
class InsightsScreen extends StatefulWidget {
  /// 偵測就寢＋上傳＋挑戰（App 層在跑，這裡只讀結果）。null＝測試或沒有。
  final NightlySync? nightly;

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
    this.nightly,
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
  late DateTime _anchor = dateOnly(widget.clock());

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

  /// Week／Month／Year 的逐夜數字。null＝還在讀。
  PeriodSeries? _series;

  /// false＝連不到後端，只有打包檔（Month／Year 照實說要後端）。
  bool _online = false;

  @override
  void initState() {
    super.initState();
    _loadSeries();
  }

  Future<void> _loadSeries() async {
    final cam = await _loader.camera();
    PeriodSeries series;
    var online = false;
    if (cam?.status == CameraInsightsStatus.ok) {
      series = PeriodSeries.fromInsights(cam!);
      online = true;
    } else {
      try {
        series = periodSeriesFromBundled(await _session);
      } catch (_) {
        series = const PeriodSeries();
      }
    }
    var first = series.firstDate;
    try {
      // 打包檔可能比後端多幾晚舊的（後端只回最近一年）
      final bundledFirst = periodSeriesFromBundled(await _session).firstDate;
      if (bundledFirst != null && (first == null || bundledFirst.isBefore(first))) {
        first = bundledFirst;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _series = series;
      _online = online;
      _first = first;
    });
  }

  void _go(int step) => setState(() {
        _anchor = insightsShift(_period, _anchor, step);
        // 不翻到未來
        final today = dateOnly(widget.clock());
        if (_anchor.isAfter(today)) _anchor = today;
      });

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(widget.clock());
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
                child: ListenableBuilder(
                  listenable: widget.nightly ?? _noNightly,
                  builder: (context, _) => _period == InsightsPeriod.day
                      ? _day(today)
                      : _periodView(today),
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
                      insightsPeriodLabels[p]!,
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

  /// 挑戰那一行：四個分頁共用、不屬於任何一個期間。拿不到就不出現。
  Widget? _challengesRow() {
    final r = widget.nightly?.challenges;
    return ChallengesRow.shows(r) ? ChallengesRow(result: r) : null;
  }

  /// 睡前 App 只有「最近一次放下手機」那一晚有（手機只留得住那一段的事件），
  /// 所以只在那一晚的 Phone down 頁出現；別的晚上不放，不拿這一晚的冒充。
  Widget? _beforeBedFor(String date) {
    final pre = widget.nightly?.preBed;
    final at = pre?.lightsOutAt;
    if (pre == null || at == null || !pre.hasData) return null;
    if (reportDateKey(nightDateOf(at)) != date) return null;
    return BeforeBedApps(preBed: pre);
  }

  Widget _periodView(DateTime today) {
    final series = _series;
    if (series == null) {
      return const Center(
        child: CircularProgressIndicator(color: ReportColors.muted),
      );
    }
    return InsightsPeriodView(
      series: series,
      period: _period,
      anchor: _anchor,
      today: today,
      online: _online,
      footer: _challengesRow(),
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
          footer: _challengesRow(),
          phoneDownFooter: _beforeBedFor(date),
        );
      },
    );
  }
}

/// 沒給 [InsightsScreen.nightly] 時給 ListenableBuilder 的空殼。
final _noNightly = ChangeNotifier();
