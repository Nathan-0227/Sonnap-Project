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

  /// 代表「開始使用」的事件。
  static const Set<String> startTypes = {
    'resumed',
    'screen_on',
    'keyguard_hidden',
  };

  /// 代表「停止使用」的事件。
  static const Set<String> endTypes = {
    'paused',
    'screen_off',
    'keyguard_shown',
  };

  bool get isStart => startTypes.contains(type);
  bool get isEnd => endTypes.contains(type);
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

  /// 視窗內收到幾筆事件。0 筆與「有事件但沒有安靜期」要分得開。
  final int eventCount;

  final String? error;

  const LightsOutResult(
    this.status, {
    this.at,
    this.quietMinutes = 0,
    this.sourceType,
    this.eventCount = 0,
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

class _Interval {
  DateTime start;
  DateTime end;
  String endType;
  _Interval(this.start, this.end, this.endType);
}

/// 從事件流找出就寢時刻。**純函式，沒有 I/O，測得到。**
///
/// 做法是把事件流還原成「使用中的區間」，再找區間之間最長的空隙。
///
/// ⚠️ 為什麼不能只取最後一筆 `paused`：**連續使用同一個 App 期間一個
/// 事件都不會產生**。23:05 打開 YouTube、看到 01:00 螢幕關掉，中間是空的。
/// 只看 paused 的話那兩小時看起來像「沒動手機」。必須把 resumed→paused
/// 之間整段標成使用中，空隙才是真的空隙。
LightsOutResult detectLightsOut(
  List<InteractionEvent> events, {
  required DateTime windowStart,
  required DateTime windowEnd,
  int minQuietMinutes = kMinQuietMinutes,
}) {
  final relevant = events
      .where((e) => e.isStart || e.isEnd)
      .where((e) =>
          !e.timestamp.isBefore(windowStart) && !e.timestamp.isAfter(windowEnd))
      .toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  if (relevant.isEmpty) {
    return const LightsOutResult(LightsOutStatus.noEvents);
  }

  // ── 還原「使用中」的區間 ────────────────────────────────────────
  final intervals = <_Interval>[];
  DateTime? openStart;

  for (final e in relevant) {
    if (e.isStart) {
      // 連續兩個 start（切 App 時 resumed 會比前一個 paused 早到）
      // 只認第一個，後面的落在同一段使用裡。
      openStart ??= e.timestamp;
    } else {
      // ⚠️ 沒有配對 start 的 end，代表這段使用從視窗之前就開始了。
      //    這裡當成**一個點**而不是「從 windowStart 一路用到現在」——
      //    我們沒有那段的證據，硬填會把視窗開頭的空隙整個吃掉。
      intervals.add(_Interval(openStart ?? e.timestamp, e.timestamp, e.type));
      openStart = null;
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
  // ⚠️ 只看「某一段使用之後」的空隙。視窗開頭到第一段使用之間也是空的，
  //    但那是「更早的事我們沒查」，不是「他放下了手機」——把它算進來，
  //    剛授權完的第一次查詢就會回一個憑空生出來的就寢時刻。
  _Interval? best;
  int bestMinutes = 0;

  for (var i = 0; i < merged.length; i++) {
    final gapEnd = i + 1 < merged.length ? merged[i + 1].start : windowEnd;
    final minutes = gapEnd.difference(merged[i].end).inMinutes;
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
    );
  }

  return LightsOutResult(
    LightsOutStatus.ok,
    at: best.end,
    quietMinutes: bestMinutes,
    sourceType: best.endType,
    eventCount: relevant.length,
  );
}
