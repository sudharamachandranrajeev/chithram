// The phone views at four sizes: a small phone, the owner's phone, a phone in
// landscape (still the phone shell) and a tablet. Every view must lay out
// without overflow, meet the 48 dp tap-target guideline and label its taps.
import 'dart:convert';

import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/livetv/add_playlist.dart';
import 'package:chithram/src/features/livetv/iptv_service.dart';
import 'package:chithram/src/features/livetv/suggestions.dart';
import 'package:chithram/src/features/receive/phone/phone_receive_page.dart';
import 'package:chithram/src/features/torrents/phone/phone_torrent_files.dart';
import 'package:chithram/src/features/torrents/torrent_files_page.dart';
import 'package:chithram/src/features/youtube/youtube_service.dart';
import 'package:chithram/src/ui/common/app.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/tv/keyboard.dart';
import 'package:chithram/src/ui/phone/phone_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:innertube/innertube.dart' as yt;
import 'package:iptv/iptv.dart';
import 'package:torrent/torrent.dart';

const sizes = {
  '360x640': Size(360, 640),
  '421x927': Size(421, 927),
  '927x421 landscape': Size(927, 421),
  '800x1280 tablet': Size(800, 1280),
};

class _Browse extends yt.InnertubeBrowse {
  final queries = <String>[];

  @override
  Future<yt.Page<yt.VideoItem>> search(
    String query, {
    String? continuation,
    String params = yt.SearchFilter.videos,
  }) async {
    queries.add(query);
    return yt.Page([
      for (var i = 0; i < 3; i++)
        yt.VideoItem(
          videoId: 'video$i'.padRight(11, '0'),
          title: 'Result $i of $query, with a title long enough to wrap onto a second line',
          author: 'Chan',
          duration: const Duration(minutes: 3, seconds: 5),
        ),
    ], null);
  }
}

class _Http implements IptvHttp {
  final requests = <Uri>[];

  @override
  Future<IptvResponse> open(Uri uri,
      {Map<String, String> headers = const {}, Duration timeout = const Duration(seconds: 15)}) async {
    requests.add(uri);
    return IptvResponse(
        status: 200,
        headers: const {},
        body: Stream.value(utf8.encode('#EXTM3U\n#EXTINF:-1 group-title="News",Alpha News\nhttp://a.test/a\n')),
        ttfb: Duration.zero);
  }
}

Future<IptvService> _iptv({_Http? http, bool sources = true}) async {
  final store = InMemoryIptvStore();
  if (sources) {
    await store.saveSource(Source(id: 's', kind: SourceKind.m3uUrl, name: 'My list', location: 'http://a.test/s.m3u'));
    await store.replaceChannels('s', [
      for (final (i, n) in ['Alpha News', 'Beta News', 'Gamma Sport'].indexed)
        StoredChannel(
          key: 's/$i',
          sourceId: 's',
          name: n,
          group: n.endsWith('Sport') ? 'Sport' : 'News',
          url: 'http://a.test/$i',
        ),
    ]);
  }
  return IptvService(store: store, http: http);
}

Future<void> _pump(WidgetTester t, Size size, AppServices services) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ChithramApp(services: services, formFactor: FormFactor.phone));
  await t.pumpAndSettle();
  expect(find.byType(PhoneShell), findsOneWidget);
}

Future<void> _open(WidgetTester t, String tab) async {
  await t.tap(find.byKey(ValueKey('nav-$tab')));
  await t.pumpAndSettle();
}

Future<void> _guidelines(WidgetTester t) async {
  await expectLater(t, meetsGuideline(androidTapTargetGuideline));
  await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
}

void main() {
  for (final MapEntry(key: name, value: size) in sizes.entries) {
    group(name, () {
      testWidgets('YouTube: IME search bar, 16:9 cards, no on-screen keyboard', (t) async {
        final semantics = t.ensureSemantics();
        final browse = _Browse();
        await _pump(t, size, AppServices.memory(youtube: YouTubeService(browse: browse)));
        await _open(t, 'youtube');
        expect(find.byType(OnScreenKeyboard), findsNothing);
        expect(find.text('Send from phone'), findsNothing);
        final field = find.byKey(const ValueKey('search-field'));
        expect(field, findsOneWidget);
        expect(t.getTopLeft(field).dy, lessThan(200), reason: 'the search bar is at the top');
        await _guidelines(t);

        await t.enterText(field, 'cats');
        await t.testTextInput.receiveAction(TextInputAction.search);
        await t.pumpAndSettle();
        expect(browse.queries, ['cats']);
        final card = find.byKey(ValueKey('yt-result-${'video0'.padRight(11, '0')}'));
        expect(card, findsOneWidget);
        final thumb = find.descendant(of: card, matching: find.byType(AspectRatio));
        expect(t.getSize(thumb).aspectRatio, closeTo(16 / 9, 0.01));
        if (size.width < 600) {
          expect(t.getSize(card).width, greaterThan(size.width - 40), reason: 'full width on a phone');
        }
        await _guidelines(t);
        semantics.dispose();
      });

      testWidgets('Search: IME bar, channels and YouTube in sections, Open link', (t) async {
        final semantics = t.ensureSemantics();
        await _pump(
          t,
          size,
          AppServices.memory(youtube: YouTubeService(browse: _Browse()), iptv: await _iptv()),
        );
        await _open(t, 'search');
        expect(find.byKey(const ValueKey('search-open-link')), findsOneWidget);
        await _guidelines(t);
        await t.enterText(find.byKey(const ValueKey('search-field')), 'news');
        await t.tap(find.byKey(const ValueKey('search-go')));
        await t.pumpAndSettle();
        expect(find.text('Live TV channels'), findsOneWidget);
        expect(find.byKey(const ValueKey('search-channel-0')), findsOneWidget);
        final page = find.byKey(const PageStorageKey<String>('phone-search-scroll'));
        await t.scrollUntilVisible(
          find.descendant(of: page, matching: find.text('YouTube')),
          200,
          scrollable: find.descendant(of: page, matching: find.byType(Scrollable)),
        );
        await t.pumpAndSettle();
        await _guidelines(t);
        semantics.dispose();
      });

      testWidgets('Live TV: sources, sticky group chips, channels', (t) async {
        final semantics = t.ensureSemantics();
        await _pump(t, size, AppServices.memory(iptv: await _iptv()));
        await _open(t, 'liveTv');
        expect(find.text('My list'), findsOneWidget);
        expect(find.text('Alpha News'), findsOneWidget);
        await _guidelines(t);

        // Choosing a group filters the channel list.
        await t.ensureVisible(find.text('Sport (1)'));
        await t.pumpAndSettle();
        await t.tap(find.text('Sport (1)'));
        await t.pumpAndSettle();
        expect(find.text('Alpha News'), findsNothing);
        expect(find.text('Gamma Sport'), findsOneWidget);
        await _guidelines(t);
        await t.ensureVisible(find.text('All (3)'));
        await t.pumpAndSettle();
        await t.tap(find.text('All (3)'));
        await t.pumpAndSettle();
        expect(find.text('Alpha News'), findsOneWidget);
        semantics.dispose();
      });

      testWidgets('Live TV: no sources offers to add one, downloads nothing', (t) async {
        final semantics = t.ensureSemantics();
        final http = _Http();
        await _pump(t, size, AppServices.memory(iptv: await _iptv(http: http, sources: false)));
        await _open(t, 'liveTv');
        expect(find.byKey(LiveTvKeys.addPlaylist), findsOneWidget);
        expect(find.byKey(LiveTvKeys.suggestion(CatalogueSuggestion.values.first)), findsOneWidget);
        expect(http.requests, isEmpty);
        await _guidelines(t);
        semantics.dispose();
      });

      testWidgets('Torrents: IME magnet field, rejects a non-magnet, no Send from phone', (t) async {
        final semantics = t.ensureSemantics();
        await _pump(t, size, AppServices.memory());
        await _open(t, 'torrents');
        expect(find.byKey(const ValueKey('torrent-magnet-field')), findsOneWidget);
        expect(find.text('Send from phone'), findsNothing);
        await _guidelines(t);
        await t.enterText(find.byKey(const ValueKey('torrent-magnet-field')), 'https://example.test');
        await t.tap(find.byKey(const ValueKey('torrent-magnet-add')));
        await t.pump();
        expect(find.text('That is not a magnet link'), findsOneWidget);
        semantics.dispose();
      });

      testWidgets('Torrent files: list tiles', (t) async {
        final semantics = t.ensureSemantics();
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        const info = TorrentInfo(id: 1, name: 'Some torrent', files: [
          TorrentFile(index: 0, path: 'movie.mkv', length: 700000000, streamable: true),
          TorrentFile(index: 1, path: 'readme.txt', length: 1200, streamable: false),
        ]);
        final played = <int>[];
        final services = AppServices.memory();
        await t.pumpWidget(MaterialApp(
          theme: buildChithramTheme(form: FormFactor.phone),
          home: FormScope(
            form: FormFactor.phone,
            child: AppServicesScope(
              services: services,
              child: PhoneTorrentFiles(info: info, service: services.torrents, onPlay: (f) => played.add(f.index)),
            ),
          ),
        ));
        await t.pumpAndSettle();
        expect(find.byKey(TorrentKeys.file(0)), findsOneWidget);
        await _guidelines(t);
        await t.tap(find.byKey(TorrentKeys.file(0)));
        expect(played, [0]);
        semantics.dispose();
      });

      testWidgets('Settings: list tiles, no Send from phone', (t) async {
        final semantics = t.ensureSemantics();
        await _pump(t, size, AppServices.memory());
        await t.tap(find.byKey(const ValueKey('nav-settings')));
        await t.pumpAndSettle();
        expect(find.textContaining('Chithram ships no sources'), findsOneWidget);
        expect(find.text('Torrent network'), findsOneWidget);
        expect(find.text('Send from phone'), findsNothing);
        expect(find.byType(ListTile), findsWidgets);
        await _guidelines(t);
        semantics.dispose();
      });

      testWidgets('Receive: status, no overflow', (t) async {
        final semantics = t.ensureSemantics();
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final services = AppServices.memory();
        await t.pumpWidget(MaterialApp(
          theme: buildChithramTheme(form: FormFactor.phone),
          home: FormScope(
            form: FormFactor.phone,
            child: AppServicesScope(services: services, child: PhoneReceivePage(service: services.receive)),
          ),
        ));
        await t.pumpAndSettle();
        expect(find.text('Starting...'), findsOneWidget);
        await _guidelines(t);
        semantics.dispose();
      });
    });
  }
}
