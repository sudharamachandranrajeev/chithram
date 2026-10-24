import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/youtube/youtube_service.dart';
import 'package:chithram/src/features/livetv/iptv_service.dart';
import 'package:chithram/src/ui/tv/focus_card.dart';
import 'package:chithram/src/ui/common/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:innertube/innertube.dart' as yt;
import 'package:iptv/iptv.dart' hide HttpStatusException;

class _Browse extends yt.InnertubeBrowse {
  final queries = <String>[];
  final suggested = <String>[];

  @override
  Future<List<String>> suggest(String prefix) async {
    suggested.add(prefix);
    return ['$prefix videos', '$prefix live'];
  }

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
  Size size = const Size(1920, 1080),
  double dpr = 1,
}) async {
  t.view.physicalSize = size * dpr;
  t.view.devicePixelRatio = dpr;
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

/// Opens the keyboard from the search bar if it is closed, then types.
Future<void> _type(WidgetTester t, String text) async {
  if (find.byKey(const ValueKey('search-go')).evaluate().isEmpty) {
    await t.tap(find.byKey(const ValueKey('search-bar')));
    await t.pumpAndSettle();
  }
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

  testWidgets('the keyboard drops down from the search bar only when it is pressed', (t) async {
    final (services, _) = await _services();
    await _pump(t, services, youtubeOnly: true);
    expect(find.byKey(const ValueKey('key-a')), findsNothing);
    await t.tap(find.byKey(const ValueKey('search-bar')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('key-a')), findsOneWidget);
    // The panel sits under the bar and leaves the rest of the screen visible.
    final bar = t.getRect(find.byKey(const ValueKey('search-bar')));
    final keys = t.getRect(find.byKey(const ValueKey('key-q')));
    expect(keys.top, greaterThan(bar.bottom));
    expect(t.getRect(find.byKey(const ValueKey('search-go'))).bottom, lessThan(1080 * 0.75));

    await _type(t, 'ab');
    await t.tap(find.byKey(const ValueKey('key-mode')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('key-1')));
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.byKey(const ValueKey('search-query'))).data, 'ab1');

    // Back closes the panel and keeps the text.
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('key-a')), findsNothing);
    expect(t.widget<Text>(find.byKey(const ValueKey('search-query'))).data, 'ab1');
  });

  testWidgets('suggestions follow the typing; picking one searches it', (t) async {
    final (services, browse) = await _services();
    await _pump(t, services, youtubeOnly: true);
    await _type(t, 'ca');
    await t.pump(const Duration(milliseconds: 100));
    await _type(t, 't');
    await t.pumpAndSettle();
    expect(browse.suggested, ['cat'], reason: 'asked once, after the pause');
    expect(find.text('cat videos'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('suggestion-1')));
    await t.pumpAndSettle();
    expect(browse.queries, ['cat live']);
    expect(find.byKey(const ValueKey('key-a')), findsNothing);
    expect(find.text('Result 0 of cat live'), findsOneWidget);
  });

  testWidgets('suggestions sit under the keys, labelled by source', (t) async {
    final (services, _) = await _services();
    await _pump(t, services, youtubeOnly: false);
    await _type(t, 'cat');
    await t.pumpAndSettle();
    // YouTube's two, then the matching Live TV channel.
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text('Live TV'), findsOneWidget);
    expect(find.text('cat videos'), findsOneWidget);
    final channel = find.ancestor(of: find.text('Cat News'), matching: find.byKey(const ValueKey('suggestion-2')));
    expect(channel, findsOneWidget);
    final go = t.getRect(find.byKey(const ValueKey('search-go')));
    expect(t.getRect(find.byKey(const ValueKey('suggestion-0'))).top, greaterThan(go.bottom));
    expect(t.getRect(channel).top, greaterThan(t.getRect(find.byKey(const ValueKey('suggestion-0'))).bottom));

    // D-pad Down from the bottom row reaches the suggestions.
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    final focused = FocusManager.instance.primaryFocus!.rect;
    expect(focused.top, greaterThan(go.bottom), reason: 'focus is on a suggestion');
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('key-a')), findsNothing);
  });

  testWidgets('960x540 TV: keys about 32 high, panel and suggestions on screen', (t) async {
    final (services, _) = await _services();
    await _pump(t, services, youtubeOnly: false, size: const Size(960, 540), dpr: 2);
    await _type(t, 'cat');
    await t.pumpAndSettle();
    final bar = t.getRect(find.byKey(const ValueKey('search-bar')));
    final q = t.getRect(find.byKey(const ValueKey('key-q')));
    expect(q.top, greaterThan(bar.bottom));
    expect(q.height, inInclusiveRange(30, 34));
    final go = t.getRect(find.byKey(const ValueKey('search-go')));
    expect(go.right - q.left, lessThanOrEqualTo(520));
    for (final i in [0, 1, 2]) {
      final s = t.getRect(find.byKey(ValueKey('suggestion-$i')));
      expect(s.top, greaterThan(go.bottom));
      expect(s.bottom, lessThanOrEqualTo(540));
    }
    expect(find.text('Start typing for suggestions'), findsNothing);
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
