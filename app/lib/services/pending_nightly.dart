import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'bed_marks.dart';
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
/// 一晚一筆 [PendingNight]：`lights_out_at`，加上使用者自己按的上床／
/// 下床時刻（[BedMarks]）。存成一個 JSON 陣列。
///
/// ⚠️ **上床標記一定要跟著一起存。** 少了它，補送回去的那一晚會缺臥床
/// 時間與行為版效率——使用者明明按了按鈕，資料卻在補送的過程中掉了，
/// 而畫面上不會有任何跡象。
///
/// ⚠️ **不存達成度、不存 `is_late`、不存 `date`。** 那三個是後端算的
/// （`behavior/adherence.py`），補送成功時會重新回一份。存下來就等於
/// 在 Dart 這邊有了第二份定義，而使用者中途改了目標就寢時間的話，
/// 兩份會不一致而且沒有任何錯誤訊息。
///
/// ⚠️ 用既有的 `sonnap/store`（Android SharedPreferences），
/// **不裝 `shared_preferences` 套件**——理由見 [KeyValueStore]。

/// 一筆等著補送的夜晚。
@immutable
class PendingNight {
  /// `lights_out_at` 的 ISO8601 字串。**這是這一筆的身分**——去重與
  /// 「今晚是不是已經在佇列裡」都看它。
  final String lightsOutIso;

  /// 使用者自己按的上床／下床時刻。沒按就是 [BedMarks.none]。
  final BedMarks marks;

  const PendingNight(this.lightsOutIso, {this.marks = BedMarks.none});

  Map<String, dynamic> toJson() => {
        'lights_out_at': lightsOutIso,
        // ⚠️ 只在有值時寫進去。寫 null 進去讀回來要多一層判斷，
        //    而「沒按按鈕」與「按了但值是 null」在這裡是同一件事。
        if (marks.startIso != null) 'bed_start_at': marks.startIso,
        if (marks.endIso != null) 'bed_end_at': marks.endIso,
      };

  static PendingNight? fromJson(Object? raw) {
    // ⚠️ 舊格式（只有一個字串）也讀得回來。這個佇列存在使用者的手機上，
    //    換格式時舊資料還在——直接丟掉就等於把那幾晚弄丟一次。
    if (raw is String) {
      return raw.isEmpty ? null : PendingNight(raw);
    }
    if (raw is! Map) return null;
    final iso = raw['lights_out_at'];
    if (iso is! String || iso.isEmpty) return null;
    return PendingNight(
      iso,
      marks: BedMarks(
        startAt: _parse(raw['bed_start_at']),
        endAt: _parse(raw['bed_end_at']),
      ),
    );
  }

  static DateTime? _parse(Object? raw) =>
      raw is String && raw.isNotEmpty ? DateTime.tryParse(raw) : null;
}

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
  Future<List<PendingNight>> load() async {
    final raw = await store.getString(storageKey);
    if (raw == null || raw.isEmpty) return <PendingNight>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <PendingNight>[];
      return decoded
          .map(PendingNight.fromJson)
          .whereType<PendingNight>()
          .toList();
    } catch (error) {
      debugPrint('PendingNightly: 佇列格式壞掉，當成空的 - $error');
      return <PendingNight>[];
    }
  }

  /// 覆寫待送清單。空清單就把鍵移掉，不要留一個 `[]` 在那裡。
  ///
  /// 去重與截斷都在這裡做，所以呼叫端不必自己記得——**漏做去重不會報錯，
  /// 只會讓同一晚被送兩次**。
  Future<void> save(List<PendingNight> nights) async {
    final deduped = <PendingNight>[];
    for (final night in nights) {
      if (night.lightsOutIso.isEmpty) continue;
      // ⚠️ 去重看的是 lights_out_at，不是整筆內容。同一晚出現兩次時
      //    **後面那筆勝出**——它帶的上床標記比較新（使用者可能在第二次
      //    開 App 之前才按下「下床」）。
      deduped.removeWhere((n) => n.lightsOutIso == night.lightsOutIso);
      deduped.add(night);
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
    await store.setString(
      storageKey,
      jsonEncode(trimmed.map((n) => n.toJson()).toList()),
    );
  }
}
