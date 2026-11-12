// 隊友的 2D 分層寵物元件（pet_preview v4.5.10）。
// 與原版的差別：加了 speed（動畫速度）、衣服圖層加上 Key('pet-accessory')、
// bored 的下沉動作改看實際畫的那組圖（缺圖的心情也畫 bored）。
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

  /// 動畫速度倍率。< 1 放慢（晚上版用來表現想睡的呼吸節奏）。
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
                  .round()),
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

  void _scheduleBlink() {
    _blinkTimer?.cancel();
    final waitMs = 2500 + math.Random().nextInt(1000);
    _blinkTimer = Timer(Duration(milliseconds: waitMs), () async {
      if (!mounted || !widget.animate || widget.pet.blinkFor(widget.mood) == null) {
        _scheduleBlink();
        return;
      }
      setState(() => _blinking = true);
      await Future<void>.delayed(const Duration(milliseconds: 170));
      if (!mounted) return;
      setState(() => _blinking = false);
      _scheduleBlink();
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
      _rebuildController();
      _scheduleBlink();
    } else if (oldWidget.animate != widget.animate) {
      if (widget.animate) {
        _controller.repeat();
        _scheduleBlink();
      } else {
        _controller.stop();
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

  Widget _layer({
    required LayerSpec spec,
    required double designSize,
    required Widget child,
    double rotationDeg = 0,
    double offsetY = 0,
  }) {
    final factor = widget.size / designSize;
    final scale = spec.sourceScale / 100;
    final childWidth = spec.sourceSize.width * scale * factor;
    final childHeight = spec.sourceSize.height * scale * factor;
    final left = (spec.position.dx - spec.sourceAnchor.dx * scale) * factor;
    final top = (spec.position.dy + offsetY - spec.sourceAnchor.dy * scale) * factor;
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
        angle: _deg(spec.rotationDeg + rotationDeg),
        alignment: alignment,
        child: child,
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
    double headRotationDeg = 0,
    double bodyOffsetY = 0,
  }) {
    final accessory = widget.accessory;
    if (accessory == null) return const SizedBox.shrink();

    final base = widget.pet.anchorFor(widget.mood, accessory.slot);
    final tweak = widget.accessoryTweak;
    final factor = widget.size / pose.designSize;
    final sourceSize = 512.0;
    final scale = base.scale * tweak.scale;
    final size = sourceSize * scale * factor;

    // Head/face accessories follow the head. Neck accessories follow the body,
    // so a scarf stays attached to the chest/neck instead of being pulled by
    // extra head-drop motion.
    final followsHead = accessory.slot == AccessorySlot.head ||
        accessory.slot == AccessorySlot.face;
    final followsBody = accessory.slot == AccessorySlot.neck;
    final x = base.position.dx + tweak.dx;
    final animatedOffsetY = followsHead
        ? headOffsetY
        : (followsBody ? bodyOffsetY : 0.0);
    final y = base.position.dy + tweak.dy + animatedOffsetY;
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

  @override
  Widget build(BuildContext context) {
    final pose = widget.pet.poseFor(widget.mood);
    final profile = widget.pet.animationFor(widget.mood);

    return GestureDetector(
      onTap: _react,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: _reacting ? 1.045 : 1,
        child: RepaintBoundary(
          child: SizedBox.square(
            dimension: widget.size,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final phase = (widget.animate ? _controller.value : 0) * 2 * math.pi;
                final tailRotation = profile.tailBaseDeg +
                    profile.tailAmplitudeDeg * math.sin(phase * profile.tailCycles);
                final bodyLift = profile.bodyLift *
                    (1 - math.cos(phase * profile.bodyCycles)) /
                    2;
                final headRotation = profile.headBaseDeg +
                    profile.headAmplitudeDeg *
                        math.sin(phase * profile.headCycles - 0.55);
                final headDrop = profile.headDrop *
                    (1 - math.cos(phase * profile.headDropCycles)) /
                    2;
                // Happy breathes upward; Bored slumps downward so the whole
                // body visibly sinks before the synchronized sigh.
                final bodyOffsetY = widget.pet.resolve(widget.mood) == PetMood.bored
                    ? bodyLift
                    : -bodyLift;
                final earLeftRotation = profile.earLeftBaseDeg +
                    profile.earLeftAmplitudeDeg *
                        math.sin(phase * profile.earLeftCycles + 0.85);
                final earRightRotation = profile.earRightBaseDeg +
                    profile.earRightAmplitudeDeg *
                        math.sin(phase * profile.earRightCycles + 1.65);

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _layer(
                      spec: pose.tail,
                      designSize: pose.designSize,
                      rotationDeg: tailRotation,
                      child: _asset(pose.tail.assetPath),
                    ),
                    _layer(
                      spec: pose.body,
                      designSize: pose.designSize,
                      offsetY: bodyOffsetY,
                      child: _asset(pose.body.assetPath),
                    ),
                    // Ears sit behind the head so they look attached at the roots.
                    _layer(
                      spec: pose.earRight,
                      designSize: pose.designSize,
                      rotationDeg: earRightRotation,
                      offsetY: bodyOffsetY + headDrop,
                      child: _asset(pose.earRight.assetPath),
                    ),
                    _layer(
                      spec: pose.earLeft,
                      designSize: pose.designSize,
                      rotationDeg: earLeftRotation,
                      offsetY: bodyOffsetY + headDrop,
                      child: _asset(pose.earLeft.assetPath),
                    ),
                    // The Bored head asset is now neck-cropped, so it can safely
                    // stay in front of the body without creating a double neck.
                    _layer(
                      spec: pose.head,
                      designSize: pose.designSize,
                      rotationDeg: headRotation,
                      offsetY: bodyOffsetY + headDrop,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _asset(pose.head.assetPath),
                          if (_blinking && widget.pet.blinkFor(widget.mood) != null)
                            CustomPaint(
                              painter: _BlinkPainter(widget.pet.blinkFor(widget.mood)!),
                            ),
                        ],
                      ),
                    ),
                    if (pose.effect != null)
                      _buildMoodEffect(pose, bodyOffsetY, headDrop),
                    _accessoryLayer(
                      pose,
                      headOffsetY: bodyOffsetY + headDrop,
                      headRotationDeg: headRotation,
                      bodyOffsetY: bodyOffsetY,
                    ),
                    _anchorDots(pose),
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
