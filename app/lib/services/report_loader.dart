import '../models/sleep_session.dart';
import '../models/wall_clock.dart';
import '../widgets/phone_week_sheet.dart';
import 'bed_marks.dart';
import 'camera_insights.dart';
import 'game_service.dart';
import 'morning_rating.dart';
import 'morning_report.dart';
import 'night_compare.dart';

/// 組一晚的早晨報告要用的東西：首頁（起床流程、點心情列）與 Insights 的 Day 分頁共用。
///
/// ⚠️ 只有這一份。2026-11-19 以前這段寫在首頁裡；Insights 改版要在別處畫同一份報告，
/// 複製一份的話兩邊遲早對不上（例如一邊多接了一個詳細頁的資料，另一邊點了沒反應）。
class ReportLoader {
  final BedMarkStore bedMarks;
  final MorningRatingStore ratings;
  final CameraInsightsSource? cameraInsights;
  final MorningReportSource? morningReport;
  final GameService? game;

  /// 打包檔那一份（首頁已經讀好的）。
  final Future<SleepSession> Function() session;

  /// 睡眠目標＝轉盤上「就寢→起床」的長度（使用者定，預設 8 小時）。
  final Future<int> Function() goalMinutes;

  /// 呼叫端手上已經有的攝影機結果（首頁一打開就讀了）。沒有就自己讀一次、記住。
  final CameraInsightsResult? Function()? cachedCamera;

  /// 呼叫端手上已經有的遊戲狀態（先畫的那一版用；問到後端之前 XP 照樣畫得出來）。
  final GameState? Function()? cachedGame;

  final DateTime Function() clock;

  ReportLoader({
    required this.clock,
    required this.bedMarks,
    required this.ratings,
    required this.session,
    required this.goalMinutes,
    this.cameraInsights,
    this.morningReport,
    this.game,
    this.cachedCamera,
    this.cachedGame,
  });

  CameraInsightsResult? _ownCamera;
  Future<CameraInsightsResult>? _cameraLoading;

  /// 手上已經有的攝影機結果（不去讀）。
  CameraInsightsResult? get knownCamera => cachedCamera?.call() ?? _ownCamera;

  /// 攝影機結果；手上沒有就讀一次（同時只讀一次）。沒有後端、讀不到 → null。
  Future<CameraInsightsResult?> camera() async {
    final known = knownCamera;
    if (known != null) return known;
    final source = cameraInsights;
    if (source == null) return null;
    try {
      final result = await (_cameraLoading ??= source.load());
      _ownCamera = result;
      return result;
    } catch (_) {
      return null;
    } finally {
      _cameraLoading = null;
    }
  }

  Future<CameraInsightsResult?> _okCamera() async {
    final c = await camera();
    return c?.status == CameraInsightsStatus.ok ? c : null;
  }

  /// 組報告要用的、手機上已經有的東西。
  Future<ReportInputs> inputs(String date) async {
    final marks = await bedMarks.read(now: clock());
    final localRating = await ratings.read(date);
    CameraNight? cam;
    for (final n in knownCamera?.nights ?? const <CameraNight>[]) {
      if (n.date == date) cam = n;
    }
    SleepSession? s;
    try {
      s = await session();
    } catch (_) {
      s = null;
    }
    return ReportInputs(
      marks: marks,
      localRating: localRating,
      camera: cam,
      session: s,
      goalMinutes: await goalMinutes(),
    );
  }

  /// 先畫手上已經有的（XP 用呼叫端已經讀到的那一份）。
  MorningReport initial(String date, ReportInputs i) =>
      buildMorningReport(date: date, marks: i.marks).withExtras(
        game: cachedGame?.call(),
        goalMinutes: i.goalMinutes,
        camera: i.camera,
        localRating: i.localRating,
        ratingIsFresh: i.ratingIsFresh,
      );

  /// 問後端之後的完整版。[early] 是已經先發出去的請求（起床流程）。
  Future<MorningReport> fetch(String date, ReportInputs i,
      [ReportFetch? early]) async {
    final homeF = early?.home ?? morningReport?.fetchNight(date);
    final gameF = early?.game ?? game?.fetchGame();
    final home = await homeF;
    final g = (await gameF)?.value ?? cachedGame?.call();
    return buildMorningReport(
      date: date,
      marks: i.marks,
      home: home,
      session: i.session,
    ).withExtras(
      game: g,
      goalMinutes: i.goalMinutes,
      camera: i.camera,
      localRating: i.localRating,
      ratingIsFresh: i.ratingIsFresh,
    );
  }

  /// 寵物 notes。[allowGenerate] 是 false 時一律 generate=false——
  /// 🔴 Insights 與首頁絕不觸發 AI；生成只在起床流程（自評之後）。
  NotesLoader? notesLoader(String date, {required bool allowGenerate}) {
    final source = morningReport;
    if (source == null) return null;
    return ({bool generate = true}) =>
        source.fetchSummary(date, generate: allowGenerate && generate);
  }

  // ── 各詳細頁的一週資料 ─────────────────────────────────────

  /// Time in bed 一週圖：按鈕（後端 /insights，連不到就沒有）＋手錶入睡→醒來（打包檔）。
  Future<
    ({
      Map<String, (DateTime?, DateTime?)> buttons,
      Map<String, (DateTime?, DateTime?)> watch,
    })
  >
  bedTimes() async {
    final watch = <String, (DateTime?, DateTime?)>{};
    try {
      for (final e in (await session()).history) {
        watch[e.date] = (parseWallClock(e.bedtime), parseWallClock(e.wakeTime));
      }
    } catch (_) {}
    final cam = await camera();
    // 手錶的入睡→醒來：後端的比打包檔新，有就蓋過去（「躺多久才睡著」要這一晚的入睡）
    return (
      buttons: cam?.bedButtons ?? const {},
      watch: {...watch, ...?cam?.watchSleep},
    );
  }

  Future<List<NightValue>> sleepSeries() async =>
      sleepMinutesSeries((await session()).history);

  Future<Map<String, PhoneDown>> phoneDowns() async =>
      (await camera())?.phoneDowns ?? const {};

  Future<Map<String, double>?> awakeMinutes() async =>
      (await _okCamera())?.awakeMinutes;

  Future<Map<String, int>?> awakeCounts() async =>
      (await _okCamera())?.awakeCounts;

  Future<Map<String, EfficiencyNight>?> efficiencyNights() async =>
      (await _okCamera())?.efficiencyNights;

  Future<Map<String, SleepHeartRate>?> sleepHeartRates() async =>
      (await _okCamera())?.sleepHeartRates;

  Future<List<CameraNight>?> cameraNights() async =>
      (await _okCamera())?.nights;
}

/// 每晚睡了幾分鐘（首頁 Sleep 小卡與報告 Total sleep 的一週圖共用）。沒值的晚上不放進來。
List<NightValue> sleepMinutesSeries(List<HistoryEntry> history) => [
  for (final e in history)
    if (e.sleepDurationHours != null)
      NightValue(e.date, e.sleepDurationHours! * 60),
];

class ReportInputs {
  final BedMarks marks;
  final MorningRating? localRating;
  final CameraNight? camera;
  final SleepSession? session;
  final int goalMinutes;

  /// localRating 是起床流程裡剛填的（見 MorningReport.withExtras）。
  final bool ratingIsFresh;

  const ReportInputs({
    required this.marks,
    required this.localRating,
    required this.camera,
    required this.session,
    required this.goalMinutes,
    this.ratingIsFresh = false,
  });

  ReportInputs withFreshRating(MorningRating rating) => ReportInputs(
        marks: marks,
        localRating: rating,
        camera: camera,
        session: session,
        goalMinutes: goalMinutes,
        ratingIsFresh: true,
      );
}

/// 起床流程在動畫一開始就先發出去的請求。
class ReportFetch {
  final Future<Map<String, dynamic>?>? home;
  final Future<GameResult<GameState>>? game;

  const ReportFetch({this.home, this.game});
}
