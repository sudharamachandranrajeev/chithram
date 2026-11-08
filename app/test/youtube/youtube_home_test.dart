// The YouTube home on each form factor: the chips switch what it shows, a
// search opens results, a loading feed shows the skeleton and a failed one
// offers Retry.
import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/youtube/feed/youtube_feed.dart';
import 'package:chithram/src/features/youtube/home/youtube_home.dart';
import 'package:chithram/src/features/youtube/home/youtube_home_keys.dart';
import 'package:chithram/src/features/youtube/home/youtube_topics.dart';
import 'package:chithram/src/features/youtube/youtube_service.dart';
import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/tv/focus_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:innertube/innertube.dart' as yt;

import '../desktop/static_feed.dart';
import '../phone/fixed_feed.dart';

const _sizes = {
  FormFactor.desktop: Size(1440, 900),
  FormFactor.phone: Size(412, 915),
  FormFactor.tv: Size(1920, 1080),
};

class _Browse extends yt.InnertubeBrowse {
  final queries = <String>[];

  @override
  Future<List<String>> suggest(String prefix) async => const [];

  @override
  Future<yt.Page<yt.VideoItem>> search(
    String query, {
    String? continuation,
    String params = yt.SearchFilter.videos,
  }) async {
    queries.add(query);
    return yt.Page([
      for (var i = 0; i < 3; i++)
        yt.VideoItem(videoId: 'video$i'.padRight(11, '0'), title: 'Result $i of $query', author: 'Chan'),
    ], null);
  }
}

/// A feed stuck in [FixedFeed]'s state that counts refreshes (Retry).
class _CountingFeed extends FixedFeed {
  _CountingFeed(super.state);

  int refreshes = 0;

  @override
  Future<void> refresh({bool force = false}) async => refreshes++;
}

Future<void> _pump(WidgetTester t, FormFactor form, {YouTubeFeed? feed, _Browse? browse, bool settle = true}) async {
  t.view.physicalSize = _sizes[form]!;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final focus = SectionFocus();
  addTearDown(focus.dispose);
  await t.pumpWidget(
    AppServicesScope(
      services: AppServices.memory(
        youtube: YouTubeService(browse: browse ?? _Browse()),
        feed: feed ?? StaticFeed(),
      ),
      child: FormScope(
        form: form,
        child: MaterialApp(
          theme: buildChithramTheme(form: form),
          home: Scaffold(body: YouTubeHome(focus: focus)),
        ),
      ),
    ),
  );
  if (settle) {
    await t.pumpAndSettle();
  } else {
    await t.pump();
  }
}

void main() {
  for (final form in FormFactor.values) {
    group(form.name, () {
      testWidgets('the chips switch the content', (t) async {
        await _pump(t, form);
        expect(find.byKey(YouTubeHomeKeys.topic('for-you')), findsOneWidget);
        expect(find.byKey(YouTubeHomeKeys.hero), findsOneWidget);
        // Continue watching shows because the feed has that rail.
        expect(find.byKey(YouTubeHomeKeys.chip('continue')), findsOneWidget);

        final music = find.byKey(YouTubeHomeKeys.chip('music'));
        // A phone's chip row scrolls sideways; Music may start past the edge.
        if (form == FormFactor.phone) {
          await t.scrollUntilVisible(
            music,
            100,
            scrollable: find.descendant(of: find.byType(TopicChipBar), matching: find.byType(Scrollable)),
          );
          // Built in the cache extent is not on screen: scroll it fully in.
          await t.ensureVisible(music);
          await t.pumpAndSettle();
        }
        await t.tap(music);
        await t.pumpAndSettle();
        expect(find.byKey(YouTubeHomeKeys.topic('music')), findsOneWidget);
        expect(find.byKey(YouTubeHomeKeys.topic('for-you')), findsNothing);
      });

      testWidgets('a search opens the results', (t) async {
        final browse = _Browse();
        await _pump(t, form, browse: browse);
        if (form == FormFactor.tv) {
          // OK on the bar opens the on-screen keyboard; its Search opens results.
          await t.tap(find.byKey(YouTubeHomeKeys.searchBar));
          await t.pumpAndSettle();
          for (final c in 'cats'.split('')) {
            await t.tap(find.byKey(ValueKey('key-$c')));
            await t.pump();
          }
          await t.tap(find.byKey(const ValueKey('search-go')));
        } else {
          await t.enterText(find.byKey(YouTubeHomeKeys.searchField), 'cats');
          await t.testTextInput.receiveAction(TextInputAction.search);
        }
        await t.pumpAndSettle();
        expect(browse.queries, ['cats']);
        expect(find.byKey(YouTubeHomeKeys.results), findsOneWidget);
        expect(find.text('Result 0 of cats'), findsOneWidget);

        // Back returns to the home, still on For you.
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(find.byKey(YouTubeHomeKeys.results), findsNothing);
        expect(find.byKey(YouTubeHomeKeys.topic('for-you')), findsOneWidget);
      });

      testWidgets('a loading feed shows the skeleton', (t) async {
        await _pump(t, form, feed: FixedFeed(const FeedState(loading: true)), settle: false);
        expect(find.byKey(YouTubeHomeKeys.skeleton), findsOneWidget);
        expect(find.byKey(YouTubeHomeKeys.hero), findsNothing);
        expect(find.byKey(YouTubeHomeKeys.error), findsNothing);
      });

      testWidgets('a failed feed offers Retry', (t) async {
        final feed = _CountingFeed(const FeedState(error: 'No connection'));
        await _pump(t, form, feed: feed);
        expect(find.byKey(YouTubeHomeKeys.error), findsOneWidget);
        expect(find.text('No connection'), findsOneWidget);
        await t.tap(find.byKey(YouTubeHomeKeys.retry));
        await t.pump();
        expect(feed.refreshes, 1);
      });
    });
  }
}
