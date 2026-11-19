// 隊友的 2D 分層寵物元件（pet_preview v4.6.45，2026-11-15 換版）。
// 與原版的差別：加了 speed（動畫速度，晚上版放慢）、衣服圖層加上 Key('pet-accessory')、
// 心情一律先過 pet.resolve()（缺圖畫 bored，不畫 happy）。預覽用的調位置工具照留、App 不開。
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pet_models.dart';

class LayeredPet extends StatefulWidget {
  const LayeredPet({
    super.key,
    required this.pet,
    required this.mood,
    this.accessory,
    this.accessoryTweak = const AccessoryTweak(),
    this.size = 440,
    this.animate = true,
    this.showAnchors = false,
    this.onAccessoryDrag,
    this.layerTunerEnabled = false,
    this.selectedLayer = 'earRight',
    this.layerTweaks = const {},
    this.onLayerDrag,
    this.speed = 1.0,
  });

  final PetDefinition pet;
  final PetMood mood;
  final AccessoryDefinition? accessory;
  final AccessoryTweak accessoryTweak;
  final double size;
  final bool animate;
  final bool showAnchors;
  final ValueChanged<Offset>? onAccessoryDrag;
  final bool layerTunerEnabled;
  final String selectedLayer;
  final Map<String, PetLayerTweak> layerTweaks;
  final ValueChanged<Offset>? onLayerDrag;

  /// 動畫速度倍率（< 1 較慢）。晚上版用來表現想睡。
  final double speed;

  @override
  State<LayeredPet> createState() => _LayeredPetState();
}

class _LayeredPetState extends State<LayeredPet>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  Timer? _blinkTimer;
  Timer? _reactionTimer;
  bool _blinking = false;
  bool _reacting = false;

  @override
  void initState() {
    super.initState();
    _createController();
    _scheduleBlink();
  }

  void _createController() {
    _controller = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds:
            (widget.pet.animationFor(widget.mood).durationMs / widget.speed)
                .round(),
      ),
    );
    if (widget.animate) {
      _controller.repeat();
    }
  }

  void _rebuildController() {
    final wasAnimating = widget.animate;
    _controller.dispose();
    _createController();
    if (!wasAnimating) {
      _controller.stop();
    }
  }

  // Happy blinks quickly. Bored takes a longer, sleepy pause.
  // A single cancellable timer prevents the old mood's blink from leaking
  // into a new mood after switching pets or stopping the animation.
  void _scheduleBlink() {
    _blinkTimer?.cancel();
    if (!widget.animate) return;
    final isCatBored = widget.pet.id == 'cat01' && widget.mood == PetMood.bored;
    final isCatTired = widget.pet.id == 'cat01' && widget.mood == PetMood.tired;
    final waitMs = isCatBored
        ? 5000 + math.Random().nextInt(3001)
        : isCatTired
            ? 3600 + math.Random().nextInt(1801)
            : 2500 + math.Random().nextInt(1000);
    _blinkTimer = Timer(Duration(milliseconds: waitMs), () {
      if (!mounted || !widget.animate) return;
      final catBlink = widget.pet.id == 'cat01' &&
          (widget.mood == PetMood.happy || widget.mood == PetMood.bored || widget.mood == PetMood.tired);
      if (widget.pet.blinkFor(widget.mood) == null && !catBlink) {
        _scheduleBlink();
        return;
      }
      setState(() => _blinking = true);
      _blinkTimer = Timer(
        Duration(milliseconds: isCatBored ? 850 : isCatTired ? 320 : 170),
        () {
          if (!mounted) return;
          setState(() => _blinking = false);
          _scheduleBlink();
        },
      );
    });
  }

  void _react() {
    _reactionTimer?.cancel();
    setState(() => _reacting = true);
    _reactionTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _reacting = false);
    });
  }

  @override
  void didUpdateWidget(covariant LayeredPet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pet.id != widget.pet.id ||
        oldWidget.mood != widget.mood ||
        oldWidget.speed != widget.speed) {
      _blinking = false;
      _rebuildController();
      _scheduleBlink();
    } else if (oldWidget.animate != widget.animate) {
      if (widget.animate) {
        _controller.repeat();
        _scheduleBlink();
      } else {
        _controller.stop();
        // Zero-phase rest pose is essential while aligning separated layers.
        _controller.value = 0.0;
        _blinkTimer?.cancel();
        _blinking = false;
      }
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _reactionTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  double _deg(double value) => value * math.pi / 180;

  PetLayerTweak _layerAdjustment(String name) =>
      widget.layerTunerEnabled && ((widget.pet.id == 'dog01' && widget.mood == PetMood.anxious) || (widget.pet.id == 'cat01' && (widget.mood == PetMood.happy || widget.mood == PetMood.bored || widget.mood == PetMood.tired || widget.mood == PetMood.anxious)))
          ? (widget.layerTweaks[name] ?? const PetLayerTweak())
          : const PetLayerTweak();

  Widget _layer({
    required LayerSpec spec,
    required double designSize,
    required Widget child,
    double rotationDeg = 0,
    double scaleMultiplier = 1.0,
    double offsetX = 0,
    double offsetY = 0,
    String? tunerPart,
  }) {
    final tune = tunerPart == null
        ? const PetLayerTweak()
        : _layerAdjustment(tunerPart);
    final factor = widget.size / designSize;
    final scale = spec.sourceScale / 100;
    final childWidth = spec.sourceSize.width * scale * factor;
    final childHeight = spec.sourceSize.height * scale * factor;
    final left = (spec.position.dx + offsetX + tune.dx - spec.sourceAnchor.dx * scale) * factor;
    final top = (spec.position.dy + offsetY + tune.dy - spec.sourceAnchor.dy * scale) * factor;
    final alignment = Alignment(
      (spec.sourceAnchor.dx / spec.sourceSize.width) * 2 - 1,
      (spec.sourceAnchor.dy / spec.sourceSize.height) * 2 - 1,
    );

    return Positioned(
      left: left,
      top: top,
      width: childWidth,
      height: childHeight,
      child: Transform.rotate(
        angle: _deg(spec.rotationDeg + rotationDeg + tune.rotationDeg),
        alignment: alignment,
        // Scale this part around its existing anatomical pivot. This keeps
        // ear roots and tail root anchored while their visible art enlarges.
        child: Transform.scale(
          scale: scaleMultiplier * tune.scale,
          alignment: alignment,
          child: child,
        ),
      ),
    );
  }

  Widget _asset(String path) => Image.asset(
        path,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.high,
      );

  Widget _accessoryLayer(
    PetPoseAssets pose, {
    double headOffsetY = 0,
    double headOffsetX = 0,
    double headRotationDeg = 0,
    double bodyOffsetY = 0,
    double bodyOffsetX = 0,
  }) {
    final accessory = widget.accessory;
    if (accessory == null) return const SizedBox.shrink();

    final base = widget.pet.anchorFor(widget.mood, accessory.slot);
    final tweak = widget.accessoryTweak;
    final factor = widget.size / pose.designSize;
    final sourceSize = 512.0;
    // 這一件自己的大小：以底邊中點縮放（見 AccessoryDefinition.fit）
    final box = sourceSize * base.scale * tweak.scale;
    final scale = base.scale * tweak.scale * accessory.fit;
    final size = sourceSize * scale * factor;
    final fitDropY = box * (1 - accessory.fit) / 2 + box * accessory.drop;

    // Head/face accessories follow the head. Neck accessories follow the body,
    // so a scarf stays attached to the chest/neck instead of being pulled by
    // extra head-drop motion.
    final followsHead = accessory.slot == AccessorySlot.head ||
        accessory.slot == AccessorySlot.face;
    final followsBody = accessory.slot == AccessorySlot.neck;
    final x = base.position.dx + tweak.dx +
        (followsHead ? headOffsetX : (followsBody ? bodyOffsetX : 0.0));
    final animatedOffsetY = followsHead
        ? headOffsetY
        : (followsBody ? bodyOffsetY : 0.0);
    final y = base.position.dy + tweak.dy + animatedOffsetY + fitDropY;
    final animatedRotation = followsHead ? headRotationDeg : 0.0;

    return Positioned(
      key: const Key('pet-accessory'),
      left: (x - sourceSize * scale / 2) * factor,
      top: (y - sourceSize * scale / 2) * factor,
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: widget.onAccessoryDrag == null
            ? null
            : (details) {
                // Convert screen pixels back into the pet design coordinate
                // system so drag values remain stable at any preview size.
                widget.onAccessoryDrag!(
                  Offset(details.delta.dx / factor, details.delta.dy / factor),
                );
              },
        child: Transform.rotate(
          angle: _deg(
            base.rotationDeg + tweak.rotationDeg + animatedRotation,
          ),
          alignment: Alignment.bottomCenter,
          child: Image.asset(
            accessory.assetPath,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }

  Widget _anchorDots(PetPoseAssets pose) {
    if (!widget.showAnchors) return const SizedBox.shrink();
    final factor = widget.size / pose.designSize;
    final entries = <MapEntry<AccessorySlot, Color>>[
      const MapEntry(AccessorySlot.head, Colors.amber),
      const MapEntry(AccessorySlot.face, Colors.cyanAccent),
      const MapEntry(AccessorySlot.neck, Colors.pinkAccent),
    ];

    return Stack(
      children: entries.map((entry) {
        final anchor = widget.pet.anchorFor(widget.mood, entry.key);
        return Positioned(
          left: anchor.position.dx * factor - 6,
          top: anchor.position.dy * factor - 6,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: entry.value,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMoodEffect(
    PetPoseAssets pose,
    double bodyOffsetY,
    double headDrop,
  ) {
    final effect = pose.effect;
    if (effect == null || !widget.animate) return const SizedBox.shrink();

    // The puff begins only when the Bored pose is near maximum slouch.
    // This makes the exhale feel caused by the body/head motion instead of
    // looking like an independent looping effect.
    final cycle = _controller.value % 1.0;
    const start = 0.44;
    const peak = 0.54;
    const end = 0.72;
    if (cycle < start || cycle > end) return const SizedBox.shrink();

    final travel = Curves.easeOut.transform(
      ((cycle - start) / (end - start)).clamp(0.0, 1.0),
    );

    double opacity;
    if (cycle <= peak) {
      opacity = Curves.easeOut.transform(
        ((cycle - start) / (peak - start)).clamp(0.0, 1.0),
      );
    } else {
      opacity = Curves.easeIn.transform(
        ((end - cycle) / (end - peak)).clamp(0.0, 1.0),
      );
    }

    final driftX = -50.0 * travel;
    final driftY = -16.0 * travel;
    final scale = 0.78 + 0.46 * travel;

    // Follow the lowered head at the start of the exhale, then drift away.
    final effectOffsetY = bodyOffsetY + headDrop * 0.88;

    return _layer(
      spec: effect,
      designSize: pose.designSize,
      offsetY: effectOffsetY,
      child: Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: Offset(driftX, driftY),
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.centerLeft,
            child: _asset(effect.assetPath),
          ),
        ),
      ),
    );
  }

  // Sleepy nod: a slow forward drop, brief hold, and gentle recovery.
  // The single phase also triggers the Zzz effect, so they stay synchronized.
  double _tiredNod(double phase) {
    if (phase < 0.46) {
      return Curves.easeInOut.transform((phase / 0.46).clamp(0.0, 1.0));
    }
    if (phase < 0.60) return 1.0;
    return 1.0 - Curves.easeInOut.transform(
      ((phase - 0.60) / 0.40).clamp(0.0, 1.0),
    );
  }

  Widget _buildTiredZzz(PetPoseAssets pose, double headOffsetY) {
    final effect = pose.effect;
    if (effect == null || !widget.animate) return const SizedBox.shrink();
    final t = _controller.value;
    const begin = 0.40;
    const fullyVisible = 0.50;
    const end = 0.82;
    if (t < begin || t > end) return const SizedBox.shrink();
    final progress = ((t - begin) / (end - begin)).clamp(0.0, 1.0);
    final drift = Curves.easeOut.transform(progress);
    final double opacity;
    if (t < fullyVisible) {
      opacity = Curves.easeOut.transform(
        ((t - begin) / (fullyVisible - begin)).clamp(0.0, 1.0),
      );
    } else {
      opacity = Curves.easeIn.transform(
        ((end - t) / (end - fullyVisible)).clamp(0.0, 1.0),
      );
    }
    return _layer(
      spec: effect,
      designSize: pose.designSize,
      offsetY: headOffsetY * 0.30,
      child: Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: Offset(-8.0 * drift, -34.0 * drift),
          child: Transform.scale(
            scale: 0.87 + 0.22 * drift,
            alignment: Alignment.topLeft,
            child: _asset(effect.assetPath),
          ),
        ),
      ),
    );
  }

  // Periodic sway whose position AND velocity match at each loop boundary.
  // sin(theta) by itself has nonzero velocity at 0/2pi; this shape eases
  // into a near-still pose at both ends without changing the static baseline.
  // For Anxious use whole-number `cycles` only.
  double _anxiousSoftWave(double phase, double cycles) {
    final theta = phase * cycles;
    return math.sin(theta) * (1.0 - math.cos(theta)) / 1.299038105676658;
  }

  // A closed-loop wave for Cat 01. The envelope is zero at both ends,
  // as is its derivative, so replaying the AnimationController never jumps.
  // Whole-number cycles ensure the motion begins at the approved static pose.
  double _catHappyWave(double t, double cycles) {
    final envelope = math.pow(math.sin(math.pi * t), 2).toDouble();
    return envelope * math.sin(2 * math.pi * cycles * t);
  }

  // Brief anxious tremors rather than continuous shaking.
  // Both head-attached accessories and the head use the same X displacement.
  double _anxiousTremor(double t) {
    double pulse(double center, double halfWidth) {
      final distance = (t - center).abs();
      if (distance >= halfWidth) return 0.0;
      final envelope = math.pow(1.0 - distance / halfWidth, 2).toDouble();
      return envelope * math.sin((t - center) * 2 * math.pi * 34);
    }
    return 3.6 * pulse(0.25, 0.11) + 3.0 * pulse(0.74, 0.095);
  }

  @override
  Widget build(BuildContext context) {
    final pose = widget.pet.poseFor(widget.mood);
    final profile = widget.pet.animationFor(widget.mood);

    return GestureDetector(
      onTap: _react,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: _reacting ? 1.045 : 1,
        // Scale the entire Anxious pose as a single composition. The preview
        // still uses the same 1024 design coordinates and accessory anchors.
        // Hats/glasses/scarves and the drag handles scale with the dog.
        child: Transform.scale(
          scale: (widget.pet.id == 'dog01' && widget.mood == PetMood.anxious) ? 0.90 : 1.0,
          alignment: Alignment.center,
          child: RepaintBoundary(
            child: SizedBox.square(
            dimension: widget.size,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = widget.animate ? _controller.value : 0.0;
                final phase = t * 2 * math.pi;
                final isTired = widget.pet.id == 'dog01' && widget.mood == PetMood.tired;
                final isCatTired = widget.pet.id == 'cat01' && widget.mood == PetMood.tired;
                final isDogAnxious = widget.pet.id == 'dog01' && widget.mood == PetMood.anxious;
                final isCatAnxious = widget.pet.id == 'cat01' && widget.mood == PetMood.anxious;
                final isAnxious = isDogAnxious || isCatAnxious;
                final isCatHappy = widget.pet.id == 'cat01' && widget.mood == PetMood.happy;
                final isCatBored = widget.pet.id == 'cat01' && widget.mood == PetMood.bored;
                final isCatTunable = isCatHappy || isCatBored || isCatTired || isCatAnxious;
                final tailRotation = (isCatHappy || isCatBored || isCatTired)
                    ? profile.tailBaseDeg + profile.tailAmplitudeDeg *
                        _catHappyWave(t, profile.tailCycles)
                    : isAnxious
                        ? profile.tailBaseDeg +
                            profile.tailAmplitudeDeg *
                                _anxiousSoftWave(phase, profile.tailCycles) +
                            (widget.animate ? _anxiousSoftWave(phase, 2.0) : 0.0)
                        : profile.tailBaseDeg +
                            profile.tailAmplitudeDeg *
                                math.sin(phase * profile.tailCycles);
                final bodyLift = profile.bodyLift *
                    (1 - math.cos(phase * profile.bodyCycles)) / 2;
                final anxiousT = widget.animate ? _controller.value : 0.0;
                final anxiousTremor = isAnxious && widget.animate
                    ? _anxiousTremor(anxiousT) : 0.0;
                // Look slightly left/right, pausing between cautious glances.
                final anxiousGlance = isAnxious && widget.animate
                    ? _anxiousSoftWave(phase, 1.0)
                    : 0.0;
                final tiredNod = isTired
                    ? _tiredNod(widget.animate ? _controller.value : 0.0)
                    : 0.0;
                // Tired head_base stays constant. Only eyes_open/eyes_closed
                // crossfade in the SAME 1024x1024 local head coordinates.
                // Nod rotation/translation is applied once to the parent layer.
                final tiredCycle = widget.animate ? _controller.value : 0.0;
                double eyeClosedOpacity = 0.0;
                if (isTired && widget.animate) {
                  if (tiredCycle >= 0.38 && tiredCycle < 0.45) {
                    eyeClosedOpacity = Curves.easeInOut.transform(
                      ((tiredCycle - 0.38) / 0.07).clamp(0.0, 1.0),
                    );
                  } else if (tiredCycle >= 0.45 && tiredCycle < 0.62) {
                    eyeClosedOpacity = 1.0;
                  } else if (tiredCycle >= 0.62 && tiredCycle < 0.71) {
                    eyeClosedOpacity = 1.0 - Curves.easeInOut.transform(
                      ((tiredCycle - 0.62) / 0.09).clamp(0.0, 1.0),
                    );
                  }
                }
                final headRotation = (isCatHappy || isCatBored || isCatTired)
                    ? profile.headBaseDeg + profile.headAmplitudeDeg *
                        _catHappyWave(t, profile.headCycles)
                    : isAnxious
                    ? profile.headBaseDeg + profile.headAmplitudeDeg * anxiousGlance
                    : isTired
                    ? profile.headBaseDeg + profile.headAmplitudeDeg * tiredNod
                    : profile.headBaseDeg +
                        profile.headAmplitudeDeg *
                            math.sin(phase * profile.headCycles - 0.55);
                final headDrop = (isCatHappy || isCatTired || isCatAnxious)
                    ? profile.headDrop * (0.5 - 0.5 * math.cos(phase))
                    : isAnxious
                    ? profile.headDrop * (0.5 - 0.5 * math.cos(phase))
                    : isTired
                    ? profile.headDrop * tiredNod
                    : profile.headDrop *
                        (1 - math.cos(phase * profile.headDropCycles)) /
                        2;
                // Happy breathes upward; Bored slumps downward so the whole
                // body visibly sinks before the synchronized sigh.
                final bodyOffsetY = widget.mood == PetMood.bored
                    ? bodyLift
                    : -bodyLift;
                final earLeftRotation = (isCatHappy || isCatBored || isCatTired)
                    ? headRotation * 0.75 + profile.earLeftBaseDeg +
                        profile.earLeftAmplitudeDeg *
                            _catHappyWave(t, profile.earLeftCycles)
                    : isAnxious
                    ? headRotation + profile.earLeftBaseDeg +
                        profile.earLeftAmplitudeDeg *
                            _anxiousSoftWave(phase, profile.earLeftCycles)
                    : isTired
                    ? profile.earLeftBaseDeg -
                        profile.earLeftAmplitudeDeg * tiredNod
                    : profile.earLeftBaseDeg +
                        profile.earLeftAmplitudeDeg *
                            math.sin(phase * profile.earLeftCycles + 0.85);
                final earRightRotation = (isCatHappy || isCatBored || isCatTired)
                    ? headRotation * 0.75 + profile.earRightBaseDeg -
                        profile.earRightAmplitudeDeg *
                            _catHappyWave(t, profile.earRightCycles)
                    : isAnxious
                    ? headRotation + profile.earRightBaseDeg -
                        profile.earRightAmplitudeDeg *
                            _anxiousSoftWave(phase, profile.earRightCycles)
                    : isTired
                    ? profile.earRightBaseDeg +
                        profile.earRightAmplitudeDeg * tiredNod
                    : profile.earRightBaseDeg +
                        profile.earRightAmplitudeDeg *
                            math.sin(phase * profile.earRightCycles + 1.65);

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _layer(
                      spec: pose.tail,
                      designSize: pose.designSize,
                      tunerPart: isAnxious || isCatTunable ? 'tail' : null,
                      scaleMultiplier: isDogAnxious ? 1.499 : isCatBored ? 1.051 : isCatTired ? 1.011 : 1.0,
                      rotationDeg: tailRotation,
                      // Keep Tired's tail joint attached during body breathing.
                      offsetX: isAnxious ? anxiousTremor * 0.85 : 0.0,
                      offsetY: isTired || isAnxious || isCatHappy || isCatBored || isCatTired ? bodyOffsetY : 0,
                      child: _asset(pose.tail.assetPath),
                    ),
                    _layer(
                      spec: pose.body,
                      tunerPart: isCatTunable ? 'body' : null,
                      designSize: pose.designSize,
                      offsetX: anxiousTremor * 0.85,
                      offsetY: bodyOffsetY,
                      child: _asset(pose.body.assetPath),
                    ),
                    // Ears sit behind the head so they look attached at the roots.
                    _layer(
                      spec: pose.earRight,
                      tunerPart: isAnxious || isCatTunable ? 'earRight' : null,
                      designSize: pose.designSize,
                      scaleMultiplier: isDogAnxious ? 1.178 : isCatBored ? 1.184 : 1.0,
                      rotationDeg: earRightRotation,
                      offsetX: anxiousTremor * 0.85,
                      offsetY: bodyOffsetY + headDrop,
                      child: _asset(pose.earRight.assetPath),
                    ),
                    _layer(
                      spec: pose.earLeft,
                      tunerPart: isAnxious || isCatTunable ? 'earLeft' : null,
                      designSize: pose.designSize,
                      scaleMultiplier: isDogAnxious ? 1.160 : isCatBored ? 1.330 : isCatTired ? 0.998 : 1.0,
                      rotationDeg: earLeftRotation,
                      offsetX: anxiousTremor * 0.85,
                      offsetY: bodyOffsetY + headDrop,
                      child: _asset(pose.earLeft.assetPath),
                    ),
                    // The Bored head asset is now neck-cropped, so it can safely
                    // stay in front of the body without creating a double neck.
                    _layer(
                      spec: pose.head,
                      tunerPart: isAnxious || isCatTunable ? 'head' : null,
                      designSize: pose.designSize,
                      scaleMultiplier: isDogAnxious ? 0.905 : 1.0,
                      rotationDeg: headRotation,
                      offsetX: anxiousTremor * 0.85,
                      offsetY: bodyOffsetY + headDrop,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Keep the head fully stable and only blend the
                          // eye-area differences. Both images are pixel-aligned
                          // and identical outside feathered eye regions.
                          _asset(pose.head.assetPath),
                          if (isCatBored)
                            AnimatedOpacity(
                              opacity: _blinking ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeInOutCubic,
                              child: _asset('assets/pets/cat01/bored/head_closed.png'),
                            ),
                          if (isCatHappy)
                            AnimatedOpacity(
                              opacity: _blinking ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 65),
                              curve: Curves.easeInOut,
                              child: _asset('assets/pets/cat01/happy/head_closed.png'),
                            ),
                          if (isCatTired)
                            AnimatedOpacity(
                              opacity: _blinking ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeInOutCubic,
                              child: _asset('assets/pets/cat01/tired/head_closed.png'),
                            ),
                          if (isTired) ...[
                            // Keep mouth, nose and muzzle untouched while eyes
                            // change. Both eye images share the head's canvas.
                            Opacity(
                              opacity: 1.0 - eyeClosedOpacity,
                              child: _asset('assets/pets/dog01/tired/eyes_open.png'),
                            ),
                            if (eyeClosedOpacity > 0.0)
                              Opacity(
                                opacity: eyeClosedOpacity,
                                child: _asset('assets/pets/dog01/tired/eyes_closed.png'),
                              ),
                          ],
                          if (_blinking && widget.pet.blinkFor(widget.mood) != null)
                            CustomPaint(
                              painter: _BlinkPainter(widget.pet.blinkFor(widget.mood)!),
                            ),
                        ],
                      ),
                    ),
                    if (pose.effect != null)
                      isTired
                          ? _buildTiredZzz(pose, bodyOffsetY + headDrop)
                          : _buildMoodEffect(pose, bodyOffsetY, headDrop),
                    _accessoryLayer(
                      pose,
                      headOffsetY: bodyOffsetY + headDrop,
                      headOffsetX: anxiousTremor * 0.85,
                      headRotationDeg: headRotation,
                      bodyOffsetY: bodyOffsetY,
                      bodyOffsetX: anxiousTremor * 0.85,
                    ),
                    _anchorDots(pose),
                    // During tuning, the whole canvas is a drag surface for the
                    // selected layer. This avoids tiny / transparent PNG hitboxes.
                    if (widget.layerTunerEnabled &&
                        (isAnxious || isCatTunable) && widget.onLayerDrag != null)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanUpdate: (details) {
                            final factor = widget.size / pose.designSize;
                            widget.onLayerDrag!(Offset(
                              details.delta.dx / factor,
                              details.delta.dy / factor,
                            ));
                          },
                          child: const SizedBox.expand(),
                        ),
                      ),
                    if (_reacting)
                      Positioned(
                        left: widget.size * 0.52,
                        top: widget.size * 0.08,
                        child: const Text('❤', style: TextStyle(fontSize: 32)),
                      ),
                  ],
                );
              },
            ),
          ),
          ),
        ),
      ),
    );
  }
}

class _BlinkPainter extends CustomPainter {
  const _BlinkPainter(this.spec);

  final BlinkSpec spec;

  @override
  void paint(Canvas canvas, Size size) {
    final facePaint = Paint()
      ..color = spec.faceColor
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = spec.lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.026
      ..strokeCap = StrokeCap.round;

    void drawEye(Offset normalized) {
      final center = Offset(size.width * normalized.dx, size.height * normalized.dy);
      final patchW = size.width * 0.110;
      final patchH = size.height * 0.125;
      canvas.drawOval(
        Rect.fromCenter(center: center, width: patchW, height: patchH),
        facePaint,
      );
      final arc = Rect.fromCenter(
        center: Offset(center.dx, center.dy + patchH * 0.05),
        width: size.width * 0.085,
        height: size.height * 0.040,
      );
      canvas.drawArc(arc, math.pi * 0.08, math.pi * 0.84, false, linePaint);
    }

    drawEye(spec.leftEye);
    drawEye(spec.rightEye);
  }

  @override
  bool shouldRepaint(covariant _BlinkPainter oldDelegate) => oldDelegate.spec != spec;
}
