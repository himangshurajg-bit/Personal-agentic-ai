import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import 'visual_theme.dart';

/// Adds a short, directional 3D press to an existing control without taking
/// over its gesture, focus, semantics, or accessibility action.
class TapMotion extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final double depth;

  const TapMotion({
    super.key,
    required this.child,
    this.enabled = true,
    this.depth = 1,
  });

  @override
  State<TapMotion> createState() => _TapMotionState();
}

class _TapMotionState extends State<TapMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 210),
    reverseDuration: const Duration(milliseconds: 170),
  );
  int? _pointer;
  Offset _tilt = Offset.zero;

  void _handleDown(PointerDownEvent event) {
    if (!widget.enabled || MediaQuery.disableAnimationsOf(context)) return;
    _pointer = event.pointer;
    _updateTilt(event.localPosition);
    _controller.forward();
  }

  void _handleMove(PointerMoveEvent event) {
    if (_pointer == event.pointer && widget.enabled) {
      _updateTilt(event.localPosition);
    }
  }

  void _updateTilt(Offset localPosition) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final size = renderObject.size;
    if (size.width <= 0 || size.height <= 0) return;
    final next = Offset(
      (localPosition.dx / size.width - .5).clamp(-.5, .5).toDouble(),
      (localPosition.dy / size.height - .5).clamp(-.5, .5).toDouble(),
    );
    if ((next - _tilt).distance < .025) return;
    setState(() => _tilt = next);
  }

  void _handleUp(PointerEvent event) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    _controller.reverse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleDown,
      onPointerMove: _handleMove,
      onPointerUp: _handleUp,
      onPointerCancel: _handleUp,
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final press = reduceMotion
              ? 0.0
              : Curves.easeOutBack
                    .transform(_controller.value)
                    .clamp(0.0, 1.0)
                    .toDouble();
          final matrix = Matrix4.identity()
            ..setEntry(3, 2, .0016)
            ..rotateX(-_tilt.dy * .25 * press * widget.depth)
            ..rotateY(_tilt.dx * .28 * press * widget.depth)
            ..scaleByDouble(
              1 - .035 * press * widget.depth,
              1 - .035 * press * widget.depth,
              1 - .035 * press * widget.depth,
              1,
            );
          return Transform(
            alignment: Alignment.center,
            transform: matrix,
            child: child,
          );
        },
      ),
    );
  }
}

/// A perspective transition for route changes, with a reduced-motion fallback.
class GlassDepthPageTransitionsBuilder extends PageTransitionsBuilder {
  const GlassDepthPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) return child;

    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      child: child,
      builder: (context, child) {
        final enter = Curves.easeOutBack
            .transform(animation.value)
            .clamp(0.0, 1.0)
            .toDouble();
        final leave = Curves.easeInCubic
            .transform(secondaryAnimation.value)
            .clamp(0.0, 1.0)
            .toDouble();
        final matrix = Matrix4.identity()
          ..setEntry(3, 2, .0014)
          ..rotateY((1 - enter) * .22 - leave * .075)
          ..rotateX((1 - enter) * .045)
          ..scaleByDouble(
            (.91 + .09 * enter) * (1 - .025 * leave),
            (.91 + .09 * enter) * (1 - .025 * leave),
            (.91 + .09 * enter) * (1 - .025 * leave),
            1,
          );
        final opacity = ((.35 + .65 * enter) * (1 - .22 * leave))
            .clamp(0.0, 1.0)
            .toDouble();
        return Opacity(
          opacity: opacity,
          child: Transform(
            alignment: Alignment.center,
            transform: matrix,
            child: child,
          ),
        );
      },
    );
  }
}

/// A restrained glow for controls that are actively listening or working.
/// It stops while idle, off-screen or when the user requests reduced motion.
class ActivityHalo extends StatefulWidget {
  final Widget child;
  final bool active;
  final Color color;
  final double strength;

  const ActivityHalo({
    super.key,
    required this.child,
    required this.active,
    required this.color,
    this.strength = 1,
  });

  @override
  State<ActivityHalo> createState() => _ActivityHaloState();
}

class _ActivityHaloState extends State<ActivityHalo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  );

  void _syncAnimation() {
    if (!widget.active ||
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant ActivityHalo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active || oldWidget.color != widget.color) {
      _syncAnimation();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      final reduced = MediaQuery.disableAnimationsOf(context);
      final phase = widget.active ? (reduced ? .4 : _controller.value) : 0.0;
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          boxShadow: widget.active
              ? [
                  BoxShadow(
                    color: widget.color.withValues(
                      alpha: (.10 + .12 * phase) * widget.strength,
                    ),
                    blurRadius: 12 + 16 * phase,
                    spreadRadius: phase * 1.5,
                  ),
                ]
              : null,
        ),
        child: child,
      );
    },
  );
}

enum HolographicOrbState { idle, listening, thinking, speaking }

/// A custom-painted particle-mesh assistant orb. It is decorative and never
/// captures gestures; animation is paused for reduced motion and ticker-off.
class HolographicAssistantOrb extends StatefulWidget {
  final HolographicOrbState state;
  final double size;
  final double audioLevel;

  const HolographicAssistantOrb({
    super.key,
    this.state = HolographicOrbState.idle,
    this.size = 128,
    this.audioLevel = 0,
  });

  @override
  State<HolographicAssistantOrb> createState() => _HolographicOrbState();
}

class _HolographicOrbState extends State<HolographicAssistantOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: _durationFor(widget.state),
  );

  static Duration _durationFor(HolographicOrbState state) => switch (state) {
    HolographicOrbState.idle => const Duration(seconds: 34),
    HolographicOrbState.listening => const Duration(seconds: 5),
    HolographicOrbState.thinking => const Duration(seconds: 7),
    HolographicOrbState.speaking => const Duration(seconds: 4),
  };

  void _syncMotion() {
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _rotation.stop();
      _rotation.value = 0.12;
    } else if (!_rotation.isAnimating) {
      _rotation.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant HolographicAssistantOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _rotation.duration = _durationFor(widget.state);
      _syncMotion();
    }
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orbColors =
        Theme.of(context).extension<PaletteVisuals>()?.orbColors ??
        const [
          Color(0xff75d9ff),
          Color(0xffb18cff),
          Color(0xffff8eae),
          Color(0xffffb16f),
        ];
    final colors = switch (widget.state) {
      HolographicOrbState.idle => orbColors,
      HolographicOrbState.listening => [
        orbColors[2],
        orbColors[0],
        orbColors[1],
        orbColors[3],
      ],
      HolographicOrbState.thinking => [
        orbColors[1],
        orbColors[3],
        orbColors[0],
        orbColors[2],
      ],
      HolographicOrbState.speaking => [
        orbColors[2],
        orbColors[3],
        orbColors[0],
        orbColors[1],
      ],
    };
    final label = switch (widget.state) {
      HolographicOrbState.idle => 'Assistant is ready',
      HolographicOrbState.listening => 'Assistant is listening',
      HolographicOrbState.thinking => 'Assistant is thinking',
      HolographicOrbState.speaking => 'Assistant is speaking',
    };
    return Semantics(
      label: label,
      liveRegion: widget.state != HolographicOrbState.idle,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: widget.size,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _rotation,
              builder: (context, _) => CustomPaint(
                painter: _HolographicAssistantOrbPainter(
                  phase: _rotation.value,
                  state: widget.state,
                  colors: colors,
                  audioLevel: widget.audioLevel,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HolographicAssistantOrbPainter extends CustomPainter {
  final double phase;
  final HolographicOrbState state;
  final List<Color> colors;
  final double audioLevel;

  const _HolographicAssistantOrbPainter({
    required this.phase,
    required this.state,
    required this.colors,
    required this.audioLevel,
  });

  double get _activity => switch (state) {
    HolographicOrbState.idle => .08,
    HolographicOrbState.listening => .65 + .35 * (audioLevel / 20).clamp(0, 1),
    HolographicOrbState.thinking => .8,
    HolographicOrbState.speaking => .75,
  };

  void _drawOrbitalGyre(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required double phase,
    required double activity,
    required double pulse,
    required List<Color> colors,
    required bool foreground,
  }) {
    const tilt = -.34;
    final orbitRadius = radius * 1.27;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(tilt);
    canvas.scale(1, .39);
    final orbit = Rect.fromCircle(center: Offset.zero, radius: orbitRadius);
    final tint = colors[0];
    if (foreground) {
      canvas.drawArc(
        orbit,
        0,
        math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = radius * .045
          ..color = tint.withValues(alpha: .24 + .16 * activity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawArc(
        orbit,
        0,
        math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = radius * .012
          ..color = Color.lerp(
            tint,
            Colors.white,
            .48,
          )!.withValues(alpha: .52 + .26 * pulse),
      );
    } else {
      canvas.drawOval(
        orbit,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius * .014
          ..color = colors[1].withValues(alpha: .27 + .12 * activity),
      );
      final nodeAngle = phase * (state == HolographicOrbState.idle ? .42 : .9);
      final node = Offset(
        math.cos(nodeAngle) * orbitRadius,
        math.sin(nodeAngle) * orbitRadius,
      );
      canvas.drawCircle(
        node,
        radius * .045,
        Paint()
          ..color = colors[2].withValues(alpha: .58 + .32 * pulse)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawCircle(
        node,
        radius * .016,
        Paint()..color = Colors.white.withValues(alpha: .88),
      );
    }
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final shortest = size.shortestSide;
    if (shortest <= 1) return;
    final angle = phase * math.pi * 2;
    final activity = _activity;
    final pulse =
        .5 +
        .5 * math.sin(angle * (state == HolographicOrbState.speaking ? 3 : 1));
    // The whole sphere floats and breathes; its longitude field below rotates too.
    final center = size
        .center(Offset.zero)
        .translate(
          math.sin(angle * .7) * shortest * .018,
          math.cos(angle * .9) * shortest * .021,
        );
    final radius = shortest * .345;
    final breathing = 1 + (.026 + .024 * activity) * pulse;
    final orbRadius = radius * breathing;

    // Original glass-orbit treatment: a fine, tilted gyre and a moving
    // light node give the sphere a crafted instrument-like silhouette.
    _drawOrbitalGyre(
      canvas,
      center: center,
      radius: orbRadius,
      phase: angle,
      activity: activity,
      pulse: pulse,
      colors: colors,
      foreground: false,
    );

    // A broad, softly colored bloom sits behind the dark glass sphere.
    final auraRect = Rect.fromCircle(center: center, radius: radius * 1.65);
    canvas.drawCircle(
      center,
      radius * 1.5,
      Paint()
        ..shader = RadialGradient(
          colors: [
            colors[0].withValues(alpha: .20 + .10 * activity * pulse),
            colors[1].withValues(alpha: .13),
            colors[2].withValues(alpha: .06),
            Colors.transparent,
          ],
          stops: const [0, .40, .70, 1],
        ).createShader(auraRect),
    );

    // Sphere body with a cool luminous crown and a warm reflected lower edge.
    final sphereRect = Rect.fromCircle(center: center, radius: orbRadius);
    canvas.drawCircle(
      center,
      orbRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.30, -.38),
          radius: 1.12,
          colors: const [
            Color(0xff25365a),
            Color(0xff11152d),
            Color(0xff080a17),
            Color(0xff04050b),
          ],
          stops: const [0, .36, .78, 1],
        ).createShader(sphereRect),
    );

    final clip = Path()..addOval(sphereRect);
    canvas.save();
    canvas.clipPath(clip);
    // The latitude/longitude point field gives a holographic particle shell.
    // Scale mesh density with the rendered size so tiny status orbs stay light.
    final latitudeCount = shortest >= 130 ? 17 : 11;
    final longitudeCount = shortest >= 130 ? 40 : 25;
    final points = List.generate(
      latitudeCount,
      (row) => List<({Offset point, double depth, double latitude})>.generate(
        longitudeCount,
        (column) {
          final latitude = -math.pi / 2 + math.pi * (row + .5) / latitudeCount;
          final longitude =
              math.pi * 2 * column / longitudeCount + angle * 1.18;
          final ripple =
              math.sin(longitude * 3 + angle * 1.5) *
              math.cos(latitude * 4 - angle) *
              (.035 + .025 * activity);
          final lat = latitude + ripple;
          final x = math.cos(lat) * math.sin(longitude);
          final y = math.sin(lat);
          final z = math.cos(lat) * math.cos(longitude);
          final tilt = .20 + .12 * math.sin(angle * .55);
          final tiltY = y * math.cos(tilt) - z * math.sin(tilt);
          final depth = y * math.sin(tilt) + z * math.cos(tilt);
          return (
            point: Offset(
              center.dx + x * orbRadius,
              center.dy + tiltY * orbRadius,
            ),
            depth: depth,
            latitude: latitude,
          );
        },
      ),
    );

    final meshPath = Path();
    for (var row = 0; row < latitudeCount; row++) {
      for (var column = 0; column < longitudeCount; column++) {
        final current = points[row][column];
        final next = points[row][(column + 1) % longitudeCount];
        final frontness = ((current.depth + next.depth) / 2 + .22).clamp(
          0.0,
          1.0,
        );
        if (frontness > .08) {
          meshPath
            ..moveTo(current.point.dx, current.point.dy)
            ..lineTo(next.point.dx, next.point.dy);
        }
        if (row + 1 < latitudeCount) {
          final below = points[row + 1][column];
          final verticalFrontness = ((current.depth + below.depth) / 2 + .22)
              .clamp(0.0, 1.0);
          if (verticalFrontness > .08) {
            meshPath
              ..moveTo(current.point.dx, current.point.dy)
              ..lineTo(below.point.dx, below.point.dy);
          }
        }
      }
    }
    canvas.drawPath(
      meshPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(.55, shortest * .0038)
        ..shader = SweepGradient(
          colors: [colors[0], colors[1], colors[2], colors[3], colors[0]],
        ).createShader(sphereRect)
        ..color = Colors.white.withValues(alpha: .48 + .12 * activity),
    );

    // Batch particles by latitude row to keep the detailed shell inexpensive.
    for (var row = 0; row < latitudeCount; row++) {
      final visiblePoints = <Offset>[];
      for (var column = 0; column < longitudeCount; column++) {
        final particle = points[row][column];
        final visibility = ((particle.depth + .35) / 1.35).clamp(0.0, 1.0);
        if (visibility > .08) visiblePoints.add(particle.point);
      }
      if (visiblePoints.isEmpty) continue;
      final rowFraction = row / math.max(1, latitudeCount - 1);
      final tint = Color.lerp(colors[0], colors[3], rowFraction)!;
      canvas.drawPoints(
        PointMode.points,
        visiblePoints,
        Paint()
          ..color = tint.withValues(alpha: .70 + .24 * pulse)
          ..strokeWidth = shortest * (shortest >= 130 ? .011 : .012)
          ..strokeCap = StrokeCap.round,
      );
    }

    // Three interwoven neural veils echo the references: a point-cloud globe,
    // flowing wave contours, and bright branching signal filaments. Their paths
    // are clipped to the actual sphere, so the core has depth rather than a flat halo.
    final veilCount = shortest >= 130 ? 13 : 8;
    for (var veil = 0; veil < veilCount; veil++) {
      final t = veil / veilCount;
      final path = Path();
      for (var step = 0; step <= 32; step++) {
        final u = step / 32;
        final theta = u * math.pi * 2 + angle * (veil.isEven ? .42 : -.31);
        final wave =
            math.sin(theta * (2.0 + (veil % 3)) + angle * 1.7 + veil) *
            (.035 + .025 * activity);
        final latitude = (t * 2 - 1) * 1.05 + wave;
        final x = math.cos(latitude) * math.sin(theta);
        final y = math.sin(latitude);
        final z = math.cos(latitude) * math.cos(theta);
        final depth = y * .31 + z * .95;
        final point = Offset(
          center.dx + x * orbRadius,
          center.dy + (y * .95 - z * .31) * orbRadius,
        );
        if (step == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
        // A moving luminous packet runs along selected filaments.
        final packet =
            (phase * (state == HolographicOrbState.idle ? .55 : 1.2) + t) % 1;
        if ((veil % 3 == 0) && (u - packet).abs() < .035 && depth > -.12) {
          final packetPaint = Paint()
            ..color = colors[(veil + 1) % colors.length].withValues(
              alpha: (.42 + .48 * pulse) * ((depth + 1) / 2).clamp(0.0, 1.0),
            )
            ..strokeWidth = shortest * .009
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
          canvas.drawCircle(point, shortest * .008, packetPaint);
        }
      }
      final veilColor = colors[veil % colors.length];
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = shortest * (veil % 4 == 0 ? .0042 : .0021)
          ..strokeCap = StrokeCap.round
          ..color = veilColor.withValues(
            alpha: (.17 + .20 * activity) * (.68 + .32 * pulse),
          )
          ..maskFilter = veil % 4 == 0
              ? const MaskFilter.blur(BlurStyle.normal, 3)
              : null,
      );
    }

    // Branching lightning nerves travel across the globe; each is a curved,
    // softly blooming filament with a crisp inner stroke for a sculpted glow.
    final nerveCount = shortest >= 130 ? 9 : 5;
    for (var nerve = 0; nerve < nerveCount; nerve++) {
      final start = nerve / nerveCount * math.pi * 2 + angle * .37;
      final path = Path();
      for (var step = 0; step <= 12; step++) {
        final u = step / 12;
        final theta = start + u * (1.25 + .35 * math.sin(nerve.toDouble()));
        final latitude =
            -.78 + u * 1.56 + .055 * math.sin(u * 19 + nerve + angle * 2);
        final x = math.cos(latitude) * math.sin(theta);
        final y = math.sin(latitude);
        final z = math.cos(latitude) * math.cos(theta);
        final depth = y * .31 + z * .95;
        final point = Offset(
          center.dx + x * orbRadius,
          center.dy + (y * .95 - z * .31) * orbRadius,
        );
        if (step == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
        if (step % 4 == 0 && step > 0 && depth > -.12) {
          final branch = Path()
            ..moveTo(point.dx, point.dy)
            ..quadraticBezierTo(
              point.dx + math.cos(start + nerve) * shortest * .07,
              point.dy + math.sin(start + nerve) * shortest * .06,
              point.dx + math.cos(start + nerve) * shortest * .13,
              point.dy + math.sin(start + nerve) * shortest * .12,
            );
          canvas.drawPath(
            branch,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = shortest * .0024
              ..color = colors[(nerve + 2) % colors.length].withValues(
                alpha: .28 + .28 * pulse,
              ),
          );
        }
      }
      final tint = colors[(nerve + 2) % colors.length];
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = shortest * .012
        ..strokeCap = StrokeCap.round
        ..color = tint.withValues(alpha: .18 + .16 * activity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawPath(path, glow);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = shortest * .0027
          ..strokeCap = StrokeCap.round
          ..color = Color.lerp(
            tint,
            Colors.white,
            .42,
          )!.withValues(alpha: .58 + .32 * pulse),
      );
    }

    // Inner luminous nucleus and volumetric highlights make the particle shell
    // read as a glassy, dimensional object rather than a wireframe sticker.
    final nucleus = Rect.fromCircle(
      center: center.translate(-orbRadius * .10, -orbRadius * .08),
      radius: orbRadius * .49,
    );
    canvas.drawCircle(
      center.translate(-orbRadius * .10, -orbRadius * .08),
      orbRadius * .49,
      Paint()
        ..shader = RadialGradient(
          colors: [
            colors[0].withValues(alpha: .22 + .12 * pulse),
            colors[1].withValues(alpha: .08),
            Colors.transparent,
          ],
          stops: const [0, .55, 1],
        ).createShader(nucleus),
    );
    final coreSpark = center.translate(
      math.sin(angle * 1.9) * orbRadius * .12,
      math.cos(angle * 1.4) * orbRadius * .10,
    );
    canvas.drawCircle(
      coreSpark,
      shortest * (.012 + .006 * pulse),
      Paint()
        ..color = colors[0].withValues(alpha: .42 + .28 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      coreSpark,
      shortest * .006,
      Paint()..color = Colors.white.withValues(alpha: .84),
    );

    // Holographic vertical glints and a low warm reflection add depth.
    final glintRect = Rect.fromCircle(
      center: center.translate(-orbRadius * .18, -orbRadius * .18),
      radius: orbRadius * .92,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(-orbRadius * .34, 0),
        width: orbRadius * .16,
        height: orbRadius * 1.46,
      ),
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            colors[0].withValues(alpha: .15 + .18 * activity),
            Colors.white.withValues(alpha: .10),
            Colors.transparent,
          ],
        ).createShader(glintRect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.restore();

    // The lower sweep catches the light in front of the sphere, completing
    // the gyre's depth cue without obscuring the central glass detail.
    _drawOrbitalGyre(
      canvas,
      center: center,
      radius: orbRadius,
      phase: angle,
      activity: activity,
      pulse: pulse,
      colors: colors,
      foreground: true,
    );

    // Bright partial rim: cool on top, violet through the middle, warm below.
    final rimRect = Rect.fromCircle(center: center, radius: orbRadius * .985);
    canvas.drawArc(
      rimRect,
      math.pi * 1.08,
      math.pi * .84,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = shortest * .012
        ..strokeCap = StrokeCap.round
        ..color = colors[0].withValues(alpha: .55 + .25 * activity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawArc(
      rimRect,
      math.pi * .02,
      math.pi * .91,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = shortest * .009
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: [colors[1], colors[2], colors[3], colors[1]],
        ).createShader(rimRect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // A light orbit and moving spark reinforce the 3D hologram silhouette.
    final orbitRect = Rect.fromCenter(
      center: center,
      width: radius * 2.52,
      height: radius * .82,
    );
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-.30 + .16 * math.sin(angle));
    canvas.translate(-center.dx, -center.dy);
    canvas.drawOval(
      orbitRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = shortest * .0028
        ..color = colors[0].withValues(alpha: .16 + .12 * activity),
    );
    final sparkAngle = angle * (state == HolographicOrbState.idle ? .5 : 1.1);
    final spark = Offset(
      center.dx + math.cos(sparkAngle) * orbitRect.width / 2,
      center.dy + math.sin(sparkAngle) * orbitRect.height / 2,
    );
    canvas.drawCircle(
      spark,
      shortest * .012,
      Paint()
        ..color = colors[0].withValues(alpha: .88)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(spark, shortest * .0045, Paint()..color = Colors.white);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HolographicAssistantOrbPainter oldDelegate) =>
      phase != oldDelegate.phase ||
      state != oldDelegate.state ||
      audioLevel != oldDelegate.audioLevel ||
      colors != oldDelegate.colors;
}
