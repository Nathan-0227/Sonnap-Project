import 'dart:convert';

import 'package:flutter/material.dart';

import 'key_value_store.dart';

/// 睡眠計畫（2026-11-19 使用者 grill 定案，依據與措辭在
/// `Research-Background/睡眠計畫.md`）。
///
/// 這一支管**自己勾的習慣**：清單、打勾、提醒時刻、連續天數。
/// 量測的三列（準時放下手機、上床少滑、準時起床）是後端 `/challenges`
/// 判的，**不在這裡判**——這裡連那三列的 id 都不認得。
///
/// ═══════════════════════════════════════════════════════════════════
/// 不能破的規則
/// ═══════════════════════════════════════════════════════════════════
/// - **只存在手機上**、不送後端、不給 AI（自訂文字可能是任何東西）。
/// - **不進分數、不改寵物心情、不給 XP**（紅線 4、5：自己勾不需要證據）。
///   畫面上只寫事實（連續幾天）。
/// - 建議清單的措辭**照抄研究文件**，改措辭先改文件、使用者審過。
///   `sleep_plan_test.dart` 直接讀那份文件逐字比對。
/// - id 能對應起床自評標籤的，與 `behavior/morning_tips.TAGS` 的鍵**相同**；
///   但兩邊**不互相代填**（沒勾「少喝咖啡因」不代表喝了）。
/// - 時間**跟著作息走**：存「相對於就寢／起床幾分鐘」，作息一改全部跟著移。

/// 時間跟著哪一端走。
enum PlanAnchor { bedtime, wake }

/// 建議清單的一條。
@immutable
class PlanSuggestion {
  final String id;
  final String text;
  final PlanAnchor anchor;

  /// 預設提醒時刻＝anchor + 這麼多分鐘（可以是負的）。
  /// ⚠️ 這些是**設計決策**（提醒排在幾點），不是文獻門檻——提醒預設是關的，
  ///    這個數字只決定打開提醒時的初始值。文獻管的是句子裡的數字（6 小時、4 小時…）。
  final int offsetMinutes;

  /// 圖示。
  final IconData icon;

  const PlanSuggestion(this.id, this.text, this.anchor, this.offsetMinutes, this.icon);
}

/// 建議清單（H1 拿掉：與量測的「上床少滑手機」重疊，使用者定）。
/// ⚠️ 字串與 `Research-Background/睡眠計畫.md`「自己勾的（建議清單）」逐字相同。
const List<PlanSuggestion> kPlanSuggestions = [
  PlanSuggestion('dim_screen', 'Dim your screen or switch to paper before bed.',
      PlanAnchor.bedtime, -60, Icons.brightness_low_rounded),
  PlanSuggestion('late_caffeine', 'Keep caffeine to more than 6 hours before bed.',
      PlanAnchor.bedtime, -360, Icons.coffee_rounded),
  PlanSuggestion('alcohol', 'Keep drinks light tonight.',
      PlanAnchor.bedtime, -240, Icons.wine_bar_rounded),
  PlanSuggestion('napped', 'If you nap, keep it to 10–20 minutes and not too late in the day.',
      PlanAnchor.wake, 360, Icons.airline_seat_flat_rounded),
  PlanSuggestion('temperature', 'Keep your bedroom cool.',
      PlanAnchor.bedtime, -60, Icons.ac_unit_rounded),
  PlanSuggestion('noise', 'Keep your bedroom quiet.',
      PlanAnchor.bedtime, -60, Icons.volume_off_rounded),
  PlanSuggestion('exercise', 'Get some physical activity today.',
      PlanAnchor.wake, 480, Icons.directions_walk_rounded),
  PlanSuggestion('early_workout', 'Finish hard workouts at least 4 hours before bed.',
      PlanAnchor.bedtime, -300, Icons.fitness_center_rounded),
  PlanSuggestion('todo_list', "Jot down tomorrow's to-do list before bed.",
      PlanAnchor.bedtime, -45, Icons.edit_note_rounded),
  PlanSuggestion('morning_light', 'Get outside for 30 minutes soon after you wake — cloudy days count too.',
      PlanAnchor.wake, 0, Icons.wb_sunny_rounded),
];

PlanSuggestion? suggestionById(String id) {
  for (final s in kPlanSuggestions) {
    if (s.id == id) return s;
  }
  return null;
}

/// 寵物 notes 的建議（`behavior/morning_tips.py` 的 id）→ Plan 的哪一條。
/// 「說明」那幾句（T9–T11、P4、P5、P8）不叫人做事，沒有對應；
/// T1／T2／P1 是作息本身或量測那幾列，也沒有。
const Map<String, String> kTipToPlan = {
  'T3': 'late_caffeine',
  'T4': 'alcohol',
  'P7': 'alcohol',
  'T5': 'napped',
  'P6': 'napped',
  'T6': 'temperature',
  'T12': 'noise',
  'T7': 'exercise',
  'P2': 'early_workout',
  'T8': 'todo_list',
  'P3': 'dim_screen',
};

/// 星期一到星期日都要 = 0x7F（bit0 = 星期一，同 DateTime.weekday − 1）。
const int kEveryDay = 0x7F;

/// 使用者清單裡的一條。
@immutable
class PlanItem {
  /// 建議的 id，或 `custom_<時間戳>`。
  final String id;
  final String text;
  final PlanAnchor anchor;
  final int offsetMinutes;
  final bool notify;

  /// 哪幾天要做。bit0＝星期一 … bit6＝星期日。
  final int days;

  const PlanItem({
    required this.id,
    required this.text,
    required this.anchor,
    required this.offsetMinutes,
    this.notify = false,
    this.days = kEveryDay,
  });

  bool get isCustom => id.startsWith('custom_');

  factory PlanItem.fromSuggestion(PlanSuggestion s) => PlanItem(
        id: s.id,
        text: s.text,
        anchor: s.anchor,
        offsetMinutes: s.offsetMinutes,
      );

  PlanItem copyWith({String? text, PlanAnchor? anchor, int? offsetMinutes, bool? notify, int? days}) =>
      PlanItem(
        id: id,
        text: text ?? this.text,
        anchor: anchor ?? this.anchor,
        offsetMinutes: offsetMinutes ?? this.offsetMinutes,
        notify: notify ?? this.notify,
        days: days ?? this.days,
      );

  bool onWeekday(int weekday) => (days >> (weekday - 1)) & 1 == 1;

  IconData get icon => suggestionById(id)?.icon ?? Icons.star_rounded;

  Map<String, Object> toJson() => {
        'id': id,
        'text': text,
        'anchor': anchor.name,
        'offset': offsetMinutes,
        'notify': notify,
        'days': days,
      };

  static PlanItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], text = raw['text'], offset = raw['offset'];
    if (id is! String || text is! String || offset is! int) return null;
    final anchor = raw['anchor'] == 'wake' ? PlanAnchor.wake : PlanAnchor.bedtime;
    final days = raw['days'] is int ? raw['days'] as int : kEveryDay;
    return PlanItem(
      id: id,
      text: text,
      anchor: anchor,
      offsetMinutes: offset,
      notify: raw['notify'] == true,
      days: days & kEveryDay,
    );
  }
}

// ── 時間 ─────────────────────────────────────────────────────────────

int _minutesOf(TimeOfDay t) => t.hour * 60 + t.minute;

/// 一條習慣在「現在的作息」底下是幾點。
TimeOfDay itemTime(PlanItem item, {required TimeOfDay bedtime, required TimeOfDay wake}) {
  final base = _minutesOf(item.anchor == PlanAnchor.wake ? wake : bedtime);
  final m = ((base + item.offsetMinutes) % 1440 + 1440) % 1440;
  return TimeOfDay(hour: m ~/ 60, minute: m % 60);
}

/// 使用者在編輯頁挑了一個時刻 → 存成相對 anchor 的分鐘數，取 (−720, 720] 較短的那一段
/// （同 `behavior/adherence.py` 的正規化：23:30 對 00:30 是 −60，不是 +1380）。
int offsetFor(TimeOfDay picked, PlanAnchor anchor,
    {required TimeOfDay bedtime, required TimeOfDay wake}) {
  final base = _minutesOf(anchor == PlanAnchor.wake ? wake : bedtime);
  var d = (_minutesOf(picked) - base) % 1440;
  if (d > 720) d -= 1440;
  return d;
}

/// 「6h before bedtime」「at wake time」「30m after wake time」。
String relativeLabel(PlanItem item) {
  final which = item.anchor == PlanAnchor.wake ? 'wake time' : 'bedtime';
  final m = item.offsetMinutes;
  if (m == 0) return 'At $which';
  final a = m.abs();
  final span = a % 60 == 0 ? '${a ~/ 60}h' : (a < 60 ? '${a}m' : '${a ~/ 60}h ${a % 60}m');
  return m < 0 ? '$span before $which' : '$span after $which';
}

/// Plan 的「一天」從目標起床前 3 小時開始（使用者定，Q18）。
/// ⚠️ 3 小時是**設計決策**，沒有文獻。用午夜切的話，凌晨三點才睡的人
///    「今天」的清單會在他還沒睡時就換新。
const int kPlanDayLeadMinutes = 180;

/// [now] 屬於哪一個 Plan 日（回傳那一天的 00:00）。
DateTime planDayOf(DateTime now, TimeOfDay wake) {
  final shift = _minutesOf(wake) - kPlanDayLeadMinutes;
  final shifted = now.subtract(Duration(minutes: shift));
  return DateTime(shifted.year, shifted.month, shifted.day);
}

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 這一條下一次提醒的時刻（[now] 之後、落在要做的那幾天）。沒有任何一天要做 → null。
DateTime? nextReminderAt(PlanItem item, DateTime now,
    {required TimeOfDay bedtime, required TimeOfDay wake}) {
  if (item.days & kEveryDay == 0) return null;
  final t = itemTime(item, bedtime: bedtime, wake: wake);
  for (var i = 0; i <= 7; i++) {
    final d = DateTime(now.year, now.month, now.day + i, t.hour, t.minute);
    if (d.isAfter(now) && item.onWeekday(d.weekday)) return d;
  }
  return null;
}

// ── 狀態 ─────────────────────────────────────────────────────────────

/// 打勾的紀錄最多留幾天（連續天數只往回數這麼多）。
const int kCheckHistoryDays = 60;

/// 自訂習慣最多幾條（提醒的通道一條一個位置）。
const int kMaxPlanItems = 20;

/// 清單＋打勾紀錄。存在手機上（`sonnap/store`）。
class PlanStore extends ChangeNotifier {
  /// App 裡那一份（MainPage 建立時登記）。寵物 notes 的「Add to my plan」用它——
  /// notes 從首頁、早晨報告、Insights 三個地方打開，一路傳參數下去要改三個畫面。
  /// null＝沒有計畫（測試、或還沒建好），按鈕就不出現。
  static PlanStore? shared;

  /// ⚠️ 改這兩個字串＝把使用者的清單弄丟，而且不會有錯誤訊息。
  static const String itemsKey = 'plan_items_v1';
  static const String checksKey = 'plan_checks_v1';

  final KeyValueStore store;
  PlanStore(this.store);

  List<PlanItem> _items = const [];
  Map<String, Set<String>> _checks = {};
  bool _loaded = false;

  List<PlanItem> get items => List.unmodifiable(_items);
  bool get loaded => _loaded;

  Future<void> load() async {
    try {
      final rawItems = await store.getString(itemsKey);
      final rawChecks = await store.getString(checksKey);
      _items = _decodeItems(rawItems);
      _checks = _decodeChecks(rawChecks);
    } catch (e) {
      // 讀不到就當空清單——不讓壞掉的儲存擋住畫面（同 KeyValueStore 的紀律）
      debugPrint('PlanStore: load failed - $e');
    }
    _loaded = true;
    notifyListeners();
  }

  static List<PlanItem> _decodeItems(String? raw) {
    if (raw == null) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final seen = <String>{};
    return [
      for (final r in decoded)
        if (PlanItem.fromJson(r) case final item? when seen.add(item.id)) item,
    ];
  }

  static Map<String, Set<String>> _decodeChecks(String? raw) {
    if (raw == null) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    return {
      for (final e in decoded.entries)
        if (e.key is String && e.value is List)
          e.key as String: {for (final v in e.value as List) if (v is String) v},
    };
  }

  Future<void> _save() async {
    await store.setString(itemsKey, jsonEncode([for (final i in _items) i.toJson()]));
    await store.setString(
      checksKey,
      jsonEncode({for (final e in _checks.entries) e.key: e.value.toList()..sort()}),
    );
  }

  bool contains(String id) => _items.any((i) => i.id == id);

  /// 加一條。已經有了就不重複加，回 false。
  Future<bool> add(PlanItem item) async {
    if (contains(item.id) || _items.length >= kMaxPlanItems) return false;
    _items = [..._items, item];
    notifyListeners();
    await _save();
    return true;
  }

  Future<void> update(PlanItem item) async {
    _items = [for (final i in _items) i.id == item.id ? item : i];
    notifyListeners();
    await _save();
  }

  /// 拿掉一條。打勾紀錄一起清掉（同一個 id 之後再加回來要從 0 開始）。
  Future<void> remove(String id) async {
    _items = [for (final i in _items) if (i.id != id) i];
    for (final s in _checks.values) {
      s.remove(id);
    }
    notifyListeners();
    await _save();
  }

  bool isChecked(String id, DateTime planDay) => _checks[dayKey(planDay)]?.contains(id) ?? false;

  Future<void> setChecked(String id, DateTime planDay, bool on) async {
    final key = dayKey(planDay);
    final set = _checks.putIfAbsent(key, () => <String>{});
    on ? set.add(id) : set.remove(id);
    if (set.isEmpty) _checks.remove(key);
    _prune(planDay);
    notifyListeners();
    await _save();
  }

  void _prune(DateTime today) {
    final cutoff = dayKey(today.subtract(const Duration(days: kCheckHistoryDays)));
    _checks.removeWhere((k, _) => k.compareTo(cutoff) < 0);
  }

  /// 今天要做的（依星期幾）。
  List<PlanItem> dueOn(DateTime planDay) =>
      [for (final i in _items) if (i.onWeekday(planDay.weekday)) i];

  /// 連續做到幾個「要做的日子」。
  ///
  /// 今天還沒勾不算斷——從昨天往回數（今天還沒過完）。不用做的日子跳過、不算斷。
  int streak(String id, DateTime planDay) {
    final item = _items.where((i) => i.id == id).firstOrNull;
    if (item == null) return 0;
    var n = 0;
    var d = planDay;
    if (!isChecked(id, d)) d = d.subtract(const Duration(days: 1));
    for (var i = 0; i < kCheckHistoryDays; i++) {
      if (item.onWeekday(d.weekday)) {
        if (!isChecked(id, d)) break;
        n++;
      }
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }
}
