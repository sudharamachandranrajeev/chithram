enum Tier { visionos, androidVr, tv, explode }

enum VideoCodec { av1, vp9, h265, h264 }

enum AudioCodec { opus, aac, other }

/// One stream YouTube offers: muxed (audio + video), adaptive video or
/// adaptive audio.
class StreamFormat {
  const StreamFormat({
    required this.itag,
    required this.url,
    this.mimeType = '',
    this.container = '',
    this.codecs = '',
    this.videoCodec,
    this.audioCodec,
    this.width,
    this.height,
    this.fps,
    this.bitrate = 0,
    this.contentLength,
    this.expires,
    this.hdr = false,
    this.isDefaultTrack = true,
    this.isDrc = false,
    this.qualityLabel,
    this.audioSampleRate,
  });

  final int itag;
  final Uri url;
  final String mimeType;

  /// "mp4", "webm".
  final String container;

  /// Raw codec string, e.g. `avc1.640028, mp4a.40.2`.
  final String codecs;
  final VideoCodec? videoCodec;
  final AudioCodec? audioCodec;
  final int? width;
  final int? height;
  final double? fps;

  /// Bits per second (peak).
  final int bitrate;
  final int? contentLength;
  final DateTime? expires;
  final bool hdr;

  /// False for a dubbed or translated audio track.
  final bool isDefaultTrack;

  /// Loudness-levelled copy of an audio track.
  final bool isDrc;
  final String? qualityLabel;
  final int? audioSampleRate;

  bool get hasVideo => videoCodec != null;
  bool get hasAudio => audioCodec != null;

  /// Short side in pixels. Used for caps and ranking so a portrait 1080x1920
  /// Short counts as 1080p.
  int get shortSide {
    final w = width, h = height;
    if (w == null || h == null) return h ?? w ?? 0;
    return w < h ? w : h;
  }

  Map<String, Object?> toJson() => {
        'itag': itag,
        'container': container,
        'codecs': codecs,
        'width': width,
        'height': height,
        'fps': fps,
        'bitrate': bitrate,
        'contentLength': contentLength,
        'expires': expires?.toIso8601String(),
        'hdr': hdr,
      };
}

class ThumbnailInfo {
  const ThumbnailInfo(this.url, {this.width, this.height});
  final String url;
  final int? width;
  final int? height;
}

/// How one tier fared.
class TierAttempt {
  const TierAttempt(this.tier, this.elapsed, {this.error});
  final Tier tier;
  final Duration elapsed;

  /// Null when the tier won.
  final String? error;
  bool get ok => error == null;
}

/// What a resolve produced.
class VideoStreams {
  const VideoStreams({
    required this.videoId,
    required this.tier,
    required this.userAgent,
    this.title = '',
    this.author = '',
    this.duration,
    this.thumbnails = const [],
    this.isLive = false,
    this.hlsManifestUrl,
    this.muxed = const [],
    this.video = const [],
    this.audio = const [],
    this.attempts = const [],
  });

  final String videoId;

  /// The tier that won.
  final Tier tier;

  /// The user agent googlevideo expects for this tier's links (its `c=`).
  final String userAgent;
  final String title;
  final String author;
  final Duration? duration;
  final List<ThumbnailInfo> thumbnails;
  final bool isLive;

  /// For live videos (and sometimes premieres): play this instead.
  final Uri? hlsManifestUrl;

  /// Audio + video in one stream (itag 18 / 22): capped at 720p.
  final List<StreamFormat> muxed;

  /// Adaptive video only.
  final List<StreamFormat> video;

  /// Adaptive audio only.
  final List<StreamFormat> audio;
  final List<TierAttempt> attempts;

  bool get hasFormats => muxed.isNotEmpty || video.isNotEmpty || audio.isNotEmpty;

  /// Earliest expiry across formats, or null when unknown.
  DateTime? get expires {
    DateTime? best;
    for (final f in [...muxed, ...video, ...audio]) {
      final e = f.expires;
      if (e != null && (best == null || e.isBefore(best))) best = e;
    }
    return best;
  }

  VideoStreams withAttempts(Tier winner, List<TierAttempt> attempts) => VideoStreams(
        videoId: videoId,
        tier: winner,
        userAgent: userAgent,
        title: title,
        author: author,
        duration: duration,
        thumbnails: thumbnails,
        isLive: isLive,
        hlsManifestUrl: hlsManifestUrl,
        muxed: muxed,
        video: video,
        audio: audio,
        attempts: attempts,
      );
}

/// Title, channel and counters of a video.
class VideoDetails {
  const VideoDetails({
    required this.videoId,
    required this.title,
    this.author = '',
    this.channelId = '',
    this.description = '',
    this.duration,
    this.viewCount,
    this.isLive = false,
    this.thumbnails = const [],
  });
  final String videoId;
  final String title;
  final String author;
  final String channelId;
  final String description;
  final Duration? duration;
  final int? viewCount;
  final bool isLive;
  final List<ThumbnailInfo> thumbnails;
}

/// A video in a search result or an uploads list.
class VideoItem {
  const VideoItem({
    required this.videoId,
    required this.title,
    this.author = '',
    this.channelId = '',
    this.duration,
    this.viewsText = '',
    this.isLive = false,
    this.thumbnails = const [],
  });
  final String videoId;
  final String title;
  final String author;
  final String channelId;
  final Duration? duration;
  final String viewsText;
  final bool isLive;
  final List<ThumbnailInfo> thumbnails;
}

/// One page of results and the token for the next one (null at the end).
class Page<T> {
  const Page(this.items, this.continuation);
  final List<T> items;
  final String? continuation;
}
