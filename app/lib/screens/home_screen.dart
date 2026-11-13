import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/sleep_session.dart';
import '../services/account_service.dart';
import '../services/sleep_sounds.dart';
import '../services/alarm.dart';
import '../services/bed_marks.dart';
import '../services/camera_insights.dart';
import '../services/game_service.dart';
import '../services/home_mode.dart';
import '../services/key_value_store.dart';
import '../services/night_compare.dart';
import '../services/sleep_repository.dart';
import '../theme/sonnap_colors.dart';
import '../widgets/bedtime_urgency.dart';
import '../widgets/countdown_border.dart';
import '../widgets/dream_diary.dart';
import '../widgets/home_pet.dart';
import '../widgets/info_tile.dart';
import '../widgets/night_sky_effects.dart';
import '../widgets/sleep_dial.dart';
import '../widgets/sleep_schedule_sheet.dart';
import '../widgets/sleep_stages_card.dart';
import '../services/morning_rating.dart';
import '../services/morning_report.dart';
import 'morning_report_screen.dart';
import 'report_loading_screen.dart';
import 'rested_screen.dart';
import 'wake_up_screen.dart';
import '../widgets/week_mood_strip.dart';
import 'closet_screen.dart';
import 'rewards_screen.dart';
import 'sleep_mode_screen.dart';

/// 首頁。資料來自 `assets/data/app_payload.json`（由 Python pipeline 產生）。
///
/// 這裡刻意**不對數據做任何判斷**——分數好不好、該顯示哪種心情、該說哪句話，
/// 全部由後端算好放在 payload 裡。專案原則是「Python 判斷，Dart 只負責畫」，
/// 這樣所有判斷都可以追溯到有文獻依據的那一層。
///
/// 版面（2026-11-12 使用者定案：一頁全放，不分早晚版）：
/// 問候 → 寵物（心情標籤）→ 一週心情列 → 分數 → 就寢時間列 → 上床／下床
/// → 四張數據卡。按了 Start sleep 照樣進全螢幕睡覺畫面。
class HomeScreen extends StatefulWidget {
  /// 帳號的暱稱。沒有帳號時是 [kFallbackDisplayName]。
  final String displayName;

  final SleepRepository repository;

  /// 目標就寢時間。**擁有者是 `main.dart` 的 `_MainPageState`**，這裡只是顯示
  /// 與往上回報。⚠️ 不要在這個畫面另存一份當「真的值」——Settings 也顯示同一個值。
  final TimeOfDay targetBedtime;
  final bool reminderOn;

  /// 使用者在首頁改了就寢時間時往上通知，由 `main.dart` 統一更新。
  final ValueChanged<TimeOfDay>? onBedtimeChanged;
  final ValueChanged<bool>? onReminderChanged;

  /// 上床／下床標記的儲存。可注入，測試才不必依賴真的原生 channel。
  final BedMarkStore bedMarks;

  /// 遊戲化層（XP、等級、衣櫃、獎勵）。null = 這支 build 沒有後端。
  final GameService? game;

  /// 攝影機那張卡的資料來源。null = 這支 build 沒有後端。
  final CameraInsightsSource? cameraInsights;

  /// 現在幾點。可注入：就寢時間列與睡覺畫面都看時間，測試要釘住才穩。
  final DateTime Function() clock;

  /// 鬧鐘的原生端（可注入，測試換成假的）。設定存在 [bedMarks] 同一個儲存裡。
  final AlarmScheduler alarmScheduler;

  /// 助眠聲音的原生端（可注入，測試換成假的）。選擇存在 [bedMarks] 同一個儲存裡。
  final SleepSoundPlayer soundPlayer;

  /// 早晨報告讀 `/home?date=` 的來源。null = 這支 build 沒有後端，
  /// 報告改用打包檔裡那一晚。
  final MorningReportSource? morningReport;

  /// 起床自評送後端（`POST /rested`）。null = 這支 build 沒有後端，只存在手機上。
  final RestedSender? rested;

  /// 早晨報告的 View sleep insights：切到 Insights 分頁。null = 不放那一列。
  final VoidCallback? onOpenInsights;

  const HomeScreen({
    super.key,
    this.bedMarks = const BedMarkStore(PlatformKeyValueStore()),
    this.alarmScheduler = const PlatformAlarmScheduler(),
    this.soundPlayer = const PlatformSleepSoundPlayer(),
    this.game,
    this.cameraInsights,
    this.morningReport,
    this.rested,
    this.onOpenInsights,
    this.clock = DateTime.now,
    this.displayName = kFallbackDisplayName,
    this.repository = const AssetSleepRepository(),
    this.targetBedtime = const TimeOfDay(hour: 23, minute: 30),
    this.reminderOn = true,
    this.onBedtimeChanged,
    this.onReminderChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// 整頁的背景圖（原創，2026-11-12 由使用者以 prompt 生成，左右翻轉讓月亮避開問候文字）。
const String kHomeBackgroundAsset = 'assets/backgrounds/night_sky.png';

/// 接在下面的湖面（原創，同樣左右翻轉，倒影與月亮在同一側）。
const String kHomeBackgroundLowerAsset = 'assets/backgrounds/night_lake.png';

/// 背景圖的寬高比（853 × 1844）。
const double kHomeBackgroundAspect = 853 / 1844;

/// 山頂在圖片高度的哪個位置（實測 0.552）。寵物的腳要踩在這裡。
const double kHomeBackgroundCrest = 0.552;

/// 圖片最下緣的顏色，圖畫完之後頁面用它接下去。
const Color kHomeBackgroundBottom = Color(0xFF090F4F);

/// 寵物的大小。
const double kHomePetSize = 230;

/// 問候＋時鐘＋倒數圓環那一塊的高度。
const double kHomeHeaderHeight = 230;

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  /// 在 initState 建立而不是在 build 裡——放 build 的話每次重繪都會重讀檔案。
  late Future<SleepSession> _sessionFuture;

  /// `GET /game` 與 `GET /closet` 的結果。⚠️ 每一格都照抄後端。
  GameResult<GameState>? _game;
  GameResult<ClosetState>? _closet;

  /// 攝影機那張卡。null = 還沒載入或沒有後端。
  CameraInsightsResult? _camera;

  /// 本機的上床／下床標記。決定要不要進睡覺畫面。
  BedMarks _marks = BedMarks.none;

  /// 首頁要不要出現「Forgot to tap last night? Add times」。
  bool _needsBackfill = false;

  /// 起床自評存在跟上床標記同一個儲存裡。
  late final MorningRatingStore _ratings =
      MorningRatingStore(widget.bedMarks.store);

  /// 夢境看過了沒（小狗旁的對話框縮成 💭 用），也存在同一個儲存裡。
  late final DreamReadStore _dreamReads = DreamReadStore(widget.bedMarks.store);

  /// 已經看過的那一晚夢境的日期。跟最新那一晚相同 → 對話框縮成 💭。
  String? _dreamReadDate;

  /// 起床 6 小時內、還沒填自評 → 首頁出現補填小卡（使用者定）。null = 不出現。
  BedMarks? _restedMakeUp;

  /// 畫面上顯示的目標就寢時間。在這頁改了之後立刻反映，同時往上回報；
  /// 上層傳來新值時以上層為準（見 didUpdateWidget）。
  late TimeOfDay _bedtime;

  /// 睡覺畫面開著時不要再推一次。
  bool _sleepRouteOpen = false;

  /// 倒數要跟著時間走，所以定時重畫。
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bedtime = widget.targetBedtime;
    _sessionFuture = widget.repository.load();
    _loadDreamRead();
    _loadGame();
    _loadCamera();
    _loadMarks();
    // 之前連不到後端、沒送出去的自評，這次補送
    final rested = widget.rested;
    if (rested != null) _ratings.retryUnsent(rested);
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetBedtime != widget.targetBedtime) {
      _bedtime = widget.targetBedtime;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 半夜打開 App：直接回到睡覺畫面（還沒按下床、未滿 14 小時）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadMarks();
  }

  Future<void> _loadMarks() async {
    final marks = await widget.bedMarks.read(now: widget.clock());
    final needsBackfill = await widget.bedMarks.needsBackfill(widget.clock());
    final makeUp = await _restedMakeUpFor(widget.clock());
    if (!mounted) return;
    setState(() {
      _marks = marks;
      _needsBackfill = needsBackfill;
      _restedMakeUp = makeUp;
    });
    _maybeOpenSleepMode();
  }

  /// 補昨晚（2026-11-12）：只補缺的那一個。昨晚有按上床就鎖月亮；
  /// 預設值用目標就寢與轉盤上的起床時間，**不用手機偵測的時間**（使用者定）。
  Future<void> _backfillLastNight() async {
    final now = widget.clock();
    final last = await widget.bedMarks.lastNight(now);
    final tappedStart = last.startAt;
    final bed = tappedStart != null
        ? TimeOfDay.fromDateTime(tappedStart)
        : _bedtime;
    final wake = await _alarmSettings.wakeTime(_bedtime);
    if (!mounted) return;
    final result = await showBedTimesSheet(
      context,
      title: 'Last night',
      bedtime: bed,
      wake: wake,
      bedLocked: tappedStart != null,
    );
    if (result == null || !mounted) return;
    final end = lastNightWake(now, result.wake.hour, result.wake.minute);
    final start = tappedStart ??
        end.subtract(sleepSpan(result.bedtime, result.wake));
    final problem = recalledTimesProblem(start, end, now);
    if (problem != null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(problem)),
      );
      return;
    }
    await widget.bedMarks.backfillLastNight(now, start: start, end: end);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text("Added last night's times.")),
    );
    await _loadMarks();
  }

  void _maybeOpenSleepMode() {
    if (_sleepRouteOpen) return;
    if (!isSleeping(widget.clock(), _marks)) return;
    final startAt = _marks.startAt!;
    _sleepRouteOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      final ended = Completer<DateTime?>();
      final sleepRoute = _NoExitAnimationRoute<void>(
        fullscreenDialog: true,
        builder: (_) => SleepModeScreen(
          alarm: _alarm,
          sounds: SleepSoundsController(
            settings: SleepSoundSettings(widget.bedMarks.store),
            player: widget.soundPlayer,
          ),
          store: widget.bedMarks,
          startAt: startAt,
          clock: widget.clock,
          onEnded: (end) {
            if (!ended.isCompleted) ended.complete(end);
          },
        ),
      );
      // Cancel／返回鍵是睡覺畫面自己關掉的 → null
      navigator.push<void>(sleepRoute).then((_) {
        if (!ended.isCompleted) ended.complete(null);
      });
      final end = await ended.future;
      if (!mounted) return;
      if (end == null) {
        _sleepRouteOpen = false;
        await _loadMarks();
        return;
      }
      // 滑完 Slide to get up（或 I already got up）→ 起床動畫 → 先問睡得怎樣
      // （看到分數之前）→ 等待畫面（按 View sleep report）→ 昨晚的報告。
      // 按 Skip 也照樣往下走。
      // ⚠️ 從睡覺畫面到報告，中間**一格都不能露出首頁**：首頁上有分數卡，
      //    而自評卡要在「看到分數之前」問（2026-11-13 實機錄影抓到露出半秒）。
      //    所以每一步都是「新的畫面蓋上去之後，才把底下那一頁收掉」：
      //    睡覺畫面 → 起床動畫 → 自評卡 → 等待畫面 → 報告。
      //    睡覺畫面也不自己關（onEnded）：讀手機儲存要好幾格，先關的話那幾格就是首頁。
      try {
        final date = reportDateKey(nightDateOf(startAt));
        // 分數那份在動畫一開始就去抓，填完自評多半已經回來了。
        // AI 那段讀起床自評，要等自評送出之後才去要（等待畫面打開時）。
        final early = _ReportFetch(
          home: widget.morningReport?.fetchNight(date),
          game: widget.game?.fetchGame(),
        );
        final wakeRoute = await _playWakeUp(end, below: sleepRoute);
        if (!mounted) return;
        await _wakeUpFlow(date, end, early,
            cover: wakeRoute ?? sleepRoute, instant: wakeRoute == null);
      } finally {
        // 沒走完（例如畫面被關掉）也要把睡覺畫面收掉
        if (sleepRoute.isActive) navigator.removeRoute(sleepRoute);
        _sleepRouteOpen = false;
        if (mounted) await _loadMarks();
      }
    });
  }

  /// 起床動畫之後：自評卡 → 等待畫面 → 報告（見上面的 ⚠️）。
  ///
  /// [cover]：目前蓋在最上面的那一頁（起床動畫；沒播動畫時是睡覺畫面），
  /// 自評卡蓋上去之後才收掉。[instant]：沒播動畫時自評卡直接出現、不從下面滑上來。
  Future<void> _wakeUpFlow(String date, DateTime? wakeAt, _ReportFetch early,
      {required Route<void> cover, required bool instant}) async {
    final navigator = Navigator.of(context);
    void removeWhenCovered(ModalRoute<dynamic> top, Route<dynamic>? below) {
      if (below == null) return;
      void listener(AnimationStatus s) {
        if (s != AnimationStatus.completed) return;
        top.animation?.removeStatusListener(listener);
        if (below.isActive) navigator.removeRoute(below);
      }

      top.animation?.addStatusListener(listener);
    }

    // ① 自評卡：沒有起床動畫（減少動態效果）時直接出現，不從下面滑上來——
    //    滑的那一段會露出底下的首頁。
    final rated = Completer<void>();
    MorningRating? justRated;
    Widget restedBuilder(BuildContext _) => RestedScreen(
          date: date,
          wakeAt: wakeAt,
          store: _ratings,
          sender: widget.rested,
          clock: widget.clock,
          onDone: (rating) {
            justRated = rating;
            if (!rated.isCompleted) rated.complete();
          },
        );
    final PageRoute<void> restedRoute = instant
        ? PageRouteBuilder<void>(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (context, _, _) => restedBuilder(context),
          )
        : MaterialPageRoute<void>(fullscreenDialog: true, builder: restedBuilder);
    var leaving = false; // 是我們自己收掉的，不是使用者按返回
    navigator.push<void>(restedRoute).then((_) {
      if (!leaving && !rated.isCompleted) rated.complete(); // 按返回鍵＝Skip
    });
    removeWhenCovered(restedRoute, cover);
    await rated.future;
    if (!mounted) return;
    // 自評卡還沒滑完就按了 Skip：底下那一頁也要收
    if (cover.isActive) navigator.removeRoute(cover);

    // ② 等待畫面：瞬間蓋在自評卡上，再收掉自評卡
    var inputs = await _reportInputs(date); // 這時才讀得到剛存的自評
    // 剛填的那一份比動畫一開始就抓的後端資料新，要蓋過它（Skip 就照一般規則）
    if (justRated != null) inputs = inputs.withFreshRating(justRated!);
    if (!mounted) return;
    final initial = _initialReport(date, inputs);
    final reportF = _fetchReport(date, inputs, early)
        .catchError((Object _) => initial);
    String? mood;
    try {
      mood = (await _sessionFuture).status.petMood;
    } catch (_) {
      mood = null;
    }
    if (!mounted) return;
    final source = widget.morningReport;
    final finished = Completer<String?>();
    var viewing = false;
    late final PageRoute<void> loadingRoute;
    loadingRoute = PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => ReportLoadingScreen(
        report: reportF,
        fallback: initial,
        mood: mood,
        loadSummary: source == null ? null : () => source.fetchSummary(date),
        onClose: () => navigator.removeRoute(loadingRoute),
        onView: (prepared) async {
          if (viewing) return;
          viewing = true;
          // ③ 報告蓋上去之後才收掉等待畫面：關報告時直接回首頁
          final route = _reportRoute(
            date,
            initial: prepared.report,
            loadSummary: prepared.pendingSummary == null
                ? null
                : () => prepared.pendingSummary!,
          );
          final result = navigator.push<String>(route);
          removeWhenCovered(route, loadingRoute);
          final r = await result;
          if (loadingRoute.isActive) navigator.removeRoute(loadingRoute);
          if (!finished.isCompleted) finished.complete(r);
        },
      ),
    );
    navigator.push<void>(loadingRoute).then((_) {
      if (!viewing && !finished.isCompleted) finished.complete(null);
    });
    leaving = true;
    if (restedRoute.isActive) navigator.removeRoute(restedRoute);
    if (mounted) await _loadMarks();
    final result = await finished.future;
    if (result == kReportOpenInsights && mounted) widget.onOpenInsights?.call();
  }

  /// 起床動畫（GIF 或程式版，點一下跳過）。系統開「減少動態效果」就不播，回 null。
  /// 播完**不自己關掉**，回傳那個畫面，讓自評卡蓋上去之後再收（見上面的 ⚠️）。
  /// 小狗用首頁同一份心情（後端的 pet_mood），不自己挑。
  /// [below]：睡覺畫面。動畫畫出第一格之後才把它收掉。
  Future<Route<void>?> _playWakeUp(DateTime? wakeAt, {Route<void>? below}) async {
    if (!shouldPlayWakeUp(context)) return null;
    String? mood;
    try {
      mood = (await _sessionFuture).status.petMood;
    } catch (_) {
      mood = null;
    }
    if (!mounted) return null;
    final done = Completer<void>();
    final route = wakeUpRoute(
      mood: mood,
      wakeAt: wakeAt,
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );
    final navigator = Navigator.of(context);
    // 按返回鍵關掉也算播完
    navigator.push(route).then((_) {
      if (!done.isCompleted) done.complete();
    });
    if (below != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (below.isActive) navigator.removeRoute(below);
      });
    }
    await done.future;
    return route;
  }

  /// 起床 6 小時內、那一晚還沒填 → 回傳那一晚的標記（補填小卡用）。
  Future<BedMarks?> _restedMakeUpFor(DateTime now) async {
    final last = await widget.bedMarks.lastNight(now);
    final start = last.startAt;
    if (start == null || last.endAt == null) return null;
    final existing = await _ratings.read(reportDateKey(nightDateOf(start)));
    return showRestedMakeUp(wakeAt: last.endAt, now: now, existing: existing)
        ? last
        : null;
  }

  /// 首頁補填小卡的自評卡。回傳存下來的（Skip 是 null）。
  /// （起床流程不走這裡，見 [_wakeUpFlow]。）
  Future<MorningRating?> _askRested(String date, DateTime? wakeAt) async {
    final rating = await Navigator.of(context).push<MorningRating>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => RestedScreen(
          date: date,
          wakeAt: wakeAt,
          store: _ratings,
          sender: widget.rested,
          clock: widget.clock,
        ),
      ),
    );
    if (mounted) await _loadMarks();
    return rating;
  }

  /// 首頁補填小卡：填完直接看那一晚的報告。
  Future<void> _makeUpRested() async {
    final last = _restedMakeUp;
    if (last?.startAt == null) return;
    final date = reportDateKey(nightDateOf(last!.startAt!));
    final rating = await _askRested(date, last.endAt);
    if (rating != null && mounted) await _openReport(date);
  }

  /// 組報告要用的、手機上已經有的東西。
  Future<_ReportInputs> _reportInputs(String date) async {
    final marks = await widget.bedMarks.read(now: widget.clock());
    final localRating = await _ratings.read(date);
    CameraNight? camera;
    for (final n in _camera?.nights ?? const <CameraNight>[]) {
      if (n.date == date) camera = n;
    }
    SleepSession? session;
    try {
      session = await _sessionFuture;
    } catch (_) {
      session = null;
    }
    // 睡眠目標＝轉盤上「就寢→起床」的長度（使用者定，預設 8 小時）
    final wake = await _alarm.settings.wakeTime(_bedtime);
    return _ReportInputs(
      marks: marks,
      localRating: localRating,
      camera: camera,
      session: session,
      goalMinutes: sleepSpan(_bedtime, wake).inMinutes,
    );
  }

  /// 先畫手上已經有的（XP 用首頁已經讀到的那一份）。
  MorningReport _initialReport(String date, _ReportInputs i) =>
      buildMorningReport(date: date, marks: i.marks).withExtras(
        game: _game?.value,
        goalMinutes: i.goalMinutes,
        camera: i.camera,
        localRating: i.localRating,
        ratingIsFresh: i.ratingIsFresh,
      );

  /// 問後端之後的完整版。[early] 是已經先發出去的請求（起床流程）。
  Future<MorningReport> _fetchReport(String date, _ReportInputs i,
      [_ReportFetch? early]) async {
    final homeF = early?.home ?? widget.morningReport?.fetchNight(date);
    final gameF = early?.game ?? widget.game?.fetchGame();
    final home = await homeF;
    final game = (await gameF)?.value ?? _game?.value;
    return buildMorningReport(
      date: date,
      marks: i.marks,
      home: home,
      session: i.session,
    ).withExtras(
      game: game,
      goalMinutes: i.goalMinutes,
      camera: i.camera,
      localRating: i.localRating,
      ratingIsFresh: i.ratingIsFresh,
    );
  }

  PageRoute<String> _reportRoute(
    String date, {
    required MorningReport initial,
    Future<MorningReport> Function()? load,
    Future<Map<String, dynamic>?> Function()? loadSummary,
  }) =>
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (_) => MorningReportScreen(
          // 今天早上起床的那一晚才說「在等手錶資料」
          pending: date == reportDateKey(widget.clock()),
          canOpenInsights: widget.onOpenInsights != null,
          // 在報告裡看過夢 → 首頁的對話框也縮成 💭
          onDreamOpened: () {
            _dreamReads.markRead(date);
            if (mounted) setState(() => _dreamReadDate = date);
          },
          initial: initial,
          load: load,
          loadSummary: loadSummary,
        ),
      );

  /// 打開某一晚的早晨報告：先畫手機上已經有的，再去問後端。
  /// （首頁點某一天、補填自評之後；起床流程走 [_wakeUpFlow]，中間多一個等待畫面。）
  Future<void> _openReport(String date) async {
    final inputs = await _reportInputs(date);
    if (!mounted) return;
    final source = widget.morningReport;
    final result = await Navigator.of(context).push<String>(_reportRoute(
      date,
      initial: _initialReport(date, inputs),
      load: () => _fetchReport(date, inputs),
      loadSummary: source == null ? null : () => source.fetchSummary(date),
    ));
    if (result == kReportOpenInsights && mounted) widget.onOpenInsights?.call();
  }

  Future<void> _startSleep() async {
    final now = widget.clock();
    await widget.bedMarks.markStart(now);
    // 鬧鐘只在按了 Start Sleep 才排（使用者決定）。
    await _alarm.onStartSleep(now, _bedtime);
    await _loadMarks();
  }

  Future<void> _loadGame() async {
    final service = widget.game;
    if (service == null) return;
    final game = await service.fetchGame();
    final closet = await service.fetchCloset();
    if (!mounted) return;
    setState(() {
      _game = game;
      _closet = closet;
    });
  }

  Future<void> _loadCamera() async {
    final source = widget.cameraInsights;
    if (source == null) return;
    final result = await source.load();
    if (mounted) setState(() => _camera = result);
  }

  /// 沒有後端時老實講。⚠️ 不要沿用「will be available later」——
  /// 功能已經做好了，缺的是連線；講成「以後才有」會讓人以為沒做。
  void _showNeedsBackend(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "$feature needs the Sonnap backend. "
          "It works when the app is connected to the server.",
        ),
      ),
    );
  }

  Future<void> _openCloset() async {
    final service = widget.game;
    if (service == null) return _showNeedsBackend("Closet");
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ClosetScreen(service: service)));
    // 回來時重讀：剛換的衣服要出現在寵物身上。
    if (mounted) await _loadGame();
  }

  Future<void> _openRewards() async {
    final service = widget.game;
    if (service == null) return _showNeedsBackend("Rewards");
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => RewardsScreen(service: service)));
    if (mounted) await _loadGame();
  }

  AlarmSettingsStore get _alarmSettings =>
      AlarmSettingsStore(widget.bedMarks.store);

  AlarmController get _alarm => AlarmController(
    settings: _alarmSettings,
    scheduler: widget.alarmScheduler,
  );

  /// 點時鐘卡：滑出轉盤（就寢＋起床＋鬧鐘開關）。
  Future<void> _pickBedtime() async {
    final result = await showSleepScheduleSheet(
      context,
      bedtime: _bedtime,
      alarmSettings: _alarmSettings,
      scheduler: widget.alarmScheduler,
    );
    if (result == null || !mounted) return;
    if (result.bedtime != _bedtime) {
      setState(() => _bedtime = result.bedtime);
      widget.onBedtimeChanged?.call(result.bedtime);
    }
  }

  void _reload() {
    setState(() {
      _sessionFuture = widget.repository.load();
    });
    _loadDreamRead();
  }

  /// 有夢境的那一晚：打包檔最新那一晚（同早晨報告的判斷）。沒有夢境 → null。
  static String? _dreamDate(SleepSession s) =>
      s.aiContent.hasDream && s.history.isNotEmpty ? s.history.last.date : null;

  Future<void> _loadDreamRead() async {
    try {
      final date = _dreamDate(await _sessionFuture);
      if (date == null) return;
      final read = await _dreamReads.isRead(date);
      if (mounted && read) setState(() => _dreamReadDate = date);
    } catch (_) {
      // 讀不到 session 時本來就沒有對話框
    }
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("$feature will be available later.")),
    );
  }

  /// 夢境日記。
  ///
  /// ⚠️ 標題必須寫成「寵物的夢」——Garmin 完全沒有量測夢境內容，
  /// 寫成「你的夢」就是誤述資料支持的範圍。disclaimer 一併顯示。
  void _showDream(SleepSession session) {
    final ai = session.aiContent;
    final date = _dreamDate(session);
    if (!ai.hasDream || date == null) {
      _showComingSoon("Dream Diary");
      return;
    }
    showDreamDiary(
      context,
      text: ai.dreamSummary!,
      date: date,
      mood: session.history.last.petMood,
      disclaimer: session.disclaimer,
    );
    _dreamReads.markRead(date);
    setState(() => _dreamReadDate = date);
  }

  /// 點卡片跳出的彈窗：最近 7 晚的長條圖（當晚那根特別亮）、跟上一晚差多少，
  /// 效率與深睡另外附上後端的警語（2026-11-12 使用者定案：畫面上不放警語）。
  ///
  /// ⚠️ 警語文字只照抄 `scoring.composition.caveats`（唯一定義處是 `score_claim.py`），
  ///    Dart 一個字都不產生。後端沒給就不放。
  void _showMetricSheet({
    required SleepSession session,
    required String id,
    required String title,
    required List<NightValue> series,
    required String Function(double) format,
    String? caveatComponent,
  }) {
    final currentDate = session.history.lastOrNull?.date;
    String? caveat;
    if (caveatComponent != null) {
      for (final c in session.scoring.composition?.caveats ?? const []) {
        if (c.component == caveatComponent) caveat = c.text;
      }
    }
    final bars = currentDate == null
        ? const <NightValue>[]
        : lastNights(series, currentDate);
    final delta = currentDate == null
        ? null
        : compareWithPrevious(series, currentDate);
    final maxV = bars.fold<double>(0, (m, n) => n.value > m ? n.value : m);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1B2350),
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          key: Key('metric-sheet-$id'),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (delta != null) ...[
                const SizedBox(height: 6),
                Text(
                  deltaText(delta, format),
                  style: TextStyle(
                    color: deltaColor(delta),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (bars.isEmpty)
                const Text(
                  'No nights to compare yet.',
                  style: TextStyle(color: Colors.white54),
                )
              else
                SizedBox(
                  height: 150,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final n in bars)
                        Expanded(
                          child: _bar(
                            n,
                            maxV,
                            isCurrent: n.date == currentDate,
                            format: format,
                          ),
                        ),
                    ],
                  ),
                ),
              if (caveat != null) ...[
                const SizedBox(height: 18),
                Text(
                  caveat,
                  key: Key('caveat-$caveatComponent'),
                  style: const TextStyle(color: Colors.white70, height: 1.5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 長條圖的一根：上面是數值，下面是日期。當晚那根是亮紫色，其他半透明。
  Widget _bar(
    NightValue n,
    double maxV, {
    required bool isCurrent,
    required String Function(double) format,
  }) {
    final frac = maxV <= 0 ? 0.0 : (n.value / maxV).clamp(0.05, 1.0);
    final d = DateTime.tryParse(n.date);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              format(n.value),
              style: TextStyle(
                color: isCurrent ? Colors.white : Colors.white54,
                fontSize: 11,
                fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Flexible(
            child: FractionallySizedBox(
              heightFactor: frac,
              child: Container(
                decoration: BoxDecoration(
                  color: isCurrent
                      ? SonnapColors.accent
                      : Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: SonnapColors.accent.withValues(alpha: 0.6),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            d == null ? '' : '${d.day}',
            style: TextStyle(
              color: isCurrent ? Colors.white : Colors.white54,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 背景圖畫在捲動內容裡（見 [_buildContent]），寵物才會一直站在山頂上。
    // 這裡的底色接在圖的下緣之後，顏色取自圖片最下面那一列。
    return ColoredBox(
      color: kHomeBackgroundBottom,
      child: FutureBuilder<SleepSession>(
        future: _sessionFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SafeArea(
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF8B6DFF)),
              ),
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return SafeArea(child: _buildError(snapshot.error));
          }
          return _buildContent(snapshot.data!);
        },
      ),
    );
  }

  /// 讀不到資料時要明確講出原因與解法，不要留白畫面。
  /// 最可能的原因就是還沒跑過 pipeline，asset 檔根本不存在。
  Widget _buildError(Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: Colors.white38,
              size: 48,
            ),
            const SizedBox(height: 16),
            const Text(
              "No sleep data yet",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Run `python garmin/run_pipeline.py` to generate\n"
              "assets/data/app_payload.json, then rebuild the app.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text("Retry"),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 16),
              Text(
                "$error",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white24, fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }


  static String _tod(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _buildContent(SleepSession session) {
    final now = widget.clock();
    final display = session.display;
    final mood = session.status.petMood;
    final game = _game?.value;
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final topInset = media.padding.top;
    final contentWidth = width > 520 ? 520.0 : width;

    // 圖片以整個螢幕寬度從最上面鋪下來，所以山頂的位置可以算出來。
    // 寵物的腳（圖框底部往上約 8%）踩在山頂稍下方一點的草地上。
    final crestY = width / kHomeBackgroundAspect * kHomeBackgroundCrest;
    // 上半部（問候＋時鐘＋倒數圓環）大約需要 [kHomeHeaderHeight]；
    // 螢幕窄到放不下時寵物往下移，寧可站在草地上也不要蓋到時鐘。
    final heroHeight = math.max(
      crestY + 14 + kHomePetSize * 0.08 - topInset,
      kHomeHeaderHeight + kHomePetSize - 20,
    );

    return SingleChildScrollView(
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // 山丘那張在上、湖面那張接在下面（兩張同寬同比例，接縫兩邊都是深色草叢）。
          // ⚠️ 用 Positioned：頁面高度由內容決定，背景只鋪到內容結束，
          //    不然兩張圖會把頁面撐長，底下多出一大段空的湖面可以捲。
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Image.asset(
                  kHomeBackgroundAsset,
                  width: width,
                  fit: BoxFit.fitWidth,
                  errorBuilder: (context, error, stack) =>
                      const SizedBox.shrink(),
                ),
                Image.asset(
                  kHomeBackgroundLowerAsset,
                  width: width,
                  fit: BoxFit.fitWidth,
                  errorBuilder: (context, error, stack) =>
                      const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          // 星星閃光與流星，只畫在山頂以上的天空。
          NightSkyEffects(width: width, height: crestY * 0.85),
          Padding(
            padding: EdgeInsets.only(top: topInset),
            child: Center(
              child: SizedBox(
                width: contentWidth,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: Column(
                    children: [
                      SizedBox(
                        height: heroHeight,
                        child: Stack(
                          children: [
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: Column(
                                children: [
                                  _buildHeader(session, now, game),
                                  // Hi 上方加了留白，這裡收一點，免得時鐘卡壓到寵物上面的等級
                                  const SizedBox(height: 8),
                                  _buildClockRow(now),
                                ],
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: _buildPet(mood, game, session),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        display.moodDescription,
                        key: const Key('mood-description'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: SonnapColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          shadows: [
                            Shadow(blurRadius: 8, color: Colors.black54),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildStartSleepPill(),
                      const SizedBox(height: 18),
                      // 點分數卡：最近 7 晚的分數長條圖（照抄後端每晚的 final_score）。
                      GestureDetector(
                        key: const Key('score-card'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _showMetricSheet(
                          session: session,
                          id: 'score',
                          title: 'Sleep Score',
                          series: _series(session.history, (e) => e.finalScore),
                          format: (v) => v.round().toString(),
                        ),
                        child: _buildScoreCard(session),
                      ),
                      const SizedBox(height: SonnapColors.gap),
                      _buildTiles(session),
                      const SizedBox(height: SonnapColors.gap),
                      // 睡眠階段（只呈現、不計分；不放警語）。沒有資料時老實講還沒有。
                      if (session.metrics.sleepStages != null)
                        SleepStagesCard(
                          stages: session.metrics.sleepStages!,
                          totalSleepMinutes:
                              session.metrics.sleepDurationMinutes,
                          // 點 Heart rate／Movement 疊線（2026-11-13）
                          heartRate: session.metrics.heartRateCurve,
                          movement: session.metrics.movementCurve,
                          camera: session.metrics.cameraCurve,
                          restingHeartRate:
                              session.metrics.restingHeartRate?.toDouble(),
                        )
                      else
                        const SleepStagesUnavailableCard(),
                      const SizedBox(height: SonnapColors.gap),
                      WeekMoodStrip(
                        history: session.history,
                        onDayTap: _openReport,
                        today: widget.clock(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 頂端：問候、名字、後端的一句話；右上是日記／衣櫃／獎勵與等級 ─────

  Widget _buildHeader(SleepSession session, DateTime now, GameState? game) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          // Hi 上面多留一點空間（2026-11-13 使用者定）；右上的圖示不跟著往下
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 2026-11-13 使用者定：小字「Hi, 暱稱!」＋大字「Welcome to Sonnap」，
              // 不再分早午晚。名字一律來自帳號（不得寫死任何人的名字）。
              Text(
                'Hi, ${widget.displayName}!',
                key: const Key('day-greeting'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // 名字淺色、細字（2026-11-13 使用者依參考圖定）
                style: const TextStyle(
                  color: Color(0x99FFFFFF),
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 2),
              // 「Let's get a good night's sleep!」與等級徽章 2026-11-13 拿掉（使用者定）；
              // 等級改放在寵物上面（_buildPet）。
              const FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'Welcome to Sonnap',
                  key: Key('day-title'),
                  maxLines: 1,
                  style: TextStyle(
                    color: SonnapColors.textPrimary,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _iconAction(
                  const Key('open-diary'),
                  Icons.menu_book_rounded,
                  'Dream diary',
                  () => _showDream(session),
                ),
                _iconAction(
                  const Key('open-closet'),
                  Icons.checkroom_rounded,
                  'Closet',
                  _openCloset,
                ),
                _iconAction(
                  const Key('open-rewards'),
                  Icons.card_giftcard_rounded,
                  'Rewards',
                  _openRewards,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _iconAction(
    Key key,
    IconData icon,
    String tooltip,
    VoidCallback onTap,
  ) {
    return IconButton(
      key: key,
      onPressed: onTap,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, color: SonnapColors.accentSoft, size: 22),
    );
  }

  Widget _levelBadge(int level) {
    return InkWell(
      key: const Key('level-badge'),
      onTap: _openRewards,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: SonnapColors.accent.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: SonnapColors.accent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, color: Color(0xFFFFD96A), size: 14),
            const SizedBox(width: 3),
            Text(
              'Lv $level',
              style: const TextStyle(
                color: SonnapColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 寵物：照後端的心情，右下角掛心情標籤 ─────────────────────────

  Widget _buildPet(String mood, GameState? game, SleepSession session) {
    final dreamDate = _dreamDate(session);
    final color = moodColor(mood);
    final pet = SizedBox(
      height: kHomePetSize,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          HomePet(
            mood: mood,
            size: kHomePetSize,
            equippedItemId: _closet?.value?.equippedItemId,
            accessoryEmoji: _closet?.value?.equipped?.emoji,
            growthStage: game?.growthStage,
          ),
          Positioned(
            right: 30,
            bottom: 0,
            child: Container(
              key: const Key('mood-chip'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MoodFace(mood: mood, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    moodLabel(mood),
                    style: const TextStyle(
                      color: Color(0xFF1B2350),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    // 小狗說「I had a dream…」，點開才看完整夢境（2026-11-13 使用者定）。
    // 只有真的有夢才出現；看過就縮成一朵小雲。
    // ⚠️ 位置照整個畫面寬度算，不是照小狗那個 230 的框：小狗的頭在框的左半邊、
    //    右緣大約就在中線，雲朵要從中線右邊開始才不會蓋到臉（實機截圖抓到過蓋住半張臉）。
    //    放在框裡面的話推不出去，推到框外又點不到。
    final petWithDream = dreamDate == null
        ? pet
        : LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              return SizedBox(
                width: w,
                height: kHomePetSize,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(child: pet),
                    Positioned(
                      key: const Key('dream-bubble'),
                      top: 4,
                      left: math.min(w / 2 + 14, w - kDreamBubbleWidth - 4),
                      child: DreamBubble(
                        read: _dreamReadDate == dreamDate,
                        onTap: () => _showDream(session),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
    // 等級在寵物上面（2026-11-13 使用者定）。照抄後端（GET /game），Dart 不從 XP 反推；
    // 點了開獎勵。沒有後端就不畫。
    if (game == null) return petWithDream;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _levelBadge(game.level),
        const SizedBox(height: 4),
        petWithDream,
      ],
    );
  }

  /// 分數卡：左邊發光圓環（分數），右邊「Good sleep」與後端那句話。
  /// 等級、分數、那句話都照抄後端（`display.score_message`），Dart 不判斷。
  /// ⚠️ 沒有分數時寫「—」，不能寫 0（`scoreAsInt` 在 null 時回 0）。
  Widget _buildScoreCard(SleepSession session) {
    final scoring = session.scoring;
    final hasScore = scoring.finalScore != null;
    final score = hasScore ? '${scoring.scoreAsInt}' : '—';
    final qualityColor = Color(session.display.colorValue);
    const ring = 104.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: sonnapCardDecoration(),
      child: Row(
        children: [
          SizedBox(
            width: ring,
            height: ring,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 光暈
                Container(
                  width: ring,
                  height: ring,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: SonnapColors.accent.withValues(alpha: 0.35),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: ring,
                  height: ring,
                  child: CircularProgressIndicator(
                    value: hasScore ? scoring.scoreAsInt / 100 : 0,
                    strokeWidth: 7,
                    strokeCap: StrokeCap.round,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    color: const Color(0xFFB9A6FF),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      score,
                      key: const Key('score-number'),
                      style: const TextStyle(
                        color: SonnapColors.textPrimary,
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Sleep Score',
                      style: TextStyle(
                        color: SonnapColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${scoring.finalQuality} sleep',
                  key: const Key('score-quality'),
                  style: TextStyle(
                    color: qualityColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (session.display.scoreMessage.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    session.display.scoreMessage,
                    style: const TextStyle(
                      color: SonnapColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 時鐘卡＋倒數圓環 ──────────────────────────────────────────

  /// 距離下一次目標就寢時刻還有多久（永遠是「下一次」，所以剛過時是 23 小時多；
  /// 那時要配 [bedtimeUrgencyCaption] 的 "past bedtime"，見 bedtime_urgency.dart）。
  Duration _untilBedtime(DateTime now) {
    final todayAt = DateTime(
      now.year,
      now.month,
      now.day,
      _bedtime.hour,
      _bedtime.minute,
    );
    final next = todayAt.isAfter(now)
        ? todayAt
        : todayAt.add(const Duration(days: 1));
    return next.difference(now);
  }

  static String _leftText(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m left' : '${m}m left';
  }

  /// 大時鐘卡（點了改目標就寢時間）。倒數是一條沿著卡片外框繞的光條：
  /// 剩越少越短、越紅（2026-11-12 使用者定案，取代右邊的圓環）。
  ///
  /// ⚠️ 過目標 60 分鐘以上（例如凌晨兩點）**不顯示倒數**——那時倒數會算成
  ///    「距離明天還有 21 小時」，寫「晚了 2 小時半」又只剩責備
  ///    （見 `bedtime_urgency.dart` 的 kOverdueWindow）。
  Widget _buildClockRow(DateTime now) {
    final late =
        homeModeFor(now: now, bedtime: _bedtime) == HomeMode.lateEvening;
    final urgency = bedtimeUrgency(now, _bedtime);
    final left = _untilBedtime(now);
    final color = countdownColor(left, urgency);
    final overdue = urgency == BedtimeUrgency.overdue;

    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.5,
        child: CountdownBorder(
          key: const Key('countdown-border'),
          // 一整天 = 一整圈；剛過就寢、或過了很久都不畫進度。
          progress: (late || overdue) ? 0 : left.inMinutes / (24 * 60),
          color: color,
          radius: SonnapColors.radius,
          child: InkWell(
            key: Key(late ? 'late-evening' : 'bedtime-row'),
            onTap: _pickBedtime,
            borderRadius: BorderRadius.circular(SonnapColors.radius),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: sonnapCardDecoration(),
              child: Column(
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      DateFormat('HH:mm').format(now),
                      key: const Key('home-clock'),
                      style: const TextStyle(
                        color: SonnapColors.textPrimary,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          late
                              ? 'Bedtime was ${_tod(_bedtime)}'
                              : 'Target ${_tod(_bedtime)}',
                          style: const TextStyle(
                            color: SonnapColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.edit,
                          color: Color(0xFFFFD96A),
                          size: 14,
                        ),
                      ],
                    ),
                  ),
                  if (!late) ...[
                    const SizedBox(height: 2),
                    Text(
                      overdue ? 'past bedtime' : _leftText(left),
                      key: const Key('bedtime-countdown'),
                      style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  if (late) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'Your buddy is waiting.',
                      style: TextStyle(
                        color: SonnapColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 小顆的 Start Sleep（LUNA 那樣的藥丸按鈕）──────────────────

  /// 首頁只有 Start sleep（2026-11-12 使用者定案）：下床在睡覺畫面裡按。
  Widget _buildStartSleepPill() {
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(
              colors: [Color(0xFFB9A6FF), Color(0xFF8B6DFF)],
            ),
            boxShadow: [
              BoxShadow(
                color: SonnapColors.accent.withValues(alpha: 0.5),
                blurRadius: 16,
              ),
            ],
          ),
          child: TextButton(
            key: const Key('start-sleep'),
            onPressed: _startSleep,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              shape: const StadiumBorder(),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.nightlight_round, size: 20),
                SizedBox(width: 10),
                Text(
                  'Start Sleep',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                SizedBox(width: 14),
                Icon(Icons.chevron_right_rounded, size: 20),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // ⚠️ 這句話很重要：它是使用者唯一會看到的「不按也沒關係」。
        //    少了它，忘記按的人會以為那一晚白過了——而 lights_out_at 照樣偵測得到。
        const Text(
          "It's fine if you forget to tap :) Bedtime is detected anyway.",
          key: Key('optional-note'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: SonnapColors.textSecondary,
            fontSize: 11,
            shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
          ),
        ),
        // 補昨晚（2026-11-12）。⚠️ 上面那句「不按也沒關係」照留——它有測試守著，
        //    是使用者唯一會看到的保證；這一行只是多給一條路。
        if (_needsBackfill)
          TextButton(
            key: const Key('backfill-last-night'),
            onPressed: _backfillLastNight,
            child: const Text(
              'Forgot to tap last night? Add times',
              style: TextStyle(
                color: Color(0xFFB9A6FF),
                fontSize: 12,
                decoration: TextDecoration.underline,
                decorationColor: Color(0xFFB9A6FF),
              ),
            ),
          ),
        // 起床自評補填（起床 6 小時內、還沒填）。不進分數、不給 XP。
        if (_restedMakeUp != null) ...[
          const SizedBox(height: 8),
          _restedMakeUpCard(),
        ],
      ],
    );
  }

  /// 補填起床自評的小卡。
  Widget _restedMakeUpCard() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('rested-make-up'),
        borderRadius: BorderRadius.circular(18),
        onTap: _makeUpRested,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0x8C3A3672),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x24FFFFFF)),
          ),
          child: Row(
            children: [
              Image.asset(
                restedFaceAsset(4),
                width: 32,
                height: 32,
                errorBuilder: (_, _, _) => const SizedBox(width: 32, height: 32),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'How rested did you feel this morning?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white70, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── 四張數據卡 ────────────────────────────────────────────────

  static List<(String, String)> _hm(int minutes) => [
    ('${minutes ~/ 60}', 'hr'),
    ('${minutes % 60}', 'min'),
  ];

  static String _fmtPts(double v) => '${v.round()}%';
  static String _fmtRate(double v) => '${v.toStringAsFixed(0)} /hr';

  /// 每一項的逐夜數值（給「跟上一晚比」與長條圖）。沒值的晚上不放進來。
  static List<NightValue> _series(
    List<HistoryEntry> history,
    double? Function(HistoryEntry) pick,
  ) => [
    for (final e in history)
      if (pick(e) != null) NightValue(e.date, pick(e)!),
  ];

  /// 四張卡（2026-11-12 定案）：睡眠長度、睡眠效率、深睡、睡眠中的動作。
  /// 每張底下一行「↑ 1h 12m vs Nov 8」（上升紅、下降綠，只代表方向）；
  /// 點了開最近 7 晚的長條圖，效率與深睡附上後端的警語。
  Widget _buildTiles(SleepSession session) {
    final m = session.metrics;
    final minutes = m.sleepDurationMinutes;
    // 效率：顯示**進分數的那一個**（2026-11-13 使用者定，同早晨報告）；舊版打包檔沒有就退回手錶的。
    final eff = m.scoredEfficiency ?? m.sleepEfficiency;
    final deep = m.deepMinutes;
    final h = session.history;
    final current = h.lastOrNull?.date;

    final durationSeries = _series(
      h,
      (e) => e.sleepDurationHours == null ? null : e.sleepDurationHours! * 60,
    );
    // ⚠️ 「跟上一晚比」與長條圖只放**同一種**效率：臥床版 88% 跟手錶版 100% 不是同一個量，
    //    混在一起比會畫出一個假的下降箭頭。舊版打包檔 basis 全是 null，就照舊全部一起比。
    final effBasis = h.lastOrNull?.scoredEfficiencyBasis;
    final effSeries = _series(
      h.where((e) => e.scoredEfficiencyBasis == effBasis).toList(),
      (e) => e.scoredEfficiency ?? e.sleepEfficiency,
    );
    final deepSeries = _series(h, (e) => e.deepMinutes?.toDouble());

    (String, Color)? cmp(List<NightValue> series, String Function(double) f) {
      if (current == null) return null;
      final d = compareWithPrevious(series, current);
      return d == null ? null : (deltaText(d, f), deltaColor(d));
    }

    // 固定高度：IntrinsicHeight 遇到 FittedBox 會量出過高的值（實機上卡片撐到半個螢幕）。
    Widget pair(Widget a, Widget b) => SizedBox(
      height: 124,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: a),
          const SizedBox(width: SonnapColors.gap),
          Expanded(child: b),
        ],
      ),
    );

    Widget tappable(Widget tile, VoidCallback onTap) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: tile,
    );

    return Column(
      children: [
        pair(
          tappable(
            InfoTile(
              key: const Key('tile-duration'),
              icon: Icons.nightlight_round,
              iconColor: const Color(0xFFB9A6FF),
              title: 'Sleep',
              value: minutes == null ? null : _hm(minutes),
              compare: cmp(durationSeries, formatMinutes),
            ),
            () => _showMetricSheet(
              session: session,
              id: 'duration',
              title: 'Sleep',
              series: durationSeries,
              format: formatMinutes,
            ),
          ),
          tappable(
            InfoTile(
              key: const Key('tile-efficiency'),
              icon: Icons.speed_rounded,
              iconColor: const Color(0xFF7EC8FF),
              title: 'Efficiency',
              value: eff == null ? null : [(eff.round().toString(), '%')],
              // 這一晚是哪一種效率（字照抄後端 score_claim）
              note: eff == null ? null : m.scoredEfficiencyLabel,
              compare: cmp(effSeries, _fmtPts),
            ),
            () => _showMetricSheet(
              session: session,
              id: 'efficiency',
              title: 'Sleep efficiency',
              series: effSeries,
              format: _fmtPts,
              caveatComponent: 'efficiency',
            ),
          ),
        ),
        const SizedBox(height: SonnapColors.gap),
        pair(
          tappable(
            InfoTile(
              key: const Key('tile-deep'),
              icon: Icons.waves_rounded,
              iconColor: const Color(0xFF9AD36A),
              title: 'Deep sleep',
              value: deep == null ? null : _hm(deep),
              compare: cmp(deepSeries, formatMinutes),
            ),
            () => _showMetricSheet(
              session: session,
              id: 'deep',
              title: 'Deep sleep',
              series: deepSeries,
              format: formatMinutes,
              caveatComponent: 'deep',
            ),
          ),
          _buildCameraTile(session),
        ),
      ],
    );
  }

  /// 睡眠中的動作（攝影機）。大字是每小時幾次，下面一行照抄後端的
  /// 「跟你平常比」。⚠️ 不跟文獻常模並列（跨夜不穩，見 CLAUDE.md 紅線 2 展開）。
  Widget _buildCameraTile(SleepSession session) {
    const key = Key('tile-camera');
    const icon = Icons.videocam_rounded;
    const color = Color(0xFFFFD96A);
    const title = 'Movement';

    final camera = _camera;
    if (widget.cameraInsights == null ||
        camera?.status == CameraInsightsStatus.noBackend) {
      return const InfoTile(
        key: key,
        icon: icon,
        iconColor: color,
        title: title,
        value: null,
        missingNote: 'Needs backend',
      );
    }

    // ⚠️ 連不到、沒帳號都不能說成「那晚沒錄影」——那會讓人以為攝影機壞了。
    if (camera == null ||
        camera.status == CameraInsightsStatus.failed ||
        camera.status == CameraInsightsStatus.noUser) {
      return InfoTile(
        key: key,
        icon: icon,
        iconColor: color,
        title: title,
        value: null,
        missingNote: camera?.status == CameraInsightsStatus.noUser
            ? 'Needs an account'
            : (camera == null ? 'Loading…' : 'Backend unreachable'),
      );
    }

    // 只看跟首頁同一晚的那一筆；沒有就是那晚沒錄影，不退回別的晚上。
    CameraNight? night;
    for (final n in camera.nights) {
      if (n.date == session.history.lastOrNull?.date) night = n;
    }
    final rate = night?.eventsPerHour;
    if (night == null || rate == null) {
      return const InfoTile(
        key: key,
        icon: icon,
        iconColor: color,
        title: title,
        value: null,
        missingNote: 'No camera this night',
      );
    }
    final series = [
      for (final n in camera.nights)
        if (n.eventsPerHour != null) NightValue(n.date, n.eventsPerHour!),
    ];
    final d = compareWithPrevious(series, night.date);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showMetricSheet(
        session: session,
        id: 'camera',
        title: 'Movement',
        series: series,
        format: _fmtRate,
      ),
      child: InfoTile(
        key: key,
        icon: icon,
        iconColor: color,
        title: title,
        value: [(rate.toStringAsFixed(0), '/ hr')],
        note: night.usualLabel,
        compare: d == null ? null : (deltaText(d, _fmtRate), deltaColor(d)),
      ),
    );
  }
}

/// 睡覺畫面用的頁面：進場照常從下往上滑，**退場不播動畫**。
///
/// 起床時睡覺畫面一退場，起床動畫（同一個房間）就直接接上。但中間要先讀一次本機標記
/// 與首頁心情，實機上會花幾格；退場動畫若在播，那幾格會露出底下的首頁（有分數卡）。
/// ⚠️ 這一條是保險：測試環境裡讀資料是瞬間完成的，`morning_report_test.dart` 的
///    「一格都不露出首頁」守不到它（反向檢查過）。守得到的是動畫與自評卡那兩段。
/// （Cancel 也一樣直接關掉，沒有影響。）
class _NoExitAnimationRoute<T> extends MaterialPageRoute<T> {
  _NoExitAnimationRoute({required super.builder, super.fullscreenDialog});

  @override
  Duration get reverseTransitionDuration => Duration.zero;
}

/// 組報告要用的、手機上已經有的東西。
class _ReportInputs {
  final BedMarks marks;
  final MorningRating? localRating;
  final CameraNight? camera;
  final SleepSession? session;
  final int goalMinutes;

  /// localRating 是起床流程裡剛填的（見 MorningReport.withExtras）。
  final bool ratingIsFresh;

  const _ReportInputs({
    required this.marks,
    required this.localRating,
    required this.camera,
    required this.session,
    required this.goalMinutes,
    this.ratingIsFresh = false,
  });

  _ReportInputs withFreshRating(MorningRating rating) => _ReportInputs(
        marks: marks,
        localRating: rating,
        camera: camera,
        session: session,
        goalMinutes: goalMinutes,
        ratingIsFresh: true,
      );
}

/// 起床流程在動畫一開始就先發出去的請求。
class _ReportFetch {
  final Future<Map<String, dynamic>?>? home;
  final Future<GameResult<GameState>>? game;

  const _ReportFetch({this.home, this.game});
}
