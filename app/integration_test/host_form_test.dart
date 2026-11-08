// Plain widget tests (no device): the shell each form factor gets, at the
// window sizes that used to be guessed wrong. CI copies this and support.dart
// into test/_host/ next to host_test.dart and runs `flutter test test/_host`.
import 'package:chithram/src/core/prefs.dart';
import 'package:chithram/src/ui/common/app.dart';
import 'package:chithram/src/ui/common/dims.dart';
import 'package:chithram/src/ui/common/form_factor.dart' show tenFootPref;
import 'package:chithram/src/ui/common/video_card.dart';
import 'package:chithram/src/ui/desktop/desktop_shell.dart';
import 'package:chithram/src/ui/phone/phone_shell.dart';
import 'package:chithram/src/ui/tv/tv_shell.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Pumps the app as [form] in a window of [size] (1 dp = 1 px). An overflow
/// anywhere fails the test on its own.
Future<void> pumpForm(WidgetTester t, Size size, FormFactor form, {Prefs? prefs}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ChithramApp(services: fixtureServices(prefs: prefs), formFactor: form));
  await t.pumpAndSettle();
}

final _navHome = find.byKey(const ValueKey('nav-home'));

void main() {
  group('phone', () {
    const sizes = {
      '421x927 (owner phone)': Size(421, 927),
      '360x640': Size(360, 640),
      '927x421 (landscape)': Size(927, 421),
    };
    for (final MapEntry(key: name, value: size) in sizes.entries) {
      testWidgets('$name: bottom bar, no rail, no overscan, full-bleed hero, touch targets', (t) async {
        final semantics = t.ensureSemantics();
        await pumpForm(t, size, FormFactor.phone);
        expect(find.byType(PhoneShell), findsOneWidget);
        expect(find.byType(TvShell), findsNothing);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byType(NavigationRail), findsNothing);
        // The bar is at the bottom, edge to edge: no overscan padding.
        expect(t.getTopLeft(find.byType(NavigationBar)).dx, 0);
        expect(t.getBottomLeft(find.byType(NavigationBar)).dy, size.height);
        expect(t.getTopLeft(_navHome).dx, lessThan(size.width / 5));
        // The hero takes the whole width.
        expect(t.getSize(find.byKey(const ValueKey('phone-hero'))).width, size.width);
        expect(t.getTopLeft(find.byKey(const ValueKey('phone-hero'))).dx, 0);
        await expectLater(t, meetsGuideline(androidTapTargetGuideline));
        await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
        semantics.dispose();
      });
    }

    testWidgets('the bottom bar switches sections and Back goes to Home', (t) async {
      await pumpForm(t, const Size(421, 927), FormFactor.phone);
      await t.tap(find.byKey(const ValueKey('nav-youtube')));
      await t.pumpAndSettle();
      // The YouTube tab opens on its home page, with the search field on top.
      expect(find.text('Search YouTube'), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Popular on YouTube'), findsWidgets);
    });

    testWidgets('the gear opens Settings, with no "Send from phone"', (t) async {
      await pumpForm(t, const Size(421, 927), FormFactor.phone);
      await t.tap(find.byKey(const ValueKey('nav-settings')));
      await t.pumpAndSettle();
      expect(find.textContaining('Chithram ships no sources'), findsOneWidget);
      expect(find.text('Send from phone'), findsNothing);
    });
  });

  testWidgets('tablet 800x1280: navigation rail instead of the bottom bar', (t) async {
    await pumpForm(t, const Size(800, 1280), FormFactor.phone);
    expect(find.byType(PhoneShell), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  group('TV', () {
    testWidgets('960x540 (small TV): TV shell, 5% overscan', (t) async {
      await pumpForm(t, const Size(960, 540), FormFactor.tv);
      expect(find.byType(TvShell), findsOneWidget);
      expect(find.byType(PhoneShell), findsNothing);
      expect(t.getTopLeft(_navHome).dx, greaterThanOrEqualTo(48));
      expect(t.getTopLeft(_navHome).dy, greaterThanOrEqualTo(27));
    });

    testWidgets('1920x1080: TV shell, 5% overscan', (t) async {
      await pumpForm(t, const Size(1920, 1080), FormFactor.tv);
      expect(find.byType(TvShell), findsOneWidget);
      expect(t.getTopLeft(_navHome).dx, greaterThanOrEqualTo(96));
      expect(t.getTopLeft(_navHome).dy, greaterThanOrEqualTo(54));
    });
  });

  group('desktop 1280x800', () {
    testWidgets('desktop shell: sidebar, no overscan, no TV shell', (t) async {
      await pumpForm(t, const Size(1280, 800), FormFactor.desktop);
      expect(find.byType(DesktopShell), findsOneWidget);
      expect(find.byType(TvShell), findsNothing);
      expect(find.byType(PhoneShell), findsNothing);
      expect(find.byKey(const ValueKey('desktop-sidebar')), findsOneWidget);
      expect(t.getTopLeft(_navHome).dx, lessThan(40));
    });

    testWidgets('the 10-foot preference gives the TV shell with no overscan', (t) async {
      // On a real desktop (not the Android the test host reports) there is no overscan.
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await pumpForm(t, const Size(1280, 800), FormFactor.desktop, prefs: Prefs.memory({tenFootPref: true}));
        expect(find.byType(TvShell), findsOneWidget);
        expect(find.byType(DesktopShell), findsNothing);
        expect(t.getTopLeft(_navHome).dx, lessThan(40));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('hover zooms a card poster without moving focus', (t) async {
      await pumpForm(t, const Size(1280, 800), FormFactor.desktop);
      // The card, not the billboard: it rotates and may show this title too
      // (it comes first in the tree).
      final tile = find.text('Fixture p-9 2').last;
      final focusBefore = FocusManager.instance.primaryFocus;
      final card = find.ancestor(of: tile, matching: find.byType(VideoCard));
      final scale = find.descendant(of: card, matching: find.byType(AnimatedScale)).first;
      expect(t.widget<AnimatedScale>(scale).scale, 1.0);

      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(t.getCenter(tile));
      await t.pumpAndSettle();
      expect(t.widget<AnimatedScale>(scale).scale, greaterThan(1.0));
      expect(FocusManager.instance.primaryFocus, focusBefore);
    });
  });
}
