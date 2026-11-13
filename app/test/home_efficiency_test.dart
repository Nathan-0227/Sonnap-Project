// 首頁效率小卡（2026-11-13 使用者定）：顯示**進分數的效率**（同早晨報告），
// 按了按鈕的晚上是臥床版、沒按退回手錶版，下面一行小字寫是哪一種（照抄後端）。
// 「跟上一晚比」只比同一種：臥床版 88% 跟手錶版 100% 不是同一個量。
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

const buttons = 'watch_tst__phone_tats';
const watchOnly = 'watch_tst__watch_onset_to_wake';

void main() {
  late Map<String, dynamic> raw;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    raw = jsonDecode(await rootBundle.loadString(AssetSleepRepository.assetPath))
        as Map<String, dynamic>;
  });

  /// 打包檔改成：最後三晚的效率（手錶版都是 100），今晚用 [tonight] 那一種。
  SleepSession session({
    required (double, String, String)? tonight,
    List<(double, String)> earlier = const [],
  }) {
    final copy = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
    final history = (copy['history'] as List).cast<Map<String, dynamic>>();
    for (final h in history) {
      h['sleep_efficiency'] = 100.0;
      h.remove('scored_efficiency');
      h.remove('scored_efficiency_basis');
      h.remove('scored_efficiency_label');
    }
    // earlier：由舊到新放在今晚前面
    for (var i = 0; i < earlier.length; i++) {
      final h = history[history.length - 1 - earlier.length + i];
      h['scored_efficiency'] = earlier[i].$1;
      h['scored_efficiency_basis'] = earlier[i].$2;
    }
    final metrics = copy['metrics'] as Map<String, dynamic>;
    metrics['sleep_efficiency'] = 100.0;
    if (tonight != null) {
      for (final target in [history.last, metrics]) {
        target['scored_efficiency'] = tonight.$1;
        target['scored_efficiency_basis'] = tonight.$2;
        target['scored_efficiency_label'] = tonight.$3;
      }
    }
    return SleepSession.fromJson(copy);
  }

  Future<void> pumpHome(WidgetTester tester, SleepSession s) async {
    // 實機大小（三星 1080×2340）：小卡固定高度，多一行字要放得下
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
    final tile = find.byKey(const Key('tile-efficiency'));
    await tester.scrollUntilVisible(tile, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pump();
  }

  Finder inTile(Finder f) =>
      find.descendant(of: find.byKey(const Key('tile-efficiency')), matching: f);

  testWidgets('按了按鈕的晚上：顯示進分數的臥床版（不是手錶的 100），下面寫是哪一種', (tester) async {
    await pumpHome(
        tester, session(tonight: (88.4, buttons, 'From your sleep buttons')));
    expect(inTile(find.textContaining('88', findRichText: true)), findsOneWidget);
    expect(inTile(find.textContaining('100', findRichText: true)), findsNothing);
    expect(inTile(find.text('From your sleep buttons')), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '固定高度的小卡多一行字不能溢出');
  });

  testWidgets('沒按按鈕的晚上：手錶版，寫 Watch only', (tester) async {
    await pumpHome(tester, session(tonight: (100.0, watchOnly, 'Watch only')));
    expect(inTile(find.textContaining('100', findRichText: true)), findsOneWidget);
    expect(inTile(find.text('Watch only')), findsOneWidget);
  });

  testWidgets('⚠️ 上一晚是另一種效率 → 不畫比較（不比臥床版 88 對手錶版 100）', (tester) async {
    await pumpHome(
        tester,
        session(
          tonight: (88.0, buttons, 'From your sleep buttons'),
          earlier: [(100.0, watchOnly), (100.0, watchOnly)],
        ));
    expect(inTile(find.byKey(const Key('tile-compare'))), findsNothing);
  });

  testWidgets('跟同一種的上一晚比：往前找到同一種的那一晚', (tester) async {
    await pumpHome(
        tester,
        session(
          tonight: (88.0, buttons, 'From your sleep buttons'),
          earlier: [(93.0, buttons), (100.0, watchOnly)],
        ));
    final cmp = tester.widget<Text>(inTile(find.byKey(const Key('tile-compare'))));
    expect(cmp.data, contains('5'), reason: '88 對 93，差 5 個百分點');
  });

  testWidgets('舊版打包檔（沒有新欄位）→ 照舊用手錶的效率、沒有那行字', (tester) async {
    await pumpHome(tester, session(tonight: null));
    expect(inTile(find.textContaining('100', findRichText: true)), findsOneWidget);
    expect(inTile(find.text('Watch only')), findsNothing);
    expect(inTile(find.text('From your sleep buttons')), findsNothing);
  });
}
