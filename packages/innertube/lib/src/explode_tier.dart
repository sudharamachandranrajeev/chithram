import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yte;

import 'errors.dart';
import 'models.dart';
import 'net.dart';

/// Last tier: youtube_explode_dart's own clients (slow, retries internally).
/// Injected into the resolver so tests can fake it.
typedef ExplodeResolver = Future<VideoStreams> Function(String videoId);

DateTime? _expiry(Uri url) {
  final expire = int.tryParse(url.queryParameters['expire'] ?? '');
  return expire == null ? null : DateTime.fromMillisecondsSinceEpoch(expire * 1000, isUtc: true);
}

/// The user agents googlevideo expects for each player client (its `c=`).
const _clientAgents = {
  'ANDROID': 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
  'ANDROID_VR':
      'com.google.android.apps.youtube.vr.oculus/1.56.21 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
  'IOS': 'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
};

String _containerOf(yte.StreamInfo s) => s.container.name;

StreamFormat _video(yte.VideoStreamInfo s, {AudioCodec? audio}) => StreamFormat(
      itag: s.tag,
      url: s.url,
      container: _containerOf(s),
      codecs: s.videoCodec,
      videoCodec: _codec(s.videoCodec),
      audioCodec: audio,
      width: s.videoResolution.width,
      height: s.videoResolution.height,
      fps: s.framerate.framesPerSecond.toDouble(),
      bitrate: s.bitrate.bitsPerSecond,
      contentLength: s.size.totalBytes,
      expires: _expiry(s.url),
      qualityLabel: s.qualityLabel,
    );

VideoCodec _codec(String c) {
  final t = c.toLowerCase();
  if (t.startsWith('av01')) return VideoCodec.av1;
  if (t.startsWith('vp09') || t.startsWith('vp9')) return VideoCodec.vp9;
  if (t.startsWith('hev1') || t.startsWith('hvc1')) return VideoCodec.h265;
  return VideoCodec.h264;
}

AudioCodec _audioCodec(String c) {
  final t = c.toLowerCase();
  if (t.contains('opus')) return AudioCodec.opus;
  if (t.startsWith('mp4a')) return AudioCodec.aac;
  return AudioCodec.other;
}

/// Builds an [ExplodeResolver] over [yt] (a new one when null).
ExplodeResolver explodeResolver([yte.YoutubeExplode? yt]) {
  final client = yt ?? yte.YoutubeExplode();
  return (videoId) async {
    final video = await client.videos.get(videoId);
    Uri? hls;
    if (video.isLive) {
      hls = Uri.parse(await client.videos.streams.getHttpLiveStreamUrl(yte.VideoId(videoId)));
    }
    final manifest = await client.videos.streams.getManifest(videoId);
    final thumbs = <ThumbnailInfo>[
      ThumbnailInfo(video.thumbnails.highResUrl),
      ThumbnailInfo(video.thumbnails.maxResUrl),
    ];
    final sample = [...manifest.muxed, ...manifest.audioOnly, ...manifest.videoOnly];
    final agent = sample.isEmpty ? browserAgent : _clientAgents[sample.first.url.queryParameters['c']] ?? browserAgent;
    final streams = VideoStreams(
      videoId: videoId,
      tier: Tier.explode,
      userAgent: agent,
      title: video.title,
      author: video.author,
      duration: video.duration,
      thumbnails: thumbs,
      isLive: video.isLive,
      hlsManifestUrl: hls,
      muxed: [for (final s in manifest.muxed) _video(s, audio: _audioCodec(s.audioCodec))],
      video: [for (final s in manifest.videoOnly) _video(s)],
      audio: [
        for (final s in manifest.audioOnly)
          StreamFormat(
            itag: s.tag,
            url: s.url,
            container: _containerOf(s),
            codecs: s.audioCodec,
            audioCodec: _audioCodec(s.audioCodec),
            bitrate: s.bitrate.bitsPerSecond,
            contentLength: s.size.totalBytes,
            expires: _expiry(s.url),
          ),
      ],
    );
    if (!streams.hasFormats && hls == null) throw InnertubeException('youtube_explode found no streams');
    return streams;
  };
}
