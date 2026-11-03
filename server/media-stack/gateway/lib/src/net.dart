import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

class HttpResult {
  HttpResult(this.status, this.body, this.cookies);
  final int status;
  final Object? body; // decoded JSON, or null when empty/not JSON
  final List<Cookie> cookies;
  bool get ok => status >= 200 && status < 300;
}

class UpstreamException implements Exception {
  UpstreamException(this.what);
  final String what; // never contains URLs with secrets or response bodies
  @override
  String toString() => 'UpstreamException: $what';
}

const _maxJsonBytes = 8 * 1024 * 1024;

final HttpClient _client = HttpClient()
  ..connectionTimeout = const Duration(seconds: 5)
  ..idleTimeout = const Duration(seconds: 15);

/// Small JSON-over-HTTP helper for the internal (plain HTTP, media network) services.
Future<HttpResult> jsonRequest(
  String method,
  Uri url, {
  Map<String, String> headers = const {},
  Object? body,
  Duration timeout = const Duration(seconds: 15),
}) async {
  try {
    final req = await _client.openUrl(method, url).timeout(timeout);
    req.followRedirects = false; // never carry the API key to a redirect target
    headers.forEach(req.headers.set);
    req.headers.set('accept', 'application/json');
    if (body != null) {
      final bytes = utf8.encode(jsonEncode(body));
      req.headers.contentType = ContentType.json;
      req.contentLength = bytes.length;
      req.add(bytes);
    }
    final res = await req.close().timeout(timeout);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in res.timeout(timeout)) {
      builder.add(chunk);
      if (builder.length > _maxJsonBytes) {
        throw UpstreamException('response too large');
      }
    }
    Object? decoded;
    if (builder.length > 0) {
      try {
        decoded = jsonDecode(
          utf8.decode(builder.takeBytes(), allowMalformed: true),
        );
      } on FormatException {
        decoded = null;
      }
    }
    return HttpResult(res.statusCode, decoded, res.cookies);
  } on UpstreamException {
    rethrow;
  } on TimeoutException {
    throw UpstreamException('timeout');
  } on SocketException {
    throw UpstreamException('unreachable');
  } on HttpException {
    throw UpstreamException('http error');
  }
}

/// Raw streaming request (images, media). Caller must drain/close the response.
Future<HttpClientResponse> rawRequest(
  Uri url, {
  Map<String, String> headers = const {},
  Duration timeout = const Duration(seconds: 15),
}) async {
  try {
    final req = await _client.getUrl(url).timeout(timeout);
    req.followRedirects = false;
    headers.forEach(req.headers.set);
    return await req.close().timeout(timeout);
  } on TimeoutException {
    throw UpstreamException('timeout');
  } on SocketException {
    throw UpstreamException('unreachable');
  } on HttpException {
    throw UpstreamException('http error');
  }
}
