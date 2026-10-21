// Runs on the Android TV emulator (and a phone emulator) via `flutter drive`
// with integration_test/driver.dart; see .github/tv-emulator.sh.
import 'dart:math';

import 'package:chithram/src/ui/app.dart';
import 'package:chithram/src/ui/details_page.dart';
import 'package:chithram/src/ui/dims.dart';
import 'package:chithram/src/ui/sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support.dart';

Future<void> pumpApp(WidgetTester t) async {
  await t.pumpWidget(const ChithramApp());
  await t.pumpAndSettle();
}

bool isPhone(WidgetTester t) =>
    Dims.formFor(t.view.physicalSize / t.view.devicePixelRatio).name == 'phone';

String _query() => (find.byKey(const ValueKey('search-query')).evaluate().single.widget as Text).data!;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('screenshots: home, search, details', (t) async {
    await binding.convertFlutterSurfaceToImage();
    await pumpApp(t);
    await binding.takeScreenshot('home');

    if (isPhone(t)) {
      await t.tap(find.byKey(const ValueKey('nav-search')));
    } else {
      await press(t, LogicalKeyboardKey.arrowDown);
    }
    await t.pumpAndSettle();
    await binding.takeScreenshot('search');

    if (isPhone(t)) {
      await t.tap(find.byKey(const ValueKey('nav-home')));
      await t.pumpAndSettle();
      await t.tap(find.text('Title 1').first);
    } else {
      await press(t, LogicalKeyboardKey.arrowUp);
      await press(t, LogicalKeyboardKey.arrowRight);
      await press(t, LogicalKeyboardKey.select);
    }
    await t.pumpAndSettle();
    expect(find.byType(DetailsPage), findsOneWidget);
    expectFocusInApp('on details');
    await binding.takeScreenshot('details');
  });

  testWidgets('every nav item is reachable and leavable', (t) async {
    await pumpApp(t);
    if (isPhone(t)) {
      for (final s in Section.values) {
        await t.tap(find.byKey(ValueKey('nav-${s.name}')));
        await t.pumpAndSettle();
        expect(focusLabel(), railLabel(s));
      }
      await t.tap(find.byKey(const ValueKey('nav-home')));
      await t.pumpAndSettle();
      expect(focusLabel(), railLabel(Section.home));
      return;
    }
    expect(focusLabel(), railLabel(Section.home));
    for (final s in Section.values) {
      if (s != Section.home) {
        await press(t, LogicalKeyboardKey.arrowDown);
      }
      expect(focusLabel(), railLabel(s), reason: 'rail item ${s.label}');
      // Into the content ...
      await press(t, LogicalKeyboardKey.arrowRight);
      expect(focusLabel(), isNot(startsWith('rail')), reason: 'content of ${s.label}');
      expectFocusInApp('in ${s.label}');
      // ... and back out to the rail.
      await press(t, LogicalKeyboardKey.arrowLeft);
      expect(focusLabel(), railLabel(s), reason: 'leaving ${s.label}');
    }
  });

  testWidgets('200 random D-pad presses never lose focus', (t) async {
    await pumpApp(t);
    final rnd = Random(2026);
    final keys = [
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.select,
    ];
    for (var i = 0; i < 200; i++) {
      final key = keys[rnd.nextInt(keys.length)];
      await press(t, key);
      expectFocusInApp('after press ${i + 1} (${key.keyLabel})');
      // Leave a details page now and then, like Back would.
      if (find.byType(DetailsPage).evaluate().isNotEmpty && rnd.nextInt(6) == 0) {
        Navigator.of(t.element(find.byType(DetailsPage))).pop();
        await t.pumpAndSettle();
        expectFocusInApp('after Back at press ${i + 1}');
      }
    }
  });

  testWidgets('typing "sintel" with the on-screen keyboard', (t) async {
    await pumpApp(t);
    if (isPhone(t)) {
      await t.tap(find.byKey(const ValueKey('nav-search')));
      await t.pumpAndSettle();
      for (final c in 'sintel'.split('')) {
        await t.tap(find.byKey(ValueKey('key-$c')));
        await t.pumpAndSettle();
      }
    } else {
      await press(t, LogicalKeyboardKey.arrowDown); // Search
      await press(t, LogicalKeyboardKey.arrowRight); // into the keyboard
      for (final c in 'sintel'.split('')) {
        await dpadTo(t, find.byKey(ValueKey('key-$c')));
        await press(t, LogicalKeyboardKey.select);
      }
    }
    expect(_query(), 'sintel');
    // Backspace and Clear work too.
    if (!isPhone(t)) {
      await dpadTo(t, find.byKey(const ValueKey('key-backspace')));
      await press(t, LogicalKeyboardKey.select);
      expect(_query(), 'sinte');
      await dpadTo(t, find.byKey(const ValueKey('key-clear')));
      await press(t, LogicalKeyboardKey.select);
      expect(_query(), '');
    }
  });

  testWidgets('TV text is at least 24sp', (t) async {
    await pumpApp(t);
    if (isPhone(t) || !Dims.of(t.element(find.byType(Scaffold).first)).tv) return;
    void check(String where) {
      for (final p in t.allRenderObjects.whereType<RenderParagraph>()) {
        final text = p.text.toPlainText().trim();
        final style = p.text.style;
        if (text.isEmpty || style?.fontFamily == 'MaterialIcons') continue;
        final size = p.textScaler.scale(style?.fontSize ?? 14);
        expect(size, greaterThanOrEqualTo(24), reason: '"$text" on $where is ${size}sp');
      }
    }

    check('Home');
    await press(t, LogicalKeyboardKey.arrowDown);
    check('Search');
    await press(t, LogicalKeyboardKey.arrowUp);
    await press(t, LogicalKeyboardKey.arrowRight);
    await press(t, LogicalKeyboardKey.select);
    expect(find.byType(DetailsPage), findsOneWidget);
    check('Details');
  });
}
