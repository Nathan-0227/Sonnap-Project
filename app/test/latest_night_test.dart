// 首頁、助理頁、計畫頁的「最近一晚」（2026-11-22 使用者 grill 定，甲-2）。
//
// 守的東西（每一條都放回錯誤驗證過會紅）：
//   1. 讀今天那一晚；沒資料退回前一晚、只退一晚
//   2. /home 那一晚比打包檔新 → 寵物心情、分數、歷史最後一格都換成它；更早的晚上不動
//   3. 比打包檔舊 → 不倒退；同一晚 → 換掉不重複
//   4. 效率是進分數的那一個（按鈕的晚上用按鈕那一種）
//   5. 等不到、連不到、沒後端 → 打包檔；三頁共用一次讀取；refresh 會重讀並通知


import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/sleep_session.dart';
import 'package:app/services/latest_night.dart';
import 'package:app/services/sleep_repository.dart';

Map<String, dynamic> _hist(String date, String mood, double score, double hours) => {
      'date': date,
      'final_score': score,
      'final_quality': 'Good',
      'sleep_duration_hours': hours,
      'pet_mood': mood,
    };

/// 打包檔：最後一晚 11-21（happy、82 分）
SleepSession _payload() => SleepSession.fromJson({
      'schema_version': 2,
      'session_id': '20261121_001',
      'status': {'pet_mood': 'happy'},
      'metrics': {'sleep_duration_minutes': 420},
      'scoring': {'final_score': 82.0, 'final_quality': 'Good'},
      'history': [
        _hist('2026-11-19', 'bored', 75, 6.5),
        _hist('2026-11-20', 'bored', 78, 5.3),
        _hist('2026-11-21', 'happy', 82, 7.0),
      ],
      'activity': {'date': '2026-11-20', 'steps': 5000},
    });

/// /home 那一晚：手錶 63 分 Poor、手錶決定 tired
Map<String, dynamic> _home(String date, {double? score = 62.9, String mood = 'tired', String? lightsOut}) => {
      'date': date,
      'status': {'pet_mood': mood, 'mood_reason': 'final_quality=Poor', 'mood_driver': 'wearable'},
      'scoring': {
        'final_score': score,
        'final_quality': score == null ? null : 'Poor',
        'composition': {'efficiency_basis': 'watch_tst__watch_onset_to_wake', 'efficiency_label': 'Watch only'},
      },
      'metrics': {'sleep_duration_minutes': 197.0, 'sleep_efficiency': 98.01, 'deep_minutes': 31.0},
      'behavior': {'lights_out_at': lightsOut},
      'yesterday': {'date': '2026-11-21', 'steps': 112},
    };

class _Payload implements SleepRepository {
  @override
  Future<SleepSession> load() async => _payload();
}

void main() {
  final now = DateTime(2026, 11, 22, 13, 0);

  group('讀哪一晚', () {
    test('今天有資料 → 今天', () async {
      final asked = <String>[];
      final got = await fetchLatestNight((d) async {
        asked.add(d);
        return _home(d);
      }, now);
      expect(got?['date'], '2026-11-22');
      expect(asked, ['2026-11-22']);
    });

    test('今天沒資料 → 前一晚；只退一晚（不問 11-20）', () async {
      final asked = <String>[];
      final got = await fetchLatestNight((d) async {
        asked.add(d);
        return d == '2026-11-22' ? _home(d, score: null) : (d == '2026-11-21' ? _home(d) : _home(d));
      }, now);
      expect(got?['date'], '2026-11-21');
      final none = <String>[];
      expect(await fetchLatestNight((d) async {
        none.add(d);
        return _home(d, score: null);
      }, now), isNull);
      expect(none, ['2026-11-22', '2026-11-21']);
    });

    test('只有放下手機（手錶還沒到）也算有資料', () {
      expect(homeHasNight(_home('2026-11-22', score: null, lightsOut: '2026-11-22T01:00:00+08:00')), isTrue);
      expect(homeHasNight(_home('2026-11-22', score: null)), isFalse);
    });
  });

  group('蓋到打包檔上', () {
    test('/home 比打包檔新 → 心情、分數、歷史最後一格都是它；更早的晚上不動', () {
      final s = mergeLatestNight(_payload(), _home('2026-11-22'));
      expect(s.status.petMood, 'tired');
      expect(s.scoring.finalScore, 62.9);
      expect(s.history.map((e) => e.date), ['2026-11-19', '2026-11-20', '2026-11-21', '2026-11-22']);
      expect(s.history.last.petMood, 'tired', reason: '一週心情列最後一格＝寵物');
      expect(s.history[s.history.length - 2].finalScore, 82, reason: '「跟上一晚比」比的是打包檔那一晚');
      expect(s.history.last.sleepDurationHours, closeTo(197 / 60, 1e-9));
      expect(s.activity?.date, '2026-11-21', reason: 'Activity 用 /home 的 yesterday');
    });

    test('比打包檔舊 → 原樣（不倒退）', () {
      final base = _payload();
      expect(identical(mergeLatestNight(base, _home('2026-11-20')), base), isTrue);
    });

    test('同一晚 → 換掉那一格、不重複', () {
      final s = mergeLatestNight(_payload(), _home('2026-11-21'));
      expect(s.history.map((e) => e.date), ['2026-11-19', '2026-11-20', '2026-11-21']);
      expect(s.history.last.petMood, 'tired');
    });

    test('效率是進分數的那一個：沒按按鈕＝手錶的', () {
      final s = mergeLatestNight(_payload(), _home('2026-11-22'));
      expect(s.metrics.scoredEfficiency, 98.01);
      expect(s.metrics.scoredEfficiencyLabel, 'Watch only');
    });

    test('效率：按了按鈕的晚上用按鈕那一種（basis 對得上 behavior）', () {
      final h = _home('2026-11-22');
      (h['scoring'] as Map)['composition'] = {'efficiency_basis': 'watch_tst__phone_tats', 'efficiency_label': 'Sleep button'};
      h['behavior'] = {'measured_efficiency': 88.4, 'measured_efficiency_basis': 'watch_tst__phone_tats'};
      final s = mergeLatestNight(_payload(), h);
      expect(s.metrics.scoredEfficiency, 88.4);
      expect(s.history.last.scoredEfficiencyBasis, 'watch_tst__phone_tats');
    });
  });

  group('三頁共用的那一層', () {
    test('/home 回來 → 合併後的那一份', () async {
      final repo = LatestNightRepository(base: _Payload(), fetchNight: (d) async => _home(d), clock: () => now);
      expect((await repo.load()).status.petMood, 'tired');
    });

    test('等不到（超過等待時間）→ 打包檔', () async {
      final repo = LatestNightRepository(
          base: _Payload(),
          wait: const Duration(milliseconds: 50),
          fetchNight: (d) async {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            return _home(d);
          },
          clock: () => now);
      expect((await repo.load()).status.petMood, 'happy');
    });

    test('連不到（丟錯）或沒後端（null）→ 打包檔', () async {
      final err = LatestNightRepository(
          base: _Payload(), fetchNight: (d) async => throw Exception('down'), clock: () => now);
      expect((await err.load()).status.petMood, 'happy');
      final none = LatestNightRepository(base: _Payload(), fetchNight: (d) async => null, clock: () => now);
      expect((await none.load()).status.petMood, 'happy');
    });

    test('三頁共用一次讀取；refresh 重讀並通知', () async {
      var calls = 0;
      final repo = LatestNightRepository(
          base: _Payload(),
          fetchNight: (d) async {
            calls++;
            return _home(d);
          },
          clock: () => now);
      await Future.wait([repo.load(), repo.load(), repo.load()]);
      expect(calls, 1);
      var notified = 0;
      repo.addListener(() => notified++);
      repo.refresh();
      await repo.load();
      expect(calls, 2);
      expect(notified, 1);
    });
  });
}
