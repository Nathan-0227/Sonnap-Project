import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/sleep_session.dart';
import '../services/account_service.dart';
import '../services/bed_marks.dart';
import '../services/camera_insights.dart';
import '../services/game_service.dart';
import '../services/home_mode.dart';
import '../services/key_value_store.dart';
import '../services/sleep_repository.dart';
import '../theme/sonnap_colors.dart';
import '../widgets/bedtime_urgency.dart';
import '../widgets/home_pet.dart';
import '../widgets/info_tile.dart';
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

  const HomeScreen({
    super.key,
    this.bedMarks = const BedMarkStore(PlatformKeyValueStore()),
    this.game,
    this.cameraInsights,
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

/// 背景圖的寬高比（853 × 1844）。
const double kHomeBackgroundAspect = 853 / 1844;

/// 山頂在圖片高度的哪個位置（實測 0.552）。寵物的腳要踩在這裡。
const double kHomeBackgroundCrest = 0.552;

/// 圖片最下緣的顏色，圖畫完之後頁面用它接下去。
const Color kHomeBackgroundBottom = Color(0xFF090F4F);

/// 寵物的大小。
const double kHomePetSize = 230;

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
    _loadGame();
    _loadCamera();
    _loadMarks();
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
      await Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => SleepModeScreen(
            store: widget.bedMarks,
            startAt: startAt,
            clock: widget.clock,
          ),
        ),
      );
      _sleepRouteOpen = false;
      if (!mounted) return;
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

  Future<void> _pickBedtime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _bedtime,
    );
    if (picked == null || !mounted) return;
    setState(() => _bedtime = picked);
    widget.onBedtimeChanged?.call(picked);
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
            child: const Text(
              "Close",
              style: TextStyle(color: Color(0xFFFFD96A)),
            ),
          ),
        ],
      ),
    );
  }

  /// 點有警語的卡片才跳出後端的原文（2026-11-12 使用者定案：畫面上不放警語）。
  ///
  /// ⚠️ 文字只照抄 `scoring.composition.caveats`（唯一定義處是 `score_claim.py`），
  ///    Dart 一個字都不產生。後端沒給就什麼都不跳。
  void _showCaveat(SleepSession session, String component, String title) {
    final caveats = session.scoring.composition?.caveats ?? const [];
    String? text;
    for (final c in caveats) {
      if (c.component == component) text = c.text;
    }
    if (text == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1B2350),
      builder: (context) => Padding(
        key: Key('caveat-$component'),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
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
            const SizedBox(height: 10),
            Text(
              text!,
              style: const TextStyle(color: Colors.white70, height: 1.5),
            ),
          ],
        ),
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

  static String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 18) return 'Good afternoon';
    return 'Good evening';
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
    final heroHeight = crestY + 14 + kHomePetSize * 0.08 - topInset;

    return SingleChildScrollView(
      child: Stack(
        children: [
          Image.asset(
            kHomeBackgroundAsset,
            width: width,
            fit: BoxFit.fitWidth,
            alignment: Alignment.topCenter,
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          ),
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
                              child: _buildHeader(session, now, game),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: _buildPet(mood, game),
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
                      const SizedBox(height: 16),
                      WeekMoodStrip(history: session.history),
                      const SizedBox(height: 16),
                      _buildScoreLine(session),
                      const SizedBox(height: 14),
                      _buildBedtimeRow(now),
                      const SizedBox(height: 12),
                      _buildBedButtons(),
                      const SizedBox(height: 18),
                      _buildTiles(session),
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

  // ── 頂端：問候、日期、等級、日記／衣櫃／獎勵 ─────────────────────

  Widget _buildHeader(SleepSession session, DateTime now, GameState? game) {
    return Row(
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
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    DateFormat('EEE, MMM d').format(now),
                    style: const TextStyle(
                      color: SonnapColors.accentSoft,
                      fontSize: 14,
                    ),
                  ),
                  // 等級照抄後端（GET /game），Dart 不從 XP 反推。點了開獎勵。
                  if (game != null) ...[
                    const SizedBox(width: 10),
                    _levelBadge(game.level),
                  ],
                ],
              ),
            ],
          ),
        ),
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

  Widget _buildPet(String mood, GameState? game) {
    final color = moodColor(mood);
    return SizedBox(
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
                  Icon(
                    moodIcon(mood),
                    color: const Color(0xFF1B2350),
                    size: 16,
                  ),
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
  }

  /// 「Good · 95 / 100」。等級與分數都照抄後端。
  /// ⚠️ 沒有分數時寫「—」，不能寫 0（`scoreAsInt` 在 null 時回 0）。
  Widget _buildScoreLine(SleepSession session) {
    final scoring = session.scoring;
    final score = scoring.finalScore == null ? '—' : '${scoring.scoreAsInt}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: sonnapCardDecoration(),
      child: Row(
        children: [
          const Text(
            'Sleep Score',
            style: TextStyle(color: SonnapColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text.rich(
                key: const Key('score-line'),
                TextSpan(
                  children: [
                    TextSpan(
                      text: score,
                      style: const TextStyle(
                        color: SonnapColors.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const TextSpan(
                      text: ' / 100 · ',
                      style: TextStyle(
                        color: SonnapColors.textMuted,
                        fontSize: 14,
                      ),
                    ),
                    TextSpan(
                      text: scoring.finalQuality,
                      style: TextStyle(
                        color: Color(session.display.colorValue),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 就寢時間列 ────────────────────────────────────────────────

  static String _remaining(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m left' : '${m}m left';
  }

  /// 「23:30 · 2h 10m left」。點了改目標就寢時間。
  ///
  /// ⚠️ 過目標 60 分鐘以上（例如凌晨兩點）**不顯示數字**，改成一句話——
  ///    那時倒數會算成「距離明天還有 21 小時」，寫「晚了 2 小時半」又只剩責備
  ///    （見 `bedtime_urgency.dart` 的 kOverdueWindow）。
  Widget _buildBedtimeRow(DateTime now) {
    final late =
        homeModeFor(now: now, bedtime: _bedtime) == HomeMode.lateEvening;
    final urgency = bedtimeUrgency(now, _bedtime);
    final color = late ? SonnapColors.accentSoft : bedtimeUrgencyColor(urgency);

    final String text;
    if (late) {
      text = 'Bedtime was ${_tod(_bedtime)} · Your buddy is waiting';
    } else if (urgency == BedtimeUrgency.overdue) {
      text = '${_tod(_bedtime)} · past bedtime';
    } else {
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
      text = '${_tod(_bedtime)} · ${_remaining(next.difference(now))}';
    }

    return InkWell(
      key: Key(late ? 'late-evening' : 'bedtime-row'),
      onTap: _pickBedtime,
      borderRadius: BorderRadius.circular(SonnapColors.radius),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: sonnapCardDecoration(),
        child: Row(
          children: [
            Icon(Icons.alarm_rounded, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                key: late ? null : const Key('bedtime-countdown'),
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Icon(
              Icons.edit_rounded,
              color: SonnapColors.textMuted,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  // ── 上床／下床按鈕 ────────────────────────────────────────────

  /// 首頁只有 Start sleep（2026-11-12 使用者定案）：下床在睡覺畫面裡按。
  Widget _buildBedButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('start-sleep'),
            onPressed: _startSleep,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFFC567),
              foregroundColor: const Color(0xFF1B2350),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: const StadiumBorder(),
            ),
            child: const Text(
              'Start sleep',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
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
          style: TextStyle(color: SonnapColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  // ── 四張數據卡 ────────────────────────────────────────────────

  static List<(String, String)> _hm(int minutes) => [
    ('${minutes ~/ 60}', 'hr'),
    ('${minutes % 60}', 'min'),
  ];

  /// 四張卡（2026-11-12 定案）：睡眠長度、睡眠效率、深睡、睡眠中的動作。
  /// 效率與深睡畫面上不放警語，點卡片才看得到後端的原文（見 [_showCaveat]）。
  Widget _buildTiles(SleepSession session) {
    final m = session.metrics;
    final minutes = m.sleepDurationMinutes;
    final eff = m.sleepEfficiency;
    final deep = m.deepMinutes;

    // 固定高度：IntrinsicHeight 遇到 FittedBox 會量出過高的值（實機上卡片撐到半個螢幕）。
    Widget pair(Widget a, Widget b) => SizedBox(
      height: 112,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: a),
          const SizedBox(width: SonnapColors.gap),
          Expanded(child: b),
        ],
      ),
    );

    Widget tappable(Widget tile, String component, String title) =>
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showCaveat(session, component, title),
          child: tile,
        );

    return Column(
      children: [
        pair(
          InfoTile(
            key: const Key('tile-duration'),
            icon: Icons.nightlight_round,
            iconColor: const Color(0xFFB9A6FF),
            title: 'Sleep',
            value: minutes == null ? null : _hm(minutes),
          ),
          tappable(
            InfoTile(
              key: const Key('tile-efficiency'),
              icon: Icons.speed_rounded,
              iconColor: const Color(0xFF7EC8FF),
              title: 'Efficiency',
              value: eff == null ? null : [(eff.round().toString(), '%')],
            ),
            'efficiency',
            'Sleep efficiency',
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
            ),
            'deep',
            'Deep sleep',
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
    return InfoTile(
      key: key,
      icon: icon,
      iconColor: color,
      title: title,
      value: [(rate.toStringAsFixed(0), '/ hr')],
      note: night.usualLabel,
    );
  }
}
