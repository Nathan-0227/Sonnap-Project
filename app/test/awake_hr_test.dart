// 早晨報告 Yesterday 的 Awake HR（2026-11-15 使用者定）。
// 守：
// - 只放醒著的平均、最高、各區間時間：**不放靜止心率、最低，不寫 Normal／High、不比平常**
//   （Research-Background/心率門檻.md：醒著的平均心率沒有結果關聯的切點）
// - 數字全部照抄後端，Dart 不重算
// - 點線：吸到最近的讀數，離讀數超過 2 分鐘寫 no reading（不內插）；睡著那段標 asleep
// - 愛心跟著心率跳；系統開「減少動態效果」時靜止
// - 後端沒給（打包檔、舊版後端）→ 退回原本的整天心率格子
import 'package:app/models/awake_heart_rate.dart';
import 'package:app/models/yesterday_activity.dart';
import 'package:app/screens/morning_report_screen.dart';
import 'package:app/services/morning_report.dart';
import 'package:app/widgets/awake_hr_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const day = '2026-11-12';

List<Map<String, Object>> readings() {
  final out = <Map<String, Object>>[];
  // 00:00–02:00 睡著 52；02:00–08:00 沒戴錶（空檔）；08:00–20:00 醒著，17:20 最高 150；
  for (var m = 0; m < 120; m += 2) {
    out.add({'t': _t(m), 'value': 52});
  }
  for (var m = 480; m < 1200; m += 2) {
    out.add({'t': _t(m), 'value': m == 1040 ? 150 : 80 + (m ~/ 2) % 7});
  }
  return out;
}

String _t(int m) =>
    '${day}T${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}:00+08:00';

Map<String, dynamic> awakeJson() => {
  'avg': 78,
  'max': 150,
  'max_at': _t(1040),
  'readings': readings(),
  'asleep': [
    {'start': _t(0), 'end': _t(120)},
  ],
  'zones': {
    'max': 199,
    'floors': [100, 119, 139, 159, 179],
    'minutes': [700, 12, 6, 2, 0, 0],
  },
};

Map<String, dynamic> yesterdayJson({bool awake = true}) => {
  'date': day,
  'steps': 9955,
  'activity': {
    'highly_active_sec': 1747,
    'active_sec': 9691,
    'sedentary_sec': 62062,
  },
  'move_iq': [
    {'type': 'walking', 'start': '12:58', 'minutes': 10},
  ],
  'heart_rate': {
    'points': [
      for (var m = 0; m < 1440; m += 10) {'t': _t(m), 'value': 70},
    ],
    'avg': 70,
    'min': 48,
    'max': 150,
    'resting': 55,
    'bucket_minutes': 10,
  },
  if (awake) 'awake_heart_rate': awakeJson(),
  'history': [
    for (var d = 6; d <= 12; d++)
      {
        'date': '2026-11-${d.toString().padLeft(2, '0')}',
        'steps': 8000,
        if (d != 9) 'awake_hr': {'avg': 76 + d % 5, 'max': 130 + d},
      },
  ],
};

Future<void> pumpReport(
  WidgetTester tester,
  Map<String, dynamic> yesterday, {
  bool reduceMotion = false,
}) async {
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
      'yesterday': yesterday,
    },
  );
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: MorningReportScreen(initial: r),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

Iterable<String> texts(WidgetTester tester, Finder within) => tester
    .widgetList<Text>(find.descendant(of: within, matching: find.byType(Text)))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '');

double beatOf(WidgetTester tester) {
  final cp = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byKey(const Key('report-awake-hr-heart')),
      matching: find.byType(CustomPaint),
    ),
  );
  return (cp.painter as GlowingHeartPainter).beat;
}

void main() {
  test('解析：照抄後端的數字；區間格式不對就不給', () {
    final a = AwakeHeartRate.fromJsonOrNull(awakeJson())!;
    expect((a.avg, a.max), (78, 150));
    expect(a.maxAt!.hour * 60 + a.maxAt!.minute, 1040);
    expect(a.zoneMinutes, [700, 12, 6, 2, 0, 0]);
    expect(a.isAsleep(a.readings.first.t), isTrue, reason: "00:00 睡著");
    expect(a.isAsleep(a.maxAt!), isFalse, reason: "17:20 醒著");
    final bad = {
      ...awakeJson(),
      'zones': {
        'max': 199,
        'floors': [100, 119],
        'minutes': [1, 2],
      },
    };
    expect(AwakeHeartRate.fromJsonOrNull(bad)!.zoneMinutes, isNull);
    expect(AwakeHeartRate.fromJsonOrNull({'avg': 70}), isNull);
    final y = YesterdayActivity.fromJsonOrNull(yesterdayJson())!;
    expect(y.history.last.awakeHrAvg, 76 + 12 % 5);
    expect(
      y.history.firstWhere((h) => h.date == '2026-11-09').awakeHrAvg,
      isNull,
    );
  });

  test('點線：吸到最近的讀數；空檔寫 no reading；睡著那段標 asleep', () {
    final a = AwakeHeartRate.fromJsonOrNull(awakeJson())!;
    expect(awakeHrProbeText(a, 1040), '17:20 · 150 bpm');
    expect(awakeHrProbeText(a, 1041), '17:20 · 150 bpm');
    expect(awakeHrProbeText(a, 300), '05:00 · no reading');
    expect(awakeHrProbeText(a, 60), '01:00 · 52 bpm · asleep');
  });

  test('區間的名字與範圍（照 Garmin 的叫法，不加好壞）', () {
    const f = [100, 119, 139, 159, 179];
    expect(
      [for (var i = 0; i <= 5; i++) awakeHrZoneRange(f, i)],
      ['< 100', '100–118', '119–138', '139–158', '159–178', '179+'],
    );
    expect(awakeHrZoneLabel(0), 'Below zone 1');
    expect(awakeHrZoneLabel(3), 'Zone 3');
  });

  testWidgets('格子：Awake HR、大字 78 BPM、peak 150 at 17:20；沒有靜止心率與判斷字眼', (
    tester,
  ) async {
    await pumpReport(tester, yesterdayJson());
    final tile = find.byKey(const Key('report-awake-hr'));
    await scrollTo(tester, tile);
    expect(find.byKey(const Key('report-day-hr')), findsNothing);
    final t = texts(tester, tile).join(' | ');
    expect(t, contains('Awake HR'));
    expect(t, contains('78 BPM'));
    expect(t, contains('peak 150 at 17:20'));
    for (final w in [
      'resting',
      'lowest',
      'normal',
      'high',
      'elevated',
      'usual',
    ]) {
      expect(t.toLowerCase(), isNot(contains(w)), reason: w);
    }
  });

  testWidgets('愛心跟著心率跳', (tester) async {
    await pumpReport(tester, yesterdayJson());
    await scrollTo(tester, find.byKey(const Key('report-awake-hr')));
    final seen = <double>{};
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      seen.add(beatOf(tester));
    }
    expect(seen.length, greaterThan(3), reason: '每分鐘 78 下，0.8 秒內要看得到在動');
  });

  // ⚠️ 另開一條（不接在上一條後面）：同一條裡第二次 pumpWidget 會沿用上一個畫面的狀態，
  //    拿掉「減少動態效果就靜止」也照樣綠（2026-11-15 反向驗證抓到）
  testWidgets('減少動態效果時愛心靜止', (tester) async {
    await pumpReport(tester, yesterdayJson(), reduceMotion: true);
    await scrollTo(tester, find.byKey(const Key('report-awake-hr')));
    final seen = <double>{};
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      seen.add(beatOf(tester));
    }
    expect(seen, {0.0});
  });

  test('一次心跳：撲通兩下，第二下比較小', () {
    expect(heartBeat(0.08), closeTo(1, 1e-9));
    expect(heartBeat(0.26), closeTo(0.55, 1e-9));
    expect(heartBeat(0.6), 0);
  });

  testWidgets('點開：平均、最高、整天的線、區間（寫 max 199）、一週；沒有靜止心率與判斷字眼', (tester) async {
    await pumpReport(tester, yesterdayJson());
    final tile = find.byKey(const Key('report-awake-hr'));
    await scrollTo(tester, tile);
    await tester.tap(tile);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    final sheet = find.byKey(const Key('awake-hr-sheet'));
    expect(sheet, findsOneWidget);
    final all = texts(tester, sheet).join(' | ');
    expect(all, contains('78 bpm'));
    expect(all, contains('peak at 17:20'));
    expect(all, contains('Time in zones (max 199)'));
    expect(all, contains('Asleep · see Sleeping HR'));
    expect(all, contains('Below zone 1'));
    expect(all, contains('11h 40m'));
    for (final w in [
      'resting',
      'lowest',
      'normal',
      'elevated',
      'usual',
      'too high',
    ]) {
      expect(all.toLowerCase(), isNot(contains(w)), reason: w);
    }
    expect(find.byKey(const Key('awake-hr-day-line')), findsOneWidget);
    for (var i = 0; i < 7; i++) {
      expect(find.byKey(Key('awake-hr-week-$i')), findsOneWidget);
    }
    // 11-09 沒有資料：寫「—」，不畫成 0
    final w = texts(tester, find.byKey(const Key('awake-hr-week-3'))).join();
    expect(w, contains('—'));
  });

  testWidgets('後端沒給 awake_heart_rate → 退回原本的整天心率格子', (tester) async {
    await pumpReport(tester, yesterdayJson(awake: false));
    await scrollTo(tester, find.byKey(const Key('report-day-hr')));
    expect(find.byKey(const Key('report-awake-hr')), findsNothing);
  });
}
