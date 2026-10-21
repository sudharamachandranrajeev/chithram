import 'dart:async';

import 'package:chithram_player/chithram_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Spike page for packages/chithram_player (debug builds only, see registry.dart).
///
/// Android CI launches it with intent extras:
/// `--es route /spike/player --es video_url URL [--es audio_url URL]`.
/// Desktop reads `--dart-define=VIDEO_URL=...` / `AUDIO_URL=...`.
/// Keys: select/enter toggles pause, left/right seek by 10 s.
class PlayerSpikePage extends StatefulWidget {
  const PlayerSpikePage({super.key});

  @override
  State<PlayerSpikePage> createState() => _PlayerSpikePageState();
}

class _PlayerSpikePageState extends State<PlayerSpikePage> {
  final _video = TextEditingController(text: const String.fromEnvironment('VIDEO_URL'));
  final _audio = TextEditingController(text: const String.fromEnvironment('AUDIO_URL'));
  final _subs = <StreamSubscription<Object?>>[];

  PlayerEngine? _engine;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _buffering = false;
  bool _playing = false;
  String? _error;
  String _status = 'starting';

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      final engine = await PlayerEngine.create();
      if (!mounted) {
        await engine.dispose();
        return;
      }
      _subs
        ..add(engine.position.listen((v) => _set(() => _position = v)))
        ..add(engine.duration.listen((v) => _set(() => _duration = v)))
        ..add(engine.buffering.listen((v) => _set(() => _buffering = v)))
        ..add(engine.playing.listen((v) => _set(() => _playing = v)))
        ..add(engine.error.listen((v) => _set(() => _error = v)));
      setState(() {
        _engine = engine;
        _status = 'ready';
      });
      final args = await launchArgs();
      final video = args['video_url'];
      if (video != null && video.isNotEmpty) {
        _video.text = video;
        _audio.text = args['audio_url'] ?? '';
      }
      // Wait a frame so the platform view exists, then open.
      await WidgetsBinding.instance.endOfFrame;
      if (_video.text.isNotEmpty) await _open();
    } catch (e) {
      _set(() => _error = '$e');
    }
  }

  void _set(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  Future<void> _open() async {
    final audio = _audio.text.trim();
    final spec = MediaSpec(
      videoUrl: _video.text.trim(),
      audioUrl: audio.isEmpty ? null : audio,
    );
    _set(() {
      _error = null;
      _status = 'opening';
    });
    debugPrint('CHITHRAM_PAGE open $spec');
    await _engine?.open(spec);
    _set(() => _status = 'open');
  }

  Future<void> _toggle() async {
    final engine = _engine;
    if (engine == null) return;
    if (_playing) {
      await engine.pause();
    } else {
      await engine.play();
    }
  }

  Future<void> _seekBy(Duration delta) async {
    final target = _position + delta;
    await _engine?.seek(target < Duration.zero ? Duration.zero : target);
  }

  // A global handler, not a Focus widget: it works whatever has focus (the URL
  // fields, the platform view), which matters with a D-pad.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    debugPrint('CHITHRAM_PAGE key ${key.keyLabel} ${key.debugName}');
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      unawaited(_toggle());
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      unawaited(_seekBy(const Duration(seconds: 10)));
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      unawaited(_seekBy(const Duration(seconds: -10)));
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    unawaited(_engine?.dispose());
    _video.dispose();
    _audio.dispose();
    super.dispose();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
          children: [
            Expanded(
              child: engine == null
                  ? const Center(child: CircularProgressIndicator())
                  : ColoredBox(color: Colors.black, child: engine.view),
            ),
            Container(
              color: const Color(0xFF111111),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_playing ? 'playing' : 'paused'}  ${_fmt(_position)} / ${_fmt(_duration)}'
                    '${_buffering ? '  buffering' : ''}  [$_status]',
                    style: const TextStyle(color: Colors.white),
                  ),
                  if (_error != null)
                    Text('error: $_error', style: const TextStyle(color: Colors.redAccent)),
                  Row(
                    children: [
                      Expanded(child: _field(_video, 'video URL')),
                      const SizedBox(width: 8),
                      Expanded(child: _field(_audio, 'audio URL (optional)')),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: _open, child: const Text('Open')),
                    ],
                  ),
                ],
              ),
            ),
          ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label) => TextField(
        controller: c,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54),
          isDense: true,
        ),
      );
}
