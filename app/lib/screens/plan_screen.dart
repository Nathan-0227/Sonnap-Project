import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/alarm.dart';
import '../services/challenges_service.dart';
import '../services/game_service.dart';
import '../services/nightly_sync.dart';
import '../services/plan_reminders.dart';
import '../services/sleep_plan.dart';
import '../theme/report_style.dart';
import '../widgets/home_pet.dart';
import '../widgets/level_progress.dart';
import 'rewards_screen.dart';
import '../widgets/plan_check_button.dart';
import '../widgets/plan_habit_editor.dart';
import '../widgets/sleep_dial.dart';
import '../widgets/sleep_schedule_sheet.dart';
import '../services/journey_service.dart';
import '../services/plan_goals.dart';
import '../widgets/plan_goal_picker.dart';
import '../widgets/report_sheet.dart';
import '../widgets/journey_section.dart';

/// 睡眠計畫頁（2026-11-19；版面照使用者給的參考圖，配色維持深色）。由上到下：
///   場景＋寵物 → 作息條 → 「今天還有幾條」＋ ＋ → 自己勾的習慣（右邊大方形勾勾）
///   → Quests：Daily（量測的三列）／Weekly（連續準時、作息收斂），完成了就地 Claim
///
/// ⚠️ 量測那幾列**一格都不算**，照抄 `/challenges`；能不能領、領多少照抄 `/game`。
/// ⚠️ 自己勾的**不給 XP、不改心情**（紅線 5）：參考圖每條旁邊的「5⚡」、
///    「Complete a goal → Claim」、寵物去冒險都不做——自己勾不需要證據。
class PlanScreen extends StatefulWidget {
  final PlanStore plan;
  final NightlySync? nightly;
  final TimeOfDay bedtime;
  final AlarmSettingsStore alarmSettings;
  final AlarmScheduler alarmScheduler;
  final PlanReminderScheduler reminders;
  final ValueChanged<TimeOfDay>? onBedtimeChanged;

  /// 起床時間改了（轉盤存完）。主程式要補送後端。
  final VoidCallback? onWakeChanged;

  /// 領量測挑戰的 XP（`/game`、`/game/claim`）。null＝沒有後端，不畫 Claim。
  final GameService? game;

  /// 打開這一頁時重新抓一次挑戰（`GET /challenges`）。null＝只用 [nightly] 那一份。
  /// ⚠️ 開 App 時那一次常常逾時（一次發一堆請求、後端一個一個處理，實測 3 秒不夠），
  ///    只靠它的話這一頁會一直寫「連不上」，而後端其實好好的。
  final Future<ChallengesResult> Function()? loadChallenges;

  /// 場景裡寵物的心情（同首頁那一份，後端 `pet_mood`）。拿不到一律照 HomePet 畫 bored。
  final Future<String?> Function()? petMood;
  final DateTime Function() clock;

  /// Journey（作息條底下）。null＝不畫（測試、沒接上的地方）。
  final JourneyController? journey;

  const PlanScreen({
    super.key,
    required this.plan,
    required this.bedtime,
    required this.alarmSettings,
    required this.alarmScheduler,
    required this.reminders,
    this.nightly,
    this.onBedtimeChanged,
    this.onWakeChanged,
    this.game,
    this.petMood,
    this.loadChallenges,
    this.clock = DateTime.now,
    this.journey,
  });

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

/// 疊在木頭地板上的字：加一層柔和陰影才讀得清楚。
const List<Shadow> _onFloor = [Shadow(blurRadius: 8, color: Color(0xCC000000))];

/// Daily＝量測的三列；Weekly＝多晚的兩個（後端 challenge id）。
const List<String> kMeasuredIds = ['on_time_tonight', 'phone_in_bed_tonight', 'up_on_time'];
const List<String> kWeekIds = ['streak_nights', 'bedtime_consistency_7d'];

/// 整頁背景（2026-11-19 使用者生成）：直式長圖，上面是窗戶、地毯在約 36%–50% 高、
/// 下面一大片往下變暗的地板。**固定不動**，清單在上面捲動、卡片從寵物身上滑過去（Q35、Q37）。
/// 讀不到時退回報告那張日出。
const String kPlanRoomAsset = 'assets/plan/room.jpg';
const double kPlanRoomAspect = 2335 / 1080; // 圖的高÷寬

/// 地毯中心落在圖高的幾成（量使用者那張圖：地毯 36%–50%）。換圖要重量。
const double kPlanRugCenter = 0.43;

/// 跳一下的某一刻：[lift] 0＝在地上、1＝最高點；[scaleX]／[scaleY] 從腳底壓扁或拉長。
typedef PetJumpPose = ({double lift, double scaleX, double scaleY});

/// 寵物跳一下的四段（t：0→1）：
///   0–0.2   蹲下蓄力（壓扁，還沒離地）
///   0.2–0.75 在空中：高度是拋物線（起跳快、頂端慢、落下加速，像重力），越快越拉長
///   0.75–0.88 落地壓扁
///   0.88–1  微微彈回原狀
PetJumpPose petJumpPose(double t) {
  double ease(double x) => math.sin(math.pi * x.clamp(0.0, 1.0)); // 0→1→0
  if (t <= 0 || t >= 1) return (lift: 0.0, scaleX: 1.0, scaleY: 1.0);
  if (t < 0.2) {
    final k = math.sin(math.pi / 2 * (t / 0.2)); // 0→1
    return (lift: 0.0, scaleX: 1 + 0.08 * k, scaleY: 1 - 0.12 * k);
  }
  if (t < 0.75) {
    final p = (t - 0.2) / 0.55;
    // 起跳、落下最快就拉最長；碰到地之前收回原狀，接落地的壓扁不會一格跳掉
    final speed = (1 - 2 * p).abs() * (p > 0.88 ? (1 - p) / 0.12 : 1.0);
    final sx = 1 - 0.05 * speed, sy = 1 + 0.08 * speed;
    // 起跳那一下從蹲的樣子（1.08／0.88）漸漸接過來，不要一格跳掉
    final w = p < 0.12 ? p / 0.12 : 1.0;
    return (
      lift: 4 * p * (1 - p),
      scaleX: 1.08 + (sx - 1.08) * w,
      scaleY: 0.88 + (sy - 0.88) * w,
    );
  }
  if (t < 0.88) {
    final k = ease((t - 0.75) / 0.13);
    return (lift: 0.0, scaleX: 1 + 0.07 * k, scaleY: 1 - 0.10 * k);
  }
  final k = ease((t - 0.88) / 0.12);
  return (lift: 0.0, scaleX: 1 - 0.015 * k, scaleY: 1 + 0.03 * k);
}

class _PlanScreenState extends State<PlanScreen> with SingleTickerProviderStateMixin {
  late TimeOfDay _bedtime = widget.bedtime;
  TimeOfDay? _wake;
  String? _mood;
  bool _weekly = false;
  List<ClaimableReward> _claimable = const [];
  // 寵物頭上的等級條（2026-11-21）。null＝沒有後端或還沒拿到，不畫
  GameState? _game;
  String? _claiming;
  ChallengesResult? _fresh;

  /// 勾下去時寵物跳一下（只動作，**臉不換**：臉是後端判的心情，Q40）。
  late final AnimationController _hop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 680));

  @override
  void initState() {
    super.initState();
    widget.plan.addListener(_onChange);
    widget.nightly?.addListener(_onChange);
    widget.journey?.addListener(_onJourney);
    // 打開這一頁時問一次（後端會重算、需要就換站）
    unawaited(widget.journey?.refresh());
    if (!widget.plan.loaded) unawaited(widget.plan.load());
    unawaited(_maybeAskGoals());
    unawaited(_loadWake());
    unawaited(_loadGame());
    unawaited(_loadMood());
    unawaited(_loadChallenges());
  }

  Future<void> _loadChallenges() async {
    final f = widget.loadChallenges;
    if (f == null) return;
    final r = await f();
    // 抓失敗就留著原本那一份（可能是好的），不拿失敗蓋掉
    if (mounted && r.status == ChallengesStatus.ok) setState(() => _fresh = r);
  }

  @override
  void dispose() {
    widget.plan.removeListener(_onChange);
    widget.nightly?.removeListener(_onChange);
    widget.journey?.removeListener(_onJourney);
    // 「Next stop from tonight」在這一頁看到了，離開就算看過（首頁小卡也跟著收起來）
    if (widget.journey?.showNotice ?? false) unawaited(widget.journey!.markSeen());
    _hop.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  /// 這一站就是目標：開始、前進、走完時作息條跟著換（主程式那邊也會換掉目標與鬧鐘）。
  void _onJourney() {
    if (!mounted) return;
    final j = widget.journey?.journey;
    final cur = j?.current;
    setState(() {
      if (j != null && cur != null && j.status != JourneyStatus.stopped) {
        _bedtime = cur.bedtime;
        _wake = cur.wake;
      }
    });
    _resyncReminders();
  }

  Future<void> _startJourney() async {
    final c = widget.journey;
    final wake = _wake;
    if (c == null || wake == null) return;
    await showJourneySetupSheet(context, controller: c, dialBedtime: _bedtime, dialWake: wake);
  }

  Future<void> _loadWake() async {
    final w = await widget.alarmSettings.wakeTime(_bedtime);
    if (mounted) setState(() => _wake = w);
  }

  Future<void> _loadMood() async {
    final f = widget.petMood;
    if (f == null) return;
    try {
      final m = await f();
      if (mounted) setState(() => _mood = m);
    } catch (_) {
      // 拿不到就照 HomePet 的規則畫 bored
    }
  }

  Future<void> _loadGame() async {
    final g = widget.game;
    if (g == null) return;
    final r = await g.fetchGame();
    if (!mounted) return;
    setState(() {
      _claimable = r.value?.claimable ?? const [];
      _game = r.value ?? _game;
    });
  }

  Future<void> _openRewards() async {
    final g = widget.game;
    if (g == null) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => RewardsScreen(service: g, mood: _mood)));
    if (mounted) await _loadGame();
  }

  Future<void> _claim(ClaimableReward reward) async {
    final g = widget.game;
    if (g == null || _claiming != null) return;
    setState(() => _claiming = reward.challengeId);
    final r = await g.claim(reward.challengeId);
    if (!mounted) return;
    setState(() => _claiming = null);
    final out = r.value;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      // 成功照抄後端給的 XP；失敗照抄後端那句（409 已經領過、422 還沒完成）
      content: Text(out != null
          ? '+${out.xpAwarded} XP${out.leveledUp ? ' · Level ${out.level}!' : ''}'
          : (r.message ?? "Couldn't claim right now.")),
    ));
    await _loadGame();
    unawaited(_loadChallenges());
  }

  void _resyncReminders() {
    final wake = _wake;
    if (wake == null) return;
    unawaited(syncPlanReminders(widget.reminders, widget.plan.items,
        now: widget.clock(), bedtime: _bedtime, wake: wake));
  }

  Future<void> _editSchedule() async {
    final result = await showSleepScheduleSheet(
      context,
      bedtime: _bedtime,
      alarmSettings: widget.alarmSettings,
      scheduler: widget.alarmScheduler,
    );
    if (result == null || !mounted) return;
    setState(() {
      _wake = result.wake;
      _bedtime = result.bedtime;
    });
    if (result.bedtime != widget.bedtime) widget.onBedtimeChanged?.call(result.bedtime);
    widget.onWakeChanged?.call();
    _resyncReminders();
  }

  Future<void> _openEditor(PlanItem item) async {
    final wake = _wake;
    if (wake == null) return;
    final out = await openPlanHabitEditor(context, item: item, bedtime: _bedtime, wake: wake);
    if (out == null) return;
    if (out.removed) {
      await widget.plan.remove(item.id);
    } else if (out.item != null) {
      await widget.plan.update(out.item!);
    }
    _resyncReminders();
  }

  /// 第一次打開計畫頁、清單是空的、而且還沒被問過（第一次登入流程裡跳過也算問過）→ 問一次（Q2）。
  Future<void> _maybeAskGoals() async {
    if (!widget.plan.loaded) await widget.plan.load();
    final goals = PlanGoalsStore(widget.plan.store);
    if (!mounted || widget.plan.items.isNotEmpty || await goals.asked()) return;
    await goals.markAsked();
    if (mounted) await _helpMePick();
  }

  /// Help me pick（Q2 B）：選目標 → 推薦頁 → 勾著的加進計畫。Journey 那一行點了就關掉，回到上面的 Journey 卡。
  Future<void> _helpMePick() async {
    final store = widget.plan.store;
    final journeyActive = await journeyLocksSchedule(store);
    if (!mounted) return;
    await showReportSheet<void>(
      context: context,
      builder: (sheet) => Container(
        key: const Key('plan-goal-sheet'),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          color: ReportColors.sheet,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: PlanGoalPicker(
              alreadyInPlan: {for (final i in widget.plan.items) i.id},
              journeyActive: journeyActive,
              onTryJourney: () => Navigator.of(sheet).pop(),
              onDone: (goals, habits) async {
                Navigator.of(sheet).pop();
                await PlanGoalsStore(store).save(goals);
                await addGoalHabits(widget.plan, habits);
                _resyncReminders();
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _add() async {
    final wake = _wake;
    if (wake == null) return;
    var help = false;
    final picked = await showPlanAddSheet(context,
        plan: widget.plan, bedtime: _bedtime, wake: wake, onHelpMePick: () => help = true);
    if (help && mounted) {
      await _helpMePick();
      return;
    }
    if (picked == null || !mounted) return;
    // 先開設定頁，按了 Add 才真的加進計畫（使用者 11-19 定）
    final out = await openPlanHabitEditor(context, item: picked, bedtime: _bedtime, wake: wake, isNew: true);
    if (out?.item == null) return;
    await widget.plan.add(out!.item!);
    _resyncReminders();
  }

  @override
  Widget build(BuildContext context) {
    final wake = _wake;
    final today = wake == null ? null : planDayOf(widget.clock(), wake);
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    // 背景用 cover、靠上對齊：圖實際畫出來的高度
    final imgH = math.max(size.height, size.width * kPlanRoomAspect);
    final rugY = imgH * kPlanRugCenter;
    const petSize = 200.0;
    // 清單從寵物腳下開始捲，**不蓋過寵物**（使用者 11-19 定：要看得到牠跳）
    final listTop = rugY + petSize * 0.22;
    return ReportFont(
      child: Scaffold(
        backgroundColor: ReportColors.bgMid,
        body: Stack(
          children: [
            Positioned.fill(child: _room()),
            // 寵物固定在地毯上；清單只在牠腳下那一塊捲動
            Positioned(
              left: 0,
              right: 0,
              top: rugY - petSize * 0.82,
              child: Center(child: _pet(petSize)),
            ),
            // 等級條在寵物頭上（同首頁，11-21 使用者定）；不能比標題列還高
            if (_game != null)
              Positioned(
                left: 0,
                right: 0,
                top: math.max(pad.top + 60, rugY - petSize * 0.82 - 46),
                child: Center(
                  child: LevelProgress(game: _game!, onTap: _openRewards),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: listTop,
              bottom: 0,
              // 上緣淡出：卡片捲上去時是慢慢消失，不是被一刀切掉
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (r) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xFF000000)],
                  stops: [0, 0.06],
                ).createShader(r),
                child: ListView(
                key: const Key('plan-list'),
                // 底部要讓出系統導覽列，不然最後一張卡的 Claim 會壓在手勢列底下
                padding: EdgeInsets.fromLTRB(18, 14, 18, 32 + pad.bottom),
                children: [
                  // 有 Journey 時作息跟路合成一張卡（11-19 使用者定）
                  if (widget.journey != null)
                    JourneySection(
                      controller: widget.journey!,
                      onStart: () => unawaited(_startJourney()),
                      bedtime: _bedtime,
                      wake: wake,
                      onEditSchedule: _editSchedule,
                    )
                  else
                    _ScheduleBar(bedtime: _bedtime, wake: wake, onTap: _editSchedule),
                  _habitHeader(today),
                  const SizedBox(height: 10),
                  if (today != null) ..._habitRows(today, wake!),
                  const SizedBox(height: 26),
                  _quests(),
                ],
              ),
              ),
            ),
            // 頂端固定：返回鍵＋標題，底下墊一層漸層，卡片捲上來時字還讀得到
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: pad.top + 72,
              child: const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xCC0B1636), Color(0x000B1636)],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 8,
              top: pad.top + 4,
              child: IconButton(
                key: const Key('plan-back'),
                onPressed: () => Navigator.of(context).maybePop(),
                style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.25)),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
            ),
            Positioned(
              left: 64,
              right: 16,
              top: pad.top + 12,
              child: const Text(
                'Your sleep plan',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  shadows: [Shadow(blurRadius: 10, color: Colors.black54)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 背景與寵物 ───────────────────────────────────────────────────

  Widget _room() => Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            kPlanRoomAsset,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (_, _, _) => Image.asset(
              'assets/backgrounds/report_dawn.jpg',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (_, _, _) => const ColoredBox(color: ReportColors.hill),
            ),
          ),
          // 地板往下再壓暗一點：白字卡片與區段標題疊在上面才讀得清楚
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00131D4A), Color(0x00131D4A), Color(0x99131D4A), Color(0xD9131D4A)],
                stops: [0, 0.5, 0.75, 1],
              ),
            ),
          ),
        ],
      );

  /// 寵物＋勾下去時跳一下（11-19 使用者：原本整張平移上下像被線提起來，改成自然的跳）。
  /// 不冒星星：方格那邊已經有光點和 Nice!，兩邊同時演眼睛不知道看哪。
  /// 腳下一直有淡影子，跳高時變小變淡。減少動態效果時 [_hop] 不會跑，就是靜止的。
  Widget _pet(double size) => AnimatedBuilder(
        key: const Key('plan-pet'),
        animation: _hop,
        builder: (context, child) {
          final j = petJumpPose(_hop.isAnimating ? _hop.value : 0.0);
          final feetY = size * 0.84;
          final shadowW = size * 0.46 * (1 - 0.35 * j.lift);
          return SizedBox(
            width: size,
            height: size,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: (size - shadowW) / 2,
                  top: feetY - size * 0.04,
                  child: IgnorePointer(
                    child: Container(
                      key: const Key('plan-pet-shadow'),
                      width: shadowW,
                      height: size * 0.08,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.elliptical(shadowW / 2, size * 0.04)),
                        color: Colors.black.withValues(alpha: 0.24 * (1 - 0.55 * j.lift)),
                      ),
                    ),
                  ),
                ),
                Transform.translate(
                  key: const Key('plan-pet-body'),
                  offset: Offset(0, -j.lift * size * 0.17),
                  child: Transform(
                    // 從腳底壓扁／拉長，不是從中心
                    alignment: Alignment(0, feetY / size * 2 - 1),
                    transform: Matrix4.diagonal3Values(j.scaleX, j.scaleY, 1),
                    child: child,
                  ),
                ),
              ],
            ),
          );
        },
        child: HomePet(mood: _mood, size: size),
      );

  void _cheer() {
    if (MediaQuery.disableAnimationsOf(context)) return;
    _hop.forward(from: 0);
  }

  // ── 習慣 ─────────────────────────────────────────────────────────

  Widget _habitHeader(DateTime? today) {
    String line;
    if (today == null || !widget.plan.loaded) {
      line = ' ';
    } else if (widget.plan.items.isEmpty) {
      line = 'Add a few small habits';
    } else {
      final due = widget.plan.dueOn(today);
      final left = due.where((i) => !widget.plan.isChecked(i.id, today)).length;
      line = due.isEmpty
          ? 'Nothing planned for today'
          : left == 0
              ? 'All done for today'
              : '$left ${left == 1 ? 'habit' : 'habits'} left for today';
    }
    final full = widget.plan.items.length >= kMaxPlanItems;
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Row(
        children: [
          const Icon(Icons.event_note_rounded, color: ReportColors.lilac, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(line,
                key: const Key('plan-left-today'),
                style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900, shadows: _onFloor)),
          ),
          IconButton(
            key: const Key('plan-add'),
            onPressed: full ? null : _add,
            tooltip: full ? 'Your plan is full ($kMaxPlanItems)' : 'Add a habit',
            style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.12)),
            icon: const Icon(Icons.add_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  List<Widget> _habitRows(DateTime today, TimeOfDay wake) {
    final items = widget.plan.items;
    if (items.isEmpty) {
      return [
        InkWell(
          key: const Key('plan-empty'),
          borderRadius: BorderRadius.circular(24),
          onTap: _add,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: reportCard(radius: 24, dashed: true),
            child: const Text(
              'Pick a few small habits to support your schedule. They never change your score.',
              style: TextStyle(color: ReportColors.soft, fontSize: 13.5, height: 1.4),
            ),
          ),
        ),
      ];
    }
    return [
      for (final item in items)
        _HabitCard(
          item: item,
          due: item.onWeekday(today.weekday),
          checked: widget.plan.isChecked(item.id, today),
          streak: widget.plan.streak(item.id, today),
          time: itemTime(item, bedtime: _bedtime, wake: wake),
          onToggle: () => widget.plan.setChecked(item.id, today, !widget.plan.isChecked(item.id, today)),
          onChecked: _cheer,
          onTap: () => _openEditor(item),
        ),
    ];
  }

  // ── Quests（量測的挑戰）──────────────────────────────────────────

  List<ChallengeProgress> _pick(ChallengesResult? r, List<String> ids) {
    if (r == null || r.status != ChallengesStatus.ok) return const [];
    return [for (final id in ids) ...r.challenges.where((c) => c.challengeId == id)];
  }

  Widget _quests() {
    final r = _fresh ?? widget.nightly?.challenges;
    final list = _pick(r, _weekly ? kWeekIds : kMeasuredIds);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Quests',
                  style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900, shadows: _onFloor)),
            ),
            _Tabs(weekly: _weekly, onChanged: (w) => setState(() => _weekly = w)),
          ],
        ),
        const SizedBox(height: 4),
        const Text('Measured by your phone and watch, from your last recorded night.',
            style: TextStyle(color: ReportColors.soft, fontSize: 12, shadows: _onFloor)),
        const SizedBox(height: 12),
        if (list.isEmpty)
          // ⚠️ 量不到時照實說，不畫成沒做到
          Text(
            r == null || r.status == ChallengesStatus.noBackend
                ? 'These need the Sonnap server.'
                : r.status == ChallengesStatus.ok
                    ? 'Nothing here yet.'
                    : "Couldn't reach the Sonnap server.",
            key: const Key('plan-measured-unavailable'),
            style: const TextStyle(color: ReportColors.dim, fontSize: 12.5),
          )
        else
          for (final c in list)
            _QuestCard(
              challenge: c,
              claimable: _claimable.where((x) => x.challengeId == c.challengeId).firstOrNull,
              claiming: _claiming == c.challengeId,
              onClaim: _claim,
            ),
      ],
    );
  }
}

String _hm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class _ScheduleBar extends StatelessWidget {
  final TimeOfDay bedtime;
  final TimeOfDay? wake;
  final VoidCallback onTap;
  const _ScheduleBar({required this.bedtime, required this.wake, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final w = wake;
    final span = w == null ? null : sleepSpan(bedtime, w);
    Widget part(IconData icon, String value, Key key) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: ReportColors.gold),
            const SizedBox(width: 6),
            Text(value, key: key,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
          ],
        );
    return Material(
      key: const Key('plan-schedule'),
      color: const Color(0xF2262C66),
      elevation: 6,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: ReportColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
          child: Row(
            children: [
              part(Icons.bedtime_rounded, _hm(bedtime), const Key('plan-bedtime')),
              const SizedBox(width: 16),
              part(Icons.wb_sunny_rounded, w == null ? '—' : _hm(w), const Key('plan-wake')),
              const Spacer(),
              // 只寫事實：幾小時。不判斷夠不夠（好壞只有後端能判）。
              if (span != null)
                Text(reportHm(span.inMinutes),
                    style: const TextStyle(color: ReportColors.muted, fontSize: 13, fontWeight: FontWeight.w700)),
              const Icon(Icons.chevron_right_rounded, color: ReportColors.accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// 左邊插圖格（有使用者的圖就用，沒有退回 Material 圖示）。
class _IconTile extends StatelessWidget {
  final String asset;
  final IconData fallback;
  final double size;
  const _IconTile({required this.asset, required this.fallback, this.size = 58});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Image.asset(
          asset,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Icon(fallback, color: ReportColors.gold, size: size * 0.5),
        ),
      );
}

/// 習慣一列（11-19 使用者選 A：照參考圖精簡成一列，高度約原本一半）。
/// 圖示 40、字最多兩行、時間小字放右邊、勾勾 42。「睡前 50 分」那種相對說法在編輯頁看得到。
class _HabitCard extends StatelessWidget {
  final PlanItem item;
  final bool due;
  final bool checked;
  final int streak;
  final TimeOfDay time;
  final VoidCallback onToggle;
  final VoidCallback onChecked;
  final VoidCallback onTap;

  const _HabitCard({
    required this.item,
    required this.due,
    required this.checked,
    required this.streak,
    required this.time,
    required this.onToggle,
    required this.onChecked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: due ? 1 : 0.5,
      child: Container(
        key: Key('plan-habit-${item.id}'),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0xE62A3070),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ReportColors.border),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(
                children: [
                  _IconTile(asset: planIconAsset(item.id), fallback: item.icon, size: 42),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(item.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w800, height: 1.2)),
                        if (streak >= 2)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text('$streak days in a row',
                                key: Key('plan-streak-${item.id}'),
                                style: const TextStyle(
                                    color: ReportColors.gold, fontSize: 11, fontWeight: FontWeight.w800)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(due ? _hm(time) : 'Not today',
                          key: Key('plan-time-${item.id}'),
                          style: const TextStyle(
                              color: ReportColors.muted, fontSize: 12, fontWeight: FontWeight.w700)),
                      if (item.notify)
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.notifications_active_rounded, size: 12, color: ReportColors.dim),
                        ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  // ⚠️ 沒勾是空的方格，不打叉、不用紅；勾下去只有當下的回饋（Q36）
                  PlanCheckButton(
                    key: Key('plan-check-${item.id}'),
                    checked: checked,
                    enabled: due,
                    onToggle: onToggle,
                    onChecked: onChecked,
                    size: 42,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  final bool weekly;
  final ValueChanged<bool> onChanged;
  const _Tabs({required this.weekly, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, bool on, bool value, Key key) => GestureDetector(
          key: key,
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: on ? ReportColors.purple : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(label,
                style: TextStyle(
                    color: on ? Colors.white : ReportColors.muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8)),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          tab('DAILY', !weekly, false, const Key('plan-tab-daily')),
          tab('WEEKLY', weekly, true, const Key('plan-tab-weekly')),
        ],
      ),
    );
  }
}

const Map<String, IconData> _questIcons = {
  'on_time_tonight': Icons.phonelink_lock_rounded,
  'phone_in_bed_tonight': Icons.bed_rounded,
  'up_on_time': Icons.wb_sunny_rounded,
  'streak_nights': Icons.local_fire_department_rounded,
  'bedtime_consistency_7d': Icons.timeline_rounded,
};

/// 任務一列（11-19 使用者選 A）：圖示 40、標題一行、細進度條，右邊 ✓／—／Claim。
/// 後端那句說明（「還差 2 晚」）**點一下才展開**——少字，但照樣整句照抄、不改寫。
class _QuestCard extends StatefulWidget {
  final ChallengeProgress challenge;
  final ClaimableReward? claimable;
  final bool claiming;
  final ValueChanged<ClaimableReward> onClaim;

  const _QuestCard({
    required this.challenge,
    required this.claimable,
    required this.claiming,
    required this.onClaim,
  });

  @override
  State<_QuestCard> createState() => _QuestCardState();
}

class _QuestCardState extends State<_QuestCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.challenge;
    final done = c.state == ChallengeState.completed;
    final noData = c.state == ChallengeState.insufficientData;
    final reward = widget.claimable;
    return Container(
      key: Key('plan-measured-${c.challengeId}'),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: reward != null ? const Color(0xEB3A3466) : const Color(0xE6242A62),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: reward != null ? const Color(0x80FFD772) : ReportColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('plan-measured-tap-${c.challengeId}'),
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _IconTile(
                          asset: 'assets/plan/${c.challengeId}.png',
                          fallback: _questIcons[c.challengeId] ?? Icons.flag_rounded,
                          size: 42,
                        ),
                        // XP 照抄 /game 的 claimable（能領的才寫，不寫死幾點）
                        if (reward != null && reward.xp > 0)
                          Positioned(
                            right: -6,
                            bottom: -6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('+${reward.xp}',
                                  style: const TextStyle(
                                      color: ReportColors.navy, fontSize: 10, fontWeight: FontWeight.w900)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(c.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          _bar(c),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 64,
                      height: 42,
                      child: Center(
                        child: reward != null
                            ? FilledButton(
                                key: Key('plan-claim-${c.challengeId}'),
                                onPressed: widget.claiming ? null : () => widget.onClaim(reward),
                                style: FilledButton.styleFrom(
                                  backgroundColor: ReportColors.gold,
                                  foregroundColor: ReportColors.navy,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  minimumSize: const Size(0, 36),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Claim!',
                                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                              )
                            : noData
                                // ⚠️ 沒量到寫「—」，不是空的（空的＝沒做到）
                                ? const Text('—',
                                    key: Key('plan-measured-nodata'),
                                    style: TextStyle(
                                        color: ReportColors.dim, fontSize: 20, fontWeight: FontWeight.w800))
                                : Icon(done ? Icons.check_rounded : Icons.more_horiz_rounded,
                                    color: done ? ReportColors.down : ReportColors.dim, size: done ? 28 : 22),
                      ),
                    ),
                  ],
                ),
                // ⚠️ 整句照抄後端，點一下才出現
                if (_open)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(52, 6, 8, 2),
                    child: Text(c.detail,
                        key: Key('plan-measured-detail-${c.challengeId}'),
                        style: const TextStyle(color: ReportColors.muted, fontSize: 12, height: 1.3)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bar(ChallengeProgress c) {
    final p = c.progress;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        // 照抄後端的 progress；沒有就是空槽（旁邊寫「—」、點開那句說沒量到，不寫 0%）
        value: p?.clamp(0.0, 1.0) ?? 0,
        minHeight: 6,
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        valueColor: AlwaysStoppedAnimation<Color>(
          c.state == ChallengeState.completed ? ReportColors.gold : ReportColors.lilac,
        ),
      ),
    );
  }
}
