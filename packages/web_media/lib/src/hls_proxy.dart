import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

import 'hls.dart';

/// Serves HLS playlists to the player over loopback HTTP with their ad breaks
/// removed ([rewritePlaylist]). Segments are not proxied: the rewritten
/// playlists point at them on their own hosts.
///
/// `GET http://127.0.0.1:<port>/<token>/<id>.m3u8`. Only playlists registered
/// with [wrap] (and the variants they list) are fetched, so this is no open
/// proxy; only loopback hosts and the per-run token are accepted.
class HlsAdProxy {
  HlsAdProxy({this.timeout = const Duration(seconds: 20), this.maxBytes = 8 * 1024 * 1024});

  final Duration timeout;
  final int maxBytes;

  /// Registered playlists; oldest dropped past [_maxEntries].
  static const _maxEntries = 2000;

  HttpServer? _server;
  late final String _token = _newToken();
  final _byId = <int, (Uri, Map<String, String>)>{};
  final _ids = <String, int>{};
  var _next = 0;

  static String _newToken() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

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

  /// The loopback URL the player opens for [playlist], fetched with
  /// [headers]. Starts the server on first use.
  Future<Uri> wrap(Uri playlist, Map<String, String> headers) async {
    await start();
    return _register(playlist, headers);
  }

  Uri _register(Uri playlist, Map<String, String> headers) {
    final k = '$playlist ${jsonEncode(headers)}';
    final id = _ids[k] ?? (_ids[k] = _next++);
    _byId[id] = (playlist, headers);
    while (_byId.length > _maxEntries) {
      final oldest = _byId.keys.first;
      _byId.remove(oldest);
      _ids.removeWhere((_, v) => v == oldest);
    }
    return Uri.parse('http://127.0.0.1:$port/$_token/$id.m3u8');
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final host = req.headers.host;
      final seg = req.uri.pathSegments;
      if ((host != '127.0.0.1' && host != 'localhost') || seg.length != 2 || seg[0] != _token) {
        res.statusCode = HttpStatus.forbidden;
        return;
      }
      final entry = _byId[int.tryParse(seg[1].replaceFirst('.m3u8', '')) ?? -1];
      if (entry == null) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      final (url, headers) = entry;
      final fetched = await _fetch(url, headers);
      if (fetched == null || !fetched.$2.trimLeft().startsWith('#EXTM3U')) {
        res.statusCode = HttpStatus.badGateway;
        return;
      }
      final body = rewritePlaylist(fetched.$2, fetched.$1, route: (u) => _register(u, headers));
      res.headers.set(HttpHeaders.contentTypeHeader, 'application/vnd.apple.mpegurl');
      res.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      res.write(body);
    } catch (_) {
      try {
        res.statusCode = HttpStatus.badGateway;
      } catch (_) {}
    } finally {
      try {
        await res.close();
      } catch (_) {}
    }
  }

  /// The final URL (after redirects, the base for relative URIs) and the body.
  Future<(Uri, String)?> _fetch(Uri url, Map<String, String> headers) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      return await () async {
        final req = await client.getUrl(url);
        req.maxRedirects = 5;
        headers.forEach(req.headers.set);
        final res = await req.close();
        if (res.statusCode != 200) return null;
        final out = BytesBuilder(copy: false);
        await for (final chunk in res) {
          out.add(chunk);
          if (out.length > maxBytes) return null;
        }
        final finalUrl = res.redirects.isEmpty ? url : url.resolveUri(res.redirects.last.location);
        return (finalUrl, utf8.decode(out.takeBytes(), allowMalformed: true));
      }()
          .timeout(timeout);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
