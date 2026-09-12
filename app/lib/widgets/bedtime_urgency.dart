import 'package:flutter/material.dart';

/// 離就寢時間還有多近。**純函式，沒有 I/O，測得到。**
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 這些門檻不是計分門檻
/// ═══════════════════════════════════════════════════════════════════
///
/// 本專案每一項**計分**都要有文獻依據（見 `Research-Background/
/// Garmin手錶分數.md` 與設計紅線 2）。這裡的 30 / 90 分鐘不是計分，
/// 是**呈現**：它只決定倒數那幾個字用什麼顏色，不進 `final_score`、
/// 不進 `total_modifier`、不影響任何挑戰的達成判定。
///
/// 同一條界線寫在 `docs/TAPO_HANDOFF.md`（偵測門檻 ≠ 計分門檻）與
/// `lights_out.dart` 的 `kMinQuietMinutes`。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 「剛過就寢時間」必須自成一種狀態
/// ═══════════════════════════════════════════════════════════════════
///
/// `_getTimeLeftDuration()` 回的永遠是**下一次**目標時刻，所以目標 23:30
/// 的人在 23:31 看到的倒數是 **23 小時 59 分**。那個數字本身沒有錯，
/// 但如果配上「時間還很充裕」的綠色，畫面就等於在他剛剛錯過的那一分鐘
/// 恭喜他。所以這裡另外看「上一次目標時刻」——剛過去不久就是 [overdue]。
enum BedtimeUrgency {
  /// 還早。
  relaxed,

  /// 快到了（[kApproachingThreshold] 以內）。
  approaching,

  /// 就要到了（[kImminentThreshold] 以內）。
  imminent,

  /// **已經過了**目標時刻不久（[kOverdueWindow] 以內）。
  overdue,
}

/// 剩這麼久以內算「就要到了」。
///
/// ⚠️ 呈現用的工程判斷，不是文獻門檻（見上）。取 30 分鐘的理由：
/// 那大約是「現在收手還來得及準時躺下」與「已經來不及」的分界，
/// 而且短到不會整個晚上都在閃紅色——一個永遠是紅色的提示等於沒有提示。
const Duration kImminentThreshold = Duration(minutes: 30);

/// 剩這麼久以內算「快到了」。
const Duration kApproachingThreshold = Duration(minutes: 90);

/// 過了目標時刻多久之內仍然算 [BedtimeUrgency.overdue]。
///
/// ⚠️ 不能太長。超過這段之後，人已經在「今晚就是晚睡了」的狀態，
/// 而下一個目標時刻是明天——那時候再紅著也沒有可以改變的行為，
/// 只剩下責備。回饋要掛在「還能做點什麼」的時候。
const Duration kOverdueWindow = Duration(minutes: 60);

/// 現在離目標就寢時間有多近。
///
/// [now] 是牆鐘時間（`DateTime.now()`）。⚠️ 不要傳 UTC——目標就寢時間是
/// 一個沒有時區的牆鐘時刻，兩者要在同一個時間軸上比。
BedtimeUrgency bedtimeUrgency(DateTime now, TimeOfDay bedtime) {
  final todayAt = DateTime(
    now.year,
    now.month,
    now.day,
    bedtime.hour,
    bedtime.minute,
  );

  // 上一次目標時刻：今天的那個若還沒到，就是昨天的。
  final previous =
      todayAt.isAfter(now) ? todayAt.subtract(const Duration(days: 1)) : todayAt;
  final sincePrevious = now.difference(previous);
  if (sincePrevious < kOverdueWindow) return BedtimeUrgency.overdue;

  // 下一次目標時刻。
  final next =
      todayAt.isAfter(now) ? todayAt : todayAt.add(const Duration(days: 1));
  final remaining = next.difference(now);

  if (remaining <= kImminentThreshold) return BedtimeUrgency.imminent;
  if (remaining <= kApproachingThreshold) return BedtimeUrgency.approaching;
  return BedtimeUrgency.relaxed;
}

/// 倒數與進度環用的顏色。
///
/// ⚠️ [BedtimeUrgency.overdue] 與 [BedtimeUrgency.imminent] 刻意是**同一個
/// 紅色**：使用者要看的是「該去睡了」，不是「你遲到了幾分鐘」。分成兩種
/// 紅色只會讓人去比對深淺，卻沒有多告訴他任何可以做的事。
Color bedtimeUrgencyColor(BedtimeUrgency urgency) {
  switch (urgency) {
    case BedtimeUrgency.relaxed:
      return const Color(0xFF7ED957);
    case BedtimeUrgency.approaching:
      return const Color(0xFFFFD96A);
    case BedtimeUrgency.imminent:
    case BedtimeUrgency.overdue:
      return const Color(0xFFFF6B6B);
  }
}

/// 倒數數字底下那一行字。
///
/// ⚠️ [BedtimeUrgency.overdue] 時**不能寫 "to bedtime"**。那時候倒數顯示的
/// 是「距離明天的目標還有 23 小時 59 分」，配上 "to bedtime" 就是在說
/// 「你還有 23 小時可以慢慢來」，而他其實剛剛錯過。
String bedtimeUrgencyCaption(BedtimeUrgency urgency) =>
    urgency == BedtimeUrgency.overdue ? 'past bedtime' : 'to bedtime';
