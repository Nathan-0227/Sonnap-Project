// Insights W/M/Y 的加總（services/insights_periods.dart）。守的都是寫錯不會報錯的地方。
import 'package:app/services/camera_insights.dart';
import 'package:app/services/insights_periods.dart';
import 'package:app/widgets/phone_week_sheet.dart' show PhoneDown;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final wed = DateTime(2026, 11, 18);

  test('中位數：沒資料的日子不算進去（不是當 0）', () {
    final s = periodStat({'2026-11-16': 400, '2026-11-17': 420, '2026-11-18': 380},
        InsightsPeriod.week, wed);
    expect(s.median, 400);
    expect(s.n, 3);
    expect(s.bars, [400, 420, 380, null, null, null, null]);
  });

  test('跟上一期比：上一週沒資料 → 沒有比較（不是跟 0 比）', () {
    final s = periodStat({'2026-11-17': 420}, InsightsPeriod.week, wed);
    expect(s.previous, isNull);
    expect(s.delta, isNull);
    final t = periodStat({'2026-11-10': 400, '2026-11-17': 430}, InsightsPeriod.week, wed);
    expect(t.delta, 30);
  });

  test('Year 是 12 欄、每欄是那個月的中位數', () {
    final s = periodStat({'2026-09-01': 10, '2026-09-02': 20, '2026-09-03': 90, '2026-11-01': 5},
        InsightsPeriod.year, wed);
    expect(s.bars.length, 12);
    expect(s.bars[8], 20, reason: '九月三晚的中位數，不是平均 40');
    expect(s.bars[10], 5);
    expect(s.bars[0], isNull);
  });

  test('跨午夜的時刻：23:50 與 00:10 的中位數是 00:00，不是中午', () {
    final a = clockFromNoon(DateTime(2026, 11, 17, 23, 50));
    final b = clockFromNoon(DateTime(2026, 11, 18, 0, 10));
    expect(clockLabel(median([a, b])!), '00:00');
  });

  test('熬夜幾晚：照抄 is_late；後端沒判的與下午的不進分母', () {
    final downs = {
      '2026-11-16': PhoneDown(DateTime(2026, 11, 16, 3, 40), true),
      '2026-11-17': PhoneDown(DateTime(2026, 11, 17, 2, 50), false),
      '2026-11-18': PhoneDown(DateTime(2026, 11, 18, 3, 10), null),
      '2026-11-19': PhoneDown(DateTime(2026, 11, 19, 14, 7), true),
    };
    final c = lateCount(downs, InsightsPeriod.week, wed);
    expect(c.late, 1);
    expect(c.judged, 2);
  });

  test('等級照後端的切點；沒有切點（舊版後端）就不換', () {
    const bands = [QualityBand(80, 'Good'), QualityBand(65, 'Normal'),
      QualityBand(50, 'Poor'), QualityBand(0, 'Bad')];
    expect(qualityFor(80, bands), 'Good');
    expect(qualityFor(79.9, bands), 'Normal');
    expect(qualityFor(80, const []), isNull);
    expect(starsFor('Good'), 4);
    expect(starsFor(null), 0);
  });

  test('從 /insights 收：0 步是沒戴錶；按鈕齊了才用按鈕，不然手錶', () {
    final r = CameraInsightsResult(
      CameraInsightsStatus.ok,
      dailies: const {
        '2026-11-16': DailyActivity(steps: 0, activeKcal: 0),
        '2026-11-17': DailyActivity(steps: 8000, activeKcal: 300),
      },
      bedButtons: {
        '2026-11-17': (DateTime(2026, 11, 17, 3, 0), DateTime(2026, 11, 17, 10, 0)),
        '2026-11-18': (DateTime(2026, 11, 18, 3, 0), null),
      },
      watchSleep: {
        '2026-11-18': (DateTime(2026, 11, 18, 3, 20), DateTime(2026, 11, 18, 9, 20)),
      },
    );
    final s = PeriodSeries.fromInsights(r);
    expect(s.steps.containsKey('2026-11-16'), isFalse);
    expect(s.activeKcal.containsKey('2026-11-16'), isFalse);
    expect(s.steps['2026-11-17'], 8000);
    expect(s.inBed['2026-11-17'], 420);
    expect(s.inBed['2026-11-18'], 360, reason: '只按了上床 → 退回手錶的入睡→醒來');
  });
}
