import 'dart:math' as math;
import 'dart:ui';

/// 平滑但**不超出**相鄰兩點範圍的曲線（Fritsch–Carlson 單調三次插值）。
///
/// 一般的平滑曲線（Catmull-Rom、二次貝茲）在轉折處會衝過頭，畫出比實際最低還低的心率——
/// 那是沒發生的值（同 Sleep Stages「不畫平滑波浪」的理由）。這個寫法保證每一段都夾在兩端點之間。
/// `test/sleep_stages_overlay_test.dart` 沿整條線取樣驗證。
Path monotonePath(List<double> xs, List<double> ys) {
  final n = xs.length;
  final path = Path()..moveTo(xs[0], ys[0]);
  if (n == 2) {
    path.lineTo(xs[1], ys[1]);
    return path;
  }
  final d = List<double>.filled(n - 1, 0);
  for (var i = 0; i < n - 1; i++) {
    final dx = xs[i + 1] - xs[i];
    d[i] = dx == 0 ? 0 : (ys[i + 1] - ys[i]) / dx;
  }
  final m = List<double>.filled(n, 0);
  m[0] = d[0];
  m[n - 1] = d[n - 2];
  for (var i = 1; i < n - 1; i++) {
    m[i] = (d[i - 1] * d[i] <= 0) ? 0 : (d[i - 1] + d[i]) / 2;
  }
  for (var i = 0; i < n - 1; i++) {
    if (d[i] == 0) {
      m[i] = 0;
      m[i + 1] = 0;
      continue;
    }
    final a = m[i] / d[i];
    final b = m[i + 1] / d[i];
    final s = a * a + b * b;
    if (s > 9) {
      final t = 3 / math.sqrt(s);
      m[i] = t * a * d[i];
      m[i + 1] = t * b * d[i];
    }
  }
  for (var i = 0; i < n - 1; i++) {
    final dx = xs[i + 1] - xs[i];
    path.cubicTo(
      xs[i] + dx / 3,
      ys[i] + m[i] * dx / 3,
      xs[i + 1] - dx / 3,
      ys[i + 1] - m[i + 1] * dx / 3,
      xs[i + 1],
      ys[i + 1],
    );
  }
  return path;
}
