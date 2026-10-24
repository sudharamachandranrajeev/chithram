import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

import 'android_engine.dart';
import 'media_kit_engine.dart';
import 'tracks.dart';

export 'tracks.dart';

/// What to play. Two URLs mean separate video and audio (YouTube DASH): the
/// engine merges them. Headers apply to both requests.
class MediaSpec {
  const MediaSpec({
    required this.videoUrl,
    this.audioUrl,
    this.headers = const <String, String>{},
    this.isLive = false,
    this.startPosition = Duration.zero,
    this.audioChoices = const [],
  });

  final String videoUrl;
  final String? audioUrl;
  final Map<String, String> headers;
  final bool isLive;
  final Duration startPosition;

  /// Other audio streams of the video (YouTube dubs), [audioUrl]'s among
  /// them. Engines ignore this: the app switches by opening a copy with
  /// another choice's url as [audioUrl] (see [withAudio]).
  final List<AudioChoice> audioChoices;

  /// This spec with [url] as the audio, starting at [start].
  MediaSpec withAudio(String url, {Duration? start}) => MediaSpec(
    videoUrl: videoUrl,
    audioUrl: url,
    headers: headers,
    isLive: isLive,
    startPosition: start ?? startPosition,
    audioChoices: audioChoices,
  );

  @override
  String toString() =>
      'MediaSpec(video: $videoUrl, audio: $audioUrl, live: $isLive, start: $startPosition)';
}

/// What the device can decode and show, for picking a YouTube format.
/// Engines report a conservative default until they query the hardware.
class PlaybackCaps {
  const PlaybackCaps({
    this.videoCodecs = const ['vp9', 'h264'],
    this.maxHeight = 1080,
    this.hdr = false,
  });

  /// Hardware-decodable codecs, best first: 'av1', 'vp9', 'h265', 'h264'.
  final List<String> videoCodecs;
  final int maxHeight;
  final bool hdr;
}

/// One player instance. Media3 on Android, media_kit (libmpv) on desktop.
///
/// Streams are broadcast. [position] ticks about 4 times a second while
/// playing. [error] carries human-readable messages.
abstract interface class PlayerEngine {
  /// Picks the engine for this platform.
  static Future<PlayerEngine> create() {
    if (Platform.isAndroid) return AndroidPlayerEngine.create();
    return MediaKitPlayerEngine.create();
  }

  /// Loads [spec] and starts playing.
  Future<void> open(MediaSpec spec);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);

  /// Decoder and display capabilities.
  Future<PlaybackCaps> capabilities();

  Stream<Duration> get position;
  Stream<Duration> get duration;

  /// How far ahead of [position] is loaded (absolute, so >= position).
  Stream<Duration> get buffered;

  /// True when playback reached the end of the media (never for live).
  Stream<bool> get completed;
  Stream<bool> get buffering;
  Stream<bool> get playing;
  Stream<String> get error;

  /// Audio and subtitle tracks of the current media, with the selected ones
  /// marked. Empty after [open] until the engine knows them.
  Stream<MediaTracks> get tracks;

  /// Plays the audio track with this [MediaTrack.id].
  Future<void> selectAudioTrack(String id);

  /// Shows the subtitle track with this id; null turns subtitles off.
  Future<void> selectSubtitleTrack(String? id);

  /// What the next [open] picks by itself. The current media keeps its
  /// tracks; use the select methods for those.
  Future<void> setTrackPreferences(TrackPreferences preferences);

  /// The video surface. Put it in the tree before or after [open].
  Widget get view;

  Future<void> dispose();
}
