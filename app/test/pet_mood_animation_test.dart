// 寵物心情 → 動畫資產對應的驗收測試。
//
// 這支測試守的不是「畫面好不好看」，是兩件會安靜壞掉的事：
//
//   1. 四個心情必須對到四個**不同**的資產。回歸成同一個檔（也就是修正
//      之前那個寫死 happy_dog.json 的狀態）不會有任何錯誤訊息，
//      只會在 demo 當天變成「文字寫 Anxious、圖在搖尾巴」。
//
//   2. 未知的心情不得被當成 happy。把未知狀態顯示成最好的狀態，
//      正是 CLAUDE.md 紅線 5 要防的「不管怎樣都給獎勵」。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/widgets/pet_mood_animation.dart';

void main() {
  // README 的 data contract 定義的四個合法值
  const moods = <String>['happy', 'bored', 'tired', 'anxious'];

  test('四個心情各自對到不同的資產路徑', () {
    final paths = moods.map((m) => petMoodVisual(m).assetPath).toList();

    expect(
      paths.toSet().length,
      moods.length,
      reason: '有心情共用了同一個動畫檔，畫面就分不出差別了：$paths',
    );

    // 每個路徑都要在宣告過的資產目錄底下，否則打包不進去
    for (final p in paths) {
      expect(p, startsWith('assets/animations/'));
      expect(p, endsWith('.json'));
    }
  });

  test('happy 用原色，其餘三個心情都有濾鏡', () {
    // happy 指向現有那個檔，本來就不需要處理
    expect(petMoodVisual('happy').fallbackFilter, isNull);

    // 其餘三個在專屬資產到位前，要靠濾鏡跟 happy 區分開來
    for (final m in ['bored', 'tired', 'anxious']) {
      expect(
        petMoodVisual(m).fallbackFilter,
        isA<ColorFilter>(),
        reason: '$m 沒有濾鏡的話，資產到位前會跟 happy 長得一模一樣',
      );
    }
  });

  test('未知心情退到 bored，不得退到 happy（紅線 5）', () {
    for (final unknown in <String?>[null, '', 'sleepy', 'ecstatic', '???']) {
      final v = petMoodVisual(unknown);
      expect(
        v.assetPath,
        isNot(petMoodVisual('happy').assetPath),
        reason: '未知心情 $unknown 退到了 happy——'
            '把不知道的狀態顯示成最好的狀態就是紅線 5 說的那種假獎勵',
      );
      expect(v.assetPath, petMoodVisual('bored').assetPath);
    }
  });

  test('大小寫不影響查表', () {
    expect(petMoodVisual('ANXIOUS').assetPath, petMoodVisual('anxious').assetPath);
    expect(petMoodVisual('Tired').assetPath, petMoodVisual('tired').assetPath);
  });

  test('退路資產是實際存在的那一個檔', () {
    // kPetFallbackAnimation 是三層退路的第二層，這個檔一定要存在，
    // 否則所有非 happy 的心情都會掉到最後的靜態 icon
    expect(kPetFallbackAnimation, petMoodVisual('happy').assetPath);
  });
}
