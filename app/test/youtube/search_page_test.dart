import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/youtube/youtube_service.dart';
import 'package:chithram/src/features/livetv/iptv_service.dart';
import 'package:chithram/src/ui/focus_card.dart';
import 'package:chithram/src/ui/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:innertube/innertube.dart' as yt;
import 'package:iptv/iptv.dart' hide HttpStatusException;

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
          title: 'Result $i of $query',
          author: 'Chan',
        ),
    ], null);
  }
}

Future<(AppServices, _Browse)> _services() async {
  final store = InMemoryIptvStore();
  await store.saveSource(
    Source(
      id: 's',
      kind: SourceKind.m3uUrl,
      name: 'S',
      location: 'http://example.test/a.m3u',
    ),
  );
  await store.replaceChannels('s', [
    StoredChannel(
      key: 's/cat',
      sourceId: 's',
      name: 'Cat News',
      url: 'http://example.test/cat',
    ),
    StoredChannel(
      key: 's/dog',
      sourceId: 's',
      name: 'Dog TV',
      url: 'http://example.test/dog',
    ),
  ]);
  final browse = _Browse();
  return (
    AppServices.memory(
      youtube: YouTubeService(browse: browse),
      iptv: IptvService(store: store),
    ),
    browse,
  );
}

Future<void> _pump(
  WidgetTester t,
  AppServices services, {
  required bool youtubeOnly,
}) async {
  t.view.physicalSize = const Size(1920, 1080);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final focus = SectionFocus();
  addTearDown(focus.dispose);
  await t.pumpWidget(
    MaterialApp(
      home: AppServicesScope(
        services: services,
        child: Scaffold(
          body: SearchPage(focus: focus, youtubeOnly: youtubeOnly),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _type(WidgetTester t, String text) async {
  for (final c in text.split('')) {
    await t.tap(find.byKey(ValueKey('key-$c')));
    await t.pump();
  }
}

void main() {
  testWidgets(
    'nothing is searched while typing; Search shows videos and channels',
    (t) async {
      final (services, browse) = await _services();
      await _pump(t, services, youtubeOnly: false);
      await _type(t, 'cat');
      await t.pumpAndSettle();
      expect(browse.queries, isEmpty);

      await t.tap(find.byKey(const ValueKey('search-go')));
      await t.pumpAndSettle();
      expect(browse.queries, ['cat']);
      expect(find.text('Live TV channels'), findsOneWidget);
      expect(find.text('Cat News'), findsOneWidget);
      expect(find.text('Dog TV'), findsNothing);
      await t.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await t.pumpAndSettle();
      expect(find.text('Result 0 of cat'), findsOneWidget);
      expect(find.byKey(const ValueKey('search-open-link')), findsOneWidget);
    },
  );

  testWidgets('the YouTube section has no channel rail and no Open link', (
    t,
  ) async {
    final (services, browse) = await _services();
    await _pump(t, services, youtubeOnly: true);
    await _type(t, 'cat');
    await t.tap(find.byKey(const ValueKey('search-go')));
    await t.pumpAndSettle();
    expect(browse.queries, ['cat']);
    expect(find.text('Live TV channels'), findsNothing);
    expect(find.byKey(const ValueKey('search-open-link')), findsNothing);
    expect(find.text('YouTube'), findsOneWidget);
  });

  testWidgets('a failing search shows the message', (t) async {
    final services = AppServices.memory(
      youtube: YouTubeService(browse: _Failing()),
    );
    await _pump(t, services, youtubeOnly: true);
    await _type(t, 'x');
    await t.tap(find.byKey(const ValueKey('search-go')));
    await t.pumpAndSettle();
    expect(find.text('www.youtube.com said 429'), findsOneWidget);
  });
}

class _Failing extends yt.InnertubeBrowse {
  @override
  Future<yt.Page<yt.VideoItem>> search(
    String query, {
    String? continuation,
    String params = yt.SearchFilter.videos,
  }) => Future.error(yt.HttpStatusException(429, 'www.youtube.com'));
}
