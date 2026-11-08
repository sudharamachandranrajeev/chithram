import 'dart:async';

import 'package:chithram_player/chithram_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/prefs.dart';
import '../core/redact.dart';
import '../core/resume_store.dart';
import '../core/services.dart';
import '../theme.dart';
import '../ui/common/dims.dart';
import '../ui/tv/focus_card.dart';
import '../ui/common/form_factor.dart';
import '../ui/tv/home_page.dart' show ActionLabel;
import '../ui/common/keys.dart';
import '../ui/desktop/window_chrome.dart';
import 'play_request.dart';
import 'player_keys.dart';
import 'player_osd.dart';
import 'seek/double_tap_ripple.dart';
import 'seek/scrub.dart';
import 'seek/storyboard_thumb.dart';
import 'speed_menu.dart';
import 'tracks.dart';
import 'tracks_menu.dart';
import 'up_next_card.dart';

/// Seek step for the 10 s buttons, J and L, and a phone's double tap.
const seekStep = Duration(seconds: 10);

/// Saved positions at or under this are not worth offering.
const resumeMinimum = Duration(seconds: 30);

/// How often the position is saved while playing.
const _saveEvery = Duration(seconds: 10);

/// Idle time before the display fades out during playback.
const osdHideAfter = Duration(seconds: 4);

/// Turns an engine error into text for the error panel. Never shows a URL.
String describePlayerError(String raw) {
  final lower = raw.toLowerCase();
  if (lower.contains('drm') ||
      lower.contains('widevine') ||
      lower.contains('playready')) {
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
/// itself, seeking, channel zapping, resume, audio and subtitle tracks and an
/// error panel.
///
/// The display shows on any key, touch or mouse move and fades out after
/// [osdHideAfter] of playback without input. It stays while paused and while
/// a scrub, the track menu or the Up next card is open. When it is hidden,
/// the arrow or OK press that brings it back does nothing else; media keys
/// (play/pause, rewind, next, channel up/down) always act.
///
/// Center plays or pauses. Left and Right scrub (VOD, live with a DVR window):
/// a preview position moves, faster the longer the key is held, and OK or a
/// pause commits it; Back drops it. Up and Down zap when the request has a
/// [ZapList]; otherwise Up reaches the top bar (Back, speed, tracks) and Down
/// the middle row (previous, -10 s, play, +10 s, next); on the buttons Left
/// and Right move along the row and Up/Down move between rows and the video.
/// Menu, Info or Settings opens the track menu; on a live channel without a
/// seek bar Left and Right reach it too. When a video with a queue ends, an
/// "Up next" card counts down to the next one. Back closes the route, which
/// disposes the engine.
///
/// Desktop keys: Esc leaves fullscreen, else closes (after dropping a menu or
/// scrub, like Back); Space or K plays/pauses; J and L seek 10 s; F toggles
/// fullscreen; M mutes; Up and Down change the volume.
class PlayerRoute extends StatefulWidget {
  const PlayerRoute({
    super.key,
    required this.request,
    this.engineFactory = PlayerEngine.create,
    this.sheetProvider = networkSheet,
    this.chrome,
  });

  final PlayRequest request;

  /// The desktop window, for fullscreen and the window buttons;
  /// [WindowChrome.instance] when null (tests pass a fake).
  final WindowChrome? chrome;

  /// Loads preview sprite sheets; tests pass a fake.
  final SheetProvider sheetProvider;

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
  Prefs? _prefs;
  PlayerEngine? _engine;
  late PlayRequest _request = widget.request;
  int _zapIndex = 0;
  StreamSubscription<String>? _statusSub;
  Timer? _hideTimer;
  Timer? _saveTimer;
  int _generation = 0;
  final _closedRequests = Set<PlayRequest>.identity();

  late final Scrubber _scrubber = Scrubber(onCommit: _commitScrub)
    ..addListener(_scrubChanged);
  final _previousFocus = FocusNode(debugLabel: 'player previous');
  final _nextFocus = FocusNode(debugLabel: 'player next');
  final _tracksFocus = FocusNode(debugLabel: 'player tracks');
  final _backFocus = FocusNode(debugLabel: 'player back');
  final _speedFocus = FocusNode(debugLabel: 'player speed');
  final _fullscreenFocus = FocusNode(debugLabel: 'player fullscreen');
  final _rewindFocus = FocusNode(debugLabel: 'player rewind');
  final _playFocus = FocusNode(debugLabel: 'player play');
  final _forwardFocus = FocusNode(debugLabel: 'player forward');

  // Speed is kept while the player is open (next item too); volume is saved.
  double _speed = 1;
  double _volume = 1;
  bool _muted = false;

  /// The player made the window fullscreen; leaving the player undoes it.
  bool _enteredFullscreen = false;
  final _rippleKey = GlobalKey<DoubleTapRippleState>();
  PlayExtras _extras = PlayExtras.none;
  PlayRequest? _extrasFor;

  // Up next: prepared ~30 s before the end, shown when it ends.
  PlayRequest? _upNext;
  bool _upNextShown = false;
  bool _upNextDeclined = false;
  bool _prefetched = false;
  bool _finished = false;
  Offset? _doubleTapAt;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  bool _loading = true;
  bool _osd = true;
  String? _error;
  String? _statusLine;

  // Tracks of the current item. The preferred audio and subtitles are picked
  // once per item, when the first tracks arrive.
  MediaTracks _tracks = MediaTracks.none;
  MediaSpec? _spec;
  bool _audioPicked = false;
  bool _subsPicked = false;
  _Menu? _menu;
  bool get _menuOpen => _menu != null;

  /// The key that brought the display back; it does nothing else until up.
  LogicalKeyboardKey? _wakeKey;

  /// Set while "Resume from / Start over" is on screen.
  Duration? _offer;
  bool _chromeSet = false;

  @override
  void initState() {
    super.initState();
    final services = context
        .getInheritedWidgetOfExactType<AppServicesScope>()
        ?.services;
    _resume = services?.resume;
    _prefs = services?.prefs;
    _volume = ((_prefs?.getInt(PlayerPrefs.volume) ?? 100) / 100).clamp(0.0, 1.0);
    _zapIndex = _request.zap?.initialIndex ?? 0;
    _saveTimer = Timer.periodic(_saveEvery, (_) => unawaited(_save()));
    _chrome.fullscreen.addListener(_fullscreenChanged);
    unawaited(_start());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_chromeSet) return;
    _chromeSet = true;
    // A phone plays in landscape with the system bars hidden.
    final isPhone =
        defaultTargetPlatform == TargetPlatform.android &&
        Dims.of(context).phone;
    if (isPhone) {
      unawaited(
        SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]),
      );
      unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
      );
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
        ..add(engine.position.listen(_onPosition))
        ..add(engine.duration.listen(_onDuration))
        ..add(engine.buffered.listen((v) => _set(() => _buffered = v)))
        ..add(engine.completed.listen(_onCompleted))
        ..add(engine.buffering.listen((v) => _set(() => _buffering = v)))
        ..add(engine.playing.listen(_onPlaying))
        ..add(engine.error.listen(_onEngineError))
        ..add(engine.tracks.listen(_onTracks));
      setState(() => _engine = engine);
      if (engine is PlayerTuning) unawaited((engine as PlayerTuning).setVolume(_volume));
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

  void _scrubChanged() {
    if (!mounted) return;
    if (_scrubber.active) {
      _hideTimer?.cancel();
      if (!_osd) _osd = true;
    } else {
      _armHide();
    }
    setState(() {});
  }

  void _onPosition(Duration v) {
    _set(() => _position = v);
    _prefetchNext();
  }

  void _onDuration(Duration v) {
    _set(() => _duration = v);
    _loadExtras();
    _prefetchNext();
  }

  /// Chapters, preview frames and the like, once the length is known.
  void _loadExtras() {
    final request = _request;
    final load = request.extras;
    if (load == null ||
        _duration <= Duration.zero ||
        identical(_extrasFor, request))
      return;
    _extrasFor = request;
    final generation = _generation;
    load(_duration).then((x) {
      if (mounted && generation == _generation && identical(request, _request))
        setState(() => _extras = x);
    }, onError: (Object _) {});
  }

  bool get _hasQueue => _request.queue != null && !_request.isLive;

  /// About 30 s before the end, picks what plays next so the card is instant.
  void _prefetchNext() {
    final queue = _request.queue;
    if (queue == null || _prefetched || _request.isLive || !queue.autoplay)
      return;
    if (_duration <= Duration.zero || _duration - _position > upNextLead)
      return;
    _prefetched = true;
    final request = _request, generation = _generation;
    queue.prepareNext().then((next) {
      if (mounted && generation == _generation && identical(request, _request))
        _upNext = next;
    }, onError: (Object _) {});
  }

  Future<void> _onCompleted(bool done) async {
    if (!done) {
      _upNextDeclined = false;
      _finished = false;
      return;
    }
    if (_request.isLive || _error != null || _offer != null || _finished)
      return;
    _finished = true;
    // Watched to the end: nothing to resume.
    unawaited(_resume?.clear(_request.itemId));
    final queue = _request.queue;
    if (queue == null || !queue.autoplay || _upNextDeclined) {
      _showOsd();
      return;
    }
    final request = _request, generation = _generation;
    var next = _upNext;
    next ??= await queue.prepareNext();
    if (!mounted ||
        generation != _generation ||
        !identical(request, _request) ||
        next == null)
      return;
    setState(() {
      _upNext = next;
      _upNextShown = true;
    });
  }

  void _cancelUpNext() {
    if (!_upNextShown) return;
    setState(() {
      _upNextShown = false;
      _upNextDeclined = true;
    });
    _rootFocus.requestFocus();
    _showOsd();
  }

  /// Plays what the queue has next (Up next, the Next button).
  Future<void> _playNext() async {
    final queue = _request.queue;
    if (queue == null) return;
    if (_upNext == null) await queue.prepareNext();
    if (!mounted) return;
    final next = queue.takeNext();
    if (next != null) await _moveTo(next);
  }

  Future<void> _playPrevious() async {
    final previous = _request.queue?.takePrevious();
    if (previous != null) await _moveTo(previous);
  }

  Future<void> _moveTo(PlayRequest next) async {
    final previous = _request;
    _set(() => _upNextShown = false);
    await _save();
    unawaited(_closeRequest(previous));
    _showOsd();
    if (mounted) _rootFocus.requestFocus();
    await _load(next);
  }

  void _commitScrub(Duration to) {
    final engine = _engine;
    if (engine == null) return;
    // Close to the live edge means the edge.
    if (_request.isLive &&
        _duration > Duration.zero &&
        _duration - to <= const Duration(seconds: 10)) {
      to = _duration;
    }
    _set(() => _position = to);
    _showOsd();
    unawaited(engine.seek(to));
  }

  bool get _canScrub => !_request.isLive || _duration >= dvrMinimum;

  void _onPlaying(bool playing) {
    // Media3 repeats the state four times a second; only a change counts,
    // or the hide timer would restart forever.
    if (playing == _playing) return;
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
  Future<void> _load(
    PlayRequest request, {
    bool offerResume = false,
    Duration? startAt,
  }) async {
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
      _buffered = Duration.zero;
      _extras = PlayExtras.none;
      _upNext = null;
      _upNextShown = false;
      _upNextDeclined = false;
      _prefetched = false;
      _finished = false;
      _menu = null;
      _tracks = MediaTracks.none;
    });
    _extrasFor = null;
    _scrubber.cancel();
    _bindStatus(request);
    try {
      final spec = _preferAudio(await request.resolve());
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
      audioChoices: spec.audioChoices,
    );
    _set(() {
      _loading = true;
      _offer = null;
      _spec = opened;
      _tracks = MediaTracks.none;
    });
    _audioPicked = false;
    _subsPicked = false;
    await engine.setTrackPreferences(PlayerPrefs.read(_prefs));
    // Live has no speed control: always 1x.
    await _tuning?.setSpeed(spec.isLive || _request.isLive ? 1 : _speed);
    await engine.open(opened);
    _set(() => _loading = false);
    _armHide();
    if (mounted) FocusScope.of(context).requestFocus(_rootFocus);
  }

  final _rootFocus = FocusNode(debugLabel: 'player root');

  void _bindStatus(PlayRequest request) {
    unawaited(_statusSub?.cancel());
    _statusLine = null;
    _statusSub = request.status?.listen(
      (line) => _set(() => _statusLine = line),
    );
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
    await _load(
      _request,
      startAt: at != null && at > Duration.zero ? at : null,
    );
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
    onWatched: r.onWatched,
    status: r.status,
    zap: zap,
    extras: r.extras,
    queue: r.queue,
  );

  // Once per request, e.g. stop a torrent. Reads the position before the
  // first await: a zap resets it right after.
  Future<void> _closeRequest(PlayRequest r) async {
    if (!_closedRequests.add(r)) return;
    if (_error == null)
      r.onWatched?.call(_position, r.isLive ? Duration.zero : _duration);
    await r.onClose?.call();
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
    if (engine == null || !_canScrub) return;
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
    if (!_playing || _error != null || _offer != null || _scrubber.active)
      return;
    if (_menuOpen || _upNextShown || _controlsFocused) return;
    _hideTimer = Timer(osdHideAfter, () => _set(() => _osd = false));
  }

  PlayerTuning? get _tuning {
    final engine = _engine;
    return engine is PlayerTuning ? engine as PlayerTuning : null;
  }

  WindowChrome get _chrome => widget.chrome ?? WindowChrome.instance;

  bool get _desktop => Dims.of(context).desktop;

  bool get _speedShown => _tuning != null && !_request.isLive;

  // The native frame (Linux) cannot go fullscreen from here.
  bool get _fullscreenShown => _desktop && _chrome.custom;

  /// The top bar's buttons, left to right, as the OSD shows them.
  List<FocusNode> get _topNodes => [
    _backFocus,
    if (_speedShown) _speedFocus,
    if (_hasTrackChoice) _tracksFocus,
    if (_fullscreenShown) _fullscreenFocus,
  ];

  /// The middle row, left to right.
  List<FocusNode> get _centreNodes {
    final queue = _hasQueue ? _request.queue : null;
    return [
      if (queue != null && queue.hasPrevious) _previousFocus,
      if (_canScrub) _rewindFocus,
      _playFocus,
      if (_canScrub) _forwardFocus,
      if (queue != null) _nextFocus,
    ];
  }

  bool get _controlsFocused =>
      _topNodes.any((n) => n.hasFocus) || _centreNodes.any((n) => n.hasFocus);

  /// Up from the video: tracks, else speed, else Back.
  void _focusTop() {
    (_hasTrackChoice ? _tracksFocus : (_speedShown ? _speedFocus : _backFocus)).requestFocus();
  }

  // --- Desktop: fullscreen, volume ---

  // F11, the window's own controls or this player: the button's icon follows.
  void _fullscreenChanged() => _set(() {});

  Future<void> _toggleFullscreen() async {
    if (!_fullscreenShown) return;
    _enteredFullscreen = !_chrome.fullscreen.value;
    _showOsd();
    await _chrome.toggleFullscreen().catchError((Object _) {});
  }

  void _setVolume(double v) {
    final tuning = _tuning;
    if (tuning == null) return;
    _set(() {
      _volume = v;
      _muted = false;
    });
    unawaited(tuning.setVolume(v));
    unawaited(_prefs?.set(PlayerPrefs.volume, (v * 100).round()));
    _showOsd();
  }

  void _toggleMute() {
    final tuning = _tuning;
    if (tuning == null) return;
    _set(() => _muted = !_muted);
    unawaited(tuning.setVolume(_muted ? 0 : _volume));
    _showOsd();
  }

  /// Esc: like Back, but a fullscreen window comes out of fullscreen first.
  void _escape() {
    if (!_menuOpen &&
        !_scrubber.active &&
        !_upNextShown &&
        _fullscreenShown &&
        _chrome.fullscreen.value) {
      unawaited(_toggleFullscreen());
      return;
    }
    unawaited(Navigator.of(context).maybePop());
  }

  // --- Tracks ---

  /// The audio entries: YouTube's dubs when the source has them (the engine
  /// only sees the one playing), else the engine's tracks.
  List<MediaTrack> get _audioItems {
    final spec = _spec;
    if (spec != null && spec.audioChoices.length > 1) return choiceTracks(spec);
    return _tracks.audio;
  }

  bool get _hasTrackChoice =>
      _audioItems.length > 1 || _tracks.subtitles.isNotEmpty;

  /// A dubbed YouTube video starts in the preferred language when it has it.
  MediaSpec _preferAudio(MediaSpec spec) {
    final want = PlayerPrefs.read(_prefs).audioLanguage;
    if (want == null || spec.audioChoices.length < 2) return spec;
    for (final c in spec.audioChoices) {
      if (c.language == want) {
        return c.url == spec.audioUrl ? spec : spec.withAudio(c.url);
      }
    }
    return spec;
  }

  void _onTracks(MediaTracks t) {
    _set(() => _tracks = t);
    final engine = _engine;
    if (engine == null) return;
    // The engine already prefers these; this covers what it cannot match
    // (subtitles on with no language, three-letter codes, no default flag).
    final prefs = PlayerPrefs.read(_prefs);
    if (!_audioPicked && t.audio.isNotEmpty) {
      _audioPicked = true;
      final want = prefs.audioLanguage;
      if (want != null && t.selectedAudio?.language != want) {
        final match = t.audio.where((a) => a.language == want).firstOrNull;
        if (match != null) unawaited(engine.selectAudioTrack(match.id));
      }
    }
    if (!_subsPicked && t.subtitles.isNotEmpty) {
      _subsPicked = true;
      if (prefs.subtitles && t.selectedSubtitle == null) {
        final pick = preferredTrack(t.subtitles, prefs.subtitleLanguage);
        if (pick != null) unawaited(engine.selectSubtitleTrack(pick.id));
      }
    }
  }

  Future<void> _remember(Map<String, Object?> values) async {
    final prefs = _prefs;
    if (prefs == null) return;
    for (final e in values.entries) {
      await prefs.set(e.key, e.value);
    }
  }

  Future<void> _pickAudio(MediaTrack t) async {
    _closeMenu();
    if (t.language != null) {
      unawaited(_remember({PlayerPrefs.audioLanguage: t.language}));
    }
    if (t.selected) return;
    final spec = _spec;
    if (t.id.startsWith(choicePrefix) && spec != null) {
      // Another YouTube audio stream: open again where we are.
      final i = int.tryParse(t.id.substring(choicePrefix.length));
      if (i == null || i >= spec.audioChoices.length) return;
      final wasPlaying = _playing;
      final at = _position;
      await _open(spec.withAudio(spec.audioChoices[i].url), at);
      if (!wasPlaying) await _engine?.pause();
      return;
    }
    _set(
      () => _tracks = MediaTracks(
        audio: [
          for (final a in _tracks.audio) a.copyWith(selected: a.id == t.id),
        ],
        subtitles: _tracks.subtitles,
      ),
    );
    await _engine?.selectAudioTrack(t.id);
  }

  /// Null turns subtitles off.
  Future<void> _pickSubtitle(MediaTrack? t) async {
    _closeMenu();
    unawaited(
      _remember({
        PlayerPrefs.subtitles: t != null,
        if (t?.language != null) PlayerPrefs.subtitleLanguage: t!.language,
      }),
    );
    _set(
      () => _tracks = MediaTracks(
        audio: _tracks.audio,
        subtitles: [
          for (final s in _tracks.subtitles)
            s.copyWith(selected: s.id == t?.id),
        ],
      ),
    );
    await _engine?.selectSubtitleTrack(t?.id);
  }

  /// The captions key: off, or on in the preferred language.
  void _toggleSubtitles() {
    if (_tracks.subtitles.isEmpty) return;
    _showOsd();
    if (_tracks.selectedSubtitle != null) {
      unawaited(_pickSubtitle(null));
    } else {
      final lang = PlayerPrefs.read(_prefs).subtitleLanguage;
      unawaited(_pickSubtitle(preferredTrack(_tracks.subtitles, lang)));
    }
  }

  void _openMenu() {
    if (_menuOpen || !_hasTrackChoice) return;
    _hideTimer?.cancel();
    setState(() {
      _menu = _Menu.tracks;
      _osd = true;
    });
    if (Dims.of(context).phone) unawaited(_openSheet());
  }

  void _openSpeedMenu() {
    if (_menuOpen || !_speedShown) return;
    _hideTimer?.cancel();
    setState(() {
      _menu = _Menu.speed;
      _osd = true;
    });
    if (Dims.of(context).phone) unawaited(_openSpeedSheet());
  }

  Future<void> _openSpeedSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: ChithramColors.of(context).surface,
      isScrollControlled: true,
      builder: (sheet) => SpeedMenu(
        sheet: true,
        speed: _speed,
        onPick: (s) {
          Navigator.of(sheet).pop();
          unawaited(_pickSpeed(s));
        },
      ),
    );
    _closeMenu();
  }

  Future<void> _pickSpeed(double speed) async {
    _closeMenu();
    _set(() => _speed = speed);
    await _tuning?.setSpeed(speed);
  }

  Future<void> _openSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: ChithramColors.of(context).surface,
      isScrollControlled: true,
      builder: (sheet) => TracksMenu(
        sheet: true,
        audio: _audioItems,
        subtitles: _tracks.subtitles,
        onAudio: (t) {
          Navigator.of(sheet).pop();
          unawaited(_pickAudio(t));
        },
        onSubtitle: (t) {
          Navigator.of(sheet).pop();
          unawaited(_pickSubtitle(t));
        },
      ),
    );
    _closeMenu();
  }

  void _closeMenu() {
    if (!_menuOpen || !mounted) return;
    setState(() => _menu = null);
    _rootFocus.requestFocus();
    _armHide();
  }

  Future<void> _save() async {
    final resume = _resume;
    if (resume == null ||
        _request.isLive ||
        _duration <= Duration.zero ||
        _error != null)
      return;
    if (_offer != null || _finished) return;
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
    _scrubber
      ..removeListener(_scrubChanged)
      ..dispose();
    _previousFocus.dispose();
    _nextFocus.dispose();
    _tracksFocus.dispose();
    for (final n in [_backFocus, _speedFocus, _fullscreenFocus, _rewindFocus, _playFocus, _forwardFocus]) {
      n.dispose();
    }
    _chrome.fullscreen.removeListener(_fullscreenChanged);
    if (_enteredFullscreen && _chrome.fullscreen.value) {
      unawaited(_chrome.toggleFullscreen().catchError((Object _) {}));
    }
    _promptFocus.dispose();
    _errorFocus.dispose();
    _rootFocus.dispose();
    super.dispose();
  }

  /// Keys that only bring a hidden display back.
  static final _wakeOnly = {
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
  };

  /// Remote keys that open the track menu.
  static final _menuKeys = {
    LogicalKeyboardKey.contextMenu,
    LogicalKeyboardKey.info,
    LogicalKeyboardKey.settings,
    LogicalKeyboardKey.tvMediaContext,
    LogicalKeyboardKey.mediaAudioTrack,
  };

  static Duration _wallClock() =>
      Duration(microseconds: DateTime.now().microsecondsSinceEpoch);

  /// Keys that still act while a button has focus.
  static final _mediaKeys = {
    LogicalKeyboardKey.mediaPlayPause,
    LogicalKeyboardKey.mediaPlay,
    LogicalKeyboardKey.mediaPause,
    LogicalKeyboardKey.mediaTrackNext,
    LogicalKeyboardKey.mediaTrackPrevious,
    LogicalKeyboardKey.mediaRewind,
    LogicalKeyboardKey.mediaFastForward,
    LogicalKeyboardKey.channelUp,
    LogicalKeyboardKey.channelDown,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final isArrow =
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
    if (event is KeyUpEvent) {
      if (key == _wakeKey) {
        _wakeKey = null;
        return KeyEventResult.handled;
      }
      if (isArrow && _scrubber.active) {
        _scrubber.keyUp();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent)
      return KeyEventResult.ignored;
    // Esc everywhere in the player, panels included: the desktop's own Esc
    // (above the Navigator) would close the page without asking it.
    if (key == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) _escape();
      return KeyEventResult.handled;
    }
    // Buttons on the error panel, the resume prompt and the Up next card use
    // normal focus movement.
    if (_error != null || _offer != null || _upNextShown || _menuOpen)
      return KeyEventResult.ignored;
    final fresh = event is KeyDownEvent;
    // Holding the key that brought the display back does nothing more.
    if (!fresh && key == _wakeKey) return KeyEventResult.handled;
    if (fresh && !_osd && _wakeOnly.contains(key)) {
      _wakeKey = key;
      _showOsd();
      return KeyEventResult.handled;
    }
    if (fresh && _menuKeys.contains(key)) {
      _showOsd();
      _openMenu();
      return KeyEventResult.handled;
    }
    if (fresh &&
        (key == LogicalKeyboardKey.closedCaptionToggle ||
            key == LogicalKeyboardKey.subtitle)) {
      _toggleSubtitles();
      return KeyEventResult.handled;
    }
    // On the buttons: the arrows move between them (Up from the top bar and
    // Down from the middle row go back to the video); OK presses the button.
    if (_controlsFocused) {
      _showOsd();
      final top = _topNodes;
      final inTop = top.any((n) => n.hasFocus);
      if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
        if (fresh) {
          final up = key == LogicalKeyboardKey.arrowUp;
          if (inTop) {
            (up ? _rootFocus : _playFocus).requestFocus();
          } else {
            up ? _focusTop() : _rootFocus.requestFocus();
          }
        }
        return KeyEventResult.handled;
      }
      if (isArrow) {
        final row = inTop ? top : _centreNodes;
        final i = row.indexWhere((n) => n.hasFocus);
        if (i >= 0) {
          final j = (i + (key == LogicalKeyboardKey.arrowLeft ? -1 : 1)).clamp(0, row.length - 1);
          row[j].requestFocus();
        }
        return KeyEventResult.handled;
      }
      if (!_mediaKeys.contains(key)) return KeyEventResult.ignored;
    }
    if (_desktop && fresh) {
      if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
        _showOsd();
        if (_scrubber.active) {
          _scrubber.commit();
        } else {
          unawaited(_toggle());
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyJ || key == LogicalKeyboardKey.keyL) {
        unawaited(_seekBy(key == LogicalKeyboardKey.keyJ ? -seekStep : seekStep));
        _showOsd();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyF) {
        unawaited(_toggleFullscreen());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyM) {
        _toggleMute();
        return KeyEventResult.handled;
      }
    }
    if (fresh &&
        (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.mediaPlayPause)) {
      _showOsd();
      // OK while scrubbing seeks there.
      if (_scrubber.active && key != LogicalKeyboardKey.mediaPlayPause) {
        _scrubber.commit();
      } else {
        unawaited(_toggle());
      }
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
    if (fresh && key == LogicalKeyboardKey.mediaTrackNext && _hasQueue) {
      unawaited(_playNext());
      return KeyEventResult.handled;
    }
    if (fresh && key == LogicalKeyboardKey.mediaTrackPrevious && _hasQueue) {
      unawaited(_playPrevious());
      return KeyEventResult.handled;
    }
    final left =
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.mediaRewind;
    final right =
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.mediaFastForward;
    if (left || right) {
      if (!_canScrub) {
        _showOsd();
        // A live channel has no seek bar: the sides reach the track button.
        if (fresh && isArrow && _hasTrackChoice) _tracksFocus.requestFocus();
      } else {
        _showOsd();
        _scrubber.key(
          left ? -1 : 1,
          repeat: !fresh,
          now: _wallClock(),
          position: _position,
          length: _duration,
        );
      }
      return KeyEventResult.handled;
    }
    final arrowUp = key == LogicalKeyboardKey.arrowUp;
    final arrowDown = key == LogicalKeyboardKey.arrowDown;
    final up = arrowUp || key == LogicalKeyboardKey.channelUp;
    final down = arrowDown || key == LogicalKeyboardKey.channelDown;
    if (up || down) {
      final zapping = widget.request.zap != null;
      if (!zapping && (arrowUp || arrowDown) && _desktop && _tuning != null) {
        // Desktop: the arrows set the volume (held keys repeat).
        _setVolume((_volume + (arrowUp ? 0.05 : -0.05)).clamp(0.0, 1.0));
        return KeyEventResult.handled;
      }
      if (!fresh) return KeyEventResult.handled;
      if (zapping) {
        unawaited(_zap(up ? -1 : 1));
      } else {
        _showOsd();
        // From the video Up reaches the top bar, Down the middle row.
        if (arrowUp) _focusTop();
        if (arrowDown) _playFocus.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onTap() {
    if (_error != null || _offer != null) return;
    if (_menuOpen) {
      _closeMenu();
      return;
    }
    final d = Dims.of(context);
    // A phone's tap shows or hides the controls; elsewhere it pauses as well.
    if (d.phone) {
      if (_osd) {
        _hideTimer?.cancel();
        setState(() => _osd = false);
      } else {
        _showOsd();
      }
      return;
    }
    if (_osd) unawaited(_toggle());
    _showOsd();
  }

  void _onDoubleTap() {
    if (_error != null || _offer != null || !_canScrub) return;
    final at = _doubleTapAt;
    final width = MediaQuery.sizeOf(context).width;
    if (at == null || at.dx > width * 0.4 && at.dx < width * 0.6) return;
    final forward = at.dx > width / 2;
    _rippleKey.currentState?.bump(forward);
    unawaited(_seekBy(forward ? seekStep : -seekStep));
  }

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    final d = Dims.of(context);
    final queue = _hasQueue ? _request.queue : null;
    final upNext = _upNext;
    final fullscreen = d.desktop && _chrome.fullscreen.value;
    return PopScope(
      // Back drops a scrub or the Up next card before it closes the player.
      canPop: !_scrubber.active && !_upNextShown && !_menuOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_menuOpen) {
          _closeMenu();
        } else if (_upNextShown) {
          _cancelUpNext();
        } else {
          _scrubber.cancel();
        }
      },
      child: Scaffold(
        key: Keys.playerRoot,
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _rootFocus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: MouseRegion(
            onHover: (_) => _showOsd(),
            cursor: _osd ? MouseCursor.defer : SystemMouseCursors.none,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onTap,
              onDoubleTapDown: d.phone
                  ? (details) => _doubleTapAt = details.localPosition
                  : null,
              onDoubleTap: d.phone ? _onDoubleTap : null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (engine != null) engine.view,
                  if (d.phone) DoubleTapRipple(key: _rippleKey),
                  PlayerOsd(
                    visible: _osd && !_upNextShown,
                    controls: _error == null && _offer == null,
                    onBack: () => unawaited(Navigator.of(context).maybePop()),
                    backFocus: _backFocus,
                    playFocus: _playFocus,
                    onRewind: _canScrub ? () => unawaited(_seekBy(-seekStep)) : null,
                    onForward: _canScrub ? () => unawaited(_seekBy(seekStep)) : null,
                    rewindFocus: _rewindFocus,
                    forwardFocus: _forwardFocus,
                    speed: _speed,
                    onSpeed: _speedShown ? _openSpeedMenu : null,
                    speedFocus: _speedFocus,
                    fullscreen: fullscreen,
                    onFullscreen: _fullscreenShown ? () => unawaited(_toggleFullscreen()) : null,
                    fullscreenFocus: _fullscreenFocus,
                    windowChrome: d.desktop ? _chrome : null,
                    volume: d.desktop && _tuning != null ? _volume : null,
                    muted: _muted,
                    onVolume: _setVolume,
                    onMute: _toggleMute,
                    title: _request.title,
                    subtitle: _request.subtitle,
                    status: _statusLine,
                    position: _position,
                    duration: _duration,
                    buffered: _buffered,
                    live: _request.isLive,
                    playing: _playing,
                    scrubber: _scrubber,
                    extras: _extras,
                    onSeek: _commitScrub,
                    onLive: () => _commitScrub(_duration),
                    onToggle: () => unawaited(_toggle()),
                    onPrevious: queue == null
                        ? null
                        : (queue.hasPrevious
                              ? () => unawaited(_playPrevious())
                              : null),
                    onNext: queue == null ? null : () => unawaited(_playNext()),
                    previousFocus: _previousFocus,
                    nextFocus: _nextFocus,
                    onTracks: _hasTrackChoice ? _openMenu : null,
                    tracksFocus: _tracksFocus,
                    sheetProvider: widget.sheetProvider,
                  ),
                  // A ring round the play button (which sits in the middle)
                  // while loading; alone when the display is hidden.
                  if (_loading || _buffering)
                    Center(
                      child: IgnorePointer(
                        child: SizedBox.square(
                          dimension: playButtonSize(d) + 16,
                          child: CircularProgressIndicator(
                            key: PlayerKeys.spinner,
                            strokeWidth: d.tv ? 4 : 3,
                            color: ChithramColors.of(context).accent,
                          ),
                        ),
                      ),
                    ),
                  if (_menu == _Menu.speed && !d.phone)
                    SpeedMenu(speed: _speed, onPick: (s) => unawaited(_pickSpeed(s))),
                  if (_menu == _Menu.tracks && !d.phone)
                    TracksMenu(
                      audio: _audioItems,
                      subtitles: _tracks.subtitles,
                      onAudio: (t) => unawaited(_pickAudio(t)),
                      onSubtitle: (t) => unawaited(_pickSubtitle(t)),
                    ),
                  if (_offer != null) _resumePrompt(_offer!),
                  if (_error != null) _errorPanel(),
                  if (_upNextShown && upNext != null)
                    UpNextCard(
                      key: ValueKey(upNext),
                      next: upNext,
                      onPlay: () => unawaited(_playNext()),
                      onCancel: _cancelUpNext,
                    ),
                ],
              ),
            ),
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
          child: ActionLabel(
            icon: Icons.play_arrow_rounded,
            text: 'Resume from ${formatPlayerTime(saved)}',
            primary: true,
          ),
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
      message: Text(
        _error!,
        key: Keys.playerError,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.redAccent),
      ),
      children: [
        FocusCard(
          key: PlayerKeys.retry,
          focusNode: _errorFocus,
          radius: 28,
          onActivate: () => unawaited(_retry()),
          child: const ActionLabel(
            icon: Icons.refresh_rounded,
            text: 'Retry',
            primary: true,
          ),
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

enum _Menu { tracks, speed }

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
        decoration: BoxDecoration(
          color: ChithramColors.of(context).surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(fontSize: d.t(20), fontWeight: FontWeight.w700),
            ),
            if (message != null) ...[const SizedBox(height: 12), message!],
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: children,
            ),
          ],
        ),
      ),
    );
  }
}
