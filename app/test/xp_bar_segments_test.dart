// 經驗條一晚一格（xpBarSegments）：只排版，每格大小就是後端那一晚的 total。
import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/game_service.dart';
import 'package:app/services/morning_report.dart';

NightXp n(String date, int total) =>
    NightXp(date: date, behaviourXp: total, qualityXp: 0, total: total);

void main() {
  test('從目前進度往回排，最舊的部分合成「更早累積的」一段', () {
    final segs = xpBarSegments(
      into: 215,
      nights: [n('11-11', 30), n('11-12', 50), n('11-13', 25)],
    );
    expect(segs.map((g) => (g.date, g.start, g.end)).toList(), [
      (null, 0, 110),
      ('11-11', 110, 140),
      ('11-12', 140, 190),
      ('11-13', 190, 215),
    ]);
  });

  test('+0 的晚上沒有格子（照實，不畫成一條線）', () {
    final segs = xpBarSegments(
      into: 60,
      nights: [n('11-12', 20), n('11-13', 0)],
    );
    expect(segs.where((g) => g.date == '11-13'), isEmpty);
    expect(segs.last.date, '11-12');
    expect(segs.last.end, 60);
  });

  test('剛升級：跨進這一級之前的那一晚只畫這一級裡的部分，沒有更早的一段', () {
    final segs = xpBarSegments(
      into: 10,
      nights: [n('11-12', 40), n('11-13', 25)],
    );
    expect(segs.map((g) => (g.date, g.start, g.end)).toList(), [
      ('11-13', 0, 10),
    ]);
  });

  test('進度是 0 → 沒有任何格子', () {
    expect(xpBarSegments(into: 0, nights: [n('11-13', 25)]), isEmpty);
  });
}
