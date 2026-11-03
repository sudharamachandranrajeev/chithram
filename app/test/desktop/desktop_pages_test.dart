import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/youtube/youtube_fixture.dart';
import 'package:chithram/src/features/youtube/youtube_service.dart';
import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/common/app.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/common/keys.dart';
import 'package:chithram/src/ui/common/sections.dart';
import 'package:chithram/src/ui/desktop/desktop_shell.dart';
import 'package:chithram/src/ui/desktop/shortcuts.dart';
import 'package:chithram/src/ui/desktop/window_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

late AppServices _services;

Future<void> _app(WidgetTester t) async {
  t.view.physicalSize = const Size(1440, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  _services = AppServices.memory(youtube: YouTubeService(browse: FixtureBrowse('')));
  await t.pumpWidget(ChithramApp(services: _services, formFactor: FormFactor.desktop));
  await t.pumpAndSettle();
}

NavigatorState get _nav => _services.navigatorKey.currentState!;

Future<void> _push(WidgetTester t, Widget body) async {
  _nav.push(MaterialPageRoute<void>(builder: (_) => Scaffold(body: body)));
  await t.pumpAndSettle();
}

Future<void> _chord(WidgetTester t, LogicalKeyboardKey key, {bool ctrl = false, bool alt = false}) async {
  if (ctrl) await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (alt) await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await t.sendKeyEvent(key);
  if (alt) await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  if (ctrl) await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pumpAndSettle();
}

const _focusedPage = Focus(autofocus: true, child: Text('over'));

class _Chrome extends NativeChrome {
  const _Chrome();

  @override
  bool get custom => true;
}

void main() {
  group('shortcuts on a page pushed over the shell', () {
    testWidgets('Esc closes it', (t) async {
      await _app(t);
      await _push(t, _focusedPage);
      expect(_nav.canPop(), isTrue);
      await _chord(t, LogicalKeyboardKey.escape);
      expect(_nav.canPop(), isFalse);
      expect(find.text('over'), findsNothing);
    });

    testWidgets('Alt+Left closes it', (t) async {
      await _app(t);
      await _push(t, _focusedPage);
      await _chord(t, LogicalKeyboardKey.arrowLeft, alt: true);
      expect(_nav.canPop(), isFalse);
    });

    testWidgets('Ctrl+K closes it and focuses the search field', (t) async {
      await _app(t);
      await _push(t, _focusedPage);
      await _chord(t, LogicalKeyboardKey.keyK, ctrl: true);
      expect(_nav.canPop(), isFalse);
      final field = t.widget<EditableText>(find.descendant(
        of: find.byKey(const ValueKey('titlebar-search')),
        matching: find.byType(EditableText),
      ));
      expect(field.focusNode.hasFocus, isTrue);
    });

    testWidgets('Ctrl+3 closes it and shows Live TV', (t) async {
      await _app(t);
      await _push(t, _focusedPage);
      await _chord(t, LogicalKeyboardKey.digit3, ctrl: true);
      expect(_nav.canPop(), isFalse);
      expect(find.byKey(ValueKey('nav-active-${Section.liveTv.name}')), findsOneWidget);
    });

    testWidgets('Esc in a focused text field only leaves the field', (t) async {
      await _app(t);
      await _push(t, const TextField(autofocus: true));
      expect(typingInTextField(), isTrue);
      await _chord(t, LogicalKeyboardKey.escape);
      expect(typingInTextField(), isFalse);
      expect(_nav.canPop(), isTrue, reason: 'the page stays');
      await _chord(t, LogicalKeyboardKey.escape);
      expect(_nav.canPop(), isFalse, reason: 'a second Esc closes it');
    });
  });

  group('AltGr', () {
    const at = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.digit2,
      logicalKey: LogicalKeyboardKey.digit2,
      character: '@',
      timeStamp: Duration.zero,
    );
    const noChar = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.digit2,
      logicalKey: LogicalKeyboardKey.digit2,
      timeStamp: Duration.zero,
    );

    testWidgets('Ctrl+Alt with a character is typing, not a chord', (t) async {
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyDownEvent(LogicalKeyboardKey.altRight);
      expect(isShortcutChord(at), isFalse);
      expect(isShortcutChord(noChar), isTrue);
      await t.sendKeyUpEvent(LogicalKeyboardKey.altRight);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });

    testWidgets('Ctrl alone, or Alt alone, is a chord; nothing held is not', (t) async {
      expect(isShortcutChord(at), isFalse);
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      expect(isShortcutChord(at), isTrue);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      expect(isShortcutChord(at), isTrue);
      await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    });
  });

  group('semantics', () {
    testWidgets('buttons, nav items, pills and cards expose the tap action', (t) async {
      final handle = t.ensureSemantics();
      t.view.physicalSize = const Size(1440, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(AppServicesScope(
        services: AppServices.memory(youtube: YouTubeService(browse: FixtureBrowse(''))),
        child: FormScope(
          form: FormFactor.desktop,
          child: MaterialApp(
            theme: buildChithramTheme(form: FormFactor.desktop),
            home: const DesktopShell(chrome: _Chrome()),
          ),
        ),
      ));
      await t.pumpAndSettle();
      const labels = [
        'Minimize',
        'Maximize',
        'Close',
        'Home',
        'Live TV',
        'Settings',
        'Play',
        'Browse YouTube',
        'Slide 1 of 5',
        'View all',
        'Next videos',
      ];
      for (final label in labels) {
        final node = t.getSemantics(find.bySemanticsLabel(label).first);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue, reason: label);
      }
      handle.dispose();
    });
  });

  group('window size', () {
    const desired = Size(1440, 900);

    test('fits in 90% of the work area', () {
      // 1920x1080 at 125%: 1536x864 logical, about 1536x824 without the taskbar.
      final fit = fitWindowSize(desired, const Size(1536, 824));
      expect(fit.size.width, closeTo(1382.4, 0.01));
      expect(fit.size.height, closeTo(741.6, 0.01));
      expect(fit.maximize, isFalse);
    });

    test('a big display gets the default size', () {
      final fit = fitWindowSize(desired, const Size(2560, 1400));
      expect(fit.size, desired);
      expect(fit.maximize, isFalse);
    });

    test('never below the minimum', () {
      final fit = fitWindowSize(desired, const Size(1100, 700));
      expect(fit.size, minWindowSize);
      expect(fit.maximize, isFalse);
    });

    test('maximizes when even the minimum does not fit', () {
      final fit = fitWindowSize(desired, const Size(1000, 600));
      expect(fit.size, minWindowSize);
      expect(fit.maximize, isTrue);
    });
  });
}
