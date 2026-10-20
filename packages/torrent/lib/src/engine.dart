import 'dart:isolate';
import 'dart:typed_data';

import 'bindings.dart';
import 'models.dart';

/// Handle to the in-process torrent engine (one per app).
///
/// Native calls block, so each one runs in a short-lived isolate; the native
/// engine state is process-global, so every isolate sees the same engine.
class TorrentEngine {
  TorrentEngine._(this.port, this.token);

  /// Loopback port of the streaming server.
  final int port;

  /// 128-bit hex token; part of every URL.
  final String token;

  /// `http://127.0.0.1:port/token`
  String get baseUrl => 'http://127.0.0.1:$port/$token';
  String get healthUrl => '$baseUrl/health';

  /// Range-capable URL for a file of torrent [id].
  String streamUrl(int id, int fileIndex) => '$baseUrl/stream/$id/$fileIndex';

  /// Starts the engine. [quotaBytes] 0 = unlimited. [socks5] is
  /// `socks5://[user:pass@]host:port`; when set DHT, listening and UDP trackers are off.
  static Future<TorrentEngine> start({
    required String dir,
    int quotaBytes = 0,
    String? socks5,
  }) async {
    final j = await Isolate.run(() => TorrentBindings.open().start(dir, quotaBytes, socks5));
    return TorrentEngine._(j['port'] as int, j['token'] as String);
  }

  /// Adds a magnet or .torrent bytes and waits (max 120 s) for the file list.
  /// [peers] ("ip:port") are tried first; useful for tests and trusted sources.
  Future<TorrentInfo> add({
    String? magnet,
    Uint8List? torrentBytes,
    List<String> peers = const [],
  }) async {
    if (magnet == null && torrentBytes == null) {
      throw ArgumentError('magnet or torrentBytes required');
    }
    final j = await Isolate.run(
      () => TorrentBindings.open().add(magnet: magnet, torrentBytes: torrentBytes, peers: peers),
    );
    return TorrentInfo.fromJson(j);
  }

  Future<TorrentStats> stats(int id) async =>
      TorrentStats(await Isolate.run(() => TorrentBindings.open().stats(id)));

  Future<void> remove(int id, {bool deleteFiles = false}) =>
      Isolate.run(() => TorrentBindings.open().remove(id, deleteFiles));

  /// Stops the server and session. The engine can be started again afterwards.
  Future<void> stop() => Isolate.run(() => TorrentBindings.open().stop());
}
