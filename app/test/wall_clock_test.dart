// 時區解析的回歸測試。
//
// 這支守的是一個**看得到但不會報錯**的 bug：payload 的時間帶 +08:00，
// 用 DateTime.tryParse 讀出來的 .hour 是 UTC 時，畫面上每一個就寢時間
// 都會早 8 小時。實際發生過兩處（Insights 圖表、睡眠助理），
// 兩處都不會有任何錯誤訊息。
//
// ⚠️ 這些測試**不能**寫成跟 DateTime.now() 或裝置時區有關的形式——
//    那樣在 CI 或別人的機器上會得到不同結果，而這正是我們要避免的問題本身。

import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/wall_clock.dart';

void main() {
  test('帶 +08:00 的字串要讀回字串上寫的時間，不是 UTC', () {
    final t = parseWallClock('2026-08-22T22:32:00+08:00')!;
    expect(t.hour, 22, reason: 'tryParse 會給 14（UTC），那是 bug 本身');
    expect(t.minute, 32);
  });

  test('跨午夜的起床時間', () {
    final t = parseWallClock('2026-08-23T04:56:00+08:00')!;
    expect(t.hour, 4);
    expect(t.minute, 56);
  });

  test('負偏移量也要對', () {
    final t = parseWallClock('2026-08-22T22:32:00-05:00')!;
    expect(t.hour, 22);
    expect(t.minute, 32);
  });

  test('有分鐘的偏移量（例如印度 +05:30）', () {
    final t = parseWallClock('2026-08-22T22:32:00+05:30')!;
    expect(t.hour, 22);
    expect(t.minute, 32);
  });

  test('標 Z 的字串本身就是牆鐘時間', () {
    final t = parseWallClock('2026-08-22T22:32:00Z')!;
    expect(t.hour, 22);
    expect(t.minute, 32);
  });

  test('沒有偏移量的字串照原樣讀', () {
    final t = parseWallClock('2026-08-22T22:32:00')!;
    expect(t.hour, 22);
    expect(t.minute, 32);
  });

  test('日期裡的減號不能被誤判成偏移量', () {
    // 2026-08-22 有兩個減號，正則若沒有錨在字串尾端就會誤判
    final t = parseWallClock('2026-08-22T22:32:00')!;
    expect(t.year, 2026);
    expect(t.month, 8);
    expect(t.day, 22);
  });

  test('壞掉的輸入回 null，不丟例外', () {
    expect(parseWallClock(null), isNull);
    expect(parseWallClock(''), isNull);
    expect(parseWallClock('not a time'), isNull);
    expect(parseWallClock(12345), isNull);
  });
}
