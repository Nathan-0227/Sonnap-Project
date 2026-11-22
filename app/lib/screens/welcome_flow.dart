import 'package:flutter/material.dart';

import '../theme/app_accent.dart';
import '../services/key_value_store.dart';
import '../services/pet_choice.dart';
import '../widgets/entry_intro.dart';
import '../widgets/home_pet.dart';
import '../widgets/plan_goal_picker.dart';
import '../widgets/sleep_dial.dart';

/// 第一次登入的流程（2026-11-22 grill Q9–Q14，取代原本只有一頁暱稱的 OnboardingScreen）。
///
/// 歡迎 → 暱稱 → 寵物 → 作息 → 想改善什麼 → 權限 → 完成。每一頁一件事、上面一排進度點，**每一頁都能跳過**。
/// 「想改善什麼」照 `睡眠計畫.md`「目標 → 建議」（11-22 使用者審過），元件跟計畫頁的 Help me pick 共用。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 這個流程一定要能被跳過、而且建不了帳號也不能擋住 App
/// ═══════════════════════════════════════════════════════════════════
/// 後端沒開是 demo 的常態。最後一步才一次送出（Q12）：送不出去時完成頁照實說，照樣進 App；
/// 跳過不寫進儲存（下次開 App 再問一次），理由同原本的暱稱畫面。
///
/// ⚠️ 不得出現「安全」「加密」這類字眼：暱稱制免註冊，user_id 本身就是憑證（account_test 守著）。
/// ⚠️ 權限說明要跟實際做的事一致（2026-11-22 查過原生端）：讀的是螢幕亮暗、解鎖的時間與每個 App 開了多久；
///    送出手機的只有時間與手機型號，App 名字只在手機上顯示。改原生端就要回來改這段話。

enum WelcomeStep { welcome, name, pet, schedule, goals, permissions, done }

/// 走完流程要存的東西。[name] 是 null＝跳過暱稱（不建帳號）。
/// [goals] 是空的＝跳過「想改善什麼」；[habits] 是推薦頁勾著的那幾條（建議清單的 id）。
@immutable
class WelcomeResult {
  final String? name;
  final TimeOfDay bedtime;
  final TimeOfDay wake;
  final List<String> goals;
  final List<String> habits;
  const WelcomeResult({
    required this.name,
    required this.bedtime,
    required this.wake,
    this.goals = const [],
    this.habits = const [],
  });
}

/// 權限那一頁要用到的兩件事（測試注入假的）。
abstract class WelcomePermissions {
  Future<bool> hasUsageAccess();
  Future<void> openUsageSettings();
  Future<void> requestNotifications();
}

/// 暱稱的檢查（跟原本的暱稱畫面同一套）。null＝可以。
String? nicknameProblem(String name) {
  final t = name.trim();
  if (t.isEmpty) return 'Pick any name you like.';
  if (t.length > 40) return 'Keep it under 40 characters.';
  return null;
}

class WelcomeFlow extends StatefulWidget {
  /// true＝從設定頁的 Replay welcome 進來：不建帳號，暱稱改了走 PATCH（Q11）。
  final bool replay;
  final String? initialName;
  final TimeOfDay initialBedtime;
  final TimeOfDay initialWake;

  /// Journey 進行中：作息由 Journey 決定，這一頁只顯示、不能轉（同 showSleepScheduleSheet 的鎖）。
  final bool scheduleLocked;

  /// 寵物選擇存在這裡（同設定頁）。
  final KeyValueStore store;

  /// 已經在計畫裡的習慣（Replay 時不再推薦）。
  final Set<String> alreadyInPlan;
  final WelcomePermissions permissions;

  /// 進到完成頁時呼叫一次。回 null＝都存好了；否則是完成頁要照實說的那句（照樣能進 App）。
  final Future<String?> Function(WelcomeResult result) onFinish;

  /// 按完成頁的按鈕：進 App。
  final VoidCallback onDone;

  /// 完成頁那隻寵物。按 Let's go 之後首頁從天空降下來，寵物從這個位置飄到山頂（進場動畫長版）。
  final GlobalKey? donePetKey;

  /// 歡迎頁的開場動畫（星星亮起、寵物浮上來、字依序進來；`WelcomeOpening`）。只有正式的 App 打開，測試預設關。
  final bool animateOpening;

  const WelcomeFlow({
    this.donePetKey,
    this.animateOpening = false,
    super.key,
    this.replay = false,
    this.initialName,
    required this.initialBedtime,
    required this.initialWake,
    this.scheduleLocked = false,
    required this.store,
    this.alreadyInPlan = const {},
    required this.permissions,
    required this.onFinish,
    required this.onDone,
  });

  @override
  State<WelcomeFlow> createState() => _WelcomeFlowState();
}

const _dim = Color(0xFF9AA8C7);
const _font = 'Nunito';

class _WelcomeFlowState extends State<WelcomeFlow>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  WelcomeStep _step = WelcomeStep.welcome;
  late final TextEditingController _name = TextEditingController(text: widget.initialName ?? '');
  String? _nameError;
  bool _nameSkipped = false;
  late TimeOfDay _bed = widget.initialBedtime;
  late TimeOfDay _wake = widget.initialWake;
  List<String> _goals = const [];
  List<String> _habits = const [];
  bool _usageOn = false;
  bool _notifyAsked = false;
  bool _finishing = false;
  String? _finishProblem;

  /// 開場動畫（null＝不播）。
  AnimationController? _opening;

  WelcomeOpening get _open {
    final c = _opening;
    if (c == null || !c.isAnimating || _step != WelcomeStep.welcome) return WelcomeOpening.rest;
    return WelcomeOpening.at(c.value * WelcomeOpening.seconds);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.animateOpening && _opening == null && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _opening = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: (WelcomeOpening.seconds * 1000).round()),
      )
        ..addListener(() => setState(() {}))
        ..forward();
    }
  }

  /// 開場時一個元件淡入、往上浮一點（沒在播時原樣）。
  Widget _fadeUp(double p, Widget child, {double dy = 14}) => p >= 1
      ? child
      : Opacity(opacity: p, child: Transform.translate(offset: Offset(0, (1 - p) * dy), child: child));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkUsage();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _opening?.dispose();
    _name.dispose();
    super.dispose();
  }

  /// 從系統設定回來：重新查一次（openUsageSettings 拿不到使用者按了什麼）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkUsage();
  }

  Future<void> _checkUsage() async {
    final on = await widget.permissions.hasUsageAccess();
    if (mounted && on != _usageOn) setState(() => _usageOn = on);
  }

  static const _order = WelcomeStep.values;

  void _go(WelcomeStep step) {
    setState(() => _step = step);
    if (step == WelcomeStep.done) _finish();
  }

  void _next() => _go(_order[_step.index + 1]);
  void _back() => _go(_order[_step.index - 1]);

  Future<void> _finish() async {
    setState(() {
      _finishing = true;
      _finishProblem = null;
    });
    final name = _nameSkipped ? null : _name.text.trim();
    final problem = await widget.onFinish(WelcomeResult(
      name: (name == null || name.isEmpty) ? null : name,
      bedtime: _bed,
      wake: _wake,
      goals: _goals,
      habits: _habits,
    ));
    if (!mounted) return;
    setState(() {
      _finishing = false;
      _finishProblem = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('welcome-flow'),
      backgroundColor: kEntrySkyTop,
      // 背景是首頁山頂上方那一片天空（進場動畫長版）：按 Let's go 之後鏡頭從這裡往下降到首頁。
      body: Stack(
        children: [
        Positioned.fill(child: EntrySky(starOpacity: _open.stars)),
        SafeArea(
          child: DefaultTextStyle.merge(
            style: const TextStyle(fontFamily: _font, color: Colors.white),
            child: Column(
              children: [
                _fadeUp(_open.topBar, _topBar(), dy: 0),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: MediaQuery.maybeDisableAnimationsOf(context) ?? false
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    // ⚠️ 淡出中的舊頁不能點：不然連點兩下「Next」會一次跳兩頁
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: IgnorePointer(ignoring: child.key != ValueKey(_step), child: child),
                    ),
                    child: KeyedSubtree(key: ValueKey(_step), child: _page()),
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

  /// 上面：返回（第一頁與完成頁沒有）、進度點、Skip（歡迎頁與完成頁沒有）。
  Widget _topBar() {
    final canBack = _step != WelcomeStep.welcome && _step != WelcomeStep.done;
    final canSkip = _step != WelcomeStep.welcome && _step != WelcomeStep.done;
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: canBack
                ? IconButton(
                    key: const Key('welcome-back'),
                    tooltip: 'Back',
                    onPressed: _back,
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
                  )
                : null,
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final s in _order)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: s == _step ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: s.index <= _step.index ? accentOf(context) : const Color(0x33FFFFFF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 64,
            child: canSkip
                ? TextButton(
                    key: const Key('welcome-skip'),
                    onPressed: _skip,
                    child: const Text('Skip', style: TextStyle(color: _dim, fontFamily: _font)),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  /// 跳過這一頁＝用原本的值（暱稱跳過＝不建帳號），往下一頁。
  void _skip() {
    switch (_step) {
      case WelcomeStep.name:
        _nameSkipped = true;
        _nameError = null;
      case WelcomeStep.schedule:
        _bed = widget.initialBedtime;
        _wake = widget.initialWake;
      case WelcomeStep.goals:
        _goals = const [];
        _habits = const [];
      default:
        break;
    }
    _next();
  }

  Widget _page() => switch (_step) {
    WelcomeStep.welcome => _welcome(),
    WelcomeStep.name => _namePage(),
    WelcomeStep.pet => _petPage(),
    WelcomeStep.schedule => _schedulePage(),
    WelcomeStep.goals => _goalsPage(),
    WelcomeStep.permissions => _permissionsPage(),
    WelcomeStep.done => _donePage(),
  };

  // ── 共用 ──────────────────────────────────────────────────────

  Widget _layout({
    required String title,
    String? subtitle,
    required Widget body,
    required Widget bottom,
  }) =>
      LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight - 28),
            // 內容少的頁面按鈕貼底（IntrinsicHeight 才放得進 Spacer）；內容多的照樣能捲
            child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _fadeUp(_open.title, Text(title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.2))),
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  _fadeUp(_open.subtitle, Text(subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15, color: _dim, height: 1.35))),
                ],
                const SizedBox(height: 24),
                body,
                const Spacer(),
                const SizedBox(height: 24),
                _fadeUp(_open.button, bottom),
              ],
            ),
            ),
          ),
        ),
      );

  Widget _primary(String label, VoidCallback? onPressed, {Key? key}) => SizedBox(
    height: 54,
    child: FilledButton(
      key: key ?? const Key('welcome-next'),
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: accentOf(context),
        disabledBackgroundColor: const Color(0x337657FF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, fontFamily: _font)),
    ),
  );

  Widget _pet(double size, {String mood = 'happy'}) => ValueListenableBuilder<PetSpecies>(
    valueListenable: PetChoice.current,
    builder: (context, species, _) => SizedBox(
      width: size,
      height: size,
      child: IgnorePointer(child: HomePet(mood: mood, species: species, size: size, animate: false)),
    ),
  );

  // ── 1 歡迎 ────────────────────────────────────────────────────

  Widget _welcome() => _layout(
    title: 'Welcome to Sonnap',
    subtitle: 'Your sleep becomes your buddy\'s day.',
    body: Column(
      children: [
        _fadeUp(_open.pet, Center(child: _pet(150)), dy: 24),
        const SizedBox(height: 20),
        _fadeUp(_open.body, Column(children: [
          _point(Icons.watch_rounded, 'If you wear a watch, it measures your sleep.'),
          _point(Icons.phone_android_rounded, 'Your phone notices when you put it down at night.'),
          _point(Icons.pets_rounded, 'Your buddy\'s mood follows your nights.'),
        ])),
      ],
    ),
    bottom: _primary('Get started', _next, key: const Key('welcome-start')),
  );

  Widget _point(IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: const Color(0x22FFFFFF), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: const Color(0xFFC9B8FF), size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 16, height: 1.3))),
      ],
    ),
  );

  // ── 2 暱稱 ────────────────────────────────────────────────────

  Widget _namePage() => _layout(
    title: 'What should we call you?',
    subtitle: 'A nickname is enough. No email, no password.',
    body: TextField(
      key: const Key('welcome-name'),
      controller: _name,
      autofocus: false,
      maxLength: 40,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submitName(),
      style: const TextStyle(color: Colors.white, fontSize: 18, fontFamily: _font),
      decoration: InputDecoration(
        hintText: 'Nickname',
        hintStyle: const TextStyle(color: Color(0xFF5B6E8C)),
        counterText: '',
        errorText: _nameError,
        filled: true,
        fillColor: const Color(0x1AFFFFFF),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      ),
    ),
    bottom: _primary('Next', _submitName),
  );

  void _submitName() {
    final problem = nicknameProblem(_name.text);
    if (problem != null) {
      setState(() => _nameError = problem);
      return;
    }
    _nameSkipped = false;
    _nameError = null;
    _next();
  }

  // ── 3 寵物 ────────────────────────────────────────────────────

  Widget _petPage() => _layout(
    title: 'Pick your buddy',
    subtitle: 'You can switch anytime in Settings.',
    body: ValueListenableBuilder<PetSpecies>(
      valueListenable: PetChoice.current,
      builder: (context, chosen, _) => Row(
        children: [
          for (final s in PetSpecies.values) ...[
            if (s != PetSpecies.values.first) const SizedBox(width: 14),
            Expanded(child: _petCard(s, chosen == s)),
          ],
        ],
      ),
    ),
    bottom: _primary('Next', _next),
  );

  Widget _petCard(PetSpecies s, bool chosen) => Semantics(
    button: true,
    selected: chosen,
    label: petSpeciesLabel(s),
    child: GestureDetector(
      key: Key('welcome-pet-${s.name}'),
      onTap: () => PetChoice.choose(widget.store, s),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: chosen ? const Color(0x337657FF) : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: chosen ? accentOf(context) : const Color(0x22FFFFFF), width: chosen ? 2.5 : 1),
        ),
        child: Column(
          children: [
            // 寵物自己可以點（會有反應），會把點擊吃掉 → 交給外層的卡片
            IgnorePointer(child: SizedBox(width: 120, height: 120, child: HomePet(mood: 'happy', species: s, size: 120, animate: false))),
            const SizedBox(height: 8),
            Text(petSpeciesLabel(s), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    ),
  );

  // ── 4 作息 ────────────────────────────────────────────────────

  String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _schedulePage() => _layout(
    title: 'When do you usually sleep?',
    subtitle: widget.scheduleLocked
        ? 'Your Journey is setting your schedule right now.'
        : 'Drag the moon and the sun. You can change this anytime.',
    body: Column(
      children: [
        // 中間只寫睡幾小時、不判斷好壞（同首頁那個轉盤）
        IgnorePointer(
          ignoring: widget.scheduleLocked,
          child: SleepDial(
            key: const Key('welcome-dial'),
            bedtime: _bed,
            wake: _wake,
            size: 260,
            bedLocked: widget.scheduleLocked,
            onBedtimeChanged: (t) => setState(() => _bed = t),
            onWakeChanged: (t) => setState(() => _wake = t),
          ),
        ),
        const SizedBox(height: 16),
        // 窄螢幕或字大時放不下就換行（不溢出）
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: [
            _timeChip(Icons.nightlight_round, 'Bedtime', _hhmm(_bed), const Key('welcome-bedtime')),
            _timeChip(Icons.wb_sunny_rounded, 'Wake up', _hhmm(_wake), const Key('welcome-wake')),
          ],
        ),
      ],
    ),
    bottom: _primary('Next', _next),
  );

  Widget _timeChip(IconData icon, String label, String value, Key key) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(color: const Color(0x1AFFFFFF), borderRadius: BorderRadius.circular(16)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: const Color(0xFFC9B8FF)),
        const SizedBox(width: 8),
        Text('$label  ', style: const TextStyle(color: _dim, fontSize: 14)),
        Text(value, key: key, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      ],
    ),
  );

  // ── 5 想改善什麼 ───────────────────────────────────────────────

  /// 選完或跳過都往下一頁；真的加進計畫要等最後（onFinish）一次做。
  /// Journey 那一行在這裡只寫字（流程中間沒有地方可以帶過去）；Journey 進行中＝作息鎖住的那個狀態，就不提。
  Widget _goalsPage() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
    child: PlanGoalPicker(
      alreadyInPlan: widget.alreadyInPlan,
      journeyActive: widget.scheduleLocked,
      onDone: (goals, habits) {
        _goals = goals;
        _habits = habits;
        _next();
      },
    ),
  );

  // ── 6 權限 ────────────────────────────────────────────────────

  Widget _permissionsPage() => _layout(
    title: 'Two quick permissions',
    subtitle: 'Both are optional. Sonnap works without them, just with less to show.',
    body: Column(
      children: [
        _permissionCard(
          key: const Key('welcome-usage'),
          icon: Icons.phone_android_rounded,
          title: 'Usage access',
          text: 'Lets Sonnap see when you put your phone down at night. '
              'It also lists the apps you used in your last hour before bed, and that list stays on your phone. '
              'Only times and your phone model are sent to Sonnap. It can\'t see what\'s inside your apps.',
          done: _usageOn,
          doneLabel: 'On',
          action: 'Open settings',
          onTap: () => widget.permissions.openUsageSettings(),
        ),
        const SizedBox(height: 14),
        _permissionCard(
          key: const Key('welcome-notify'),
          icon: Icons.notifications_rounded,
          title: 'Notifications',
          text: 'For your bedtime reminder and your alarm.',
          done: _notifyAsked,
          // 系統視窗按了什麼拿不到，所以只寫問過了，不寫已開啟
          doneLabel: 'Asked',
          action: 'Allow',
          onTap: () async {
            await widget.permissions.requestNotifications();
            if (mounted) setState(() => _notifyAsked = true);
          },
        ),
      ],
    ),
    bottom: _primary('Continue', _next),
  );

  Widget _permissionCard({
    required Key key,
    required IconData icon,
    required String title,
    required String text,
    required bool done,
    required String doneLabel,
    required String action,
    required VoidCallback onTap,
  }) =>
      Container(
        key: key,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0x14FFFFFF), borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFFC9B8FF)),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              ],
            ),
            const SizedBox(height: 6),
            Text(text, style: const TextStyle(color: _dim, fontSize: 14, height: 1.4)),
            const SizedBox(height: 10),
            // 按鈕放在說明底下（跟標題同一列會把標題擠成好幾行）
            Align(
              alignment: Alignment.centerRight,
              child: done
                  ? Row(
                      key: Key('${(key as ValueKey).value}-done'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Color(0xFF6FE3D0), size: 20),
                        const SizedBox(width: 4),
                        Text(doneLabel, style: const TextStyle(color: Color(0xFF6FE3D0), fontWeight: FontWeight.w700)),
                      ],
                    )
                  : FilledButton.tonal(
                      key: Key('${(key as ValueKey).value}-action'),
                      onPressed: onTap,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0x337657FF),
                        foregroundColor: const Color(0xFFD9CCFF),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(action, style: const TextStyle(fontWeight: FontWeight.w800, fontFamily: _font)),
                    ),
            ),
          ],
        ),
      );

  // ── 6 完成 ────────────────────────────────────────────────────

  Widget _donePage() => _layout(
    title: 'You\'re all set',
    subtitle: 'Tap the moon when you go to bed. It\'s okay if you forget.',
    body: Column(
      children: [
        Center(child: KeyedSubtree(key: widget.donePetKey, child: _pet(150, mood: 'happy'))),
        if (_finishProblem case final p?) ...[
          const SizedBox(height: 16),
          Text(p,
              key: const Key('welcome-finish-problem'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFFFB4A8), fontSize: 14, height: 1.4)),
        ],
      ],
    ),
    bottom: _primary(_finishing ? 'Saving…' : 'Let\'s go', _finishing ? null : widget.onDone,
        key: const Key('welcome-done')),
  );
}
