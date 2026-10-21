import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'player_engine.dart';

/// libmpv through media_kit (Windows, Linux).
///
/// Separate audio (YouTube DASH) is attached with mpv's `audio-add` command.
/// Setting the `audio-files` option would split the URL at its `:` characters
/// (mpv's list separator on Unix), so the command is the safe route.
class MediaKitPlayerEngine implements PlayerEngine {
  MediaKitPlayerEngine._() {
    _player = Player();
    _controller = VideoController(_player);
  }

  static Future<MediaKitPlayerEngine> create() async {
    MediaKit.ensureInitialized();
    final engine = MediaKitPlayerEngine._();
    return engine;
  }

  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<Duration>? _audioWait;
  bool _aoApplied = false;

  @override
  Future<void> open(MediaSpec spec) async {
    await _audioWait?.cancel();
    _audioWait = null;
    // Set here, not in create(): mpv property writes wait for the video
    // controller, which only initialises once [view] is in the widget tree.
    // CI has no sound card: CHITHRAM_MPV_AO=null routes audio to the null output.
    final ao = Platform.environment['CHITHRAM_MPV_AO'];
    if (!_aoApplied && ao != null && ao.isNotEmpty) {
      _aoApplied = true;
      await (_player.platform as NativePlayer).setProperty('ao', ao);
    }
    final audio = spec.audioUrl;
    await _player.open(
      Media(
        spec.videoUrl,
        httpHeaders: spec.headers.isEmpty ? null : spec.headers,
        start: spec.startPosition == Duration.zero ? null : spec.startPosition,
      ),
      play: audio == null,
    );
    if (audio == null) return;
    // The file must be loaded before audio-add; the duration stream firing
    // with a real value is the signal.
    final loaded = Completer<void>();
    _audioWait = _player.stream.duration.listen((d) {
      if (d > Duration.zero && !loaded.isCompleted) loaded.complete();
    });
    if (_player.state.duration > Duration.zero && !loaded.isCompleted) {
      loaded.complete();
    }
    await loaded.future.timeout(const Duration(seconds: 20));
    await (_player.platform as NativePlayer)
        .command(<String>['audio-add', audio, 'select']);
    await _player.play();
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Stream<Duration> get position => _player.stream.position;
  @override
  Stream<Duration> get duration => _player.stream.duration;
  @override
  Stream<bool> get buffering => _player.stream.buffering;
  @override
  Stream<bool> get playing => _player.stream.playing;
  @override
  Stream<String> get error => _player.stream.error;

  @override
  Widget get view => Video(controller: _controller, controls: NoVideoControls);

  @override
  Future<PlaybackCaps> capabilities() async => const PlaybackCaps();

  @override
  Future<void> dispose() async {
    await _audioWait?.cancel();
    await _player.dispose();
  }
}
