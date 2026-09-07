// 接近就寢時間時倒數要變紅。
//
// ═══════════════════════════════════════════════════════════════════
// 這裡最容易錯的不是門檻，是「剛過就寢時間」那一格
// ═══════════════════════════════════════════════════════════════════
//
// header_card 的 _getTimeLeftDuration() 回的永遠是**下一次**目標時刻。
// 所以目標 23:30 的人在 23:31 看到的倒數是 23 小時 59 分——數字本身沒錯，
// 但照直覺套「剩越多越放鬆」的規則，畫面會在他剛剛錯過的那一分鐘
// 顯示綠色的「還很充裕」，底下還寫著 "to bedtime"。
//
// ⚠️ 這些門檻是**呈現**用的，不是計分門檻。它們不進 final_score、
//    不進 total_modifier、不影響任何挑戰的達成判定，所以不受設計紅線 2
//    （每一項計分都要有文獻）約束。同一條界線見 TAPO_HANDOFF.md 的
//    「偵測門檻 ≠ 計分門檻」。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/widgets/bedtime_urgency.dart';
import 'package:app/widgets/header_card.dart';

void main() {
  const bedtime = TimeOfDay(hour: 23, minute: 30);

  DateTime at(int hour, int minute, {int day = 10}) =>
      DateTime(2026, 9, day, hour, minute);

  group('四種狀態', () {
    test('離很遠 → relaxed', () {
      expect(bedtimeUrgency(at(18, 0), bedtime), BedtimeUrgency.relaxed);
    });

    test('剩 90 分鐘內 → approaching', () {
      expect(bedtimeUrgency(at(22, 30), bedtime), BedtimeUrgency.approaching);
      expect(bedtimeUrgency(at(22, 1), bedtime), BedtimeUrgency.approaching);
    });

    test('剩 30 分鐘內 → imminent', () {
      expect(bedtimeUrgency(at(23, 0), bedtime), BedtimeUrgency.imminent);
      expect(bedtimeUrgency(at(23, 29), bedtime), BedtimeUrgency.imminent);
    });

    test('門檻剛好落在邊界上時算進去', () {
      // 剩正好 30 分鐘 → imminent（不是 approaching）
      expect(bedtimeUrgency(at(23, 0), bedtime), BedtimeUrgency.imminent);
      // 剩正好 90 分鐘 → approaching（不是 relaxed）
      expect(bedtimeUrgency(at(22, 0), bedtime), BedtimeUrgency.approaching);
    });
  });

  group('剛過就寢時間', () {
    test('過了一分鐘 → overdue，不是 relaxed', () {
      expect(
        bedtimeUrgency(at(23, 31), bedtime),
        BedtimeUrgency.overdue,
        reason: '倒數這時顯示 23 小時 59 分。照直覺看「剩很多」會判成 relaxed，'
            '等於在他剛剛錯過的那一分鐘恭喜他',
      );
    });

    test('過了 59 分鐘還是 overdue', () {
      expect(bedtimeUrgency(at(0, 29, day: 11), bedtime), BedtimeUrgency.overdue);
    });

    test('過了一小時就不再是 overdue', () {
      // ⚠️ 這時候已經沒有可以改變的行為了（下一個目標是明天），
      //    繼續紅著只剩下責備。
      expect(
        bedtimeUrgency(at(0, 31, day: 11), bedtime),
        BedtimeUrgency.relaxed,
      );
    });

    test('跨午夜的目標時間也對', () {
      const lateBedtime = TimeOfDay(hour: 1, minute: 0);
      // 01:01 → 剛過
      expect(bedtimeUrgency(at(1, 1), lateBedtime), BedtimeUrgency.overdue);
      // 00:45 → 還剩 15 分鐘
      expect(bedtimeUrgency(at(0, 45), lateBedtime), BedtimeUrgency.imminent);
      // 23:50（前一天晚上）→ 還剩 70 分鐘
      expect(bedtimeUrgency(at(23, 50), lateBedtime), BedtimeUrgency.approaching);
    });
  });

  group('真的接到 HeaderCard 上', () {
    // 純函式對了不代表畫面用了它——原本那四個顏色是編譯期常數，
    // 換掉函式而忘了接上去，這裡就會紅。
    //
    // ⚠️ HeaderCard 內部用 DateTime.now()，所以測試反過來做：
    //    把目標就寢時間訂在「現在之後 N 分鐘」，跨午夜也成立。

    Future<Color> countdownColor(WidgetTester tester, Duration fromNow) async {
      final target = DateTime.now().add(fromNow);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HeaderCard(
            username: 'Nathan',
            message: 'test',
            initialTargetBedtime:
                TimeOfDay(hour: target.hour, minute: target.minute),
          ),
        ),
      ));
      await tester.pump();

      // 倒數是唯一用 FittedBox 包起來的那個 Text（註解寫在 header_card 裡：
      // 字串變長時會撐破圓環，所以只有它需要縮放）。
      final text = tester.widget<Text>(
        find.descendant(
          of: find.byType(FittedBox),
          matching: find.byType(Text),
        ),
      );
      return text.style!.color!;
    }

    testWidgets('剩 10 分鐘 → 紅色', (tester) async {
      expect(
        await countdownColor(tester, const Duration(minutes: 10)),
        bedtimeUrgencyColor(BedtimeUrgency.imminent),
      );
    });

    testWidgets('剩 5 小時 → 不是紅色', (tester) async {
      final color = await countdownColor(tester, const Duration(hours: 5));
      expect(color, bedtimeUrgencyColor(BedtimeUrgency.relaxed));
      expect(color, isNot(bedtimeUrgencyColor(BedtimeUrgency.imminent)));
    });

    testWidgets('剩 1 小時 → 黃色', (tester) async {
      expect(
        await countdownColor(tester, const Duration(minutes: 60)),
        bedtimeUrgencyColor(BedtimeUrgency.approaching),
      );
    });
  });

  group('顏色與文案', () {
    test('越接近越紅，四種狀態不能全部同色', () {
      final colors = {
        for (final u in BedtimeUrgency.values) u: bedtimeUrgencyColor(u),
      };
      expect(
        colors[BedtimeUrgency.relaxed],
        isNot(colors[BedtimeUrgency.imminent]),
        reason: '原本四種情況全是同一個黃色（編譯期常數），那等於沒有提示',
      );
      expect(
        colors[BedtimeUrgency.approaching],
        isNot(colors[BedtimeUrgency.relaxed]),
      );
    });

    test('overdue 與 imminent 刻意同色', () {
      // 使用者要看的是「該去睡了」，不是「你遲到了幾分鐘」。
      expect(
        bedtimeUrgencyColor(BedtimeUrgency.overdue),
        bedtimeUrgencyColor(BedtimeUrgency.imminent),
      );
    });

    test('overdue 時不得寫 "to bedtime"', () {
      expect(
        bedtimeUrgencyCaption(BedtimeUrgency.overdue),
        'past bedtime',
        reason: '那時候倒數顯示的是「距離明天的目標還有 23 小時 59 分」，'
            '寫 to bedtime 就是在說「你還有 23 小時可以慢慢來」',
      );
      for (final u in BedtimeUrgency.values) {
        if (u == BedtimeUrgency.overdue) continue;
        expect(bedtimeUrgencyCaption(u), 'to bedtime');
      }
    });
  });
}
