import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'bedtime_reminder.dart';

/// 走 `sonnap/notify` channel，另一頭是 `NotificationService.kt`
/// （AlarmManager + NotificationManager）。
///
/// ## 為什麼不裝 flutter_local_notifications
///
/// 理由與 `shared_preferences` 不裝相同：它會連帶動到 linux / macos / windows
/// 三個平台的 generated plugin 檔，而這個專案不出那三個平台。
/// MethodChannel 的基礎建設這個 App 已經有兩條了（`sonnap/usage`、`sonnap/store`）。
///
/// ⚠️ **失敗一律吞掉、不拋例外。** 通知是加分項：排不進去最壞的後果是
/// 「今晚沒有提醒」，為了它讓整個設定頁或 App 啟動掛掉不成比例
/// （與 [PlatformKeyValueStore] 同一條紀律）。
class PlatformReminderScheduler implements ReminderScheduler {
  static const MethodChannel _channel = MethodChannel('sonnap/notify');

  const PlatformReminderScheduler();

  @override
  Future<bool> schedule(DateTime at, {required String title, required String body}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('schedule', {
        'triggerAtMillis': at.millisecondsSinceEpoch,
        'title': title,
        'body': body,
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint('Reminder: schedule failed - $e');
      return false;
    } on MissingPluginException {
      return false; // 非 Android 平台，或測試環境。
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } on PlatformException catch (e) {
      debugPrint('Reminder: cancel failed - $e');
    } on MissingPluginException {
      // 同上
    }
  }

  @override
  Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod<void>('requestPermission');
    } on PlatformException catch (e) {
      debugPrint('Reminder: requestPermission failed - $e');
    } on MissingPluginException {
      // 同上
    }
  }
}
