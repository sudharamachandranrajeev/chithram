import 'package:chithram/src/core/prefs.dart';
import 'package:chithram/src/features/youtube/feed/taste.dart';
import 'package:chithram/src/features/youtube/youtube_prefs.dart';
import 'package:chithram/src/features/youtube/youtube_queue.dart';
import 'package:chithram/src/features/youtube/youtube_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:innertube/innertube.dart';

VideoItem v(
  String id, {
  String channel = '',
  String title = '',
  bool live = false,
}) => VideoItem(
  videoId: id.padRight(11, '0'),
  title: title.isEmpty ? 'Video $id' : title,
  channelId: channel,
  author: channel,
  isLive: live,
);

class FakeBrowse extends InnertubeBrowse {
  FakeBrowse(this.lists);
  final Map<String, List<VideoItem>> lists;
  final calls = <String>[];

  @override
  Future<WatchInfo> watchInfo(String videoId, {Duration? duration}) async {
    calls.add(videoId);
    return WatchInfo(related: lists[videoId] ?? const []);
  }
}

void main() {
  group('pickNextVideo', () {
    test('YouTube order wins on an empty profile', () {
      expect(
        pickNextVideo([v('a'), v('b')], TasteProfile())!.videoId,
        v('a').videoId,
      );
    });

    test('a liked channel beats a better position', () {
      final taste = TasteProfile()
        ..watched(
          v('x', channel: 'UCliked', title: 'guitar lesson'),
          position: const Duration(minutes: 9),
          duration: const Duration(minutes: 10),
        );
      final pick = pickNextVideo([
        v('a', channel: 'UCother'),
        v('b', channel: 'UCliked', title: 'guitar riffs'),
      ], taste);
      expect(pick!.videoId, v('b').videoId);
    });

    test('skips seen, played, live and disliked channels', () {
      final taste = TasteProfile()
        ..watched(
          v('a'),
          position: const Duration(minutes: 9),
          duration: const Duration(minutes: 10),
        )
        ..watched(
          v('d', channel: 'UCbad'),
          position: const Duration(seconds: 3),
          duration: const Duration(minutes: 10),
        );
      final pick = pickNextVideo(
        [v('a'), v('b'), v('c', live: true), v('d', channel: 'UCbad'), v('e')],
        taste,
        played: {v('b').videoId},
      );
      expect(pick!.videoId, v('e').videoId);
    });

    test('everything seen: still the first not played this session; nothing left: null', () {
      final taste = TasteProfile()
        ..watched(
          v('a'),
          position: const Duration(minutes: 9),
          duration: const Duration(minutes: 10),
        )
        ..watched(
          v('b'),
          position: const Duration(minutes: 9),
          duration: const Duration(minutes: 10),
        );
      expect(
        pickNextVideo(
          [v('a'), v('b')],
          taste,
          played: {v('a').videoId},
        )!.videoId,
        v('b').videoId,
      );
      expect(pickNextVideo([v('a')], taste, played: {v('a').videoId}), isNull);
      expect(pickNextVideo(const [], taste), isNull);
    });
  });

  group('YouTubeQueue through the service', () {
    late FakeBrowse browse;
    late YouTubeService service;
    late Prefs prefs;

    setUp(() {
      browse = FakeBrowse({
        v('a').videoId: [v('b'), v('c')],
        v('b').videoId: [v('a'), v('c'), v('d')],
        v('c').videoId: [v('a'), v('b')],
      });
      prefs = Prefs.memory();
      service = YouTubeService(
        browse: browse,
        taste: TasteStore.memory(),
        prefs: prefs,
      );
    });

    test(
      'next never repeats a video in the session; Previous and forward replay',
      () async {
        final first = await service.playRequest(v('a'));
        final q = first.queue!;
        expect(q.hasPrevious, isFalse);
        final b = (await q.prepareNext())!;
        expect(b.itemId, 'yt:${v('b').videoId}');
        expect(
          (await q.prepareNext())!.itemId,
          b.itemId,
          reason: 'same answer until taken',
        );
        expect(browse.calls, [v('a').videoId], reason: 'one /next call');
        expect(q.takeNext()!.itemId, b.itemId);
        expect(q.hasPrevious, isTrue);
        // b's related list is a, c, d: a was played, so c.
        final c = (await q.prepareNext())!;
        expect(c.itemId, 'yt:${v('c').videoId}');
        expect(q.takeNext(), isNotNull);
        // c's related: a, b both played -> nothing.
        expect(await q.prepareNext(), isNull);
        expect(q.takeNext(), isNull);
        // Back to b, back to a, then forward replays b.
        expect(q.takePrevious()!.itemId, b.itemId);
        expect(q.takePrevious()!.itemId, first.itemId);
        expect(q.takePrevious(), isNull);
        expect((await q.prepareNext())!.itemId, b.itemId);
        expect(q.takeNext()!.itemId, b.itemId);
      },
    );

    test('an autoplayed play reports to taste with source autoplay', () async {
      final first = await service.playRequest(v('a'), source: 'rail-x');
      first.onWatched!(const Duration(minutes: 9), const Duration(minutes: 10));
      await Future<void>.delayed(Duration.zero);
      final next = (await first.queue!.prepareNext())!;
      next.onWatched!(const Duration(minutes: 9), const Duration(minutes: 10));
      await Future<void>.delayed(Duration.zero);
      final history = service.taste.profile.history;
      expect(history.first.item.videoId, v('b').videoId);
      expect(history.first.source, 'autoplay');
      expect(history.last.source, 'rail-x');
    });

    test('the autoplay setting is read live and defaults to on', () async {
      final q = (await service.playRequest(v('a'))).queue!;
      expect(q.autoplay, isTrue);
      await prefs.set(YouTubePrefs.autoplay, false);
      expect(q.autoplay, isFalse);
    });

    test('live videos get no queue or extras', () async {
      final r = await service.playRequest(v('a', live: true));
      expect(r.queue, isNull);
      expect(r.extras, isNull);
    });

    test('a failing /next gives no next video, not an error', () async {
      final failing = YouTubeService(
        browse: _Failing(),
        taste: TasteStore.memory(),
      );
      final q = (await failing.playRequest(v('a'))).queue!;
      expect(await q.prepareNext(), isNull);
    });
  });

  test(
    'extras: chapters past the end are dropped; SponsorBlock only when on',
    () async {
      final browse = _WithChapters();
      final prefs = Prefs.memory();
      final service = YouTubeService(
        browse: browse,
        taste: TasteStore.memory(),
        prefs: prefs,
        sponsorBlock: _NoSponsors(),
      );
      final r = await service.playRequest(v('a'));
      final x = await r.extras!(const Duration(minutes: 2));
      expect(x.chapters.map((c) => c.title), ['One', 'Two']);
      expect(x.heatmap, hasLength(1));
      expect(x.segments, isEmpty);
      await prefs.set(YouTubePrefs.sponsorBlock, true);
      final y = await r.extras!(const Duration(minutes: 2));
      expect(y.segments, hasLength(1));
    },
  );
}

class _Failing extends InnertubeBrowse {
  @override
  Future<WatchInfo> watchInfo(String videoId, {Duration? duration}) =>
      throw StateError('offline');
}

class _WithChapters extends InnertubeBrowse {
  @override
  Future<WatchInfo> watchInfo(String videoId, {Duration? duration}) async =>
      const WatchInfo(
        chapters: [
          Chapter(Duration.zero, 'One'),
          Chapter(Duration(minutes: 1), 'Two'),
          Chapter(Duration(minutes: 9), 'Late'),
        ],
        heatmap: [HeatBin(Duration.zero, Duration(seconds: 5), 1)],
      );
}

class _NoSponsors extends SponsorBlockClient {
  @override
  Future<List<SponsorSegment>> segments(
    String videoId, {
    List<String> categories = defaultSponsorCategories,
  }) async => const [
    SponsorSegment(
      category: 'sponsor',
      actionType: 'skip',
      start: Duration(seconds: 5),
      end: Duration(seconds: 15),
    ),
  ];
}
