import 'dart:async';

import 'package:chithram_player/chithram_player.dart';
import 'package:flutter/widgets.dart';

/// A [PlayerEngine] that plays nothing and records what it was asked.
class FakeEngine implements PlayerEngine {
  final opened = <MediaSpec>[];
  final seeks = <Duration>[];
  bool isPlaying = false;
  bool disposed = false;

  final positionC = StreamController<Duration>.broadcast();
  final durationC = StreamController<Duration>.broadcast();
  final bufferedC = StreamController<Duration>.broadcast();
  final completedC = StreamController<bool>.broadcast();
  final bufferingC = StreamController<bool>.broadcast();
  final playingC = StreamController<bool>.broadcast();
  final errorC = StreamController<String>.broadcast();
  final tracksC = StreamController<MediaTracks>.broadcast();

  /// What the select methods were asked: 'audio:<id>', 'sub:<id>', 'sub:off'.
  final selections = <String>[];

  /// The preferences handed over before each [open].
  final preferences = <TrackPreferences>[];

  /// The tracks the next [emitTracks] marks selection on.
  MediaTracks current = MediaTracks.none;

  /// Publishes [t] as the media's tracks.
  void emitTracks(MediaTracks t) {
    current = t;
    tracksC.add(t);
  }

  @override
  Future<void> open(MediaSpec spec) async {
    opened.add(spec);
    isPlaying = true;
    playingC.add(true);
  }

  @override
  Future<void> play() async {
    isPlaying = true;
    playingC.add(true);
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    playingC.add(false);
  }

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  @override
  Future<PlaybackCaps> capabilities() async => const PlaybackCaps();

  @override
  Stream<Duration> get position => positionC.stream;
  @override
  Stream<Duration> get duration => durationC.stream;
  @override
  Stream<Duration> get buffered => bufferedC.stream;
  @override
  Stream<bool> get completed => completedC.stream;
  @override
  Stream<bool> get buffering => bufferingC.stream;
  @override
  Stream<bool> get playing => playingC.stream;
  @override
  Stream<String> get error => errorC.stream;

  @override
  Stream<MediaTracks> get tracks => tracksC.stream;

  @override
  Future<void> selectAudioTrack(String id) async {
    selections.add('audio:$id');
    emitTracks(
      MediaTracks(
        audio: [
          for (final t in current.audio) t.copyWith(selected: t.id == id),
        ],
        subtitles: current.subtitles,
      ),
    );
  }

  @override
  Future<void> selectSubtitleTrack(String? id) async {
    selections.add('sub:${id ?? 'off'}');
    emitTracks(
      MediaTracks(
        audio: current.audio,
        subtitles: [
          for (final t in current.subtitles) t.copyWith(selected: t.id == id),
        ],
      ),
    );
  }

  @override
  Future<void> setTrackPreferences(TrackPreferences p) async =>
      preferences.add(p);

  @override
  Widget get view => const SizedBox.expand();

  @override
  Future<void> dispose() async => disposed = true;
}
