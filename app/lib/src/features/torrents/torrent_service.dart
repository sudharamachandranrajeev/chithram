import 'dart:async';
import 'dart:io';

import 'package:chithram_player/chithram_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:torrent/torrent.dart';

import '../../core/item_id.dart';
import '../../core/paths.dart';
import '../../core/prefs.dart';
import '../../player/play_request.dart';
import 'network_dialog.dart';
import 'torrent_files_page.dart';
import 'torrent_logic.dart';

/// Initial peers for the end-to-end tests (`--dart-define=E2E_PEER=ip:port`).
/// Read in debug builds only; a release build never connects to one.
const _e2ePeer = String.fromEnvironment('E2E_PEER');

/// The single active torrent and the network-choice guard.
///
/// The engine starts on the first torrent action, in `<cache>/torrent`, which
/// is emptied first. Only one torrent lives at a time, and it is removed when
/// the player closes, so Chithram seeds only while you watch.
class TorrentService extends ChangeNotifier {
  TorrentService({
    required this.paths,
    required this.prefs,
    Future<bool> Function(Socks5Address)? probe,
    Future<int?> Function(Directory)? freeSpace,
  })  : guard = NetworkGuard(prefs),
        _probe = probe ?? probeSocks5,
        _freeSpace = freeSpace ?? freeSpaceBytes {
    prefs.addListener(_onPrefs);
  }

  final AppPaths paths;
  final Prefs prefs;
  final NetworkGuard guard;
  final Future<bool> Function(Socks5Address) _probe;
  final Future<int?> Function(Directory) _freeSpace;

  TorrentEngine? _engine;
  String? _engineSignature;
  Future<TorrentEngine>? _starting;
  TorrentInfo? _active;
  TorrentStats? _stats;
  Timer? _poll;
  bool _resolving = false;

  /// The torrent being watched or listed, if any.
  TorrentInfo? get active => _active;

  /// Its latest stats (null until the first poll).
  TorrentStats? get stats => _stats;

  /// True while a magnet is looking for its file list.
  bool get resolving => _resolving;

  @override
  void dispose() {
    prefs.removeListener(_onPrefs);
    _poll?.cancel();
    super.dispose();
  }

  /// Asks for SOCKS5 or direct on the first torrent action; true when the user chose.
  Future<bool> ensureNetworkChoice(BuildContext c) async {
    if (!guard.needsChoice) return true;
    return chooseNetwork(c, guard, probe: _probe);
  }

  /// Settings: change the choice. Takes effect by restarting the engine.
  Future<bool> changeNetworkChoice(BuildContext c) => chooseNetwork(c, guard, probe: _probe);

  /// A changed choice stops the engine; the next torrent action starts it again.
  void _onPrefs() {
    if (_engine != null && guard.choice.signature != _engineSignature) {
      unawaited(_shutdown());
    }
    notifyListeners();
  }

  Future<void> _shutdown() async {
    _poll?.cancel();
    _poll = null;
    final engine = _engine;
    _engine = null;
    _engineSignature = null;
    _starting = null;
    _active = null;
    _stats = null;
    notifyListeners();
    try {
      await engine?.stop();
    } catch (_) {
      // Already stopped.
    }
  }

  Future<TorrentEngine> _ensureEngine() {
    final choice = guard.choice;
    if (choice.mode == NetworkMode.unset) throw StateError('torrent network not chosen');
    if (_engine != null && _engineSignature == choice.signature) return Future.value(_engine);
    return _starting ??= _startEngine(choice).whenComplete(() => _starting = null);
  }

  Future<TorrentEngine> _startEngine(NetworkChoice choice) async {
    if (_engine != null) await _shutdown();
    // State is process-global; clear anything a previous service left running.
    try {
      await TorrentEngine.stopRunning();
    } catch (_) {
      // Nothing was running.
    }
    final dir = paths.cacheDir('torrent');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final engine = await TorrentEngine.start(
      dir: dir.path,
      quotaBytes: quotaFor(await _freeSpace(dir)),
      socks5: choice.socks5?.url,
    );
    _engine = engine;
    _engineSignature = choice.signature;
    return engine;
  }

  List<String> get _initialPeers => kDebugMode && _e2ePeer.isNotEmpty ? [_e2ePeer] : const [];

  Future<TorrentInfo> addMagnet(String magnet) => _add(magnet: magnet.trim());

  Future<TorrentInfo> addTorrentBytes(Uint8List b) => _add(bytes: b);

  Future<TorrentInfo> _add({String? magnet, Uint8List? bytes}) async {
    await removeActive();
    _resolving = true;
    notifyListeners();
    try {
      final engine = await _ensureEngine();
      final info = await engine.add(magnet: magnet, torrentBytes: bytes, peers: _initialPeers);
      _active = info;
      _stats = null;
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_refresh(engine, info.id)));
      return info;
    } finally {
      _resolving = false;
      notifyListeners();
    }
  }

  Future<void> _refresh(TorrentEngine engine, int id) async {
    try {
      final s = await engine.stats(id);
      if (_active?.id != id) return;
      _stats = s;
      notifyListeners();
    } catch (_) {
      // Removed meanwhile.
    }
  }

  /// Removes the active torrent (or [id] only, when that is still the active one)
  /// and its files, which ends any seeding.
  Future<void> removeActive({int? id}) async {
    final info = _active;
    final engine = _engine;
    if (info == null || engine == null || (id != null && info.id != id)) return;
    _poll?.cancel();
    _poll = null;
    _active = null;
    _stats = null;
    notifyListeners();
    try {
      await engine.remove(info.id, deleteFiles: true);
    } catch (_) {
      // Already gone.
    }
  }

  /// Stats of torrent [id] straight from the engine; throws once it is removed.
  @visibleForTesting
  Future<TorrentStats> statsFor(int id) {
    final engine = _engine;
    if (engine == null) throw StateError('engine is not running');
    return engine.stats(id);
  }

  /// Download state for the player's status line, once a second, until the
  /// torrent is gone.
  Stream<String> statusStream(int id) async* {
    while (_active?.id == id) {
      yield statusLine(_stats);
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  PlayRequest playRequest(TorrentInfo t, TorrentFile f) {
    final engine = _engine;
    if (engine == null || _active?.id != t.id) throw StateError('torrent is not active');
    return PlayRequest(
      itemId: ItemId.torrentFile(t.infoHash, f.index),
      title: fileTitle(f.path),
      subtitle: t.name,
      resolve: () async {
        if (!f.streamable) throw TorrentException('Not a media file');
        return MediaSpec(videoUrl: engine.streamUrl(t.id, f.index));
      },
      onClose: () => removeActive(id: t.id),
      status: statusStream(t.id),
    );
  }

  /// Shows the file list. Backing out without playing removes the torrent.
  Future<void> openFiles(BuildContext c, TorrentInfo t) {
    return Navigator.of(c).push(
      MaterialPageRoute<void>(builder: (_) => TorrentFilesPage(info: t)),
    );
  }
}
