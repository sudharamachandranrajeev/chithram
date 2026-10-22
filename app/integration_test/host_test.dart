// Plain widget tests (no device): focus rules at TV size and layout at phone size.
// CI copies this and support.dart into test/_host/ and runs `flutter test test/_host`.
import 'package:chithram/src/ui/app.dart';
import 'package:chithram/src/ui/details_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<void> pumpAt(WidgetTester t, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(const ChithramApp());
  await t.pumpAndSettle();
}

String _query(WidgetTester t) => t.widget<Text>(find.byKey(const ValueKey('search-query'))).data!;

void main() {
  group('phone (400x800)', () {
    testWidgets('bottom nav, tap search, type', (t) async {
      await pumpAt(t, const Size(400, 800));
      // Bottom nav, no overscan padding.
      expect(t.getTopLeft(find.byKey(const ValueKey('nav-home'))).dx, lessThan(60));
      expect(t.getTopLeft(find.byKey(const ValueKey('nav-home'))).dy, greaterThan(600));
      await t.tap(find.byKey(const ValueKey('nav-search')));
      await t.pumpAndSettle();
      expect(find.textContaining('Unified search'), findsOneWidget);
      // A phone types into a real TextField (the system keyboard), not the
      // on-screen keys.
      expect(find.byKey(const ValueKey('key-s')), findsNothing);
      await t.enterText(find.byKey(const ValueKey('search-field')), 'sin');
      await t.pumpAndSettle();
      expect(t.widget<TextField>(find.byKey(const ValueKey('search-field'))).controller!.text, 'sin');
    });

    testWidgets('tile opens details, back returns', (t) async {
      await pumpAt(t, const Size(400, 800));
      await t.tap(find.text('Title 1').first);
      await t.pumpAndSettle();
      expect(find.byType(DetailsPage), findsOneWidget);
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Trailer'), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);
      expect(find.text('Episodes'), findsOneWidget);
      Navigator.of(t.element(find.byType(DetailsPage))).pop();
      await t.pumpAndSettle();
      expect(find.byType(DetailsPage), findsNothing);
    });
  });

  testWidgets('TV 960x540 (small TV): no overflow anywhere', (t) async {
    await pumpAt(t, const Size(960, 540));
    for (var i = 0; i < 6; i++) {
      if (i > 0) await press(t, LogicalKeyboardKey.arrowDown);
      await press(t, LogicalKeyboardKey.arrowRight);
      await press(t, LogicalKeyboardKey.arrowDown);
      await press(t, LogicalKeyboardKey.arrowDown);
      await press(t, LogicalKeyboardKey.arrowLeft);
      await press(t, LogicalKeyboardKey.arrowLeft);
    }
    await press(t, LogicalKeyboardKey.arrowUp);
    await press(t, LogicalKeyboardKey.arrowUp);
    await press(t, LogicalKeyboardKey.arrowUp);
    await press(t, LogicalKeyboardKey.arrowUp);
    await press(t, LogicalKeyboardKey.arrowUp);
    await press(t, LogicalKeyboardKey.arrowRight);
    await press(t, LogicalKeyboardKey.select);
    expect(find.byType(DetailsPage), findsOneWidget);
    await press(t, LogicalKeyboardKey.arrowDown);
    await press(t, LogicalKeyboardKey.arrowDown);
    expectFocusInApp();
  });

  group('TV (1920x1080)', () {
    testWidgets('5% overscan padding', (t) async {
      await pumpAt(t, const Size(1920, 1080));
      expect(t.getTopLeft(find.byKey(const ValueKey('nav-home'))).dx, greaterThanOrEqualTo(96));
      expect(t.getTopLeft(find.byKey(const ValueKey('nav-home'))).dy, greaterThanOrEqualTo(54));
    });

    testWidgets('vertical moves keep the nearest column', (t) async {
      await pumpAt(t, const Size(1920, 1080));
      await press(t, LogicalKeyboardKey.arrowRight); // hero Play
      await press(t, LogicalKeyboardKey.arrowDown); // first rail
      for (var i = 0; i < 3; i++) {
        await press(t, LogicalKeyboardKey.arrowRight);
      }
      final x = FocusManager.instance.primaryFocus!.rect.center.dx;
      final y = FocusManager.instance.primaryFocus!.rect.center.dy;
      await press(t, LogicalKeyboardKey.arrowDown);
      final r = FocusManager.instance.primaryFocus!.rect;
      expect(r.center.dy, greaterThan(y));
      expect((r.center.dx - x).abs(), lessThan(40));
      await press(t, LogicalKeyboardKey.arrowUp);
      expect((FocusManager.instance.primaryFocus!.rect.center.dx - x).abs(), lessThan(40));
      expectFocusInApp();
    });

    testWidgets('rails keep their scroll offset and focused tile across sections', (t) async {
      await pumpAt(t, const Size(1920, 1080));
      await press(t, LogicalKeyboardKey.arrowRight); // hero Play
      await press(t, LogicalKeyboardKey.arrowDown); // first tile
      for (var i = 0; i < 3; i++) {
        await press(t, LogicalKeyboardKey.arrowRight);
      }
      // Back along the row to its first tile; that is the last tile focused.
      for (var i = 0; i < 3; i++) {
        await press(t, LogicalKeyboardKey.arrowLeft);
      }
      final node = FocusManager.instance.primaryFocus;
      await press(t, LogicalKeyboardKey.arrowLeft); // out to the rail
      expect(focusLabel(), 'rail Home');
      final railScroll = find
          .descendant(
              of: find.byKey(const PageStorageKey<String>('rail-Continue watching')),
              matching: find.byType(Scrollable))
          .first;
      await t.drag(railScroll, const Offset(-500, 0));
      await t.pumpAndSettle();
      final before = t.state<ScrollableState>(railScroll).position.pixels;
      expect(before, greaterThan(0));
      // To Search and back to Home.
      await press(t, LogicalKeyboardKey.arrowDown);
      expect(find.textContaining('Unified search'), findsOneWidget);
      await press(t, LogicalKeyboardKey.arrowUp);
      expect(t.state<ScrollableState>(railScroll).position.pixels, before);
      await press(t, LogicalKeyboardKey.arrowRight);
      expect(FocusManager.instance.primaryFocus, node);
    });

    testWidgets('hardware keyboard types into search', (t) async {
      await pumpAt(t, const Size(1920, 1080));
      await press(t, LogicalKeyboardKey.arrowDown);
      await press(t, LogicalKeyboardKey.arrowRight);
      await t.sendKeyEvent(LogicalKeyboardKey.keyS, character: 's');
      await t.sendKeyEvent(LogicalKeyboardKey.keyI, character: 'i');
      await t.pumpAndSettle();
      expect(_query(t), 'si');
      await t.sendKeyEvent(LogicalKeyboardKey.backspace);
      await t.pumpAndSettle();
      expect(_query(t), 's');
    });

    testWidgets('details opens from a tile and Back returns focus', (t) async {
      await pumpAt(t, const Size(1920, 1080));
      await press(t, LogicalKeyboardKey.arrowRight);
      await press(t, LogicalKeyboardKey.arrowDown);
      final tile = FocusManager.instance.primaryFocus;
      await press(t, LogicalKeyboardKey.select);
      expect(find.byType(DetailsPage), findsOneWidget);
      expectFocusInApp();
      Navigator.of(t.element(find.byType(DetailsPage))).pop();
      await t.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, tile);
    });
  });
}
