// 隊友的 2D 分層寵物（OneDrive pet_preview_multi_v4_5_10，2026-11-12 搬入）。
// 與原版的差別只有：缺圖時改畫 bored（見 PetDefinition.resolve）。
// 座標、尺寸、定位點一律不動——那些是人工對好的。
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
    this.blinkSpecs = const {},
  });

  final String id;
  final String label;
  final Map<PetMood, PetPoseAssets> poses;
  final Map<PetMood, AnimationProfile> animations;
  final Map<PetMood, Map<AccessorySlot, AccessoryAnchor>> anchors;
  final Map<PetMood, BlinkSpec> blinkSpecs;

  /// 這個心情實際要畫哪一組圖。
  ///
  /// ⚠️ **缺圖一律畫 bored，絕不畫 happy**（隊友原版退回 happy；接進 App 時改掉）。
  /// 把焦慮、疲倦的夜晚畫成開心的狗，正是紅線 5 要防的「不管怎樣都給獎勵」。
  /// 動畫參數與衣服定位點也跟著用 bored 的——那兩樣是照各組圖的座標調的，
  /// 拿 tired 的參數去動 bored 的圖，頭會轉到錯的角度。
  PetMood resolve(PetMood mood) =>
      poses.containsKey(mood) ? mood : PetMood.bored;

  PetPoseAssets poseFor(PetMood mood) => poses[resolve(mood)]!;

  bool hasDedicatedPose(PetMood mood) => poses.containsKey(mood);

  AnimationProfile animationFor(PetMood mood) => animations[resolve(mood)]!;

  BlinkSpec? blinkFor(PetMood mood) => blinkSpecs[resolve(mood)];

  AccessoryAnchor anchorFor(PetMood mood, AccessorySlot slot) {
    return anchors[resolve(mood)]?[slot] ??
        const AccessoryAnchor(position: Offset(256, 160), scale: 0.28);
  }
}

class AccessoryDefinition {
  const AccessoryDefinition({
    required this.id,
    required this.label,
    required this.slot,
    required this.assetPath,
  });

  final String id;
  final String label;
  final AccessorySlot slot;
  final String assetPath;
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
