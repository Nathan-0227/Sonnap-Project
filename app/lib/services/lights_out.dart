import 'package:flutter/foundation.dart';

/// 從手機互動事件推出 `lights_out_at`——最後一次放下手機的時刻。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 這是 proxy，不是入睡時間
/// ═══════════════════════════════════════════════════════════════════
///
/// 手機量得到的是「最後一次操作手機」。有人放下手機後還會躺半小時。
/// 報告裡一律寫成替代測量，比照本專案對 `sleep_efficiency`
/// （分母不含入睡潛伏期）與 `movement_sample_minutes`（其實是取樣分鐘數）
/// 的既有處理標準。
///
/// 但**對「睡眠拖延」這個研究問題而言，這個 proxy 正好對題**：
/// Kroese et al. (2014) 的定義是「在沒有外在因素阻礙的情況下，未能在
/// 預定時間上床」——那是純粹的行為，定義裡沒有睡眠品質。
/// （同一段理由寫在 `behavior/adherence.py` 的檔頭。）
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 這個檔案不算達成度
/// ═══════════════════════════════════════════════════════════════════
///
/// 「距離目標就寢差幾分鐘」由後端 `behavior/adherence.py` 的
/// `adherence_minutes()` 算，它處理了跨午夜正規化（目標 23:30、實際
/// 02:15 直覺相減會得到「提早 21 小時」）。在 Dart 再寫一份就會有第二個
/// 定義處，兩份漂移時不會有任何錯誤訊息——與「不要在 Dart 從
/// final_quality 推 pet_mood」是同一條紀律：**Python 判斷、Dart 只負責畫。**
///
/// 這裡只做一件 Python 做不到的事：把原始事件流變成一個時刻。

/// 一筆原生端來的互動事件。
@immutable
class InteractionEvent {
  final DateTime timestamp;

  /// resumed / paused / screen_on / screen_off / keyguard_hidden / keyguard_shown
  final String type;

  final String packageName;

  const InteractionEvent({
    required this.timestamp,
    required this.type,
    this.packageName = '',
  });

  factory InteractionEvent.fromMap(Map<Object?, Object?> map) {
    final ms = (map['timestamp'] as num?)?.toInt() ?? 0;
    return InteractionEvent(
      timestamp: DateTime.fromMillisecondsSinceEpoch(ms),
      type: (map['type'] as String?) ?? '',
      packageName: (map['package_name'] as String?) ?? '',
    );
  }

  /// 解鎖了——**這是唯一能證明「人拿起了手機」的事件**。見 [LightsOutMode]。
  static const String unlocked = 'keyguard_hidden';
}

/// 判斷「人在用手機」的兩種模式。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 螢幕亮 ≠ 有人在用（實機才看得到的錯）
/// ═══════════════════════════════════════════════════════════════════
///
/// 第一版把 `SCREEN_INTERACTIVE`（螢幕亮）與 `ACTIVITY_RESUMED` 當成互動。
/// 單元測試全過，實機上卻回報「偵測不到就寢時刻」。
///
/// 拉 `adb shell dumpsys usagestats` 出來對，2026-09-01 03:45~08:00
/// 那段（人明顯在睡）有：
///
///     KEYGUARD_HIDDEN      0 次   ← 手機一次都沒被解鎖
///     SCREEN_INTERACTIVE  14 次
///     ACTIVITY_RESUMED    14 次   Bixby 6、抖音 6、鬧鐘 2
///
/// 全部是**通知把螢幕點亮**與背景活動，沒有一次是人拿起手機。這些假的
/// 互動把整夜切成 39 / 30 / 28 分鐘的碎片，最長的安靜期只剩 148 分鐘
/// （而且落在白天），於是畫面顯示「沒有一段安靜超過三小時」——
/// 結論講得很誠實，前提卻是錯的。
///
/// 改成「解鎖才算互動」之後，同一份資料的最長安靜期變成
/// **249 分鐘（03:51 放下 → 08:00 拿起）**，第二長的只有 148 分鐘，
/// 兩者分得很開。
///
/// ⚠️ 順帶解掉了另一個問題：解鎖區段本來就涵蓋「連續看兩小時同一個 App」，
/// 因為那段期間手機一直是解鎖的。activity 模式要靠 resumed→paused 配對
/// 才補得起來的那個洞，unlock 模式根本不存在。
enum LightsOutMode {
  /// 拿 `keyguard_hidden` → `keyguard_shown` / `screen_off`
  /// 圈出「解鎖中」的區段。**這是想要的模式。**
  ///
  /// ⚠️ 這個模式**完全不看** `resumed` / `paused`。鎖著的時候那兩種事件
  /// 照樣會發生（背景服務、通知），算進來就回到上面那個錯誤。
  unlock,

  /// 退化模式：這支手機在這個視窗裡沒有給任何 `keyguard_hidden`。
  ///
  /// 部分 ROM 只把鎖定畫面事件發給系統 App。沒有解鎖訊號時只能退回
  /// 「App 前景切換」，**準確度明顯較差**——夜間的背景活動分不出來。
  activity,
}

enum LightsOutStatus {
  /// 找到了一段夠長的安靜期，[LightsOutResult.at] 是它的起點
  ok,

  /// 有事件，但整個視窗裡沒有任何一段安靜超過門檻
  noQuietGap,

  /// 視窗內完全沒有事件（剛開機、剛授權、或手機整天沒開）
  noEvents,

  /// 還沒授權「使用情況存取」
  permissionRequired,

  /// 這個平台沒有這個能力（iOS、桌機、widget test）
  unsupported,

  /// 呼叫原生端時出錯
  failed,
}

@immutable
class LightsOutResult {
  final LightsOutStatus status;

  /// 放下手機的時刻。只有 [LightsOutStatus.ok] 時非 null。
  final DateTime? at;

  /// 那之後的安靜長度（分鐘）。**這不是睡眠時數**——它到「下一次碰手機」
  /// 為止，而醒來後不一定馬上碰手機。
  final int quietMinutes;

  /// 是哪一種事件標記了那個時刻。`screen_off` / `keyguard_shown` 比
  /// `paused` 更貼近「放下手機」，但不是每支手機都給得到。
  final String? sourceType;

  /// 視窗內收到幾筆**採用的**事件（見 [mode]，兩種模式看的事件不同）。
  /// 0 筆與「有事件但沒有安靜期」要分得開。
  final int eventCount;

  /// 用哪一種判準認定「人在用手機」。`activity` 是退化模式，準確度較差。
  final LightsOutMode mode;

  final String? error;

  const LightsOutResult(
    this.status, {
    this.at,
    this.quietMinutes = 0,
    this.sourceType,
    this.eventCount = 0,
    this.mode = LightsOutMode.unlock,
    this.error,
  });

  /// 後端 `POST /nightly` 要的 ISO8601 字串（含 +08:00 之類的位移）。
  ///
  /// ⚠️ 不要 `.toUtc()`——`behavior/adherence.py` 的 `night_date()` 與
  /// `adherence_minutes()` 都是拿牆鐘時間跟 "23:30" 這種本地目標比。
  /// 送 UTC 過去，就寢時刻會整整差掉一個時區
  /// （與 `wall_clock.dart` 修掉的那個 bug 是同一類）。
  String? get iso8601 => at?.toIso8601String();
}

/// 「安靜多久才算去睡了」。
///
/// ⚠️ **這是工程判斷，不是文獻門檻。** 必須講清楚，因為本專案每一項
/// **計分**都有引文（見 `Research-Background/Garmin手錶分數.md`）。
/// 之所以可以這樣訂，是因為它不進任何分數——它只決定「哪一筆事件被當成
/// 就寢時刻」，屬於偵測層。同一條界線寫在 `TAPO_HANDOFF.md`：
/// **偵測門檻 ≠ 計分門檻**，前者拿觀測資料校準，後者才必須有文獻。
///
/// 取 3 小時的理由：要長到不會被「睡前放下手機去洗澡」或半夜起來上廁所
/// 誤觸發，又要短到抓得住只睡 4 小時的夜晚（那正是本專案最在意的夜晚，
/// 門檻訂太長會把睡最少的人整晚判成「沒有資料」）。
const int kMinQuietMinutes = 180;

/// 往回看多久。一天，這樣不管在早上還是深夜查，上一段睡眠都在視窗裡。
const Duration kLightsOutWindow = Duration(hours: 24);

/// 一次最多向原生端要幾筆事件。要與 `UsageStatsService.kt` 的
/// `getInteractionEvents(limit)` 預設值一致。
///
/// ⚠️ 實機（三星 One UI）24 小時有 **4057 筆**，所以 2000 這種值會把視窗
/// 砍掉一半——而且砍掉的是舊的那半，正好是昨晚睡覺的那段。
const int kMaxInteractionEvents = 20000;

/// 一個「停止使用」事件在**沒有配對的開始事件**時，還算不算證據。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 這個函式存在的唯一理由，是實機上就寢時刻**正好是事件流的第一筆**
/// ═══════════════════════════════════════════════════════════════════
///
/// 實測 2026-09-02 02:25 那次查詢，`queryEvents()` 回來的第一筆是
/// `2026-09-01 03:51:11 screen_off`——而那正是要找的就寢時刻。
/// 它前面沒有解鎖事件（流就從那裡開始），所以「沒配對就丟掉」會把
/// 唯一正確的答案丟掉，剩下的最長空隙變成白天的 147 分鐘。
///
/// 但也不能全部收下：那一夜 04:30~07:53 有五次通知把螢幕點亮又熄掉，
/// 每一次都會產生一個沒配對的 `screen_off`，收下就會把 249 分鐘切碎。
///
/// 分界在**這個事件本身能不能證明「剛剛還在用」**：
///
/// | 事件 | 沒配對時 | 為什麼 |
/// |---|---|---|
/// | `keyguard_shown` | ✅ 算 | 上鎖是 解鎖→鎖定 的轉換，不解鎖就不會發生 |
/// | `screen_off` | ❌ 不算 | 鎖著的時候通知也會讓螢幕亮了又暗 |
///
/// 實測驗證：那一夜 03:50~08:05 之間 `KEYGUARD_SHOWN` 只出現在
/// **03:51:16**（就寢），中間五次通知一次都沒有。這個訊號是乾淨的。
///
/// activity 模式沒有鎖定畫面訊號可以倚賴，`paused` 已經是最好的證據，
/// 所以照收。
bool _unmatchedEndIsEvidence(String type, LightsOutMode mode) {
  if (mode == LightsOutMode.activity) return true;
  return type == 'keyguard_shown';
}

class _Interval {
  DateTime start;
  DateTime end;
  String endType;
  _Interval(this.start, this.end, this.endType);
}

/// 從事件流找出就寢時刻。**純函式，沒有 I/O，測得到。**
///
/// 做法是把事件流還原成「使用中的區間」，再找區間之間最長的空隙。
/// 「使用中」怎麼認由 [LightsOutMode] 決定——**那一段一定要讀**，
/// 用錯判準的話演算法完全正確、答案卻是錯的（實機上真的發生過）。
LightsOutResult detectLightsOut(
  List<InteractionEvent> events, {
  required DateTime windowStart,
  required DateTime windowEnd,
  int minQuietMinutes = kMinQuietMinutes,
}) {
  final inWindow = events
      .where((e) =>
          !e.timestamp.isBefore(windowStart) && !e.timestamp.isAfter(windowEnd))
      .toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  if (inWindow.isEmpty) {
    return const LightsOutResult(LightsOutStatus.noEvents);
  }

  // ── 挑判準 ──────────────────────────────────────────────────────
  //
  // 有解鎖訊號就用解鎖，沒有才退回 App 前景切換。判斷依據是**這個視窗裡
  // 實際收到的事件**而不是 Android 版本——同一支手機在不同情況下給不給
  // keyguard 事件是會變的，問資料比問版本可靠。
  final bool hasUnlock =
      inWindow.any((e) => e.type == InteractionEvent.unlocked);
  final mode = hasUnlock ? LightsOutMode.unlock : LightsOutMode.activity;

  // ⚠️ unlock 模式**刻意不含** resumed / paused：手機鎖著的時候那兩種
  //    事件照樣會發生（通知、背景服務），算進來就等於沒有這個修正。
  final Set<String> startTypes =
      hasUnlock ? const {'keyguard_hidden'} : const {'resumed', 'screen_on'};
  final Set<String> endTypes = hasUnlock
      ? const {'keyguard_shown', 'screen_off'}
      : const {'paused', 'screen_off', 'keyguard_shown'};

  final relevant = inWindow
      .where((e) => startTypes.contains(e.type) || endTypes.contains(e.type))
      .toList();

  if (relevant.isEmpty) {
    return LightsOutResult(
      LightsOutStatus.noEvents,
      mode: mode,
    );
  }

  // ── 還原「使用中」的區間 ────────────────────────────────────────
  final intervals = <_Interval>[];
  DateTime? openStart;

  for (final e in relevant) {
    if (startTypes.contains(e.type)) {
      // 連續兩個 start（切 App 時 resumed 會比前一個 paused 早到）
      // 只認第一個，後面的落在同一段使用裡。
      openStart ??= e.timestamp;
    } else if (openStart != null) {
      intervals.add(_Interval(openStart, e.timestamp, e.type));
      openStart = null;
    } else if (_unmatchedEndIsEvidence(e.type, mode)) {
      // 沒有配對 start 的 end，但仍然算數——當成**一個點**而不是
      // 「從 windowStart 一路用到現在」。我們沒有那段的證據，
      // 硬填會把視窗開頭的空隙整個吃掉。
      intervals.add(_Interval(e.timestamp, e.timestamp, e.type));
    }
  }
  if (openStart != null) {
    // 還在用（或最後一個 paused 掉了）——算到視窗結尾為止。
    intervals.add(_Interval(openStart, windowEnd, 'open'));
  }

  // ── 合併重疊的區間 ──────────────────────────────────────────────
  final merged = <_Interval>[];
  for (final it in intervals) {
    if (merged.isNotEmpty && !it.start.isAfter(merged.last.end)) {
      if (it.end.isAfter(merged.last.end)) {
        merged.last.end = it.end;
        merged.last.endType = it.endType;
      }
    } else {
      merged.add(_Interval(it.start, it.end, it.endType));
    }
  }

  // ── 找最長的空隙 ────────────────────────────────────────────────
  //
  // ⚠️ 只認**兩段使用之間**的空隙，頭尾都不算：
  //
  //  - 視窗開頭到第一段使用之間也是空的，但那是「更早的事我們沒查」，
  //    不是「他放下了手機」。算進去的話，剛授權完的第一次查詢就會回一個
  //    憑空生出來的就寢時刻。
  //  - 最後一段使用到視窗結尾同理：那段安靜**還沒結束**，不構成「睡了
  //    一晚」的證據。而且視窗結尾是「現在」，它幾乎一定是最長的一段，
  //    會直接蓋掉真正的那一段。實務上不會因此漏掉——人要開這個 App
  //    就得先解鎖，所以視窗結尾一定落在一段使用裡。
  //
  // 換句話說：**就寢時刻一定是一段「已經結束」的安靜期的起點**，
  // 而結束的證據就是他後來又把手機拿了起來。
  _Interval? best;
  int bestMinutes = 0;

  for (var i = 0; i + 1 < merged.length; i++) {
    final minutes = merged[i + 1].start.difference(merged[i].end).inMinutes;
    if (minutes > bestMinutes) {
      bestMinutes = minutes;
      best = merged[i];
    }
  }

  if (best == null || bestMinutes < minQuietMinutes) {
    return LightsOutResult(
      LightsOutStatus.noQuietGap,
      eventCount: relevant.length,
      quietMinutes: bestMinutes,
      mode: mode,
    );
  }

  return LightsOutResult(
    LightsOutStatus.ok,
    at: best.end,
    quietMinutes: bestMinutes,
    sourceType: best.endType,
    eventCount: relevant.length,
    mode: mode,
  );
}
