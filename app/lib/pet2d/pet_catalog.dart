// 隊友的 2D 分層寵物圖層設定（pet_preview v4.5.10）。
// 與原版的差別：拿掉「tired／anxious 用 happy 的衣服定位點」那兩行
// （缺圖時整組改用 bored，見 PetDefinition.resolve）。
// tired／anxious 的動畫參數留著，等那兩組圖畫好就會用到。
import 'package:flutter/material.dart';

import 'pet_models.dart';

const _happyPose = PetPoseAssets(
  tail: LayerSpec(
    assetPath: 'assets/pets/dog01/happy/tail.png',
    position: Offset(349.19, 304.43),
    sourceAnchor: Offset(238.87, 1040.77),
    sourceSize: Size(1254, 1254),
    sourceScale: 15.0,
  ),
  body: LayerSpec(
    assetPath: 'assets/pets/dog01/happy/body.png',
    position: Offset(242.89, 289.36),
    sourceAnchor: Offset(627, 627),
    sourceSize: Size(1254, 1254),
    sourceScale: 32.0,
  ),
  earRight: LayerSpec(
    assetPath: 'assets/pets/dog01/happy/ear_right.png',
    position: Offset(187.05, 167.88),
    sourceAnchor: Offset(627, 1254),
    sourceSize: Size(1254, 1254),
    sourceScale: 12.26,
  ),
  earLeft: LayerSpec(
    assetPath: 'assets/pets/dog01/happy/ear_left.png',
    position: Offset(234.08, 180.19),
    sourceAnchor: Offset(627, 1254),
    sourceSize: Size(1254, 1254),
    sourceScale: 12.26,
  ),
  head: LayerSpec(
    assetPath: 'assets/pets/dog01/happy/head.png',
    position: Offset(193.98, 180.77),
    sourceAnchor: Offset(627, 627),
    sourceSize: Size(1254, 1254),
    sourceScale: 20.0,
  ),
);

// Bored pose rebuilt from the finalized separated source sheet.
// The six assets are exact crops from the approved Bored artwork, not AI-redrawn parts.
const _boredPose = PetPoseAssets(
  // v4.4 uses full 1024 x 1024 transparent layer canvases.
  // Every Bored part is already pre-aligned to the approved full pose,
  // so Flutter only needs to stack the layers and animate around pivots.
  designSize: 1024,
  tail: LayerSpec(
    assetPath: 'assets/pets/dog01/bored/tail.png',
    position: Offset(700, 748),
    sourceAnchor: Offset(700, 748),
    sourceSize: Size(1024, 1024),
    sourceScale: 100.0,
  ),
  body: LayerSpec(
    assetPath: 'assets/pets/dog01/bored/body.png',
    position: Offset(0, 0),
    sourceAnchor: Offset(0, 0),
    sourceSize: Size(1024, 1024),
    sourceScale: 100.0,
  ),
  earRight: LayerSpec(
    assetPath: 'assets/pets/dog01/bored/ear_right.png',
    position: Offset(465, 296),
    sourceAnchor: Offset(465, 296),
    sourceSize: Size(1024, 1024),
    sourceScale: 100.0,
  ),
  earLeft: LayerSpec(
    assetPath: 'assets/pets/dog01/bored/ear_left.png',
    // v4.4.4: nudge the corrected ear slightly inward and downward.
    position: Offset(202, 247),
    sourceAnchor: Offset(190, 238),
    sourceSize: Size(1024, 1024),
    sourceScale: 90.0,
  ),
  head: LayerSpec(
    assetPath: 'assets/pets/dog01/bored/head.png',
    position: Offset(310, 485),
    sourceAnchor: Offset(310, 485),
    sourceSize: Size(1024, 1024),
    sourceScale: 100.0,
  ),
  effect: LayerSpec(
    assetPath: 'assets/pets/dog01/bored/sigh_puff.png',
    position: Offset(0, 0),
    sourceAnchor: Offset(0, 0),
    sourceSize: Size(1024, 1024),
    sourceScale: 100.0,
  ),
);

const _happyAnimation = AnimationProfile(
  durationMs: 5000,
  tailBaseDeg: -6,
  tailAmplitudeDeg: 3,
  tailCycles: 6,
  bodyLift: 3,
  bodyCycles: 3,
  headBaseDeg: 12,
  headAmplitudeDeg: 1.2,
  headCycles: 2,
  earLeftBaseDeg: 2,
  earLeftAmplitudeDeg: 3.2,
  earLeftCycles: 3,
  earRightBaseDeg: -39,
  earRightAmplitudeDeg: 3.0,
  earRightCycles: 2,
);

const _boredAnimation = AnimationProfile(
  durationMs: 6400,
  tailBaseDeg: 0,
  tailAmplitudeDeg: 4.2,
  tailCycles: 1.05,
  bodyLift: 16.0,
  bodyCycles: 1,
  headBaseDeg: 0,
  headAmplitudeDeg: 2.6,
  headCycles: 0.92,
  earLeftBaseDeg: 0,
  earLeftAmplitudeDeg: 4.8,
  earLeftCycles: 0.95,
  earRightBaseDeg: 0,
  earRightAmplitudeDeg: 4.4,
  earRightCycles: 0.90,
  headDrop: 27.0,
  headDropCycles: 1,
);

const _tiredAnimation = AnimationProfile(
  durationMs: 7600,
  tailBaseDeg: -10,
  tailAmplitudeDeg: 0.8,
  tailCycles: 0.8,
  bodyLift: 2.8,
  bodyCycles: 1,
  headBaseDeg: 15,
  headAmplitudeDeg: 2.6,
  headCycles: 0.85,
  earLeftBaseDeg: -4,
  earLeftAmplitudeDeg: 1.0,
  earLeftCycles: 0.8,
  earRightBaseDeg: -44,
  earRightAmplitudeDeg: 1.0,
  earRightCycles: 0.8,
  headDrop: 7.0,
  headDropCycles: 0.85,
);

const _anxiousAnimation = AnimationProfile(
  durationMs: 3600,
  tailBaseDeg: -7,
  tailAmplitudeDeg: 1.6,
  tailCycles: 7,
  bodyLift: 1.0,
  bodyCycles: 4,
  headBaseDeg: 12,
  headAmplitudeDeg: 1.0,
  headCycles: 5,
  earLeftBaseDeg: 0,
  earLeftAmplitudeDeg: 2.4,
  earLeftCycles: 6,
  earRightBaseDeg: -40,
  earRightAmplitudeDeg: 2.0,
  earRightCycles: 5.5,
);

const _happyAnchors = <AccessorySlot, AccessoryAnchor>{
  AccessorySlot.head: AccessoryAnchor(position: Offset(208.8, 89.5), scale: 0.299, rotationDeg: -5.2),
  AccessorySlot.face: AccessoryAnchor(position: Offset(168.7, 161.8), scale: 0.399, rotationDeg: 0.0),
  AccessorySlot.neck: AccessoryAnchor(position: Offset(225.4, 270.0), scale: 0.582, rotationDeg: -6.9),
};

const _boredAnchors = <AccessorySlot, AccessoryAnchor>{
  AccessorySlot.head: AccessoryAnchor(position: Offset(342.2, 132.1), scale: 0.665, rotationDeg: 9.1),
  AccessorySlot.face: AccessoryAnchor(position: Offset(272.8, 301.3), scale: 0.900, rotationDeg: 11.0),
  AccessorySlot.neck: AccessoryAnchor(position: Offset(417.0, 556.8), scale: 1.334, rotationDeg: -10.6),
};

const dog01 = PetDefinition(
  id: 'dog01',
  label: 'Dog 01',
  poses: {
    PetMood.happy: _happyPose,
    PetMood.bored: _boredPose,
  },
  animations: {
    PetMood.happy: _happyAnimation,
    PetMood.bored: _boredAnimation,
    PetMood.tired: _tiredAnimation,
    PetMood.anxious: _anxiousAnimation,
  },
  anchors: {
    PetMood.happy: _happyAnchors,
    PetMood.bored: _boredAnchors,
  },
  blinkSpecs: {
    PetMood.happy: BlinkSpec(
      faceColor: Color(0xFFF1994B),
      lineColor: Color(0xFF4A261C),
      leftEye: Offset(0.351, 0.451),
      rightEye: Offset(0.630, 0.451),
    ),
  },
);

const pets = <PetDefinition>[dog01];

const accessories = <AccessoryDefinition>[
  AccessoryDefinition(
    id: 'sleep_hat',
    label: 'Moon Sleep Hat',
    slot: AccessorySlot.head,
    assetPath: 'assets/accessories/head/sleep_hat.png',
  ),
  AccessoryDefinition(
    id: 'round_glasses',
    label: 'Navy Paw Glasses',
    slot: AccessorySlot.face,
    assetPath: 'assets/accessories/face/round_glasses.png',
  ),
  AccessoryDefinition(
    id: 'night_scarf',
    label: 'Moon Night Scarf',
    slot: AccessorySlot.neck,
    assetPath: 'assets/accessories/neck/night_scarf.png',
  ),
];
