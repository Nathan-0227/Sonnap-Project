import 'package:flutter/foundation.dart';

import '../pet2d/pet_catalog.dart';
import '../pet2d/pet_models.dart';
import 'key_value_store.dart';

/// 使用者選的寵物（2026-11-15 使用者定）：小狗或貓，**只存在手機上**、預設小狗。
///
/// - 設定頁的「Pet」那一列切換；首頁寵物插槽（`HomePet`）跟著它畫。
/// - 起床、等報告、睡覺這三個畫面的 GIF **只有小狗版**：選貓時改走它們本來就有的程式版退路
///   （裡面的寵物是 `HomePet`，所以是貓），不會出現貓變狗。
/// - 一週心情列、Insights 的心情、導覽列中間那顆的頭像也跟著換（`moodFaceAsset`，2026-11-22 補上貓頭）。
/// - 換手機或重裝就回到預設的小狗（使用者接受，好友頁沒有畫寵物、用不到後端）。
enum PetSpecies { dog, cat }

class PetChoice {
  PetChoice._();

  static const storeKey = 'pet_species';

  /// 全 App 共用的那一個選擇。讀不到手機儲存時維持預設的小狗。
  static final ValueNotifier<PetSpecies> current = ValueNotifier(
    PetSpecies.dog,
  );

  static bool get isCat => current.value == PetSpecies.cat;

  /// 不認得的值一律當小狗（預設），不會讓畫面空掉。
  static PetSpecies fromId(String? id) =>
      id == PetSpecies.cat.name ? PetSpecies.cat : PetSpecies.dog;

  static Future<void> load(KeyValueStore store) async {
    try {
      current.value = fromId(await store.getString(storeKey));
    } catch (_) {
      // 讀不到就維持預設
    }
  }

  static Future<void> choose(KeyValueStore store, PetSpecies species) async {
    current.value = species;
    try {
      await store.setString(storeKey, species.name);
    } catch (_) {
      // 存不進去也照樣換（這次開著的期間有效）
    }
  }
}

String petSpeciesLabel(PetSpecies s) => switch (s) {
  PetSpecies.dog => 'Dog',
  PetSpecies.cat => 'Cat',
};

/// 選的寵物 → 隊友的 2D 分層寵物。
PetDefinition petDefinitionFor(PetSpecies s) => switch (s) {
  PetSpecies.dog => dog01,
  PetSpecies.cat => cat01,
};
