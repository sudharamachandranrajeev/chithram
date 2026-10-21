import 'package:chithram_player/chithram_player.dart';
import 'package:innertube/innertube.dart';

import '../../core/item_id.dart';
import '../../player/play_request.dart';
import 'youtube_fixture.dart';

// innertube's `Page` clashes with Flutter's: import it with a prefix or `hide`
// in files that also import material.

/// Compiled in only for the end-to-end suite (`--dart-define=E2E_BASE=...`):
/// search and stream resolution are answered by fixtures on that server.
const _e2eBase = String.fromEnvironment('E2E_BASE');

/// No stream could be built for a video. [toString] is the text the player
/// shows: one line per tier that failed.
class YouTubeUnavailable implements Exception {
  YouTubeUnavailable(this.message);

  factory YouTubeUnavailable.fromTiers(AllTiersFailed failed) {
    final lines = [
      for (final a in failed.attempts)
        '${a.tier.name}: ${a.ok ? 'ok' : a.error}',
    ];
    return YouTubeUnavailable(
      'YouTube would not play this video.\n${lines.join('\n')}',
    );
  }

  final String message;

  @override
  String toString() => message;
}

/// YouTube search and stream resolution.
class YouTubeService {
  YouTubeService({
    InnertubeBrowse? browse,
    YouTubeResolver? resolver,
    this.caps = const PlaybackCaps(),
  }) {
    if (_e2eBase.isNotEmpty && browse == null && resolver == null) {
      _browse = FixtureBrowse(_e2eBase);
      _resolver = FixtureResolver(_e2eBase);
    } else {
      _browse = browse;
      _resolver = resolver;
    }
  }

  InnertubeBrowse? _browse;
  YouTubeResolver? _resolver;

  InnertubeBrowse get browse => _browse ??= InnertubeBrowse();
  YouTubeResolver get resolver => _resolver ??= YouTubeResolver();

  /// What the playing device decodes. Engines report it; set it once known.
  PlaybackCaps caps;

  Future<Page<VideoItem>> search(String q, {String? continuation}) =>
      browse.search(q, continuation: continuation);

  Future<PlayRequest> playRequest(VideoItem v) async => PlayRequest(
    itemId: ItemId.youtube(v.videoId),
    title: v.title,
    subtitle: v.author.isEmpty ? null : v.author,
    artwork: _artwork(v.thumbnails),
    isLive: v.isLive,
    resolve: () => resolveSpec(v.videoId),
  );

  Future<PlayRequest> playRequestForId(String videoId) async => PlayRequest(
    itemId: ItemId.youtube(videoId),
    title: videoId,
    resolve: () => resolveSpec(videoId),
  );

  /// Resolves [videoId] and maps it to what the player opens.
  Future<MediaSpec> resolveSpec(String videoId) async {
    final VideoStreams streams;
    try {
      streams = await resolver.resolve(videoId);
    } on AllTiersFailed catch (failed) {
      throw YouTubeUnavailable.fromTiers(failed);
    }
    return mediaSpecFor(streams, caps);
  }

  /// The player's view of [streams]:
  /// - live: the HLS manifest;
  /// - adaptive: best video and audio for [caps], with ranged headers;
  /// - otherwise the muxed fallback (720p at most), or video alone.
  static MediaSpec mediaSpecFor(VideoStreams streams, PlaybackCaps caps) {
    final manifest = streams.hlsManifestUrl;
    if (streams.isLive && manifest != null) {
      return MediaSpec(
        videoUrl: manifest.toString(),
        headers: {'User-Agent': streams.userAgent},
        isLive: true,
      );
    }
    final picked = pickFormats(streams, deviceCaps(caps));
    final headers = rangedHeaders(streams.userAgent);
    final video = picked.video ?? picked.muxed;
    if (video == null)
      throw YouTubeUnavailable(
        'YouTube offered no playable stream for this video.',
      );
    final audio = picked.isAdaptive ? picked.audio : null;
    return MediaSpec(
      videoUrl: video.url.toString(),
      audioUrl: audio?.url.toString(),
      headers: headers,
    );
  }

  /// [PlaybackCaps] (what the engine reports) as the picker's [DeviceCaps].
  static DeviceCaps deviceCaps(PlaybackCaps caps) {
    final codecs = <VideoCodec>[
      for (final name in caps.videoCodecs)
        for (final c in VideoCodec.values)
          if (c.name == name) c,
    ];
    return DeviceCaps(
      videoCodecs: codecs.isEmpty ? const [VideoCodec.h264] : codecs,
      maxHeight: caps.maxHeight,
      preferHdr: caps.hdr,
    );
  }

  static String? _artwork(List<ThumbnailInfo> thumbs) =>
      thumbs.isEmpty ? null : thumbs.last.url;

  static final _idRe = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// The video id in a YouTube link (watch, youtu.be, shorts, live), or null.
  static String? videoIdFromUrl(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null || (u.scheme != 'http' && u.scheme != 'https')) return null;
    final host = u.host.toLowerCase();
    String? id;
    if (host == 'youtu.be') {
      id = u.pathSegments.firstOrNull;
    } else if (host == 'youtube.com' || host.endsWith('.youtube.com')) {
      final seg = u.pathSegments;
      if (u.path == '/watch') {
        id = u.queryParameters['v'];
      } else if (seg.length >= 2 && (seg[0] == 'shorts' || seg[0] == 'live')) {
        id = seg[1];
      }
    }
    return id != null && _idRe.hasMatch(id) ? id : null;
  }
}
