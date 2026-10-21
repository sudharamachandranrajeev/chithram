import 'dart:async';

import 'package:chithram_player/chithram_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/redact.dart';
import '../ui/keys.dart';
import 'play_request.dart';

/// Fullscreen player. Stub: the video, a play/pause toggle on Select, and Back
/// to close. The on-screen display, seeking, zapping and resume come with the
/// player work package.
class PlayerRoute extends StatefulWidget {
  const PlayerRoute({super.key, required this.request});

  final PlayRequest request;

  @override
  State<PlayerRoute> createState() => _PlayerRouteState();
}

class _PlayerRouteState extends State<PlayerRoute> {
  final _subs = <StreamSubscription<Object?>>[];
  PlayerEngine? _engine;
  Duration _position = Duration.zero;
  bool _playing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final engine = await PlayerEngine.create();
      if (!mounted) {
        await engine.dispose();
        return;
      }
      _subs
        ..add(engine.position.listen((v) => _set(() => _position = v)))
        ..add(engine.playing.listen((v) => _set(() => _playing = v)))
        ..add(engine.error.listen((v) => _set(() => _error = v)));
      setState(() => _engine = engine);
      // The video surface must be in the tree before open.
      await WidgetsBinding.instance.endOfFrame;
      final spec = await widget.request.resolve();
      debugPrint('CHITHRAM_OPEN video=${redactUrl(spec.videoUrl)}');
      if (mounted) await engine.open(spec);
    } catch (e) {
      _set(() => _error = '$e');
    }
  }

  void _set(VoidCallback fn) {
    if (mounted) setState(fn);
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

  @override
  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    unawaited(_engine?.dispose());
    unawaited(widget.request.onClose?.call());
    super.dispose();
  }

  static String _fmt(Duration d) {
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    if (d.inHours == 0) return '${d.inMinutes}:$s';
    return '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:$s';
  }

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    return Scaffold(
      key: Keys.playerRoot,
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter ||
              key == LogicalKeyboardKey.mediaPlayPause) {
            unawaited(_toggle());
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (engine != null) engine.view else const Center(child: CircularProgressIndicator()),
            Positioned(
              left: 24,
              bottom: 16,
              child: Text(
                _fmt(_position),
                key: Keys.playerPosition,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            if (_error != null)
              Center(
                child: Text(_error!, key: Keys.playerError, style: const TextStyle(color: Colors.redAccent)),
              ),
          ],
        ),
      ),
    );
  }
}
