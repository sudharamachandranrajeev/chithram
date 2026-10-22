import 'dart:async';

import 'package:chithram_player/chithram_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/redact.dart';
import '../core/resume_store.dart';
import '../core/services.dart';
import '../theme.dart';
import '../ui/common/dims.dart';
import '../ui/tv/focus_card.dart';
import '../ui/common/form_factor.dart';
import '../ui/tv/home_page.dart' show ActionLabel;
import '../ui/common/keys.dart';
import 'play_request.dart';
import 'player_keys.dart';

/// Seek step for Left and Right.
const seekStep = Duration(seconds: 10);

/// Saved positions at or under this are not worth offering.
const resumeMinimum = Duration(seconds: 30);

/// How often the position is saved while playing.
const _saveEvery = Duration(seconds: 10);
const _osdHideAfter = Duration(seconds: 4);

/// Turns an engine error into text for the error panel. Never shows a URL.
String describePlayerError(String raw) {
  final lower = raw.toLowerCase();
  if (lower.contains('drm') || lower.contains('widevine') || lower.contains('playready')) {
    return 'This stream is protected by DRM. Chithram does not play protected streams.';
  }
  return redactText(raw);
}

/// m:ss, or h:mm:ss from one hour.
String formatPlayerTime(Duration d) {
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  if (d.inHours == 0) return '${d.inMinutes}:$s';
  return '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:$s';
}

/// Fullscreen player for any [PlayRequest]: on-screen display that hides
/// itself, seeking, channel zapping, resume and an error panel.
///
/// Center plays or pauses. Left and Right seek by [seekStep] (VOD). Up and Down
/// zap when the request has a [ZapList], otherwise they show the display. Back
/// closes the route, which disposes the engine.
class PlayerRoute extends StatefulWidget {
  const PlayerRoute({super.key, required this.request, this.engineFactory = PlayerEngine.create});

  final PlayRequest request;

  /// The platform engine; tests pass a fake.
  final Future<PlayerEngine> Function() engineFactory;

  @override
  State<PlayerRoute> createState() => _PlayerRouteState();
}

class _PlayerRouteState extends State<PlayerRoute> {
  final _subs = <StreamSubscription<Object?>>[];
  final _promptFocus = FocusNode(debugLabel: 'player prompt');
  final _errorFocus = FocusNode(debugLabel: 'player error');
  ResumeStore? _resume;
  PlayerEngine? _engine;
  late PlayRequest _request = widget.request;
  int _zapIndex = 0;
  StreamSubscription<String>? _statusSub;
  Timer? _hideTimer;
  Timer? _saveTimer;
  int _generation = 0;
  final _closedRequests = Set<PlayRequest>.identity();

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  bool _loading = true;
  bool _osd = true;
  String? _error;
  String? _statusLine;

  /// Set while "Resume from / Start over" is on screen.
  Duration? _offer;
  bool _chromeSet = false;

  @override
  void initState() {
    super.initState();
    _resume = context.getInheritedWidgetOfExactType<AppServicesScope>()?.services.resume;
    _zapIndex = _request.zap?.initialIndex ?? 0;
    _saveTimer = Timer.periodic(_saveEvery, (_) => unawaited(_save()));
    unawaited(_start());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_chromeSet) return;
    _chromeSet = true;
    // A phone plays in landscape with the system bars hidden.
    final isPhone = defaultTargetPlatform == TargetPlatform.android && Dims.of(context).phone;
    if (isPhone) {
      unawaited(SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]));
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    }
    _restoreChrome = isPhone;
  }

  bool _restoreChrome = false;

  Future<void> _start() async {
    try {
      final engine = await widget.engineFactory();
      if (!mounted) {
        await engine.dispose();
        return;
      }
      _subs
        ..add(engine.position.listen((v) => _set(() => _position = v)))
        ..add(engine.duration.listen((v) => _set(() => _duration = v)))
        ..add(engine.buffering.listen((v) => _set(() => _buffering = v)))
        ..add(engine.playing.listen(_onPlaying))
        ..add(engine.error.listen(_onEngineError));
      setState(() => _engine = engine);
      // The video surface must be in the tree before open.
      await WidgetsBinding.instance.endOfFrame;
      await _load(_request, offerResume: true);
    } catch (e) {
      _fail('$e');
    }
  }

  void _set(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  void _onPlaying(bool playing) {
    _set(() => _playing = playing);
    // A paused video keeps its display up.
    if (!playing) {
      _showOsd();
      _hideTimer?.cancel();
    } else {
      _armHide();
    }
  }

  void _onEngineError(String message) {
    if (_error != null) return;
    _fail(message);
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = describePlayerError(message);
      _loading = false;
      _offer = null;
      _osd = true;
    });
    _hideTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _error != null) _errorFocus.requestFocus();
    });
  }

  /// Resolves [request] and opens it. With [offerResume] a saved position over
  /// [resumeMinimum] first asks whether to continue there.
  Future<void> _load(PlayRequest request, {bool offerResume = false, Duration? startAt}) async {
    final generation = ++_generation;
    final engine = _engine;
    if (engine == null) return;
    _set(() {
      _request = request;
      _error = null;
      _loading = true;
      _offer = null;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    _bindStatus(request);
    try {
      final spec = await request.resolve();
      if (!mounted || generation != _generation) return;
      var start = startAt ?? spec.startPosition;
      if (offerResume && startAt == null && !request.isLive && !spec.isLive) {
        final saved = await _resume?.get(request.itemId);
        if (!mounted || generation != _generation) return;
        if (saved != null && saved > resumeMinimum) {
          setState(() {
            _offer = saved;
            _loading = false;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _offer != null) _promptFocus.requestFocus();
          });
          _pendingSpec = spec;
          return;
        }
      }
      await _open(spec, start);
    } catch (e) {
      if (generation == _generation) _fail('$e');
    }
  }

  MediaSpec? _pendingSpec;

  Future<void> _open(MediaSpec spec, Duration start) async {
    final engine = _engine;
    if (engine == null || !mounted) return;
    debugPrint('CHITHRAM_OPEN video=${redactUrl(spec.videoUrl)}');
    final opened = MediaSpec(
      videoUrl: spec.videoUrl,
      audioUrl: spec.audioUrl,
      headers: spec.headers,
      isLive: spec.isLive,
      startPosition: start,
    );
    _set(() {
      _loading = true;
      _offer = null;
    });
    await engine.open(opened);
    _set(() => _loading = false);
    _armHide();
    if (mounted) FocusScope.of(context).requestFocus(_rootFocus);
  }

  final _rootFocus = FocusNode(debugLabel: 'player root');

  void _bindStatus(PlayRequest request) {
    unawaited(_statusSub?.cancel());
    _statusLine = null;
    _statusSub = request.status?.listen((line) => _set(() => _statusLine = line));
  }

  Future<void> _answerOffer(bool resume) async {
    final saved = _offer;
    final spec = _pendingSpec;
    if (saved == null || spec == null) return;
    _pendingSpec = null;
    if (!resume) await _resume?.clear(_request.itemId);
    try {
      await _open(spec, resume ? saved : Duration.zero);
    } catch (e) {
      _fail('$e');
    }
  }

  Future<void> _retry() async {
    final at = _request.isLive ? null : _position;
    await _load(_request, startAt: at != null && at > Duration.zero ? at : null);
  }

  Future<void> _zap(int delta) async {
    final zap = _request.zap ?? widget.request.zap;
    if (zap == null || zap.length < 2) return;
    final next = (_zapIndex + delta) % zap.length;
    _zapIndex = next < 0 ? next + zap.length : next;
    final previous = _request;
    final request = zap.requestAt(_zapIndex);
    await _save();
    unawaited(_closeRequest(previous));
    _showOsd();
    await _load(request.zap == null ? _withZap(request, zap) : request);
  }

  // The request for one channel need not carry the list: keep the first one's.
  PlayRequest _withZap(PlayRequest r, ZapList zap) => PlayRequest(
        itemId: r.itemId,
        title: r.title,
        subtitle: r.subtitle,
        artwork: r.artwork,
        isLive: r.isLive,
        resolve: r.resolve,
        onClose: r.onClose,
        status: r.status,
        zap: zap,
      );

  // Once per request, e.g. stop a torrent.
  Future<void> _closeRequest(PlayRequest r) async {
    if (_closedRequests.add(r)) await r.onClose?.call();
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
    final engine = _engine;
    if (engine == null || _request.isLive) return;
    var to = _position + delta;
    if (to < Duration.zero) to = Duration.zero;
    if (_duration > Duration.zero && to > _duration) to = _duration;
    _set(() => _position = to);
    _showOsd();
    await engine.seek(to);
  }

  void _showOsd() {
    if (!_osd) _set(() => _osd = true);
    _armHide();
  }

  void _armHide() {
    _hideTimer?.cancel();
    if (!_playing || _error != null || _offer != null) return;
    _hideTimer = Timer(_osdHideAfter, () => _set(() => _osd = false));
  }

  Future<void> _save() async {
    final resume = _resume;
    if (resume == null || _request.isLive || _duration <= Duration.zero || _error != null) return;
    if (_offer != null) return;
    // Before the engine has moved there is nothing new to remember.
    if (_position <= Duration.zero) return;
    await resume.put(_request.itemId, _position, _duration);
  }

  @override
  void dispose() {
    _generation++;
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    unawaited(_statusSub?.cancel());
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    final engine = _engine;
    unawaited(() async {
      await _save();
      await engine?.dispose();
      await _closeRequest(_request);
    }());
    if (_restoreChrome) {
      // Back to the launch policy: portrait on a phone, free on a tablet.
      OrientationPolicy.restore();
    }
    _promptFocus.dispose();
    _errorFocus.dispose();
    _rootFocus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    // Buttons on the error panel and the resume prompt use normal focus movement.
    if (_error != null || _offer != null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final fresh = event is KeyDownEvent;
    if (fresh &&
        (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.mediaPlayPause)) {
      _showOsd();
      unawaited(_toggle());
      return KeyEventResult.handled;
    }
    if (fresh && key == LogicalKeyboardKey.mediaPlay) {
      unawaited(_engine?.play());
      return KeyEventResult.handled;
    }
    if (fresh && key == LogicalKeyboardKey.mediaPause) {
      unawaited(_engine?.pause());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.mediaRewind) {
      if (_request.isLive) {
        _showOsd();
      } else {
        unawaited(_seekBy(-seekStep));
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.mediaFastForward) {
      if (_request.isLive) {
        _showOsd();
      } else {
        unawaited(_seekBy(seekStep));
      }
      return KeyEventResult.handled;
    }
    final up = key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.channelUp;
    final down = key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.channelDown;
    if (fresh && (up || down)) {
      if (widget.request.zap != null) {
        unawaited(_zap(up ? -1 : 1));
      } else {
        _showOsd();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    final d = Dims.of(context);
    return Scaffold(
      key: Keys.playerRoot,
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _rootFocus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_error != null || _offer != null) return;
            if (_osd) {
              unawaited(_toggle());
            }
            _showOsd();
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (engine != null) engine.view,
              if (_loading || _buffering)
                Center(
                  child: CircularProgressIndicator(key: PlayerKeys.spinner, color: ChithramColors.accent),
                ),
              _Osd(
                visible: _osd,
                title: _request.title,
                subtitle: _request.subtitle,
                status: _statusLine,
                position: _position,
                duration: _duration,
                live: _request.isLive,
                playing: _playing,
                phone: d.phone,
              ),
              if (_offer != null) _resumePrompt(_offer!),
              if (_error != null) _errorPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resumePrompt(Duration saved) {
    return _Panel(
      title: 'Continue watching?',
      children: [
        FocusCard(
          key: PlayerKeys.resume,
          focusNode: _promptFocus,
          radius: 28,
          onActivate: () => unawaited(_answerOffer(true)),
          child: ActionLabel(icon: Icons.play_arrow_rounded, text: 'Resume from ${formatPlayerTime(saved)}', primary: true),
        ),
        FocusCard(
          key: PlayerKeys.startOver,
          radius: 28,
          onActivate: () => unawaited(_answerOffer(false)),
          child: const ActionLabel(text: 'Start over'),
        ),
      ],
    );
  }

  Widget _errorPanel() {
    return _Panel(
      title: 'Cannot play this',
      message: Text(_error!, key: Keys.playerError, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
      children: [
        FocusCard(
          key: PlayerKeys.retry,
          focusNode: _errorFocus,
          radius: 28,
          onActivate: () => unawaited(_retry()),
          child: const ActionLabel(icon: Icons.refresh_rounded, text: 'Retry', primary: true),
        ),
        FocusCard(
          key: PlayerKeys.back,
          radius: 28,
          onActivate: () => Navigator.of(context).maybePop(),
          child: const ActionLabel(text: 'Back'),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, this.message, required this.children});

  final String title;
  final Widget? message;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: ChithramColors.surface.withValues(alpha: 0.94), borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: TextStyle(fontSize: d.t(20), fontWeight: FontWeight.w700)),
            if (message != null) ...[const SizedBox(height: 12), message!],
            const SizedBox(height: 20),
            Wrap(spacing: 16, runSpacing: 12, alignment: WrapAlignment.center, children: children),
          ],
        ),
      ),
    );
  }
}

/// Title, status line and progress bar. Always in the tree (the position text
/// is what tests read); it only fades.
class _Osd extends StatelessWidget {
  const _Osd({
    required this.visible,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.position,
    required this.duration,
    required this.live,
    required this.playing,
    required this.phone,
  });

  final bool visible;
  final String title;
  final String? subtitle;
  final String? status;
  final Duration position;
  final Duration duration;
  final bool live;
  final bool playing;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final fraction = duration > Duration.zero ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0) : 0.0;
    final line = [if (subtitle != null && subtitle!.isNotEmpty) subtitle!, if (status != null && status!.isNotEmpty) status!].join('  ·  ');
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          alignment: Alignment.bottomCenter,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.center,
              colors: [Color(0xCC000000), Color(0x00000000)],
            ),
          ),
          padding: EdgeInsets.fromLTRB(d.tv ? 64 : 24, 0, d.tv ? 64 : 24, d.tv ? 40 : 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  key: PlayerKeys.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: d.t(22), fontWeight: FontWeight.w700, color: Colors.white)),
              if (line.isNotEmpty)
                Text(line,
                    key: PlayerKeys.status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: d.t(14), color: ChithramColors.textDim)),
              const SizedBox(height: 10),
              if (!live)
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 5,
                    backgroundColor: Colors.white24,
                    color: ChithramColors.accent,
                  ),
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(playing ? Icons.play_arrow_rounded : Icons.pause_rounded, color: Colors.white70, size: d.t(20)),
                  const SizedBox(width: 8),
                  Text(formatPlayerTime(position),
                      key: Keys.playerPosition, style: TextStyle(color: Colors.white70, fontSize: d.t(14))),
                  if (live)
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text('LIVE',
                          style: TextStyle(color: ChithramColors.accent, fontSize: d.t(14), fontWeight: FontWeight.w700)),
                    )
                  else if (duration > Duration.zero)
                    Text(' / ${formatPlayerTime(duration)}',
                        key: PlayerKeys.duration, style: TextStyle(color: Colors.white38, fontSize: d.t(14))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
