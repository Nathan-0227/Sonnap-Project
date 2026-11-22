// 「最近一晚」接到畫面上（2026-11-22，甲-2）：首頁與助理頁標題列講同一晚、同一個心情。
//
// 用真的打包檔，/home 給「打包檔最後一晚的隔天」那一晚（tired、63 分）。
// 守的東西（放回錯誤驗證過會紅）：
//   1. 首頁的寵物、分數卡是 /home 那一晚的（不是打包檔那一晚）
//   2. refresh 之後首頁換成新的那一晚，而且換的時候不閃讀取中的轉圈
//   3. 助理頁標題列跟著 refresh 換心情

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/sleep_session.dart';
import 'package:app/screens/assistant_screen.dart';
import 'package:app/screens/home_screen.dart';
import 'package:app/services/alarm.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/latest_night.dart';
import 'package:app/services/sleep_repository.dart';
import 'package:app/widgets/home_pet.dart';

class _Repo implements SleepRepository {
  final SleepSession s;
  _Repo(this.s);
  @override
  Future<SleepSession> load() async => s;
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

void main() {
  late SleepSession payload;
  late String tonight; // 打包檔最後一晚的隔天
  late DateTime now;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    payload = SleepSession.fromJson(
        jsonDecode(await rootBundle.loadString(AssetSleepRepository.assetPath)) as Map<String, dynamic>);
    final last = DateTime.parse(payload.history.last.date);
    final next = last.add(const Duration(days: 1));
    now = DateTime(next.year, next.month, next.day, 13);
    tonight = '${next.year.toString().padLeft(4, '0')}-${next.month.toString().padLeft(2, '0')}'
        '-${next.day.toString().padLeft(2, '0')}';
  });

  Map<String, dynamic> home(String mood) => {
        'date': tonight,
        'status': {'pet_mood': mood, 'mood_driver': 'wearable'},
        'scoring': {'final_score': 62.9, 'final_quality': 'Poor'},
        'metrics': {'sleep_duration_minutes': 197.0, 'sleep_efficiency': 98.0},
        'behavior': {},
      };

  Future<void> pumpHome(WidgetTester tester, LatestNightRepository repo) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeScreen(
          repository: repo,
          bedMarks: BedMarkStore(InMemoryKeyValueStore()),
          alarmScheduler: _NoAlarm(),
          clock: () => now,
        ),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  String? petMood(WidgetTester tester) => tester.widget<HomePet>(find.byType(HomePet).first).mood;

  testWidgets('首頁的寵物、分數卡是 /home 那一晚的', (tester) async {
    final repo = LatestNightRepository(base: _Repo(payload), fetchNight: (d) async => home('tired'), clock: () => now);
    await pumpHome(tester, repo);
    expect(petMood(tester), 'tired');
    expect(find.descendant(of: find.byKey(const Key('score-card')), matching: find.text('63')), findsWidgets);
  });

  testWidgets('refresh → 首頁換成新的那一晚，換的時候不閃讀取中', (tester) async {
    Map<String, dynamic>? answer; // 一開始 /home 還沒有這一晚 → 打包檔
    final repo = LatestNightRepository(
        base: _Repo(payload), fetchNight: (d) async => d == tonight ? answer : null, clock: () => now);
    await pumpHome(tester, repo);
    expect(petMood(tester), payload.status.petMood);

    answer = home('anxious');
    repo.refresh();
    // 整頁閃成讀取中的話分數卡會不見（首頁別張卡自己的小轉圈不算）
    var cardAlways = true;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      cardAlways &= find.byKey(const Key('score-card')).evaluate().isNotEmpty;
    }
    expect(petMood(tester), 'anxious');
    expect(cardAlways, isTrue, reason: '重讀時整頁不該先變成讀取中的轉圈');
  });

  testWidgets('助理頁標題列跟著 refresh 換心情', (tester) async {
    Map<String, dynamic>? answer;
    final repo = LatestNightRepository(
        base: _Repo(payload), fetchNight: (d) async => d == tonight ? answer : null, clock: () => now);
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AssistantScreen(
          username: 'Nathan',
          store: InMemoryKeyValueStore(),
          clock: () => now,
          petMood: () async => (await repo.load()).status.petMood,
          moodChanges: repo,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    answer = home('tired');
    repo.refresh();
    await tester.pump();
    await tester.pump();
    expect(find.text('Feeling sleepy'), findsOneWidget);
  });
}
