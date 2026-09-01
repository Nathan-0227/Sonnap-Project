// lights_out_at 的偵測——把手機互動事件還原成「幾點放下手機」。
//
// 這一組守的是**兩個安靜地壞掉的機制**：
//
//   1. 只看 ACTIVITY_PAUSED 會把「連續看兩小時 YouTube」誤判成安靜。
//      連續使用同一個 App 期間一個事件都不會產生，所以事件流上那段是空的。
//      壞掉的話不會報錯，只會給出一個早了兩小時的就寢時刻。
//
//   2. 視窗開頭到第一筆事件之間也是空的，但那是「更早的事我們沒查」，
//      不是「他放下了手機」。把它算成安靜期的話，剛授權完的第一次查詢
//      就會憑空生出一個就寢時刻——而且看起來完全正常。
//
// ⚠️ 這裡沒有一條測試在驗「距離目標就寢差幾分鐘」。那是後端
// behavior/adherence.py 的事（跨午夜正規化寫在那裡），Dart 不該有第二份。

import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/lights_out.dart';

/// 那一晚的基準日，讓每個時刻讀起來就是牆上的鐘。
final DateTime day = DateTime(2026, 9, 1);

InteractionEvent at(int hour, int minute, String type, {int dayOffset = 0}) {
  return InteractionEvent(
    timestamp: day.add(Duration(days: dayOffset, hours: hour, minutes: minute)),
    type: type,
    packageName: 'com.example.test',
  );
}

LightsOutResult run(
  List<InteractionEvent> events, {
  DateTime? start,
  DateTime? end,
  int minQuiet = kMinQuietMinutes,
}) {
  return detectLightsOut(
    events,
    windowStart: start ?? day.add(const Duration(hours: 12)),
    windowEnd: end ?? day.add(const Duration(days: 1, hours: 12)),
    minQuietMinutes: minQuiet,
  );
}

void main() {
  group('正常的一晚', () {
    test('最後一次 paused 之後的長安靜期 → 那就是就寢時刻', () {
      final result = run([
        at(20, 0, 'resumed'),
        at(20, 30, 'paused'),
        at(22, 45, 'resumed'),
        at(23, 12, 'paused'), // ← 放下手機
        at(7, 40, 'resumed', dayOffset: 1), // 隔天早上第一次拿起來
        at(8, 5, 'paused', dayOffset: 1),
      ]);

      expect(result.status, LightsOutStatus.ok);
      expect(result.at, day.add(const Duration(hours: 23, minutes: 12)));
      expect(result.quietMinutes, 8 * 60 + 28);
      expect(result.sourceType, 'paused');
    });

    test('screen_off 與 keyguard_shown 也算「停止使用」', () {
      // 這兩種事件比 paused 更貼近「放下手機」，但不是每支手機都給得到。
      // 給得到的時候要用得上。
      final result = run([
        at(22, 0, 'resumed'),
        at(23, 30, 'screen_off'),
        at(7, 0, 'screen_on', dayOffset: 1),
        at(7, 30, 'paused', dayOffset: 1),
      ]);

      expect(result.status, LightsOutStatus.ok);
      expect(result.at, day.add(const Duration(hours: 23, minutes: 30)));
      expect(result.sourceType, 'screen_off');
    });
  });

  group('⚠️ 連續使用同一個 App 不可以被當成安靜', () {
    // 熬夜追劇的一晚：22:00 打開影片看到 04:00，睡到 08:30。
    //
    // 這一組刻意讓**使用時間（6 小時）比睡眠（4.5 小時）還長**。
    // 只有這樣，「有沒有讀 resumed」才會給出不同的答案——
    // 兩段都選最長的空隙，而拿掉 resumed 之後最長的那一段就換人了。
    final night = [
      at(21, 55, 'paused'), // 切出上一個 App
      at(22, 0, 'resumed'), // 打開影片
      // …看了六小時，中間一個事件都沒有…
      at(4, 0, 'paused', dayOffset: 1), // 螢幕關掉，這才是就寢時刻
      at(8, 30, 'resumed', dayOffset: 1), // 早上拿起手機
      at(9, 0, 'paused', dayOffset: 1),
    ];

    // 視窗結尾貼著早上那次使用。不這樣的話「最後一次放下 → 視窗結尾」
    // 會變成最長的空隙，兩條測試就都被那一段主導、分不出差別。
    final windowEnd = day.add(const Duration(days: 1, hours: 10));

    test('就寢時刻是 04:00，不是 21:55', () {
      final result = run(night, end: windowEnd);

      expect(result.status, LightsOutStatus.ok);
      expect(
        result.at,
        day.add(const Duration(days: 1, hours: 4)),
        reason: '選到 21:55 就表示 22:00 的 resumed 沒有被算成「使用中」，'
            '那六小時被誤判成安靜期',
      );
      expect(result.quietMinutes, 4 * 60 + 30);
    });

    test('把 resumed 濾掉，答案就會錯成 21:55（反向對照）', () {
      // 沒有這一條的話，上一條有可能因為別的原因通過。
      // 這裡拿同一組事件、只濾掉 resumed，證明那些事件真的被讀了。
      final result = run(
        night.where((e) => e.type != 'resumed').toList(),
        end: windowEnd,
      );

      expect(result.status, LightsOutStatus.ok);
      expect(
        result.at,
        day.add(const Duration(hours: 21, minutes: 55)),
        reason: '反向對照失效了——若這裡也答對，表示上一條測的不是 resumed',
      );
    });
  });

  group('⚠️ 視窗開頭的空白不是安靜期', () {
    test('第一筆事件在視窗開始 10 小時後，不可以回報就寢時刻', () {
      // 剛授權完只會拿到很短一段事件。若把「視窗開始→第一筆事件」
      // 算成安靜期，這裡就會回一個 12:00 的「就寢時刻」。
      final result = run([
        at(22, 0, 'resumed'),
        at(22, 30, 'paused'),
        at(23, 0, 'resumed'),
        at(23, 20, 'paused'),
        at(0, 30, 'resumed', dayOffset: 1),
        at(0, 50, 'paused', dayOffset: 1),
      ], end: day.add(const Duration(days: 1, hours: 2)));

      expect(
        result.status,
        LightsOutStatus.noQuietGap,
        reason: '回報了 ${result.at}——那是視窗開頭的空白被當成了安靜期',
      );
    });
  });

  group('回報不出來的時候要說不知道', () {
    test('完全沒有事件 → noEvents', () {
      expect(run(const []).status, LightsOutStatus.noEvents);
    });

    test('整天每兩小時就碰一次手機 → noQuietGap，不是硬挑一個', () {
      final events = <InteractionEvent>[];
      for (var h = 0; h < 24; h += 2) {
        events.add(at(h, 0, 'resumed', dayOffset: h < 12 ? 1 : 0));
        events.add(at(h, 20, 'paused', dayOffset: h < 12 ? 1 : 0));
      }

      final result = run(events);
      expect(result.status, LightsOutStatus.noQuietGap);
      expect(result.at, isNull);
      expect(
        result.quietMinutes,
        lessThan(kMinQuietMinutes),
        reason: '要能講出「最長也才 ${result.quietMinutes} 分鐘」，'
            '不然使用者不知道差多少',
      );
    });

    test('不認得的事件型別直接忽略，不會被當成互動', () {
      final result = run([
        at(22, 0, 'resumed'),
        at(22, 30, 'paused'),
        at(2, 0, 'device_shutdown', dayOffset: 1), // 不在 start/end 兩組裡
        at(8, 0, 'resumed', dayOffset: 1),
      ]);

      expect(result.status, LightsOutStatus.ok);
      expect(
        result.at,
        day.add(const Duration(hours: 22, minutes: 30)),
        reason: '02:00 那筆若被算成互動，安靜期會被切成兩段 3.5 小時，'
            '就寢時刻會變成 02:00',
      );
      expect(result.eventCount, 3);
    });
  });

  group('邊界', () {
    test('視窗外的事件不算', () {
      final result = run(
        [
          at(6, 0, 'paused'), // 視窗（12:00 起）之前
          at(22, 0, 'resumed'),
          at(22, 30, 'paused'),
          at(9, 0, 'resumed', dayOffset: 1),
        ],
      );

      expect(result.eventCount, 3);
      expect(result.at, day.add(const Duration(hours: 22, minutes: 30)));
    });

    test('最後還開著的 App 算到視窗結尾為止，不會變成安靜期', () {
      // 最後一筆是 resumed 沒有配對的 paused（人正在用手機看這個畫面）。
      // 那段是「使用中」，不是「安靜」。
      final result = run([
        at(22, 0, 'resumed'),
        at(22, 30, 'paused'),
        at(23, 0, 'resumed'), // 之後沒有 paused
      ]);

      expect(
        result.status,
        LightsOutStatus.noQuietGap,
        reason: '若把 23:00 之後當成安靜，會回報一個 23:00 的就寢時刻——'
            '但那段其實是他還在用手機',
      );
    });

    test('剛好等於門檻要算數（>= 不是 >）', () {
      final result = run(
        [
          at(23, 0, 'resumed'),
          at(23, 30, 'paused'),
          at(2, 30, 'resumed', dayOffset: 1), // 整整 180 分鐘
          at(3, 0, 'paused', dayOffset: 1),
          at(4, 0, 'resumed', dayOffset: 1),
        ],
        end: day.add(const Duration(days: 1, hours: 5)),
      );

      expect(result.status, LightsOutStatus.ok);
      expect(result.quietMinutes, kMinQuietMinutes);
    });
  });

  group('送給後端的格式', () {
    test('iso8601 帶時區位移，不是 UTC', () {
      // ⚠️ behavior/adherence.py 拿牆鐘時間跟 "23:30" 這種本地目標比。
      // 送 UTC 過去，就寢時刻會整整差掉一個時區——那正是
      // wall_clock.dart 當初修掉的同一類 bug。
      final result = run([
        at(22, 0, 'resumed'),
        at(23, 12, 'paused'),
        at(8, 0, 'resumed', dayOffset: 1),
      ]);

      final iso = result.iso8601!;
      expect(iso, startsWith('2026-09-01T23:12'));
      expect(
        iso.endsWith('Z'),
        isFalse,
        reason: '結尾是 Z 代表送出去的是 UTC，後端會算錯就寢達成度',
      );
    });

    test('沒偵測到的時候 iso8601 是 null，不是某個預設時刻', () {
      // 「沒量到」與「準時」是兩件事——後端 main.py 對空的 lights_out_at
      // 明確回 400 而不是當成準時，Dart 這邊也不可以自己填一個。
      expect(run(const []).iso8601, isNull);
    });
  });
}
