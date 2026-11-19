import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/camera_insights.dart';

/// 攝影機每晚資料的解析（`CameraNight.fromJson`、`nightOn`）。
///
/// 2026-11-19 Insights 改版拿掉了舊的攝影機卡，畫面那一半的測試跟著刪掉；
/// 片段與「跟你平常比」在畫面上的規則改由早晨報告的 Movement 詳細頁守。
/// 這裡留的是資料層：相對網址接上 baseUrl、clips 欄位有沒有、usual 解析、
/// 點了某一晚卻沒有那晚的錄影時**不退回最近一晚**。

/// 09-11：潛伏期高於下限，有數字（實測 13.5 分）。
const _aboveFloor = CameraNight(
  date: '2026-09-11',
  bedStartAt: '2026-09-11T01:36:07',
  bedEndAt: '2026-09-11T07:11:22',
  timeInBedMinutes: 335.3,
  sleepOnsetAt: '2026-09-11T01:49:37',
  sleepOnsetLatencyMinutes: 13.5,
  belowFloor: false,
  floorMinutes: 10,
  eventsPerHour: 15.9,
  bedTimesProvenance: 'SELF_REPORTED_recording_start_stop',
  sleepOnsetProvenance: 'DETECTED_motion_density__n2_unvalidated',
);

/// 09-12：潛伏期低於下限 → 後端給 null + floor，**不是 0**。
const _belowFloor = CameraNight(
  date: '2026-09-12',
  bedStartAt: '2026-09-12T01:18:01',
  bedEndAt: '2026-09-12T11:29:28',
  timeInBedMinutes: 611.5,
  sleepOnsetAt: null,
  sleepOnsetLatencyMinutes: null,
  belowFloor: true,
  floorMinutes: 10,
  eventsPerHour: 11.7,
  bedTimesProvenance: 'SELF_REPORTED_recording_start_stop',
  sleepOnsetProvenance: 'DETECTED_motion_density__n2_unvalidated',
);

void main() {





  // ──────────────────────────────────────────────────────────────
  // 動作片段（2026-11-07）。四件壞掉時不會報錯的事：
  //   1. 標籤與「沒有片段的原因」要**照抄後端**（camera_clips.py 是唯一定義處）
  //   2. 網址要接上 baseUrl，而且不能出現 `//`
  //   3. 舊版後端（沒有 clips 欄位）整段不出現，不是說「沒有片段」
  //   4. 指定某一晚卻沒有那晚時回 null，**不偷偷換成最近一晚**
  // ──────────────────────────────────────────────────────────────
  group('動作片段', () {
    // 哨兵字串：Dart 裡任何地方都不會自己寫出這兩句，畫面上出現就證明是照抄的。
    const sentinelLabel = '02:41 · moved for 6 s [from backend 7Q]';
    const sentinelNote = 'Sentinel note from camera_clips.py 9X';





    test('fromJson：相對網址接上 baseUrl，不出現 //', () {
      final night = CameraNight.fromJson({
        'date': '2026-09-13',
        'clips': [
          {'url': '/camera/clips/abc.gif', 'label': sentinelLabel},
        ],
        'clips_note': null,
      }, baseUrl: 'http://10.0.0.5:8000/');
      expect(night.clips.single.url, 'http://10.0.0.5:8000/camera/clips/abc.gif');
      expect(night.clips.single.label, sentinelLabel);
      expect(night.clipsSupported, isTrue);
    });

    test('fromJson：有 clips 欄位但是空的 → 仍算支援，原因照抄', () {
      final night = CameraNight.fromJson({
        'date': '2026-09-13',
        'clips': <dynamic>[],
        'clips_note': sentinelNote,
      });
      expect(night.clipsSupported, isTrue);
      expect(night.clips, isEmpty);
      expect(night.clipsNote, sentinelNote);
    });

    test('nightOn：沒有那一晚就回 null，不退回最近一晚', () {
      const result = CameraInsightsResult(
        CameraInsightsStatus.ok,
        nights: [_aboveFloor, _belowFloor],
      );
      expect(result.nightOn('2026-09-11')?.date, '2026-09-11');
      expect(result.nightOn('2026-01-01'), isNull,
          reason: '換成最近一晚的話，使用者會以為看到的是自己點的那晚');
      expect(result.latest?.date, '2026-09-12');
    });
  });

  // ⚠️ 這一組守的是「跟你平常比」那句話。四個會安靜說謊的地方：
  //    ① 那句話在 Dart 重寫一份 → 兩邊漂移不會報錯
  //    ② 在 Dart 自己算百分比 → 第二份判準，後端改門檻時畫面不跟著變
  //    ③ 基線不足時畫成 0% 或空白 → 0% 會被讀成「跟平常一模一樣」
  //    ④ 舊版後端沒有 usual 時自己編話 → 講的是「沒差別」而真相是「算不出」
  group('跟你平常比', () {
    // 哨兵字串：Dart 任何地方都不會自己寫出這句，畫面上出現就證明是照抄的。
    const sentinel = '27% less movement than usual [from camera_usual.py 4K]';






    test('fromJson：usual 解析得出來；沒有那個欄位時 supported 是 false', () {
      final withIt = CameraNight.fromJson({
        'date': '2026-11-07',
        'events_per_hour': 15.7,
        'usual': {
          'label': sentinel,
          'usual_events_per_hour': 21.4,
          'delta_pct': -26.6,
          'baseline_nights': 7,
          'basis': 'within_person__median_of_recent_nights',
        },
      });
      expect(withIt.usualSupported, isTrue);
      expect(withIt.usualLabel, sentinel);
      expect(withIt.usualEventsPerHour, 21.4);
      expect(withIt.usualDeltaPct, -26.6);
      expect(withIt.usualBaselineNights, 7);

      final without = CameraNight.fromJson({'date': '2026-11-07'});
      expect(without.usualSupported, isFalse);
      expect(without.usualLabel, isNull);
    });
  });
}
