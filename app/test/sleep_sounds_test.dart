// 助眠聲音（2026-11-12 定案）。
//
// 守的是壞掉時不會報錯的地方：
// - 記住上次選的聲音與時間；存了怪值要退回預設 30 分鐘，不是 0
// - 播多久、淡出多久由 Dart 決定、原封不動傳給原生端
// - 按 Out of bed、按 Cancel 都要停聲音（不停的話會整晚播到時間到）
// - 正在播的時候換聲音要照新的重播
import 'package:app/services/bed_marks.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/sleep_sounds.dart';
import 'package:app/screens/sleep_mode_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePlayer implements SleepSoundPlayer {
  final List<(SleepSound, Duration, Duration)> played = [];
  int stops = 0;
  DateTime? ends;

  @override
  Future<void> play(SleepSound sound, Duration length, Duration fade) async =>
      played.add((sound, length, fade));
  @override
  Future<void> stop() async => stops++;
  @override
  Future<DateTime?> endsAt() async => ends;
}

DateTime at(int h, [int m = 0]) => DateTime(2026, 11, 12, h, m);

void main() {
  group('設定', () {
    test('預設 Rain、30 分鐘；存了就記得', () async {
      final s = SleepSoundSettings(InMemoryKeyValueStore());
      expect(await s.sound(), SleepSound.rain);
      expect(await s.minutes(), 30);
      await s.save(SleepSound.ocean, 60);
      expect(await s.sound(), SleepSound.ocean);
      expect(await s.minutes(), 60);
    });

    test('⚠️ 存了不在選項裡的分鐘數 → 退回 30，不是 0', () async {
      final kv = InMemoryKeyValueStore();
      await kv.setString('sleep_sound_minutes', '7');
      expect(await SleepSoundSettings(kv).minutes(), 30);
    });

    test('播多久、淡出 1 分鐘原封不動交給原生端', () async {
      final kv = InMemoryKeyValueStore();
      final p = FakePlayer();
      final c = SleepSoundsController(
        settings: SleepSoundSettings(kv),
        player: p,
      );
      await SleepSoundSettings(kv).save(SleepSound.brown, 15);
      expect(await c.play(at(23)), at(23, 15));
      expect(p.played.single, (
        SleepSound.brown,
        const Duration(minutes: 15),
        const Duration(minutes: 1),
      ));
    });
  });

  group('睡覺畫面那一列', () {
    late InMemoryKeyValueStore kv;
    late FakePlayer player;
    late BedMarkStore store;
    var now = at(23, 40);

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      kv = InMemoryKeyValueStore();
      player = FakePlayer();
      store = BedMarkStore(kv);
      now = at(23, 40);
      await store.markStart(now);
      await tester.pumpWidget(
        MaterialApp(
          home: SleepModeScreen(
            store: store,
            startAt: now,
            clock: () => now,
            sounds: SleepSoundsController(
              settings: SleepSoundSettings(kv),
              player: player,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    String detail(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('sleep-sounds-detail'))).data!;

    testWidgets('按播放 → 播；再按 → 停', (tester) async {
      await pump(tester);
      expect(find.text('Sleep sounds'), findsOneWidget);
      expect(detail(tester), 'Rain · 30 min');
      await tester.tap(find.byKey(const Key('sleep-sounds-play')));
      await settle(tester);
      expect(player.played, hasLength(1));
      expect(detail(tester), 'Rain · until 00:10');
      await tester.tap(find.byKey(const Key('sleep-sounds-play')));
      await settle(tester);
      expect(player.stops, 1);
      expect(detail(tester), 'Rain · 30 min');
    });

    testWidgets('喇叭鈕選 Ocean、60 分鐘 → 記住；正在播就照新的重播', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('sleep-sounds-play')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('sleep-sounds-pick')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('sound-ocean')));
      await tester.tap(find.byKey(const Key('sound-min-60')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('sound-done')));
      await settle(tester);
      expect(await SleepSoundSettings(kv).sound(), SleepSound.ocean);
      expect(await SleepSoundSettings(kv).minutes(), 60);
      expect(player.played.last.$1, SleepSound.ocean);
      expect(player.played.last.$2, const Duration(minutes: 60));
      expect(detail(tester), 'Ocean · until 00:40');
    });

    testWidgets('⚠️ 按 Out of bed → 聲音要停', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('sleep-sounds-play')));
      await settle(tester);
      now = at(23, 55);
      await tester.tap(find.byKey(const Key('sleep-out-of-bed')));
      await settle(tester);
      expect(player.stops, 1);
    });

    testWidgets('⚠️ 按 Cancel → 聲音要停', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('sleep-cancel')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('sleep-cancel-confirm')));
      await settle(tester);
      expect(player.stops, 1);
    });

    testWidgets('打開畫面時已經在播（例如 App 重開）→ 顯示停止鈕與結束時間', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final kv2 = InMemoryKeyValueStore();
      final p = FakePlayer()..ends = at(0, 5).add(const Duration(days: 1));
      await tester.pumpWidget(
        MaterialApp(
          home: SleepModeScreen(
            store: BedMarkStore(kv2),
            startAt: at(23, 30),
            clock: () => at(23, 50),
            sounds: SleepSoundsController(
              settings: SleepSoundSettings(kv2),
              player: p,
            ),
          ),
        ),
      );
      await settle(tester);
      expect(detail(tester), 'Rain · until 00:05');
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    });
  });
}
