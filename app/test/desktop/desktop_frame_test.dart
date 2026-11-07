import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/player/play_request.dart';
import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/common/keys.dart';
import 'package:chithram/src/ui/desktop/shortcuts.dart';
import 'package:chithram/src/ui/desktop/title_bar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_chrome.dart';

final _navKey = GlobalKey<NavigatorState>();
NavigatorState get _nav => _navKey.currentState!;

/// The desktop frame as the app builds it, over a plain home page (the real
/// shell is covered by desktop_pages_test).
Future<FakeChrome> _frame(WidgetTester t) async {
  t.view.physicalSize = const Size(1440, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final chrome = FakeChrome();
  final routes = DesktopRouteObserver();
  await t.pumpWidget(AppServicesScope(
    services: AppServices.memory(),
    child: FormScope(
      form: FormFactor.desktop,
      child: MaterialApp(
        navigatorKey: _navKey,
        navigatorObservers: [routes],
        theme: buildChithramTheme(form: FormFactor.desktop),
        builder: (context, child) => DesktopShortcutScope(
          navigatorKey: _navKey,
          routes: routes,
          chrome: chrome,
          child: child!,
        ),
        home: const Scaffold(body: Text('home')),
      ),
    ),
  ));
  await t.pumpAndSettle();
  return chrome;
}

Future<void> _push(WidgetTester t, Widget body, {String? name}) async {
  _nav.push(MaterialPageRoute<void>(
    settings: RouteSettings(name: name),
    builder: (_) => Scaffold(body: body),
  ));
  await t.pumpAndSettle();
}

Future<void> _key(WidgetTester t, LogicalKeyboardKey key, {bool alt = false}) async {
  if (alt) await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await t.sendKeyEvent(key);
  if (alt) await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await t.pumpAndSettle();
}

/// A page that keeps itself open on the first Back, like the player with a
/// menu open.
class _Guarded extends StatefulWidget {
  const _Guarded();

  @override
  State<_Guarded> createState() => _GuardedState();
}

class _GuardedState extends State<_Guarded> {
  bool open = true;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !open,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => open = false);
        },
        child: Focus(autofocus: true, child: Text(open ? 'menu open' : 'menu closed')),
      );
}

void main() {
  testWidgets('the title bar shows Back only over the shell, and Back closes the page', (t) async {
    await _frame(t);
    expect(find.byType(DesktopTitleBar), findsOneWidget);
    expect(find.byKey(Keys.titleBarBack), findsNothing);

    await _push(t, const Text('details'));
    expect(find.byKey(Keys.titleBarBack), findsOneWidget);
    expect(find.text('Chithram'), findsOneWidget, reason: 'the same bar stays over the page');
    expect(find.byIcon(Icons.close_rounded), findsOneWidget, reason: 'window buttons stay reachable');

    await t.tap(find.byKey(Keys.titleBarBack));
    await t.pumpAndSettle();
    expect(find.text('details'), findsNothing);
    expect(find.byKey(Keys.titleBarBack), findsNothing);
  });

  testWidgets('the mouse back button closes the page', (t) async {
    await _frame(t);
    await _push(t, const Text('details'));
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse, buttons: kBackMouseButton);
    await mouse.down(const Offset(700, 500));
    await mouse.up();
    await t.pumpAndSettle();
    expect(find.text('details'), findsNothing);
  });

  testWidgets('Esc, Alt+Left and Back let the page close something first', (t) async {
    await _frame(t);
    await _push(t, const _Guarded());
    await _key(t, LogicalKeyboardKey.escape);
    expect(find.text('menu closed'), findsOneWidget, reason: 'Esc asked the page (maybePop)');
    await _key(t, LogicalKeyboardKey.escape);
    expect(find.text('menu closed'), findsNothing);

    await _push(t, const _Guarded());
    await _key(t, LogicalKeyboardKey.arrowLeft, alt: true);
    expect(find.text('menu closed'), findsOneWidget);
    await t.tap(find.byKey(Keys.titleBarBack));
    await t.pumpAndSettle();
    expect(_nav.canPop(), isFalse);
  });

  testWidgets('the bar folds away under the player and comes back after it', (t) async {
    await _frame(t);
    await _push(t, const Text('player'), name: playerRouteName);
    expect(t.getSize(find.byType(ClipRect).first).height, 0);
    expect(find.byKey(Keys.titleBarBack).hitTestable(), findsNothing);
    _nav.pop();
    await t.pumpAndSettle();
    expect(t.getSize(find.byType(ClipRect).first).height, titleBarHeight);
  });

  testWidgets('focusing the search field from a page goes back to the shell', (t) async {
    await _frame(t);
    await _push(t, const Text('details'));
    await t.tap(find.byKey(const ValueKey('titlebar-search')));
    await t.pumpAndSettle();
    expect(_nav.canPop(), isFalse);
  });
}
