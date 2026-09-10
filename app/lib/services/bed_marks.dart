import 'package:flutter/foundation.dart';

import 'key_value_store.dart';

/// 存在本機的鍵。
const String kBedStartKey = 'bed_start_at';
const String kBedEndKey = 'bed_end_at';

/// 已經按完、但還沒上傳的那一對（見 [BedMarkStore.markStart]）。
const String kBedPendingStartKey = 'bed_pending_start_at';
const String kBedPendingEndKey = 'bed_pending_end_at';

/// 超過這麼久的標記就當作沒有。
///
/// ⚠️ **這是防止「上禮拜按的開始睡覺」被算進今晚**。沒有這條規則，
/// 一個沒有配對結束的 start 會永遠留在本機，然後某天被配上一個
/// 毫不相干的 end，算出一個 40 小時的臥床時間 —— 而那不會拋任何錯誤。
///
/// 36 小時是產品決定：一夜最長約 14 小時，而使用者可能隔天晚上才開 App。
/// 36 小時涵蓋得到「昨晚按的、今晚才上傳」，又擋得掉更久以前的。
const Duration kBedMarkMaxAge = Duration(hours: 36);

/// 「下床」按得比實際起床晚多久，還算說得通。
///
/// ⚠️ **忘記按是常態，不是例外。** 2026-09-08 實測：08:20 起床、12:11 才
/// 想起來按。那個 12:11 不是下床時刻，是「想起來要按」的時刻——中間 3 小時
/// 51 分會被算成躺在床上，而且那段時間的手機使用會被算成「躺床上滑手機」。
/// 臥床時間與行為版睡眠效率**兩個都會錯，而且錯得看起來很合理**。
///
/// 判準用現成的東西：`lights_out_at + quietMinutes` 就是安靜期結束、也就是
/// **手機第一次被碰**的時刻。人起床後不一定馬上碰手機，碰了也可能再賴床，
/// 所以給兩小時寬限；但差到三小時以上就不是賴床了。
///
/// ⚠️ 超過寬限時**不是**改用推算的時刻——那會把自述欄位偷偷換成偵測值，
/// 而「使用者說的」與「手機測的」是兩個不同的量，混起來之後誰也分不出
/// 哪個數字是誰的。做法是**不送 `bed_end_at`**：算不出效率，
/// 好過算出一個錯的效率。
const Duration kBedEndGrace = Duration(hours: 2);

/// 這個「下床」時刻相對於手機的動靜還說得通嗎。
///
/// [lightsOutAt] 與 [quietMinutes] 來自 `LightsOutResult`。任何一個缺了就
/// 沒有參考點，一律回 true——**寧可放行，也不要因為量不到而丟掉使用者的輸入**。
bool bedEndIsPlausible(
  DateTime bedEnd,
  DateTime? lightsOutAt,
  int quietMinutes,
) {
  if (lightsOutAt == null || quietMinutes <= 0) return true;
  final firstTouch = lightsOutAt.add(Duration(minutes: quietMinutes));
  return !bedEnd.isAfter(firstTouch.add(kBedEndGrace));
}

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

  /// 上一晚**已經按完、但還沒上傳**的那一對。
  ///
  /// 見 [markStart] 的說明：這個槽是 2026-09-09 因為真的掉了一晚的資料
  /// 才加的。沒有 pending 時回 [BedMarks.none]。
  Future<BedMarks> readPending({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final start = _parse(await store.getString(kBedPendingStartKey));
    final end = _parse(await store.getString(kBedPendingEndKey));
    if (start == null || end == null || !end.isAfter(start)) {
      return BedMarks.none;
    }
    if (at.difference(start) > kBedMarkMaxAge) return BedMarks.none;
    return BedMarks(startAt: start, endAt: end);
  }

  Future<void> markStart(DateTime at) async {
    // ═══════════════════════════════════════════════════════════════
    // ⚠️ 按下一晚的「開始」之前，先把**已經按完但還沒上傳**的那一對
    //    搬到 pending 槽，不要直接銷毀。
    // ═══════════════════════════════════════════════════════════════
    // 2026-09-09 真的掉了一晚的資料：
    //
    //   09-08 01:53  按 Start sleep
    //   09-08 12:11  按 Out of bed        ← 這時已經是完整的一對
    //   （整天沒開 Insights，所以沒上傳）
    //   09-09 00:49  按下一晚的 Start sleep → 舊版在這裡把 end 刪掉
    //   09-09 00:49  開 Insights → 送出 start=09-09 00:49
    //   後端 same_night 判定 night_date(09-09) != 09-08 → 整組丟掉
    //
    // 兩個守門都正常運作，資料是在更早一步掉的。原本那行註解
    //（「重新開始一晚 → 上一晚的結束時刻不能留著」）顧慮沒錯——配成
    // 錯的一對確實更糟——但它把**還沒上傳的完整一對**也一起銷毀了。
    //
    // ⚠️ 上傳只在 Insights 頁那一輪做。「早上沒開 App、晚上又按了開始」
    //    對 D2 受測者會是常態不是例外。
    final current = await read(now: at);
    if (current.isComplete) {
      await store.setString(
          kBedPendingStartKey, current.startAt!.toIso8601String());
      await store.setString(
          kBedPendingEndKey, current.endAt!.toIso8601String());
    }

    await store.setString(kBedStartKey, at.toIso8601String());
    // 重新開始一晚 → 上一晚的結束時刻不能留在這個槽，否則會配成錯的一對。
    await store.remove(kBedEndKey);
  }

  Future<void> markEnd(DateTime at) =>
      store.setString(kBedEndKey, at.toIso8601String());

  /// 上傳成功之後清掉，免得同一對標記被算進第二晚。
  Future<void> clear() async {
    await store.remove(kBedStartKey);
    await store.remove(kBedEndKey);
  }

  /// pending 那一對上傳成功之後清掉。
  ///
  /// ⚠️ **不要**用 [clear] 代替：那會把使用者今晚剛按的「開始」也刪掉。
  Future<void> clearPending() async {
    await store.remove(kBedPendingStartKey);
    await store.remove(kBedPendingEndKey);
  }

  static DateTime? _parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}
