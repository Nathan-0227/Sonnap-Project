import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../pet2d/pet_catalog.dart';
import '../pet2d/pet_models.dart';
import '../pet2d/pet_widget.dart';
import 'pet_mood_animation.dart';

/// 首頁的寵物「插槽」：外面只給心情與衣服，裡面畫哪一套寵物由這裡決定。
///
/// 現在畫的是隊友的 2D 分層小狗（`lib/pet2d/`）。換寵物時只改這個檔案，
/// 首頁、晚上版、睡覺畫面都不用動（2026-11-12 定案）。
///
/// 退路由好到壞（2D 讀不到 → Lottie → 爪印），Lottie 一個都不刪。
///
/// ⚠️ 心情照抄後端的 `pet_mood`，這裡不推。不認得的值一律當 bored——
///    把未知狀態畫成最好的狀態，正是紅線 5 要防的事。
class HomePet extends StatefulWidget {
  /// 後端給的心情字串（happy / bored / tired / anxious）。
  final String? mood;
  final double size;

  /// 衣櫃裡穿的那一件（後端的 item_id）與它的 emoji。
  /// 有真圖的三件畫真圖，其餘疊 emoji（使用者決定：看得到比好看重要）。
  final String? equippedItemId;
  final String? accessoryEmoji;

  /// 成長階段（後端依等級決定），只換成大小。
  final String? growthStage;

  /// 動畫速度倍率。晚上版用 < 1 表現想睡。
  final double speed;

  const HomePet({
    super.key,
    required this.mood,
    this.size = 220,
    this.equippedItemId,
    this.accessoryEmoji,
    this.growthStage,
    this.speed = 1.0,
  });

  @override
  State<HomePet> createState() => _HomePetState();
}

/// 後端心情字串 → 2D 寵物的心情。不認得的一律 bored。
PetMood petMoodFromBackend(String? mood) => switch (mood) {
      'happy' => PetMood.happy,
      'tired' => PetMood.tired,
      'anxious' => PetMood.anxious,
      _ => PetMood.bored,
    };

/// 衣櫃的 item_id（`game/inventory.py`）→ 隊友畫好的衣服圖。
/// 不在表上的（bow、top_hat、crown）沒有圖，改疊 emoji。
const Map<String, String> kLayeredAccessoryFor = {
  'cap': 'sleep_hat',
  'glasses': 'round_glasses',
  'scarf': 'night_scarf',
};

AccessoryDefinition? layeredAccessoryFor(String? itemId) {
  final id = kLayeredAccessoryFor[itemId];
  if (id == null) return null;
  for (final a in accessories) {
    if (a.id == id) return a;
  }
  return null;
}

double _growthScale(String? stage) => switch (stage) {
      'baby' => 0.85,
      'adult' => 1.12,
      _ => 1.0,
    };

class _HomePetState extends State<HomePet> {
  /// 2D 的圖讀不到時改走 Lottie。
  bool _layeredMissing = false;

  @override
  void initState() {
    super.initState();
    _checkLayeredAssets();
  }

  Future<void> _checkLayeredAssets() async {
    final pose = dog01.poseFor(petMoodFromBackend(widget.mood));
    try {
      await rootBundle.load(pose.body.assetPath);
    } catch (_) {
      if (mounted) setState(() => _layeredMissing = true);
    }
  }

  Widget _lottieFallback() {
    final visual = petMoodVisual(widget.mood);
    return Lottie.asset(
      visual.assetPath,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stack) => SizedBox.square(
        dimension: widget.size,
        child: Icon(Icons.pets_rounded,
            color: Colors.white54, size: widget.size * 0.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layered = layeredAccessoryFor(widget.equippedItemId);
    final emoji = layered == null ? widget.accessoryEmoji : null;

    final Widget pet = _layeredMissing
        ? _lottieFallback()
        : LayeredPet(
            pet: dog01,
            mood: petMoodFromBackend(widget.mood),
            accessory: layered,
            size: widget.size,
            speed: widget.speed,
          );

    return SizedBox.square(
      key: const Key('home-pet'),
      dimension: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Transform.scale(scale: _growthScale(widget.growthStage), child: pet),
          if (emoji != null)
            Positioned(
              top: widget.size * 0.02,
              child: Text(
                emoji,
                key: const Key('pet-accessory'),
                style: TextStyle(fontSize: widget.size * 0.2),
              ),
            ),
        ],
      ),
    );
  }
}
