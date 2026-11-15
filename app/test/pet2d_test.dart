// 隊友的 2D 分層寵物（lib/pet2d/，2026-11-15 換成 v4.6.45：小狗四種心情都有圖、多一隻貓）。
//
// 守的是「壞掉時不會報錯」的地方：隊友原版在缺圖時退回 happy，
// 結果焦慮、疲倦的夜晚畫的是一隻開心的狗——畫面完全正常、沒有任何錯誤訊息。
// 那正是紅線 5 要防的「不管怎樣都給獎勵」。現在兩隻都有四種心情的圖，
// 所以退路規則改用一隻**故意缺圖**的假寵物驗；並守「每隻、每種心情都畫自己的圖」。
import 'package:app/pet2d/pet_catalog.dart';
import 'package:app/pet2d/pet_models.dart';
import 'package:app/services/pet_choice.dart';
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

/// 只有 happy、bored 兩組圖的假寵物（照小狗的圖），用來驗退路。
final _partial = PetDefinition(
  id: 'partial',
  label: 'Partial',
  poses: {
    PetMood.happy: dog01.poseFor(PetMood.happy),
    PetMood.bored: dog01.poseFor(PetMood.bored),
  },
  animations: {
    PetMood.happy: dog01.animationFor(PetMood.happy),
    PetMood.bored: dog01.animationFor(PetMood.bored),
    PetMood.anxious: dog01.animationFor(PetMood.anxious),
  },
  anchors: {
    PetMood.happy: {
      for (final s in AccessorySlot.values)
        s: dog01.anchorFor(PetMood.happy, s),
    },
    PetMood.bored: {
      for (final s in AccessorySlot.values)
        s: dog01.anchorFor(PetMood.bored, s),
    },
  },
);

Future<List<String>> _drawnPaths(WidgetTester tester, String mood) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: HomePet(mood: mood)),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return _paths(tester);
}

List<String> _paths(WidgetTester tester) => tester
    .widgetList<Image>(find.byType(Image))
    .map((i) => i.image)
    .whereType<AssetImage>()
    .map((a) => a.assetName)
    .toList();

void main() {
  tearDown(() => PetChoice.current.value = PetSpecies.dog);

  group('缺圖的心情一律畫 bored，絕不畫 happy（用故意缺圖的假寵物驗）', () {
    for (final mood in [PetMood.tired, PetMood.anxious]) {
      test('$mood：每一層都是 bored 的圖', () {
        expect(_partial.hasDedicatedPose(mood), isFalse, reason: '反向對照：真的缺圖');
        expect(_partial.resolve(mood), PetMood.bored);
        for (final path in _layerPaths(_partial.poseFor(mood))) {
          expect(path, contains('/bored/'), reason: path);
          expect(path, isNot(contains('/happy/')), reason: path);
        }
      });

      test('$mood：動畫與衣服定位點也跟著用 bored 的（就算那個心情自己有動畫參數）', () {
        // 定位點與動畫是照各組圖的座標調的，拿別組的參數動 bored 的圖，頭會轉錯、帽子會飄
        expect(
          identical(
            _partial.animationFor(mood),
            _partial.animationFor(PetMood.bored),
          ),
          isTrue,
        );
        for (final slot in AccessorySlot.values) {
          expect(
            _partial.anchorFor(mood, slot).position,
            _partial.anchorFor(PetMood.bored, slot).position,
            reason: '$slot',
          );
        }
      });
    }
  });

  group('兩隻寵物的四種心情都畫自己的圖（v4.6.45）', () {
    for (final pet in [dog01, cat01]) {
      for (final mood in PetMood.values) {
        test('${pet.id} $mood', () {
          expect(pet.hasDedicatedPose(mood), isTrue);
          for (final path in _layerPaths(pet.poseFor(mood))) {
            expect(path, contains('/${pet.id}/'), reason: path);
            expect(path, contains('/${mood.name}/'), reason: path);
          }
        });
      }
    }
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

  testWidgets('畫面上：anxious 的小狗畫 anxious 的圖，沒有任何一張 happy 的圖', (tester) async {
    final paths = await _drawnPaths(tester, 'anxious');
    expect(paths, isNotEmpty, reason: '要真的畫出 2D 小狗，這條才有意義');
    expect(paths.where((p) => p.contains('/happy/')), isEmpty);
    expect(paths.where((p) => p.contains('/dog01/anxious/')), isNotEmpty);
  });

  testWidgets('選貓：首頁寵物換成貓；換回小狗也跟著換', (tester) async {
    PetChoice.current.value = PetSpecies.cat;
    var paths = await _drawnPaths(tester, 'tired');
    expect(paths.where((p) => p.contains('/cat01/tired/')), isNotEmpty);
    expect(paths.where((p) => p.contains('/dog01/')), isEmpty);
    PetChoice.current.value = PetSpecies.dog;
    await tester.pump(const Duration(milliseconds: 100));
    paths = _paths(tester);
    expect(paths.where((p) => p.contains('/dog01/tired/')), isNotEmpty);
    expect(paths.where((p) => p.contains('/cat01/')), isEmpty);
  });

  test('選寵物：不認得的值一律當小狗（預設）', () {
    expect(PetChoice.fromId('cat'), PetSpecies.cat);
    expect(PetChoice.fromId('dog'), PetSpecies.dog);
    for (final v in [null, '', 'Cat', 'dragon']) {
      expect(PetChoice.fromId(v), PetSpecies.dog, reason: '$v');
    }
  });
}
