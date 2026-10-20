import 'package:chithram/src/ui/sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sends one key and lets the animations finish.
Future<void> press(WidgetTester t, LogicalKeyboardKey key) async {
  await t.sendKeyEvent(key);
  await t.pumpAndSettle(const Duration(milliseconds: 50));
}

String? focusLabel() => FocusManager.instance.primaryFocus?.debugLabel;

/// Focus is on a real node that is part of the app (never lost, never only a scope).
void expectFocusInApp([String? when]) {
  final f = FocusManager.instance.primaryFocus;
  expect(f, isNotNull, reason: 'primaryFocus is null ${when ?? ''}');
  expect(f, isNot(isA<FocusScopeNode>()), reason: 'only a scope has focus ${when ?? ''}');
  expect(f!.context, isNotNull, reason: 'focused node is detached ${when ?? ''}');
  expect(f.context!.mounted, isTrue, reason: 'focused node is unmounted ${when ?? ''}');
  expect(f.context!.findAncestorWidgetOfExactType<MaterialApp>(), isNotNull,
      reason: 'focus is outside the app ${when ?? ''}');
}

String railLabel(Section s) => 'rail ${s.label}';

/// Moves focus to [target] using only D-pad presses (geometry based).
Future<void> dpadTo(WidgetTester t, Finder target) async {
  final goal = t.getRect(target).center;
  for (var i = 0; i < 80; i++) {
    final cur = FocusManager.instance.primaryFocus!.rect;
    final delta = goal - cur.center;
    if (delta.distance < 4) return;
    final LogicalKeyboardKey key;
    if (delta.dy.abs() > cur.height / 2) {
      key = delta.dy > 0 ? LogicalKeyboardKey.arrowDown : LogicalKeyboardKey.arrowUp;
    } else {
      key = delta.dx > 0 ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft;
    }
    await press(t, key);
  }
  fail('D-pad never reached $target (focus: ${focusLabel()})');
}
