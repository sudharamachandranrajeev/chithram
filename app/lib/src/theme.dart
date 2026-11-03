import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/prefs.dart';
import 'ui/common/form_factor.dart';

/// Prefs keys for the look (see [ChithramTheme.fromPrefs]).
class ThemePrefs {
  ThemePrefs._();

  /// The preset's id; absent means the default.
  static const preset = 'theme.preset';

  /// A custom accent, as an ARGB int; absent means the preset's own.
  static const accent = 'theme.accent';

  /// True: pure black background (OLED), any accent.
  static const amoled = 'theme.amoled';
}

/// Chithram's colours as data: one set per look, carried by [ThemeData] as an
/// extension and read with [ChithramColors.of].
@immutable
class ChithramTheme extends ThemeExtension<ChithramTheme> {
  const ChithramTheme({
    required this.accent,
    required this.onAccent,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.text,
    required this.textDim,
    required this.heroTint,
    this.accent2 = const Color(0xFF9B87FF),
    this.status = StatusColors.standard,
  });

  /// The accent: focus glow, selected state, primary buttons.
  final Color accent;

  /// Text and icons drawn on [accent] (black or white, whichever reads better).
  final Color onAccent;
  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color text;
  final Color textDim;

  /// The corner glow of the Home hero gradient.
  final Color heroTint;

  /// The secondary accent (progress, secondary highlights).
  final Color accent2;

  /// The colours of the request statuses (see `StatusChip`).
  final StatusColors status;

  /// The default look: lime on a deep violet-black.
  static const night = ChithramTheme(
    accent: Color(0xFFC6F432),
    onAccent: Color(0xFF0E0B12),
    background: Color(0xFF0E0B12),
    surface: Color(0xFF18141E),
    surfaceHigh: Color(0xFF241E2C),
    text: Color(0xFFF5F3F7),
    textDim: Color(0xFFABA4B6),
    heroTint: Color(0x59C6F432),
    accent2: Color(0xFF9B87FF),
  );

  /// The original look: saffron / gold on near-black.
  static const saffron = ChithramTheme(
    accent: Color(0xFFF5A300),
    onAccent: Color(0xFF000000),
    background: Color(0xFF0B0B10),
    surface: Color(0xFF16161E),
    surfaceHigh: Color(0xFF22222D),
    text: Color(0xFFFFFFFF),
    textDim: Color(0xFF9A9AAB),
    heroTint: Color(0x59F5A300),
  );

  /// Black or white, whichever has the higher contrast on [accent].
  static Color onColor(Color accent) {
    final black = contrastRatio(accent, Colors.black);
    final white = contrastRatio(accent, Colors.white);
    return black >= white ? Colors.black : Colors.white;
  }

  /// The WCAG contrast ratio of two opaque colours (1 to 21).
  static double contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// A see-through panel over the page (sidebars, bars, chips): [surface]
  /// let through, so the hero glow shows under it.
  Color get glass => surface.withValues(alpha: 0.72);

  /// The hairline edge of a [glass] panel.
  Color get glassEdge => hairline;

  /// A 1 dp divider or outline: [text] at 8%.
  Color get hairline => text.withValues(alpha: 0.08);

  /// This look with another accent; [onAccent] and [heroTint] follow.
  ChithramTheme withAccent(Color accent) =>
      copyWith(accent: accent, onAccent: onColor(accent), heroTint: accent.withAlpha(0x59));

  /// This look on a pure black background; surfaces sink toward black too.
  ChithramTheme toAmoled() => copyWith(
        background: Colors.black,
        surface: Color.lerp(surface, Colors.black, 0.55),
        surfaceHigh: Color.lerp(surfaceHigh, Colors.black, 0.4),
      );

  /// The look saved in [prefs]: preset, optional custom accent, AMOLED flag.
  /// Unknown or missing values fall back to the default.
  static ChithramTheme fromPrefs(Prefs prefs) {
    var t = ThemePreset.resolve(prefs.getString(ThemePrefs.preset)).theme;
    final accent = prefs.getInt(ThemePrefs.accent);
    if (accent != null) t = t.withAccent(Color(accent | 0xFF000000));
    if (prefs.getBool(ThemePrefs.amoled)) t = t.toAmoled();
    return t;
  }

  @override
  ChithramTheme copyWith({
    Color? accent,
    Color? onAccent,
    Color? background,
    Color? surface,
    Color? surfaceHigh,
    Color? text,
    Color? textDim,
    Color? heroTint,
    Color? accent2,
    StatusColors? status,
  }) =>
      ChithramTheme(
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceHigh: surfaceHigh ?? this.surfaceHigh,
        text: text ?? this.text,
        textDim: textDim ?? this.textDim,
        heroTint: heroTint ?? this.heroTint,
        accent2: accent2 ?? this.accent2,
        status: status ?? this.status,
      );

  @override
  ChithramTheme lerp(ThemeExtension<ChithramTheme>? other, double t) {
    if (other is! ChithramTheme) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return ChithramTheme(
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceHigh: l(surfaceHigh, other.surfaceHigh),
      text: l(text, other.text),
      textDim: l(textDim, other.textDim),
      heroTint: l(heroTint, other.heroTint),
      accent2: l(accent2, other.accent2),
      status: StatusColors.lerp(status, other.status, t),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChithramTheme &&
      other.accent == accent &&
      other.onAccent == onAccent &&
      other.background == background &&
      other.surface == surface &&
      other.surfaceHigh == surfaceHigh &&
      other.text == text &&
      other.textDim == textDim &&
      other.heroTint == heroTint &&
      other.accent2 == accent2 &&
      other.status == status;

  @override
  int get hashCode =>
      Object.hash(accent, onAccent, background, surface, surfaceHigh, text, textDim, heroTint, accent2, status);
}

/// One colour per request status. The same on every look: a status keeps its
/// meaning when the accent changes.
@immutable
class StatusColors {
  const StatusColors({
    required this.requested,
    required this.awaitingApproval,
    required this.searching,
    required this.downloading,
    required this.importing,
    required this.available,
    required this.failed,
  });

  final Color requested;
  final Color awaitingApproval;
  final Color searching;
  final Color downloading;
  final Color importing;
  final Color available;
  final Color failed;

  static const standard = StatusColors(
    requested: Color(0xFFABA4B6),
    awaitingApproval: Color(0xFFF5B83D),
    searching: Color(0xFF5AA9FF),
    downloading: Color(0xFF9B87FF),
    importing: Color(0xFF3DD6D0),
    available: Color(0xFF3DDC84),
    failed: Color(0xFFFF6B6B),
  );

  static StatusColors lerp(StatusColors a, StatusColors b, double t) {
    Color l(Color x, Color y) => Color.lerp(x, y, t)!;
    return StatusColors(
      requested: l(a.requested, b.requested),
      awaitingApproval: l(a.awaitingApproval, b.awaitingApproval),
      searching: l(a.searching, b.searching),
      downloading: l(a.downloading, b.downloading),
      importing: l(a.importing, b.importing),
      available: l(a.available, b.available),
      failed: l(a.failed, b.failed),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StatusColors &&
      other.requested == requested &&
      other.awaitingApproval == awaitingApproval &&
      other.searching == searching &&
      other.downloading == downloading &&
      other.importing == importing &&
      other.available == available &&
      other.failed == failed;

  @override
  int get hashCode =>
      Object.hash(requested, awaitingApproval, searching, downloading, importing, available, failed);
}

/// A hand-picked dark look.
class ThemePreset {
  const ThemePreset(this.id, this.name, this.theme);

  final String id;
  final String name;
  final ChithramTheme theme;

  static ThemePreset? byId(String? id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  static ChithramTheme _dark(int accent, int bg, int surface, int high, int dim) =>
      ChithramTheme(
        accent: Color(accent),
        onAccent: ChithramTheme.onColor(Color(accent)),
        background: Color(bg),
        surface: Color(surface),
        surfaceHigh: Color(high),
        text: const Color(0xFFFFFFFF),
        textDim: Color(dim),
        heroTint: Color(accent).withAlpha(0x59),
      );

  /// Ids that earlier versions saved, mapped to the nearest look kept.
  static const legacyIds = <String, String>{
    'chithram': 'saffron', // the old default
    'sunset': 'saffron',
    'plum': 'night',
    'frost': 'night',
    'violet': 'night',
    'rose': 'noir',
    'emerald': 'mint',
  };

  /// The look for a saved [id]: a current id as is, a removed one through
  /// [legacyIds], anything else (or null) the default, Night.
  static ThemePreset resolve(String? id) => byId(id) ?? byId(legacyIds[id]) ?? all.first;

  /// Saves a look once for installs that never picked one, so changing the
  /// default never restyles an existing user: an install from before Night
  /// became the default ([existingInstall]) keeps Saffron, the old default;
  /// a fresh one starts on Night. A saved choice is left alone.
  static Future<void> pinDefault(Prefs prefs, {required bool existingInstall}) async {
    if (prefs.getString(ThemePrefs.preset) != null) return;
    await prefs.set(ThemePrefs.preset, existingInstall ? 'saffron' : all.first.id);
  }

  /// The first is the default.
  static final all = <ThemePreset>[
    const ThemePreset('night', 'Night', ChithramTheme.night),
    const ThemePreset('saffron', 'Saffron', ChithramTheme.saffron),
    ThemePreset('noir', 'Noir', _dark(0xFFF2555A, 0xFF0A0A0B, 0xFF161618, 0xFF212124, 0xFFA6A6AD)),
    ThemePreset('mint', 'Mint', _dark(0xFF2EE07A, 0xFF0E0F12, 0xFF181A1F, 0xFF22252B, 0xFFA0A4AD)),
    ThemePreset('ocean', 'Ocean', _dark(0xFF3D9BFF, 0xFF090D14, 0xFF121A26, 0xFF1C2636, 0xFF9AA6BA)),
    ThemePreset('graphite', 'Graphite', _dark(0xFFE0E0E0, 0xFF0E0E0E, 0xFF1A1A1A, 0xFF262626, 0xFFA3A3A3)),
  ];
}

/// The accent swatches offered for a custom accent. Each reads on every
/// preset background and on AMOLED black.
const accentSwatches = <Color>[
  Color(0xFFF5A300),
  Color(0xFFFFC107),
  Color(0xFFFF7A45),
  Color(0xFFFF5252),
  Color(0xFFFF5C8A),
  Color(0xFFFF6FD8),
  Color(0xFFC77DFF),
  Color(0xFFA678FF),
  Color(0xFF7C8CFF),
  Color(0xFF3D9BFF),
  Color(0xFF29C7E6),
  Color(0xFF2FD3C4),
  Color(0xFF2ECC8F),
  Color(0xFF7ED957),
  Color(0xFFC6E03A),
  Color(0xFFE0E0E0),
];

/// Chithram's colours. Read the current look with [of].
class ChithramColors {
  ChithramColors._();

  /// The colours of the nearest theme (the default look when there is none).
  static ChithramTheme of(BuildContext context) =>
      Theme.of(context).extension<ChithramTheme>() ?? ChithramTheme.night;
}

/// The theme for [form] in the look [colors]. A TV (and desktop) draws its own
/// focus glow and has no touch feedback; a phone gets ripples, padded tap
/// targets, the M3 type scale and predictive back.
ThemeData buildChithramTheme({
  FormFactor form = FormFactor.tv,
  ChithramTheme colors = ChithramTheme.night,
}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: colors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: colors.accent,
    onPrimary: colors.onAccent,
    surface: colors.surface,
  );
  if (form == FormFactor.phone) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: [colors],
      fontFamily: 'Poppins',
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      focusColor: Colors.transparent,
      splashFactory: InkSparkle.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      textTheme: Typography.material2021()
          .white
          .apply(fontFamily: 'Poppins', bodyColor: colors.text, displayColor: colors.text),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        systemOverlayStyle: systemBars(colors),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.accent.withValues(alpha: 0.25),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      }),
    );
  }
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    extensions: [colors],
    fontFamily: 'Poppins',
    scaffoldBackgroundColor: colors.background,
    canvasColor: colors.background,
    // The app draws its own focus glow.
    focusColor: Colors.transparent,
    splashFactory: NoSplash.splashFactory,
  );
}

/// Android status and navigation bars in the look [colors].
SystemUiOverlayStyle systemBars(ChithramTheme colors) => SystemUiOverlayStyle(
      statusBarColor: colors.background,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: colors.surface,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: colors.surface,
    );
