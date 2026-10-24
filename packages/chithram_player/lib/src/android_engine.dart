import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'player_engine.dart';

/// Media3's MIME type for subtitles it parsed while extracting; the original
/// format is then in `codecs`.
const _parsedCues = 'application/x-media3-cues';

/// One track map from the `tracks` event (see PlayerHost.kt).
MediaTrack androidTrack(Map<Object?, Object?> m) {
  final mime = m['mime'] as String?;
  final codecs = m['codecs'] as String?;
  return MediaTrack(
    id: m['id'] as String,
    language: normalizeLanguage(m['lang'] as String?),
    label: m['label'] as String?,
    codec: shortCodec(mime == _parsedCues ? codecs : (mime ?? codecs)),
    channels: (m['ch'] as num?)?.toInt(),
    selected: m['sel'] as bool? ?? false,
    isDefault: m['def'] as bool? ?? false,
    forced: m['forced'] as bool? ?? false,
  );
}

/// The `tracks` event as [MediaTracks].
MediaTracks androidTracks(Map<Object?, Object?> event) {
  List<MediaTrack> list(Object? raw) => [
    for (final t in (raw as List?) ?? const [])
      if (t is Map) androidTrack(t),
  ];
  return MediaTracks(
    audio: list(event['audio']),
    subtitles: list(event['text']),
  );
}

/// Media3 ExoPlayer behind a method channel. Video renders into a SurfaceView
/// hosted by a Hybrid Composition PlatformView (see [view]).
class AndroidPlayerEngine implements PlayerEngine {
  AndroidPlayerEngine._(this._id);

  static const MethodChannel _methods = MethodChannel(
    'chithram_player/methods',
  );
  static const String viewType = 'chithram_player/surface';

  static Future<AndroidPlayerEngine> create() async {
    final id = await _methods.invokeMethod<int>('create');
    if (id == null) throw StateError('chithram_player: create returned null');
    final engine = AndroidPlayerEngine._(id);
    engine._sub = EventChannel('chithram_player/events/$id')
        .receiveBroadcastStream()
        .listen(engine._onEvent, onError: engine._onStreamError);
    return engine;
  }

  final int _id;
  StreamSubscription<dynamic>? _sub;
  bool _disposed = false;

  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _buffered = StreamController<Duration>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _error = StreamController<String>.broadcast();
  final _tracks = StreamController<MediaTracks>.broadcast();

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    switch (event['t']) {
      case 'state':
        _position.add(Duration(milliseconds: (event['pos'] as num).toInt()));
        _duration.add(Duration(milliseconds: (event['dur'] as num).toInt()));
        _buffered.add(
          Duration(milliseconds: (event['buf'] as num? ?? 0).toInt()),
        );
        _completed.add(event['ended'] as bool? ?? false);
        _buffering.add(event['buffering'] as bool);
        _playing.add(event['playing'] as bool);
      case 'tracks':
        _tracks.add(androidTracks(event));
      case 'error':
        _error.add(event['message'] as String);
    }
  }

  void _onStreamError(Object e) => _error.add('$e');

  Future<void> _call(String method, [Map<String, Object?> args = const {}]) =>
      _methods.invokeMethod<void>(method, <String, Object?>{
        'id': _id,
        ...args,
      });

  @override
  Future<void> open(MediaSpec spec) => _call('open', {
    'videoUrl': spec.videoUrl,
    'audioUrl': spec.audioUrl,
    'headers': spec.headers,
    'isLive': spec.isLive,
    'startMs': spec.startPosition.inMilliseconds,
  });

  @override
  Future<void> play() => _call('play');

  @override
  Future<void> pause() => _call('pause');

  @override
  Future<void> seek(Duration position) =>
      _call('seek', {'positionMs': position.inMilliseconds});

  @override
  Stream<Duration> get position => _position.stream;
  @override
  Stream<Duration> get duration => _duration.stream;
  @override
  Stream<Duration> get buffered => _buffered.stream;
  @override
  Stream<bool> get completed => _completed.stream.distinct();
  @override
  Stream<bool> get buffering => _buffering.stream;
  @override
  Stream<bool> get playing => _playing.stream;
  @override
  Stream<String> get error => _error.stream;
  @override
  Stream<MediaTracks> get tracks => _tracks.stream;

  @override
  Future<void> selectAudioTrack(String id) =>
      _call('selectTrack', {'kind': 'audio', 'trackId': id});

  @override
  Future<void> selectSubtitleTrack(String? id) =>
      _call('selectTrack', {'kind': 'text', 'trackId': id});

  @override
  Future<void> setTrackPreferences(TrackPreferences p) =>
      _call('trackPreferences', {
        'audioLanguage': p.audioLanguage,
        'textLanguage': p.subtitleLanguage,
        'text': p.subtitles,
      });

  /// Hybrid Composition (always), not TLHC: the Android view is composed in the
  /// real view hierarchy, so a SurfaceView keeps its own hardware layer. That is
  /// what later tunneling, HDR and Surface.setFrameRate need. TLHC would render
  /// the SurfaceView into a Flutter texture and Flutter falls back to HC for it
  /// anyway, so we ask for HC outright.
  @override
  Widget get view => PlatformViewLink(
    viewType: viewType,
    surfaceFactory: (context, controller) => AndroidViewSurface(
      controller: controller as AndroidViewController,
      gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
    ),
    onCreatePlatformView: (params) {
      return PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: viewType,
          layoutDirection: TextDirection.ltr,
          creationParams: <String, Object?>{'playerId': _id},
          creationParamsCodec: const StandardMessageCodec(),
        )
        ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
        ..create();
    },
  );

  @override
  Future<PlaybackCaps> capabilities() async {
    try {
      final m = await _methods.invokeMapMethod<String, Object?>('capabilities');
      if (m == null) return const PlaybackCaps();
      return PlaybackCaps(
        videoCodecs:
            (m['videoCodecs'] as List?)?.cast<String>() ?? const ['h264'],
        maxHeight: (m['maxHeight'] as num?)?.toInt() ?? 1080,
        hdr: m['hdr'] as bool? ?? false,
      );
    } catch (e) {
      debugPrint('chithram_player: capabilities failed: $e');
      return const PlaybackCaps();
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _sub?.cancel();
    try {
      await _call('dispose');
    } catch (e) {
      debugPrint('chithram_player: dispose failed: $e');
    }
    await Future.wait([
      _position.close(),
      _duration.close(),
      _buffering.close(),
      _buffered.close(),
      _completed.close(),
      _playing.close(),
      _error.close(),
      _tracks.close(),
    ]);
  }
}
