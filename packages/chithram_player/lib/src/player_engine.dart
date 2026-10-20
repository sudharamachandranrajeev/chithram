import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

import 'android_engine.dart';
import 'media_kit_engine.dart';

/// What to play. Two URLs mean separate video and audio (YouTube DASH): the
/// engine merges them. Headers apply to both requests.
class MediaSpec {
  const MediaSpec({
    required this.videoUrl,
    this.audioUrl,
    this.headers = const <String, String>{},
    this.isLive = false,
    this.startPosition = Duration.zero,
  });

  final String videoUrl;
  final String? audioUrl;
  final Map<String, String> headers;
  final bool isLive;
  final Duration startPosition;

  @override
  String toString() =>
      'MediaSpec(video: $videoUrl, audio: $audioUrl, live: $isLive, start: $startPosition)';
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

  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<bool> get buffering;
  Stream<bool> get playing;
  Stream<String> get error;

  /// The video surface. Put it in the tree before or after [open].
  Widget get view;

  Future<void> dispose();
}
