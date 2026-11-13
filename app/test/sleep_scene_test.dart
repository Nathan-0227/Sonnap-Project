// 睡覺畫面的場景（2026-11-14）：房間＋睡覺小狗的循環 GIF 鋪滿，剛按 Start Sleep 先播過場。
// 守：缺檔退回原本的臥室＋程式小狗、減少動態效果用靜止圖且不播過場、三個檔都在而且不太大。
import 'dart:io';

import 'package:app/screens/sleep_mode_screen.dart';
import 'package:app/screens/wake_up_screen.dart' show gifDurationFromBytes;
import 'package:app/services/bed_marks.dart';
import 'package:app/services/key_value_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester,
      {bool intro = false, bool reduce = false, String scene = kSleepLoopGif}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: SleepModeScreen(
          store: BedMarkStore(InMemoryKeyValueStore()),
          startAt: DateTime(2026, 11, 13, 23, 40),
          clock: () => DateTime(2026, 11, 13, 23, 41),
          playIntro: intro,
          sceneAsset: scene,
        ),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('有場景：鋪滿、小狗在場景裡（不另外畫程式小狗）', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('sleep-scene')), findsOneWidget);
    expect(find.byKey(const Key('sleeping-pet')), findsNothing);
  });

  testWidgets('缺檔 → 退回臥室背景＋程式小狗，不報錯', (tester) async {
    await pump(tester, scene: 'assets/pets/dog01/nope.gif');
    expect(find.byKey(const Key('sleep-scene')), findsNothing);
    expect(find.byKey(const Key('sleeping-pet')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('減少動態效果 → 靜止圖、不播過場', (tester) async {
    await pump(tester, intro: true, reduce: true);
    expect(find.byKey(const Key('sleep-intro')), findsNothing);
    final img = tester.widget<Image>(find.byKey(const Key('sleep-scene')));
    expect((img.image as AssetImage).assetName, kSleepStill);
  });

  testWidgets('過場點一下跳過，控制項淡入', (tester) async {
    await pump(tester, intro: true);
    expect(find.byKey(const Key('sleep-intro')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sleep-intro')));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(const Key('sleep-intro')), findsNothing);
    final fade = tester.widget<AnimatedOpacity>(find.ancestor(
        of: find.byKey(const Key('sleep-cancel')), matching: find.byType(AnimatedOpacity)).first);
    expect(fade.opacity, 1);
  });

  test('三個檔都在、不太大；過場約 4 秒、播一次', () {
    for (final (path, maxMb) in [
      ('assets/pets/dog01/sleeping_loop.gif', 4.0),
      ('assets/pets/dog01/go_to_sleep.gif', 4.0),
      ('assets/pets/dog01/sleeping_still.jpg', 0.5),
    ]) {
      final f = File(path);
      expect(f.existsSync(), isTrue, reason: path);
      expect(f.lengthSync() / 1e6, lessThan(maxMb), reason: path);
    }
    final d = gifDurationFromBytes(File('assets/pets/dog01/go_to_sleep.gif').readAsBytesSync())!;
    expect(d.inMilliseconds, inInclusiveRange(3800, 4200));
  });
}
