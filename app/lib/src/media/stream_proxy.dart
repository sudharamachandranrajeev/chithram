import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'gateway_client.dart';

/// The players (libmpv, ExoPlayer) cannot pin the gateway's self-signed
/// certificate and a player URL must not carry the token. So playback goes
/// through this: a server on 127.0.0.1 only, on a random port, answering one
/// secret random path for one item. It forwards `GET /v1/stream/<id>` over the
/// pinned connection with the token in the header, passing Range through.
///
/// The path is a one-time local capability, not the device token. The proxy
/// refuses other paths, other methods and any `Host` that is not the loopback
/// address it listens on (DNS rebinding). The secret path is compared in
/// constant time and at most [maxConnections] requests run at once.
class StreamProxy {
  StreamProxy._(this._server, this._client, this._itemId, this._secret, this._onUnauthorized, this._onClosed, this.maxConnections);

  final HttpServer _server;
  final GatewayClient _client;
  final String _itemId;
  final String _secret;
  final void Function()? _onUnauthorized;
  final void Function(StreamProxy)? _onClosed;

  /// Requests served at the same time; one more gets a 503.
  final int maxConnections;
  int _active = 0;
  bool _closed = false;

  /// Starts a proxy for [itemId]. [client] must be the paired, pinned client.
  /// [onUnauthorized] runs when the gateway says the token is dead (401);
  /// [onClosed] runs once the proxy has stopped.
  static Future<StreamProxy> start(
    GatewayClient client,
    String itemId, {
    void Function()? onUnauthorized,
    void Function(StreamProxy)? onClosed,
    int maxConnections = 8,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final rng = Random.secure();
    final secret = [for (var i = 0; i < 16; i++) rng.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
    final p = StreamProxy._(server, client, itemId, secret, onUnauthorized, onClosed, maxConnections);
    unawaited(p._serve());
    return p;
  }

  /// What to give the player: plain http on loopback, no credentials.
  String get url => 'http://127.0.0.1:${_server.port}/$_secret';

  /// Stops listening and drops every open request. Safe to call twice.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _server.close(force: true);
    _onClosed?.call(this);
  }

  Future<void> _serve() async {
    await for (final req in _server) {
      unawaited(_handle(req).catchError((Object _) {
        try {
          req.response.close();
        } catch (_) {}
      }));
    }
  }

  bool _secretPathOk(String path) =>
      constantTimeBytesEqual(utf8.encode(path), utf8.encode('/$_secret'));

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    final hostOk = req.headers.host == '127.0.0.1' && req.headers.port == _server.port;
    // Every check runs; the answer does not say which one failed.
    final pathOk = _secretPathOk(req.uri.path);
    final methodOk = req.method == 'GET' || req.method == 'HEAD';
    if (!hostOk || !methodOk || !pathOk) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    if (_active >= maxConnections) {
      res.statusCode = HttpStatus.serviceUnavailable;
      await res.close();
      return;
    }
    _active++;
    try {
      await _forward(req, res);
    } finally {
      _active--;
    }
  }

  Future<void> _forward(HttpRequest req, HttpResponse res) async {
    final HttpClientResponse up;
    try {
      up = await _client.openStream(_itemId, range: req.headers.value(HttpHeaders.rangeHeader));
    } on GatewayException catch (e) {
      if (e.kind == GatewayErrorKind.unauthorized) _onUnauthorized?.call();
      res.statusCode = switch (e.kind) {
        GatewayErrorKind.notFound => HttpStatus.notFound,
        GatewayErrorKind.unauthorized => HttpStatus.unauthorized,
        GatewayErrorKind.forbidden => HttpStatus.forbidden,
        GatewayErrorKind.unavailable => HttpStatus.serviceUnavailable,
        _ => HttpStatus.badGateway,
      };
      await res.close();
      return;
    }
    res.statusCode = up.statusCode;
    for (final name in const ['content-type', 'content-length', 'content-range', 'accept-ranges']) {
      final v = up.headers.value(name);
      if (v != null) res.headers.set(name, v);
    }
    if (req.method == 'HEAD') {
      // Headers only. The upstream body is never read: drop the connection.
      unawaited(up.detachSocket().then<void>((s) => s.destroy(), onError: (Object _) {}));
      await res.close();
      return;
    }
    await res.addStream(up);
    await res.close();
  }
}
