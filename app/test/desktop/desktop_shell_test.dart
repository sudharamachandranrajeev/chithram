import 'package:chithram/src/core/prefs.dart';
import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/youtube/youtube_fixture.dart';
import 'package:chithram/src/features/youtube/youtube_service.dart';
import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/common/app.dart';
import 'package:chithram/src/ui/common/glass.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/common/sections.dart';
import 'package:chithram/src/ui/common/video_billboard.dart' show kenBurnsTime;
import 'package:chithram/src/ui/common/video_card.dart';
import 'package:chithram/src/ui/desktop/desktop_home.dart';
import 'package:chithram/src/ui/desktop/desktop_shell.dart';
import 'package:chithram/src/ui/desktop/shortcuts.dart';
import 'package:chithram/src/ui/desktop/sidebar.dart';
import 'package:chithram/src/ui/phone/phone_shell.dart';
import 'package:chithram/src/ui/tv/tv_shell.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_chrome.dart';
import 'static_feed.dart';

AppServices _services({Prefs? prefs}) => AppServices.memory(
      prefs: prefs,
      youtube: YouTubeService(browse: FixtureBrowse('')),
    );

Future<void> _pump(
  WidgetTester t, {
  Size size = const Size(1440, 900),
  Prefs? prefs,
  FakeChrome? chrome,
  bool disableAnimations = false,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(AppServicesScope(
    services: _services(prefs: prefs),
    child: FormScope(
      form: FormFactor.desktop,
      child: MediaQuery(
        data: MediaQueryData(size: size, disableAnimations: disableAnimations),
        child: MaterialApp(
          theme: buildChithramTheme(form: FormFactor.desktop),
          home: DesktopShell(chrome: chrome ?? FakeChrome()),
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

double _sidebarWidth(WidgetTester t) => t.getSize(find.byKey(const ValueKey('desktop-sidebar'))).width;

Finder _active(Section s) => find.byKey(ValueKey('nav-active-${s.name}'));

Future<void> _chord(WidgetTester t, LogicalKeyboardKey key, {bool ctrl = false, bool alt = false}) async {
  if (ctrl) await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (alt) await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await t.sendKeyEvent(key);
  if (alt) await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  if (ctrl) await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pumpAndSettle();
}

FocusNode? _primary() => FocusManager.instance.primaryFocus;

bool _searchHasFocus(WidgetTester t) =>
    t.widget<EditableText>(find.descendant(
      of: find.byKey(const ValueKey('titlebar-search')),
      matching: find.byType(EditableText),
    )).focusNode.hasFocus;

void main() {
  group('shell switch', () {
    Future<void> pumpApp(WidgetTester t, Size size, FormFactor form, {Prefs? prefs}) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(ChithramApp(services: _services(prefs: prefs), formFactor: form));
      await t.pumpAndSettle();
    }

    testWidgets('phone, tv and desktop each get their own shell', (t) async {
      await pumpApp(t, const Size(412, 915), FormFactor.phone);
      expect(find.byType(PhoneShell), findsOneWidget);
      expect(find.byType(TvShell), findsNothing);
      expect(find.byType(DesktopShell), findsNothing);

      await pumpApp(t, const Size(960, 540), FormFactor.tv);
      expect(find.byType(TvShell), findsOneWidget);
      expect(find.byType(PhoneShell), findsNothing);
      expect(find.byType(DesktopShell), findsNothing);

      await pumpApp(t, const Size(1440, 900), FormFactor.desktop);
      expect(find.byType(DesktopShell), findsOneWidget);
      expect(find.byType(TvShell), findsNothing);
      expect(find.byType(PhoneShell), findsNothing);
    });

    testWidgets('the 10-foot preference sends a desktop to the TV shell', (t) async {
      await pumpApp(t, const Size(1440, 900), FormFactor.desktop, prefs: Prefs.memory({tenFootPref: true}));
      expect(find.byType(TvShell), findsOneWidget);
      expect(find.byType(DesktopShell), findsNothing);
    });
  });

  group('sidebar', () {
    testWidgets('240 dp wide at 1440, with labels and Settings at the bottom', (t) async {
      await _pump(t);
      expect(_sidebarWidth(t), 240);
      for (final s in desktopSectionOrder) {
        expect(find.text(s.label), findsWidgets);
      }
      final settingsY = t.getCenter(find.text('Settings')).dy;
      for (final s in desktopSectionOrder.where((s) => s != Section.settings)) {
        expect(t.getCenter(find.text(s.label).first).dy, lessThan(settingsY));
      }
      expect(_active(Section.home), findsOneWidget);
    });

    testWidgets('collapses to a 72 dp icon rail below 1200 wide', (t) async {
      await _pump(t, size: const Size(1100, 800));
      expect(_sidebarWidth(t), 72);
      expect(find.text('Live TV'), findsNothing); // no labels in the rail
    });

    testWidgets('Ctrl+B collapses and expands, and the choice is saved', (t) async {
      final prefs = Prefs.memory();
      await _pump(t, prefs: prefs);
      expect(_sidebarWidth(t), 240);
      await _chord(t, LogicalKeyboardKey.keyB, ctrl: true);
      expect(_sidebarWidth(t), 72);
      expect(prefs.getBool(sidebarCollapsedPref), isTrue);
      await _chord(t, LogicalKeyboardKey.keyB, ctrl: true);
      expect(_sidebarWidth(t), 240);
      expect(prefs.getBool(sidebarCollapsedPref), isFalse);
    });

    testWidgets('a saved collapse is there at start', (t) async {
      await _pump(t, prefs: Prefs.memory({sidebarCollapsedPref: true}));
      expect(_sidebarWidth(t), 72);
    });

    testWidgets('hover does not move focus; a click shows the section but does not enter it', (t) async {
      await _pump(t);
      final before = _primary();
      expect(before?.debugLabel, 'rail Home');

      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(t.getCenter(find.byKey(const ValueKey('nav-liveTv'))));
      await t.pumpAndSettle();
      expect(_primary(), same(before), reason: 'hovering Live TV must not take focus');
      expect(_active(Section.home), findsOneWidget);

      await mouse.down(t.getCenter(find.byKey(const ValueKey('nav-liveTv'))));
      await mouse.up();
      await t.pumpAndSettle();
      expect(_active(Section.liveTv), findsOneWidget);
      expect(_primary()?.debugLabel, 'rail Live TV', reason: 'a click stays on the sidebar item');
    });
  });

  group('shortcuts', () {
    testWidgets('Ctrl+K and / focus the search field; Esc leaves it', (t) async {
      await _pump(t);
      expect(_searchHasFocus(t), isFalse);
      await _chord(t, LogicalKeyboardKey.keyK, ctrl: true);
      expect(_searchHasFocus(t), isTrue);
      expect(_active(Section.search), findsOneWidget, reason: 'focusing search shows Search');
      await _chord(t, LogicalKeyboardKey.escape);
      expect(_searchHasFocus(t), isFalse);
      expect(_active(Section.home), findsOneWidget, reason: 'Esc returns to where it was');

      await _chord(t, LogicalKeyboardKey.slash);
      expect(_searchHasFocus(t), isTrue);
    });

    testWidgets('/ is a normal character while typing in a text field', (t) async {
      await _pump(t);
      await _chord(t, LogicalKeyboardKey.keyK, ctrl: true);
      expect(typingInTextField(), isTrue);
      // Esc, then a text field has no focus: / works again.
      await _chord(t, LogicalKeyboardKey.escape);
      expect(typingInTextField(), isFalse);
    });

    testWidgets('Ctrl+1 to Ctrl+6 and Ctrl+, pick the sections', (t) async {
      await _pump(t);
      const digits = [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
      ];
      for (var i = 0; i < digits.length; i++) {
        await _chord(t, digits[i], ctrl: true);
        expect(_active(desktopSectionOrder[i]), findsOneWidget, reason: 'Ctrl+${i + 1}');
      }
      await _chord(t, LogicalKeyboardKey.digit1, ctrl: true);
      await _chord(t, LogicalKeyboardKey.comma, ctrl: true);
      expect(_active(Section.settings), findsOneWidget);
    });

    testWidgets('Alt+Left goes back to Home', (t) async {
      await _pump(t);
      await _chord(t, LogicalKeyboardKey.digit3, ctrl: true);
      expect(_active(Section.liveTv), findsOneWidget);
      await _chord(t, LogicalKeyboardKey.arrowLeft, alt: true);
      expect(_active(Section.home), findsOneWidget);
    });

    testWidgets('F11 toggles fullscreen through the window', (t) async {
      final chrome = FakeChrome();
      await _pump(t, chrome: chrome);
      await _chord(t, LogicalKeyboardKey.f11);
      expect(chrome.calls, contains('fullscreen'));
    });
  });

  group('title bar', () {
    testWidgets('custom frame: min, max and close buttons, with labels', (t) async {
      final chrome = FakeChrome();
      await _pump(t, chrome: chrome);
      for (final label in ['Minimize', 'Maximize', 'Close']) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }
      await t.tap(find.bySemanticsLabel('Minimize'));
      await t.tap(find.bySemanticsLabel('Maximize'));
      await t.tap(find.bySemanticsLabel('Close'));
      expect(chrome.calls, containsAllInOrder(['minimize', 'maximize', 'close']));
      expect(chrome.calls.first, 'frame:true');
    });

    testWidgets('native frame (Linux): no window buttons, no drag area', (t) async {
      await _pump(t, chrome: FakeChrome(custom: false));
      expect(find.bySemanticsLabel('Close'), findsNothing);
      expect(find.byKey(const ValueKey('titlebar-drag')), findsNothing);
    });

    testWidgets('the search field shows its hint and key hint, and submitting opens search', (t) async {
      await _pump(t);
      expect(find.text('Search movies, channels, videos…'), findsOneWidget);
      expect(find.text('Ctrl K'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('titlebar-search')));
      await t.enterText(find.byKey(const ValueKey('titlebar-search')), 'fixture');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await t.pumpAndSettle();
      expect(Navigator.of(t.element(find.byType(DesktopShell, skipOffstage: false))).canPop(), isTrue);
    });
  });

  group('tab order', () {
    testWidgets('title bar, then sidebar, then content', (t) async {
      await _pump(t, chrome: FakeChrome(custom: false));
      await _chord(t, LogicalKeyboardKey.keyK, ctrl: true);
      expect(_searchHasFocus(t), isTrue);
      await _chord(t, LogicalKeyboardKey.tab);
      expect(_primary()?.debugLabel, startsWith('rail'), reason: 'Tab from the title bar enters the sidebar');
      // Past the six sidebar items: into the content.
      for (var i = 0; i < Section.values.length; i++) {
        await _chord(t, LogicalKeyboardKey.tab);
      }
      expect(_primary()?.debugLabel, isNot(startsWith('rail')));
      expect(_searchHasFocus(t), isFalse);
    });
  });

  group('home', () {
    int cardsInFirstRow(WidgetTester t) => find
        .descendant(
          of: find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('home-popular')).first,
          matching: find.byType(VideoCard),
        )
        .evaluate()
        .length;

    test('cards per row by window width', () {
      expect(cardsPerRow(1440), 4);
      expect(cardsPerRow(1920), 4);
      expect(cardsPerRow(1439), 3);
      expect(cardsPerRow(1100), 3);
      expect(cardsPerRow(1099), 2);
    });

    testWidgets('4 cards per row at 1440', (t) async {
      await _pump(t);
      expect(cardsInFirstRow(t), 4);
    });

    testWidgets('3 cards per row at 1100', (t) async {
      await _pump(t, size: const Size(1100, 800));
      expect(cardsInFirstRow(t), 3);
    });

    List<String> heroTexts(WidgetTester t) => [
          for (final w in t.widgetList<Text>(find.descendant(
            of: find.byKey(const ValueKey('desktop-hero')),
            matching: find.byType(Text),
          )))
            w.data ?? '',
        ];

    testWidgets('the hero advances every 8 s, pauses on hover, and stops when animations are off', (t) async {
      // Settles when the first slide's Ken Burns push ends, 7 s in.
      await _pump(t);
      final first = heroTexts(t);
      await t.pump(heroAutoAdvance - kenBurnsTime - const Duration(milliseconds: 500));
      expect(heroTexts(t), first, reason: 'not yet');
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      final second = heroTexts(t);
      expect(second, isNot(first), reason: 'advanced after 8 s');

      // Hover pauses it.
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(t.getCenter(find.byKey(const ValueKey('desktop-hero'))));
      await t.pump();
      await t.pump(const Duration(seconds: 20));
      await t.pumpAndSettle();
      expect(heroTexts(t), second, reason: 'paused while hovered');
    });

    testWidgets('the hero does not auto-advance when the system asks for no animation', (t) async {
      await _pump(t, disableAnimations: true);
      final first = heroTexts(t);
      await t.pump(const Duration(seconds: 30));
      expect(heroTexts(t), first);
    });

    testWidgets('Continue watching cards carry a progress bar; other rows do not', (t) async {
      t.view.physicalSize = const Size(1440, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(AppServicesScope(
        services: AppServices.memory(feed: StaticFeed()),
        child: FormScope(
          form: FormFactor.desktop,
          child: MaterialApp(
            theme: buildChithramTheme(form: FormFactor.desktop),
            home: const DesktopShell(),
          ),
        ),
      ));
      await t.pumpAndSettle();
      Finder inRow(String id) => find.descendant(
            of: find.byKey(ValueKey('home-$id')),
            matching: find.byType(WatchProgress),
          );
      expect(inRow('continue'), findsNWidgets(4));
      expect(inRow('popular-music'), findsNothing);
    });

    testWidgets('page dots and the row chevrons are labelled buttons', (t) async {
      await _pump(t);
      expect(find.bySemanticsLabel('Slide 1 of 5'), findsOneWidget);
      expect(find.bySemanticsLabel('Next videos'), findsWidgets);
      expect(find.bySemanticsLabel('Previous videos'), findsWidgets);
      expect(find.text('VIEW ALL ›'), findsWidgets);
    });
  });
}
