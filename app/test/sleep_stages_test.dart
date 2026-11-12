// 首頁 Sleep Stages 卡（2026-11-12）。
//
// 守的是壞掉時不會報錯的地方：
// - 時間照牆鐘讀（+08:00 不能被換成 UTC，否則軸上的時間差 8 小時）
// - 沒量到 REM 的晚上：圖例寫 not measured，不寫 0m
// - 沒有資料時老實講「Not available yet」，不畫假的
import 'package:app/models/sleep_stages.dart';
import 'package:app/widgets/sleep_stages_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> block({bool remMeasured = true}) => {
  'segments': [
    {
      'stage': 'light',
      'start': '2026-11-08T02:48:00+08:00',
      'end': '2026-11-08T03:06:00+08:00',
    },
    {
      'stage': 'deep',
      'start': '2026-11-08T03:06:00+08:00',
      'end': '2026-11-08T03:34:00+08:00',
    },
    {
      'stage': 'light',
      'start': '2026-11-08T03:34:00+08:00',
      'end': '2026-11-08T06:43:00+08:00',
    },
  ],
  'minutes': {
    'awake': 0,
    'rem': remMeasured ? 67 : 0,
    'light': 138,
    'deep': 30,
  },
  'rem_measured': remMeasured,
};

Future<void> pump(WidgetTester tester, Widget w) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
}

void main() {
  test('解析：段數、牆鐘時間（不是 UTC）、圖例分鐘數', () {
    final s = SleepStages.fromJsonOrNull(block())!;
    expect(s.segments.length, 3);
    expect(s.start.hour, 2, reason: '+08:00 的 02:48 要讀成 02 點，不是 UTC 的 18 點');
    expect(s.end.hour, 6);
    expect(s.lightMinutes, 138);
    expect(s.remMeasured, isTrue);
  });

  test('沒有區塊、或沒有任何有效段 → null（不畫卡）', () {
    expect(SleepStages.fromJsonOrNull(null), isNull);
    expect(SleepStages.fromJsonOrNull({'segments': []}), isNull);
  });

  testWidgets('卡片：圖例用手錶的總數、時間軸從入睡到起床', (tester) async {
    await pump(
      tester,
      SleepStagesCard(
        stages: SleepStages.fromJsonOrNull(block())!,
        totalSleepMinutes: 235,
      ),
    );
    expect(find.text('2h 18m'), findsOneWidget); // light 138
    expect(find.text('1h 7m'), findsOneWidget); // rem 67
    expect(find.text('3h 55m'), findsOneWidget); // 總睡眠
    expect(find.text('2:48 AM'), findsOneWidget);
    expect(find.text('6:43 AM'), findsOneWidget);
  });

  testWidgets('⚠️ 沒量到 REM：圖例寫 not measured，不寫 0m', (tester) async {
    await pump(
      tester,
      SleepStagesCard(
        stages: SleepStages.fromJsonOrNull(block(remMeasured: false))!,
      ),
    );
    expect(find.text('not measured'), findsOneWidget);
    expect(
      find.text('0m'),
      findsOneWidget,
      reason: '只有 awake 的 0m，REM 那格不能是 0m',
    );
  });

  testWidgets('沒有資料的那張卡老實講還沒有', (tester) async {
    await pump(tester, const SleepStagesUnavailableCard());
    expect(find.text('Not available yet'), findsOneWidget);
  });
}
