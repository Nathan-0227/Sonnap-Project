// 送禮推門的時間軸（widgets/town_door_route.dart）：
// 先淡入地圖 → 一路放大、不回頭 → 暖光蓋滿之後地圖才淡掉（不然會直接切到客廳）→ 最後只剩客廳。
import 'package:app/widgets/friends_town.dart' show kTownLots;
import 'package:app/widgets/town_door_route.dart';
import 'package:flutter/material.dart';
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

  test('【4】每一間、每一刻、各種螢幕：地圖都蓋滿畫面（不露出空的一邊）', () {
    // 2026-11-22 實機：地圖先裁成畫面大小再移，往中間移時左半邊整片黑；房子在地圖邊上時也會拉出地圖外面
    for (final size in const [Size(360, 780), Size(411, 900), Size(800, 600)]) {
      for (final lot in kTownLots) {
        for (var t = 0.0; t <= 1; t += .02) {
          final f = TownDoorFrame.at(t);
          final g = townDoorGeometry(size, lot + kTownDoorHouseShift, f);
          Offset at(Offset p) => g.anchor + (p - g.house) * f.scale;
          final tl = at(g.map.topLeft), br = at(g.map.bottomRight);
          final why = 'size=$size lot=$lot t=${t.toStringAsFixed(2)}';
          expect(tl.dx, lessThanOrEqualTo(.001), reason: why);
          expect(tl.dy, lessThanOrEqualTo(.001), reason: why);
          expect(br.dx, greaterThanOrEqualTo(size.width - .001), reason: why);
          expect(br.dy, greaterThanOrEqualTo(size.height - .001), reason: why);
        }
      }
    }
  });
}
