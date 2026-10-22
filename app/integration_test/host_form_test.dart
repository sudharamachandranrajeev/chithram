// Plain widget tests (no device): the shell each form factor gets, at the
// window sizes that used to be guessed wrong. CI copies this and support.dart
// into test/_host/ next to host_test.dart and runs `flutter test test/_host`.
import 'package:chithram/src/ui/common/app.dart';
import 'package:chithram/src/ui/common/details_page.dart';
import 'package:chithram/src/ui/common/dims.dart';
import 'package:chithram/src/ui/phone/phone_shell.dart';
import 'package:chithram/src/ui/tv/tv_shell.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps the app as [form] in a window of [size] (1 dp = 1 px). An overflow
/// anywhere fails the test on its own.
Future<void> pumpForm(WidgetTester t, Size size, FormFactor form) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ChithramApp(formFactor: form));
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
      expect(find.text('Search YouTube.'), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Hero billboard'), findsOneWidget);
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
    testWidgets('TV shell without overscan', (t) async {
      await pumpForm(t, const Size(1280, 800), FormFactor.desktop);
      expect(find.byType(TvShell), findsOneWidget);
      expect(t.getTopLeft(_navHome).dx, lessThan(40));
    });

    testWidgets('hover highlights a tile without moving focus; a click opens details', (t) async {
      await pumpForm(t, const Size(1280, 800), FormFactor.desktop);
      final tile = find.text('Title 1').first;
      final focusBefore = FocusManager.instance.primaryFocus;
      final scale = find.ancestor(of: tile, matching: find.byType(AnimatedScale)).first;
      expect(t.widget<AnimatedScale>(scale).scale, 1.0);

      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(t.getCenter(tile));
      await t.pumpAndSettle();
      expect(t.widget<AnimatedScale>(scale).scale, greaterThan(1.0));
      expect(FocusManager.instance.primaryFocus, focusBefore);

      await mouse.down(t.getCenter(tile));
      await mouse.up();
      await t.pumpAndSettle();
      expect(find.byType(DetailsPage), findsOneWidget);
    });
  });
}
