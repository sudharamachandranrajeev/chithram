import 'models.dart';

/// What the playing device can do.
class DeviceCaps {
  const DeviceCaps({
    this.videoCodecs = const [VideoCodec.av1, VideoCodec.vp9, VideoCodec.h264],
    this.audioCodecs = const [AudioCodec.opus, AudioCodec.aac],
    this.maxHeight = 2160,
    this.preferHdr = false,
  });

  /// Hardware-decodable codecs in order of preference (best first).
  final List<VideoCodec> videoCodecs;
  final List<AudioCodec> audioCodecs;

  /// Cap on the picture's short side (1080 for a 1080p panel).
  final int maxHeight;

  /// Choose HDR (PQ/HLG) formats when the display handles HDR; otherwise SDR
  /// is chosen and HDR only used when nothing else fits.
  final bool preferHdr;
}

class PickedFormats {
  const PickedFormats({this.video, this.audio, this.muxed});

  /// Adaptive pair: play both (Media3 MergingMediaSource, mpv `audio-files`).
  final StreamFormat? video;
  final StreamFormat? audio;

  /// Single-stream fallback when no adaptive video fits.
  final StreamFormat? muxed;

  bool get isAdaptive => video != null;
  bool get isEmpty => video == null && muxed == null && audio == null;
}

/// Best video and audio for [caps]. Ranking for video: short side (within the
/// cap), then codec preference order, then fps, then bitrate. Audio: the
/// original-language track, not the DRC copy, then preferred codec, then
/// bitrate.
PickedFormats pickFormats(VideoStreams streams, DeviceCaps caps) {
  final video = _bestVideo(streams.video, caps);
  final audio = _bestAudio(streams.audio, caps);
  // Muxed is the fallback: without adaptive video, or with no audio to merge.
  final muxed = _bestVideo(streams.muxed, caps, anyCodec: true);
  if (video != null && audio != null) {
    return PickedFormats(video: video, audio: audio, muxed: muxed);
  }
  if (muxed != null) return PickedFormats(muxed: muxed);
  return PickedFormats(video: video, audio: audio);
}

StreamFormat? _bestVideo(List<StreamFormat> formats, DeviceCaps caps, {bool anyCodec = false}) {
  var pool = formats.where((f) => f.hasVideo).toList();
  final codecOk = pool.where((f) => anyCodec || caps.videoCodecs.contains(f.videoCodec)).toList();
  pool = codecOk;
  if (pool.isEmpty) return null;
  final capped = pool.where((f) => f.shortSide <= caps.maxHeight).toList();
  // Nothing under the cap: take the smallest one over it.
  if (capped.isEmpty) {
    pool.sort((a, b) => a.shortSide.compareTo(b.shortSide));
    return pool.first;
  }
  pool = capped;
  final sdr = pool.where((f) => !f.hdr).toList();
  final hdr = pool.where((f) => f.hdr).toList();
  if (caps.preferHdr && hdr.isNotEmpty) {
    pool = hdr;
  } else if (sdr.isNotEmpty) {
    pool = sdr;
  }
  int codecRank(StreamFormat f) {
    final i = caps.videoCodecs.indexOf(f.videoCodec!);
    return i < 0 ? caps.videoCodecs.length : i;
  }

  pool.sort((a, b) {
    var c = b.shortSide.compareTo(a.shortSide);
    if (c != 0) return c;
    c = codecRank(a).compareTo(codecRank(b));
    if (c != 0) return c;
    c = (b.fps ?? 0).compareTo(a.fps ?? 0);
    if (c != 0) return c;
    return b.bitrate.compareTo(a.bitrate);
  });
  return pool.first;
}

StreamFormat? _bestAudio(List<StreamFormat> formats, DeviceCaps caps) {
  var pool = formats.where((f) => f.hasAudio).toList();
  if (pool.isEmpty) return null;
  final supported = pool.where((f) => caps.audioCodecs.contains(f.audioCodec)).toList();
  if (supported.isNotEmpty) pool = supported;
  int codecRank(StreamFormat f) {
    final i = caps.audioCodecs.indexOf(f.audioCodec!);
    return i < 0 ? caps.audioCodecs.length : i;
  }

  pool.sort((a, b) {
    if (a.isDefaultTrack != b.isDefaultTrack) return a.isDefaultTrack ? -1 : 1;
    if (a.isDrc != b.isDrc) return a.isDrc ? 1 : -1;
    // Within ~10%, prefer the codec order; otherwise the higher bitrate.
    final hi = a.bitrate > b.bitrate ? a.bitrate : b.bitrate;
    if ((a.bitrate - b.bitrate).abs() > hi * 0.1) return b.bitrate.compareTo(a.bitrate);
    final c = codecRank(a).compareTo(codecRank(b));
    if (c != 0) return c;
    return b.bitrate.compareTo(a.bitrate);
  });
  return pool.first;
}
