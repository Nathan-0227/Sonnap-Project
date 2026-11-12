import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/account_service.dart';
import '../models/sleep_session.dart';
import '../services/sleep_repository.dart';
import '../services/game_service.dart';
import '../services/home_mode.dart';
import '../theme/sonnap_colors.dart';
import '../widgets/home_mode_toggle.dart';
import '../widgets/home_pet.dart';
import '../widgets/info_tile.dart';
import '../widgets/week_mood_strip.dart';
import '../widgets/sleepy_pet.dart';
import 'closet_screen.dart';
import 'rewards_screen.dart';
import 'sleep_mode_screen.dart';
import '../services/bed_marks.dart';
import '../services/key_value_store.dart';
import '../widgets/header_card.dart';
import '../widgets/sleep_streak_card.dart';

/// 首頁。資料來自 `assets/data/app_payload.json`（由 Python pipeline 產生）。
///
/// 這裡刻意**不對數據做任何判斷**——分數好不好、該顯示哪種心情、該說哪句話，
/// 全部由後端算好放在 payload 裡。專案原則是「Python 判斷，Dart 只負責畫」，
/// 這樣所有判斷都可以追溯到有文獻依據的那一層。
class HomeScreen extends StatefulWidget {
  /// 帳號的暱稱。沒有帳號時是 [kFallbackDisplayName]。
  final String displayName;

  final SleepRepository repository;

  /// 目標就寢時間。**擁有者是 `main.dart` 的 `_MainPageState`**，這裡只是轉交
  /// 給 HeaderCard。⚠️ 不要在這個畫面自己存一份——Settings 也顯示同一個值，
  /// 兩邊各存一份就是先前那個「改了 Settings 首頁倒數不動」的 bug。
  final TimeOfDay targetBedtime;
  final bool reminderOn;

  /// 使用者在首頁改了就寢時間／提醒開關時往上通知，由 `main.dart` 統一更新。
  final ValueChanged<TimeOfDay>? onBedtimeChanged;
  final ValueChanged<bool>? onReminderChanged;

  /// 上床／下床標記的儲存。可注入，測試才不必依賴真的原生 channel。
  final BedMarkStore bedMarks;

  /// 遊戲化層（XP、等級、衣櫃、獎勵）。null = 這支 build 沒有後端，
  /// 等級卡不顯示、衣櫃與獎勵點下去會老實講「要連上後端」。
  final GameService? game;

  /// 現在幾點。可注入：首頁顯示哪一版取決於時間，測試要釘住時間才測得穩。
  final DateTime Function() clock;

  const HomeScreen({
    super.key,
    this.bedMarks = const BedMarkStore(PlatformKeyValueStore()),
    this.game,
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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  /// 在 initState 建立而不是在 build 裡——放 build 的話每次重繪都會重讀檔案。
  late Future<SleepSession> _sessionFuture;

  /// `GET /game` 與 `GET /closet` 的結果。⚠️ 每一格都照抄後端，
  /// 這個畫面不算 XP、不判斷哪件衣服解鎖了。
  GameResult<GameState>? _game;
  GameResult<ClosetState>? _closet;

  /// 本機的上床／下床標記。決定要不要進睡覺畫面。
  BedMarks _marks = BedMarks.none;

  /// 使用者手動切的 Today / Tonight。null = 照時間自動。
  /// ⚠️ 只存在記憶體：下次打開 App 恢復自動（2026-11-12 定案）。
  bool? _tonightOverride;

  /// 睡覺畫面開著時不要再推一次。
  bool _sleepRouteOpen = false;

  /// 時間一到就要換版（例如 21:59 → 22:00 變晚上版），所以定時重畫。
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionFuture = widget.repository.load();
    _loadGame();
    _loadMarks();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
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
    if (!mounted) return;
    setState(() => _marks = marks);
    _maybeOpenSleepMode();
  }

  void _maybeOpenSleepMode() {
    if (_sleepRouteOpen) return;
    if (!isSleeping(widget.clock(), _marks)) return;
    final startAt = _marks.startAt!;
    _sleepRouteOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SleepModeScreen(
          store: widget.bedMarks,
          startAt: startAt,
          clock: widget.clock,
        ),
      ));
      _sleepRouteOpen = false;
      if (!mounted) return;
      // 回來時（下床或取消）照時間回到白天版或晚上版，不留手動切換。
      setState(() => _tonightOverride = null);
      await _loadMarks();
    });
  }

  Future<void> _startSleep() async {
    await widget.bedMarks.markStart(widget.clock());
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

  /// 沒有後端時老實講。⚠️ 不要沿用「will be available later」——
  /// 功能已經做好了，缺的是連線；講成「以後才有」會讓人以為沒做。
  void _showNeedsBackend(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("$feature needs the Sonnap backend. "
            "It works when the app is connected to the server."),
      ),
    );
  }

  Future<void> _openCloset() async {
    final service = widget.game;
    if (service == null) return _showNeedsBackend("Closet");
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ClosetScreen(service: service)),
    );
    // 回來時重讀：剛換的衣服要出現在寵物身上。
    if (mounted) await _loadGame();
  }

  Future<void> _openRewards() async {
    final service = widget.game;
    if (service == null) return _showNeedsBackend("Rewards");
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RewardsScreen(service: service)),
    );
    if (mounted) await _loadGame();
  }

  void _reload() {
    setState(() {
      _sessionFuture = widget.repository.load();
    });
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
    if (!ai.hasDream) {
      _showComingSoon("Dream Diary");
      return;
    }

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF10265A),
        title: const Text(
          "Your buddy's dream diary",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ai.dreamSummary!,
                style: const TextStyle(color: Colors.white70, height: 1.5),
              ),
              const SizedBox(height: 16),
              Text(
                session.disclaimer ?? "",
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close",
                style: TextStyle(color: Color(0xFFFFD96A))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    return SafeArea(
      child: Center(
        child: SizedBox(
          width: screenWidth > 520 ? 520 : screenWidth,
          child: FutureBuilder<SleepSession>(
            future: _sessionFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF8B6DFF)),
                );
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return _buildError(snapshot.error);
              }
              return _buildContent(snapshot.data!);
            },
          ),
        ),
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
            const Icon(Icons.cloud_off_rounded,
                color: Colors.white38, size: 48),
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

  /// 現在要畫白天版還是晚上版（睡覺畫面另外推一頁，不在這裡畫）。
  HomeMode _visibleMode(DateTime now) {
    final auto = homeModeFor(now: now, bedtime: widget.targetBedtime);
    final tonight = _tonightOverride ??
        (auto == HomeMode.evening || auto == HomeMode.lateEvening);
    if (!tonight) return HomeMode.day;
    // 手動切到 Tonight 的時候，如果時間上還不是晚上，就畫一般的晚上版（有倒數）。
    return auto == HomeMode.lateEvening ? HomeMode.lateEvening : HomeMode.evening;
  }

  Widget _buildContent(SleepSession session) {
    final now = widget.clock();
    final mode = _visibleMode(now);
    final tonight = mode != HomeMode.day;

    // 整頁一個場景：上半部一片光暈，寵物站在上面，而不是被裝在卡片裡。
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, 0.55],
          colors: [SonnapColors.backdropTop, SonnapColors.background],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          children: [
            Row(
              children: [
                HomeModeToggle(
                  tonight: tonight,
                  onChanged: (v) => setState(() => _tonightOverride = v),
                ),
                const Spacer(),
                _iconAction(const Key('open-diary'), Icons.menu_book_rounded,
                    'Dream diary', () => _showDream(session)),
                _iconAction(const Key('open-closet'), Icons.checkroom_rounded,
                    'Closet', _openCloset),
                _iconAction(const Key('open-rewards'),
                    Icons.card_giftcard_rounded, 'Rewards', _openRewards),
              ],
            ),
            const SizedBox(height: 16),
            if (tonight)
              ..._buildEvening(session, mode)
            else
              ..._buildDay(session, now),
          ],
        ),
      ),
    );
  }

  Widget _iconAction(
      Key key, IconData icon, String tooltip, VoidCallback onTap) {
    return IconButton(
      key: key,
      onPressed: onTap,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, color: SonnapColors.accentSoft, size: 22),
    );
  }

  // ── 晚上版：準備睡覺 ─────────────────────────────────────────────

  List<Widget> _buildEvening(SleepSession session, HomeMode mode) {
    final display = session.display;
    return [
      const Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Tonight',
          style: TextStyle(
              color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
        ),
      ),
      // ⚠️ 固定畫想睡的樣子、不顯示心情標籤：晚上傳達的是「該睡了」，
      //    不是昨晚的成績（見 SleepyPet 的說明）。
      const SleepyPet(size: 220),
      const SizedBox(height: 8),
      if (mode == HomeMode.lateEvening)
        _buildLateEveningCard()
      else
        // 倒數、變色、提醒開關、改就寢時間都沿用 HeaderCard（測試守著的那一套）。
        // 就寢時間與提醒開關的值來自 main.dart，改動也往上回報。
        HeaderCard(
          username: widget.displayName,
          message: display.headerMessage,
          initialReminderOn: widget.reminderOn,
          initialTargetBedtime: widget.targetBedtime,
          onReminderChanged: widget.onReminderChanged,
          onBedtimeChanged: widget.onBedtimeChanged,
        ),
      _buildStartSleep(),
      SleepStreakCard(
        streakDays: session.streak.streakDays,
        completedDays: session.streak.completedDays,
        encouragement: display.streakEncouragement,
        completedColor: const Color(0xFF9AD36A),
        iconBackgroundColor: const Color(0xFFFF7043),
      ),
    ];
  }

  /// 過了目標一小時以上（例如凌晨兩點還沒睡）。
  ///
  /// ⚠️ **不顯示數字、不用紅色。** 這時倒數會算成「距離明天還有 21 小時」，
  /// 寫「晚了 2 小時 30 分」又只剩責備——`bedtime_urgency.dart` 的
  /// kOverdueWindow 註解寫的是同一件事：回饋要掛在「還能做點什麼」的時候。
  Widget _buildLateEveningCard() {
    final t = widget.targetBedtime;
    final hhmm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Container(
      key: const Key('late-evening'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: sonnapCardDecoration(),
      child: Column(
        children: [
          Text('Bedtime was $hhmm',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Your buddy is waiting.',
              style: TextStyle(color: Colors.white70, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _buildStartSleep() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('start-sleep'),
              onPressed: _startSleep,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB9A6FF),
                foregroundColor: const Color(0xFF1B2350),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: const StadiumBorder(),
              ),
              child: const Text('Start sleep',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 8),
          // ⚠️ 這句話很重要：它是使用者唯一會看到的「不按也沒關係」。
          //    少了它，忘記按的人會以為那一晚白過了——而 lights_out_at 照樣偵測得到。
          const Text(
            'Optional - bedtime is detected anyway. Tapping just adds how long '
            'you were in bed.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF8498B7), fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ── 白天版：回顧昨晚 ─────────────────────────────────────────────

  static String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  List<Widget> _buildDay(SleepSession session, DateTime now) {
    final display = session.display;
    final mood = session.status.petMood;
    final game = _game?.value;

    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_greeting(now)}, ${widget.displayName}',
                  key: const Key('day-greeting'),
                  style: const TextStyle(
                      color: SonnapColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w800),
                ),
                Text(DateFormat('EEE, MMM d').format(now),
                    style: const TextStyle(
                        color: SonnapColors.accentSoft, fontSize: 14)),
              ],
            ),
          ),
          // 等級照抄後端（GET /game），Dart 不從 XP 反推。點了開獎勵。
          if (game != null) _levelBadge(game.level),
        ],
      ),
      const SizedBox(height: 14),
      WeekMoodStrip(history: session.history),
      const SizedBox(height: 8),

      // 寵物是主角：沒有框，站在背景的光暈上。心情照抄 status.pet_mood。
      Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                SonnapColors.accent.withValues(alpha: 0.28),
                SonnapColors.accent.withValues(alpha: 0),
              ]),
            ),
          ),
          HomePet(
            mood: mood,
            size: 230,
            equippedItemId: _closet?.value?.equippedItemId,
            accessoryEmoji: _closet?.value?.equipped?.emoji,
            growthStage: game?.growthStage,
          ),
        ],
      ),
      _buildScoreLine(session),
      const SizedBox(height: 8),
      _buildMoodChip(mood, display.moodDescription),
      const SizedBox(height: 16),
      _buildTiles(session),
    ];
  }

  Widget _levelBadge(int level) {
    return InkWell(
      key: const Key('level-badge'),
      onTap: _openRewards,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: SonnapColors.accent.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: SonnapColors.accent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, color: Color(0xFFFFD96A), size: 16),
            const SizedBox(width: 4),
            Text('Lv $level',
                style: const TextStyle(
                    color: SonnapColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }

  /// 寵物下面那一行：「Good · 82 / 100」。等級與分數都照抄後端。
  /// ⚠️ 沒有分數時寫「—」，不能寫 0（`scoreAsInt` 在 null 時回 0）。
  Widget _buildScoreLine(SleepSession session) {
    final scoring = session.scoring;
    final score = scoring.finalScore == null ? '—' : '${scoring.scoreAsInt}';
    return Text.rich(
      key: const Key('score-line'),
      TextSpan(children: [
        TextSpan(
          text: '${scoring.finalQuality} · ',
          style: TextStyle(
              color: Color(session.display.colorValue),
              fontSize: 22,
              fontWeight: FontWeight.w800),
        ),
        TextSpan(
          text: score,
          style: const TextStyle(
              color: SonnapColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800),
        ),
        const TextSpan(
          text: ' / 100',
          style: TextStyle(color: SonnapColors.textMuted, fontSize: 14),
        ),
      ]),
    );
  }

  Widget _buildMoodChip(String mood, String description) {
    final color = moodColor(mood);
    return Row(
      key: const Key('mood-chip'),
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(moodIcon(mood), color: color, size: 18),
        const SizedBox(width: 6),
        Text(moodLabel(mood),
            style: TextStyle(
                color: color, fontSize: 14, fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(description,
              style: const TextStyle(
                  color: SonnapColors.textSecondary, fontSize: 13)),
        ),
      ],
    );
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// 四張數據卡（2026-11-12 定案）：睡眠長度、入睡→起床、連續天數、中途醒來。
  /// 都不需要掛警語；深睡、REM、效率留在 Insights（那裡有警語的位置）。
  Widget _buildTiles(SleepSession session) {
    final m = session.metrics;
    final minutes = m.sleepDurationMinutes;
    final start = m.sleepStartTime;
    final wake = m.wakeTime;
    final waso = m.wasoMinutes;
    final streak = session.streak.streakDays;

    // 固定高度：IntrinsicHeight 遇到 FittedBox 會量出過高的值（實機上卡片撐到半個螢幕）。
    Widget pair(Widget a, Widget b) => SizedBox(
          height: 104,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: a),
              const SizedBox(width: SonnapColors.gap),
              Expanded(child: b),
            ],
          ),
        );

    return Column(
      children: [
        pair(
          InfoTile(
            key: const Key('tile-duration'),
            icon: Icons.nightlight_round,
            iconColor: const Color(0xFFB9A6FF),
            title: 'Sleep',
            value: minutes == null
                ? null
                : [('${minutes ~/ 60}', 'hr'), ('${minutes % 60}', 'min')],
          ),
          InfoTile(
            key: const Key('tile-window'),
            icon: Icons.schedule_rounded,
            iconColor: const Color(0xFF7EC8FF),
            // ⚠️ 手錶偵測到「睡著」的時刻，不是放下手機的時刻（lights_out_at）。
            title: 'Asleep → awake',
            value: (start == null || wake == null)
                ? null
                : [(_hhmm(start), '→'), (_hhmm(wake), '')],
          ),
        ),
        const SizedBox(height: SonnapColors.gap),
        pair(
          InfoTile(
            key: const Key('tile-streak'),
            icon: Icons.local_fire_department_rounded,
            iconColor: const Color(0xFFFF7043),
            title: 'Streak',
            value: [('$streak', streak == 1 ? 'night' : 'nights')],
          ),
          InfoTile(
            key: const Key('tile-waso'),
            icon: Icons.visibility_rounded,
            iconColor: const Color(0xFFFFD96A),
            title: 'Awake in bed',
            value: waso == null ? null : [('$waso', 'min')],
          ),
        ),
      ],
    );
  }
}
