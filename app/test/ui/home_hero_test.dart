import 'package:chithram/src/ui/focus_card.dart';
import 'package:chithram/src/ui/home_page.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app font, as on a device. With the test font (every glyph a wide box)
/// the hero's text fills the card and hides the bug.
Future<void> _loadPoppins() async {
  final loader = FontLoader('Poppins');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = await File('assets/fonts/Poppins-$w.ttf').readAsBytes();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

void main() {
  // A real phone: 1264x2780 px at 480 dpi (3x here), so about 421x927 dp.
  testWidgets('the hero card spans the content width on a phone', (tester) async {
    tester.view.physicalSize = const Size(1264, 2780);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.runAsync(_loadPoppins);
    // The TV Home page at a phone's width (no form scope: the size decides).
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HomePage(focus: SectionFocus()))));
    await tester.pumpAndSettle();

    final home = tester.getRect(find.byType(HomePage));
    final heroWidget = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Hero');
    // The painted card: the gradient box inside the margin.
    final hero = tester.getRect(find.descendant(of: heroWidget, matching: find.byType(DecoratedBox)).first);
    // The hero's own side margin is 8 dp.
    expect(hero.left, home.left + 8);
    expect(hero.right, home.right - 8, reason: 'the hero stops short of the right edge');
  });
}
