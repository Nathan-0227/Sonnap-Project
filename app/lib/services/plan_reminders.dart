import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sleep_plan.dart';

/// 睡眠計畫每條習慣的提醒。走同一條 `sonnap/notify`，每條一個位置（slot 1..）；
/// slot 0 是就寢提醒，**這裡永遠不碰**。
///
/// 判斷全在 Dart（幾點、哪幾天），原生端只做「在這個時刻響、下次挑對的星期幾」，
/// 同就寢提醒與鬧鐘的紀律。
abstract class PlanReminderScheduler {
  Future<bool> schedule(int slot, DateTime at, {required String body, required int days});
  Future<void> cancel(int slot);
}

class PlatformPlanReminderScheduler implements PlanReminderScheduler {
  static const MethodChannel _channel = MethodChannel('sonnap/notify');
  const PlatformPlanReminderScheduler();

  @override
  Future<bool> schedule(int slot, DateTime at, {required String body, required int days}) async {
    assert(slot >= 1, 'slot 0 是就寢提醒');
    try {
      return await _channel.invokeMethod<bool>('schedule', {
            'triggerAtMillis': at.millisecondsSinceEpoch,
            'title': kPlanReminderTitle,
            'body': body,
            'slot': slot,
            'days': days,
          }) ??
          false;
    } on PlatformException catch (e) {
      debugPrint('PlanReminder: schedule failed - $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> cancel(int slot) async {
    assert(slot >= 1, 'slot 0 是就寢提醒');
    try {
      await _channel.invokeMethod<void>('cancel', {'slot': slot});
    } on PlatformException catch (e) {
      debugPrint('PlanReminder: cancel failed - $e');
    } on MissingPluginException {
      // 非 Android／測試環境
    }
  }
}

const String kPlanReminderTitle = 'Your sleep plan';

/// 依清單重排所有提醒：每個位置先取消，再排打開提醒的那幾條。
///
/// ⚠️ 一律「全部取消再排」：拿掉一條、或把第 3 條往前挪之後，
///    舊位置上那一則不取消的話照樣會每天響。
/// ⚠️ 不 await 在畫面上：通知是加分項，排不進去不能擋住任何東西。
Future<void> syncPlanReminders(
  PlanReminderScheduler scheduler,
  List<PlanItem> items, {
  required DateTime now,
  required TimeOfDay bedtime,
  required TimeOfDay wake,
}) async {
  for (var slot = 1; slot <= kMaxPlanItems; slot++) {
    await scheduler.cancel(slot);
  }
  for (var i = 0; i < items.length && i < kMaxPlanItems; i++) {
    final item = items[i];
    if (!item.notify) continue;
    final at = nextReminderAt(item, now, bedtime: bedtime, wake: wake);
    if (at == null) continue;
    await scheduler.schedule(i + 1, at, body: item.text, days: item.days);
  }
}
