import 'package:flutter/material.dart';

/// The three color worlds used by the app-wide futuristic visual system.
class FuturisticPalette {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color lightPrimary;
  final Color lightSecondary;
  final Color lightTertiary;
  final Color darkBackground;
  final Color lightBackground;
  final List<Color> orbColors;

  const FuturisticPalette({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.lightPrimary,
    required this.lightSecondary,
    required this.lightTertiary,
    required this.darkBackground,
    required this.lightBackground,
    required this.orbColors,
  });

  Color primaryFor(Brightness brightness) =>
      brightness == Brightness.dark ? primary : lightPrimary;
  Color secondaryFor(Brightness brightness) =>
      brightness == Brightness.dark ? secondary : lightSecondary;
  Color tertiaryFor(Brightness brightness) =>
      brightness == Brightness.dark ? tertiary : lightTertiary;
  Color backgroundFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkBackground : lightBackground;

  static const List<FuturisticPalette> all = [
    FuturisticPalette(
      id: 'aurora',
      name: 'Aurora',
      description: 'Violet · teal',
      icon: Icons.auto_awesome,
      primary: Color(0xffc2a6ff),
      secondary: Color(0xff55ead5),
      tertiary: Color(0xffff91c7),
      lightPrimary: Color(0xff6547b4),
      lightSecondary: Color(0xff007c72),
      lightTertiary: Color(0xffa44377),
      darkBackground: Color(0xff0b0b1a),
      lightBackground: Color(0xfff6f3fc),
      orbColors: [
        Color(0xff72e5ff),
        Color(0xffb497ff),
        Color(0xff60ead1),
        Color(0xffff92c7),
      ],
    ),
    FuturisticPalette(
      id: 'solar',
      name: 'Solar',
      description: 'Amber · coral',
      icon: Icons.wb_sunny_rounded,
      primary: Color(0xffffbd70),
      secondary: Color(0xffff7d8b),
      tertiary: Color(0xffffe38d),
      lightPrimary: Color(0xff9a4b11),
      lightSecondary: Color(0xffb52c52),
      lightTertiary: Color(0xff775800),
      darkBackground: Color(0xff180e17),
      lightBackground: Color(0xfffcf5f0),
      orbColors: [
        Color(0xffffd16f),
        Color(0xffff856f),
        Color(0xffffb45e),
        Color(0xffff77a2),
      ],
    ),
    FuturisticPalette(
      id: 'deep_space',
      name: 'Deep Space',
      description: 'Ice blue · indigo',
      icon: Icons.blur_on_rounded,
      primary: Color(0xff7bdcff),
      secondary: Color(0xff858dff),
      tertiary: Color(0xffb8a7ff),
      lightPrimary: Color(0xff075e91),
      lightSecondary: Color(0xff4b4fae),
      lightTertiary: Color(0xff6842a2),
      darkBackground: Color(0xff080f20),
      lightBackground: Color(0xfff1f5fc),
      orbColors: [
        Color(0xff7be9ff),
        Color(0xff848dff),
        Color(0xffa9c6ff),
        Color(0xffc09fff),
      ],
    ),
  ];

  static FuturisticPalette fromId(String id) =>
      all.firstWhere((palette) => palette.id == id, orElse: () => all.first);
}

/// ThemeExtension keeps the orb and glows in sync with the selected palette,
/// including Flutter's animated transition between theme choices.
@immutable
class PaletteVisuals extends ThemeExtension<PaletteVisuals> {
  final List<Color> orbColors;
  final List<Color> glowColors;

  const PaletteVisuals({required this.orbColors, required this.glowColors});

  @override
  PaletteVisuals copyWith({List<Color>? orbColors, List<Color>? glowColors}) =>
      PaletteVisuals(
        orbColors: orbColors ?? this.orbColors,
        glowColors: glowColors ?? this.glowColors,
      );

  @override
  PaletteVisuals lerp(covariant PaletteVisuals? other, double t) {
    if (other == null) return this;
    return PaletteVisuals(
      orbColors: _lerpColors(orbColors, other.orbColors, t),
      glowColors: _lerpColors(glowColors, other.glowColors, t),
    );
  }

  static List<Color> _lerpColors(List<Color> a, List<Color> b, double t) => [
    for (var i = 0; i < a.length; i++) Color.lerp(a[i], b[i], t) ?? a[i],
  ];
}
