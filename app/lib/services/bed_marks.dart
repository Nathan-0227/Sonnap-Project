import 'package:flutter/foundation.dart';

import 'key_value_store.dart';

/// 存在本機的鍵。
const String kBedStartKey = 'bed_start_at';
const String kBedEndKey = 'bed_end_at';

/// 超過這麼久的標記就當作沒有。
///
/// ⚠️ **這是防止「上禮拜按的開始睡覺」被算進今晚**。沒有這條規則，
/// 一個沒有配對結束的 start 會永遠留在本機，然後某天被配上一個
/// 毫不相干的 end，算出一個 40 小時的臥床時間 —— 而那不會拋任何錯誤。
///
/// 36 小時是產品決定：一夜最長約 14 小時，而使用者可能隔天晚上才開 App。
/// 36 小時涵蓋得到「昨晚按的、今晚才上傳」，又擋得掉更久以前的。
const Duration kBedMarkMaxAge = Duration(hours: 36);

/// 使用者自己按的「上床 / 下床」時刻。
///
/// ⚠️ **這是自述，不是量到的。** 它與 `lights_out_at`（手機事件推出來的
/// 「放下手機」）是兩個不同的量：一個是行為宣告，一個是被動偵測。
/// 兩者都送給後端，由後端各自算各自的（見 `behavior/sleep_efficiency.py`）。
@immutable
class BedMarks {
  final DateTime? startAt;
  final DateTime? endAt;

  const BedMarks({this.startAt, this.endAt});

  static const BedMarks none = BedMarks();

  bool get hasStart => startAt != null;

  /// 兩端都有，才算得出臥床時間。
  bool get isComplete => startAt != null && endAt != null;

  String? get startIso => startAt?.toIso8601String();
  String? get endIso => endAt?.toIso8601String();
}

/// 讀寫本機的上床 / 下床標記。
///
/// ⚠️ **這是加分項不是取代品。** 沒按按鈕的夜晚照樣有 `lights_out_at`
/// （被動偵測，早上開 App 就回推得到），只是少了臥床時間。
/// 任何一段程式都不可以因為「沒有標記」就不上傳那一晚。
class BedMarkStore {
  final KeyValueStore store;

  const BedMarkStore(this.store);

  /// 讀出目前有效的標記。
  ///
  /// 過期（見 [kBedMarkMaxAge]）或順序顛倒的一律當作沒有 —— 回 null
  /// 而不是回一個看起來合理的錯值。
  Future<BedMarks> read({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final start = _parse(await store.getString(kBedStartKey));
    final end = _parse(await store.getString(kBedEndKey));

    if (start == null) {
      // 沒有起點的 end 沒有意義（臥床時間算不出來），一併丟掉。
      return BedMarks.none;
    }
    if (at.difference(start) > kBedMarkMaxAge) {
      return BedMarks.none;
    }
    // 結束早於開始 = 按錯了。丟掉 end，保留 start（人可能還在床上）。
    if (end != null && !end.isAfter(start)) {
      return BedMarks(startAt: start);
    }
    return BedMarks(startAt: start, endAt: end);
  }

  Future<void> markStart(DateTime at) async {
    await store.setString(kBedStartKey, at.toIso8601String());
    // 重新開始一晚 → 上一晚的結束時刻不能留著，否則會配成錯的一對。
    await store.remove(kBedEndKey);
  }

  Future<void> markEnd(DateTime at) =>
      store.setString(kBedEndKey, at.toIso8601String());

  /// 上傳成功之後清掉，免得同一對標記被算進第二晚。
  Future<void> clear() async {
    await store.remove(kBedStartKey);
    await store.remove(kBedEndKey);
  }

  static DateTime? _parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}
