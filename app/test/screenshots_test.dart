import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/livetv/iptv_service.dart';
import 'package:chithram/src/features/torrents/home/popular_item.dart';
import 'package:chithram/src/features/torrents/home/popular_source.dart';
import 'package:chithram/src/features/torrents/home/torrent_home_feed.dart';
import 'package:chithram/src/features/youtube/feed/youtube_feed.dart';
import 'package:chithram/src/features/youtube/youtube_service.dart';
import 'package:chithram/src/ui/common/app.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:innertube/innertube.dart';
import 'package:iptv/iptv.dart' hide SecretStore;

/// Renders the main screens with the real fonts to PNG files, for checking
/// the look and for the README. Runs only when CHITHRAM_SHOTS names an output
/// folder: `CHITHRAM_SHOTS=/tmp/shots flutter test test/screenshots_test.dart`.
///
/// Everything shown is made up: video titles, channels, playlists and
/// torrents are invented, and every thumbnail is a generated gradient
/// (the image client below never touches the network).
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

  testWidgets('screenshots', skip: out == null, (tester) async {
    await tester.runAsync(loadFonts);
    debugDisableShadows = false;
    final art = (await tester.runAsync(_PlaceholderArt.make))!;
    debugNetworkImageHttpClientProvider = () => _ArtClient(art);
    final key = GlobalKey();
    var n = 0;

    Future<void> settle([int rounds = 14]) async {
      for (var i = 0; i < rounds; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    Future<void> shot(String name) async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(
          pixelRatio: tester.view.devicePixelRatio,
        );
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File('$out/${(++n).toString().padLeft(2, '0')}-$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    Future<AppServices> services() async {
      final youtube = YouTubeService(browse: _DemoBrowse());
      final iptv = IptvService(
        store: InMemoryIptvStore(),
        http: _DemoPlaylists(),
      );
      await tester.runAsync(
        () => iptv.addM3uUrl(
          name: 'Demo channels',
          url: 'https://demo.example.test/tv.m3u',
        ),
      );
      final now = DateTime.now();
      PopularItem item(
        String t,
        PopularKind k,
        int seeders,
        int gb10,
        int hoursAgo,
      ) => PopularItem(
        title: t,
        kind: k,
        sourceId: 'demo',
        sourceLabel: 'Demo indexer',
        seeders: seeders,
        leechers: seeders ~/ 6,
        sizeBytes: gb10 * 107374182,
        infoHash: (t.hashCode.abs().toRadixString(16) * 6)
            .padRight(40, 'a')
            .substring(0, 40),
        published: now.subtract(Duration(hours: hoursAgo)),
      );
      return AppServices.memory(
        youtube: youtube,
        feed: YouTubeFeed(youtube: youtube),
        iptv: iptv,
        torrentHome: TorrentHomeFeed(
          sources: FixturePopularSources([
            FixturePopularSource(
              id: 'demo',
              label: 'Demo indexer',
              films: [
                item(
                  'Lantern Harbour 2026 1080p WEB-DL',
                  PopularKind.film,
                  1840,
                  28,
                  5,
                ),
                item(
                  'The Quiet Orchard 2026 2160p',
                  PopularKind.film,
                  1210,
                  62,
                  9,
                ),
                item(
                  'Salt and Signal 2025 1080p BluRay',
                  PopularKind.film,
                  960,
                  41,
                  20,
                ),
                item('Midnight Ferry 2026 720p', PopularKind.film, 640, 14, 30),
                item(
                  'Paper Kingdoms 2025 1080p',
                  PopularKind.film,
                  420,
                  22,
                  70,
                ),
              ],
              tv: [
                item(
                  'Northern Lines S02E05 1080p',
                  PopularKind.tv,
                  2100,
                  21,
                  3,
                ),
                item(
                  'Copper Valley S01 Complete 1080p',
                  PopularKind.tv,
                  1500,
                  140,
                  40,
                ),
                item('Tidewater S03E01 720p', PopularKind.tv, 880, 9, 12),
                item('Little Observatory S01E08', PopularKind.tv, 530, 7, 26),
              ],
            ),
          ]),
          clock: () => now,
        ),
      );
    }

    Future<void> run(
      FormFactor form,
      Size size,
      double ratio,
      List<(String, String)> tabs,
      String tag,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = ratio;
      final s = await services();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: ChithramApp(key: ValueKey(tag), services: s, formFactor: form),
        ),
      );
      await settle(20);
      await shot('$tag-home');
      for (final (label, name) in tabs) {
        if (form == FormFactor.tv) {
          final order = [
            'Home',
            'Search',
            'Live TV',
            'Torrents',
            'YouTube',
            'Settings',
          ];
          // The rail is focused: Down moves one section at a time.
          final from = order.indexOf(_current);
          final to = order.indexOf(label);
          for (var i = 0; i < (to - from).abs(); i++) {
            await tester.sendKeyEvent(
              to > from
                  ? LogicalKeyboardKey.arrowDown
                  : LogicalKeyboardKey.arrowUp,
            );
            await tester.pump(const Duration(milliseconds: 120));
          }
          _current = label;
        } else {
          await tester.tap(find.text(label).last);
        }
        await settle(20);
        await shot('$tag-$name');
      }
    }

    final tabs = [('Live TV', 'livetv'), ('Torrents', 'torrents')];
    _current = 'Home';
    await run(FormFactor.tv, const Size(1920, 1080), 1, tabs, 'tv');
    await run(FormFactor.phone, const Size(1264, 2780), 3, [
      ('Live TV', 'livetv'),
      ('Torrents', 'torrents'),
    ], 'phone');
    await tester.pumpWidget(const SizedBox());
    tester.view.reset();
    debugDisableShadows = true;
    debugNetworkImageHttpClientProvider = null;
  });
}

String _current = 'Home';

/// Made-up videos. Each topic channel gets its own set, so no rail repeats.
class _DemoBrowse extends InnertubeBrowse {
  static const _titles = {
    'music': [
      'Evening Ragas, a one-hour mix',
      'Rooftop sessions: live in the city',
      'Lo-fi beats for long train rides',
      'Acoustic covers from the hills',
      'The story of a small-town band',
      'Piano for rainy afternoons',
      'Festival highlights, night two',
      'Studio diary: recording day',
    ],
    'live': [
      'Harbour cam: sunrise over the bay',
      'Mountain pass weather, live',
      'City lights livestream',
      'Wildlife waterhole camera',
      'Space launch countdown',
      'Night market walk, live',
      'Radio studio on air',
      'Storm watch from the coast',
    ],
    'sports': [
      'Last-minute winner: full replay',
      'Training camp, behind the scenes',
      'Top ten saves this season',
      'Marathon finish line moments',
      'Cricket: the over that changed it',
      'Skate park session',
      'Rowing across the strait',
      'Courtside: the final set',
    ],
    'news': [
      'Morning briefing in five minutes',
      'Markets explained: the week ahead',
      'Inside the new science museum',
      'Local election, what to know',
      'Climate report: coastal towns',
      'Weekend headlines',
      'A day with the harbour pilots',
      'Tech roundup: this week',
    ],
    'gaming': [
      'Speedrun record, start to finish',
      'Cosy farm game: first hours',
      'Puzzle platformer walkthrough',
      'Indie showcase highlights',
      'Retro console teardown',
      'Co-op night: we try again',
      'Level design, explained',
      'Strategy masterclass, part 3',
    ],
  };

  static const _channels = {
    'UC-9-kyTW8ZkZNDHQJ6FgpwQ': ('music', 'Sample Music'),
    'UC4R8DWoMoI7CAwX8_LjQHig': ('live', 'Example Live'),
    'UCEgdi0XIXXZ-qJOFPf4JSKw': ('sports', 'Demo Sports'),
    'UCYfdidRxbB8Qhf0Nx7ioOYw': ('news', 'Sample News'),
    'UCOpNcN46UbXVtpKMrmU4Abg': ('gaming', 'Example Games'),
  };

  @override
  Future<List<VideoItem>> channelHome(String channelId) async {
    final (topic, author) = _channels[channelId] ?? ('news', 'Sample News');
    final titles = _titles[topic]!;
    return [
      for (var i = 0; i < titles.length; i++)
        VideoItem(
          videoId: '$topic${'$i'.padLeft(11 - topic.length, 'x')}',
          title: titles[i],
          author: author,
          channelId: channelId,
          duration: topic == 'live'
              ? null
              : Duration(minutes: 4 + i * 7, seconds: 12),
          viewsText: '${(i + 2) * 38}K views',
          isLive: topic == 'live',
          thumbnails: [
            ThumbnailInfo(
              'https://i.ytimg.com/vi/$topic${'$i'.padLeft(11 - topic.length, 'x')}/hqdefault.jpg',
              width: 480,
              height: 360,
            ),
          ],
        ),
    ];
  }

  @override
  Future<List<VideoItem>> related(String videoId) async => const [];

  @override
  Future<List<String>> suggest(String prefix) async => const [];
}

/// A made-up playlist: invented channels, no logos.
class _DemoPlaylists implements IptvHttp {
  static const _m3u = '''#EXTM3U
#EXTINF:-1 group-title="News",Harbour News 24
http://demo.example.test/1.m3u8
#EXTINF:-1 group-title="News",Metro Report
http://demo.example.test/2.m3u8
#EXTINF:-1 group-title="News",World Briefing
http://demo.example.test/3.m3u8
#EXTINF:-1 group-title="Sport",Arena One
http://demo.example.test/4.m3u8
#EXTINF:-1 group-title="Sport",Coastline Cricket
http://demo.example.test/5.m3u8
#EXTINF:-1 group-title="Music",Sunrise Radio TV
http://demo.example.test/6.m3u8
#EXTINF:-1 group-title="Music",Evening Ragas
http://demo.example.test/7.m3u8
#EXTINF:-1 group-title="Kids",Little Lantern
http://demo.example.test/8.m3u8
#EXTINF:-1 group-title="Documentary",Wild Shores
http://demo.example.test/9.m3u8
#EXTINF:-1 group-title="Documentary",Deep Space Channel
http://demo.example.test/10.m3u8
''';

  @override
  Future<IptvResponse> open(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 15),
  }) async => IptvResponse(
    status: 200,
    headers: const {},
    body: Stream.value(utf8.encode(_m3u)),
    ttfb: Duration.zero,
  );
}

/// Generated gradient thumbnails, so no real artwork is ever fetched.
class _PlaceholderArt {
  _PlaceholderArt(this.variants);
  final List<Uint8List> variants;

  static const _palettes = [
    [Color(0xFF3A2A6B), Color(0xFFF5A300)],
    [Color(0xFF0F3D5E), Color(0xFF3CC4B2)],
    [Color(0xFF5B1F4A), Color(0xFFFF7A59)],
    [Color(0xFF1D3B2A), Color(0xFFB6E36B)],
    [Color(0xFF2B2F6B), Color(0xFF6FB1FF)],
    [Color(0xFF4A1C1C), Color(0xFFFFC857)],
  ];

  static Future<_PlaceholderArt> make() async {
    final list = <Uint8List>[];
    for (final p in _palettes) {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      const r = Rect.fromLTWH(0, 0, 640, 360);
      c.drawRect(
        r,
        Paint()..shader = ui.Gradient.linear(r.topLeft, r.bottomRight, p),
      );
      // A soft sun and a dark ground, so the frames read as scenes.
      c.drawCircle(
        const Offset(470, 120),
        70,
        Paint()..color = const Color(0x33FFFFFF),
      );
      c.drawRect(
        const Rect.fromLTWH(0, 260, 640, 100),
        Paint()..color = const Color(0x44000000),
      );
      final img = await rec.endRecording().toImage(640, 360);
      list.add(
        (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer
            .asUint8List(),
      );
    }
    return _PlaceholderArt(list);
  }
}

class _ArtClient implements HttpClient {
  _ArtClient(this.art);
  final _PlaceholderArt art;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _ArtRequest(
    art.variants[url.toString().hashCode.abs() % art.variants.length],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ArtRequest implements HttpClientRequest {
  _ArtRequest(this.bytes);
  final Uint8List bytes;

  @override
  final HttpHeaders headers = _Headers();

  @override
  Future<HttpClientResponse> close() async => _ArtResponse(bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Headers implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ArtResponse extends Stream<List<int>> implements HttpClientResponse {
  _ArtResponse(this.bytes);
  final Uint8List bytes;

  @override
  int get statusCode => 200;

  @override
  int get contentLength => bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
