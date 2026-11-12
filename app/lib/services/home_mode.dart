import 'package:flutter/material.dart';

import '../widgets/bedtime_urgency.dart';
import 'bed_marks.dart';
import 'bedtime_guard.dart';

/// 首頁現在該顯示哪一版。規則由使用者 2026-11-12 定案（grill 五輪）。
///
/// | 版面 | 什麼時候 |
/// |---|---|
/// | [HomeMode.sleeping] | 有一個還沒按「下床」、而且未滿 [kMaxSleepSession] 的「開始睡覺」 |
/// | [HomeMode.evening] | 目標就寢前 [kEveningLeadIn] ～ 目標後 [kOverdueWindow] |
/// | [HomeMode.lateEvening] | 目標後 [kOverdueWindow] ～ 目標後 [kEveningTail] |
/// | [HomeMode.day] | 其他時間（包括下午） |
///
/// ⚠️ **三個時間都沿用既有常數，不另訂**：
/// - 晚上版的起點 = 倒數變黃色的那一刻（[kApproachingThreshold]）
/// - 「過了就不再紅」= 倒數停止變紅的那一刻（[kOverdueWindow]）
/// - 晚上版的終點 = 就寢守門的尾巴（[kGuardTail]）
/// 另訂一組數字的話，會出現「倒數已經黃了、首頁卻還是白天版」這種兩邊對不上。
///
/// ⚠️ 判斷全部在這支純函式裡，畫面只照它畫。理由同 `bedtime_guard.dart`：
/// 這種「現在幾點該怎樣」的規則散在 widget 裡就測不到。
enum HomeMode { day, evening, lateEvening, sleeping }

const Duration kEveningLeadIn = kApproachingThreshold;
const Duration kEveningTail = kGuardTail;

/// 一晚最長多久。超過就不再當成「還在睡」，退回一般首頁。
///
/// ⚠️ 與 `bed_marks.dart` 的 [kBedMarkMaxAge]（36 小時）是兩件事：那個管
/// 「標記多久還能上傳」，這個管「睡覺畫面多久還合理」。用 36 小時的話，
/// 忘了按下床的人隔天下午打開 App 還會看到「Sleeping since 00:12」。
/// 14 小時沿用 `bed_marks.dart` 註解裡「一夜最長約 14 小時」。
const Duration kMaxSleepSession = Duration(hours: 14);

/// 有沒有一個「正在睡」的標記：按了開始、還沒按下床、未滿 [kMaxSleepSession]。
bool isSleeping(DateTime now, BedMarks marks) {
  final start = marks.startAt;
  if (start == null || marks.endAt != null) return false;
  if (start.isAfter(now)) return false; // 時鐘被往回調過，不要卡在睡覺畫面
  return now.difference(start) < kMaxSleepSession;
}

/// 包住 [now] 的那一次目標就寢時刻（晚上版的時段以它為中心）。
/// null = 現在不在任何一晚的晚上版時段內。
DateTime? eveningAnchor(DateTime now, TimeOfDay bedtime) {
  final today =
      DateTime(now.year, now.month, now.day, bedtime.hour, bedtime.minute);
  // 跨午夜的目標（例如 01:00）在晚上 23:00 時屬於「明天」那一次，
  // 凌晨 02:00 時屬於「今天」那一次，所以前後一天都要看。
  for (final days in const [-1, 0, 1]) {
    final anchor = today.add(Duration(days: days));
    final start = anchor.subtract(kEveningLeadIn);
    final end = anchor.add(kEveningTail);
    if (!now.isBefore(start) && now.isBefore(end)) return anchor;
  }
  return null;
}

HomeMode homeModeFor({
  required DateTime now,
  required TimeOfDay bedtime,
  BedMarks marks = BedMarks.none,
}) {
  if (isSleeping(now, marks)) return HomeMode.sleeping;
  final anchor = eveningAnchor(now, bedtime);
  if (anchor == null) return HomeMode.day;
  if (!now.isBefore(anchor.add(kOverdueWindow))) return HomeMode.lateEvening;
  return HomeMode.evening;
}
