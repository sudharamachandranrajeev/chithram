import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'media_config.dart';
import 'models.dart';

/// Why a gateway call failed. Messages are for the user; none carries the
/// token, a pairing code or a response body.
enum GatewayErrorKind {
  /// 401: the token is not accepted any more. The app unpairs.
  unauthorized,
  forbidden,
  notFound,

  /// 409: already requested.
  conflict,

  /// 429, with [GatewayException.retryAfter].
  rateLimited,

  /// 502 or 503: the gateway or a service behind it is down (it fails closed).
  unavailable,

  /// The certificate is not the pinned one (or TLS failed).
  pinMismatch,
  network,
  timeout,
  tooLarge,

  /// Not what the contract says (also a redirect, which is never followed).
  badResponse,
  invalidInput,
  server,
}

class GatewayException implements Exception {
  const GatewayException(this.kind, this.message, {this.status, this.retryAfter, this.code});

  final GatewayErrorKind kind;
  final String message;
  final int? status;

  /// For [GatewayErrorKind.rateLimited].
  final Duration? retryAfter;

  /// The gateway's error code (`invalid_code`, `forbidden`...), if it sent one.
  final String? code;

  @override
  String toString() => 'GatewayException(${kind.name}: $message)';
}

/// SHA-256 of a DER certificate, as `AA:BB:...` (the form the gateway prints).
String certFingerprintOfDer(List<int> der) => sha256
    .convert(der)
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(':');

/// Equality that looks at every byte whatever the content.
bool constantTimeBytesEqual(List<int> a, List<int> b) {
  var diff = a.length ^ b.length;
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// True only when [cert] hashes to exactly the pinned [fingerprint]
/// (normalised `AA:BB:...`, 32 bytes).
bool certMatchesPin(X509Certificate cert, String fingerprint) {
  final pinned = normalizeFingerprint(fingerprint);
  if (pinned == null) return false;
  return constantTimeBytesEqual(sha256.convert(cert.der).bytes, fingerprintBytes(pinned));
}

/// The `badCertificateCallback` of a pinned client: accepts the connection
/// only for the expected host and port and a certificate matching the pin.
/// There is no "trust all" path.
bool Function(X509Certificate, String, int) pinnedCertificateCallback({
  required String host,
  required int port,
  required String fingerprint,
}) =>
    (cert, h, p) => h.toLowerCase() == host.toLowerCase() && p == port && certMatchesPin(cert, fingerprint);

typedef HttpClientFactory = HttpClient Function();

const _pinMismatchMessage = 'The server certificate does not match the fingerprint you entered.';

/// An [HttpClient] that only ever talks to the server whose certificate
/// matches [fingerprint].
///
/// The pin is enforced on every new connection, before the HTTP client gets
/// the socket and so before a byte (the token, a pairing code) is written:
/// the `connectionFactory` opens the TLS socket itself and checks the peer
/// certificate against the pin. It does not rely on `badCertificateCallback`
/// alone, which the platform verifier may skip when an OS-trusted CA signed
/// the certificate. The trust store is empty by default; [context] is for
/// tests that need a CA-signed server.
HttpClient createPinnedHttpClient({
  required String host,
  required int port,
  required String fingerprint,
  SecurityContext? context,
}) {
  final ctx = context ?? SecurityContext(withTrustedRoots: false);
  final accept = pinnedCertificateCallback(host: host, port: port, fingerprint: fingerprint);
  final client = HttpClient(context: ctx);
  client.badCertificateCallback = accept;
  client.findProxy = (_) => 'DIRECT';
  client.connectionFactory = (uri, proxyHost, proxyPort) async {
    if (uri.scheme != 'https' || uri.host.toLowerCase() != host.toLowerCase() || uri.port != port) {
      throw const GatewayException(GatewayErrorKind.pinMismatch, _pinMismatchMessage);
    }
    final task = await SecureSocket.startConnect(host, port, context: ctx, onBadCertificate: (c) => accept(c, host, port));
    final verified = task.socket.then<Socket>((socket) {
      final peer = socket.peerCertificate;
      if (peer == null || !certMatchesPin(peer, fingerprint)) {
        socket.destroy();
        throw const GatewayException(GatewayErrorKind.pinMismatch, _pinMismatchMessage);
      }
      return socket;
    });
    return ConnectionTask.fromSocket(verified, task.cancel);
  };
  client.connectionTimeout = const Duration(seconds: 8);
  client.idleTimeout = const Duration(seconds: 10);
  // Never decompress: a gzip stream would break Content-Length and Range.
  client.autoUncompress = false;
  return client;
}

/// 1 MiB is far more than any JSON answer of the gateway.
const maxJsonBytes = 1024 * 1024;

/// A poster at the largest width the gateway serves is well under this.
const maxImageBytes = 2 * 1024 * 1024;

final _hexId = RegExp(r'^[0-9a-f]{32}$');

/// The only thing that talks to the gateway: HTTPS to one pinned host, the
/// device token in the `Authorization` header (never in a URL), no redirects,
/// capped response sizes and timeouts. Nothing here logs.
class GatewayClient {
  GatewayClient({
    required this.host,
    required this.fingerprint,
    this.token,
    HttpClientFactory? clientFactory,
    this.timeout = const Duration(seconds: 15),
  }) : _factory = clientFactory ??
            (() => createPinnedHttpClient(host: host.host, port: host.port, fingerprint: fingerprint));

  final GatewayHost host;
  final String fingerprint;
  final String? token;
  final Duration timeout;
  final HttpClientFactory _factory;
  HttpClient? _client;
  bool _closed = false;

  HttpClient get _http => _client ??= _factory();

  /// Drops connections. The client is not used afterwards.
  void close() {
    _closed = true;
    _client?.close(force: true);
    _client = null;
  }

  // ------------------------------------------------------------------ calls

  /// Exchanges the 6-digit code for a device token.
  Future<PairResult> pair(String code, String deviceName) async {
    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      throw const GatewayException(GatewayErrorKind.invalidInput, 'The pairing code is 6 digits.');
    }
    final raw = await _send('POST', '/v1/pair', body: {'code': code, 'deviceName': deviceName}, auth: false);
    return _parse(raw, PairResult.fromJson);
  }

  Future<Me> me() async => _parse(await _send('GET', '/v1/me'), Me.fromJson);

  Future<List<SearchItem>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty || q.length > 100) {
      throw const GatewayException(GatewayErrorKind.invalidInput, 'Search for 1 to 100 characters.');
    }
    return _parse(await _send('GET', '/v1/search', query: {'q': q}), SearchItem.listFrom);
  }

  /// Requests a title (requesters and admins).
  Future<RequestItem> createRequest(int tmdbId, String type) async =>
      _parse(await _send('POST', '/v1/requests', body: {'tmdbId': tmdbId, 'type': type}), RequestItem.fromJson);

  Future<Paged<RequestItem>> requests({String? cursor}) async =>
      _parse(await _send('GET', '/v1/requests', query: {'cursor': ?cursor}), requestPageFrom);

  /// Admins only.
  Future<RequestItem> decide(int id, {required bool approve}) async => _parse(
        await _send('POST', '/v1/requests/$id/${approve ? 'approve' : 'decline'}', body: const {}),
        RequestItem.fromJson,
      );

  /// Admins only.
  Future<List<DownloadItem>> downloads() async => _parse(await _send('GET', '/v1/downloads'), DownloadItem.listFrom);

  Future<Paged<LibraryItem>> library(LibraryKind kind, {String? cursor}) async => _parse(
        await _send('GET', '/v1/library', query: {'type': kind.name, 'cursor': ?cursor}),
        libraryPageFrom,
      );

  /// Image bytes for a gateway image path (`/v1/images/<id>?w=342`), fetched
  /// with the token header.
  Future<Uint8List> image(String path) async {
    if (!validImagePath(path)) {
      throw const GatewayException(GatewayErrorKind.invalidInput, 'Not an image path.');
    }
    final u = Uri.parse(path);
    final raw = await _send('GET', u.path, query: u.queryParameters, maxBytes: maxImageBytes, json: false);
    final type = raw.contentType;
    if (type == null || !type.startsWith('image/')) {
      throw const GatewayException(GatewayErrorKind.badResponse, 'The gateway sent something other than an image.');
    }
    return raw.bytes;
  }

  /// Opens `GET /v1/stream/<id>` and hands back the response unread, for the
  /// local player proxy. The caller must drain or detach it.
  Future<HttpClientResponse> openStream(String itemId, {String? range}) async {
    if (!_hexId.hasMatch(itemId)) {
      throw const GatewayException(GatewayErrorKind.invalidInput, 'Not an item id.');
    }
    final res = await _guard(() async {
      final req = await _request('GET', '/v1/stream/$itemId', const {});
      if (range != null && RegExp(r'^bytes=[0-9]{0,15}-[0-9]{0,15}$').hasMatch(range)) {
        req.headers.set(HttpHeaders.rangeHeader, range);
      }
      final r = await req.close().timeout(timeout);
      _requirePinned(r);
      return r;
    });
    if (res.statusCode == 200 || res.statusCode == 206 || res.statusCode == 416) return res;
    final err = await _errorFor(res);
    throw err;
  }

  // ------------------------------------------------------------------ plumbing

  /// Second guard behind the connection check: the answer must have come over
  /// a connection whose certificate is the pinned one. Nothing is read otherwise.
  void _requirePinned(HttpClientResponse res) {
    final cert = res.certificate;
    if (cert == null || !certMatchesPin(cert, fingerprint)) {
      unawaited(res.detachSocket().then<void>((s) => s.destroy(), onError: (Object _) {}));
      throw const GatewayException(GatewayErrorKind.pinMismatch, _pinMismatchMessage);
    }
  }

  Future<T> _guard<T>(Future<T> Function() op) async {
    if (_closed) throw const GatewayException(GatewayErrorKind.network, 'The connection was closed.');
    try {
      return await op();
    } on GatewayException {
      rethrow;
    } on TimeoutException {
      throw const GatewayException(GatewayErrorKind.timeout, 'The media server did not answer in time.');
    } on HandshakeException {
      throw const GatewayException(GatewayErrorKind.pinMismatch, _pinMismatchMessage);
    } on TlsException {
      throw const GatewayException(GatewayErrorKind.pinMismatch, _pinMismatchMessage);
    } on SocketException {
      throw const GatewayException(GatewayErrorKind.network, 'Cannot reach the media server.');
    } on HttpException {
      throw const GatewayException(GatewayErrorKind.network, 'The media server connection failed.');
    }
  }

  Future<HttpClientRequest> _request(String method, String path, Map<String, String> query, {bool auth = true}) async {
    final uri = Uri(
      scheme: 'https',
      host: host.host,
      port: host.port,
      path: path,
      queryParameters: query.isEmpty ? null : query,
    );
    final req = await _http.openUrl(method, uri).timeout(timeout);
    req.followRedirects = false;
    req.maxRedirects = 0;
    req.headers.set(HttpHeaders.acceptHeader, 'application/json, image/*');
    req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    if (auth) {
      final t = token;
      if (t == null) throw const GatewayException(GatewayErrorKind.unauthorized, 'This device is not paired.');
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $t');
    }
    return req;
  }

  Future<_Raw> _send(
    String method,
    String path, {
    Map<String, String> query = const {},
    Object? body,
    bool auth = true,
    int maxBytes = maxJsonBytes,
    bool json = true,
  }) {
    return _guard(() async {
      final req = await _request(method, path, query, auth: auth);
      if (body != null) {
        final data = utf8.encode(jsonEncode(body));
        req.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
        req.contentLength = data.length;
        req.add(data);
      }
      final res = await req.close().timeout(timeout);
      _requirePinned(res);
      final bytes = await _readCapped(res, maxBytes);
      final raw = _Raw(res.statusCode, bytes, res.headers.contentType?.mimeType, res.headers.value('retry-after'));
      if (raw.status < 200 || raw.status > 299) throw _errorFromRaw(raw);
      return raw;
    });
  }

  Future<Uint8List> _readCapped(HttpClientResponse res, int max) async {
    final declared = res.contentLength;
    if (declared > max) {
      unawaited(res.drain<void>().catchError((_) {}));
      throw const GatewayException(GatewayErrorKind.tooLarge, 'The media server sent too much data.');
    }
    final out = BytesBuilder(copy: false);
    await for (final chunk in res.timeout(timeout)) {
      out.add(chunk);
      if (out.length > max) {
        throw const GatewayException(GatewayErrorKind.tooLarge, 'The media server sent too much data.');
      }
    }
    return out.takeBytes();
  }

  Future<GatewayException> _errorFor(HttpClientResponse res) async {
    Uint8List bytes;
    try {
      bytes = await _readCapped(res, 4096);
    } on GatewayException {
      bytes = Uint8List(0);
    }
    return _errorFromRaw(_Raw(res.statusCode, bytes, res.headers.contentType?.mimeType, res.headers.value('retry-after')));
  }

  T _parse<T>(_Raw raw, T Function(Object?) build) {
    if (raw.contentType != 'application/json') {
      throw const GatewayException(GatewayErrorKind.badResponse, 'The media server sent an unexpected answer.');
    }
    try {
      return build(jsonDecode(utf8.decode(raw.bytes)));
    } on ModelError {
      throw const GatewayException(GatewayErrorKind.badResponse, 'The media server sent an unexpected answer.');
    } on FormatException {
      throw const GatewayException(GatewayErrorKind.badResponse, 'The media server sent an unexpected answer.');
    }
  }
}

class _Raw {
  const _Raw(this.status, this.bytes, this.contentType, this.retryAfter);

  final int status;
  final Uint8List bytes;
  final String? contentType;
  final String? retryAfter;
}

/// Maps an HTTP status (and the gateway's `{"error": code}`) onto an error.
GatewayException _errorFromRaw(_Raw raw) {
  String? code;
  if (raw.contentType == 'application/json') {
    try {
      final j = jsonDecode(utf8.decode(raw.bytes));
      if (j is Map && j['error'] is String) {
        final c = j['error'] as String;
        if (RegExp(r'^[a-z_]{1,40}$').hasMatch(c)) code = c;
      }
    } on FormatException {
      // No usable code.
    }
  }
  final s = raw.status;
  GatewayException e(GatewayErrorKind k, String m, {Duration? retry}) =>
      GatewayException(k, m, status: s, code: code, retryAfter: retry);
  if (s == 401) {
    return code == 'invalid_code'
        ? e(GatewayErrorKind.unauthorized, 'That pairing code is wrong or has expired.')
        : e(GatewayErrorKind.unauthorized, 'This device is no longer paired.');
  }
  if (s == 403) return e(GatewayErrorKind.forbidden, 'Your role does not allow that.');
  if (s == 404) return e(GatewayErrorKind.notFound, 'Not found.');
  if (s == 409) return e(GatewayErrorKind.conflict, 'Already requested.');
  if (s == 429) {
    final secs = int.tryParse(raw.retryAfter ?? '') ?? 60;
    final retry = Duration(seconds: secs.clamp(1, 3600));
    return e(GatewayErrorKind.rateLimited, 'Too many attempts. Try again in ${retry.inSeconds} s.', retry: retry);
  }
  if (s == 502 || s == 503) return e(GatewayErrorKind.unavailable, 'The media service is unavailable. Try again later.');
  if (s >= 300 && s < 400) return e(GatewayErrorKind.badResponse, 'The media server tried to redirect; refused.');
  if (s >= 500) return e(GatewayErrorKind.server, 'The media server had an error.');
  return e(GatewayErrorKind.badResponse, 'The media server refused the request.');
}
