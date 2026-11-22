import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/account_service.dart';
import '../services/alarm.dart';
import '../services/game_service.dart';
import '../services/key_value_store.dart';
import '../services/pet_choice.dart';
import '../widgets/report_sheet.dart';
import '../widgets/settings_list.dart';
import '../widgets/sleep_schedule_sheet.dart';
import '../widgets/week_mood_strip.dart' show MoodFace;

/// 設定頁（2026-11-22 grill 定案，畫布「A 分組＋B 名片」）。
///
/// - 最上面是**寵物名片**：寵物頭（照首頁那一份心情，沒有就是 bored）、暱稱、
///   三顆膠囊（Lv → 獎勵頁、Dog/Cat、邀請碼點了複製）、Edit name、Change pet。
/// - 底下分組：Sleep（作息轉盤、提醒開關、守門）／Friends／Data & devices／App。
/// - 🔴 **不放按了沒反應的東西**：原本的 Appearance、Language、Log Out、名片上的 email
///   都只會跳「以後才有」。Appearance（主題色、減少動態效果）與登入（Log out、Set up login）
///   各有自己的 PR；Language 先照實寫 English。
class SettingsScreen extends StatefulWidget {
  final String username;
  final String appVersion;

  final bool initialReminderOn;
  final TimeOfDay initialTargetBedtime;
  final ValueChanged<bool>? onReminderChanged;
  final ValueChanged<TimeOfDay>? onBedtimeChanged;

  /// 名片上寵物的心情（首頁那一份，`LatestNightRepository`）。null／拿不到＝bored。
  final Future<String?> Function()? petMood;

  /// 最近一晚換了就重讀 [petMood]。
  final Listenable? moodChanges;

  /// 等級（`/game`）。null＝這支 build 沒有後端，Lv 那顆不畫。
  final Future<GameState?> Function()? loadGame;

  /// 我的邀請碼（`/friends`）。null／拿不到＝那顆不畫。
  final Future<String?> Function()? loadInviteCode;

  /// 點 Lv 開獎勵頁。
  final VoidCallback? onOpenRewards;

  /// 改暱稱：回 null＝成功，否則是要顯示的那句話。null＝沒有後端。
  final Future<String?> Function(String name)? onRename;

  /// 換寵物；null＝用設定頁自己的面板。
  final VoidCallback? onPetTap;

  /// 從頭再走一次第一次登入的流程（2026-11-22 Q11）。null＝不畫那一列。
  final VoidCallback? onReplayWelcome;

  /// 打開就寢守門的設定頁（B4）。
  final VoidCallback? onBedtimeGuardTap;

  /// 打開 Health Connect 的設定頁（B8）。
  final VoidCallback? onHealthConnectTap;

  /// What friends can see（2026-11-15）。null＝這支 build 沒有後端，點了說要連上後端。
  final VoidCallback? onFriendSharingTap;

  /// 「Data」點開的那一整塊（資料是不是即時的、昨晚送到了沒、來源）。null＝不畫 Data 那一列。
  final Widget? dataSection;

  /// Data 那一列右邊的小字：true＝Live、false＝Bundled（⚠️ 退回打包檔時一定要寫出來）、null＝不寫。
  final bool? Function()? dataLive;

  /// 左上角的返回（回首頁）。null＝不畫。
  final VoidCallback? onBack;

  /// 這一頁現在在不在畫面上（IndexedStack）：一出現就重讀等級與邀請碼。
  final bool visible;

  /// 鬧鐘的設定存在哪、原生端是誰（可注入，測試換成假的）。
  final KeyValueStore store;
  final AlarmScheduler alarmScheduler;

  const SettingsScreen({
    super.key,
    this.username = kFallbackDisplayName,
    this.appVersion = "1.0",
    this.initialReminderOn = true,
    this.initialTargetBedtime = const TimeOfDay(hour: 23, minute: 30),
    this.onReminderChanged,
    this.onBedtimeChanged,
    this.petMood,
    this.moodChanges,
    this.loadGame,
    this.loadInviteCode,
    this.onOpenRewards,
    this.onRename,
    this.onPetTap,
    this.onReplayWelcome,
    this.onBedtimeGuardTap,
    this.onHealthConnectTap,
    this.onFriendSharingTap,
    this.dataSection,
    this.dataLive,
    this.onBack,
    this.visible = true,
    this.store = const PlatformKeyValueStore(),
    this.alarmScheduler = const PlatformAlarmScheduler(),
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

const _sub = kSettingsSub;
const _accent = kSettingsAccent;

class _SettingsScreenState extends State<SettingsScreen> {
  late bool reminderOn;
  late TimeOfDay targetBedtime;
  TimeOfDay? _wake;
  String? _mood;
  GameState? _game;
  String? _invite;

  @override
  void initState() {
    super.initState();
    reminderOn = widget.initialReminderOn;
    targetBedtime = widget.initialTargetBedtime;
    widget.moodChanges?.addListener(_loadMood);
    _loadWake();
    _loadMood();
    _loadCard();
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialReminderOn != widget.initialReminderOn) {
      reminderOn = widget.initialReminderOn;
    }
    if (oldWidget.initialTargetBedtime != widget.initialTargetBedtime) {
      targetBedtime = widget.initialTargetBedtime;
      _loadWake();
    }
    if (oldWidget.moodChanges != widget.moodChanges) {
      oldWidget.moodChanges?.removeListener(_loadMood);
      widget.moodChanges?.addListener(_loadMood);
    }
    if (widget.visible && !oldWidget.visible) {
      _loadCard();
      _loadWake();
    }
  }

  @override
  void dispose() {
    widget.moodChanges?.removeListener(_loadMood);
    super.dispose();
  }

  void _loadMood() {
    widget.petMood?.call().then((m) {
      if (mounted) setState(() => _mood = m);
    }, onError: (_) {});
  }

  void _loadCard() {
    widget.loadGame?.call().then((g) {
      if (mounted && g != null) setState(() => _game = g);
    }, onError: (_) {});
    widget.loadInviteCode?.call().then((c) {
      if (mounted && c != null && c.isNotEmpty) setState(() => _invite = c);
    }, onError: (_) {});
  }

  Future<void> _loadWake() async {
    try {
      final w = await AlarmSettingsStore(widget.store).wakeTime(targetBedtime);
      if (mounted) setState(() => _wake = w);
    } catch (_) {
      // 讀不到就只寫就寢時間
    }
  }

  String _hm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// 與首頁時鐘卡同一個轉盤（就寢＋起床＋鬧鐘開關；Journey 進行中鎖在轉盤裡）。
  Future<void> _pickBedtime() async {
    final result = await showSleepScheduleSheet(
      context,
      bedtime: targetBedtime,
      alarmSettings: AlarmSettingsStore(widget.store),
      scheduler: widget.alarmScheduler,
    );
    if (result == null || !mounted) return;
    setState(() => _wake = result.wake);
    if (result.bedtime == targetBedtime) return;
    setState(() => targetBedtime = result.bedtime);
    widget.onBedtimeChanged?.call(result.bedtime);
  }

  void _changeReminder(bool value) {
    setState(() => reminderOn = value);
    widget.onReminderChanged?.call(value);
  }

  /// 換寵物：兩張大卡（寵物頭＋名字），選中的主色框＋勾；點了就換、面板關掉。
  Future<void> _choosePet() async {
    final picked = await showReportSheet<PetSpecies>(
      context: context,
      builder: (context) => Container(
        key: const Key('pet-choice-sheet'),
        width: double.infinity,
        decoration: const BoxDecoration(
          color: kSettingsSheetColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your pet',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('Your buddy on every screen, and what friends see.',
                    style: TextStyle(color: _sub, fontSize: 13)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    for (final s in PetSpecies.values) ...[
                      if (s != PetSpecies.values.first) const SizedBox(width: 12),
                      Expanded(child: _PetCard(species: s, selected: s == PetChoice.current.value)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked != null) await PetChoice.choose(widget.store, picked);
  }

  void _say(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _editName() async {
    final rename = widget.onRename;
    if (rename == null) {
      _say("Changing your name needs Sonnap's server.");
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _EditNameDialog(initial: widget.username),
    );
    if (name == null || name == widget.username || !mounted) return;
    final error = await rename(name);
    if (!mounted) return;
    _say(error ?? 'Name updated.');
  }

  Future<void> _copyInvite(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) _say('Invite code copied.');
  }

  /// 設定頁點開的面板。⚠️ showReportSheet 的外框是透明的，底色要內容自己畫
  /// （2026-11-22 實機：Language 點開整片透明，字直接疊在設定頁上）。
  Future<void> _openSheet(Key key, String title, Widget body) => showReportSheet<void>(
        context: context,
        builder: (context) => Container(
          key: key,
          width: double.infinity,
          decoration: const BoxDecoration(
            color: kSettingsSheetColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  body,
                ],
              ),
            ),
          ),
        ),
      );

  void _showLanguage() => _openSheet(
        const Key('language-sheet'),
        'Language',
        const Text(
          'Sonnap is in English for now. Traditional Chinese is planned.',
          style: TextStyle(color: _sub, fontSize: 15, height: 1.4),
        ),
      );

  void _showData() {
    final section = widget.dataSection;
    if (section == null) return;
    _openSheet(const Key('data-sheet'), 'Data', section);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final live = widget.dataLive?.call();
    return SafeArea(
      child: Center(
        child: SizedBox(
          width: width > 520 ? 520 : width,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsHeader(title: 'Settings', onBack: widget.onBack),
                const SizedBox(height: 16),
                _profileCard(),
                const SizedBox(height: 20),
                SettingsGroup(title: 'SLEEP', rows: [
                  SettingsRow(
                    key: const Key('settings-sleep-schedule'),
                    icon: Icons.nightlight_round,
                    color: _accent,
                    title: 'Sleep schedule',
                    value: _wake == null ? _hm(targetBedtime) : '${_hm(targetBedtime)} → ${_hm(_wake!)}',
                    onTap: _pickBedtime,
                  ),
                  SettingsRow(
                    key: const Key('settings-reminder'),
                    icon: Icons.notifications_none_rounded,
                    color: const Color(0xFFE58A3A),
                    title: 'Bedtime reminder',
                    subtitle: '30 min before bedtime',
                    trailing: SettingsSwitch(
                      key: const Key('settings-reminder-switch'),
                      value: reminderOn,
                      onChanged: _changeReminder,
                    ),
                    onTap: () => _changeReminder(!reminderOn),
                  ),
                  SettingsRow(
                    key: const Key('settings-guard'),
                    icon: Icons.shield_outlined,
                    color: const Color(0xFFD2557A),
                    title: 'Bedtime guard',
                    subtitle: 'Remind or block chosen apps near bedtime',
                    onTap: widget.onBedtimeGuardTap ?? () => _say("Bedtime guard needs the Android app."),
                  ),
                ]),
                SettingsGroup(title: 'FRIENDS', rows: [
                  SettingsRow(
                    key: const Key('settings-friend-sharing'),
                    icon: Icons.visibility_outlined,
                    color: const Color(0xFF3B7DD8),
                    title: 'What friends can see',
                    onTap: widget.onFriendSharingTap ?? () => _say("Sharing with friends needs Sonnap's server."),
                  ),
                ]),
                SettingsGroup(title: 'DATA & DEVICES', rows: [
                  SettingsRow(
                    key: const Key('settings-health'),
                    icon: Icons.favorite_border_rounded,
                    color: const Color(0xFF2E9BB0),
                    title: 'Health Connect',
                    subtitle: 'Import sleep from your watch or band',
                    onTap: widget.onHealthConnectTap ?? () => _say("Health Connect needs Sonnap's server."),
                  ),
                  if (widget.dataSection != null)
                    SettingsRow(
                      key: const Key('settings-data'),
                      icon: Icons.storage_rounded,
                      color: const Color(0xFF5B6B9A),
                      title: 'Data',
                      trailing: live == null ? null : _DataBadge(live: live),
                      onTap: _showData,
                    ),
                ]),
                SettingsGroup(title: 'APP', rows: [
                  SettingsRow(
                    key: const Key('settings-language'),
                    title: 'Language',
                    value: 'English',
                    onTap: _showLanguage,
                  ),
                  if (widget.onReplayWelcome case final replay?)
                    SettingsRow(
                      key: const Key('settings-replay-welcome'),
                      title: 'Replay welcome',
                      subtitle: 'Walk through the first-time setup again',
                      onTap: replay,
                    ),
                  SettingsRow(
                    key: const Key('settings-about'),
                    title: 'About Sonnap',
                    value: widget.appVersion,
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileCard() {
    final game = _game;
    final invite = _invite;
    return Container(
      key: const Key('settings-profile'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A2C8C), Color(0xFF1B2552)],
        ),
      ),
      child: Column(
        children: [
          // 寵物頭跟著選的寵物換（MoodFace 自己聽 PetChoice），心情照首頁那一份；沒有＝bored
          MoodFace(mood: _mood ?? 'bored', size: 104),
          const SizedBox(height: 8),
          Text(
            widget.username,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              if (game != null)
                _Chip(
                  key: const Key('settings-level'),
                  label: 'Lv ${game.level}',
                  background: const Color(0xFFFFD66B),
                  foreground: const Color(0xFF3A2A00),
                  semantics: 'Level ${game.level}, open rewards',
                  onTap: widget.onOpenRewards,
                ),
              ValueListenableBuilder<PetSpecies>(
                valueListenable: PetChoice.current,
                builder: (_, s, _) => _Chip(key: const Key('settings-species'), label: petSpeciesLabel(s)),
              ),
              if (invite != null)
                _Chip(
                  key: const Key('settings-invite'),
                  label: invite,
                  icon: Icons.copy_rounded,
                  semantics: 'Invite code $invite, copy',
                  onTap: () => _copyInvite(invite),
                ),
            ],
          ),
          const SizedBox(height: 14),
          // 兩顆並排、一樣寬（Wrap 在窄的手機上會把第二顆擠到下一行）
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: const Key('settings-edit-name'),
                  onPressed: _editName,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF2A1F6B),
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  child: const Text('Edit name', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  key: const Key('settings-change-pet'),
                  onPressed: widget.onPetTap ?? _choosePet,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF8C7BE0)),
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  child: const Text('Change pet', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 換寵物面板裡的一張卡。
class _PetCard extends StatelessWidget {
  final PetSpecies species;
  final bool selected;
  const _PetCard({required this.species, required this.selected});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: petSpeciesLabel(species),
        excludeSemantics: true,
        child: Material(
          color: selected ? const Color(0xFF2A2470) : kSettingsCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: selected ? kSettingsAccent : kSettingsLine, width: selected ? 2.5 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: Key('pet-choice-${species.name}'),
            onTap: () => Navigator.of(context).pop(species),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
              child: Column(
                children: [
                  Image.asset(
                    'assets/moods/${species.name}_happy.png',
                    width: 88,
                    height: 88,
                    errorBuilder: (_, _, _) => const SizedBox(width: 88, height: 88),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(petSpeciesLabel(species),
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 6),
                      SettingsRadio(selected: selected),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// 改暱稱的對話框。⚠️ 輸入框的 controller 由它自己管：在呼叫端 dispose 的話，
/// 對話框還在淡出時就被釋放，會丟 "TextEditingController was used after being disposed"。
class _EditNameDialog extends StatefulWidget {
  final String initial;
  const _EditNameDialog({required this.initial});

  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: const Key('edit-name-dialog'),
        backgroundColor: const Color(0xFF10265A),
        title: const Text('Your name', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: TextField(
          key: const Key('edit-name-field'),
          controller: _c,
          autofocus: true,
          maxLength: 40,
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.white,
          decoration: const InputDecoration(
            counterStyle: TextStyle(color: _sub),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: _sub)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _sub)),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _c,
            builder: (context, v, _) => TextButton(
              key: const Key('edit-name-save'),
              onPressed: v.text.trim().isEmpty ? null : () => Navigator.pop(context, v.text.trim()),
              child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      );
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color background;
  final Color foreground;
  final String? semantics;
  final VoidCallback? onTap;

  const _Chip({
    super.key,
    required this.label,
    this.icon,
    this.background = const Color(0xFF2A3870),
    this.foreground = const Color(0xFFE6E9F7),
    this.semantics,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(15)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: foreground, fontSize: 13, fontWeight: FontWeight.w800)),
          if (icon != null) ...[
            const SizedBox(width: 5),
            Icon(icon, size: 13, color: foreground),
          ],
        ],
      ),
    );
    if (onTap == null) return chip;
    return Semantics(
      button: true,
      label: semantics ?? label,
      excludeSemantics: true,
      child: InkWell(borderRadius: BorderRadius.circular(15), onTap: onTap, child: chip),
    );
  }
}

/// Data 那一列右邊：Live 綠點、Bundled 黃點（⚠️ 退回打包檔時一定要照實寫，不能只畫綠的）。
class _DataBadge extends StatelessWidget {
  final bool live;
  const _DataBadge({required this.live});

  @override
  Widget build(BuildContext context) => Row(
        key: Key(live ? 'data-badge-live' : 'data-badge-bundled'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: live ? const Color(0xFF4FE0A0) : const Color(0xFFFFC83D),
            ),
          ),
          const SizedBox(width: 6),
          Text(live ? 'Live' : 'Bundled', style: const TextStyle(color: _sub, fontSize: 14)),
        ],
      );
}
