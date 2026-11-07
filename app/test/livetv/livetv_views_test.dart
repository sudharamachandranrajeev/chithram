// Filter, sort and favourite flows on each form: desktop (mouse, popovers),
// phone (chips, bottom sheets) and TV (D-pad pickers).
import 'package:chithram/src/core/prefs.dart';
import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/livetv/channel_filter.dart';
import 'package:chithram/src/features/livetv/iptv_service.dart';
import 'package:chithram/src/features/livetv/livetv_library.dart';
import 'package:chithram/src/features/livetv/livetv_page.dart';
import 'package:chithram/src/features/livetv/livetv_widgets.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/tv/focus_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv/iptv.dart';

Future<IptvService> _seeded() async {
  final store = InMemoryIptvStore();
  await store.saveSource(
    Source(
      id: 's',
      kind: SourceKind.m3uUrl,
      name: 'World',
      location: 'http://a.test/w.m3u',
    ),
  );
  await store.saveSource(
    Source(
      id: 't',
      kind: SourceKind.m3uUrl,
      name: 'Extra',
      location: 'http://a.test/x.m3u',
    ),
  );
  StoredChannel ch(
    String key,
    String name,
    String group,
    String country,
    String lang, {
    String src = 's',
  }) => StoredChannel(
    key: key,
    sourceId: src,
    name: name,
    url: 'http://c.test/$key.m3u8',
    group: group,
    country: country,
    languages: [lang],
  );
  await store.replaceChannels('s', [
    ch('s:1', 'Alpha News', 'News', 'GB', 'English'),
    ch('s:2', 'Bravo Sport', 'Sports', 'GB', 'English'),
    ch('s:3', 'Charlie Info', 'News', 'FR', 'French'),
    ch('s:4', 'Delta Kids', 'Kids', 'US', 'English'),
  ]);
  await store.replaceChannels('t', [
    ch('t:1', 'Echo Noticias', 'News', 'ES', 'Spanish', src: 't'),
  ]);
  return IptvService(store: store, http: _NoHttp());
}

class _NoHttp implements IptvHttp {
  @override
  Future<IptvResponse> open(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 15),
  }) => throw StateError('no network in tests');
}

Future<Prefs> _pump(
  WidgetTester t,
  Size size, {
  FormFactor? form,
  Prefs? prefs,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final focus = SectionFocus();
  addTearDown(focus.dispose);
  final p = prefs ?? Prefs.memory();
  Widget page = Scaffold(body: LiveTvPage(focus: focus));
  if (form != null) page = FormScope(form: form, child: page);
  await t.pumpWidget(
    AppServicesScope(
      services: AppServices.memory(iptv: await _seeded(), prefs: p),
      child: MaterialApp(home: page),
    ),
  );
  await t.pumpAndSettle();
  return p;
}

/// Scrolls [f] into view (chip rows scroll sideways), then taps it.
Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  group('desktop', () {
    const size = Size(1440, 900);

    testWidgets('facet popover, search, sort, view toggle and favourites', (
      t,
    ) async {
      final prefs = await _pump(t, size, form: FormFactor.desktop);
      expect(find.byKey(LiveTvFilterKeys.search), findsOneWidget);
      expect(find.text('Alpha News'), findsOneWidget);
      expect(find.text('Echo Noticias'), findsOneWidget);

      // Country popover: pick France, then close it.
      await _tap(t, find.byKey(LiveTvFilterKeys.facet(ChannelFacet.country)));
      expect(
        find.byKey(LiveTvFilterKeys.option(ChannelFacet.country, 'GB')),
        findsOneWidget,
      );
      await _tap(
        t,
        find.byKey(LiveTvFilterKeys.option(ChannelFacet.country, 'FR')),
      );
      await t.tapAt(const Offset(1400, 880));
      await t.pumpAndSettle();
      expect(find.text('Country: France'), findsOneWidget);
      expect(find.text('Charlie Info'), findsOneWidget);
      expect(find.text('Alpha News'), findsNothing);
      expect(find.text('1 of 5'), findsOneWidget);

      // Clear brings everything back; search narrows by any word.
      await _tap(t, find.byKey(LiveTvFilterKeys.clear));
      expect(find.text('Alpha News'), findsOneWidget);
      await t.enterText(find.byKey(LiveTvFilterKeys.search), 'spanish');
      await t.pumpAndSettle();
      expect(find.text('Echo Noticias'), findsOneWidget);
      expect(find.text('Alpha News'), findsNothing);
      await t.enterText(find.byKey(LiveTvFilterKeys.search), '');
      await t.pumpAndSettle();

      // Sort Z-A puts Echo first.
      await _tap(t, find.byKey(LiveTvFilterKeys.sort));
      await _tap(
        t,
        find.byKey(LiveTvFilterKeys.sortOption(ChannelSort.nameZa)),
      );
      expect(
        t.getTopLeft(find.text('Echo Noticias')).dy,
        lessThan(t.getTopLeft(find.text('Alpha News')).dy),
      );

      // List view is remembered.
      await _tap(t, find.byTooltip('List'));
      expect(prefs.getBool(LiveTvLibrary.gridKey, fallback: true), isFalse);
      expect(find.text('CHANNEL'), findsOneWidget);

      // A star adds a favourite and a Favourites row appears.
      await _tap(t, find.byKey(LiveTvFilterKeys.favourite('s:3')));
      expect(LiveTvLibrary(prefs).favourites, ['s:3']);
      expect(find.text('Favourites'), findsWidgets);
      expect(find.text('Charlie Info'), findsNWidgets(2));
    });

    testWidgets('sources popover lists sources with refresh and remove', (
      t,
    ) async {
      await _pump(t, size, form: FormFactor.desktop);
      await _tap(t, find.byKey(LiveTvFilterKeys.sources));
      expect(find.byKey(const ValueKey('livetv-source-s')), findsOneWidget);
      expect(find.byKey(const ValueKey('livetv-remove-t')), findsOneWidget);
      // Tapping a source filters to it.
      await _tap(t, find.byKey(const ValueKey('livetv-source-t')));
      await t.tapAt(const Offset(20, 880));
      await t.pumpAndSettle();
      expect(find.text('Echo Noticias'), findsOneWidget);
      expect(find.text('Alpha News'), findsNothing);
    });
  });

  group('phone', () {
    const size = Size(360, 800);

    testWidgets('language sheet, category chips, sort sheet and favourites', (
      t,
    ) async {
      final prefs = await _pump(t, size);
      expect(find.text('Alpha News'), findsOneWidget);

      await _tap(t, find.byKey(LiveTvFilterKeys.facet(ChannelFacet.language)));
      await _tap(
        t,
        find.byKey(LiveTvFilterKeys.option(ChannelFacet.language, 'French')),
      );
      await _tap(t, find.text('Done'));
      expect(find.text('Charlie Info'), findsOneWidget);
      expect(find.text('Alpha News'), findsNothing);

      await _tap(t, find.byKey(LiveTvFilterKeys.clear));
      await _tap(t, find.text('Kids (1)'));
      expect(find.text('Delta Kids'), findsOneWidget);
      expect(find.text('Alpha News'), findsNothing);
      await _tap(t, find.byKey(LiveTvFilterKeys.allCategories));

      await _tap(t, find.byKey(LiveTvFilterKeys.sort));
      await _tap(
        t,
        find.byKey(LiveTvFilterKeys.sortOption(ChannelSort.nameZa)),
      );
      expect(
        t.getTopLeft(find.text('Echo Noticias')).dy,
        lessThan(t.getTopLeft(find.text('Delta Kids')).dy),
      );

      // Long press marks a favourite, like the star.
      await t.longPress(find.text('Bravo Sport'));
      await t.pumpAndSettle();
      expect(LiveTvLibrary(prefs).favourites, ['s:2']);
    });
  });

  group('tv', () {
    const size = Size(1920, 1080);

    testWidgets('pickers work with the D-pad and filters clear', (t) async {
      await _pump(t, size);
      expect(find.text('Alpha News'), findsOneWidget);

      // Open the country picker; the first (largest) option has focus.
      await _tap(t, find.byKey(LiveTvFilterKeys.facet(ChannelFacet.country)));
      expect(
        find.byKey(LiveTvFilterKeys.option(ChannelFacet.country, 'GB')),
        findsOneWidget,
      );
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.text('Country: United Kingdom'), findsOneWidget);
      expect(find.text('Alpha News'), findsOneWidget);
      expect(find.text('Bravo Sport'), findsOneWidget);
      expect(find.text('Charlie Info'), findsNothing);

      // Sort picker.
      await _tap(t, find.byKey(LiveTvFilterKeys.sort));
      await _tap(
        t,
        find.byKey(LiveTvFilterKeys.sortOption(ChannelSort.nameZa)),
      );
      expect(
        t.getTopLeft(find.text('Bravo Sport')).dy,
        lessThan(t.getTopLeft(find.text('Alpha News')).dy),
      );

      await _tap(t, find.byKey(LiveTvFilterKeys.clear));
      expect(find.text('Charlie Info'), findsOneWidget);
    });

    testWidgets('a star marks a favourite and the row appears', (t) async {
      final prefs = await _pump(t, size);
      await _tap(t, find.byKey(LiveTvFilterKeys.favourite('s:4')));
      expect(LiveTvLibrary(prefs).favourites, ['s:4']);
      expect(find.text('Favourites'), findsWidgets);
    });
  });
}
