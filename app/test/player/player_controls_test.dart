import 'package:chithram/src/core/prefs.dart';
import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/player/play_request.dart';
import 'package:chithram/src/player/player_keys.dart';
import 'package:chithram/src/player/player_route.dart';
import 'package:chithram/src/player/tracks.dart';
import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/common/keys.dart';
import 'package:chithram/src/ui/desktop/shortcuts.dart';
import 'package:chithram_player/chithram_player.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../desktop/fake_chrome.dart';
import 'fake_engine.dart';

PlayRequest _request({bool live = false}) => PlayRequest(
      itemId: 'url:a',
      title: 'A film',
      isLive: live,
      resolve: () async => MediaSpec(videoUrl: 'http://x/a.mp4', isLive: live),
    );

final _navKey = GlobalKey<NavigatorState>();

/// A home page with the player pushed over it, as `openPlayer` does. The
/// desktop gets the app's frame above the Navigator, so Esc and the mouse
/// back button take the real path.
Future<(FakeEngine, FakeChrome)> _open(
  WidgetTester t, {
  FormFactor form = FormFactor.desktop,
  bool live = false,
  Prefs? prefs,
  Size size = const Size(1440, 900),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final engine = FakeEngine();
  final chrome = FakeChrome();
  final routes = DesktopRouteObserver();
  await t.pumpWidget(AppServicesScope(
    services: AppServices.memory(prefs: prefs),
    child: FormScope(
      form: form,
      child: MaterialApp(
        navigatorKey: _navKey,
        navigatorObservers: [routes],
        theme: buildChithramTheme(form: form),
        builder: form == FormFactor.desktop
            ? (context, child) => DesktopShortcutScope(
                  navigatorKey: _navKey,
                  routes: routes,
                  chrome: chrome,
                  child: child!,
                )
            : null,
        home: const Scaffold(body: Text('home')),
      ),
    ),
  ));
  _navKey.currentState!.push(MaterialPageRoute<void>(
    settings: const RouteSettings(name: playerRouteName),
    builder: (_) => PlayerRoute(
      request: _request(live: live),
      engineFactory: () async => engine,
      chrome: chrome,
    ),
  ));
  await t.pump();
  await t.pump(const Duration(seconds: 1));
  await t.pump();
  // The frame's title bar folds away (it hears of the route after a frame).
  await t.pump(const Duration(milliseconds: 500));
  return (engine, chrome);
}

bool get _playerOpen => find.byKey(Keys.playerRoot).evaluate().isNotEmpty;

Future<void> _key(WidgetTester t, LogicalKeyboardKey key) async {
  await t.sendKeyEvent(key);
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

bool _focused(Key key) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  if (context.widget.key == key) return true;
  var found = false;
  context.visitAncestorElements((e) {
    found = e.widget.key == key;
    return !found;
  });
  return found;
}

Future<void> _close(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

void main() {
  group('top bar', () {
    testWidgets('Back is always there and closes the player', (t) async {
      await _open(t);
      expect(find.byKey(PlayerKeys.osdBack), findsOneWidget);
      expect(find.byKey(PlayerKeys.title), findsOneWidget);
      await t.tap(find.byKey(PlayerKeys.osdBack));
      await t.pumpAndSettle();
      expect(_playerOpen, isFalse);
      expect(find.text('home'), findsOneWidget);
      await _close(t);
    });

    testWidgets('Back is on a phone too, in landscape', (t) async {
      await _open(t, form: FormFactor.phone, size: const Size(800, 360));
      await t.tap(find.byKey(PlayerKeys.osdBack));
      // The video's double tap (seek) holds a single tap for its timeout.
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      expect(_playerOpen, isFalse);
      await _close(t);
    });

    testWidgets('a custom-frame window keeps its buttons over the video', (t) async {
      final (_, chrome) = await _open(t);
      // The app's own bar is folded away under the player but still built.
      await t.tap(find.byIcon(Icons.remove_rounded).hitTestable());
      expect(chrome.calls, contains('minimize'));
      await _close(t);
    });
  });

  group('desktop keys', () {
    testWidgets('Esc closes the player', (t) async {
      await _open(t);
      await _key(t, LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(_playerOpen, isFalse);
      await _close(t);
    });

    testWidgets('the mouse back button closes the player', (t) async {
      await _open(t);
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse, buttons: kBackMouseButton);
      await mouse.down(const Offset(700, 450));
      await mouse.up();
      await t.pumpAndSettle();
      expect(_playerOpen, isFalse);
      await _close(t);
    });

    testWidgets('Space and K play/pause; J and L seek 10 s; M mutes; Up and Down set the volume', (t) async {
      final prefs = Prefs.memory();
      final (engine, _) = await _open(t, prefs: prefs);
      engine.durationC.add(const Duration(minutes: 5));
      engine.positionC.add(const Duration(seconds: 30));
      await t.pump();
      await _key(t, LogicalKeyboardKey.space);
      expect(engine.isPlaying, isFalse);
      await _key(t, LogicalKeyboardKey.keyK);
      expect(engine.isPlaying, isTrue);
      await _key(t, LogicalKeyboardKey.keyL);
      expect(engine.seeks.last, const Duration(seconds: 40));
      await _key(t, LogicalKeyboardKey.keyJ);
      expect(engine.seeks.last, const Duration(seconds: 30));
      await _key(t, LogicalKeyboardKey.keyM);
      expect(engine.volumes.last, 0);
      await _key(t, LogicalKeyboardKey.keyM);
      expect(engine.volumes.last, 1);
      await _key(t, LogicalKeyboardKey.arrowDown);
      expect(engine.volumes.last, closeTo(0.95, 0.001));
      expect(prefs.getInt(PlayerPrefs.volume), 95);
      await _close(t);
    });

    testWidgets('the saved volume is applied at start', (t) async {
      final (engine, _) = await _open(t, prefs: Prefs.memory({PlayerPrefs.volume: 40}));
      expect(engine.volumes.first, closeTo(0.4, 0.001));
      await _close(t);
    });
  });

  group('fullscreen', () {
    testWidgets('the button and F go through the window; Esc leaves fullscreen before it closes', (t) async {
      final (_, chrome) = await _open(t);
      await t.tap(find.byKey(PlayerKeys.fullscreen));
      await t.pump();
      expect(chrome.calls.where((c) => c == 'fullscreen'), hasLength(1));
      expect(chrome.fullscreen.value, isTrue);
      expect(find.byIcon(Icons.fullscreen_exit_rounded), findsOneWidget);

      await _key(t, LogicalKeyboardKey.escape);
      expect(chrome.fullscreen.value, isFalse, reason: 'the first Esc only leaves fullscreen');
      expect(_playerOpen, isTrue);

      await _key(t, LogicalKeyboardKey.keyF);
      expect(chrome.fullscreen.value, isTrue);
      await _key(t, LogicalKeyboardKey.escape);
      await _key(t, LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(_playerOpen, isFalse);
      await _close(t);
    });

    testWidgets('closing the player leaves the fullscreen it entered', (t) async {
      final (_, chrome) = await _open(t);
      await t.tap(find.byKey(PlayerKeys.fullscreen));
      await t.pump();
      await t.tap(find.byKey(PlayerKeys.osdBack));
      await t.pumpAndSettle();
      expect(chrome.fullscreen.value, isFalse);
      await _close(t);
    });

    testWidgets('no fullscreen button on a phone or TV', (t) async {
      await _open(t, form: FormFactor.tv, size: const Size(1920, 1080));
      expect(find.byKey(PlayerKeys.fullscreen), findsNothing);
      await _close(t);
    });
  });

  group('middle row', () {
    testWidgets('-10 s and +10 s buttons seek; not on live', (t) async {
      final (engine, _) = await _open(t);
      engine.durationC.add(const Duration(minutes: 5));
      engine.positionC.add(const Duration(seconds: 30));
      await t.pump();
      await t.tap(find.byKey(PlayerKeys.rewind));
      await t.pump();
      expect(engine.seeks.last, const Duration(seconds: 20));
      await t.tap(find.byKey(PlayerKeys.forward));
      await t.pump();
      expect(engine.seeks.last, const Duration(seconds: 30));
      await t.tap(find.byKey(PlayerKeys.playPause));
      await t.pump();
      expect(engine.isPlaying, isFalse);
      await _close(t);

      await _open(t, live: true);
      expect(find.byKey(PlayerKeys.rewind), findsNothing);
      expect(find.byKey(PlayerKeys.forward), findsNothing);
      expect(find.byKey(PlayerKeys.playPause), findsOneWidget);
      await _close(t);
    });

    testWidgets('a click on a button does not take focus from the player keys', (t) async {
      final (engine, _) = await _open(t);
      await t.tap(find.byKey(PlayerKeys.playPause));
      await t.pump();
      expect(engine.isPlaying, isFalse);
      await _key(t, LogicalKeyboardKey.space);
      expect(engine.isPlaying, isTrue);
      await _close(t);
    });
  });

  group('speed', () {
    testWidgets('the menu sets the speed, shows it on the button and Esc closes only the menu', (t) async {
      final (engine, _) = await _open(t);
      expect(engine.speeds, [1.0], reason: 'normal speed at open');
      await t.tap(find.byKey(PlayerKeys.speed));
      await t.pump();
      expect(find.byKey(PlayerKeys.speedMenu), findsOneWidget);
      await t.tap(find.byKey(PlayerKeys.speedOption(1.5)));
      await t.pump();
      expect(engine.speeds.last, 1.5);
      expect(find.byKey(PlayerKeys.speedMenu), findsNothing);
      expect(find.text('1.5×'), findsOneWidget);

      await t.tap(find.byKey(PlayerKeys.speed));
      await t.pump();
      await _key(t, LogicalKeyboardKey.escape);
      expect(find.byKey(PlayerKeys.speedMenu), findsNothing);
      expect(_playerOpen, isTrue, reason: 'Esc closed the menu, not the player');
      await _close(t);
    });

    testWidgets('no speed on live', (t) async {
      final (engine, _) = await _open(t, live: true);
      expect(find.byKey(PlayerKeys.speed), findsNothing);
      expect(engine.speeds, [1.0]);
      await _close(t);
    });
  });

  group('TV D-pad', () {
    testWidgets('Down reaches play, Left and Right move along the row, OK presses; Up reaches Back', (t) async {
      final (engine, _) = await _open(t, form: FormFactor.tv, size: const Size(1920, 1080));
      engine.durationC.add(const Duration(minutes: 5));
      engine.positionC.add(const Duration(seconds: 30));
      await t.pump();
      await _key(t, LogicalKeyboardKey.arrowDown);
      expect(_focused(PlayerKeys.playPause), isTrue);
      await _key(t, LogicalKeyboardKey.arrowLeft);
      expect(_focused(PlayerKeys.rewind), isTrue);
      await _key(t, LogicalKeyboardKey.arrowLeft);
      expect(_focused(PlayerKeys.rewind), isTrue, reason: 'the row ends there');
      await _key(t, LogicalKeyboardKey.enter);
      expect(engine.seeks.last, const Duration(seconds: 20));
      await _key(t, LogicalKeyboardKey.arrowUp);
      expect(_focused(PlayerKeys.speed), isTrue, reason: 'the top bar, on its main action');
      await _key(t, LogicalKeyboardKey.arrowLeft);
      expect(_focused(PlayerKeys.osdBack), isTrue);
      await _key(t, LogicalKeyboardKey.arrowUp);
      expect(_focused(PlayerKeys.osdBack), isFalse, reason: 'Up from the top bar returns to the video');
      await _key(t, LogicalKeyboardKey.mediaPlayPause);
      expect(engine.isPlaying, isFalse);
      await _close(t);
    });

    testWidgets('Back still closes the player', (t) async {
      await _open(t, form: FormFactor.tv, size: const Size(1920, 1080));
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(_playerOpen, isFalse);
      await _close(t);
    });
  });
}
