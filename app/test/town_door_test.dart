// 送禮推門的時間軸（widgets/town_door_route.dart）：
// 先淡入地圖 → 一路放大、不回頭 → 暖光蓋滿之後地圖才淡掉（不然會直接切到客廳）→ 最後只剩客廳。
import 'package:app/widgets/town_door_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('【1】開始時是原本大小、沒有光；結束時地圖已經淡掉', () {
    final a = TownDoorFrame.at(0);
    expect(a.scale, 1);
    expect(a.glow, 0);
    expect(TownDoorFrame.at(1).map, 0);
  });

  test('【2】一路放大、不回頭，最後放到最大', () {
    var last = 0.0;
    for (var t = 0.0; t <= 1; t += .01) {
      final s = TownDoorFrame.at(t).scale;
      expect(s, greaterThanOrEqualTo(last), reason: 't=$t');
      last = s;
    }
    expect(TownDoorFrame.at(1).scale, closeTo(TownDoorFrame.maxScale, 1e-9));
  });

  test('【3】暖光亮滿之前地圖不淡掉（看得到推進門裡，不是直接切換）', () {
    for (var t = 0.2; t <= 1; t += .01) {
      final f = TownDoorFrame.at(t);
      if (f.glow < 1) expect(f.map, closeTo(1, 1e-9), reason: 't=$t');
    }
  });
}
