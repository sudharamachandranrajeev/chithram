import 'package:chithram/src/ui/common/keys.dart';
import 'package:chithram/src/ui/common/text_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _openDialog(WidgetTester t, {TextEntryKind kind = TextEntryKind.magnet}) async {
  t.view.physicalSize = const Size(1920, 1080);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (c) => TextButton(onPressed: () => askText(c, title: 'Link', kind: kind), child: const Text('go')),
    ),
  ));
  await t.tap(find.text('go'));
  await t.pumpAndSettle();
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

  testWidgets('the URL keyboard types a magnet prefix', (t) async {
    await _openDialog(t);
    for (final c in 'magnet:?xt='.split('')) {
      await t.tap(find.byKey(ValueKey('key-$c')));
      await t.pump();
    }
    final text = t.widget<TextField>(find.byKey(Keys.textEntryField)).controller!.text;
    expect(text, 'magnet:?xt=');
    // Shift gives capitals; backspace removes one character.
    await t.tap(find.byKey(const ValueKey('key-shift')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('key-B')));
    await t.tap(find.byKey(const ValueKey('key-backspace')));
    await t.pump();
    expect(t.widget<TextField>(find.byKey(Keys.textEntryField)).controller!.text, 'magnet:?xt=');
  });

  testWidgets('Send from phone is offered for links', (t) async {
    await _openDialog(t);
    expect(find.byKey(Keys.textEntrySend), findsOneWidget);
    expect(find.byKey(Keys.textEntryPaste), findsOneWidget);
  });

  testWidgets('a PIN entry has no link helpers', (t) async {
    await _openDialog(t, kind: TextEntryKind.pin);
    expect(find.byKey(Keys.textEntrySend), findsNothing);
    expect(find.byKey(Keys.textEntryKeyboard), findsNothing);
    expect(find.byKey(Keys.textEntryPaste), findsOneWidget);
  });
}
