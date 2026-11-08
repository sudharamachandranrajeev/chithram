import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/youtube/feed/youtube_feed.dart';
import 'package:chithram/src/features/youtube/home/youtube_home.dart';
import 'package:chithram/src/features/youtube/home/youtube_home_keys.dart';
import 'package:chithram/src/features/youtube/youtube_fixture.dart';
import 'package:chithram/src/features/youtube/youtube_service.dart';
import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/tv/focus_card.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:innertube/innertube.dart' hide Page;
import 'package:innertube/innertube.dart' as yt show Page;

/// Renders the YouTube home (loaded and loading) and its results on each
/// form factor to PNG files, with the real fonts. Runs only when
/// CHITHRAM_SHOTS names an output folder:
/// `CHITHRAM_SHOTS=/tmp/shots flutter test test/youtube/youtube_shots_test.dart`.
///
/// Everything shown is made up, and every thumbnail is a generated gradient
/// (the image client below never touches the network).
void main() {
  final out = Platform.environment['CHITHRAM_SHOTS'];

  Future<void> loadFonts() async {
    final poppins = FontLoader('Poppins');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      poppins.addFont(Future.value(ByteData.sublistView(File('assets/fonts/Poppins-$w.ttf').readAsBytesSync())));
    }
    await poppins.load();
    final root = Platform.environment['FLUTTER_ROOT'] ?? '';
    final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
      await l.load();
    }
  }

  testWidgets('youtube screenshots', skip: out == null, (t) async {
    await t.runAsync(loadFonts);
    debugDisableShadows = false;
    final art = (await t.runAsync(_PlaceholderArt.make))!;
    debugNetworkImageHttpClientProvider = () => _ArtClient(art);
    final key = GlobalKey();

    Future<void> settle([int rounds = 14]) async {
      for (var i = 0; i < rounds; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await t.pump(const Duration(milliseconds: 250));
      }
    }

    Future<void> shot(String name) async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await t.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: t.view.devicePixelRatio);
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File('$out/$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    Future<void> show(FormFactor form, FeedState state, String tag) async {
      final focus = SectionFocus();
      await t.pumpWidget(
        RepaintBoundary(
          key: key,
          child: AppServicesScope(
            key: ValueKey(tag),
            services: AppServices.memory(youtube: YouTubeService(browse: _DemoBrowse()), feed: _ShotFeed(state)),
            child: FormScope(
              form: form,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: buildChithramTheme(form: form),
                home: Scaffold(body: YouTubeHome(focus: focus)),
              ),
            ),
          ),
        ),
      );
    }

    for (final (form, size, ratio) in [
      (FormFactor.desktop, const Size(1440, 900), 1.0),
      (FormFactor.phone, const Size(720, 1600), 2.0),
      (FormFactor.tv, const Size(1920, 1080), 1.0),
    ]) {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = ratio;
      final tag = form.name;

      await show(form, const FeedState(loading: true), '$tag-loading');
      await t.pump(const Duration(milliseconds: 600));
      await shot('$tag-home-loading');

      await show(form, _demoFeed(), '$tag-home');
      await settle(24);
      await shot('$tag-home');

      if (form == FormFactor.tv) {
        await t.tap(find.byKey(YouTubeHomeKeys.searchBar));
        await settle(4);
        for (final c in 'rain'.split('')) {
          await t.tap(find.byKey(ValueKey('key-$c')));
          await t.pump();
        }
        await t.tap(find.byKey(const ValueKey('search-go')));
      } else {
        await t.enterText(find.byKey(YouTubeHomeKeys.searchField), 'rain');
        await t.testTextInput.receiveAction(TextInputAction.search);
      }
      await settle(24);
      await shot('$tag-results');
    }

    await t.pumpWidget(const SizedBox());
    t.view.reset();
    debugDisableShadows = true;
    debugNetworkImageHttpClientProvider = null;
  });
}

/// A feed fixed at one state: no disk, no network.
class _ShotFeed extends YouTubeFeed {
  _ShotFeed(FeedState state) : _state = ValueNotifier(state), super(youtube: YouTubeService(browse: FixtureBrowse('')));

  final ValueNotifier<FeedState> _state;

  @override
  ValueListenable<FeedState> get state => _state;

  @override
  Future<void> open() async {}

  @override
  Future<void> refresh({bool force = false}) async {}
}

const _titles = {
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
  ],
  'sports': [
    'Last-minute winner: full replay',
    'Training camp, behind the scenes',
    'Top ten saves this season',
    'Marathon finish line moments',
    'Cricket: the over that changed it',
    'Skate park session',
  ],
  'news': [
    'Morning briefing in five minutes',
    'Markets explained: the week ahead',
    'Inside the new science museum',
    'Local election, what to know',
    'Climate report: coastal towns',
    'Weekend headlines',
  ],
};

const _authors = {'music': 'Sample Music', 'live': 'Example Live', 'sports': 'Demo Sports', 'news': 'Sample News'};

List<VideoItem> _videos(String topic, {List<String>? titles}) {
  final list = titles ?? _titles[topic]!;
  return [
    for (var i = 0; i < list.length; i++)
      VideoItem(
        videoId: '$topic${'$i'.padLeft(11 - topic.length, 'x')}',
        title: list[i],
        author: _authors[topic] ?? 'Rain Channel',
        duration: topic == 'live' ? null : Duration(minutes: 4 + i * 7, seconds: 12),
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

FeedState _demoFeed() {
  final music = _videos('music');
  final cont = _videos('news').take(4).toList();
  return FeedState(
    hero: music.take(5).toList(),
    rails: [
      FeedRail('continue', 'Continue watching', cont, progress: {
        for (final (i, v) in cont.indexed) v.videoId: 0.2 + 0.18 * i,
      }),
      FeedRail('popular-music', 'Popular music', music),
      FeedRail('popular-live', 'Live now', _videos('live')),
      FeedRail('popular-sports', 'Sports', _videos('sports')),
      FeedRail('popular-news', 'News', _videos('news')),
    ],
  );
}

/// Made-up search results.
class _DemoBrowse extends InnertubeBrowse {
  @override
  Future<yt.Page<VideoItem>> search(String query, {String? continuation, String params = SearchFilter.videos}) async =>
      yt.Page(
        _videos('rain', titles: [
          for (final t in [
            'Rain on a tin roof, eight hours',
            'Monsoon walk through the old town',
            'Why it rains more on the coast',
            'Rainy cafe jazz',
            'Thunderstorm timelapse over the plains',
            'Cooking on a rainy day',
            'The rain gauge, explained',
            'Night rain in the forest',
            'Umbrella repair, start to finish',
            'Raindrops in slow motion',
            'A rainy train journey',
            'Rain sounds for focus',
          ])
            t,
        ]),
        null,
      );

  @override
  Future<List<String>> suggest(String prefix) async => const [];
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
      c.drawRect(r, Paint()..shader = ui.Gradient.linear(r.topLeft, r.bottomRight, p));
      c.drawCircle(const Offset(470, 120), 70, Paint()..color = const Color(0x33FFFFFF));
      c.drawRect(const Rect.fromLTWH(0, 260, 640, 100), Paint()..color = const Color(0x44000000));
      final img = await rec.endRecording().toImage(640, 360);
      list.add((await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
    }
    return _PlaceholderArt(list);
  }
}

class _ArtClient implements HttpClient {
  _ArtClient(this.art);
  final _PlaceholderArt art;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _ArtRequest(art.variants[url.toString().hashCode.abs() % art.variants.length]);

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
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
