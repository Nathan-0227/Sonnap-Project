// 隊友的 2D 分層小狗（lib/pet2d/）接進 App 時改掉的那一條規則。
//
// 守的是「壞掉時不會報錯」的地方：隊友原版在缺圖時退回 happy，
// 結果焦慮、疲倦的夜晚畫的是一隻開心的狗——畫面完全正常、沒有任何錯誤訊息。
// 那正是紅線 5 要防的「不管怎樣都給獎勵」。
import 'package:app/pet2d/pet_catalog.dart';
import 'package:app/pet2d/pet_models.dart';
import 'package:app/widgets/home_pet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _layerPaths(PetPoseAssets p) => [
      p.body.assetPath,
      p.head.assetPath,
      p.earLeft.assetPath,
      p.earRight.assetPath,
      p.tail.assetPath,
      if (p.effect != null) p.effect!.assetPath,
    ];

void main() {
  group('缺圖的心情一律畫 bored，絕不畫 happy', () {
    for (final mood in [PetMood.tired, PetMood.anxious]) {
      test('$mood：每一層都是 bored 的圖', () {
        // 反向對照：這個心情真的沒有自己的圖。等隊友補上之後這條會紅，
        // 那時把這個心情從清單拿掉即可。
        expect(dog01.hasDedicatedPose(mood), isFalse);
        for (final path in _layerPaths(dog01.poseFor(mood))) {
          expect(path, contains('/bored/'), reason: path);
          expect(path, isNot(contains('/happy/')), reason: path);
        }
      });

      test('$mood：動畫與衣服定位點也跟著用 bored 的', () {
        // 定位點是照各組圖的座標調的，拿 happy 的點套 bored 的圖，帽子會飄在空中。
        expect(identical(dog01.animationFor(mood),
            dog01.animationFor(PetMood.bored)), isTrue);
        for (final slot in AccessorySlot.values) {
          final a = dog01.anchorFor(mood, slot);
          final b = dog01.anchorFor(PetMood.bored, slot);
          expect(a.position, b.position, reason: '$slot');
        }
      });
    }

    test('happy、bored 有自己的圖（反向對照：上面那幾條不是假性通過）', () {
      expect(_layerPaths(dog01.poseFor(PetMood.happy)).first,
          contains('/happy/'));
      expect(_layerPaths(dog01.poseFor(PetMood.bored)).first,
          contains('/bored/'));
    });
  });

  group('後端心情字串 → 2D 心情', () {
    test('四個合法值照對', () {
      expect(petMoodFromBackend('happy'), PetMood.happy);
      expect(petMoodFromBackend('bored'), PetMood.bored);
      expect(petMoodFromBackend('tired'), PetMood.tired);
      expect(petMoodFromBackend('anxious'), PetMood.anxious);
    });

    test('不認得的一律 bored（不能是 happy）', () {
      for (final v in [null, '', 'Happy', 'sleepy']) {
        expect(petMoodFromBackend(v), PetMood.bored, reason: '$v');
      }
    });
  });

  testWidgets('畫面上：anxious 的寵物沒有任何一張 happy 的圖', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: HomePet(mood: 'anxious'))),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    final paths = tester
        .widgetList<Image>(find.byType(Image))
        .map((i) => i.image)
        .whereType<AssetImage>()
        .map((a) => a.assetName)
        .toList();
    expect(paths, isNotEmpty, reason: '要真的畫出 2D 小狗，這條才有意義');
    expect(paths.where((p) => p.contains('/happy/')), isEmpty);
  });
}
