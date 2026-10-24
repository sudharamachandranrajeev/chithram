import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:tdlib/tdlib.dart';

/// Serves Telegram files to the player over loopback HTTP with Range, so a
/// video plays while TDLib is still downloading it.
///
/// `GET http://127.0.0.1:<port>/<token>/tg/<fileId>/<name>`. For each range it
/// moves TDLib's download to the requested offset when that is outside what is
/// being fetched, waits on `updateFile` until the bytes are on disk, then
/// reads them with `readFilePart`. Only loopback hosts and the per-run token
/// are accepted.
class TgRangeServer {
  TgRangeServer(this.client, {this.chunk = 512 * 1024, this.stall = const Duration(seconds: 90), this.aheadSlack = 4 * 1024 * 1024});

  final TelegramClient client;

  /// Bytes read from TDLib per step.
  final int chunk;

  /// Gives up on a request when no new bytes arrive for this long.
  final Duration stall;

  /// A request this far past the active download's frontier waits for it
  /// instead of restarting the download.
  final int aheadSlack;

  HttpServer? _server;
  late final String _token = _newToken();
  final _names = <int, String>{};
  final _mimes = <int, String>{};

  static String _newToken() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  String get token => _token;
  int get port => _server?.port ?? 0;

  Future<void> start() async {
    if (_server != null) return;
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = s;
    s.listen((req) => unawaited(_handle(req)), onError: (_) {});
  }

  Future<void> close() async {
    final s = _server;
    _server = null;
    await s?.close(force: true);
  }

  /// The URL the player opens for [fileId]. Starts the server on first use.
  Future<String> urlFor(int fileId, String name, {String mime = ''}) async {
    await start();
    _names[fileId] = name;
    if (mime.isNotEmpty) _mimes[fileId] = mime;
    return 'http://127.0.0.1:$port/$_token/tg/$fileId/${Uri.encodeComponent(name)}';
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    var sent = false;
    try {
      final host = req.headers.host;
      if (host != '127.0.0.1' && host != 'localhost') {
        res.statusCode = HttpStatus.forbidden;
        return;
      }
      final seg = req.uri.pathSegments;
      if (seg.length < 3 || seg[0] != _token || seg[1] != 'tg') {
        res.statusCode = HttpStatus.forbidden;
        return;
      }
      if (req.method != 'GET' && req.method != 'HEAD') {
        res.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final id = int.tryParse(seg[2]);
      TgFile file;
      try {
        file = await client.getFile(id ?? -1);
      } on TdError {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      final size = file.size;
      if (id == null || size <= 0) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      final range = _parseRange(req.headers.value(HttpHeaders.rangeHeader), size);
      res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      res.headers.set(HttpHeaders.contentTypeHeader, _contentType(id));
      if (range == null && req.headers.value(HttpHeaders.rangeHeader) != null) {
        res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
        return;
      }
      final (start, end) = range ?? (0, size - 1);
      if (range != null) {
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$size');
      }
      res.contentLength = end - start + 1;
      if (req.method == 'HEAD') return;
      var pos = start;
      while (pos <= end) {
        final bytes = await _read(id, pos, min(chunk, end + 1 - pos));
        if (bytes.isEmpty) break;
        res.add(bytes);
        sent = true;
        await res.flush();
        pos += bytes.length;
      }
    } catch (_) {
      // The player closed the connection, or TDLib failed mid-stream: the
      // response is cut short and the player retries. Before the first byte
      // it is a clean error instead.
      if (!sent) {
        try {
          res.statusCode = HttpStatus.gatewayTimeout;
          res.headers.removeAll(HttpHeaders.contentRangeHeader);
          res.contentLength = 0;
        } catch (_) {}
      }
    } finally {
      try {
        await res.close();
      } catch (_) {}
    }
  }

  String _contentType(int id) {
    final m = _mimes[id];
    if (m != null && m.contains('/')) return m;
    final name = (_names[id] ?? '').toLowerCase();
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1);
    return switch (ext) {
      'mkv' => 'video/x-matroska',
      'webm' => 'video/webm',
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/mp4',
      'flac' => 'audio/flac',
      'ogg' || 'opus' || 'oga' => 'audio/ogg',
      'wav' => 'audio/wav',
      'avi' => 'video/x-msvideo',
      'mov' => 'video/quicktime',
      _ => 'video/mp4',
    };
  }

  /// One `bytes=a-b`, `a-` or `-n` range, clamped to [size]; null when absent
  /// or unsatisfiable.
  static (int, int)? _parseRange(String? header, int size) {
    if (header == null) return null;
    final m = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (m == null) return null;
    final a = m.group(1)!;
    final b = m.group(2)!;
    if (a.isEmpty && b.isEmpty) return null;
    int start;
    int end;
    if (a.isEmpty) {
      final n = int.parse(b);
      if (n == 0) return null;
      start = max(0, size - n);
      end = size - 1;
    } else {
      start = int.parse(a);
      end = b.isEmpty ? size - 1 : min(int.parse(b), size - 1);
    }
    if (start >= size || end < start) return null;
    return (start, end);
  }

  /// At least one byte (up to [want]) at [pos], once it is on disk.
  Future<Uint8List> _read(int id, int pos, int want) async {
    var wake = Completer<void>();
    final sub = client.fileUpdates.where((f) => f.id == id).listen((_) {
      if (!wake.isCompleted) wake.complete();
    });
    try {
      var restarted = false;
      while (true) {
        final f = await client.getFile(id);
        final have = _available(f, pos);
        if (have > 0) {
          final n = min(have, want);
          final out = await client.readFilePart(id, pos, n);
          if (out.isNotEmpty) return out;
        } else if (!restarted && _needsRestart(f, pos)) {
          // Not what the download is fetching: move it here.
          restarted = true;
          await client.downloadFile(id, offset: pos);
          continue;
        }
        wake = Completer<void>();
        await wake.future.timeout(stall);
      }
    } finally {
      await sub.cancel();
    }
  }

  /// Contiguous bytes readable from [pos].
  int _available(TgFile f, int pos) {
    if (f.isComplete) return max(0, f.size - pos);
    if (pos < f.downloadOffset) return 0;
    return max(0, f.downloadOffset + f.prefixSize - pos);
  }

  bool _needsRestart(TgFile f, int pos) {
    if (f.isComplete) return false;
    if (!f.isDownloading) return true;
    if (pos < f.downloadOffset) return true;
    return pos > f.downloadOffset + f.prefixSize + aheadSlack;
  }
}
