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
      expect(find.text(kDreamBubbleText), findsOneWidget);
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

    testWidgets('⚠️ 雲朵不蓋到小狗的臉（實機截圖抓到過：雲朵左邊蓋住半張臉）', (tester) async {
      // 實機的大小（三星，1080×2340）
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            repository: _Repo(withDream),
            bedMarks: BedMarkStore(kv),
            alarmScheduler: _NoAlarm(),
            clock: () => DateTime(2026, 11, 13, 9),
          ),
        ),
      ));
      await frames(tester);
      final cloud = tester.getRect(find.byKey(const Key('dream-bubble')));
      final pet = tester.getRect(find.byKey(const Key('home-pet')));
      // 小狗的頭在圖的左半邊，右緣大約就在中線（2026-11-13 實機截圖量的）
      expect(cloud.left, greaterThan(pet.center.dx + 8));
      expect(cloud.right, lessThanOrEqualTo(tester.view.physicalSize.width / 2.625));
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

  group('雲朵', () {
    Future<void> pumpBubble(WidgetTester tester, {bool compact = false, String? asset}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: DreamBubble(
              onTap: () {},
              compact: compact,
              cloudAsset: asset ?? kDreamCloudAsset,
            ),
          ),
        ),
      ));
      // 讀資產是真的 I/O，假時鐘底下要 runAsync 才會回來
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await frames(tester, 3);
    }

    testWidgets('預設畫雲朵圖，字疊在雲身上；看過之後只剩小雲、不寫字', (tester) async {
      await pumpBubble(tester);
      expect(find.byKey(const Key('dream-cloud')), findsOneWidget);
      expect(find.text(kDreamBubbleText), findsOneWidget);
      final cloud = tester.getRect(find.byKey(const Key('dream-cloud')));
      final text = tester.getRect(find.byKey(const Key('dream-bubble-text')));
      expect(cloud.contains(text.topLeft) && cloud.contains(text.bottomRight), isTrue,
          reason: '字不能跑出雲外');

      await pumpBubble(tester, compact: true);
      expect(find.byKey(const Key('dream-bubble-compact')), findsOneWidget);
      expect(find.text(kDreamBubbleText), findsNothing);
    });

    testWidgets('⚠️ 雲朵圖讀不到 → 退回程式畫的對話框，字還在、不報錯', (tester) async {
      await pumpBubble(tester, asset: 'assets/nope.png');
      expect(find.text('$kDreamBubbleText 💭'), findsOneWidget);
      expect(tester.takeException(), isNull);
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
      // 報告用小雲：大的會蓋到分數圓環
      final cloud = tester.getRect(find.byKey(const Key('report-dream')));
      final ring = tester.getRect(find.byKey(const Key('report-score')));
      expect(cloud.overlaps(ring), isFalse);
      await tester.tap(find.byKey(const Key('report-dream')));
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
