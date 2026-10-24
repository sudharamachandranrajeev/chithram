import 'package:chithram/src/core/prefs.dart';
import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/common/app.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/common/theme_page.dart';
import 'package:chithram/src/features/youtube/youtube_fixture.dart';
import 'package:chithram/src/features/youtube/youtube_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _c(Color a, Color b) => ChithramTheme.contrastRatio(a, b);

/// Every look a user can reach: presets, with and without AMOLED.
Map<String, ChithramTheme> _looks() => {
      for (final p in ThemePreset.all) ...{
        p.id: p.theme,
        '${p.id}+amoled': p.theme.toAmoled(),
      },
    };

void _checkLook(String name, ChithramTheme t) {
  for (final (label, bg) in [('background', t.background), ('surface', t.surface), ('surfaceHigh', t.surfaceHigh)]) {
    expect(_c(t.text, bg), greaterThanOrEqualTo(4.5), reason: '$name text on $label');
    expect(_c(t.textDim, bg), greaterThanOrEqualTo(4.5), reason: '$name textDim on $label');
  }
  expect(_c(t.accent, t.background), greaterThanOrEqualTo(3), reason: '$name accent on background');
  expect(_c(t.accent, t.surface), greaterThanOrEqualTo(3), reason: '$name accent on surface');
  expect(_c(t.onAccent, t.accent), greaterThanOrEqualTo(4.5), reason: '$name onAccent on accent');
}

Widget _app(AppServices s, {FormFactor form = FormFactor.tv}) => ChithramApp(
      services: s,
      formFactor: form,
    );

Color _bg(WidgetTester t) => Theme.of(t.element(find.byType(Scaffold).first)).scaffoldBackgroundColor;

void main() {
  test('default look is the original Chithram colours', () {
    final t = ChithramTheme.fromPrefs(Prefs.memory());
    expect(t, ChithramTheme.chithram);
    expect(t.accent, const Color(0xFFF5A300));
    expect(t.background, const Color(0xFF0B0B10));
    expect(t.surface, const Color(0xFF16161E));
    expect(t.surfaceHigh, const Color(0xFF22222D));
    expect(t.textDim, const Color(0xFF9A9AAB));
    expect(t.heroTint, const Color(0x59F5A300));
    expect(ThemePreset.all.length, inInclusiveRange(6, 8));
  });

  test('every preset and its AMOLED variant is readable', () {
    for (final e in _looks().entries) {
      _checkLook(e.key, e.value);
    }
  });

  test('every accent swatch reads on every look and picks a legible onAccent', () {
    for (final e in _looks().entries) {
      for (final c in accentSwatches) {
        _checkLook('${e.key}/${c.toARGB32().toRadixString(16)}', e.value.withAccent(c));
      }
    }
    expect(accentSwatches.length, inInclusiveRange(12, 20));
  });

  test('onColor picks black on light accents and white on dark ones', () {
    expect(ChithramTheme.onColor(const Color(0xFFFFEB3B)), Colors.black);
    expect(ChithramTheme.onColor(const Color(0xFF1B3A8C)), Colors.white);
  });

  test('saved choice is restored; unknown values fall back', () {
    final prefs = Prefs.memory({
      ThemePrefs.preset: 'ocean',
      ThemePrefs.accent: 0xFF2ECC8F,
      ThemePrefs.amoled: true,
    });
    final t = ChithramTheme.fromPrefs(prefs);
    expect(t.accent, const Color(0xFF2ECC8F));
    expect(t.background, Colors.black);
    expect(t.surface, ThemePreset.byId('ocean')!.theme.toAmoled().surface);
    expect(ChithramTheme.fromPrefs(Prefs.memory({ThemePrefs.preset: 'gone'})), ChithramTheme.chithram);
  });

  test('lerp blends and a missing extension keeps this', () {
    final a = ChithramTheme.chithram;
    final b = ThemePreset.byId('ocean')!.theme;
    expect(a.lerp(b, 0), a);
    expect(a.lerp(b, 1), b);
    expect(a.lerp(null, 0.5), a);
  });

  testWidgets('switching theme rebuilds the app in the new colours', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final prefs = Prefs.memory();
    await tester.pumpWidget(_app(AppServices.memory(
      prefs: prefs,
      youtube: YouTubeService(browse: FixtureBrowse('')),
    )));
    await tester.pumpAndSettle();
    expect(_bg(tester), ChithramTheme.chithram.background);

    await prefs.set(ThemePrefs.preset, 'emerald');
    await tester.pump();
    await tester.pumpAndSettle();
    expect(_bg(tester), ThemePreset.byId('emerald')!.theme.background);
    expect(tester.takeException(), isNull);

    await prefs.set(ThemePrefs.amoled, true);
    await tester.pumpAndSettle();
    expect(_bg(tester), Colors.black);
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme page: preset, AMOLED and accent apply and persist', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final prefs = Prefs.memory();
    final services = AppServices.memory(prefs: prefs);
    await tester.pumpWidget(_app(services));
    await tester.pumpAndSettle();
    final nav = services.navigatorKey.currentState!;
    nav.push(MaterialPageRoute<void>(builder: (_) => const ThemePage()));
    await tester.pumpAndSettle();
    expect(find.byKey(ThemeKeys.page), findsOneWidget);
    for (final p in ThemePreset.all) {
      expect(find.byKey(ThemeKeys.preset(p.id)), findsOneWidget);
    }

    await tester.tap(find.byKey(ThemeKeys.preset('rose')));
    await tester.pumpAndSettle();
    expect(prefs.getString(ThemePrefs.preset), 'rose');
    expect(_bg(tester), ThemePreset.byId('rose')!.theme.background);

    await tester.tap(find.byKey(ThemeKeys.swatch(accentSwatches[9])));
    await tester.pumpAndSettle();
    expect(prefs.getInt(ThemePrefs.accent), accentSwatches[9].toARGB32());

    await tester.ensureVisible(find.byKey(ThemeKeys.amoled));
    await tester.tap(find.byKey(ThemeKeys.amoled));
    await tester.pumpAndSettle();
    expect(prefs.getBool(ThemePrefs.amoled), isTrue);
    expect(_bg(tester), Colors.black);

    // A new session reads the same look from the saved prefs.
    final restored = ChithramTheme.fromPrefs(Prefs.memory({
      ThemePrefs.preset: prefs.getString(ThemePrefs.preset),
      ThemePrefs.accent: prefs.getInt(ThemePrefs.accent),
      ThemePrefs.amoled: prefs.getBool(ThemePrefs.amoled),
    }));
    expect(restored, ChithramTheme.fromPrefs(prefs));
    expect(themeLabel(prefs), 'Rose, custom accent, AMOLED');
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme page lays out on a phone and a small TV without overflow', (tester) async {
    for (final (size, form) in [
      (const Size(360, 780), FormFactor.phone),
      (const Size(1280, 720), FormFactor.tv),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(AppServicesScope(
        services: AppServices.memory(),
        child: FormScope(
          form: form,
          child: MaterialApp(theme: buildChithramTheme(form: form), home: const ThemePage()),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(ThemeKeys.page), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$form');
    }
    addTearDown(tester.view.reset);
  });

  testWidgets('settings entry shows the current look', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final prefs = Prefs.memory({ThemePrefs.preset: 'violet'});
    await tester.pumpWidget(MaterialApp(
      theme: buildChithramTheme(colors: ChithramTheme.fromPrefs(prefs)),
      home: AppServicesScope(
        services: AppServices.memory(prefs: prefs),
        child: const Scaffold(body: ThemeSettings()),
      ),
    ));
    expect(find.text('Theme: Violet'), findsOneWidget);
  });
}
