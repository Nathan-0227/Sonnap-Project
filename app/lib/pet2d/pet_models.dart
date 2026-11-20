// 隊友的 2D 分層寵物資料模型（pet_preview v4.6.45，2026-11-15 換版）。
// 與原版的差別：缺圖的心情一律退回 **bored**，原版退回 happy（resolve()）。
// 焦慮、疲倦的晚上畫成開心的寵物，正是紅線 5 要防的事；pet2d_test.dart 守著。
import 'package:flutter/material.dart';

enum PetMood { happy, bored, tired, anxious }

enum AccessorySlot { head, face, neck }

extension PetMoodLabel on PetMood {
  String get label {
    switch (this) {
      case PetMood.happy:
        return 'Happy';
      case PetMood.bored:
        return 'Bored';
      case PetMood.tired:
        return 'Tired';
      case PetMood.anxious:
        return 'Anxious';
    }
  }
}

class LayerSpec {
  const LayerSpec({
    required this.assetPath,
    required this.position,
    required this.sourceAnchor,
    required this.sourceSize,
    required this.sourceScale,
    this.rotationDeg = 0,
  });

  final String assetPath;
  final Offset position;
  final Offset sourceAnchor;
  final Size sourceSize;
  final double sourceScale;
  final double rotationDeg;
}

class PetPoseAssets {
  const PetPoseAssets({
    required this.body,
    required this.head,
    required this.earLeft,
    required this.earRight,
    required this.tail,
    this.effect,
    this.designSize = 512,
  });

  final LayerSpec body;
  final LayerSpec head;
  final LayerSpec earLeft;
  final LayerSpec earRight;
  final LayerSpec tail;
  final LayerSpec? effect;
  final double designSize;
}

class AnimationProfile {
  const AnimationProfile({
    required this.durationMs,
    required this.tailBaseDeg,
    required this.tailAmplitudeDeg,
    required this.tailCycles,
    required this.bodyLift,
    required this.bodyCycles,
    required this.headBaseDeg,
    required this.headAmplitudeDeg,
    required this.headCycles,
    required this.earLeftBaseDeg,
    required this.earLeftAmplitudeDeg,
    required this.earLeftCycles,
    required this.earRightBaseDeg,
    required this.earRightAmplitudeDeg,
    required this.earRightCycles,
    this.headDrop = 0,
    this.headDropCycles = 1,
  });

  final int durationMs;
  final double tailBaseDeg;
  final double tailAmplitudeDeg;
  final double tailCycles;
  final double bodyLift;
  final double bodyCycles;
  final double headBaseDeg;
  final double headAmplitudeDeg;
  final double headCycles;
  final double earLeftBaseDeg;
  final double earLeftAmplitudeDeg;
  final double earLeftCycles;
  final double earRightBaseDeg;
  final double earRightAmplitudeDeg;
  final double earRightCycles;
  final double headDrop;
  final double headDropCycles;
}

class AccessoryAnchor {
  const AccessoryAnchor({
    required this.position,
    required this.scale,
    this.rotationDeg = 0,
  });

  final Offset position;
  final double scale;
  final double rotationDeg;
}

class BlinkSpec {
  const BlinkSpec({
    required this.faceColor,
    required this.lineColor,
    required this.leftEye,
    required this.rightEye,
  });

  final Color faceColor;
  final Color lineColor;
  final Offset leftEye;
  final Offset rightEye;
}

class PetDefinition {
  const PetDefinition({
    required this.id,
    required this.label,
    required this.poses,
    required this.animations,
    required this.anchors,
    this.accessoryAnchors = const {},
    this.blinkSpecs = const {},
  });

  final String id;
  final String label;
  final Map<PetMood, PetPoseAssets> poses;
  final Map<PetMood, AnimationProfile> animations;
  final Map<PetMood, Map<AccessorySlot, AccessoryAnchor>> anchors;

  /// 某一件衣服自己的定位點（隊友 v4.6.48，貝雷帽與紅蝴蝶結逐姿勢對好的）。
  /// 鍵是衣服的圖檔 id；沒列到的衣服用上面那組插槽錨點。
  final Map<String, Map<PetMood, AccessoryAnchor>> accessoryAnchors;
  final Map<PetMood, BlinkSpec> blinkSpecs;

  /// 這個心情有自己的圖就用；沒有就整組改用 bored（圖、動畫、衣服定位點、眨眼一起換）。
  /// ⚠️ 不可退回 happy。動畫參數與衣服定位點也跟著用 bored 的——那兩樣是照各組圖的座標調的。
  PetMood resolve(PetMood mood) =>
      poses.containsKey(mood) ? mood : PetMood.bored;

  PetPoseAssets poseFor(PetMood mood) => poses[resolve(mood)]!;

  bool hasDedicatedPose(PetMood mood) => poses.containsKey(mood);

  AnimationProfile animationFor(PetMood mood) =>
      animations[resolve(mood)] ?? animations[PetMood.bored]!;

  BlinkSpec? blinkFor(PetMood mood) => blinkSpecs[resolve(mood)];

  AccessoryAnchor anchorFor(PetMood mood, AccessorySlot slot,
      {String? accessoryId}) {
    final specific =
        accessoryId == null ? null : accessoryAnchors[accessoryId]?[resolve(mood)];
    if (specific != null) return specific;
    return anchors[resolve(mood)]?[slot] ??
        const AccessoryAnchor(position: Offset(256, 160), scale: 0.28);
  }
}

/// 一件衣服在某一個姿勢上怎麼戴（相對於插槽錨點）。
/// [fit]：大小，以底邊中點縮放；[drop]：往下移（錨點框邊長的比例，負的往上）；
/// [dx]：往右移（同一個比例，負的往左）；[rotationDeg]：再多轉幾度。
class AccessoryFit {
  const AccessoryFit({
    this.fit = 1,
    this.drop = 0,
    this.dx = 0,
    this.rotationDeg = 0,
  });

  final double fit;
  final double drop;
  final double dx;
  final double rotationDeg;
}

class AccessoryDefinition {
  const AccessoryDefinition({
    required this.id,
    required this.label,
    required this.slot,
    required this.assetPath,
    this.fit = 1,
    this.drop = 0,
    this.shadowAt,
    this.poseFits = const {},
  });

  final String id;
  final String label;
  final AccessorySlot slot;
  final String assetPath;

  /// 這一件相對於插槽錨點的大小（錨點是照睡帽、圍巾那幾件對的）。
  /// 縮放以**底邊中點**為準，帽子照樣坐在頭頂、只是變窄，兩邊的耳朵露出來。
  /// 2026-11-19 使用者：禮帽、皇冠太大、蓋住耳朵 → 那兩頂 < 1。
  final double fit;

  /// 往下移多少（錨點框邊長的比例）；讓硬的帽子坐進兩耳之間，不是浮在頭頂上。
  final double drop;

  /// 帽子底下那道淡影子落在框高的哪裡（＝圖裡帽子的底邊，0–1）；null＝不畫。
  /// 硬帽子沒有影子看起來是「浮」在頭上（2026-11-19 使用者：很突兀）。
  final double? shadowAt;

  /// 依姿勢個別調整（2026-11-19 使用者逐格挑的），鍵是「寵物 id.心情」，例如 `dog01.happy`。
  /// 沒列到的姿勢用上面的 [fit]／[drop]。
  final Map<String, AccessoryFit> poseFits;

  AccessoryFit fitFor(String petId, PetMood mood) =>
      poseFits['$petId.${mood.name}'] ?? AccessoryFit(fit: fit, drop: drop);
}

class AccessoryTweak {
  const AccessoryTweak({
    this.dx = 0,
    this.dy = 0,
    this.scale = 1,
    this.rotationDeg = 0,
  });

  final double dx;
  final double dy;
  final double scale;
  final double rotationDeg;

  AccessoryTweak copyWith({
    double? dx,
    double? dy,
    double? scale,
    double? rotationDeg,
  }) {
    return AccessoryTweak(
      dx: dx ?? this.dx,
      dy: dy ?? this.dy,
      scale: scale ?? this.scale,
      rotationDeg: rotationDeg ?? this.rotationDeg,
    );
  }
}


/// Preview-only local adjustments to an individual pet layer. The rotation and
/// scale are relative to the baseline LayerSpec and animation multipliers.
class PetLayerTweak {
  const PetLayerTweak({
    this.dx = 0,
    this.dy = 0,
    this.scale = 1,
    this.rotationDeg = 0,
  });
  final double dx;
  final double dy;
  final double scale;
  final double rotationDeg;

  PetLayerTweak copyWith({
    double? dx,
    double? dy,
    double? scale,
    double? rotationDeg,
  }) => PetLayerTweak(
        dx: dx ?? this.dx,
        dy: dy ?? this.dy,
        scale: scale ?? this.scale,
        rotationDeg: rotationDeg ?? this.rotationDeg,
      );
}
