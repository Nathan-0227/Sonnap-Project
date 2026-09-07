import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'key_value_store.dart';

/// 上傳失敗的夜晚先留在這台手機上，下次開 App 補送。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 沒有這一層，連不到後端的那一晚會**永久消失**
/// ═══════════════════════════════════════════════════════════════════
///
/// 三件事湊在一起才成立這個洞，單看任何一件都不明顯：
///
///   1. `lights_out.dart` 的視窗是**往回 24 小時的滑動視窗**
///      （[kLightsOutWindow]）。今天早上算得出昨晚，明天早上就算不出了。
///   2. 上傳是一次性的：失敗就只回一個 `failed`，沒有任何東西被留下來。
///   3. 後端只有在同一個 Wi-Fi 底下連得到（見 CLAUDE.md 的 IP 那一節），
///      而 D2 受測者早上起來第一件事不一定在家。
///
/// 所以「隔天再開一次 App」救不回來——隔天的視窗裡已經沒有那一晚了。
///
/// ═══════════════════════════════════════════════════════════════════
/// 存什麼
/// ═══════════════════════════════════════════════════════════════════
///
/// 只存 `lights_out_at` 的 ISO8601 字串，一個 JSON 陣列。
///
/// ⚠️ **不存達成度、不存 `is_late`、不存 `date`。** 那三個是後端算的
/// （`behavior/adherence.py`），補送成功時會重新回一份。存下來就等於
/// 在 Dart 這邊有了第二份定義，而使用者中途改了目標就寢時間的話，
/// 兩份會不一致而且沒有任何錯誤訊息。
///
/// ⚠️ 用既有的 `sonnap/store`（Android SharedPreferences），
/// **不裝 `shared_preferences` 套件**——理由見 [KeyValueStore]。
class PendingNightlyStore {
  /// ⚠️ 這個鍵改了就等於把所有人手機上的待送夜晚丟掉，而且不會有錯誤訊息。
  static const String storageKey = 'sonnap.pending_nightly';

  /// 佇列上限。超過就丟掉最舊的。
  ///
  /// 取 14 的理由：Android 的事件歷史實測保留 ≥5 天，所以能進到佇列的
  /// 夜晚本來就有限；而「後端一直連不上」的情況下這個清單會無限長下去，
  /// 存進 SharedPreferences 的東西沒有上限就是一個慢性的洩漏。
  /// 14 給了兩週的容錯，遠大於 D2 的 4-5 晚。
  static const int maxEntries = 14;

  final KeyValueStore store;

  const PendingNightlyStore(this.store);

  /// 讀出待送清單，**舊的在前**。
  ///
  /// ⚠️ 讀不到或格式壞掉一律當成空清單，不拋例外。這裡存的東西壞掉最壞
  /// 的後果是「少補送幾晚」，為了它讓 Insights 頁開不起來不成比例
  /// （與 [PlatformKeyValueStore] 同一條紀律）。
  Future<List<String>> load() async {
    final raw = await store.getString(storageKey);
    if (raw == null || raw.isEmpty) return <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>[];
      return decoded.whereType<String>().where((s) => s.isNotEmpty).toList();
    } catch (error) {
      debugPrint('PendingNightly: 佇列格式壞掉，當成空的 - $error');
      return <String>[];
    }
  }

  /// 覆寫待送清單。空清單就把鍵移掉，不要留一個 `[]` 在那裡。
  ///
  /// 去重與截斷都在這裡做，所以呼叫端不必自己記得——**漏做去重不會報錯，
  /// 只會讓同一晚被送兩次**。
  Future<void> save(List<String> isoTimestamps) async {
    final deduped = <String>[];
    for (final iso in isoTimestamps) {
      if (iso.isEmpty || deduped.contains(iso)) continue;
      deduped.add(iso);
    }
    // 超過上限就丟最舊的（清單維持插入順序，而插入順序就是時間順序：
    // 每一輪都把當晚那筆接在最後面）。
    final trimmed = deduped.length > maxEntries
        ? deduped.sublist(deduped.length - maxEntries)
        : deduped;

    if (trimmed.isEmpty) {
      await store.remove(storageKey);
      return;
    }
    await store.setString(storageKey, jsonEncode(trimmed));
  }
}
