import 'dart:async';

import 'package:flutter/material.dart';

import '../services/alarm.dart';
import '../services/bed_marks.dart';
import '../widgets/sleep_schedule_sheet.dart';
import '../widgets/sleepy_pet.dart';

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
/// 助眠聲音那一列在做聲音的 PR 加；「I already got up」也在之後的 PR。
class SleepModeScreen extends StatefulWidget {
  final BedMarkStore store;
  final DateTime startAt;
  final DateTime Function() clock;

  /// 鬧鐘。null = 沒有鬧鐘（測試或舊的呼叫端）。
  final AlarmController? alarm;

  const SleepModeScreen({
    super.key,
    required this.store,
    required this.startAt,
    this.clock = DateTime.now,
    this.alarm,
  });

  @override
  State<SleepModeScreen> createState() => _SleepModeScreenState();
}

class _SleepModeScreenState extends State<SleepModeScreen> {
  Timer? _tick;

  /// 今晚鬧鐘排在幾點。null = 沒排、或使用者點了「只關今晚」。
  DateTime? _alarmAt;

  @override
  void initState() {
    super.initState();
    _loadAlarm();
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
    await widget.alarm?.cancelTonight();
    await widget.store.markEnd(widget.clock());
    if (mounted) Navigator.of(context).pop();
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
    await widget.alarm?.cancelTonight();
    await widget.store.cancelStart();
    if (mounted) Navigator.of(context).pop();
  }

  static const _line = Divider(color: Colors.white24, height: 1);

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
                    const SleepingPet(size: 260),
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
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        key: const Key('sleep-out-of-bed'),
                        onPressed: _outOfBed,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          side: const BorderSide(
                            color: Color(0xFFB9A6FF),
                            width: 2,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Out of bed',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    TextButton(
                      key: const Key('sleep-cancel'),
                      onPressed: _cancel,
                      child: const Text(
                        'Not sleeping? Cancel',
                        style: TextStyle(
                          color: Colors.white60,
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.white60,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
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
