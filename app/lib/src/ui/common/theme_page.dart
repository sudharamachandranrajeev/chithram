import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/prefs.dart';
import '../../core/services.dart';
import '../../theme.dart';
import '../tv/focus_card.dart';
import '../tv/home_page.dart' show ActionLabel;
import 'dims.dart';

/// Keys for tests.
class ThemeKeys {
  ThemeKeys._();

  static const page = ValueKey('theme-page');
  static const amoled = ValueKey('theme-amoled');
  static const presetAccent = ValueKey('theme-preset-accent');
  static ValueKey<String> preset(String id) => ValueKey('theme-preset-$id');
  static ValueKey<String> swatch(Color c) =>
      ValueKey('theme-swatch-${c.toARGB32().toRadixString(16)}');
}

/// The name of the saved look, for the Settings entry.
String themeLabel(Prefs prefs) {
  final name = (ThemePreset.byId(prefs.getString(ThemePrefs.preset)) ?? ThemePreset.all.first).name;
  final custom = prefs.getInt(ThemePrefs.accent) != null ? ', custom accent' : '';
  final black = prefs.getBool(ThemePrefs.amoled) ? ', AMOLED' : '';
  return '$name$custom$black';
}

Future<void> openThemePage(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ThemePage()));

/// Settings > Theme on a TV or desktop: a card that opens [ThemePage].
class ThemeSettings extends StatelessWidget {
  const ThemeSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = AppServices.of(context).prefs;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.all(8),
        child: FocusCard(
          radius: 24,
          onActivate: () => openThemePage(context),
          child: ActionLabel(text: 'Theme: ${themeLabel(prefs)}'),
        ),
      ),
    );
  }
}

/// Settings > Theme on a phone.
class PhoneThemeTile extends StatelessWidget {
  const PhoneThemeTile({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = AppServices.of(context).prefs;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => ListTile(
        minTileHeight: 56,
        leading: const Icon(Icons.palette_outlined),
        title: const Text('Theme'),
        subtitle: Text(themeLabel(prefs)),
        onTap: () => openThemePage(context),
      ),
    );
  }
}

/// Pick a look: presets with live previews, AMOLED black, a custom accent.
/// Every choice applies at once and is saved.
class ThemePage extends StatefulWidget {
  const ThemePage({super.key});

  @override
  State<ThemePage> createState() => _ThemePageState();
}

class _ThemePageState extends State<ThemePage> {
  final _focus = SectionFocus();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !Dims.of(context).phone) _focus.entry.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final prefs = AppServices.of(context).prefs;
    final colors = ChithramColors.of(context);
    final dim = TextStyle(color: colors.textDim, fontSize: d.t(14));
    final heading = TextStyle(fontSize: d.t(20), fontWeight: FontWeight.w600);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
      },
      child: Scaffold(
        key: ThemeKeys.page,
        appBar: d.phone ? AppBar(title: const Text('Theme')) : null,
        body: Overscan(
          child: FocusScope(
            child: ListenableBuilder(
              listenable: prefs,
              builder: (context, _) {
                final presetId = (ThemePreset.byId(prefs.getString(ThemePrefs.preset)) ?? ThemePreset.all.first).id;
                final accent = prefs.getInt(ThemePrefs.accent);
                final amoled = prefs.getBool(ThemePrefs.amoled);
                return SingleChildScrollView(
                  padding: EdgeInsets.all(d.gutter),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!d.phone) ...[
                        Text('Theme', style: TextStyle(fontSize: d.t(32), fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                      ],
                      Text('Applies at once and is kept on this device.', style: dim),
                      const SizedBox(height: 20),
                      Text('Look', style: heading),
                      const SizedBox(height: 8),
                      Wrap(
                        children: [
                          for (final p in ThemePreset.all)
                            _PresetTile(
                              preset: p,
                              selected: p.id == presetId,
                              accent: p.id == presetId && accent != null ? Color(accent) : null,
                              amoled: amoled,
                              focusNode: p.id == presetId ? _focus.entry : null,
                              section: _focus,
                              onActivate: () async {
                                // A preset brings its own accent back.
                                await prefs.set(ThemePrefs.accent, null);
                                await prefs.set(ThemePrefs.preset, p.id);
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: FocusCard(
                          key: ThemeKeys.amoled,
                          radius: 24,
                          section: _focus,
                          onActivate: () => prefs.set(ThemePrefs.amoled, !amoled),
                          child: ActionLabel(text: 'AMOLED black background: ${amoled ? 'on' : 'off'}'),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text('Accent', style: heading),
                      const SizedBox(height: 8),
                      Wrap(
                        children: [
                          for (final c in accentSwatches)
                            _Swatch(
                              color: c,
                              selected: accent != null && (accent | 0xFF000000) == c.toARGB32(),
                              size: d.phone ? 48 : d.u(44),
                              section: _focus,
                              onActivate: () => prefs.set(ThemePrefs.accent, c.toARGB32()),
                            ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: FocusCard(
                          key: ThemeKeys.presetAccent,
                          radius: 24,
                          section: _focus,
                          onActivate: () => prefs.set(ThemePrefs.accent, null),
                          child: const ActionLabel(text: 'Use the look\'s own accent'),
                        ),
                      ),
                      if (!d.phone) ...[
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: FocusCard(
                            radius: 24,
                            section: _focus,
                            onActivate: () => Navigator.of(context).maybePop(),
                            child: const ActionLabel(text: 'Back'),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.selected,
    required this.accent,
    required this.amoled,
    required this.focusNode,
    required this.section,
    required this.onActivate,
  });

  final ThemePreset preset;
  final bool selected;
  final Color? accent;
  final bool amoled;
  final FocusNode? focusNode;
  final SectionFocus section;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    var look = preset.theme;
    if (accent != null) look = look.withAccent(accent!);
    if (amoled) look = look.toAmoled();
    final width = d.phone ? 156.0 : d.u(168);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Semantics(
        label: '${preset.name} theme',
        selected: selected,
        button: true,
        child: FocusCard(
          key: ThemeKeys.preset(preset.id),
          radius: 16,
          focusNode: focusNode,
          section: section,
          onActivate: onActivate,
          child: SizedBox(
            width: width,
            child: ColoredBox(
              color: look.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ThemePreview(look: look, height: width * 0.62),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(preset.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: look.text, fontSize: d.t(14), fontWeight: FontWeight.w600)),
                        ),
                        if (selected) Icon(Icons.check_circle_rounded, color: look.accent, size: d.t(20)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A miniature Home in the look [look]: a hero, a rail with one focused card.
/// Drawn from [look] alone, so it previews a look without applying it.
class ThemePreview extends StatelessWidget {
  const ThemePreview({super.key, required this.look, required this.height});

  final ChithramTheme look;
  final double height;

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, Color c, [double h = 5]) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
        );
    Widget card({bool focused = false}) => Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: look.surfaceHigh,
              borderRadius: BorderRadius.circular(4),
              border: focused ? Border.all(color: look.accent, width: 1.5) : null,
            ),
          ),
        );
    return Container(
      height: height,
      color: look.background,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [look.heroTint, look.surface, look.background],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(28, look.accent, 4),
                  const SizedBox(height: 4),
                  bar(70, look.text),
                  const SizedBox(height: 3),
                  bar(46, look.textDim, 4),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                card(),
                const SizedBox(width: 5),
                card(focused: true),
                const SizedBox(width: 5),
                card(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.size,
    required this.section,
    required this.onActivate,
  });

  final Color color;
  final bool selected;
  final double size;
  final SectionFocus section;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Semantics(
        label: 'Accent #${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
        selected: selected,
        button: true,
        child: FocusCard(
          key: ThemeKeys.swatch(color),
          radius: size / 2,
          section: section,
          onActivate: onActivate,
          child: Container(
            width: size,
            height: size,
            color: color,
            // The check mark is black or white, whichever reads on this colour.
            child: selected ? Icon(Icons.check_rounded, color: ChithramTheme.onColor(color)) : null,
          ),
        ),
      ),
    );
  }
}
