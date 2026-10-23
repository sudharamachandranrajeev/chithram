import 'dart:io';

import 'package:chithram/src/features/youtube/feed/taste.dart';
import 'package:chithram/src/features/youtube/feed/youtube_feed.dart';
import 'package:chithram/src/features/youtube/youtube_fixture.dart';
import 'package:chithram/src/features/youtube/youtube_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:innertube/innertube.dart';

/// Fixture lists, counting calls; [down] makes every call fail.
class _Browse extends FixtureBrowse {
  _Browse() : super('');

  bool down = false;
  final calls = <String>[];

  @override
  Future<List<VideoItem>> channelHome(String channelId) async {
    calls.add('home $channelId');
    if (down) throw const SocketException('offline');
    return super.channelHome(channelId);
  }

  @override
  Future<List<VideoItem>> related(String videoId) async {
    calls.add('related $videoId');
    if (down) throw const SocketException('offline');
    return super.related(videoId);
  }

  @override
  Future<Page<VideoItem>> channelUploads(String channelId, {String? continuation}) async {
    calls.add('uploads $channelId');
    if (down) throw const SocketException('offline');
    return Page(FixtureBrowse.videos('u', 5), null);
  }
}

void main() {
  late _Browse browse;
  late YouTubeService youtube;
  var now = DateTime.utc(2026, 10, 24, 12);

  YouTubeFeed feedWith({File? cache}) => YouTubeFeed(youtube: youtube, cacheFile: cache, clock: () => now);

  setUp(() {
    browse = _Browse();
    youtube = YouTubeService(browse: browse, taste: TasteStore.memory());
    now = DateTime.utc(2026, 10, 24, 12);
  });

  test('with no history: a billboard and the popular rails only', () async {
    final feed = feedWith();
    await feed.open();
    final s = feed.state.value;
    expect(s.rails.map((r) => r.id), [for (final t in popularTopics) t.$1]);
    expect(s.hero, hasLength(5));
    expect(s.error, isNull);
    expect(browse.calls, hasLength(popularTopics.length));
  });

  test('plays teach it: continue watching, suggestions, because-you-watched, rail order', () async {
    final feed = feedWith();
    await feed.open();
    final news = feed.state.value.rails.firstWhere((r) => r.id == 'popular-news');
    final liked = news.items.first;
    await youtube.taste.watched(liked, position: const Duration(minutes: 9), duration: const Duration(minutes: 10), source: 'popular-news');
    final half = news.items[1];
    await youtube.taste.watched(half, position: const Duration(minutes: 4), duration: const Duration(minutes: 10), source: 'popular-news');
    await feed.refresh();

    final s = feed.state.value;
    final ids = s.rails.map((r) => r.id).toList();
    expect(ids.take(3), ['continue', 'for-you', 'because']);
    expect(s.rails.first.items.single.videoId, half.videoId);
    final forYou = s.rails[1].items.map((v) => v.videoId);
    expect(forYou, isNot(contains(liked.videoId)));
    expect(s.rails[2].title, 'Because you watched ${half.title}');
    // News was played from: it moves to the top of the popular rails.
    expect(ids.indexOf('popular-news'), 3);
    expect(browse.calls, contains('related ${liked.videoId}'));
  });

  test('only stale lists are fetched again; the cache file survives a restart', () async {
    final dir = await Directory.systemTemp.createTemp('feed');
    addTearDown(() => dir.delete(recursive: true));
    final cache = File('${dir.path}/youtube_feed.json');
    await feedWith(cache: cache).open();
    expect(browse.calls, hasLength(popularTopics.length));

    browse.calls.clear();
    browse.down = true;
    final restarted = feedWith(cache: cache);
    await restarted.open();
    expect(browse.calls, isEmpty, reason: 'fresh in the cache');
    expect(restarted.state.value.rails, hasLength(popularTopics.length));

    now = now.add(YouTubeFeed.popularTtl + const Duration(minutes: 1));
    await restarted.refresh();
    expect(browse.calls, hasLength(popularTopics.length));
    expect(restarted.state.value.error, isNull, reason: 'old lists stay up when a refresh fails');
    expect(restarted.state.value.rails, hasLength(popularTopics.length));
  });

  test('nothing fetched and nothing cached: an error to retry', () async {
    browse.down = true;
    final feed = feedWith();
    await feed.open();
    expect(feed.state.value.error, isNotNull);
    expect(feed.state.value.rails, isEmpty);

    browse.down = false;
    await feed.refresh(force: true);
    expect(feed.state.value.error, isNull);
    expect(feed.state.value.rails, isNotEmpty);
  });

  test('a play reaches the profile through the play request', () async {
    final v = FixtureBrowse.videos('x', 1).single;
    final request = await youtube.playRequest(v, source: 'popular-music');
    request.onWatched!(Duration.zero, const Duration(minutes: 1));
    await Future<void>.delayed(Duration.zero);
    expect(youtube.taste.profile.history, isEmpty, reason: 'never started');
    request.onWatched!(const Duration(minutes: 1), const Duration(minutes: 1));
    await Future<void>.delayed(Duration.zero);
    expect(youtube.taste.profile.history.single.source, 'popular-music');
  });
}
