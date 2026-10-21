import 'package:innertube/innertube.dart';

/// Search that finds one "Fixture" item, for the end-to-end suite.
class FixtureBrowse extends InnertubeBrowse {
  FixtureBrowse(this.base);

  final String base;

  @override
  Future<Page<VideoItem>> search(
    String query, {
    String? continuation,
    String params = SearchFilter.videos,
  }) async => const Page([
    VideoItem(
      videoId: 'fixturevid1',
      title: 'Fixture',
      author: 'Chithram tests',
      duration: Duration(seconds: 60),
    ),
  ], null);
}

/// Resolves to the fixture server's `video.mp4` and `audio.m4a`.
class FixtureResolver extends YouTubeResolver {
  FixtureResolver(this.base);

  final String base;

  @override
  Future<VideoStreams> resolve(String videoId) async => VideoStreams(
    videoId: videoId,
    tier: Tier.visionos,
    userAgent: browserAgent,
    title: 'Fixture',
    video: [
      StreamFormat(
        itag: 137,
        url: Uri.parse('$base/video.mp4'),
        videoCodec: VideoCodec.h264,
        width: 1280,
        height: 720,
        fps: 30,
      ),
    ],
    audio: [
      StreamFormat(
        itag: 140,
        url: Uri.parse('$base/audio.m4a'),
        audioCodec: AudioCodec.aac,
        bitrate: 128000,
      ),
    ],
  );
}
