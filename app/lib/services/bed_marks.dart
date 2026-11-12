import 'package:flutter/foundation.dart';

import 'key_value_store.dart';

/// 存在本機的鍵。
const String kBedStartKey = 'bed_start_at';
const String kBedEndKey = 'bed_end_at';

/// 已經按完、但還沒上傳的那一對（見 [BedMarkStore.markStart]）。
const String kBedPendingStartKey = 'bed_pending_start_at';
const String kBedPendingEndKey = 'bed_pending_end_at';

/// 上床／下床是當下按的還是事後補的（2026-11-12）。值是 'recalled'；沒有 = 當下按的。
const String kBedStartKindKey = 'bed_start_kind';
const String kBedEndKindKey = 'bed_end_kind';
const String kBedPendingStartKindKey = 'bed_pending_start_kind';
const String kBedPendingEndKindKey = 'bed_pending_end_kind';

/// 最近一晚按了什麼的紀錄（2026-11-12）。
///
/// ⚠️ 不能拿上面那幾個槽來判斷「昨晚有沒有按齊」：上傳被收下之後槽就清掉了，
///    分不出「按齊而且傳了」與「根本沒按」。這份紀錄只給首頁的
///    「Forgot to tap last night?」用，**不參與上傳**。
const String kBedLogStartKey = 'bed_log_start_at';
const String kBedLogEndKey = 'bed_log_end_at';

/// 事後補的值。
const String kRecalled = 'recalled';

/// 一個時刻屬於哪一晚（起床日）。與 `behavior/adherence.py` 的 `night_date()`
/// 同一個約定：往後推 6 小時再取日期。
DateTime nightDateOf(DateTime t) {
  final shifted = t.add(const Duration(hours: 6));
  return DateTime(shifted.year, shifted.month, shifted.day);
}

/// 首頁「補昨晚」只在早上 6 點之後出現：之前那段時間今晚可能還沒結束。
const int kBackfillFromHour = 6;

/// 一晚最長多久，與睡覺畫面、鬧鐘同一個 14 小時（`home_mode.dart` 的 kMaxSleepSession）。
const Duration kMaxRecalledNight = Duration(hours: 14);

/// 事後補的一對時間說不說得通。說得通回 null，否則回一句給使用者看的話。
///
/// 仍然要檢查（使用者定）：起床要晚於上床、不能晚於現在、整晚不超過 14 小時。
/// ⚠️ **不**套「比手機第一次被碰晚 2 小時」那條（[kBedEndGrace]）：那條擋的正是
///    「起床好幾小時才按」，而補的時間就是使用者說的起床時刻。
String? recalledTimesProblem(DateTime start, DateTime end, DateTime now) {
  if (!end.isAfter(start)) return 'Wake time has to be after bedtime.';
  if (end.isAfter(now)) return "That's later than now.";
  if (end.difference(start) > kMaxRecalledNight) {
    return "That's more than 14 hours in bed.";
  }
  return null;
}

/// 起床時刻（只有時分）→ 從 [start] 往後算第一個那個時刻。
DateTime wakeAfter(DateTime start, int hour, int minute) {
  final base = DateTime(start.year, start.month, start.day, start.hour, start.minute);
  final startMin = start.hour * 60 + start.minute;
  final wakeMin = hour * 60 + minute;
  return base.add(Duration(minutes: (wakeMin - startMin) % (24 * 60)));
}

/// 昨晚的起床時刻：今天早上那個時分。上床 = 起床往前推轉盤上的長度。
DateTime lastNightWake(DateTime now, int hour, int minute) =>
    DateTime(now.year, now.month, now.day, hour, minute);

/// 超過這麼久的標記就當作沒有。
///
/// ⚠️ **這是防止「上禮拜按的開始睡覺」被算進今晚**。沒有這條規則，
/// 一個沒有配對結束的 start 會永遠留在本機，然後某天被配上一個
/// 毫不相干的 end，算出一個 40 小時的臥床時間 —— 而那不會拋任何錯誤。
///
/// 36 小時是產品決定：一夜最長約 14 小時，而使用者可能隔天晚上才開 App。
/// 36 小時涵蓋得到「昨晚按的、今晚才上傳」，又擋得掉更久以前的。
const Duration kBedMarkMaxAge = Duration(hours: 36);

/// 待送的那一對放多久之後**從儲存裡刪掉**（不只是不採用）。
///
/// ⚠️ 刻意遠大於 [kBedMarkMaxAge]：超過 36 小時只是「不拿來用」，
/// 刪掉卻是不可逆的。留這麼寬的間距，是為了讓「時鐘／時區讓一對正常的
/// 標記看起來過期」這種情況不會把真的資料銷毀。
const Duration kPendingDiscardAfter = Duration(days: 7);

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

  /// 這個時刻是事後補的（回想的），不是當下按的。
  final bool startRecalled;
  final bool endRecalled;

  const BedMarks({
    this.startAt,
    this.endAt,
    this.startRecalled = false,
    this.endRecalled = false,
  });

  static const BedMarks none = BedMarks();

  bool get hasStart => startAt != null;

  /// 兩端都有，才算得出臥床時間。
  bool get isComplete => startAt != null && endAt != null;

  String? get startIso => startAt?.toIso8601String();
  String? get endIso => endAt?.toIso8601String();

  /// 送給後端的 kind：'tap' 或 'recalled'；沒有那個時刻就是 null。
  String? get startKind =>
      startAt == null ? null : (startRecalled ? kRecalled : 'tap');
  String? get endKind => endAt == null ? null : (endRecalled ? kRecalled : 'tap');
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
    final startRecalled = await store.getString(kBedStartKindKey) == kRecalled;
    if (end != null && !end.isAfter(start)) {
      return BedMarks(startAt: start, startRecalled: startRecalled);
    }
    return BedMarks(
      startAt: start,
      endAt: end,
      startRecalled: startRecalled,
      endRecalled:
          end != null && await store.getString(kBedEndKindKey) == kRecalled,
    );
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
    if (at.difference(start) > kBedMarkMaxAge) {
      // 早就不會被採用了，但**還留在儲存裡**。2026-10-02 在實機上看到
      // 09-20 那一對卡在這裡十二天：上傳時後端沒回報收下（`marksStored`
      // 是 false），清除條件因此一直沒成立。
      //
      // ⚠️ 不在 [kBedMarkMaxAge] 一到就刪，要再等到 [kPendingDiscardAfter]。
      //    刪掉是不可逆的；萬一哪天是時鐘或時區讓一對正常的標記「看起來」
      //    過期，36 小時就刪會把真的資料銷毀，而留著只是佔位子。
      //    七天遠超過任何合理的時鐘偏差，又能讓它不要無限期堆在那裡。
      if (at.difference(start) > kPendingDiscardAfter) {
        await clearPending();
      }
      return BedMarks.none;
    }
    return BedMarks(
      startAt: start,
      endAt: end,
      startRecalled:
          await store.getString(kBedPendingStartKindKey) == kRecalled,
      endRecalled: await store.getString(kBedPendingEndKindKey) == kRecalled,
    );
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
      await _setKind(kBedPendingStartKindKey, current.startRecalled);
      await _setKind(kBedPendingEndKindKey, current.endRecalled);
    }

    await store.setString(kBedStartKey, at.toIso8601String());
    // 重新開始一晚 → 上一晚的結束時刻不能留在這個槽，否則會配成錯的一對。
    await store.remove(kBedEndKey);
    await store.remove(kBedStartKindKey);
    await store.remove(kBedEndKindKey);
    await store.setString(kBedLogStartKey, at.toIso8601String());
    await store.remove(kBedLogEndKey);
  }

  /// [recalled]：「I already got up」補的下床（2026-11-12），不是當下按的。
  Future<void> markEnd(DateTime at, {bool recalled = false}) async {
    await store.setString(kBedEndKey, at.toIso8601String());
    await _setKind(kBedEndKindKey, recalled);
    await store.setString(kBedLogEndKey, at.toIso8601String());
  }

  /// 首頁「Forgot to tap last night?」要不要出現：早上 6 點後，而且最近一晚
  /// 不是昨晚、或昨晚少了上床或下床。
  ///
  /// ⚠️ 從沒按過的人每天都會看到——使用者知道並同意（2026-11-12）。
  Future<bool> needsBackfill(DateTime now) async {
    if (now.hour < kBackfillFromHour) return false;
    final last = await lastNight(now);
    return !last.isComplete;
  }

  /// 昨晚（今天早上結束的那一晚）按了什麼。不是昨晚的紀錄一律當作沒有。
  Future<BedMarks> lastNight(DateTime now) async {
    final start = _parse(await store.getString(kBedLogStartKey));
    if (start == null) return BedMarks.none;
    if (nightDateOf(start) != DateTime(now.year, now.month, now.day)) {
      return BedMarks.none;
    }
    final end = _parse(await store.getString(kBedLogEndKey));
    return BedMarks(
      startAt: start,
      endAt: end != null && end.isAfter(start) ? end : null,
    );
  }

  /// 首頁補昨晚：只補缺的那一個（當下按的不能被回想的蓋掉，使用者定）。
  ///
  /// [start] 是 null 時沿用昨晚當下按的上床。寫進目前這個槽，下一次上傳
  /// （Insights 頁那一輪）送出去；後端也會再守一次「不蓋掉當下按的」。
  Future<void> backfillLastNight(
    DateTime now, {
    DateTime? start,
    required DateTime end,
  }) async {
    final last = await lastNight(now);
    final useStart = last.startAt ?? start;
    if (useStart == null) {
      throw ArgumentError('start is required when last night has no tap');
    }
    final startRecalled = last.startAt == null;
    await store.setString(kBedStartKey, useStart.toIso8601String());
    await _setKind(kBedStartKindKey, startRecalled);
    await store.setString(kBedEndKey, end.toIso8601String());
    await _setKind(kBedEndKindKey, true);
    await store.setString(kBedLogStartKey, useStart.toIso8601String());
    await store.setString(kBedLogEndKey, end.toIso8601String());
  }

  Future<void> _setKind(String key, bool recalled) =>
      recalled ? store.setString(key, kRecalled) : store.remove(key);

  /// 「Not sleeping? Cancel」：不小心按到「開始睡覺」時，把這次的開始刪掉。
  ///
  /// ⚠️ 只刪**目前這個槽**，不碰 pending。[markStart] 已經把上一晚按完、
  /// 還沒上傳的那一對搬進 pending 了；那一對是真的資料，取消今晚不能連它一起刪。
  /// ⚠️ 也不能用「按下床」代替取消：那會留下一筆兩分鐘的假睡眠，
  /// 而上床按鈕是驗證攝影機上床偵測唯一的 ground truth。
  Future<void> cancelStart() async {
    await store.remove(kBedStartKey);
    await store.remove(kBedEndKey);
    await store.remove(kBedStartKindKey);
    await store.remove(kBedEndKindKey);
    await store.remove(kBedLogStartKey);
    await store.remove(kBedLogEndKey);
  }

  /// 上傳成功之後清掉，免得同一對標記被算進第二晚。
  Future<void> clear() async {
    await store.remove(kBedStartKey);
    await store.remove(kBedEndKey);
    await store.remove(kBedStartKindKey);
    await store.remove(kBedEndKindKey);
  }

  /// pending 那一對上傳成功之後清掉。
  ///
  /// ⚠️ **不要**用 [clear] 代替：那會把使用者今晚剛按的「開始」也刪掉。
  Future<void> clearPending() async {
    await store.remove(kBedPendingStartKey);
    await store.remove(kBedPendingEndKey);
    await store.remove(kBedPendingStartKindKey);
    await store.remove(kBedPendingEndKindKey);
  }

  static DateTime? _parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}
