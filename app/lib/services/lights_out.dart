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
/// 一段「已經結束」的安靜期，當成就寢時刻的候選。
///
/// ⚠️ 手機**不判斷**哪一段才對——它照舊送出自己挑的那一個
/// （[LightsOutResult.at]），候選只是額外附上的材料。判斷在後端，
/// 因為裁判（手錶認定的入睡時刻）只有後端拿得到。
class QuietCandidate {
  /// 這一段安靜的起點＝候選的就寢時刻（前一次使用結束的那一刻）。
  final DateTime at;

  /// 這一段安靜多久（分鐘）。
  final int quietMinutes;

  /// 是哪一種事件標記了起點（同 [LightsOutResult.sourceType]）。
  final String sourceType;

  /// 這一段跨過了幾次半夜的短解鎖（見 [kBriefUnlockSeconds]）。
  /// 一般的候選是 0；只有第 4 條規則產生的那一段才會 > 0。
  final int bridgedUnlocks;

  const QuietCandidate({
    required this.at,
    required this.quietMinutes,
    required this.sourceType,
    this.bridgedUnlocks = 0,
  });

  /// `POST /nightly` 的 `quiet_candidates` 陣列元素。
  ///
  /// ⚠️ 時刻一律 `toIso8601String()`、**不要 `.toUtc()`**——後端
  /// `night_date()` 與達成度都是拿牆鐘時間比，送 UTC 會整整差一個時區。
  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'quiet_minutes': quietMinutes,
        'source_type': sourceType,
        'bridged_unlocks': bridgedUnlocks,
      };
}

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

  /// 跨過了幾次半夜的短解鎖（第 4 條規則，見 [kBriefUnlockSeconds]）。
  /// 0＝照原本的規則就偵測到了。會跟著上傳（`bridged_unlocks`），只供分析、不顯示。
  final int bridgedUnlocks;

  /// 所有 ≥ [kCandidateMinMinutes] 的安靜期，依時間排序（見 [QuietCandidate]）。
  ///
  /// ⚠️ [at] 那一段**一定在裡面**——後端挑不到更好的候選時會退回它，
  /// 不在裡面的話那一晚會莫名其妙變成「不知道」。
  final List<QuietCandidate> candidates;

  const LightsOutResult(
    this.status, {
    this.at,
    this.quietMinutes = 0,
    this.sourceType,
    this.eventCount = 0,
    this.mode = LightsOutMode.unlock,
    this.error,
    this.bridgedUnlocks = 0,
    this.candidates = const [],
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

/// 第 4 條規則：半夜「看一下時間」的短解鎖可以跨過去（2026-11-15 使用者定）。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 只在原本的規則找不到 ≥ [kMinQuietMinutes] 的安靜期時才用（fallback）
/// ═══════════════════════════════════════════════════════════════════
///
/// 實例 11-12：05:43 放下手機（手錶 05:54 入睡），07:20 解鎖 4 秒看時間，09:28 起床。
/// 那 4 秒把 3 小時 45 分的安靜期切成 97＋128 分鐘，兩段都不到 3 小時 → 整晚偵測不到。
///
/// - 一次「短解鎖」＝一段使用 < 30 秒。⚠️ **這是設計決策，沒有文獻依據**（同 3 小時那個門檻，
///   屬偵測層、不進任何分數）。30 秒涵蓋看時間、看一則通知，不涵蓋回訊息。
/// - 比對之前先把相隔 < [kUnlockCoalesceSeconds] 秒的紀錄併成一次使用：一次解鎖在事件流上
///   常是「screen_off」接著 0.7 秒後的「keyguard_shown」，不併的話一次會被算成兩次。
/// - 可以跨**任意次**，每一次都要 < 30 秒，跨完的整段仍要 ≥ 3 小時。
/// - 有好幾段都過 3 小時時，挑**跨最少次**的那段，同樣次數再挑最長的。理由：睡前 5 秒看一下
///   鬧鐘也是短解鎖，挑最長的會把它也跨過去、就寢時刻往前移；挑最少次就停在睡前最後一次使用。
/// - 就寢時刻＝整段的起點＝睡前最後一次使用結束，同原本的規則。
/// - **只用在 unlock 模式**：activity 模式本來就會被通知切碎，跨過去會跨到不該跨的。
/// - 原本的三條規則照舊：短解鎖本身仍是「使用」，只是允許跨過；頭尾空隙仍不算。
const int kBriefUnlockSeconds = 30;

/// 相隔幾秒以內的使用紀錄併成同一次解鎖（見 [kBriefUnlockSeconds]）。
const int kUnlockCoalesceSeconds = 10;

/// 候選安靜期的下限（2026-11-16 使用者定）。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 這**不是**挑選門檻，是「要不要把這一段附在上傳裡」的門檻
/// ═══════════════════════════════════════════════════════════════════
///
/// 現行規則挑**最長**的那一段，而半夜起來用幾分鐘手機會把一晚切成兩段。
/// 11-16 實例：00:49 放下（手錶 00:56 入睡），02:18 醒來用 5 分 3 秒，02:23 再睡。
/// 兩段是 88.4 與 218.8 分鐘 → 挑到後面那段 → 記成熬夜 98.6 分鐘。
/// 真正那一段**不可能晚於手錶認定的入睡**，但只有後端拿得到手錶資料，
/// 而後端收到的只有一個時刻——所以手機要把**所有**候選都附上去，
/// 由後端用手錶當裁判刷掉不可能的那些（`behavior/lights_out_resolve.py`）。
///
/// 下限取 60 分鐘：11-16 真正那段是 88 分，訂 90 就會漏掉
/// 「上床後 70 分鐘被叫起來」那種夜晚。⚠️ 設計決策，沒有文獻（屬偵測層）。
const int kCandidateMinMinutes = 60;

/// 最多附幾段候選。超過就留最長的幾段（**當選的那段一定留著**）。
/// 11-16 全天 ≥60 分鐘的只有 2 段，10 是上限不是常態。
const int kMaxCandidates = 10;

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

  // 候選（2026-11-16）：同一個迴圈順便把每一段 ≥ kCandidateMinMinutes 的
  // 空隙都記下來。⚠️ 判準與 best 完全一樣（都是兩段使用之間的空隙），
  // 只差在門檻——分開寫兩個迴圈就會有第二份「什麼算安靜期」的定義。
  final candidates = <QuietCandidate>[];

  for (var i = 0; i + 1 < merged.length; i++) {
    final minutes = merged[i + 1].start.difference(merged[i].end).inMinutes;
    if (minutes >= kCandidateMinMinutes) {
      candidates.add(QuietCandidate(
        at: merged[i].end,
        quietMinutes: minutes,
        sourceType: merged[i].endType,
      ));
    }
    if (minutes > bestMinutes) {
      bestMinutes = minutes;
      best = merged[i];
    }
  }

  if (best == null || bestMinutes < minQuietMinutes) {
    // 第 4 條規則（fallback）：跨過半夜的短解鎖再找一次。
    final bridged = mode == LightsOutMode.unlock
        ? _bridgeBriefUnlocks(merged, minQuietMinutes)
        : null;
    if (bridged != null) {
      final chosen = QuietCandidate(
        at: bridged.at,
        quietMinutes: bridged.minutes,
        sourceType: bridged.endType,
        bridgedUnlocks: bridged.count,
      );
      return LightsOutResult(
        LightsOutStatus.ok,
        at: bridged.at,
        quietMinutes: bridged.minutes,
        sourceType: bridged.endType,
        eventCount: relevant.length,
        mode: mode,
        bridgedUnlocks: bridged.count,
        candidates: _capCandidates(candidates, chosen),
      );
    }
    // 偵測不到的夜晚**照樣附候選**：後端可能拿手錶刷掉之後，剩下的那段
    // 正好是對的（候選只要 60 分鐘，不必 3 小時）。
    return LightsOutResult(
      LightsOutStatus.noQuietGap,
      eventCount: relevant.length,
      quietMinutes: bestMinutes,
      mode: mode,
      candidates: _capCandidates(candidates, null),
    );
  }

  final chosen = QuietCandidate(
    at: best.end,
    quietMinutes: bestMinutes,
    sourceType: best.endType,
  );
  return LightsOutResult(
    LightsOutStatus.ok,
    at: best.end,
    quietMinutes: bestMinutes,
    sourceType: best.endType,
    eventCount: relevant.length,
    mode: mode,
    candidates: _capCandidates(candidates, chosen),
  );
}

/// 最多留 [kMaxCandidates] 段：留最長的幾段，但 [chosen]（手機挑的那一段）
/// **一定留著**。
///
/// ⚠️ 少了這個保證，候選多到爆表的夜晚後端會找不到手機挑的那一段，
/// 而那正是「挑不到更好的就退回原值」的退路。
List<QuietCandidate> _capCandidates(
  List<QuietCandidate> all,
  QuietCandidate? chosen,
) {
  final kept = <QuietCandidate>[];
  // 跨短解鎖產生的那一段不在 all 裡（它橫跨了好幾段），要另外補進來。
  final bool chosenInAll =
      chosen != null && all.any((c) => c.at == chosen.at && c.bridgedUnlocks == chosen.bridgedUnlocks);
  if (chosen != null && !chosenInAll) kept.add(chosen);

  final rest = [...all]
    ..sort((a, b) => b.quietMinutes.compareTo(a.quietMinutes));
  for (final c in rest) {
    if (kept.length >= kMaxCandidates) break;
    kept.add(c);
  }
  // 留著的那幾段依時間排序後送出（後端挑「最晚」的那一段，順序只是方便讀）。
  kept.sort((a, b) => a.at.compareTo(b.at));
  return kept;
}

/// 第 4 條規則的實作（見 [kBriefUnlockSeconds]）。找不到 ≥ [minQuietMinutes] 的段落 → null。
({DateTime at, int minutes, String endType, int count})? _bridgeBriefUnlocks(
  List<_Interval> merged,
  int minQuietMinutes,
) {
  // 相隔幾秒的紀錄併成一次使用
  final uses = <_Interval>[];
  for (final it in merged) {
    if (uses.isNotEmpty &&
        it.start.difference(uses.last.end).inSeconds < kUnlockCoalesceSeconds) {
      if (it.end.isAfter(uses.last.end)) {
        uses.last.end = it.end;
        uses.last.endType = it.endType;
      }
    } else {
      uses.add(_Interval(it.start, it.end, it.endType));
    }
  }
  bool brief(_Interval u) =>
      u.endType != 'open' &&
      u.end.difference(u.start).inSeconds < kBriefUnlockSeconds;

  ({DateTime at, int minutes, String endType, int count})? best;
  // uses[i] 是睡前最後一次使用；往後跨過連續的短解鎖，停在下一次真正的使用（或最後一筆）。
  // ⚠️ 頭尾空隙仍不算：起點一定是某一段使用的結束，終點一定是某一段使用的開始。
  for (var i = 0; i + 1 < uses.length; i++) {
    var k = i + 1;
    var count = 0;
    while (k < uses.length - 1 && brief(uses[k])) {
      count++;
      k++;
    }
    if (count == 0) continue; // 沒跨，原本的規則已經看過這一段
    final minutes = uses[k].start.difference(uses[i].end).inMinutes;
    if (minutes < minQuietMinutes) continue;
    final b = best;
    if (b == null ||
        count < b.count ||
        (count == b.count && minutes > b.minutes)) {
      best = (
        at: uses[i].end,
        minutes: minutes,
        endType: uses[i].endType,
        count: count,
      );
    }
  }
  return best;
}
