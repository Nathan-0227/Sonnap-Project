// 首頁早晚版的切換規則（2026-11-12 使用者定案）。
//
// 守的是「現在幾點該顯示哪一版」這支純函式。畫錯版不會報錯，只會讓
// 凌晨兩點還醒著的人找不到 Start sleep，或下午看到大倒數。
import 'package:app/services/bed_marks.dart';
import 'package:app/services/bedtime_guard.dart';
import 'package:app/services/home_mode.dart';
import 'package:app/widgets/bedtime_urgency.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime at(int day, int h, [int m = 0]) => DateTime(2026, 11, day, h, m);

void main() {
  const t2330 = TimeOfDay(hour: 23, minute: 30);
  const t0100 = TimeOfDay(hour: 1, minute: 0);

  group('目標 23:30', () {
    final cases = {
      at(12, 14, 0): HomeMode.day, // 下午
      at(12, 21, 59): HomeMode.day,
      at(12, 22, 0): HomeMode.evening, // 前 90 分鐘，倒數剛變黃
      at(12, 23, 30): HomeMode.evening,
      at(13, 0, 29): HomeMode.evening, // 過了 59 分，倒數還是紅的
      at(13, 0, 30): HomeMode.lateEvening, // 過了 60 分，不再紅
      at(13, 2, 0): HomeMode.lateEvening, // 凌晨兩點還沒睡
      at(13, 5, 29): HomeMode.lateEvening,
      at(13, 5, 30): HomeMode.day, // 目標後 6 小時，回到白天版
      at(13, 9, 0): HomeMode.day,
    };
    cases.forEach((now, expected) {
      test('$now → $expected', () {
        expect(homeModeFor(now: now, bedtime: t2330), expected);
      });
    });
  });

  group('目標跨午夜 01:00', () {
    test('前一晚 23:30 已經是晚上版（屬於明天 01:00 那一次）', () {
      expect(homeModeFor(now: at(12, 23, 30), bedtime: t0100), HomeMode.evening);
    });
    test('23:29 還是白天版', () {
      expect(homeModeFor(now: at(12, 23, 29), bedtime: t0100), HomeMode.day);
    });
    test('03:00 是晚上版的後段', () {
      expect(homeModeFor(now: at(13, 3, 0), bedtime: t0100),
          HomeMode.lateEvening);
    });
    test('18:00 是白天版（不能被「前一天那一次」誤判）', () {
      expect(homeModeFor(now: at(13, 18, 0), bedtime: t0100), HomeMode.day);
    });
  });

  group('按了開始睡覺', () {
    test('還沒按下床 → 不管幾點都是睡覺畫面', () {
      final marks = BedMarks(startAt: at(12, 23, 41));
      expect(homeModeFor(now: at(13, 0, 12), bedtime: t2330, marks: marks),
          HomeMode.sleeping);
      // 早上 9 點還沒按下床：仍然是睡覺畫面（Out of bed 就在上面）
      expect(homeModeFor(now: at(13, 9, 0), bedtime: t2330, marks: marks),
          HomeMode.sleeping);
    });

    test('滿 14 小時 → 退回一般首頁（不要隔天下午還在睡覺畫面）', () {
      final marks = BedMarks(startAt: at(12, 23, 41));
      expect(homeModeFor(now: at(13, 13, 40), bedtime: t2330, marks: marks),
          HomeMode.sleeping);
      expect(homeModeFor(now: at(13, 13, 41), bedtime: t2330, marks: marks),
          HomeMode.day);
    });

    test('按了下床 → 照時間走', () {
      final marks = BedMarks(startAt: at(12, 23, 41), endAt: at(13, 7, 10));
      expect(homeModeFor(now: at(13, 8, 0), bedtime: t2330, marks: marks),
          HomeMode.day);
    });

    test('開始時刻在未來（時鐘被調過）→ 不卡在睡覺畫面', () {
      final marks = BedMarks(startAt: at(13, 1, 0));
      expect(homeModeFor(now: at(12, 14, 0), bedtime: t2330, marks: marks),
          HomeMode.day);
    });
  });

  test('三個時間沿用既有常數（改了其中一邊要一起改）', () {
    expect(kEveningLeadIn, kApproachingThreshold);
    expect(kEveningTail, kGuardTail);
  });
}
