import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'player_engine.dart';

/// Headers for libmpv. `Range` is dropped: ffmpeg's http protocol sends no
/// Range header of its own when the user headers contain one, so every seek
/// would re-request from byte 0. mpv asks for ranges itself.
Map<String, String> mpvHeaders(Map<String, String> headers) => {
  for (final e in headers.entries)
    if (e.key.toLowerCase() != 'range') e.key: e.value,
};

/// False for log lines media_kit reports as errors that playback survives.
/// "Could not open codec." is mpv's decoder log when a hardware decoder (VA-API,
/// VDPAU, ...) fails to start; it then falls back to software and plays on.
/// Showing it would put an error panel over a working video. A decoder that
/// fails for real is also reported as a failed file load, which still arrives.
bool isFatalMpvError(String text) => !text.startsWith('Could not open codec');

/// A real mpv track id ("1", "2"); null for "no", "auto" and the like.
String? mpvTrackId(String? value) =>
    value != null && int.tryParse(value) != null ? value : null;

/// media_kit's track lists as [MediaTracks]. Its lists start with the "auto"
/// and "no" pseudo-tracks; those are dropped. [aid] and [sid] are mpv's
/// selected ids.
MediaTracks mpvTracks(Tracks tracks, {String? aid, String? sid}) {
  MediaTrack convert(
    String id,
    String? title,
    String? language,
    String? codec,
    int? channels,
    bool? isDefault,
    String selected,
  ) => MediaTrack(
    id: id,
    language: normalizeLanguage(language),
    label: title,
    codec: shortCodec(codec),
    channels: channels,
    selected: id == selected,
    isDefault: isDefault ?? false,
  );
  return MediaTracks(
    audio: [
      for (final t in tracks.audio)
        if (mpvTrackId(t.id) != null)
          convert(
            t.id,
            t.title,
            t.language,
            t.codec,
            t.audiochannels ?? t.channelscount,
            t.isDefault,
            aid ?? '',
          ),
    ],
    subtitles: [
      for (final t in tracks.subtitle)
        if (mpvTrackId(t.id) != null)
          convert(
            t.id,
            t.title,
            t.language,
            t.codec,
            null,
            t.isDefault,
            sid ?? '',
          ),
    ],
  );
}

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
  bool _observing = false;
  TrackPreferences _prefs = const TrackPreferences();
  String? _aid, _sid;
  final _tracks = StreamController<MediaTracks>.broadcast();
  StreamSubscription<Tracks>? _trackSub;

  NativePlayer get _native => _player.platform as NativePlayer;

  void _emitTracks() {
    if (!_tracks.isClosed) {
      _tracks.add(mpvTracks(_player.state.tracks, aid: _aid, sid: _sid));
    }
  }

  /// mpv's `aid` and `sid` read back the track it actually chose.
  Future<void> _observeSelection() async {
    if (_observing) return;
    _observing = true;
    _trackSub = _player.stream.tracks.listen((_) => _emitTracks());
    await _native.observeProperty('aid', (v) async {
      _aid = mpvTrackId(v);
      _emitTracks();
    });
    await _native.observeProperty('sid', (v) async {
      _sid = mpvTrackId(v);
      _emitTracks();
    });
  }

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
      await _native.setProperty('ao', ao);
    }
    await _observeSelection();
    // Options for the file about to load: languages, and subtitles on or
    // off. A track picked by hand on the last file must not carry over.
    await _native.setProperty('alang', _prefs.audioLanguage ?? '');
    await _native.setProperty('slang', _prefs.subtitleLanguage ?? '');
    await _native.setProperty('aid', 'auto');
    await _native.setProperty('sid', _prefs.subtitles ? 'auto' : 'no');
    final audio = spec.audioUrl;
    await _player.open(
      Media(
        spec.videoUrl,
        httpHeaders: mpvHeaders(spec.headers).isEmpty
            ? null
            : mpvHeaders(spec.headers),
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
    await _native.command(<String>['audio-add', audio, 'select']);
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
  Stream<Duration> get buffered => _player.stream.buffer;
  @override
  Stream<bool> get completed => _player.stream.completed;
  @override
  Stream<bool> get buffering => _player.stream.buffering;
  @override
  Stream<bool> get playing => _player.stream.playing;
  @override
  Stream<String> get error => _player.stream.error.where(isFatalMpvError);

  @override
  Stream<MediaTracks> get tracks => _tracks.stream;

  @override
  Future<void> selectAudioTrack(String id) => _native.setProperty('aid', id);

  @override
  Future<void> selectSubtitleTrack(String? id) =>
      _native.setProperty('sid', id ?? 'no');

  @override
  Future<void> setTrackPreferences(TrackPreferences preferences) async =>
      _prefs = preferences;

  @override
  Widget get view => Video(controller: _controller, controls: NoVideoControls);

  @override
  Future<PlaybackCaps> capabilities() async => const PlaybackCaps();

  @override
  Future<void> dispose() async {
    await _audioWait?.cancel();
    await _trackSub?.cancel();
    await _tracks.close();
    await _player.dispose();
  }
}
