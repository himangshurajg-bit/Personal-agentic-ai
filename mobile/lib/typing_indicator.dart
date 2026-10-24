import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

/// A compact glass typing cue for the assistant's in-progress chat response.
class GlassTypingIndicator extends StatefulWidget {
  const GlassTypingIndicator({super.key});

  @override
  State<GlassTypingIndicator> createState() => _GlassTypingIndicatorState();
}

class _GlassTypingIndicatorState extends State<GlassTypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1260),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse
        ..stop()
        ..value = 0;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final radius = BorderRadius.circular(22);

    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Assistant is typing',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: dark ? .25 : .16),
              blurRadius: 22,
              spreadRadius: -5,
              offset: const Offset(0, 7),
            ),
            BoxShadow(
              color: scheme.tertiary.withValues(alpha: dark ? .14 : .10),
              blurRadius: 26,
              spreadRadius: -8,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: dark ? .16 : .61),
                    scheme.surface.withValues(alpha: dark ? .53 : .58),
                    scheme.primary.withValues(alpha: dark ? .10 : .06),
                  ],
                ),
                borderRadius: radius,
                border: Border.all(
                  color: Colors.white.withValues(alpha: dark ? .35 : .78),
                ),
              ),
              child: ExcludeSemantics(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(3, (index) {
                      final wave = reduceMotion
                          ? .58
                          : (math.sin(
                                      _pulse.value * math.pi * 2 -
                                          index * math.pi * 2 / 3,
                                    ) +
                                    1) /
                                2;
                      final accent = index.isEven
                          ? scheme.primary
                          : scheme.tertiary;
                      final glow = reduceMotion ? .18 : .10 + wave * .30;
                      return Padding(
                        padding: EdgeInsets.only(left: index == 0 ? 0 : 8),
                        child: Opacity(
                          opacity: reduceMotion ? .68 : .32 + wave * .64,
                          child: Transform.scale(
                            key: ValueKey('typing-scale-$index'),
                            scale: reduceMotion ? .96 : .80 + wave * .28,
                            child: Container(
                              key: ValueKey('typing-dot-$index'),
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    Colors.white.withValues(
                                      alpha: dark ? .98 : 1,
                                    ),
                                    accent.withValues(alpha: dark ? .88 : .78),
                                    accent.withValues(alpha: dark ? .60 : .52),
                                  ],
                                ),
                                border: Border.all(
                                  color: Colors.white.withValues(
                                    alpha: dark ? .82 : .94,
                                  ),
                                  width: .8,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: accent.withValues(alpha: glow),
                                    blurRadius: 7 + wave * 9,
                                    spreadRadius: wave * 1.2,
                                  ),
                                  BoxShadow(
                                    color: scheme.tertiary.withValues(
                                      alpha: glow * .42,
                                    ),
                                    blurRadius: 13,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
