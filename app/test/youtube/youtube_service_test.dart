import 'package:chithram/src/features/youtube/youtube_search_controller.dart';
import 'package:chithram/src/features/youtube/youtube_service.dart';
import 'package:chithram_player/chithram_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:innertube/innertube.dart';

VideoItem video(String id) =>
    VideoItem(videoId: id.padRight(11, '0'), title: 'Video $id');

/// Three pages: a, b, c. Records every call.
class FakeBrowse extends InnertubeBrowse {
  final calls = <String>[];
  Object? failWith;

  @override
  Future<Page<VideoItem>> search(
    String query, {
    String? continuation,
    String params = SearchFilter.videos,
  }) async {
    calls.add('$query|${continuation ?? ''}');
    final error = failWith;
    if (error != null) throw error;
    return switch (continuation) {
      null => Page([video('a1'), video('a2')], 'p2'),
      'p2' => Page([video('a2'), video('b1')], 'p3'),
      _ => Page([video('c1')], null),
    };
  }
}

class FakeResolver extends YouTubeResolver {
  FakeResolver(this.streams);
  final VideoStreams Function(String id) streams;
  Object? failWith;

  @override
  Future<VideoStreams> resolve(String videoId) async {
    final error = failWith;
    if (error != null) throw error;
    return streams(videoId);
  }
}

StreamFormat fmt(
  int itag, {
  VideoCodec? v,
  AudioCodec? a,
  int? h,
  bool hdr = false,
  int bitrate = 1000,
}) => StreamFormat(
  itag: itag,
  url: Uri.parse('https://gv.example/$itag'),
  videoCodec: v,
  audioCodec: a,
  width: h == null ? null : h * 16 ~/ 9,
  height: h,
  hdr: hdr,
  bitrate: bitrate,
);

VideoStreams streams({
  List<StreamFormat> video = const [],
  List<StreamFormat> audio = const [],
  List<StreamFormat> muxed = const [],
  bool live = false,
  Uri? hls,
}) => VideoStreams(
  videoId: 'abcdefghijk',
  tier: Tier.visionos,
  userAgent: 'UA/1',
  video: video,
  audio: audio,
  muxed: muxed,
  isLive: live,
  hlsManifestUrl: hls,
);

void main() {
  group('search paging', () {
    test(
      'first page, then continuation without duplicates, then the end',
      () async {
        final browse = FakeBrowse();
        final c = YouTubeSearchController(YouTubeService(browse: browse));
        await c.search('  cats ');
        expect(c.items.map((v) => v.title), ['Video a1', 'Video a2']);
        expect(c.continuation, 'p2');
        expect(c.searched, isTrue);

        await c.loadMore();
        expect(c.items.map((v) => v.title), [
          'Video a1',
          'Video a2',
          'Video b1',
        ]);
        await c.loadMore();
        expect(c.items.length, 4);
        expect(c.continuation, isNull);
        await c.loadMore(); // nothing left: no call
        expect(browse.calls, ['cats|', 'cats|p2', 'cats|p3']);
      },
    );

    test(
      'a new search replaces the old results; an empty query clears them',
      () async {
        final c = YouTubeSearchController(YouTubeService(browse: FakeBrowse()));
        await c.search('one');
        await c.search('two');
        expect(c.query, 'two');
        expect(c.items.length, 2);
        await c.search('   ');
        expect(c.items, isEmpty);
        expect(c.searched, isFalse);
      },
    );

    test('a failed search shows its message', () async {
      final browse = FakeBrowse()
        ..failWith = HttpStatusException(429, 'www.youtube.com');
      final c = YouTubeSearchController(YouTubeService(browse: browse));
      await c.search('x');
      expect(c.error, 'www.youtube.com said 429');
      expect(c.items, isEmpty);
    });
  });

  group('MediaSpec shapes', () {
    const caps = PlaybackCaps();

    test('adaptive: best video and audio with ranged headers', () {
      final spec = YouTubeService.mediaSpecFor(
        streams(
          video: [
            fmt(1, v: VideoCodec.h264, h: 720),
            fmt(2, v: VideoCodec.vp9, h: 1080),
          ],
          audio: [fmt(3, a: AudioCodec.opus, bitrate: 160000)],
          muxed: [fmt(18, v: VideoCodec.h264, a: AudioCodec.aac, h: 360)],
        ),
        caps,
      );
      expect(spec.videoUrl, 'https://gv.example/2');
      expect(spec.audioUrl, 'https://gv.example/3');
      expect(spec.headers, {'User-Agent': 'UA/1', 'Range': 'bytes=0-'});
      expect(spec.isLive, isFalse);
    });

    test('live: the HLS manifest, no Range header', () {
      final spec = YouTubeService.mediaSpecFor(
        streams(
          live: true,
          hls: Uri.parse('https://gv.example/live.m3u8'),
          muxed: [fmt(18, v: VideoCodec.h264, a: AudioCodec.aac, h: 360)],
        ),
        caps,
      );
      expect(spec.videoUrl, 'https://gv.example/live.m3u8');
      expect(spec.audioUrl, isNull);
      expect(spec.isLive, isTrue);
      expect(spec.headers, {'User-Agent': 'UA/1'});
    });

    test('muxed fallback when no adaptive video fits the codecs', () {
      final spec = YouTubeService.mediaSpecFor(
        streams(
          video: [fmt(1, v: VideoCodec.av1, h: 1080)],
          audio: [fmt(3, a: AudioCodec.opus)],
          muxed: [fmt(18, v: VideoCodec.h264, a: AudioCodec.aac, h: 360)],
        ),
        caps,
      );
      expect(spec.videoUrl, 'https://gv.example/18');
      expect(spec.audioUrl, isNull);
    });

    test('video without audio plays alone', () {
      final spec = YouTubeService.mediaSpecFor(
        streams(video: [fmt(1, v: VideoCodec.h264, h: 720)]),
        caps,
      );
      expect(spec.videoUrl, 'https://gv.example/1');
      expect(spec.audioUrl, isNull);
    });

    test('nothing playable is an error with a message', () {
      expect(
        () => YouTubeService.mediaSpecFor(streams(), caps),
        throwsA(isA<YouTubeUnavailable>()),
      );
    });
  });

  group('caps mapping', () {
    test('codecs, height and HDR carry over; unknown names are dropped', () {
      final d = YouTubeService.deviceCaps(
        const PlaybackCaps(
          videoCodecs: ['av1', 'bogus', 'h264'],
          maxHeight: 2160,
          hdr: true,
        ),
      );
      expect(d.videoCodecs, [VideoCodec.av1, VideoCodec.h264]);
      expect(d.maxHeight, 2160);
      expect(d.preferHdr, isTrue);
    });

    test('the default is vp9 and h264 at 1080, no HDR', () {
      final d = YouTubeService.deviceCaps(const PlaybackCaps());
      expect(d.videoCodecs, [VideoCodec.vp9, VideoCodec.h264]);
      expect(d.maxHeight, 1080);
      expect(d.preferHdr, isFalse);
    });

    test('the service picks with its caps', () async {
      final all = streams(
        video: [
          fmt(1, v: VideoCodec.h264, h: 1080),
          fmt(2, v: VideoCodec.h264, h: 720),
        ],
        audio: [fmt(3, a: AudioCodec.aac)],
      );
      final service = YouTubeService(
        resolver: FakeResolver((_) => all),
        caps: const PlaybackCaps(videoCodecs: ['h264'], maxHeight: 720),
      );
      expect(
        (await service.resolveSpec('abcdefghijk')).videoUrl,
        'https://gv.example/2',
      );
      service.caps = const PlaybackCaps(videoCodecs: ['h264']);
      expect(
        (await service.resolveSpec('abcdefghijk')).videoUrl,
        'https://gv.example/1',
      );
    });
  });

  group('errors', () {
    test('AllTiersFailed lists each tier outcome', () async {
      final resolver = FakeResolver((_) => throw StateError('unused'))
        ..failWith = AllTiersFailed('abcdefghijk', const [
          TierAttempt(
            Tier.visionos,
            Duration(seconds: 1),
            error: '403: LOGIN_REQUIRED',
          ),
          TierAttempt(
            Tier.androidVr,
            Duration(seconds: 2),
            error: 'TimeoutException',
          ),
        ]);
      final service = YouTubeService(resolver: resolver);
      await expectLater(
        service.resolveSpec('abcdefghijk'),
        throwsA(
          isA<YouTubeUnavailable>().having(
            (e) => e.toString(),
            'message',
            'YouTube would not play this video.\nvisionos: 403: LOGIN_REQUIRED\nandroidVr: TimeoutException',
          ),
        ),
      );
    });

    test('the play request resolves through the service', () async {
      final service = YouTubeService(
        resolver: FakeResolver(
          (_) => streams(
            muxed: [fmt(18, v: VideoCodec.h264, a: AudioCodec.aac, h: 360)],
          ),
        ),
      );
      final request = await service.playRequest(video('a1'));
      expect(request.itemId, 'yt:a1000000000');
      expect((await request.resolve()).videoUrl, 'https://gv.example/18');
    });
  });
}
