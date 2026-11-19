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

// Tired uses six pre-aligned 1024 x 1024 RGBA canvases. Original
// Tired artwork is now normalized to full-size transparent layers.
// The pet lies down; ears remain behind the head and the tail behind body.
const _tiredPose = PetPoseAssets(
  designSize: 1024,
  tail: LayerSpec(
    assetPath: 'assets/pets/dog01/tired/tail.png',
    position: Offset(770, 571),
    sourceAnchor: Offset(803, 563),
    sourceSize: Size(1024, 1024),
    sourceScale: 100,
  ),
  body: LayerSpec(
    assetPath: 'assets/pets/dog01/tired/body.png',
    position: Offset(0, 0),
    sourceAnchor: Offset(0, 0),
    sourceSize: Size(1024, 1024),
    sourceScale: 100,
  ),
  earRight: LayerSpec(
    assetPath: 'assets/pets/dog01/tired/ear_right.png',
    position: Offset(428, 267),
    sourceAnchor: Offset(428, 267),
    sourceSize: Size(1024, 1024),
    sourceScale: 100,
  ),
  earLeft: LayerSpec(
    assetPath: 'assets/pets/dog01/tired/ear_left.png',
    position: Offset(183, 238),
    sourceAnchor: Offset(183, 238),
    sourceSize: Size(1024, 1024),
    sourceScale: 100,
  ),
  head: LayerSpec(
    assetPath: 'assets/pets/dog01/tired/head_base.png',
    position: Offset(300, 438),
    sourceAnchor: Offset(300, 438),
    sourceSize: Size(1024, 1024),
    sourceScale: 100,
  ),
  effect: LayerSpec(
    assetPath: 'assets/pets/dog01/tired/zzz.png',
    position: Offset(0, 0),
    sourceAnchor: Offset(0, 0),
    sourceSize: Size(1024, 1024),
    sourceScale: 100,
  ),
);

// Anxious: five separated transparent layers aligned on one 1024 canvas.
// Ears remain BEHIND the head. Separate pivot points preserve ear roots.
// Anxious v4.6.16: permanent positions/rotations from the user-approved Layer Tuner pose.
// Body remains the lengthened, 1024-aligned version from v4.6.15.
// Pivots retain their anatomical locations, and positions are calibrated
// against the approved full-body reference using code-only layer transforms.
const _anxiousPose = PetPoseAssets(
  designSize: 1024,
  tail: LayerSpec(
    assetPath: 'assets/pets/dog01/anxious/tail.png',
    position: Offset(735.7, 360.6), sourceAnchor: Offset(758, 489),
    sourceSize: Size(1024, 1024), sourceScale: 100,
    rotationDeg: -4.0,
  ),
  body: LayerSpec(
    assetPath: 'assets/pets/dog01/anxious/body.png',
    position: Offset.zero, sourceAnchor: Offset.zero,
    sourceSize: Size(1024, 1024), sourceScale: 100,
  ),
  earRight: LayerSpec(
    assetPath: 'assets/pets/dog01/anxious/ear_right.png',
    position: Offset(452.9, 94.9), sourceAnchor: Offset(474, 224),
    sourceSize: Size(1024, 1024), sourceScale: 100,
    rotationDeg: 121.6,
  ),
  earLeft: LayerSpec(
    assetPath: 'assets/pets/dog01/anxious/ear_left.png',
    position: Offset(208.9, 172.9), sourceAnchor: Offset(243, 205),
    sourceSize: Size(1024, 1024), sourceScale: 100,
    rotationDeg: -10.6,
  ),
  head: LayerSpec(
    assetPath: 'assets/pets/dog01/anxious/head.png',
    position: Offset(292.5, 348.8), sourceAnchor: Offset(328, 402),
    sourceSize: Size(1024, 1024), sourceScale: 100,
    rotationDeg: 2.3,
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
  durationMs: 9300,
  // Broad but slow tired tail sway, pivot kept inside the body for no seam.
  tailBaseDeg: 17.0,
  tailAmplitudeDeg: 13.0,
  tailCycles: 1,
  bodyLift: 8.0,
  bodyCycles: 1,
  headBaseDeg: 0,
  headAmplitudeDeg: 4.6,
  headCycles: 1,
  earLeftBaseDeg: 0,
  earLeftAmplitudeDeg: 2.9,
  earLeftCycles: 1,
  earRightBaseDeg: 0,
  earRightAmplitudeDeg: 2.6,
  earRightCycles: 1,
  headDrop: 36.0,
  headDropCycles: 1,
);

const _anxiousAnimation = AnimationProfile(
  // v4.6.18: seamless periodic motion, with more expressive ear movement.
  durationMs: 6700,
  tailBaseDeg: 0.0,
  tailAmplitudeDeg: 9.0,
  // Whole-number cycles guarantee identical rotation at loop boundaries.
  tailCycles: 1.0,
  bodyLift: 5.0,
  bodyCycles: 1,
  headBaseDeg: 0.0,
  headAmplitudeDeg: 4.3,
  headCycles: 1,
  earLeftBaseDeg: 0.0,
  // Ears follow head + their own larger counter-sway.
  earLeftAmplitudeDeg: 5.5,
  earLeftCycles: 2.0,
  earRightBaseDeg: 0.0,
  earRightAmplitudeDeg: 5.8,
  earRightCycles: 2.0,
  headDrop: 9.0,
  headDropCycles: 1,
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

// Confirmed Tired attachment positions from the preview UI.
// Happy/Bored anchors remain unchanged.
const _tiredAnchors = <AccessorySlot, AccessoryAnchor>{
  AccessorySlot.head: AccessoryAnchor(position: Offset(349.5, 139.8), scale: 0.680, rotationDeg: 9.7),
  AccessorySlot.face: AccessoryAnchor(position: Offset(265.2, 309.4), scale: 0.890, rotationDeg: 9.5),
  AccessorySlot.neck: AccessoryAnchor(position: Offset(469.5, 568.3), scale: 1.504, rotationDeg: -13.7),
};

// Anxious placeholders only: refine in the preview with drag/scale/rotation.
// They do NOT overwrite the nine confirmed Happy/Bored/Tired anchors.
// Anxious accessory anchors confirmed by the user's on-screen tuner (2026-11-14).
// Independent of Happy / Bored / Tired anchor maps.
const _anxiousAnchors = <AccessorySlot, AccessoryAnchor>{
  AccessorySlot.head: AccessoryAnchor(
    position: Offset(351.8, 28.9), scale: 0.700, rotationDeg: 5.6,
  ),
  AccessorySlot.face: AccessoryAnchor(
    position: Offset(261.2, 200.0), scale: 0.910, rotationDeg: 7.1,
  ),
  AccessorySlot.neck: AccessoryAnchor(
    position: Offset(497.2, 455.7), scale: 1.741, rotationDeg: -17.2,
  ),
};

const dog01 = PetDefinition(
  id: 'dog01',
  label: 'Dog 01',
  poses: {
    PetMood.happy: _happyPose,
    PetMood.bored: _boredPose,
    PetMood.tired: _tiredPose,
    PetMood.anxious: _anxiousPose,
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
    PetMood.tired: _tiredAnchors,
    PetMood.anxious: _anxiousAnchors,
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

// Cat 01 Happy: approved five-layer alignment (v4.6.22). Animated
// rotations keep the existing anatomical pivots; static positions unchanged.
const _catHappyPose = PetPoseAssets(
  designSize: 1024,
  tail: LayerSpec(
    assetPath: 'assets/pets/cat01/happy/tail.png',
    position: Offset(807, 455), sourceAnchor: Offset(807, 455),
    sourceSize: Size(1024, 1024), sourceScale: 100,
  ),
  body: LayerSpec(
    assetPath: 'assets/pets/cat01/happy/body.png',
    position: Offset(550, 640), sourceAnchor: Offset(550, 640),
    sourceSize: Size(1024, 1024), sourceScale: 100,
  ),
  earRight: LayerSpec(
    assetPath: 'assets/pets/cat01/happy/ear_right.png',
    position: Offset(495.3, 338.7), sourceAnchor: Offset(513, 352),
    rotationDeg: 0.0,
    sourceSize: Size(1024, 1024), sourceScale: 100,
  ),
  earLeft: LayerSpec(
    assetPath: 'assets/pets/cat01/happy/ear_left.png',
    position: Offset(268.4, 332.3), sourceAnchor: Offset(295, 350),
    rotationDeg: -18.2,
    sourceSize: Size(1024, 1024), sourceScale: 100,
  ),
  head: LayerSpec(
    assetPath: 'assets/pets/cat01/happy/head.png',
    position: Offset(375, 467), sourceAnchor: Offset(375, 467),
    sourceSize: Size(1024, 1024), sourceScale: 100,
  ),
);

// Cat-specific Happy animation. Each motion starts and ends at the
// approved static pose; the pet_widget.dart envelope makes looping smooth.
const _catHappyAnimation = AnimationProfile(
  durationMs: 5600,
  tailBaseDeg: 0, tailAmplitudeDeg: 23.0, tailCycles: 1,
  bodyLift: 6.5, bodyCycles: 1,
  headBaseDeg: 0, headAmplitudeDeg: 4.2, headCycles: 1,
  earLeftBaseDeg: 0, earLeftAmplitudeDeg: 8.0, earLeftCycles: 2,
  earRightBaseDeg: 0, earRightAmplitudeDeg: 7.0, earRightCycles: 2,
  headDrop: 5.0, headDropCycles: 1,
);


// Cat 01 Bored: 5 aligned 1024x1024 layers rebuilt from the user-provided
// bored parts sheet. This is the first Flutter integration pass; positions can
// be tuned later with the same layer-tuner workflow used for Happy.
const _catBoredPose = PetPoseAssets(
  designSize: 1024,
  tail: LayerSpec(
    assetPath: 'assets/pets/cat01/bored/tail.png',
    position: Offset(741.3, 722.3), sourceAnchor: Offset(759, 740),
    rotationDeg: -2.3,
    sourceSize: Size(1024, 1024), sourceScale: 100,
  ),
  body: LayerSpec(
    assetPath: 'assets/pets/cat01/bored/body.png',
    position: Offset.zero, sourceAnchor: Offset.zero,
    sourceSize: Size(1024, 1024), sourceScale: 100,
  ),
  earRight: LayerSpec(
    assetPath: 'assets/pets/cat01/bored/ear_right.png',
    position: Offset(518.1, 347.7), sourceAnchor: Offset(527, 330),
    sourceSize: Size(1024, 1024), sourceScale: 100,
  ),
  earLeft: LayerSpec(
    assetPath: 'assets/pets/cat01/bored/ear_left.png',
    position: Offset(263.6, 362.4), sourceAnchor: Offset(237, 327),
    sourceSize: Size(1024, 1024), sourceScale: 100,
  ),
  head: LayerSpec(
    assetPath: 'assets/pets/cat01/bored/head.png',
    position: Offset(380, 457), sourceAnchor: Offset(380, 457),
    sourceSize: Size(1024, 1024), sourceScale: 100,
  ),
);

const _catBoredAnimation = AnimationProfile(
  durationMs: 7200,
  // Bored cat: slow tail sway, subtle head nod and independent ear twitches.
  tailBaseDeg: 0.0, tailAmplitudeDeg: 17.0, tailCycles: 1,
  bodyLift: 4.0, bodyCycles: 1,
  headBaseDeg: 0.0, headAmplitudeDeg: 3.0, headCycles: 1,
  earLeftBaseDeg: 0.0, earLeftAmplitudeDeg: 5.0, earLeftCycles: 2,
  earRightBaseDeg: 0.0, earRightAmplitudeDeg: 4.0, earRightCycles: 2,
  headDrop: 15.0, headDropCycles: 1,
);

// Cat 01 Tired: separate full-canvas 1024x1024 layers.
// Initial pose is aligned visually; adjust using Cat Tired Layer Tuner.
const _catTiredPose = PetPoseAssets(
  designSize: 1024,
  tail: LayerSpec(
    assetPath: 'assets/pets/cat01/tired/tail.png',
    position: Offset(796.1, 774.9), sourceAnchor: Offset(805, 704),
    rotationDeg: -38.7,
    sourceSize: Size(1024, 1024), sourceScale: 100,
  ),
  body: LayerSpec(
    assetPath: 'assets/pets/cat01/tired/body.png',
    position: Offset.zero, sourceAnchor: Offset.zero,
    sourceSize: Size(1024, 1024), sourceScale: 100,
  ),
  earRight: LayerSpec(
    assetPath: 'assets/pets/cat01/tired/ear_right.png',
    position: Offset(502.0, 377.4), sourceAnchor: Offset(502, 404),
    sourceSize: Size(1024, 1024), sourceScale: 100,
  ),
  earLeft: LayerSpec(
    assetPath: 'assets/pets/cat01/tired/ear_left.png',
    position: Offset(283.0, 382.8), sourceAnchor: Offset(252, 405),
    rotationDeg: -9.1,
    sourceSize: Size(1024, 1024), sourceScale: 100,
  ),
  head: LayerSpec(
    assetPath: 'assets/pets/cat01/tired/head.png',
    position: Offset(389.2, 516.0), sourceAnchor: Offset(336, 516),
    sourceSize: Size(1024, 1024), sourceScale: 100,
  ),
);

// Gentle sleepy motion, separate from the existing Dog Tired treatment.
// Whole-number wave cycles ensure a continuous loop with no pose reset jump.
const _catTiredAnimation = AnimationProfile(
  durationMs: 9000,
  // Expressive but still sleepy: preserve the approved rest pose.
  // Whole-number waves and zero-phase motion keep the cycle seamless.
  tailBaseDeg: 0.0, tailAmplitudeDeg: 18.0, tailCycles: 1,
  bodyLift: 8.0, bodyCycles: 1,
  headBaseDeg: 0.0, headAmplitudeDeg: 5.2, headCycles: 1,
  earLeftBaseDeg: 0.0, earLeftAmplitudeDeg: 3.8, earLeftCycles: 1,
  earRightBaseDeg: 0.0, earRightAmplitudeDeg: 3.5, earRightCycles: 1,
  headDrop: 25.0, headDropCycles: 1,
);


// Cat 01 Anxious: user-approved static placement from Cat 01 Anxious
// Layer Tuner. All five layers stay on full 1024x1024 transparent canvases.
// These offsets are now fixed and are safe to animate around their current pivots.
const _catAnxiousPose = PetPoseAssets(
  designSize: 1024,
  tail: LayerSpec(
    assetPath: 'assets/pets/cat01/anxious/tail.png',
    position: Offset(668.1, 515.4), sourceAnchor: Offset(725.7, 511.0),
    rotationDeg: -18.2,
    sourceSize: Size(1024, 1024), sourceScale: 100,
  ),
  body: LayerSpec(
    assetPath: 'assets/pets/cat01/anxious/body.png',
    position: Offset.zero, sourceAnchor: Offset.zero,
    sourceSize: Size(1024, 1024), sourceScale: 100,
  ),
  earRight: LayerSpec(
    assetPath: 'assets/pets/cat01/anxious/ear_right.png',
    position: Offset(518.2, 326.0), sourceAnchor: Offset(527.0, 326.0),
    rotationDeg: 0.0,
    sourceSize: Size(1024, 1024), sourceScale: 100,
  ),
  earLeft: LayerSpec(
    assetPath: 'assets/pets/cat01/anxious/ear_left.png',
    position: Offset(222.6, 314.7), sourceAnchor: Offset(244.7, 314.7),
    rotationDeg: -4.6,
    sourceSize: Size(1024, 1024), sourceScale: 100,
  ),
  head: LayerSpec(
    assetPath: 'assets/pets/cat01/anxious/head.png',
    position: Offset(382.0, 444.0), sourceAnchor: Offset(382.0, 444.0),
    rotationDeg: 0.0,
    sourceSize: Size(1024, 1024), sourceScale: 100,
  ),
);

// Cat 01 Anxious animation: slightly more alert than Tired, but still subtle.
// All cycles are whole-number to keep the loop seamless when repeating.
const _catAnxiousAnimation = AnimationProfile(
  durationMs: 6200,
  tailBaseDeg: 0, tailAmplitudeDeg: 12.0, tailCycles: 1,
  bodyLift: 5.0, bodyCycles: 1,
  headBaseDeg: 0, headAmplitudeDeg: 4.6, headCycles: 1,
  earLeftBaseDeg: 0, earLeftAmplitudeDeg: 8.5, earLeftCycles: 2,
  earRightBaseDeg: 0, earRightAmplitudeDeg: 8.0, earRightCycles: 2,
  headDrop: 8.0, headDropCycles: 1,
);

const cat01 = PetDefinition(
  id: 'cat01',
  label: 'Cat 01 - Gray Tabby',
  poses: {
    PetMood.happy: _catHappyPose,
    PetMood.bored: _catBoredPose,
    PetMood.tired: _catTiredPose,
    PetMood.anxious: _catAnxiousPose,
  },
  animations: {
    PetMood.happy: _catHappyAnimation,
    PetMood.bored: _catBoredAnimation,
    PetMood.tired: _catTiredAnimation,
    PetMood.anxious: _catAnxiousAnimation,
  },
  anchors: {
    // Cat 01 Happy: confirmed accessory anchors.
    PetMood.happy: {
      AccessorySlot.head: AccessoryAnchor(
        position: Offset(400.1, 204.9), scale: 0.700, rotationDeg: -1.5),
      AccessorySlot.face: AccessoryAnchor(
        position: Offset(354.0, 420.1), scale: 0.924, rotationDeg: 0.0),
      AccessorySlot.neck: AccessoryAnchor(
        position: Offset(590.0, 620.5), scale: 1.470, rotationDeg: -19.2),
    },
    // Cat 01 Bored: user-confirmed accessory anchors (v4.6.30).
    PetMood.bored: {
      AccessorySlot.head: AccessoryAnchor(
        position: Offset(431.8, 266.2), scale: 0.624, rotationDeg: -3.0),
      AccessorySlot.face: AccessoryAnchor(
        position: Offset(359.2, 466.2), scale: 0.782, rotationDeg: 1.5),
      AccessorySlot.neck: AccessoryAnchor(
        position: Offset(622.3, 559.4), scale: 1.231, rotationDeg: -28.8),
    },
    // Cat 01 Tired: user-confirmed accessory anchors (v4.6.39).
    PetMood.tired: {
      AccessorySlot.head: AccessoryAnchor(
        position: Offset(435.5, 292.2), scale: 0.640, rotationDeg: 0.0),
      AccessorySlot.face: AccessoryAnchor(
        position: Offset(366.0, 497.6), scale: 0.812, rotationDeg: 5.1),
      AccessorySlot.neck: AccessoryAnchor(
        position: Offset(545.6, 673.0), scale: 1.270, rotationDeg: -15.0),
    },
    // Cat 01 Anxious: user-confirmed accessory anchors (v4.6.45).
    PetMood.anxious: {
      AccessorySlot.head: AccessoryAnchor(
        position: Offset(413.2, 174.4), scale: 0.690, rotationDeg: 0.0),
      AccessorySlot.face: AccessoryAnchor(
        position: Offset(369.2, 390.6), scale: 0.944, rotationDeg: 0.0),
      AccessorySlot.neck: AccessoryAnchor(
        position: Offset(554.8, 590.8), scale: 1.381, rotationDeg: -18.1),
    },
  },
);

const pets = <PetDefinition>[dog01, cat01];

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
  // 隊友 2026-11-15 交來的第四件真圖，補上後端 Lv4 的 bow（原本只有 emoji）。
  // 與圍巾同一個 neck 插槽，所以共用那三種心情的 neck 錨點，不必另外對位。
  AccessoryDefinition(
    id: 'pink_bow',
    label: 'Pink Ribbon Bow',
    slot: AccessorySlot.neck,
    assetPath: 'assets/accessories/neck/pink_bow.png',
  ),
  // 2026-11-19 使用者生成，取代 top_hat／crown 原本的 emoji。都是 head 插槽，
  // 沿用睡帽那組頭部錨點（小狗、貓各一組），不另外對位。
  AccessoryDefinition(
    id: 'star_top_hat',
    label: 'Star Top Hat',
    slot: AccessorySlot.head,
    assetPath: 'assets/accessories/head/star_top_hat.png',
    fit: 0.62,
    drop: -0.04,
    shadowAt: 0.887,
    // 使用者 2026-11-19 逐格挑的戴法（每種姿勢一組）
    poseFits: {
      'dog01.happy': AccessoryFit(fit: 0.86, drop: -0.03, dx: 0.06, rotationDeg: 16),
      'dog01.bored': AccessoryFit(fit: 0.72, drop: -0.16, dx: 0.0),
      'dog01.tired': AccessoryFit(fit: 0.72, drop: -0.16, dx: 0.0),
      'dog01.anxious': AccessoryFit(fit: 0.86, drop: -0.16, dx: 0.0),
      'cat01.happy': AccessoryFit(fit: 0.8, drop: -0.02, dx: 0.0),
      'cat01.bored': AccessoryFit(fit: 0.74, drop: -0.02, dx: -0.12),
      'cat01.tired': AccessoryFit(fit: 0.72, drop: -0.16, dx: -0.06),
      'cat01.anxious': AccessoryFit(fit: 0.72, drop: -0.09, dx: -0.06),
    },
  ),
  AccessoryDefinition(
    id: 'moon_crown',
    label: 'Moon Crown',
    slot: AccessorySlot.head,
    assetPath: 'assets/accessories/head/moon_crown.png',
    fit: 0.58,
    drop: -0.04,
    shadowAt: 0.82,
    poseFits: {
      'dog01.happy': AccessoryFit(fit: 0.74, drop: -0.12, dx: -0.04),
      'dog01.bored': AccessoryFit(fit: 0.72, drop: -0.16, dx: 0.0),
      'dog01.tired': AccessoryFit(fit: 0.72, drop: -0.16, dx: 0.0),
      'dog01.anxious': AccessoryFit(fit: 0.72, drop: -0.16, dx: -0.07),
      'cat01.happy': AccessoryFit(fit: 0.72, drop: -0.16, dx: -0.06),
      'cat01.bored': AccessoryFit(fit: 0.72, drop: -0.10, dx: -0.06, rotationDeg: -8),
      'cat01.tired': AccessoryFit(fit: 0.72, drop: -0.16, dx: -0.06),
      'cat01.anxious': AccessoryFit(fit: 0.72, drop: -0.16, dx: -0.06),
    },
  ),
];
