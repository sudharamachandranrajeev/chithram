import 'package:chithram/src/ui/common/keys.dart';
import 'package:chithram/src/ui/common/text_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens the dialog; the returned list gets its result when it closes.
Future<List<String?>> _openDialog(
  WidgetTester t, {
  TextEntryKind kind = TextEntryKind.magnet,
  Size size = const Size(1920, 1080),
  double dpr = 1,
}) async {
  t.view.physicalSize = size * dpr;
  t.view.devicePixelRatio = dpr;
  addTearDown(t.view.reset);
  final result = <String?>[];
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (c) => TextButton(
        onPressed: () async => result.add(await askText(c, title: 'Link', kind: kind)),
        child: const Text('go'),
      ),
    ),
  ));
  await t.tap(find.text('go'));
  await t.pumpAndSettle();
  return result;
}

String _text(WidgetTester t) => t.widget<TextField>(find.byKey(Keys.textEntryField)).controller!.text;

Future<void> _keys(WidgetTester t, String ids) async {
  for (final c in ids.split('')) {
    await t.tap(find.byKey(ValueKey('key-$c')));
    await t.pump();
  }
}

void main() {
  testWidgets('D-pad Down leaves the TextField', (t) async {
    await _openDialog(t);
    final field = find.descendant(of: find.byKey(Keys.textEntryField), matching: find.byType(EditableText));
    expect(t.widget<EditableText>(field).focusNode.hasFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    expect(t.widget<EditableText>(field).focusNode.hasFocus, isFalse);
    expect(FocusManager.instance.primaryFocus, isNotNull);
  });

  testWidgets('on a TV the keyboard stays closed until the field is selected', (t) async {
    final result = await _openDialog(t);
    expect(find.byKey(const ValueKey('key-m')), findsNothing);
    expect(find.byKey(Keys.textEntryOk), findsOneWidget);

    // The remote's centre key on the focused field drops the keyboard down.
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    await _keys(t, 'magnet:?xt=');
    expect(_text(t), 'magnet:?xt=');
    // Shift gives capitals; backspace removes one character.
    await t.tap(find.byKey(const ValueKey('key-shift')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('key-B')));
    await t.pump();
    expect(_text(t), 'magnet:?xt=B');
    await t.tap(find.byKey(const ValueKey('key-backspace')));
    await t.pump();
    expect(_text(t), 'magnet:?xt=');

    // A hardware keyboard keeps its case in a link.
    await t.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'A');
    await t.pump();
    expect(_text(t), 'magnet:?xt=A');

    // OK on the keyboard confirms the dialog.
    await t.tap(find.byKey(const ValueKey('key-ok')));
    await t.pumpAndSettle();
    expect(result, ['magnet:?xt=A']);
  });

  testWidgets('Back closes the keyboard and keeps the dialog and the text', (t) async {
    final result = await _openDialog(t, kind: TextEntryKind.search);
    await t.tap(find.byKey(Keys.textEntryKeyboard));
    await t.pumpAndSettle();
    await _keys(t, 'hi');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('key-h')), findsNothing);
    expect(_text(t), 'hi');
    expect(result, isEmpty);
    await t.tap(find.byKey(Keys.textEntryOk));
    await t.pumpAndSettle();
    expect(result, ['hi']);
  });

  testWidgets('Send from phone is offered for links', (t) async {
    await _openDialog(t);
    expect(find.byKey(Keys.textEntrySend), findsOneWidget);
    expect(find.byKey(Keys.textEntryPaste), findsOneWidget);
    expect(find.byKey(Keys.textEntryKeyboard), findsOneWidget);
  });

  testWidgets('a PIN has a digits row and Shift, and no link helpers', (t) async {
    await _openDialog(t, kind: TextEntryKind.pin);
    expect(find.byKey(Keys.textEntrySend), findsNothing);
    expect(find.byKey(Keys.textEntryPaste), findsOneWidget);
    await t.tap(find.byKey(Keys.textEntryKeyboard));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('key-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('key-shift')), findsOneWidget);
    await _keys(t, '1a');
    expect(_text(t), '1a');
  });

  testWidgets('a phone number gets a number pad', (t) async {
    await _openDialog(t, kind: TextEntryKind.number);
    await t.tap(find.byKey(Keys.textEntryKeyboard));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('key-a')), findsNothing);
    await _keys(t, '+123');
    // Letters from a hardware keyboard are ignored.
    await t.sendKeyEvent(LogicalKeyboardKey.keyX, character: 'x');
    await t.pump();
    expect(_text(t), '+123');
  });

  testWidgets('960x540 TV: the dialog is compact and the keyboard fits under the field', (t) async {
    await _openDialog(t, size: const Size(960, 540), dpr: 2);
    final dialog = t.getRect(find.descendant(of: find.byType(Dialog), matching: find.byType(Material)).first);
    expect(dialog.height, lessThan(540 * 0.5), reason: 'only the field and buttons at first');
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    final field = t.getRect(find.byKey(Keys.textEntryField));
    final q = t.getRect(find.byKey(const ValueKey('key-q')));
    expect(q.top, greaterThan(field.top));
    expect(q.height, inInclusiveRange(30, 34));
    final ok = t.getRect(find.byKey(const ValueKey('key-ok')));
    expect(ok.bottom, lessThanOrEqualTo(540));
  });
}
