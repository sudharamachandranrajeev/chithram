import 'package:flutter/material.dart';

import 'form_factor.dart';

/// Spacing steps, in dp.
class Space {
  Space._();

  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s48 = 48;
  static const double s64 = 64;
}

/// Corner radii, in dp.
class Radii {
  Radii._();

  static const double chip = 999;
  static const double button = 12;

  /// A pill button (fully rounded).
  static const double pill = 999;
  static const double panel = 20;
  static const double hero = 28;

  /// A card: 14 dp, 12 dp on a TV.
  static double card(FormFactor form) => form == FormFactor.tv ? 12 : 14;
}

/// Animation timing. Use [Motion.of] so "remove animations" is respected.
class Motion {
  const Motion._(this.reduced);

  /// True when the system asks for no animation.
  final bool reduced;

  static const Duration hoverPress = Duration(milliseconds: 120);
  static const Duration focus = Duration(milliseconds: 180);
  static const Duration expand = Duration(milliseconds: 240);
  static const Duration heroChange = Duration(milliseconds: 320);
  static const Curve curve = Curves.easeOutCubic;

  static Motion of(BuildContext context) =>
      Motion._(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  Duration get hoverPressTime => reduced ? Duration.zero : hoverPress;
  Duration get focusTime => reduced ? Duration.zero : focus;
  Duration get expandTime => reduced ? Duration.zero : expand;
  Duration get heroTime => reduced ? Duration.zero : heroChange;
}

/// The type scale for one form factor. Poppins, weights 400 to 700 only (the
/// bundled files). Colours come from the theme, so styles carry none.
class TypeScale {
  const TypeScale._(this.form);

  factory TypeScale.of(FormFactor form) => TypeScale._(form);

  final FormFactor form;

  double _pick(double desktop, double tv, double phone) => switch (form) {
        FormFactor.desktop => desktop,
        FormFactor.tv => tv,
        FormFactor.phone => phone,
      };

  TextStyle get hero => TextStyle(fontSize: _pick(44, 36, 26), fontWeight: FontWeight.w700);
  TextStyle get h1 => TextStyle(fontSize: _pick(28, 28, 22), fontWeight: FontWeight.w700);
  TextStyle get row => TextStyle(fontSize: _pick(20, 22, 18), fontWeight: FontWeight.w600);
  TextStyle get card => TextStyle(fontSize: _pick(15, 18, 15), fontWeight: FontWeight.w600);
  TextStyle get body => TextStyle(fontSize: _pick(14, 18, 15), fontWeight: FontWeight.w400);
  TextStyle get meta => TextStyle(fontSize: _pick(12, 16, 12), fontWeight: FontWeight.w500);
  TextStyle get overline => TextStyle(
        fontSize: _pick(11, 15, 11),
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      );
}

/// How a focused control looks. A TV scales the control and glows; a desktop
/// draws an offset ring.
class FocusSpec {
  const FocusSpec._({
    required this.scale,
    required this.gap,
    required this.ring,
    required this.glowAlpha,
    required this.glowBlur,
  });

  /// Scale of the focused control (1 = none).
  final double scale;

  /// Gap between the control and its ring, in dp.
  final double gap;

  /// Ring thickness, in dp.
  final double ring;

  /// Opacity of the accent glow (0 = no glow).
  final double glowAlpha;
  final double glowBlur;

  static const tv = FocusSpec._(scale: 1.06, gap: 2, ring: 3, glowAlpha: 0.45, glowBlur: 24);
  static const desktop = FocusSpec._(scale: 1, gap: 2, ring: 2, glowAlpha: 0, glowBlur: 0);

  static FocusSpec of(FormFactor form) => form == FormFactor.tv ? tv : desktop;
}
