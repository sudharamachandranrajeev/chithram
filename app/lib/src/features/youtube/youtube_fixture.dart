import 'package:innertube/innertube.dart';

/// Search that finds one "Fixture" item and Home lists of "Fixture N"
/// videos, for the end-to-end suite and widget tests. Never touches the
/// network.
class FixtureBrowse extends InnertubeBrowse {
  FixtureBrowse(this.base);

  final String base;

  /// [n] videos with ids starting with [prefix], each on its own channel.
  static List<VideoItem> videos(String prefix, int n) => [
    for (var i = 1; i <= n; i++)
      VideoItem(
        videoId: '$prefix${'$i'.padLeft(11 - prefix.length, '0')}',
        title: 'Fixture $prefix $i',
        author: 'Chithram tests $i',
        channelId: 'UC${'$prefix$i'.padRight(22, 'f')}',
        duration: const Duration(seconds: 60),
      ),
  ];

  @override
  Future<List<VideoItem>> channelHome(String channelId) async =>
      videos('p${channelId.substring(2, 4)}', 6);

  @override
  Future<List<VideoItem>> related(String videoId) async =>
      videos('r${videoId.substring(9)}', 8);

  @override
  Future<List<String>> suggest(String prefix) async =>
      prefix.trim().isEmpty ? const [] : ['${prefix.trim()} fixture', '${prefix.trim()} songs'];

  Future<WatchInfo> watchInfo(String videoId, {Duration? duration}) async =>
      WatchInfo(
        related: await related(videoId),
        chapters: const [
          Chapter(Duration.zero, 'Start'),
          Chapter(Duration(seconds: 20), 'Middle'),
          Chapter(Duration(seconds: 40), 'End'),
        ],
      );

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
