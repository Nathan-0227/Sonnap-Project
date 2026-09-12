import 'package:flutter/material.dart';

/// 就寢提醒：什麼時候響、響什麼。純函式 + 一個薄薄的控制器。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 「提前幾分鐘」是產品判斷，所以寫在 Dart，不寫在 Kotlin
/// ═══════════════════════════════════════════════════════════════════
///
/// 原生端（`NotificationService.kt`）只負責「在這個時刻發出這則通知」，
/// 不知道目標就寢時間、不知道提前多少。門檻寫進 Kotlin 的話，每次調整都要
/// 重編 APK 才驗得了——與「原生端只回事實，產品判斷留在 Dart」同一條紀律
/// （`lights_out.dart` 的安靜門檻也是這樣放的）。
///
/// ⚠️ [kReminderLead] 是**行為提示**的工程判斷，不是計分門檻：它不進任何
///    分數、不影響任何挑戰。30 分鐘的理由同 `bedtime_urgency.dart` 的
///    kImminentThreshold——那是「現在收手還來得及準時躺下」的分界，
///    兩者刻意一致，否則通知說「還有 30 分」而首頁倒數還是綠的。

const Duration kReminderLead = Duration(minutes: 30);

/// 下一次提醒的時刻：下一次目標就寢時間往前推 [lead]。
///
/// ⚠️ **剛好等於現在也算「已經過了」**，排到明天。否則在提醒響起的那一刻
///    重新排程（例如使用者剛好那時開 App），會排出一個立刻又響一次的鬧鐘。
///
/// ⚠️ 跨午夜：目標 00:15 → 提醒是**前一晚** 23:45。`DateTime` 減掉 lead
///    會自動跨日，不需要特別處理，但測試要守著。
DateTime nextReminderAt(DateTime now, TimeOfDay bedtime, {Duration lead = kReminderLead}) {
  var candidate = DateTime(now.year, now.month, now.day, bedtime.hour, bedtime.minute).subtract(lead);
  while (!candidate.isAfter(now)) {
    candidate = candidate.add(const Duration(days: 1));
  }
  return candidate;
}

/// 排程的介面。真的實作走 `sonnap/notify`；測試用假的記下呼叫。
abstract class ReminderScheduler {
  /// 排一則提醒（取代先前排的那一則）。回傳「這支手機現在能不能發通知」——
  /// false 代表排是排了，但使用者關了通知權限，到時候不會出現。
  Future<bool> schedule(DateTime at, {required String title, required String body});

  Future<void> cancel();

  /// Android 13 以上要在執行時跟使用者要通知權限。其他版本什麼都不做。
  Future<void> requestPermission();
}

/// 把「開關 + 目標時間」變成一次排程或取消。
class BedtimeReminderController {
  final ReminderScheduler scheduler;

  /// 可注入，測試才能固定「現在」。
  final DateTime Function() clock;

  BedtimeReminderController({required this.scheduler, DateTime Function()? clock})
      : clock = clock ?? DateTime.now;

  static String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// 依目前的設定重排。回傳值同 [ReminderScheduler.schedule]；關掉時回 true。
  ///
  /// ⚠️ 開關關掉時一定要 cancel，不能只是「不再排新的」——已經排好的那一則
  ///    還躺在 AlarmManager 裡，關掉之後照樣會響，而使用者會以為開關壞了。
  Future<bool> sync({required bool on, required TimeOfDay bedtime}) async {
    if (!on) {
      await scheduler.cancel();
      return true;
    }
    return scheduler.schedule(
      nextReminderAt(clock(), bedtime),
      title: 'Bedtime in ${kReminderLead.inMinutes} minutes',
      body: 'Your target bedtime is ${_hhmm(bedtime)}. '
          'Start winding down and put the phone away soon.',
    );
  }
}
