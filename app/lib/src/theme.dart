import 'package:flutter/material.dart';

import 'ui/form_factor.dart';

/// Chithram's look, defined once. Dark, with a saffron-gold accent.
class ChithramColors {
  ChithramColors._();

  /// The accent: deep saffron / gold.
  static const Color accent = Color(0xFFF5A300);
  static const Color background = Color(0xFF0B0B10);
  static const Color surface = Color(0xFF16161E);
  static const Color surfaceHigh = Color(0xFF22222D);
  static const Color textDim = Color(0xFF9A9AAB);
}

/// The theme for [form]. A TV (and desktop) draws its own focus glow and has
/// no touch feedback; a phone gets ripples, padded tap targets, the M3 type
/// scale and predictive back.
ThemeData buildChithramTheme({FormFactor form = FormFactor.tv}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: ChithramColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: ChithramColors.accent,
    onPrimary: Colors.black,
    surface: ChithramColors.surface,
  );
  if (form == FormFactor.phone) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Poppins',
      scaffoldBackgroundColor: ChithramColors.background,
      canvasColor: ChithramColors.background,
      focusColor: Colors.transparent,
      splashFactory: InkSparkle.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      textTheme: Typography.material2021().white.apply(fontFamily: 'Poppins'),
      appBarTheme: const AppBarTheme(
        backgroundColor: ChithramColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: ChithramColors.surface,
        indicatorColor: ChithramColors.accent.withValues(alpha: 0.25),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      }),
    );
  }
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Poppins',
    scaffoldBackgroundColor: ChithramColors.background,
    canvasColor: ChithramColors.background,
    // The app draws its own focus glow.
    focusColor: Colors.transparent,
    splashFactory: NoSplash.splashFactory,
  );
}
