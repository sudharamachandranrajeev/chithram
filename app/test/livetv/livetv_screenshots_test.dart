import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chithram/src/core/prefs.dart';
import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/livetv/channel_filter.dart';
import 'package:chithram/src/features/livetv/iptv_service.dart';
import 'package:chithram/src/features/livetv/livetv_library.dart';
import 'package:chithram/src/features/livetv/livetv_page.dart';
import 'package:chithram/src/features/livetv/livetv_widgets.dart';
import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/tv/focus_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv/iptv.dart';

/// Renders Live TV on desktop, phone and TV, with filters applied and a
/// filter sheet open, to PNG files for checking the look. Runs only when
/// CHITHRAM_SHOTS names an output folder:
/// `CHITHRAM_SHOTS=/tmp/shots flutter test test/livetv/livetv_screenshots_test.dart`.
///
/// Every channel, playlist and URL is made up; there are no logos, so the
/// initials fallback shows, and nothing touches the network.
void main() {
  final out = Platform.environment['CHITHRAM_SHOTS'];

  Future<void> loadFonts() async {
    final poppins = FontLoader('Poppins');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      poppins.addFont(
        Future.value(
          ByteData.sublistView(
            File('assets/fonts/Poppins-$w.ttf').readAsBytesSync(),
          ),
        ),
      );
    }
    await poppins.load();
    final root = Platform.environment['FLUTTER_ROOT'] ?? '';
    final icons = File(
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      final l = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
      await l.load();
    }
  }

  testWidgets('live tv screenshots', skip: out == null, (t) async {
    await t.runAsync(loadFonts);
    debugDisableShadows = false;
    final boundaryKey = GlobalKey();

    Future<void> settle([int rounds = 8]) async {
      for (var i = 0; i < rounds; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await t.pump(const Duration(milliseconds: 250));
      }
    }

    Future<void> shot(String name) async {
      await settle();
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final bytes = await t.runAsync(() async {
        final image = await boundary.toImage(
          pixelRatio: t.view.devicePixelRatio,
        );
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File('$out/$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    // ensureVisible on a chip in the phone's pinned header scrolls the page
    // to its end, so those are tapped where they are ([scroll] false).
    Future<void> tap(Finder f, {bool scroll = true}) async {
      if (scroll) {
        await t.ensureVisible(f);
        await settle(2);
      }
      await t.tap(f);
      await settle(3);
    }

    Future<void> pump(FormFactor form, Size size) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      final iptv = (await t.runAsync(_demoService))!;
      final prefs = Prefs.memory({
        LiveTvLibrary.favouritesKey: jsonEncode([
          'w:2',
          'w:7',
          'w:15',
          'w:21',
          'r:3',
        ]),
        LiveTvLibrary.recentKey: jsonEncode([
          'w:7',
          'r:1',
          'w:30',
          'w:2',
          'w:12',
          'r:6',
        ]),
      });
      final focus = SectionFocus();
      addTearDown(focus.dispose);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(
        AppServicesScope(
          services: AppServices.memory(iptv: iptv, prefs: prefs),
          child: FormScope(
            form: form,
            // Around the whole app, so dialogs, sheets and popovers show too.
            child: RepaintBoundary(
              key: boundaryKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: buildChithramTheme(form: form),
                home: Builder(
                  builder: (context) => Scaffold(
                    backgroundColor: ChithramColors.of(context).background,
                    body: SafeArea(child: LiveTvPage(focus: focus)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await settle();
    }

    // Desktop: grid, filtered grid, a facet popover, the list view.
    await pump(FormFactor.desktop, const Size(1440, 900));
    await shot('desktop-1-home');
    await tap(find.byKey(LiveTvFilterKeys.category('News')));
    await tap(find.byKey(LiveTvFilterKeys.facet(ChannelFacet.language)));
    await tap(
      find.byKey(LiveTvFilterKeys.option(ChannelFacet.language, 'English')),
    );
    await t.tapAt(const Offset(1430, 890));
    await settle(3);
    await shot('desktop-2-filtered');
    await tap(find.byKey(LiveTvFilterKeys.facet(ChannelFacet.country)));
    await tap(find.byKey(LiveTvFilterKeys.option(ChannelFacet.country, 'GB')));
    await shot('desktop-3-country-popover');
    await t.tapAt(const Offset(1430, 890));
    await settle(3);
    await tap(find.byTooltip('List'));
    await shot('desktop-4-list');
    await tap(find.byKey(LiveTvFilterKeys.clear));
    await tap(find.byKey(LiveTvFilterKeys.sources));
    await shot('desktop-5-sources');

    // Phone: home, filtered, the language sheet open.
    await pump(FormFactor.phone, const Size(360, 800));
    await shot('phone-1-home');
    await t.drag(find.byType(CustomScrollView), const Offset(0, -260));
    await settle(3);
    await shot('phone-2-scrolled');
    await tap(
      find.byKey(LiveTvFilterKeys.facet(ChannelFacet.language)),
      scroll: false,
    );
    await tap(
      find.byKey(LiveTvFilterKeys.option(ChannelFacet.language, 'English')),
    );
    await shot('phone-3-language-sheet');
    await tap(find.text('Done'));
    await tap(find.byKey(LiveTvFilterKeys.category('Sports')), scroll: false);
    await shot('phone-4-filtered');

    // TV: home, filtered, the country picker open.
    await pump(FormFactor.tv, const Size(1920, 1080));
    await shot('tv-1-home');
    await tap(find.byKey(LiveTvFilterKeys.category('Movies')));
    await tap(find.byKey(LiveTvFilterKeys.facet(ChannelFacet.country)));
    await tap(find.byKey(LiveTvFilterKeys.option(ChannelFacet.country, 'US')));
    await shot('tv-2-country-picker');
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(3);
    await shot('tv-3-filtered');

    await t.pumpWidget(const SizedBox());
    t.view.reset();
    debugDisableShadows = true;
  });
}

class _NoHttp implements IptvHttp {
  @override
  Future<IptvResponse> open(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 15),
  }) => throw StateError('screenshots never touch the network');
}

/// Two invented playlists: a large mixed one and a small regional one.
Future<IptvService> _demoService() async {
  final store = InMemoryIptvStore();
  final now = DateTime.now().toUtc();
  await store.saveSource(
    Source(
      id: 'w',
      kind: SourceKind.m3uUrl,
      name: 'World sampler',
      location: 'https://demo.example.test/world.m3u',
      lastSuccess: now,
    ),
  );
  await store.saveSource(
    Source(
      id: 'r',
      kind: SourceKind.m3uUrl,
      name: 'Regional extras',
      location: 'https://demo.example.test/regional.m3u',
      lastSuccess: now.subtract(const Duration(hours: 3)),
    ),
  );
  const names = [
    'Aurora News',
    'Beacon Sports',
    'Cinema Lumen',
    'Driftwood Kids',
    'Ember Music',
    'Fjord Weather',
    'Granite Business',
    'Harbour Info',
    'Iris Movies',
    'Juniper Comedy',
    'Kestrel Docs',
    'Lagoon Travel',
    'Meridian 24',
    'Nimbus Science',
    'Orchard Food',
    'Pinnacle Sport 2',
    'Quartz Classics',
    'Riverbank TV',
    'Saffron Cooking',
    'Tidal Nature',
    'Umber Retro',
    'Vesper Drama',
    'Willow Family',
    'Xenon Tech',
    'Yarrow Faith',
    'Zephyr Outdoors',
    'Atlas Headlines',
    'Basalt Racing',
    'Cobalt Cartoons',
    'Dune Westerns',
    'Echo Radio Live',
    'Falcon Football',
  ];
  const groups = [
    'News',
    'Sports',
    'Movies',
    'Kids;Animation',
    'Music',
    'Weather',
    'Business',
    'News',
    'Movies',
    'Comedy',
    'Documentary',
    'Travel',
    'News',
    'Science',
    'Cooking',
    'Sports',
    'Classic',
    'General',
    'Cooking',
    'Documentary',
    'Classic',
    'Entertainment',
    'Family',
    'Science',
    'Religious',
    'Outdoor',
    'News',
    'Sports',
    'Kids;Animation',
    'Movies',
    'Music',
    'Sports',
  ];
  const countries = [
    'GB',
    'US',
    'FR',
    'IN',
    'DE',
    'ES',
    'CA',
    'AU',
    'BR',
    'IT',
    'JP',
    'MX',
  ];
  const langs = [
    'English',
    'English',
    'French',
    'Hindi',
    'German',
    'Spanish',
    'English',
    'English',
    'Portuguese',
    'Italian',
    'Japanese',
    'Spanish',
  ];
  const quality = ['fhd', 'hd', null, 'sd', 'uhd', 'hd'];
  await store.replaceChannels('w', [
    for (var i = 0; i < names.length; i++)
      StoredChannel(
        key: 'w:$i',
        sourceId: 'w',
        name: i % 9 == 4 ? '${names[i]} [Geo-blocked]' : names[i],
        url: 'https://demo.example.test/w/$i.m3u8',
        group: groups[i],
        country: countries[i % countries.length],
        languages: i % 5 == 3 ? const [] : [langs[i % langs.length]],
        quality: quality[i % quality.length],
        number: i + 1,
        ttfbMs: 120 + (i * 37) % 900,
        dead: i % 8 == 5,
      ),
  ]);
  const regional = [
    'Coastline Local',
    'Highland Channel',
    'Metro City News',
    'Valley Sport',
    'Prairie Movies',
    'Delta Music',
    'Summit Kids',
  ];
  const regionalGroups = [
    'General',
    'General',
    'News',
    'Sports',
    'Movies',
    'Music',
    'Kids',
  ];
  await store.replaceChannels('r', [
    for (var i = 0; i < regional.length; i++)
      StoredChannel(
        key: 'r:$i',
        sourceId: 'r',
        name: regional[i],
        url: 'https://demo.example.test/r/$i.m3u8',
        group: regionalGroups[i],
        country: i.isEven ? 'US' : 'CA',
        languages: const ['English'],
        quality: i.isEven ? 'hd' : null,
        ttfbMs: 300 + i * 50,
      ),
  ]);
  return IptvService(store: store, http: _NoHttp());
}
