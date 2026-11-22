import 'package:flutter/material.dart';

import 'key_value_store.dart';
import 'sleep_plan.dart';

/// 「想改善什麼」（2026-11-22 grill，第一次登入流程的一步＋計畫頁的 Help me pick）。
///
/// ⚠️ 目標、對應、畫面上的字**逐字照抄** `Research-Background/睡眠計畫.md`「目標 → 建議」（使用者 11-22 審過），
///    `plan_goals_test.dart` 直接讀那份文件比對。改對應或措辭先改文件。
/// ⚠️ 目標只存在手機上：不送後端、不給 AI、不進分數與徽章（同自己勾的習慣）。

@immutable
class PlanGoal {
  final String id;
  final String label;
  final IconData icon;

  /// 推薦哪幾條（建議清單的 id），照順序。
  final List<String> habits;
  const PlanGoal(this.id, this.label, this.icon, this.habits);
}

const List<PlanGoal> kPlanGoals = [
  PlanGoal('earlier', 'Go to bed earlier', Icons.bedtime_rounded, ['morning_light', 'dim_screen']),
  PlanGoal('less_phone', 'Less phone before bed', Icons.phonelink_erase_rounded, ['dim_screen']),
  PlanGoal('rested', 'Wake up feeling rested', Icons.wb_twilight_rounded, ['late_caffeine', 'alcohol', 'dim_screen']),
  PlanGoal('sound', 'Sleep more soundly', Icons.nights_stay_rounded, ['temperature', 'noise', 'alcohol', 'exercise']),
];

/// 最多選幾個目標、推薦合起來最多幾條。
const int kMaxPlanGoals = 2;
const int kMaxGoalHabits = 3;

// 畫面上的字（照抄文件「畫面上的字」那張表）
const String kGoalQuestion = 'What would you like to work on?';
const String kGoalSubtitle = 'Pick up to two.';
const String kGoalSkip = 'Not sure — skip';
const String kGoalRecTitle = 'A few to start with';
const String kGoalRecSubtitle = "Untick any you don't want. You can change them anytime.";
const String kGoalJourneyLine = 'Want to move your bedtime step by step? Try a Journey.';
const String kGoalTrackedLine = "Already tracked for you: Lights out on time · Phone down once you're in bed";

/// Add N habits（N＝勾著的條數）；0 條時是 Skip。
String goalAddLabel(int n) => n == 0 ? 'Skip' : 'Add $n ${n == 1 ? 'habit' : 'habits'}';

PlanGoal? goalById(String id) {
  for (final g in kPlanGoals) {
    if (g.id == id) return g;
  }
  return null;
}

/// 推薦哪幾條：兩個目標**交錯取**（目標 1 第 1 條、目標 2 第 1 條、目標 1 第 2 條…），
/// 重複的只算一次、已經在計畫裡的跳過，取到 [kMaxGoalHabits] 條為止。
List<String> recommendHabits(List<String> goalIds, {Set<String> already = const {}}) {
  final lists = [for (final id in goalIds) ?goalById(id)?.habits];
  final out = <String>[];
  for (var i = 0; out.length < kMaxGoalHabits; i++) {
    var any = false;
    for (final l in lists) {
      if (i >= l.length) continue;
      any = true;
      final h = l[i];
      if (out.length < kMaxGoalHabits && !out.contains(h) && !already.contains(h) && suggestionById(h) != null) {
        out.add(h);
      }
    }
    if (!any) break;
  }
  return out;
}

/// 選的目標與「問過了沒」，只存在手機上。
class PlanGoalsStore {
  static const String goalsKey = 'plan_goals_v1';
  static const String askedKey = 'plan_goals_asked_v1';

  final KeyValueStore store;
  const PlanGoalsStore(this.store);

  Future<bool> asked() async {
    try {
      return await store.getString(askedKey) == '1';
    } catch (_) {
      return true; // 讀不到就當問過了：寧可不問，也不要每次打開都跳出來
    }
  }

  /// 計畫頁自己跳出來問的那一次：一跳出來就算問過了（往下拉關掉也算，不會每次打開都問）。
  Future<void> markAsked() async {
    try {
      await store.setString(askedKey, '1');
    } catch (_) {}
  }

  /// 記下選了什麼（跳過也算問過了）。
  Future<void> save(List<String> goals) async {
    try {
      await store.setString(goalsKey, goals.join(','));
      await store.setString(askedKey, '1');
    } catch (_) {}
  }

  Future<List<String>> goals() async {
    try {
      final raw = await store.getString(goalsKey);
      return [for (final g in (raw ?? '').split(',')) if (goalById(g) != null) g];
    } catch (_) {
      return const [];
    }
  }
}
