import 'package:flutter/foundation.dart';

import 'key_value_store.dart';

/// 目標就寢時間與提醒開關的持久化。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 這個設定有**兩份**，而且會安靜地漂移
/// ═══════════════════════════════════════════════════════════════════
///
/// | 在哪 | 誰在用 |
/// |---|---|
/// | 這台手機（`sonnap/store`） | 畫面上的倒數、Settings 頁顯示的值 |
/// | 後端 `users.target_bedtime` | **`POST /nightly` 算達成度用的就是這一份** |
///
/// 在此之前 App 端只存在記憶體裡，改完就寢時間**完全不會告訴後端**。
/// 症狀：使用者在 Settings 把目標改成 01:00，首頁的倒數跟著變，
/// 隔天早上卻收到「比目標晚了 90 分鐘」——因為後端還在拿註冊當天填的
/// 23:30 在算。畫面上沒有任何地方看得出來這兩個數字講的不是同一個目標。
///
/// 所以這裡存**兩個**值：使用者的設定，以及「最後一次成功同步到後端的
/// 那個值」。兩者不同就代表還欠一次 PATCH，下次開 App 會補送——
/// 與 [PendingNightlyStore] 是同一個做法，理由也一樣：後端只有在同一個
/// Wi-Fi 底下連得到，改設定的當下不一定連得上。
///
/// ⚠️ **改目標不會追溯性地改寫歷史達成度**，這是後端刻意的
/// （`nightly_behavior` 存的是當晚的快照，見 `main.py` 的 `update_user`）。
/// 所以補送晚了幾天也不會弄髒舊資料，只影響補送之後的夜晚。

/// 從儲存讀回來的設定。null 代表「沒存過」，不是「預設值」——
/// 預設值由呼叫端決定，這裡不替它決定。
@immutable
class StoredSettings {
  /// `"HH:MM"`，或 null（沒存過）。
  final String? targetBedtime;

  /// 最後一次成功 PATCH 到後端的值。與 [targetBedtime] 不同就代表欠一次同步。
  final String? syncedBedtime;

  /// null 代表沒存過。
  final bool? reminderOn;

  const StoredSettings({
    this.targetBedtime,
    this.syncedBedtime,
    this.reminderOn,
  });

  /// 還欠一次 PATCH 嗎？
  ///
  /// ⚠️ 沒存過（[targetBedtime] 是 null）時回 false：那代表使用者從來
  /// 沒動過這個設定，後端用註冊時填的那個值是對的，不需要補送。
  bool get needsSync =>
      targetBedtime != null && targetBedtime != syncedBedtime;
}

class UserSettingsStore {
  /// ⚠️ 改這些字串等於把使用者存過的設定弄丟，而且不會有錯誤訊息——
  /// 只會安靜地退回預設值。要改就要一併寫遷移。
  static const String bedtimeKey = 'target_bedtime';
  static const String syncedBedtimeKey = 'target_bedtime_synced';
  static const String reminderKey = 'reminder_on';

  final KeyValueStore store;

  const UserSettingsStore(this.store);

  Future<StoredSettings> load() async {
    final bedtime = await store.getString(bedtimeKey);
    final synced = await store.getString(syncedBedtimeKey);
    final reminder = await store.getString(reminderKey);

    return StoredSettings(
      // ⚠️ 讀出來的字串要驗過才收。存壞掉（或被手動改壞）時當成沒存過，
      //    不要讓一個 "25:99" 傳到後端去換一個 422。
      targetBedtime: isValidBedtime(bedtime) ? bedtime : null,
      syncedBedtime: isValidBedtime(synced) ? synced : null,
      reminderOn: reminder == null ? null : reminder == 'true',
    );
  }

  /// 存使用者剛設的目標。**不動 syncedBedtime**——那要等 PATCH 真的成功。
  Future<void> saveBedtime(String hhmm) async {
    if (!isValidBedtime(hhmm)) {
      debugPrint('UserSettings: 拒絕存一個壞掉的就寢時間 $hhmm');
      return;
    }
    await store.setString(bedtimeKey, hhmm);
  }

  /// PATCH 成功之後才呼叫。
  Future<void> markSynced(String hhmm) async {
    await store.setString(syncedBedtimeKey, hhmm);
  }

  Future<void> saveReminder(bool on) async {
    await store.setString(reminderKey, on ? 'true' : 'false');
  }
}

/// `"HH:MM"`，24 小時制，兩位數。
///
/// ⚠️ 格式要與 `behavior/adherence.py` 的 `parse_bedtime()` 一致——
/// 後端對格式不合的值回 422，而那個錯誤在 App 端只會表現成「設定沒有生效」。
bool isValidBedtime(String? value) {
  if (value == null) return false;
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
  if (match == null) return false;
  final h = int.parse(match.group(1)!);
  final m = int.parse(match.group(2)!);
  return h >= 0 && h <= 23 && m >= 0 && m <= 59;
}

/// 小時、分鐘 → `"HH:MM"`。
///
/// ⚠️ 這裡不用 `parseWallClock()`——那一支處理的是 payload 裡帶時區位移的
/// ISO 時間戳（`DateTime.tryParse("...+08:00")` 會回 UTC 那個坑）。
/// 目標就寢時間是一個**沒有日期也沒有時區**的牆鐘時刻，兩者不是同一件事。
String formatBedtime(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// `"HH:MM"` → (小時, 分鐘)。格式不合回 null。
({int hour, int minute})? parseBedtime(String? value) {
  if (!isValidBedtime(value)) return null;
  final parts = value!.split(':');
  return (hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}
