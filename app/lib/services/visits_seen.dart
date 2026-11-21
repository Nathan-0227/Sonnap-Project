import 'friends_service.dart';
import 'key_value_store.dart';

/// 小鎮愛心上的數字＝今天收到、**還沒看過**的那幾則（2026-11-22 Q12，同寵物 notes 的紅點）。
/// 打開「Stopped by today」就全部算看過。只存在手機上，一天一個鍵（舊的天數用不到，留著也只有幾個字）。
class VisitsSeenStore {
  final KeyValueStore store;
  const VisitsSeenStore(this.store);

  static String _key(String day) => 'town_visits_seen_$day';

  Future<Set<String>> seen(String day) async {
    try {
      final raw = await store.getString(_key(day));
      if (raw == null || raw.isEmpty) return {};
      return raw.split('\n').toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> markSeen(String day, Iterable<TownVisit> visits) async {
    try {
      final all = {...await seen(day), for (final v in visits) v.seenKey(day)};
      await store.setString(_key(day), all.join('\n'));
    } catch (_) {
      // 記不住就下次再亮一次，不影響看內容
    }
  }
}

/// 還沒看過的幾則。
int unseenVisits(TownState town, Set<String> seen) =>
    town.visits.where((v) => !seen.contains(v.seenKey(town.day))).length;
