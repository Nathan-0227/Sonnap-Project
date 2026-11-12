import 'dart:async';

import 'package:flutter/material.dart';

import '../services/alarm.dart';
import '../services/bed_marks.dart';
import '../services/sleep_sounds.dart';
import '../widgets/sleep_schedule_sheet.dart';
import '../widgets/sleepy_pet.dart';
import '../widgets/slide_to_confirm.dart';

/// 按了「Start sleep」之後佔滿整個畫面的睡覺畫面（2026-11-12 定案）。
///
/// ⚠️ 幾條不能破的規則：
/// - **不讓螢幕常亮。** 我們是靠「手機什麼時候上鎖／解鎖」推就寢時刻
///   （`lights_out.dart`）。螢幕一直亮著，手機整晚不上鎖，那一晚就抓不到。
/// - **不放任何即時數據**，也不說「App 在量」：睡覺時 App 沒有在量東西，放上去等於造假。
///   副標寫 `Sleeping… your watch is tracking`（使用者定）——量的是手錶，這句是事實。
/// - **有 Cancel**：不小心按到開始的人，只能按「下床」離開的話會留下一筆兩分鐘
///   的假睡眠，而上床按鈕是驗證攝影機唯一的 ground truth。
/// - 返回鍵擋掉：只能用「下床」或「取消」離開。導覽列不在這一頁上。
///
/// 版面（2026-11-12 使用者定）：大時間 → 副標 → 睡著的寵物 → 鬧鐘列 → Out of bed 外框按鈕
/// → Cancel 小字。背景是房間（`assets/backgrounds/bedroom.png`，使用者生成；沒有就退回漸層）。
/// 點鬧鐘列打開跟外面一樣的轉盤（月亮鎖住），可以**改今晚的時間**或**關掉今晚**，轉盤上的設定不變。
/// 鬧鐘列下面是助眠聲音（喇叭鈕選聲音與時間、播放鈕播／停），按 Out of bed／Cancel 會停。
/// 「I already got up」在之後的 PR。
class SleepModeScreen extends StatefulWidget {
  final BedMarkStore store;
  final DateTime startAt;
  final DateTime Function() clock;

  /// 鬧鐘。null = 沒有鬧鐘（測試或舊的呼叫端）。
  final AlarmController? alarm;

  /// 助眠聲音。null = 不顯示那一列（測試或舊的呼叫端）。
  final SleepSoundsController? sounds;

  const SleepModeScreen({
    super.key,
    required this.store,
    required this.startAt,
    this.clock = DateTime.now,
    this.alarm,
    this.sounds,
  });

  @override
  State<SleepModeScreen> createState() => _SleepModeScreenState();
}

class _SleepModeScreenState extends State<SleepModeScreen> {
  Timer? _tick;

  /// 今晚鬧鐘排在幾點。null = 沒排、或使用者點了「只關今晚」。
  DateTime? _alarmAt;

  SleepSound _sound = SleepSound.rain;
  int _soundMinutes = kDefaultSleepSoundMinutes;

  /// 聲音幾點會停。null = 沒在播。
  DateTime? _soundEndsAt;

  bool get _soundPlaying {
    final end = _soundEndsAt;
    return end != null && widget.clock().isBefore(end);
  }

  @override
  void initState() {
    super.initState();
    _loadAlarm();
    _loadSounds();
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _loadAlarm() async {
    final at = await widget.alarm?.settings.tonight();
    if (mounted) setState(() => _alarmAt = at);
  }

  Future<void> _loadSounds() async {
    final sounds = widget.sounds;
    if (sounds == null) return;
    final sound = await sounds.settings.sound();
    final minutes = await sounds.settings.minutes();
    final endsAt = await sounds.player.endsAt();
    if (!mounted) return;
    setState(() {
      _sound = sound;
      _soundMinutes = minutes;
      _soundEndsAt = endsAt;
    });
  }

  Future<void> _toggleSound() async {
    final sounds = widget.sounds;
    if (sounds == null) return;
    if (_soundPlaying) {
      setState(() => _soundEndsAt = null);
      await sounds.stop();
    } else {
      final end = await sounds.play(widget.clock());
      if (mounted) setState(() => _soundEndsAt = end);
    }
  }

  /// 喇叭鈕：選聲音與播多久。正在播的話照新的選擇重播。
  Future<void> _pickSound() async {
    final sounds = widget.sounds;
    if (sounds == null) return;
    var sound = _sound;
    var minutes = _soundMinutes;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF1B2350),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sleep sounds',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in SleepSound.values)
                      ChoiceChip(
                        key: Key('sound-${s.id}'),
                        label: Text(s.label),
                        selected: sound == s,
                        onSelected: (_) => setSheet(() => sound = s),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Stop after',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in kSleepSoundMinutes)
                      ChoiceChip(
                        key: Key('sound-min-$m'),
                        label: Text('$m min'),
                        selected: minutes == m,
                        onSelected: (_) => setSheet(() => minutes = m),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('sound-done'),
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF8B7BFF),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await sounds.settings.save(sound, minutes);
    if (!mounted) return;
    setState(() {
      _sound = sound;
      _soundMinutes = minutes;
    });
    if (_soundPlaying) {
      final end = await sounds.play(widget.clock());
      if (mounted) setState(() => _soundEndsAt = end);
    }
  }

  /// 點鬧鐘那一列：打開跟外面一樣的轉盤（使用者定），月亮固定在按 Start Sleep 的時刻，
  /// 只撥太陽。**只改今晚**，轉盤上存的設定不變（Q4／Q10）。
  Future<void> _alarmMenu() async {
    final alarm = widget.alarm;
    if (alarm == null) return;
    final started = TimeOfDay.fromDateTime(widget.startAt);
    final current = _alarmAt;
    final wake = current != null
        ? TimeOfDay.fromDateTime(current)
        : await alarm.settings.wakeTime(started);
    if (!mounted) return;
    final result = await showTonightAlarmSheet(
      context,
      startedAt: started,
      wake: wake,
      alarmOn: current != null,
      scheduler: alarm.scheduler,
    );
    if (result == null || !mounted) return;
    if (!result.alarmEnabled) {
      await alarm.cancelTonight();
      if (mounted) setState(() => _alarmAt = null);
      return;
    }
    final at = await alarm.setTonightAt(widget.clock(), result.wake);
    if (!mounted) return;
    if (at == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text("That's more than 14 hours away, so nothing changed."),
        ),
      );
    } else {
      setState(() => _alarmAt = at);
    }
  }

  Future<void> _outOfBed() async {
    // 下床會取消鬧鐘；但鬧鐘響了不會反過來自動按下床（使用者決定）。
    unawaited(widget.sounds?.stop());
    await widget.alarm?.cancelTonight();
    await widget.store.markEnd(widget.clock());
    // 回傳 true = 這一晚結束了，首頁接著打開早晨報告（Cancel 不回 true）
    if (mounted) Navigator.of(context).pop(true);
  }

  /// 「I already got up」（2026-11-12）：忘了按 Out of bed，事後補起床時間。
  /// 跟鬧鐘同一個轉盤，月亮鎖在上床時刻；太陽一開始停在今晚的鬧鐘（沒排就停在
  /// 轉盤上的起床時間）——**不用手機偵測的時間**（使用者定）。
  Future<void> _alreadyUp() async {
    final started = TimeOfDay.fromDateTime(widget.startAt);
    final alarmAt = _alarmAt;
    final TimeOfDay wake;
    if (alarmAt != null) {
      wake = TimeOfDay.fromDateTime(alarmAt);
    } else if (widget.alarm != null) {
      wake = await widget.alarm!.settings.wakeTime(started);
    } else {
      wake = defaultWakeTime(started);
    }
    if (!mounted) return;
    final result = await showBedTimesSheet(
      context,
      title: 'When did you get up?',
      bedtime: started,
      wake: wake,
      bedLocked: true,
    );
    if (result == null || !mounted) return;
    final end = wakeAfter(widget.startAt, result.wake.hour, result.wake.minute);
    final problem = recalledTimesProblem(widget.startAt, end, widget.clock());
    if (problem != null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(problem)),
      );
      return;
    }
    unawaited(widget.sounds?.stop());
    await widget.alarm?.cancelTonight();
    await widget.store.markEnd(end, recalled: true);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B2350),
        title: const Text(
          'Cancel this sleep?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This removes the "Start sleep" you just tapped. Nothing else changes.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep sleeping'),
          ),
          TextButton(
            key: const Key('sleep-cancel-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Cancel sleep',
              style: TextStyle(color: Color(0xFFFF8A8A)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    unawaited(widget.sounds?.stop());
    await widget.alarm?.cancelTonight();
    await widget.store.cancelStart();
    if (mounted) Navigator.of(context).pop();
  }

  static const _line = Divider(color: Colors.white24, height: 1);

  Widget _soundsRow() {
    final playing = _soundPlaying;
    final detail = playing
        ? '${_sound.label} · until ${_hhmm(_soundEndsAt!)}'
        : '${_sound.label} · $_soundMinutes min';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sleep sounds',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  key: const Key('sleep-sounds-detail'),
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
            ),
          ),
          _squareButton(
            const Key('sleep-sounds-pick'),
            Icons.volume_up_rounded,
            _pickSound,
          ),
          const SizedBox(width: 10),
          _squareButton(
            const Key('sleep-sounds-play'),
            playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
            _toggleSound,
          ),
        ],
      ),
    );
  }

  Widget _squareButton(Key key, IconData icon, VoidCallback onTap) => InkWell(
    key: key,
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white38),
      ),
      child: Icon(icon, color: Colors.white, size: 26),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final now = widget.clock();
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1530),
        body: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/backgrounds/bedroom.png',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF0F1530),
                        Color(0xFF1B2350),
                        Color(0xFF2A2766),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // 上下壓暗，字放在任何背景圖上都讀得到。
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x99000000),
                      Color(0x00000000),
                      Color(0x00000000),
                      Color(0xCC0B1028),
                    ],
                    stops: [0, 0.3, 0.55, 0.8],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    FittedBox(
                      child: Text(
                        _hhmm(now),
                        key: const Key('sleep-clock'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 72,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Sleeping… your watch is tracking',
                      key: Key('sleep-since'),
                      style: TextStyle(color: Colors.white70, fontSize: 15),
                    ),
                    const Spacer(),
                    // 往下挪，讓墊子落在背景地毯的中央（使用者 2026-11-12 看實機後要求）。
                    // 圖片上下各有約 1/7 的透明邊，挪 48 不會壓到下面的鬧鐘列。
                    Transform.translate(
                      offset: const Offset(0, 48),
                      child: const SleepingPet(size: 260),
                    ),
                    const Spacer(),
                    if (widget.alarm != null) ...[
                      _line,
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Row(
                          children: [
                            const Text(
                              'Alarm',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            InkWell(
                              key: const Key('sleep-alarm'),
                              onTap: _alarmMenu,
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: 150,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white38),
                                ),
                                child: Text(
                                  _alarmAt == null ? 'Off' : _hhmm(_alarmAt!),
                                  key: const Key('sleep-alarm-time'),
                                  style: TextStyle(
                                    color: _alarmAt == null
                                        ? Colors.white54
                                        : Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _line,
                    ],
                    if (widget.sounds != null) ...[
                      if (widget.alarm == null) _line,
                      _soundsRow(),
                      _line,
                    ],
                    const SizedBox(height: 28),
                    // 用滑的結束（使用者要求）：點一下不算，半夜被碰到不會記成下床。
                    SlideToConfirm(
                      key: const Key('sleep-out-of-bed'),
                      label: 'Slide to get up',
                      onConfirmed: _outOfBed,
                    ),
                    // 兩個併成一列：分兩行的話 6.4 吋手機底部溢出 21 像素（2026-11-12 實機）。
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: TextButton(
                            key: const Key('sleep-already-up'),
                            onPressed: _alreadyUp,
                            child: const Text(
                              'I already got up',
                              style: TextStyle(color: Colors.white, fontSize: 14),
                            ),
                          ),
                        ),
                        Flexible(
                          child: TextButton(
                            key: const Key('sleep-cancel'),
                            onPressed: _cancel,
                            child: const Text(
                              'Not sleeping? Cancel',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 14,
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.white60,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
