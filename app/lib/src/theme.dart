import 'package:flutter/material.dart';

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

ThemeData buildChithramTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: ChithramColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: ChithramColors.accent,
    onPrimary: Colors.black,
    surface: ChithramColors.surface,
  );
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
