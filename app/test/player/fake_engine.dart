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
  final bufferingC = StreamController<bool>.broadcast();
  final playingC = StreamController<bool>.broadcast();
  final errorC = StreamController<String>.broadcast();

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
  Stream<bool> get buffering => bufferingC.stream;
  @override
  Stream<bool> get playing => playingC.stream;
  @override
  Stream<String> get error => errorC.stream;

  @override
  Widget get view => const SizedBox.expand();

  @override
  Future<void> dispose() async => disposed = true;
}
