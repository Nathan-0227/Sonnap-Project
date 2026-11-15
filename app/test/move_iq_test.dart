// 早晨報告 Yesterday 的 Move IQ（2026-11-15 使用者定）。
// 守：
// - 🔴 騎車不顯示（使用者多半騎機車，手錶分不出機車與腳踏車）：格子、點開的清單、一週、
//   Awake HR 線圖底下的標記都不能出現；只剩騎車的那天整格不畫
// - 其他類型照 Garmin 寫，不用步數改（游泳照寫 Swim）
// - 不寫每段走了幾步、不比平常
import 'package:app/models/yesterday_activity.dart';
import 'package:app/screens/morning_report_screen.dart';
import 'package:app/services/morning_report.dart';
import 'package:app/widgets/move_iq_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MoveIqEvent ev(String type, String start, int minutes) =>
    MoveIqEvent(type: type, start: start, minutes: minutes);

Map<String, dynamic> yesterday(List<Map<String, Object>> moves) => {
  'date': '2026-11-12',
  'steps': 9955,
  'activity': {
    'highly_active_sec': 1747,
    'active_sec': 9691,
    'sedentary_sec': 62062,
  },
  'move_iq': moves,
  'history': [
    for (var d = 6; d <= 12; d++)
      {
        'date': '2026-11-${d.toString().padLeft(2, '0')}',
        'steps': 8000,
        if (d != 9)
          'move_iq': [
            {'type': 'walking', 'start': '17:00', 'minutes': 10 + d},
            {'type': 'cycling', 'start': '18:00', 'minutes': 40},
          ],
      },
  ],
};

Future<void> pumpReport(WidgetTester tester, Map<String, dynamic> y) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  final r = buildMorningReport(
    date: '2026-11-13',
    home: {
      'date': '2026-11-13',
      'behavior': null,
      'metrics': null,
      'scoring': null,
      'yesterday': y,
    },
  );
  await tester.pumpWidget(MaterialApp(home: MorningReportScreen(initial: r)));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Iterable<String> texts(WidgetTester tester, Finder within) => tester
    .widgetList<Text>(find.descendant(of: within, matching: find.byType(Text)))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '');

void main() {
  test('騎車拿掉，其他照留（游泳照 Garmin 寫）', () {
    final shown = moveIqShown([
      ev('cycling', '08:00', 20),
      ev('walking', '12:00', 14),
      ev('swimming', '19:00', 30),
    ]);
    expect(shown.map((e) => e.type), ['walking', 'swimming']);
    expect(moveIqLabel('swimming'), 'Swim');
    expect(moveIqLabel('stair_climbing'), 'Stair climbing');
    expect(moveIqShown(null), isEmpty);
  });

  test('格子的字：全是走路寫 walks；混了別的寫 moves', () {
    final walks = [ev('walking', '12:00', 14), ev('walking', '17:42', 50)];
    expect(moveIqTileValue(walks), '2 walks');
    expect(moveIqTileLine(walks), '1h 4m in total');
    final mixed = [ev('walking', '12:00', 14), ev('swimming', '19:00', 30)];
    expect(moveIqTileValue(mixed), '2 moves');
    expect(moveIqTileLine(mixed), '1 walk · 1 swim · 44m');
    expect(moveIqSpan(ev('walking', '23:50', 20)), '23:50–00:10');
  });

  test('一週：各類型幾分鐘、不含騎車；沒資料是 null', () {
    final y = YesterdayActivity.fromJsonOrNull(yesterday(const []))!;
    final w = moveIqWeek(y.history, '2026-11-12');
    expect(w.length, 7);
    expect(w.last.$2, {'walking': 22});
    expect(w[3].$2, isNull, reason: '11-09 沒帶 move_iq');
  });

  testWidgets('格子：鐘面＋1 walk；點開清單只有走路、沒有 ride', (tester) async {
    await pumpReport(
      tester,
      yesterday([
        {'type': 'walking', 'start': '17:42', 'minutes': 14},
        {'type': 'cycling', 'start': '18:30', 'minutes': 25},
      ]),
    );
    final tile = find.byKey(const Key('report-moveiq'));
    await tester.scrollUntilVisible(
      tile,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    final t = texts(tester, tile).join(' | ');
    expect(t, contains('1 walk'));
    expect(t, contains('14m in total'));
    expect(t.toLowerCase(), isNot(contains('ride')));
    expect(find.byKey(const Key('report-moveiq-dial')), findsOneWidget);

    await tester.tap(tile);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    final sheet = find.byKey(const Key('moveiq-sheet'));
    final all = texts(tester, sheet).join(' | ');
    expect(all, contains('Walk  17:42–17:56'));
    expect(find.byKey(const Key('moveiq-row-0')), findsOneWidget);
    expect(find.byKey(const Key('moveiq-row-1')), findsNothing);
    expect(all, contains('scooter'), reason: '說明為什麼沒有騎車');
    for (final w in ['steps', 'usual', 'week before', 'cycling']) {
      expect(all.toLowerCase(), isNot(contains(w)), reason: w);
    }
    for (var i = 0; i < 7; i++) {
      expect(find.byKey(Key('moveiq-week-$i')), findsOneWidget);
    }
  });

  testWidgets('只有騎車的那天 → 整格不畫', (tester) async {
    await pumpReport(
      tester,
      yesterday([
        {'type': 'cycling', 'start': '18:30', 'minutes': 25},
      ]),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('report-steps')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pump();
    expect(find.byKey(const Key('report-moveiq')), findsNothing);
  });
}
