import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/ui/focus_card.dart';
import 'package:chithram/src/ui/keyboard.dart';
import 'package:chithram/src/ui/keys.dart';
import 'package:chithram/src/ui/search_page.dart';
import 'package:chithram/src/ui/text_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the calls the text field makes to the platform keyboard.
List<String> _recordKeyboard(WidgetTester t) {
  final calls = <String>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.textInput, (call) async {
    calls.add(call.method);
    return null;
  });
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.textInput, null));
  return calls;
}

void _phone(WidgetTester t) {
  t.view.physicalSize = const Size(1264, 2780);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

void main() {
  testWidgets('search on a phone is a TextField that asks for the system keyboard', (t) async {
    _phone(t);
    final calls = _recordKeyboard(t);
    final focus = SectionFocus();
    await t.pumpWidget(AppServicesScope(
      services: AppServices.memory(),
      child: MaterialApp(home: Scaffold(body: SearchPage(focus: focus))),
    ));
    await t.pump();

    expect(find.byType(OnScreenKeyboard), findsNothing);
    final field = find.byKey(const ValueKey('search-field'));
    expect(field, findsOneWidget);
    expect(t.widget<TextField>(field).focusNode?.hasFocus ?? true, isTrue);
    expect(calls, contains('TextInput.show'));

    calls.clear();
    await t.tap(field);
    await t.pump();
    expect(calls, contains('TextInput.show'), reason: 'tapping the field shows the keyboard');
    await t.enterText(field, 'big buck');
    expect(t.widget<TextField>(field).controller!.text, 'big buck');
  });

  testWidgets('text entry on a phone uses the system keyboard only', (t) async {
    _phone(t);
    final calls = _recordKeyboard(t);
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => TextButton(onPressed: () => askText(c, title: 'Link'), child: const Text('go')),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.byType(UrlKeyboard), findsNothing);
    expect(find.byKey(Keys.textEntryKeyboard), findsNothing);
    expect(find.byKey(Keys.textEntryField), findsOneWidget);
    expect(calls, contains('TextInput.show'));
    expect(find.byKey(Keys.textEntryPaste), findsOneWidget);
  });

  testWidgets('openSearch shows the text and runs the search', (t) async {
    _phone(t);
    await t.pumpWidget(AppServicesScope(
      services: AppServices.memory(),
      child: MaterialApp(
        home: Builder(builder: (c) => TextButton(onPressed: () => openSearch(c, 'fixture'), child: const Text('go'))),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pump();
    await t.pump();
    expect(t.widget<TextField>(find.byKey(const ValueKey('search-field'))).controller!.text, 'fixture');
    // Let the (offline) lookup finish.
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
  });
}
