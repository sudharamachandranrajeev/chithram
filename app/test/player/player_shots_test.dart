import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/player/play_request.dart';
import 'package:chithram/src/player/player_route.dart';
import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/desktop/shortcuts.dart';
import 'package:chithram_player/chithram_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../desktop/fake_chrome.dart';
import 'fake_engine.dart';

/// Renders the player's on-screen display on each form to PNG files, for
/// checking the look. Runs only when CHITHRAM_SHOTS names an output folder:
/// `CHITHRAM_SHOTS=/tmp/shots flutter test test/player/player_shots_test.dart`.
///
/// Titles are made up and the "video" is a painted gradient; nothing touches
/// the network.
void main() {
  final out = Platform.environment['CHITHRAM_SHOTS'];

  Future<void> loadFonts() async {
    final poppins = FontLoader('Poppins');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      poppins.addFont(
        Future.value(ByteData.sublistView(File('assets/fonts/Poppins-$w.ttf').readAsBytesSync())),
      );
    }
    await poppins.load();
    final root = Platform.environment['FLUTTER_ROOT'] ?? '';
    final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final l = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
      await l.load();
    }
  }

  testWidgets('player screenshots', skip: out == null, (t) async {
    await t.runAsync(loadFonts);
    debugDisableShadows = false;
    final boundary = GlobalKey();

    Future<void> shot(String name) async {
      final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await t.runAsync(() async {
        final image = await render.toImage(pixelRatio: t.view.devicePixelRatio);
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File('$out/$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    /// The app's frame (desktop) and a home page; returns the navigator.
    Future<(NavigatorState, FakeChrome)> app(FormFactor form, Size size) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      final nav = GlobalKey<NavigatorState>();
      final chrome = FakeChrome();
      final routes = DesktopRouteObserver();
      await t.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: AppServicesScope(
            services: AppServices.memory(),
            child: FormScope(
              form: form,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                navigatorKey: nav,
                navigatorObservers: [routes],
                theme: buildChithramTheme(form: form),
                builder: form == FormFactor.desktop
                    ? (context, child) => DesktopShortcutScope(
                        navigatorKey: nav,
                        routes: routes,
                        chrome: chrome,
                        child: child!,
                      )
                    : null,
                home: const Scaffold(body: SizedBox.expand()),
              ),
            ),
          ),
        ),
      );
      await t.pump();
      return (nav.currentState!, chrome);
    }

    Future<void> player(String name, FormFactor form, Size size, {required bool live}) async {
      final (nav, chrome) = await app(form, size);
      final engine = _PictureEngine();
      unawaited(
        nav.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: playerRouteName),
            builder: (_) => PlayerRoute(
              request: PlayRequest(
                itemId: 'url:$name',
                title: live ? 'Harbour Lights News' : 'The Long Monsoon',
                subtitle: live ? 'Channel 7' : 'Season 1 · Episode 3',
                isLive: live,
                status: live ? null : Stream.value('2.4 MB/s · 38 peers'),
                resolve: () async => MediaSpec(videoUrl: 'http://x/a.mp4', isLive: live),
              ),
              engineFactory: () async => engine,
              chrome: chrome,
            ),
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      if (!live) {
        engine.durationC.add(const Duration(hours: 1, minutes: 52, seconds: 10));
        engine.positionC.add(const Duration(minutes: 41, seconds: 27));
        engine.bufferedC.add(const Duration(minutes: 49));
      }
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      // TV: show where the D-pad focus sits.
      if (form == FormFactor.tv) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await t.pump(const Duration(milliseconds: 300));
        // The focus animation starts on that frame; let it run.
        await t.pump(const Duration(milliseconds: 300));
      }
      await shot(name);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    }

    for (final live in [false, true]) {
      final kind = live ? 'live' : 'vod';
      await player('desktop-1440x900-$kind', FormFactor.desktop, const Size(1440, 900), live: live);
      await player('phone-800x360-$kind', FormFactor.phone, const Size(800, 360), live: live);
      await player('tv-1920x1080-$kind', FormFactor.tv, const Size(1920, 1080), live: live);
    }

    // A pushed desktop page: the title bar stays and shows Back.
    final (nav, _) = await app(FormFactor.desktop, const Size(1440, 900));
    unawaited(
      nav.push(
        MaterialPageRoute<void>(
          builder: (context) => Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Torrent files', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  for (final f in ['The.Long.Monsoon.S01E03.mkv', 'Subtitles/English.srt', 'Sample.mkv'])
                    ListTile(leading: const Icon(Icons.movie_outlined), title: Text(f)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await shot('desktop-1440x900-pushed-page');
    await t.pumpWidget(const SizedBox());
    t.view.reset();
    // The binding checks this is back to its default before the test ends.
    debugDisableShadows = true;
  });
}

/// A fake engine whose picture is a painted dusk scene, so the display is
/// judged over something like video rather than black.
class _PictureEngine extends FakeEngine {
  @override
  Widget get view => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF2B3A67), Color(0xFFB5577A), Color(0xFFF2A65A), Color(0xFF3A2E39)],
        stops: [0, 0.45, 0.62, 1],
      ),
    ),
    child: SizedBox.expand(),
  );
}
