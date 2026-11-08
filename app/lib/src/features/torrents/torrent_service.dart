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
import 'downloads.dart';
import 'network_dialog.dart';
import 'torrent_files_page.dart';
import 'torrent_logic.dart';

/// Initial peers for the end-to-end tests (`--dart-define=E2E_PEER=ip:port`).
/// Read in debug builds only; a release build never connects to one.
const _e2ePeer = String.fromEnvironment('E2E_PEER');

/// The single streamed torrent, the kept downloads, and the network-choice guard.
///
/// The engine starts on the first torrent action, in `<cache>/torrent`, which
/// is emptied first. Only one streamed torrent lives at a time, and it is
/// removed when the player closes, so a stream seeds only while you watch.
/// Downloads are kept in a folder of their own, survive a restart and seed
/// while the app is open (unless seeding is off).
class TorrentService extends ChangeNotifier {
  TorrentService({
    required this.paths,
    required this.prefs,
    Future<bool> Function(Socks5Address)? probe,
    Future<int?> Function(Directory)? freeSpace,
  })  : guard = NetworkGuard(prefs),
        _probe = probe ?? probeSocks5,
        _freeSpace = freeSpace ?? freeSpaceBytes,
        _store = DownloadStore(paths.supportFile('downloads.json')) {
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
  bool _disposed = false;

  /// How the streamed torrent was added, for "Download instead".
  String? _activeMagnet;
  Uint8List? _activeBytes;

  final DownloadStore _store;
  final List<Download> _downloads = [];
  bool _loaded = false;
  Timer? _downloadPoll;
  final Set<String> _autoPaused = {};
  String? _limitsSignature;

  /// Kept downloads, oldest first.
  List<Download> get downloads => List.unmodifiable(_downloads);

  /// The torrent being watched or listed, if any.
  TorrentInfo? get active => _active;

  /// Its latest stats (null until the first poll).
  TorrentStats? get stats => _stats;

  /// True while a magnet is looking for its file list.
  bool get resolving => _resolving;

  @override
  void dispose() {
    _disposed = true;
    prefs.removeListener(_onPrefs);
    _poll?.cancel();
    _downloadPoll?.cancel();
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
      unawaited(_shutdown().then((_) {
        // Downloads carry on over the new network.
        if (!_disposed && _downloads.isNotEmpty && !guard.needsChoice) unawaited(_ensureEngine());
      }));
    } else if (_engine != null) {
      unawaited(_applyLimits(_engine!));
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
    _downloadPoll?.cancel();
    _downloadPoll = null;
    _limitsSignature = null;
    _autoPaused.clear();
    for (final d in _downloads) {
      d
        ..info = null
        ..stats = null;
    }
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
    await _applyLimits(engine);
    await _loadDownloads();
    for (final d in _downloads) {
      unawaited(_attach(engine, d));
    }
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
      _activeMagnet = magnet;
      _activeBytes = bytes;
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
    _activeMagnet = null;
    _activeBytes = null;
    // Called from widget dispose (the player route, the file list): listeners
    // cannot be told while the tree is being torn down.
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
    // A stream of something also kept as a download is that download: leave it.
    if (downloadFor(info.infoHash) != null) return;
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
    while (true) {
      final d = _downloadById(id);
      if (d != null) {
        yield downloadLine(d);
      } else if (_active?.id == id) {
        yield statusLine(_stats);
      } else {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  PlayRequest playRequest(TorrentInfo t, TorrentFile f) {
    final engine = _engine;
    if (engine == null || (_active?.id != t.id && _downloadById(t.id) == null)) {
      throw StateError('torrent is not active');
    }
    return PlayRequest(
      itemId: ItemId.torrentFile(t.infoHash, f.index),
      title: fileTitle(f.path),
      subtitle: t.name,
      resolve: () async {
        if (!f.streamable) throw TorrentException('Not a media file');
        return MediaSpec(videoUrl: engine.streamUrl(t.id, f.index));
      },
      // Ends a stream; a download stays (removeActive leaves those alone).
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

  // Downloads.

  /// The kept download of [infoHash], if any.
  Download? downloadFor(String infoHash) {
    final h = infoHash.toLowerCase();
    for (final d in _downloads) {
      if (d.infoHash == h) return d;
    }
    return null;
  }

  Download? _downloadById(int id) {
    for (final d in _downloads) {
      if (d.info?.id == id) return d;
    }
    return null;
  }

  /// Where new downloads go: the chosen folder, else [defaultDownloadsBase].
  Future<Directory> downloadsBase() async {
    final chosen = prefs.getString(DownloadPrefs.folder)?.trim() ?? '';
    if (chosen.isNotEmpty) return Directory(chosen);
    return defaultDownloadsBase(paths);
  }

  /// Settings: a folder for later downloads (existing ones stay where they
  /// are). Empty goes back to the default. Throws when it cannot be made.
  Future<void> setDownloadsBase(String path) async {
    final p = path.trim();
    if (p.isNotEmpty) await Directory(p).create(recursive: true);
    await prefs.set(DownloadPrefs.folder, p);
  }

  /// Finished downloads keep sharing while the app is open.
  bool get seeding => prefs.getBool(DownloadPrefs.seed, fallback: true);

  /// After the first frame: brings saved downloads back when there are any and
  /// the network is chosen (otherwise on the first torrent action).
  Future<void> restoreDownloads() async {
    await _loadDownloads();
    if (_downloads.isEmpty || guard.needsChoice || _engine != null) return;
    try {
      await _ensureEngine();
    } catch (_) {
      // The next torrent action tries again.
    }
  }

  Future<void> _loadDownloads() async {
    if (_loaded) return;
    _loaded = true;
    final known = {for (final d in _downloads) d.infoHash};
    for (final r in await _store.load()) {
      if (known.add(r.infoHash)) _downloads.add(Download(r));
    }
    if (_downloads.isNotEmpty && !_disposed) notifyListeners();
  }

  Future<void> _save() => _store.save([for (final d in _downloads) d.record]);

  Future<void> _applyLimits(TorrentEngine engine) async {
    final down = DownloadPrefs.limitBps(prefs, DownloadPrefs.downKib);
    final up = DownloadPrefs.limitBps(prefs, DownloadPrefs.upKib);
    final sig = '$down/$up';
    if (sig == _limitsSignature) return;
    _limitsSignature = sig;
    try {
      await engine.setLimits(downloadBps: down, uploadBps: up);
    } catch (_) {
      _limitsSignature = null;
    }
  }

  /// Adds a stored download to the running engine.
  Future<void> _attach(TorrentEngine engine, Download d) async {
    final r = d.record;
    d.error = null;
    try {
      Uint8List? bytes;
      if (r.magnet == null && r.torrentFile != null) bytes = await File(r.torrentFile!).readAsBytes();
      if (r.magnet == null && bytes == null) throw TorrentException('Nothing to add it from');
      final info = await engine.add(
        magnet: r.magnet,
        torrentBytes: bytes,
        peers: _initialPeers,
        outputFolder: r.folder,
        paused: r.paused,
        onlyFiles: r.onlyFiles,
      );
      if (_engine != engine || !_downloads.contains(d)) return;
      d.info = info;
      if (r.name.isEmpty && (info.name?.isNotEmpty ?? false)) {
        d.record = r.copyWith(name: info.name);
        unawaited(_save());
      }
    } on TorrentException catch (e) {
      d.error = e.message;
    } catch (e) {
      d.error = '$e';
    }
    _startDownloadPoll();
    if (!_disposed) notifyListeners();
  }

  void _startDownloadPoll() {
    _downloadPoll ??= Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_refreshDownloads()));
  }

  Future<void> _refreshDownloads() async {
    final engine = _engine;
    if (engine == null || _disposed) return;
    var changed = false;
    for (final d in List.of(_downloads)) {
      final info = d.info;
      if (info == null) continue;
      try {
        final s = await engine.stats(info.id);
        d.stats = s;
        changed = true;
        // Seeding off: a finished download stops sharing until it is resumed.
        if (s.finished && !seeding && !d.paused && !s.paused && _autoPaused.add(d.infoHash)) {
          await engine.pause(info.id);
        } else if (seeding && !d.paused && _autoPaused.remove(d.infoHash)) {
          await engine.resume(info.id);
        }
      } catch (_) {
        // Removed meanwhile.
      }
    }
    if (changed && !_disposed) notifyListeners();
  }

  /// Keeps [magnet] or [bytes] as a download in [downloadsBase]. Stops the
  /// stream first (it may be the same torrent). Returns the existing download
  /// when it is already kept.
  Future<Download> download({String? magnet, Uint8List? bytes}) async {
    magnet = magnet?.trim();
    if (magnet == null && bytes == null) throw ArgumentError('magnet or bytes required');
    final hash = magnet == null ? null : btihFromMagnet(magnet);
    if (magnet != null && hash == null) throw TorrentException('That is not a magnet link');
    await _loadDownloads();
    final existing = hash == null ? null : downloadFor(hash);
    if (existing != null) return existing;
    await removeActive();
    _resolving = true;
    notifyListeners();
    try {
      final engine = await _ensureEngine();
      final name = (magnet != null ? magnetName(magnet) : torrentName(bytes!)) ?? '';
      final base = await downloadsBase();
      final folder = '${base.path}${Platform.pathSeparator}'
          '${folderNameFor(name, hash ?? 'torrent-${DateTime.now().millisecondsSinceEpoch}')}';
      await Directory(folder).create(recursive: true);
      final info = await engine.add(magnet: magnet, torrentBytes: bytes, peers: _initialPeers, outputFolder: folder);
      final again = downloadFor(info.infoHash);
      if (again != null) return again;
      final record = DownloadRecord(
        infoHash: info.infoHash,
        name: info.name ?? name,
        folder: folder,
        magnet: magnet,
        torrentFile: bytes == null ? null : await _store.saveTorrent(info.infoHash, bytes),
        added: DateTime.now(),
      );
      final d = Download(record, info: info);
      _downloads.add(d);
      await _save();
      _startDownloadPoll();
      return d;
    } finally {
      _resolving = false;
      notifyListeners();
    }
  }

  /// "Download instead": keeps the torrent being streamed.
  Future<Download> downloadActive() {
    final magnet = _activeMagnet, bytes = _activeBytes;
    if (magnet == null && bytes == null) throw StateError('nothing is streaming');
    return download(magnet: magnet, bytes: bytes);
  }

  Future<void> _update(Download d, DownloadRecord r) async {
    d.record = r;
    notifyListeners();
    await _save();
  }

  Future<void> pauseDownload(Download d) async {
    final id = d.info?.id;
    if (id != null) await _engine?.pause(id);
    await _update(d, d.record.copyWith(paused: true));
  }

  Future<void> resumeDownload(Download d) async {
    _autoPaused.remove(d.infoHash);
    await _update(d, d.record.copyWith(paused: false));
    final id = d.info?.id;
    final engine = _engine;
    if (engine != null && id != null) {
      await engine.resume(id);
      return;
    }
    // Not running, or it failed to start: try again.
    if (guard.needsChoice) return;
    final e = await _ensureEngine();
    if (d.info == null) await _attach(e, d);
  }

  /// Downloads only [files] (indexes) of [d] from now on.
  Future<void> setDownloadFiles(Download d, List<int> files) async {
    final info = d.info;
    if (info == null) throw StateError('download is not running');
    final chosen = files.toSet().toList()..sort();
    await _engine?.setFiles(info.id, chosen);
    await _update(d, d.record.copyWith(onlyFiles: chosen.length == info.files.length ? null : chosen));
  }

  /// Forgets [d]; with [deleteFiles] its files go too.
  Future<void> removeDownload(Download d, {bool deleteFiles = false}) async {
    _downloads.remove(d);
    _autoPaused.remove(d.infoHash);
    notifyListeners();
    final id = d.info?.id;
    final engine = _engine;
    if (id != null && engine != null) {
      if (_active?.id == id) {
        _poll?.cancel();
        _poll = null;
        _active = null;
        _stats = null;
      }
      try {
        await engine.remove(id, deleteFiles: deleteFiles);
      } catch (_) {
        // Already gone.
      }
    }
    if (deleteFiles) {
      // The engine deletes the files it wrote; drop the folder once empty.
      try {
        final dir = Directory(d.record.folder);
        if (await dir.exists() && await dir.list().isEmpty) await dir.delete();
      } catch (_) {
        // In use, or not empty.
      }
    }
    final t = d.record.torrentFile;
    if (t != null) {
      try {
        await File(t).delete();
      } catch (_) {
        // Already gone.
      }
    }
    await _save();
  }

  /// Opens [d]'s folder in the file manager; false where there is none.
  Future<bool> openFolder(Download d) async {
    final cmd = Platform.isWindows
        ? 'explorer'
        : Platform.isMacOS
            ? 'open'
            : Platform.isLinux
                ? 'xdg-open'
                : null;
    if (cmd == null) return false;
    try {
      await Process.start(cmd, [d.record.folder], mode: ProcessStartMode.detached);
      return true;
    } catch (_) {
      return false;
    }
  }
}
