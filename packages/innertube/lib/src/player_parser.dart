import 'errors.dart';
import 'models.dart';
import 'util.dart';

final _codecsRe = RegExp(r'codecs="([^"]*)"');

VideoCodec? videoCodecOf(String codec) {
  final c = codec.trim().toLowerCase();
  if (c.startsWith('avc1') || c.startsWith('avc3')) return VideoCodec.h264;
  if (c.startsWith('vp09') || c.startsWith('vp9')) return VideoCodec.vp9;
  if (c.startsWith('av01')) return VideoCodec.av1;
  if (c.startsWith('hev1') || c.startsWith('hvc1')) return VideoCodec.h265;
  return null;
}

AudioCodec? audioCodecOf(String codec) {
  final c = codec.trim().toLowerCase();
  if (c.startsWith('mp4a')) return AudioCodec.aac;
  if (c.startsWith('opus')) return AudioCodec.opus;
  if (c.startsWith('vorbis') || c.startsWith('ec-3') || c.startsWith('ac-3') || c.startsWith('flac')) {
    return AudioCodec.other;
  }
  return null;
}

DateTime? _expiryOf(Uri url, DateTime now, int? expiresInSeconds) {
  final expire = int.tryParse(url.queryParameters['expire'] ?? '');
  if (expire != null) return DateTime.fromMillisecondsSinceEpoch(expire * 1000, isUtc: true);
  if (expiresInSeconds != null) return now.add(Duration(seconds: expiresInSeconds));
  return null;
}

/// One format object from `streamingData`, or null when it has no direct
/// link (a `signatureCipher` needs the player JS, which no tier here runs).
StreamFormat? parseFormat(Json f, {required DateTime now, int? expiresInSeconds}) {
  final urlText = asString(f['url']);
  if (urlText.isEmpty) return null;
  final itag = toInt(f['itag']);
  if (itag == null) return null;
  final url = Uri.parse(urlText);
  final mime = asString(f['mimeType']);
  final codecs = _codecsRe.firstMatch(mime)?.group(1) ?? '';
  final parts = codecs.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  VideoCodec? video;
  AudioCodec? audio;
  for (final p in parts) {
    video ??= videoCodecOf(p);
    audio ??= audioCodecOf(p);
  }
  // A "video/" format with an unknown codec is still video.
  if (mime.startsWith('video/') && video == null && audio == null) video = VideoCodec.h264;
  final track = asJson(f['audioTrack']);
  final transfer = asString(asJson(f['colorInfo'])['transferCharacteristics']);
  final fps = f['fps'];
  return StreamFormat(
    itag: itag,
    url: url,
    mimeType: mime,
    container: mime.split(';').first.split('/').last,
    codecs: codecs,
    videoCodec: video,
    audioCodec: audio,
    width: toInt(f['width']),
    height: toInt(f['height']),
    fps: fps is num ? fps.toDouble() : null,
    bitrate: toInt(f['bitrate']) ?? toInt(f['averageBitrate']) ?? 0,
    contentLength: toInt(f['contentLength']),
    expires: _expiryOf(url, now, expiresInSeconds),
    hdr: transfer.contains('SMPTEST2084') || transfer.contains('ARIB_STD_B67'),
    isDefaultTrack: track.isEmpty || track['audioIsDefault'] == true,
    isDrc: f['isDrc'] == true,
    qualityLabel: f['qualityLabel'] as String?,
    audioSampleRate: toInt(f['audioSampleRate']),
  );
}

List<ThumbnailInfo> parseThumbnails(Object? thumbnail) => [
      for (final t in asList(asJson(thumbnail)['thumbnails']).map(asJson))
        if (asString(t['url']).isNotEmpty)
          ThumbnailInfo(
            asString(t['url']).startsWith('//') ? 'https:${t['url']}' : asString(t['url']),
            width: toInt(t['width']),
            height: toInt(t['height']),
          ),
    ];

/// Throws [PlayabilityException] unless the response is playable.
void checkPlayability(Json response) {
  final status = asJson(response['playabilityStatus']);
  final text = asString(status['status']);
  if (text != 'OK') {
    final reason = asString(status['reason']).replaceAll(RegExp(r'\s+'), ' ').trim();
    throw PlayabilityException(text.isEmpty ? 'UNKNOWN' : text, reason);
  }
}

/// Turns a player response into [VideoStreams]. [tier] and [userAgent] say
/// which client asked. Throws [PlayabilityException] when the video is not
/// playable and [InnertubeException] when it has neither formats nor an HLS
/// manifest.
VideoStreams parsePlayerResponse(Json response,
    {required Tier tier, required String userAgent, DateTime? now}) {
  checkPlayability(response);
  final clock = now ?? DateTime.now().toUtc();
  final streaming = asJson(response['streamingData']);
  final expiresIn = toInt(streaming['expiresInSeconds']);
  final muxed = <StreamFormat>[];
  final video = <StreamFormat>[];
  final audio = <StreamFormat>[];
  for (final raw in asList(streaming['formats']).map(asJson)) {
    final f = parseFormat(raw, now: clock, expiresInSeconds: expiresIn);
    if (f != null && f.hasVideo) muxed.add(f);
  }
  for (final raw in asList(streaming['adaptiveFormats']).map(asJson)) {
    final f = parseFormat(raw, now: clock, expiresInSeconds: expiresIn);
    if (f == null) continue;
    if (f.hasVideo && f.hasAudio) {
      muxed.add(f);
    } else if (f.hasVideo) {
      video.add(f);
    } else if (f.hasAudio) {
      audio.add(f);
    }
  }
  final details = asJson(response['videoDetails']);
  final hls = asString(streaming['hlsManifestUrl']);
  final isLive = details['isLive'] == true || details['isLiveContent'] == true && hls.isNotEmpty;
  final seconds = toInt(details['lengthSeconds']);
  final streams = VideoStreams(
    videoId: asString(details['videoId']),
    tier: tier,
    userAgent: userAgent,
    title: asString(details['title']),
    author: asString(details['author']),
    duration: seconds != null && seconds > 0 ? Duration(seconds: seconds) : null,
    thumbnails: parseThumbnails(details['thumbnail']),
    isLive: isLive,
    hlsManifestUrl: hls.isEmpty ? null : Uri.parse(hls),
    muxed: muxed,
    video: video,
    audio: audio,
    storyboardSpec: storyboardSpecOf(response),
  );
  if (!streams.hasFormats && streams.hlsManifestUrl == null) {
    throw InnertubeException('no playable links in the response');
  }
  return streams;
}

/// Title, channel and counters from a player response's `videoDetails`.
VideoDetails parseVideoDetails(Json response) {
  checkPlayability(response);
  final d = asJson(response['videoDetails']);
  final seconds = toInt(d['lengthSeconds']);
  return VideoDetails(
    videoId: asString(d['videoId']),
    title: asString(d['title']),
    author: asString(d['author']),
    channelId: asString(d['channelId']),
    description: asString(d['shortDescription']),
    duration: seconds != null && seconds > 0 ? Duration(seconds: seconds) : null,
    viewCount: toInt(d['viewCount']),
    isLive: d['isLive'] == true,
    thumbnails: parseThumbnails(d['thumbnail']),
  );
}

/// The storyboard spec string of a player response, or null.
String? storyboardSpecOf(Json response) {
  final spec = asString(asJson(asJson(response['storyboards'])['playerStoryboardSpecRenderer'])['spec']);
  return spec.isEmpty ? null : spec;
}
