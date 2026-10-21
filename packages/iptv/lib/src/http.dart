import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// An opened HTTP response whose body has not been consumed yet.
class IptvResponse {
  IptvResponse({
    required this.status,
    required this.headers,
    required this.body,
    required this.ttfb,
    this.finalUri,
    this.onClose,
  });
  final int status;

  /// Lower-cased header names, first value only.
  final Map<String, String> headers;
  final Stream<List<int>> body;

  /// Time from request start to response headers.
  final Duration ttfb;
  final Uri? finalUri;
  final void Function()? onClose;

  bool get ok => status >= 200 && status < 300;
  void close() => onClose?.call();
}

/// Minimal HTTP seam so parsers/clients are testable without a network.
abstract class IptvHttp {
  Future<IptvResponse> open(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 15),
  });
}

class HttpStatusException implements Exception {
  HttpStatusException(this.status, this.what);
  final int status;
  final String what;
  @override
  String toString() => 'HttpStatusException($status) $what';
}

/// Reads a response fully as text, capped at [maxBytes].
Future<String> readText(IptvResponse r, {int maxBytes = 32 * 1024 * 1024}) async {
  final b = BytesBuilder(copy: false);
  await for (final c in r.body) {
    b.add(c);
    if (b.length > maxBytes) {
      r.close();
      throw StateError('response larger than $maxBytes bytes');
    }
  }
  return utf8.decode(b.takeBytes(), allowMalformed: true);
}

/// dart:io implementation. Follows redirects, honours a per-request timeout.
class DartIoHttp implements IptvHttp {
  DartIoHttp({String userAgent = 'Chithram'}) : _client = HttpClient() {
    _client.userAgent = userAgent;
    _client.autoUncompress = false; // we gunzip XMLTV ourselves
    _client.connectionTimeout = const Duration(seconds: 15);
  }
  final HttpClient _client;

  @override
  Future<IptvResponse> open(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final sw = Stopwatch()..start();
    final req = await _client.getUrl(uri).timeout(timeout);
    req.followRedirects = true;
    req.maxRedirects = 5;
    headers.forEach(req.headers.set);
    final res = await req.close().timeout(timeout);
    final h = <String, String>{};
    res.headers.forEach((k, v) {
      if (v.isNotEmpty) h[k.toLowerCase()] = v.first;
    });
    return IptvResponse(
      status: res.statusCode,
      headers: h,
      body: res,
      ttfb: sw.elapsed,
      finalUri: uri,
      onClose: () => res.detachSocket().then((s) => s.destroy(), onError: (_) {}),
    );
  }

  void close() => _client.close(force: true);
}
