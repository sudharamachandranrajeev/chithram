import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:chithram_player/chithram_player.dart';
import 'package:innertube/innertube.dart';

import '../../core/item_id.dart';
import '../../core/prefs.dart';
import '../../player/play_request.dart';
import 'feed/taste.dart';
import 'youtube_fixture.dart';
import 'youtube_prefs.dart';
import 'youtube_queue.dart';

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

/// YouTube search and stream resolution. Every play and search also teaches
/// [taste], which Home's suggestions come from.
class YouTubeService {
  YouTubeService({
    InnertubeBrowse? browse,
    YouTubeResolver? resolver,
    this.caps = const PlaybackCaps(),
    TasteStore? taste,
    this.prefs,
    SponsorBlockClient? sponsorBlock,
  }) : taste = taste ?? TasteStore.memory(),
       _sponsorBlock = sponsorBlock {
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

  InnertubeBrowse get browse =>
      _browse ??= InnertubeBrowse(region: deviceRegion());
  YouTubeResolver get resolver => _resolver ??= YouTubeResolver();

  final TasteStore taste;
  final Prefs? prefs;
  SponsorBlockClient? _sponsorBlock;
  SponsorBlockClient get sponsorBlock => _sponsorBlock ??= SponsorBlockClient();

  // /next answers, one call per video: the queue wants the related list and
  // the seek bar the chapters. Kept for the last few videos only.
  final _info = <String, Future<WatchInfo>>{};
  final _storyboards = <String, String>{};

  /// Related videos, chapters and heatmap of [videoId]; empty when YouTube
  /// does not answer.
  Future<WatchInfo> watchInfo(String videoId) {
    final known = _info.remove(videoId);
    if (known != null) return _info[videoId] = known;
    if (_info.length >= 6) _info.remove(_info.keys.first);
    return _info[videoId] = browse.watchInfo(videoId).catchError((Object _) {
      _info.remove(videoId);
      return const WatchInfo();
    });
  }

  /// The device's country, for what is popular there; US when unknown.
  static String deviceRegion() {
    final code = PlatformDispatcher.instance.locale.countryCode?.toUpperCase();
    return code != null && RegExp(r'^[A-Z]{2}$').hasMatch(code) ? code : 'US';
  }

  /// What the playing device decodes. Engines report it; set it once known.
  PlaybackCaps caps;

  Future<Page<VideoItem>> search(String q, {String? continuation}) {
    if (continuation == null) unawaited(taste.searched(q));
    return browse.search(q, continuation: continuation);
  }

  /// Search box suggestions for [prefix]; empty when offline.
  Future<List<String>> suggest(String prefix) async {
    try {
      return await browse.suggest(prefix);
    } catch (_) {
      return const [];
    }
  }

  /// [source] is the Home rail [v] was picked from, if any.
  Future<PlayRequest> playRequest(VideoItem v, {String? source}) async =>
      _request(v, source: source);

  PlayRequest _request(VideoItem v, {String? source, PlayQueue? queue}) =>
      PlayRequest(
        itemId: ItemId.youtube(v.videoId),
        title: v.title,
        subtitle: v.author.isEmpty ? null : v.author,
        artwork: _artwork(v.thumbnails),
        isLive: v.isLive,
        resolve: () => resolveSpec(v.videoId),
        extras: v.isLive ? null : (duration) => _extras(v.videoId, duration),
        queue: v.isLive ? null : queue ?? _newQueue(v),
        onWatched: (position, duration) {
          // Never started (an error, or backed out of the resume prompt).
          if (position > Duration.zero) {
            unawaited(
              taste.watched(
                v,
                position: position,
                duration: duration,
                source: source,
              ),
            );
          }
        },
      );

  PlayQueue _newQueue(VideoItem first) {
    unawaited(taste.load());
    return YouTubeQueue(
      first: first,
      relatedOf: (id) async => (await watchInfo(id)).related,
      profile: () => taste.profile,
      build: (v, {required source, required queue}) =>
          _request(v, source: source, queue: queue),
      autoplayOn: () => YouTubePrefs.autoplayOn(prefs),
    );
  }

  /// Chapters, heatmap, preview sprites and (when turned on) SponsorBlock
  /// segments for the seek bar. Each part fails alone.
  Future<PlayExtras> _extras(String videoId, Duration duration) async {
    final sponsors = YouTubePrefs.sponsorBlockOn(prefs)
        ? sponsorBlock
              .segments(videoId)
              .catchError((Object _) => <SponsorSegment>[])
        : Future.value(<SponsorSegment>[]);
    final info = await watchInfo(videoId);
    final chapters = info.chapters
        .where((c) => duration <= Duration.zero || c.start < duration)
        .toList();
    return PlayExtras(
      chapters: chapters,
      heatmap: info.heatmap,
      segments: await sponsors,
      storyboard: parseStoryboardSpec(
        _storyboards.remove(videoId),
        duration: duration,
      ),
    );
  }

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
    final sprites = streams.storyboardSpec;
    if (sprites != null) {
      if (_storyboards.length >= 4)
        _storyboards.remove(_storyboards.keys.first);
      _storyboards[videoId] = sprites;
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
