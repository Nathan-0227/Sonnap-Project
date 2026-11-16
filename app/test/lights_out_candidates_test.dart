import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/lights_out.dart';

/// 守「候選安靜期」這一層（2026-11-16）。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 用的是 11-16 的**真實事件流**
/// ═══════════════════════════════════════════════════════════════════
/// `test/fixtures/lights_out_20261116.txt` 是從實機 `adb shell dumpsys
/// usagestats` 抓下來的 294 筆事件（已去掉 App 名稱）。手機只保留約
/// 24 小時，所以那一份是唯一的證據——其餘五個同型的夜晚救不回來。
///
/// 那一晚手機挑了 **02:23**（安靜 218 分鐘，最長），真正的就寢時刻是
/// **00:49**（安靜 88 分鐘）。手錶認定 00:56 入睡——放下手機不可能發生在
/// 睡著之後 87 分鐘。手機身上沒有裁判，所以它要把兩段都送上去。
///
/// ⚠️ 這支測試**不驗「挑對了」**（那是後端的事，見
/// `tests/test_lights_out_resolve.py`），只驗「兩段都有送出去」。
void main() {
  List<InteractionEvent> loadFixture() {
    const typeMap = {
      'SCREEN_INTERACTIVE': 'screen_on',
      'SCREEN_NON_INTERACTIVE': 'screen_off',
      'KEYGUARD_HIDDEN': 'keyguard_hidden',
      'KEYGUARD_SHOWN': 'keyguard_shown',
    };
    final lines = File('test/fixtures/lights_out_20261116.txt').readAsLinesSync();
    final events = <InteractionEvent>[];
    for (final line in lines) {
      if (line.startsWith('#') || line.trim().isEmpty) continue;
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 3) continue;
      final type = typeMap[parts[2]];
      if (type == null) continue;
      events.add(InteractionEvent(
        timestamp: DateTime.parse('${parts[0]} ${parts[1]}'),
        type: type,
      ));
    }
    return events;
  }

  LightsOutResult detect() {
    final events = loadFixture();
    return detectLightsOut(
      events,
      windowStart: events.first.timestamp,
      // 視窗結尾＝早上開 App 的那一刻（實機是 08:38 抓的）。
      windowEnd: DateTime.parse('2026-11-16 08:38:00'),
    );
  }

  group('11-16 真實事件流', () {
    test('事件讀得進來（反向對照：檔案壞掉的話下面幾條會假性通過）', () {
      expect(loadFixture().length, greaterThan(250));
    });

    test('手機照舊挑 02:23——這一輪**不改**手機端的挑選規則', () {
      final r = detect();
      expect(r.status, LightsOutStatus.ok);
      expect(r.at, DateTime.parse('2026-11-16 02:23:37'));
    });

    test('⚠️ 真正那一段 00:49 必須在候選裡，不然後端沒東西可挑', () {
      final r = detect();
      final times = r.candidates.map((c) => c.at).toList();
      expect(times, contains(DateTime.parse('2026-11-16 00:49:54')),
          reason: '00:49 那段安靜 88 分鐘，≥ kCandidateMinMinutes(60) 就該附上去');
    });

    test('手機自己挑的那一段**一定也在**候選裡（後端挑不到更好的要退回它）', () {
      final r = detect();
      expect(r.candidates.map((c) => c.at), contains(r.at));
    });

    test('候選依時間排序、每段都 ≥ 60 分鐘、不超過 10 段', () {
      final r = detect();
      expect(r.candidates.length, lessThanOrEqualTo(kMaxCandidates));
      for (final c in r.candidates) {
        expect(c.quietMinutes, greaterThanOrEqualTo(kCandidateMinMinutes));
      }
      for (var i = 0; i + 1 < r.candidates.length; i++) {
        expect(r.candidates[i].at.isBefore(r.candidates[i + 1].at), isTrue);
      }
    });

    test('那兩段的長度就是 88 與 218 分鐘', () {
      final r = detect();
      final byTime = {for (final c in r.candidates) c.at: c.quietMinutes};
      expect(byTime[DateTime.parse('2026-11-16 00:49:54')], 88);
      expect(byTime[DateTime.parse('2026-11-16 02:23:37')], 218);
    });

    test('toJson 的鍵名與後端收的欄位一致', () {
      final json = detect().candidates.first.toJson();
      expect(json.keys.toSet(),
          {'at', 'quiet_minutes', 'source_type', 'bridged_unlocks'});
      // ⚠️ 不可以是 UTC——後端 night_date() 與達成度都拿牆鐘時間比，
      //    送 UTC 過去就寢時刻會整整差一個時區。
      expect(json['at'], isNot(contains('Z')));
    });
  });

  group('候選的規則', () {
    List<InteractionEvent> use(String from, String to) => [
          InteractionEvent(
              timestamp: DateTime.parse(from), type: 'keyguard_hidden'),
          InteractionEvent(
              timestamp: DateTime.parse(to), type: 'keyguard_shown'),
        ];

    test('< 60 分鐘的空隙不算候選（邊界）', () {
      final events = [
        ...use('2026-11-16 22:00:00', '2026-11-16 22:10:00'),
        // 59 分鐘的空隙
        ...use('2026-11-16 23:09:00', '2026-11-16 23:20:00'),
        // 61 分鐘的空隙
        ...use('2026-11-17 00:21:00', '2026-11-17 00:30:00'),
      ];
      final r = detectLightsOut(events,
          windowStart: DateTime.parse('2026-11-16 20:00:00'),
          windowEnd: DateTime.parse('2026-11-17 08:00:00'));
      expect(r.candidates.length, 1);
      expect(r.candidates.single.quietMinutes, 61);
    });

    test('偵測不到的夜晚**照樣附候選**（後端刷掉之後可能剩對的那段）', () {
      final events = [
        ...use('2026-11-16 22:00:00', '2026-11-16 22:10:00'),
        ...use('2026-11-17 00:20:00', '2026-11-17 00:30:00'), // 130 分鐘
        ...use('2026-11-17 02:40:00', '2026-11-17 02:50:00'), // 130 分鐘
      ];
      final r = detectLightsOut(events,
          windowStart: DateTime.parse('2026-11-16 20:00:00'),
          windowEnd: DateTime.parse('2026-11-17 08:00:00'));
      expect(r.status, LightsOutStatus.noQuietGap,
          reason: '兩段都不到 3 小時');
      expect(r.candidates.length, 2);
    });

    test('沒有事件時候選是空的，不是憑空生出來', () {
      final r = detectLightsOut(const [],
          windowStart: DateTime.parse('2026-11-16 20:00:00'),
          windowEnd: DateTime.parse('2026-11-17 08:00:00'));
      expect(r.candidates, isEmpty);
    });
  });
}
