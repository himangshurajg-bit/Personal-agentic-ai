import 'package:flutter/material.dart';

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
