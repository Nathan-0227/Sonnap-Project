import 'package:flutter/material.dart';

import '../services/alarm.dart';
import '../theme/sonnap_colors.dart';
import 'sleep_dial.dart';

/// 點首頁時鐘卡、或設定頁的目標就寢時間時滑出來的面板（2026-11-12 定案）。
/// 轉盤設定就寢與起床；Alarm 開關決定按 Start Sleep 時要不要排鬧鐘。
///
/// ⚠️ 權限在**打開鬧鐘開關時**才問（Q12），被拒絕就寫一行說明＋Open settings。
class SleepScheduleResult {
  final TimeOfDay bedtime;
  final TimeOfDay wake;
  final bool alarmEnabled;
  const SleepScheduleResult(this.bedtime, this.wake, this.alarmEnabled);
}

Future<SleepScheduleResult?> showSleepScheduleSheet(
  BuildContext context, {
  required TimeOfDay bedtime,
  required AlarmSettingsStore alarmSettings,
  required AlarmScheduler scheduler,
  String confirmLabel = 'Save',
}) async {
  final wake = await alarmSettings.wakeTime(bedtime);
  final enabled = await alarmSettings.enabled();
  if (!context.mounted) return null;
  final result = await showModalBottomSheet<SleepScheduleResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1B2350),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => SleepScheduleSheet(
      bedtime: bedtime,
      wake: wake,
      alarmEnabled: enabled,
      scheduler: scheduler,
      confirmLabel: confirmLabel,
    ),
  );
  if (result != null) {
    await alarmSettings.save(wake: result.wake, enabled: result.alarmEnabled);
  }
  return result;
}

/// 睡覺畫面點鬧鐘列：同一個轉盤，月亮固定在按 Start Sleep 的時刻，只撥太陽。
/// **不存檔**——只改今晚，轉盤上的設定不變（呼叫端自己排今晚的鬧鐘）。
Future<SleepScheduleResult?> showTonightAlarmSheet(
  BuildContext context, {
  required TimeOfDay startedAt,
  required TimeOfDay wake,
  required bool alarmOn,
  required AlarmScheduler scheduler,
}) {
  return showModalBottomSheet<SleepScheduleResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1B2350),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => SleepScheduleSheet(
      bedtime: startedAt,
      wake: wake,
      alarmEnabled: alarmOn,
      scheduler: scheduler,
      tonightOnly: true,
    ),
  );
}

/// 事後補時間用的轉盤（2026-11-12）：沒有 Alarm 開關，回傳拖好的上床／起床。
///
/// - 睡覺畫面「I already got up」：月亮鎖在按 Start Sleep 的時刻，只拖太陽。
/// - 首頁「Forgot to tap last night?」：昨晚有按上床就鎖月亮，沒按就兩個都能拖。
///
/// ⚠️ 只回傳時刻，不存檔、也不判斷合不合理——換算成哪一天、能不能晚於現在，
///    由呼叫端決定（它才知道是哪一晚）。
Future<SleepScheduleResult?> showBedTimesSheet(
  BuildContext context, {
  required String title,
  required TimeOfDay bedtime,
  required TimeOfDay wake,
  required bool bedLocked,
}) {
  return showModalBottomSheet<SleepScheduleResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1B2350),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => SleepScheduleSheet(
      bedtime: bedtime,
      wake: wake,
      alarmEnabled: false,
      title: title,
      bedLocked: bedLocked,
      showAlarm: false,
    ),
  );
}

class SleepScheduleSheet extends StatefulWidget {
  final TimeOfDay bedtime;
  final TimeOfDay wake;
  final bool alarmEnabled;
  final AlarmScheduler scheduler;

  /// 睡覺畫面用的版本：標題改成 Tonight's alarm、月亮把手鎖住（已經上床了）。
  final bool tonightOnly;

  /// 標題。null = 依 [tonightOnly] 決定。
  final String? title;

  /// 月亮把手鎖住。[tonightOnly] 一定鎖。
  final bool bedLocked;

  /// 顯示 Alarm 開關。事後補時間不需要。
  final bool showAlarm;

  /// 底下那顆按鈕的字。導覽列中間那顆打開時是「Start Sleep」（2026-11-13 使用者定：
  /// 先看一眼就寢／起床／鬧鐘，按了才開始睡覺）。
  final String confirmLabel;

  const SleepScheduleSheet({
    super.key,
    required this.bedtime,
    required this.wake,
    required this.alarmEnabled,
    this.scheduler = const PlatformAlarmScheduler(),
    this.tonightOnly = false,
    this.title,
    this.bedLocked = false,
    this.showAlarm = true,
    this.confirmLabel = 'Save',
  });

  @override
  State<SleepScheduleSheet> createState() => _SleepScheduleSheetState();
}

class _SleepScheduleSheetState extends State<SleepScheduleSheet> {
  late TimeOfDay _bed = widget.bedtime;
  late TimeOfDay _wake = widget.wake;
  late bool _alarm = widget.alarmEnabled;
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    if (_alarm) _checkPermission(ask: false);
  }

  Future<void> _checkPermission({required bool ask}) async {
    var ok = await widget.scheduler.canRing();
    if (!ok && ask) {
      await widget.scheduler.requestPermission();
      ok = await widget.scheduler.canRing();
    }
    if (mounted) setState(() => _blocked = !ok);
  }

  Future<void> _toggle(bool on) async {
    setState(() => _alarm = on);
    if (on) {
      await _checkPermission(ask: true);
    } else {
      setState(() => _blocked = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.title ??
                  (widget.tonightOnly ? "Tonight's alarm" : 'Sleep schedule'),
              style: const TextStyle(
                color: SonnapColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            SleepDial(
              bedtime: _bed,
              wake: _wake,
              onBedtimeChanged: (t) => setState(() => _bed = t),
              onWakeChanged: (t) => setState(() => _wake = t),
              bedLocked: widget.tonightOnly || widget.bedLocked,
            ),
            const SizedBox(height: 12),
            SleepTimesCard(bedtime: _bed, wake: _wake, alarmOn: _alarm),
            if (widget.showAlarm) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: sonnapCardDecoration(),
              child: Row(
                children: [
                  const Icon(Icons.alarm_rounded, color: Color(0xFFFF7AD9)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Alarm',
                      style: TextStyle(
                        color: SonnapColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Switch(
                    key: const Key('alarm-switch'),
                    value: _alarm,
                    onChanged: _toggle,
                    activeThumbColor: Colors.white,
                    activeTrackColor: SonnapColors.accent,
                  ),
                ],
              ),
            ),
            ],
            if (widget.showAlarm && _alarm && _blocked) ...[
              const SizedBox(height: 8),
              Row(
                key: const Key('alarm-permission-note'),
                children: [
                  const Expanded(
                    child: Text(
                      'Allow notifications for the alarm to ring',
                      style: TextStyle(color: Color(0xFFFFB86B), fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await widget.scheduler.openSettings();
                    },
                    child: const Text('Open settings'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('schedule-save'),
                onPressed: () => Navigator.of(
                  context,
                ).pop(SleepScheduleResult(_bed, _wake, _alarm)),
                style: FilledButton.styleFrom(
                  backgroundColor: SonnapColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  widget.confirmLabel,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
