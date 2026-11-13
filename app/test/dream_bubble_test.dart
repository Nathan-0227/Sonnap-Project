// 小狗說「I had a dream…」的對話框（2026-11-13 使用者定）：
// 對話框只放一句短話，點開才看完整夢境；沒有夢境就不出現；首頁看過就縮成 💭。
import 'dart:convert';

import 'package:app/models/sleep_session.dart';
import 'package:app/screens/home_screen.dart';
import 'package:app/screens/morning_report_screen.dart';
import 'package:app/services/alarm.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/morning_report.dart';
import 'package:app/services/sleep_repository.dart';
import 'package:app/widgets/dream_diary.dart';
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

Future<void> frames(WidgetTester tester, [int n = 8]) async {
  // 小狗一直在動，pumpAndSettle 等不到停
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  late Map<String, dynamic> raw;
  late SleepSession withDream;
  late SleepSession noDream;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    raw = jsonDecode(await rootBundle.loadString(AssetSleepRepository.assetPath))
        as Map<String, dynamic>;
    withDream = SleepSession.fromJson(raw);
    final copy = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
    (copy['ai_content'] as Map<String, dynamic>)['dream_summary'] = null;
    noDream = SleepSession.fromJson(copy);
  });

  group('首頁', () {
    late InMemoryKeyValueStore kv;
    setUp(() => kv = InMemoryKeyValueStore());

    Future<void> pumpHome(WidgetTester tester, SleepSession s) async {
      tester.view.physicalSize = const Size(1200, 4200);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            repository: _Repo(s),
            bedMarks: BedMarkStore(kv),
            alarmScheduler: _NoAlarm(),
            clock: () => DateTime(2026, 11, 13, 9),
          ),
        ),
      ));
      await frames(tester);
    }

    testWidgets('有夢 → 小狗旁只說一句短話，不把夢境內容放在對話框裡', (tester) async {
      expect(withDream.aiContent.hasDream, isTrue, reason: '打包檔要有夢境才測得到');
      await pumpHome(tester, withDream);
      expect(find.text('$kDreamBubbleText 💭'), findsOneWidget);
      expect(find.text(withDream.aiContent.dreamSummary!), findsNothing,
          reason: '使用者定：對話框不要那麼多字，點開才看');
    });

    testWidgets('點對話框 → 夢境日記：全文、那一晚的日期、AI 小字；看過縮成 💭 並記住',
        (tester) async {
      await pumpHome(tester, withDream);
      await tester.tap(find.byKey(const Key('dream-bubble-text')));
      await frames(tester);
      expect(find.byKey(const Key('dream-diary')), findsOneWidget);
      expect(textOf(tester, 'dream-diary-text'), withDream.aiContent.dreamSummary);
      final night = DateTime.parse(withDream.history.last.date);
      expect(textOf(tester, 'dream-diary-date'), reportDateTitle(night),
          reason: '舊的夢也要看得出是哪一晚，不被當成昨晚的');
      expect(find.byKey(const Key('dream-diary-disclaimer')), findsOneWidget);

      Navigator.of(tester.element(find.byKey(const Key('dream-diary')))).pop();
      await frames(tester);
      expect(find.byKey(const Key('dream-bubble-compact')), findsOneWidget);
      expect(find.byKey(const Key('dream-bubble-text')), findsNothing);
      expect(
          await DreamReadStore(kv).isRead(withDream.history.last.date), isTrue);
    });

    testWidgets('這個夢已經看過 → 一打開就是 💭', (tester) async {
      await DreamReadStore(kv).markRead(withDream.history.last.date);
      await pumpHome(tester, withDream);
      expect(find.byKey(const Key('dream-bubble-compact')), findsOneWidget);
    });

    testWidgets('看過的是別晚的夢 → 新的夢照樣大聲說', (tester) async {
      await DreamReadStore(kv).markRead('2026-01-01');
      await pumpHome(tester, withDream);
      expect(find.byKey(const Key('dream-bubble-text')), findsOneWidget);
    });

    testWidgets('⚠️ 沒有夢 → 不出現對話框，也不說「沒做夢」', (tester) async {
      await pumpHome(tester, noDream);
      expect(find.byKey(const Key('dream-bubble')), findsNothing);
      expect(find.textContaining("didn't dream"), findsNothing);
      expect(find.textContaining('no dream', findRichText: true), findsNothing);
    });

    testWidgets('對話框不擋到等級徽章', (tester) async {
      await pumpHome(tester, withDream);
      final bubble = tester.getRect(find.byKey(const Key('dream-bubble-text')));
      for (final k in ['level-badge', 'mood-chip']) {
        final f = find.byKey(Key(k));
        if (f.evaluate().isEmpty) continue;
        expect(bubble.overlaps(tester.getRect(f)), isFalse, reason: k);
      }
    });
  });

  group('早晨報告', () {
    Future<void> pumpReport(WidgetTester tester, MorningReport r,
        {VoidCallback? onDreamOpened}) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: MorningReportScreen(initial: r, onDreamOpened: onDreamOpened),
      ));
      await frames(tester);
    }

    MorningReport report({required bool dream}) {
      final date = withDream.history.last.date;
      return buildMorningReport(
        date: date,
        session: dream ? withDream : noDream,
      );
    }

    testWidgets('有夢 → 小狗頭上的對話框，不再有 Dream diary 那一列', (tester) async {
      var opened = 0;
      await pumpReport(tester, report(dream: true), onDreamOpened: () => opened++);
      expect(find.byKey(const Key('report-dream')), findsOneWidget);
      expect(find.text('Dream diary'), findsNothing);
      expect(find.text('$kDreamBubbleText 💭'), findsOneWidget);
      await tester.tap(find.byKey(const Key('dream-bubble-text')));
      await frames(tester);
      expect(textOf(tester, 'dream-diary-text'), withDream.aiContent.dreamSummary);
      expect(opened, 1, reason: '首頁要知道看過了');
      expect(tester.takeException(), isNull);
    });

    testWidgets('沒有夢 → 沒有對話框', (tester) async {
      await pumpReport(tester, report(dream: false));
      expect(find.byKey(const Key('report-dream')), findsNothing);
      expect(find.byType(DreamBubble), findsNothing);
    });
  });
}

String? textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data;
