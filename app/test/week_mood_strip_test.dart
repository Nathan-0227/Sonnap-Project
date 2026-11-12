// 首頁上方的一週日期列。
import 'package:app/models/sleep_session.dart';
import 'package:app/widgets/week_mood_strip.dart';
import 'package:flutter_test/flutter_test.dart';

HistoryEntry night(String date, String? mood) =>
    HistoryEntry.fromJson({'date': date, 'pet_mood': mood});

void main() {
  test('四種心情的圖示與顏色都不一樣（不然 anxious 會被看成 bored）', () {
    const moods = ['happy', 'bored', 'tired', 'anxious'];
    expect(moods.map(moodIcon).toSet().length, 4);
    expect(moods.map(moodColor).toSet().length, 4);
  });

  test('以最新一晚為終點往回 7 個日曆天，中間沒資料的那天留空', () {
    final days = WeekMoodStrip.lastSevenDays([
      night('2026-11-01', 'happy'),
      night('2026-11-04', 'tired'),
      night('2026-11-06', 'anxious'),
    ]);
    expect(days.length, 7);
    expect(days.first.$1, DateTime(2026, 10, 31));
    expect(days.last.$1, DateTime(2026, 11, 6));
    expect(days.map((d) => d.$2?.petMood).toList(),
        [null, 'happy', null, null, 'tired', null, 'anxious'],
        reason: '只取最後 7 筆的話，沒戴錶的日子會被藏起來');
  });

  test('跨月也連續', () {
    final days = WeekMoodStrip.lastSevenDays([night('2026-12-02', 'happy')]);
    expect(days.first.$1, DateTime(2026, 11, 26));
  });

  test('沒有任何歷史 → 不畫', () {
    expect(WeekMoodStrip.lastSevenDays(const []), isEmpty);
  });
}
