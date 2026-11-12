// 首頁「跟上一晚比」的純函式。
import 'package:app/services/night_compare.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const nights = [
    NightValue('2026-11-05', 400),
    NightValue('2026-11-06', 360),
    // 11-07 沒戴錶：沒有這一筆
    NightValue('2026-11-08', 420),
  ];

  test('比的是上一個有資料的晚上（沒資料的跳過）', () {
    final d = compareWithPrevious(nights, '2026-11-08')!;
    expect(d.previousDate, '2026-11-06');
    expect(d.delta, 60);
  });

  test('首頁那一晚沒有值 → 不比', () {
    expect(compareWithPrevious(nights, '2026-11-07'), isNull);
  });

  test('之前沒有任何一晚 → 不比', () {
    expect(compareWithPrevious(nights, '2026-11-05'), isNull);
  });

  test('不會拿之後的晚上來比（順序打亂也一樣）', () {
    final shuffled = [nights[2], nights[0], nights[1]];
    expect(
      compareWithPrevious(shuffled, '2026-11-06')!.previousDate,
      '2026-11-05',
    );
  });

  test('⚠️ 顏色只看方向：上升紅、下降綠、持平灰（不判斷好壞）', () {
    expect(deltaColor(const NightDelta(5, '2026-11-01')), kDeltaUp);
    expect(deltaColor(const NightDelta(-5, '2026-11-01')), kDeltaDown);
    expect(deltaColor(const NightDelta(0, '2026-11-01')), kDeltaFlat);
    expect(kDeltaUp, const Color(0xFFFF6B6B));
    expect(kDeltaDown, const Color(0xFF7ED957));
  });

  test('文字：箭頭＋差多少＋跟哪一晚比', () {
    expect(
      deltaText(const NightDelta(72, '2026-11-08'), formatMinutes),
      '↑ 1h 12m vs Nov 8',
    );
    expect(
      deltaText(const NightDelta(-15, '2026-11-08'), formatMinutes),
      '↓ 15m vs Nov 8',
    );
    expect(
      deltaText(const NightDelta(0, '2026-11-08'), formatMinutes),
      '= same vs Nov 8',
    );
  });

  test('長條圖：最近 7 晚、含當晚、由舊到新、不含之後的', () {
    final many = [
      for (var d = 1; d <= 10; d++)
        NightValue('2026-11-${d.toString().padLeft(2, '0')}', d.toDouble()),
    ];
    final got = lastNights(many, '2026-11-09');
    expect(got.length, 7);
    expect(got.first.date, '2026-11-03');
    expect(got.last.date, '2026-11-09');
  });
}
