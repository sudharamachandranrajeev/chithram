import 'package:chithram/src/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

int _focusedCards(WidgetTester tester) =>
    tester.widgetList<AnimatedScale>(find.byType(AnimatedScale)).where((w) => w.scale > 1).length;

void main() {
  testWidgets('rail and home are D-pad navigable', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ChithramApp());
    await tester.pumpAndSettle();

    // Home, with the rail focused and open.
    expect(find.text('Hero billboard'), findsOneWidget);
    expect(find.text('Continue watching'), findsOneWidget);
    expect(find.text('Live TV'), findsOneWidget);
    expect(_focusedCards(tester), 0);

    // Down: Search is selected.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.textContaining('Unified search'), findsOneWidget);
    expect(find.text('Hero billboard'), findsNothing);

    // Right goes into the section and the tile grows.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_focusedCards(tester), 1);

    // Left at the edge goes back to the rail; Up selects Home.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_focusedCards(tester), 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.text('Hero billboard'), findsOneWidget);

    // Right focuses the hero's Play button; Down reaches a rail tile.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_focusedCards(tester), 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_focusedCards(tester), 1);
  });
}
