// 首頁兩張主卡（2026-11-13 使用者定，參考 Otter Life）：Sleep（昨晚）與 Activity（前一天）。
// 守：只寫事實（goal、不寫達標、不寫 Normal）；Sleep 卡的心率是睡著期間、Activity 卡是整天，
//     兩個不混；沒有白天資料整張 Activity 不畫；點了開長條圖／整天心率線；實機大小不溢出。
import 'dart:convert';

import 'package:app/models/sleep_session.dart';
import 'package:app/screens/home_screen.dart';
import 'package:app/services/alarm.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/sleep_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repo implements SleepRepository {
  final SleepSession session;
  const _Repo(this.session);
  @override
  Future<SleepSession> load() async => session;
}

class _NoAlarm implements AlarmScheduler {
  @override
  Future<void> schedule(DateTime at) async {}
  @override
  Future<void> cancel() async {}
  @override
  Future<bool> canRing() async => true;
  @override
  Future<void> requestPermission() async {}
  @override
  Future<void> openSettings() async {}
}

Map<String, dynamic> curve(int n, double base, String day, {int every = 10}) => {
      'points': [
        for (var i = 0; i < n; i++)
          {
            't': '${DateTime(2026, 11, int.parse(day), 0, 0).add(Duration(minutes: every * i)).toIso8601String().replaceFirst('.000', '')}+08:00',
            'value': base + (i % 7) * 10,
          }
      ],
      'avg': base + 20,
      'min': base,
      'max': base + 60,
    };

Map<String, dynamic> activity() => {
      'date': '2026-11-12',
      'steps': 9955,
      'step_goal': 9430,
      'distance_m': 6720,
      'active_kcal': 377,
      'floors_up': 9.4,
      'activity': {'highly_active_sec': 1747, 'active_sec': 9691, 'sedentary_sec': 62062},
      'vo2max': {'value': 46.0, 'measured_on': '2026-10-09'},
      'move_iq': [
        {'type': 'walking', 'start': '12:58', 'minutes': 10},
        {'type': 'walking', 'start': '17:19', 'minutes': 19},
        {'type': 'cycling', 'start': '20:55', 'minutes': 31},
      ],
      'heart_rate': {...curve(140, 52, '12'), 'resting': 59},
      'history': [
        for (var d = 6; d <= 12; d++)
          {'date': '2026-11-${d.toString().padLeft(2, '0')}', 'steps': 7000 + d * 100,
           'active_kcal': 300 + d, 'active_minutes': 150 + d},
      ],
    };

void main() {
  late Map<String, dynamic> raw;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    raw = jsonDecode(await rootBundle.loadString(AssetSleepRepository.assetPath))
        as Map<String, dynamic>;
  });

  SleepSession session({bool withActivity = true, bool nightHr = true}) {
    final copy = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
    final m = copy['metrics'] as Map<String, dynamic>;
    m['resting_heart_rate'] = 53;
    m['heart_rate_curve'] = nightHr ? curve(40, 47, '13', every: 5) : null;
    if (withActivity) {
      copy['activity'] = activity();
    } else {
      copy.remove('activity');
    }
    return SleepSession.fromJson(copy);
  }

  Future<void> pumpHome(WidgetTester tester, SleepSession s) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeScreen(
          repository: _Repo(s),
          bedMarks: BedMarkStore(InMemoryKeyValueStore()),
          alarmScheduler: _NoAlarm(),
          clock: () => DateTime(2026, 11, 13, 9),
        ),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  Future<void> scrollTo(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first);
    await tester.pump();
  }

  String textIn(WidgetTester tester, String tileKey, String needle) {
    final texts = tester
        .widgetList<Text>(find.descendant(of: find.byKey(Key(tileKey)), matching: find.byType(Text)))
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .join(' | ');
    expect(texts, contains(needle), reason: tileKey);
    return texts;
  }

  testWidgets('兩張主卡：Sleep（昨晚）與 Activity（Yesterday · 那一天）', (tester) async {
    await pumpHome(tester, session());
    await scrollTo(tester, find.byKey(const Key('home-activity-section')));
    expect(find.text('Yesterday · Thu, Nov 12'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '實機大小不溢出');
  });

  testWidgets('兩欄（照 Otter Life）：左邊一格一格、右邊一張 Activity 卡，上下緣對齊、各佔一半', (tester) async {
    await pumpHome(tester, session());
    await scrollTo(tester, find.byKey(const Key('home-activity-section')));
    final sleep = tester.getRect(find.byKey(const Key('home-sleep-section')));
    final act = tester.getRect(find.byKey(const Key('home-activity-section')));
    expect(act.left, greaterThan(sleep.right), reason: 'Activity 在右邊');
    expect((act.top - sleep.top).abs(), lessThan(1), reason: '上緣對齊');
    expect((act.bottom - sleep.bottom).abs(), lessThan(1), reason: '下緣對齊（兩張一樣高）');
    // 睡眠的在左欄；Activity 的在右邊那張
    bool inside(String k, Rect box) {
      final r = tester.getRect(find.byKey(Key(k)));
      return r.left >= box.left && r.right <= box.right && r.top >= box.top && r.bottom <= box.bottom;
    }
    for (final k in ['tile-duration', 'tile-efficiency', 'tile-deep', 'tile-camera']) {
      expect(inside(k, sleep), isTrue, reason: k);
    }
    for (final k in ['tile-steps', 'tile-kcal', 'tile-active', 'tile-day-hr', 'home-moveiq']) {
      expect(inside(k, act), isTrue, reason: k);
    }
    // 使用者 2026-11-13 拿掉：左邊的睡著心率（Sleep Stages 疊線還看得到）、右邊的 VO2 max
    expect(find.byKey(const Key('tile-night-hr')), findsNothing);
    expect(find.byKey(const Key('tile-vo2')), findsNothing);
    // 右邊四項平均分配高度：最後一項下面不留一大塊空白
    final hrRow = tester.getRect(find.byKey(const Key('tile-day-hr')));
    final steps = tester.getRect(find.byKey(const Key('tile-steps')));
    final kcal = tester.getRect(find.byKey(const Key('tile-kcal')));
    final pitch = kcal.center.dy - steps.center.dy;
    expect(act.bottom - tester.getRect(find.byKey(const Key('home-moveiq'))).bottom,
        lessThan(pitch / 2 + 12), reason: '底下不留整段空白');
    expect(hrRow.top, greaterThan(kcal.bottom));
    // 分隔線在兩項正中間：每一項在自己那一段上下置中，上下留白差不多
    final dividers = tester
        .widgetList<Divider>(find.descendant(
            of: find.byKey(const Key('home-activity-section')), matching: find.byType(Divider)))
        .length;
    expect(dividers, 5, reason: '標題下一條＋四項之間三條＋Move IQ 前一條');
    final lines = tester
        .getRect(find.byKey(const Key('home-activity-section')))
        .top; // 只為了讀起來清楚：以下都是螢幕座標
    final ys = [
      for (final e in find
          .descendant(of: find.byKey(const Key('home-activity-section')), matching: find.byType(Divider))
          .evaluate())
        (e.renderObject! as RenderBox).localToGlobal(Offset.zero).dy +
            (e.renderObject! as RenderBox).size.height / 2,
    ]..sort();
    expect(ys.first, greaterThan(lines));
    // Steps 夾在第一、二條線之間，上下留白一樣多（線在兩項正中間）
    expect(((steps.top - ys[0]) - (ys[1] - steps.bottom)).abs(), lessThan(2));
    // 左欄的小卡一張張往下疊（不是 2x2）
    final d = tester.getRect(find.byKey(const Key('tile-duration')));
    final e = tester.getRect(find.byKey(const Key('tile-efficiency')));
    expect(e.top, greaterThan(d.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('沒有白天資料 → Sleep 退回整寬 2x2', (tester) async {
    await pumpHome(tester, session(withActivity: false));
    await scrollTo(tester, find.byKey(const Key('tile-efficiency')));
    final d = tester.getRect(find.byKey(const Key('tile-duration')));
    final e = tester.getRect(find.byKey(const Key('tile-efficiency')));
    expect((e.top - d.top).abs(), lessThan(1), reason: '同一列');
    expect(find.textContaining('Last night · '), findsOneWidget);
  });

  testWidgets('Activity：步數只寫 goal、Move IQ 寫幾段；不判斷', (tester) async {
    await pumpHome(tester, session());
    await scrollTo(tester, find.byKey(const Key('tile-active')));
    textIn(tester, 'tile-steps', 'goal 9,430');
    textIn(tester, 'tile-kcal', '6.7 km');
    textIn(tester, 'tile-active', '');
    await scrollTo(tester, find.byKey(const Key('home-moveiq')));
    expect(tester.widget<Text>(find.byKey(const Key('home-moveiq'))).data,
        'Move IQ · 2 walks · 1 ride');
    final all = [
      for (final k in ['tile-steps', 'tile-kcal', 'tile-active', 'tile-day-hr'])
        ...tester.widgetList<Text>(find.descendant(of: find.byKey(Key(k)), matching: find.byType(Text))),
      tester.widget<Text>(find.byKey(const Key('home-moveiq'))),
    ].map((t) => (t.data ?? t.textSpan?.toPlainText() ?? '').toLowerCase()).join(' ');
    expect(all, contains('9,955'), reason: '反向對照：真的有讀到字');
    for (final w in ['reached', 'achieved', 'normal', 'high', 'good', 'great']) {
      expect(all.contains(w), isFalse, reason: w);
    }
  });

  testWidgets('⚠️ 兩個心率不混：首頁兩欄只放整天心率；沒有白天資料時 Sleep 格子才放睡著期間的', (tester) async {
    await pumpHome(tester, session());
    await scrollTo(tester, find.byKey(const Key('tile-day-hr')));
    textIn(tester, 'tile-day-hr', 'all day · resting 59');
    textIn(tester, 'tile-day-hr', 'resting 59');
    expect(find.byKey(const Key('tile-night-hr')), findsNothing);
  });

  testWidgets('沒有白天資料 → 整寬 Sleep 格子照舊有睡著期間的心率', (tester) async {
    await pumpHome(tester, session(withActivity: false));
    await scrollTo(tester, find.byKey(const Key('tile-night-hr')));
    textIn(tester, 'tile-night-hr', 'avg while asleep · resting 53');
  });

  testWidgets('點整天心率 → 那一天的心率線，只寫最低最高靜止', (tester) async {
    await pumpHome(tester, session());
    await scrollTo(tester, find.byKey(const Key('tile-day-hr')));
    await tester.tap(find.byKey(const Key('tile-day-hr')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('day-hr-sheet')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('day-hr-facts'))).data,
        'lowest 52 · highest 112 · resting 59');
    expect(tester.takeException(), isNull);
  });

  testWidgets('點步數 → 最近 7 天長條圖', (tester) async {
    await pumpHome(tester, session());
    await scrollTo(tester, find.byKey(const Key('tile-steps')));
    await tester.tap(find.byKey(const Key('tile-steps')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('activity-sheet-steps')), findsOneWidget);
    expect(find.text('Steps · last 7 days'), findsOneWidget);
  });

  testWidgets('沒有白天資料 → 整張 Activity 不畫；沒有心率曲線 → Sleep 卡不畫心率', (tester) async {
    await pumpHome(tester, session(withActivity: false, nightHr: false));
    await scrollTo(tester, find.byKey(const Key('home-sleep-section')));
    expect(find.byKey(const Key('home-activity-section')), findsNothing);
    expect(find.byKey(const Key('tile-night-hr')), findsNothing);
  });
}
