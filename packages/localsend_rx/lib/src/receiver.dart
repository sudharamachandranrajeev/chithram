import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'discovery.dart';
import 'identity.dart';
import 'models.dart';
import 'net.dart';
import 'protocol.dart';

class _Session {
  _Session(this.id, this.ownerIp, this.alias, this.files);

  final String id;
  final String ownerIp;
  final String alias;
  final Map<String, AcceptedFile> files;
  Timer? idle;

  bool get finished => files.values.every((f) => f.uploaded);
}

/// Receives LocalSend transfers while it is running.
///
/// Security model: listens only on private IPv4 addresses (never loopback,
/// tunnels or public addresses), refuses any request whose remote address is
/// not private, takes only text, `.txt` and `.torrent` under small caps, asks
/// the user for every transfer, and never writes anything to disk.
class LsReceiver {
  LsReceiver({required this.identity, required this.config, required this.onOffer, DateTime Function()? clock})
      : _pins = PinGuard(clock: clock);

  final LsIdentity identity;
  final LsReceiverConfig config;

  /// Asked for every transfer; return false to reject it.
  final Future<bool> Function(LsOffer offer) onOffer;

  final PinGuard _pins;
  final _received = StreamController<LsIncoming>.broadcast();
  final _servers = <HttpServer>[];
  final _rng = Random.secure();
  Discovery? _discovery;
  _Session? _session;

  /// A prompt is open or an accepted transfer is still uploading.
  bool _busy = false;
  bool _running = false;
  int _inflight = 0;

  bool get running => _running;
  Stream<LsIncoming> get received => _received.stream;

  /// Addresses the server listens on.
  List<InternetAddress> get addresses => [for (final s in _servers) s.address];

  /// The HTTPS port (the first listener's; all share one unless tests asked for port 0).
  int? get port => _servers.isEmpty ? null : _servers.first.port;

  /// Why multicast discovery is off, if it is.
  String? get discoveryError => _discovery?.error;

  Map<String, Object?> _info({bool announce = false}) => {
        'alias': config.alias,
        'version': protocolVersion,
        'deviceModel': config.deviceModel,
        'deviceType': config.deviceType,
        'fingerprint': identity.fingerprint,
        'port': port ?? config.port,
        'protocol': 'https',
        'download': false,
        if (announce) 'announce': true,
      };

  Future<void> start() async {
    if (_running) return;
    final targets = config.bindAddresses ?? [for (final p in await privateInterfaces()) p.address];
    if (targets.isEmpty) {
      throw const LsBindException('No private network address found. Connect to your home network.');
    }
    final context = identity.securityContext();
    try {
      for (final a in targets) {
        try {
          final s = await HttpServer.bindSecure(a, config.port, context);
          s.idleTimeout = const Duration(seconds: 15);
          s.serverHeader = null;
          s.listen(_handle, onError: (Object _) {}, cancelOnError: false);
          _servers.add(s);
        } on SocketException {
          // Another address may still work; report only if none does.
        }
      }
    } catch (_) {
      await _closeServers();
      rethrow;
    }
    if (_servers.isEmpty) {
      throw LsBindException(
        'Port ${config.port} is in use. Close other LocalSend apps and try again.',
      );
    }
    _running = true;
    if (config.multicast) {
      _discovery = Discovery(
        identity: identity,
        port: config.port,
        allowLoopback: config.allowLoopback,
        info: _info,
      );
      await _discovery!.start();
      unawaited(announce());
    }
  }

  Future<void> _closeServers() async {
    final servers = List.of(_servers);
    _servers.clear();
    await Future.wait([for (final s in servers) s.close(force: true)]);
  }

  Future<void> stop() async {
    if (!_running && _servers.isEmpty) return;
    _running = false;
    await _discovery?.stop();
    _discovery = null;
    _endSession();
    await _closeServers();
  }

  /// Sends the multicast announce burst (0, 0.5 and 2 s after start).
  Future<void> announce() async => _discovery?.announceBurst();

  Future<void> dispose() async {
    await stop();
    await _received.close();
  }

  // ---- requests ----------------------------------------------------------

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    if (_inflight >= 16) return _reply(res, 503, 'Busy');
    _inflight++;
    try {
      final remote = req.connectionInfo?.remoteAddress;
      if (remote == null || !(isPrivateV4(remote) || (config.allowLoopback && remote.isLoopback))) {
        return await _reply(res, 403, 'Forbidden');
      }
      final path = req.uri.path;
      if (!path.startsWith('$apiBase/')) return await _reply(res, 404, 'Not found');
      switch (path.substring(apiBase.length)) {
        case '/info':
          if (req.method != 'GET') return await _reply(res, 405, 'Method not allowed');
          await _reply(res, 200, _info());
        case '/register':
          if (req.method != 'POST') return await _reply(res, 405, 'Method not allowed');
          await _register(req);
        case '/prepare-upload':
          if (req.method != 'POST') return await _reply(res, 405, 'Method not allowed');
          await _prepare(req, remote);
        case '/upload':
          if (req.method != 'POST') return await _reply(res, 405, 'Method not allowed');
          await _upload(req, remote);
        case '/cancel':
          if (req.method != 'POST') return await _reply(res, 405, 'Method not allowed');
          await _cancel(req, remote);
        default:
          await _reply(res, 404, 'Not found');
      }
    } catch (_) {
      try {
        await _reply(res, 500, 'Internal error');
      } catch (_) {
        // The peer is gone.
      }
    } finally {
      _inflight--;
    }
  }

  /// Answers with [body]: a map is sent as JSON, a string as `{"message": ...}`.
  Future<void> _reply(HttpResponse res, int status, [Object? body]) async {
    res.statusCode = status;
    if (body != null) {
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(body is String ? {'message': body} : body));
    }
    await res.close();
  }

  /// Ends the connection without reading the rest of the request body.
  Future<void> _drop(HttpResponse res, int status, String reason) async {
    try {
      final socket = await res.detachSocket(writeHeaders: false);
      socket.add(ascii.encode('HTTP/1.1 $status $reason\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'));
      await socket.flush();
      socket.destroy();
    } catch (_) {
      // Already closed.
    }
  }

  /// Reads at most [cap] bytes; null when the body is larger or stalls.
  Future<Uint8List?> _readBody(HttpRequest req, int cap) async {
    if (req.contentLength > cap) return null;
    final bytes = BytesBuilder(copy: false);
    try {
      await for (final chunk in req.timeout(config.readTimeout)) {
        bytes.add(chunk);
        if (bytes.length > cap) return null;
      }
    } on TimeoutException {
      return null;
    }
    return bytes.takeBytes();
  }

  Future<void> _register(HttpRequest req) async {
    final body = await _readBody(req, maxRegisterBodyBytes);
    if (body == null) return _drop(req.response, 400, 'Bad Request');
    Object? j;
    try {
      j = jsonDecode(utf8.decode(body));
    } on FormatException {
      return _reply(req.response, 400, 'Invalid body');
    }
    if (PeerInfo.parse(j) == null) return _reply(req.response, 400, 'Invalid body');
    await _reply(req.response, 200, _info());
  }

  Future<void> _prepare(HttpRequest req, InternetAddress remote) async {
    final res = req.response;
    final ip = remote.address;
    if (_pins.limited(ip)) return _reply(res, 429, 'Too many attempts');
    final pin = config.pin;
    if (pin != null) {
      final given = req.uri.queryParameters['pin'];
      if (given == null || given.isEmpty) return _reply(res, 401, 'PIN required');
      if (!constantTimeEquals(given, pin)) {
        _pins.fail(ip);
        return _reply(res, _pins.limited(ip) ? 429 : 401, 'Invalid PIN');
      }
    }
    final body = await _readBody(req, maxPrepareBodyBytes);
    if (body == null) return _drop(res, 400, 'Bad Request');
    PeerInfo? peer;
    Object? files;
    try {
      final j = jsonDecode(utf8.decode(body));
      if (j is Map) {
        peer = PeerInfo.parse(j['info']);
        files = j['files'];
      }
    } on FormatException {
      // Falls through to the 400 below.
    }
    if (peer == null || files is! Map || files.isEmpty) return _reply(res, 400, 'Invalid body');
    final filesJson = files;
    if (filesJson.length > maxFiles) return _reply(res, 403, 'Too many files');

    final accepted = <String, AcceptedFile>{};
    for (final entry in filesJson.entries) {
      final file = acceptFile(entry.value);
      // The map key and the file's own id must agree.
      if (file != null && file.id == entry.key) accepted[file.id] = file;
    }
    if (accepted.isEmpty) return _reply(res, 403, 'Nothing Chithram accepts');

    if (_busy) return _reply(res, 409, 'Another transfer is in progress');
    _busy = true;
    try {
      final offer = LsOffer(
        senderAlias: peer.alias,
        senderAddress: ip,
        senderModel: peer.model,
        files: [
          for (final f in accepted.values)
            LsOfferedFile(id: f.id, name: f.name, size: f.size, type: f.type, preview: f.preview),
        ],
      );
      bool ok;
      try {
        ok = await onOffer(offer).timeout(config.promptTimeout);
      } catch (_) {
        ok = false;
      }
      if (!ok || !_running) {
        _busy = false;
        return await _reply(res, 403, 'Rejected');
      }

      final messages = [for (final f in accepted.values) if (f.kind == FileKind.message) f];
      final uploads = [for (final f in accepted.values) if (f.kind != FileKind.message) f];
      void emitMessages() {
        for (final m in messages) {
          if (!_received.isClosed) _received.add(TextIncoming(m.preview!, peer!.alias, ip));
        }
      }

      if (uploads.isEmpty) {
        _busy = false;
        await _reply(res, 204);
        emitMessages();
        return;
      }
      final session = _Session(_token(), ip, peer.alias, accepted);
      for (final f in accepted.values) {
        f.token = _token();
        // Inline messages need no upload; mark them done so only real
        // uploads keep the session open.
        if (f.kind == FileKind.message) f.uploaded = true;
      }
      _session = session;
      _touch(session);
      await _reply(res, 200, {
        'sessionId': session.id,
        'files': {for (final f in uploads) f.id: f.token},
      });
      emitMessages();
    } catch (_) {
      if (_session == null) _busy = false;
      rethrow;
    }
  }

  void _touch(_Session s) {
    s.idle?.cancel();
    s.idle = Timer(config.sessionIdle, () {
      if (identical(_session, s)) _endSession();
    });
  }

  void _endSession() {
    _session?.idle?.cancel();
    _session = null;
    _busy = false;
  }

  Future<void> _upload(HttpRequest req, InternetAddress remote) async {
    final res = req.response;
    final q = req.uri.queryParameters;
    final s = _session;
    final file = s?.files[q['fileId']];
    if (s == null ||
        q['sessionId'] != s.id ||
        s.ownerIp != remote.address ||
        file == null ||
        file.kind == FileKind.message ||
        file.uploaded ||
        !constantTimeEquals(q['token'] ?? '', file.token)) {
      return _reply(res, 403, 'Forbidden');
    }
    _touch(s);
    // The declared size is the cap: a longer body is refused before it is read.
    if (req.contentLength >= 0 && req.contentLength != file.size) {
      return _drop(res, 400, 'Bad Request');
    }
    final bytes = BytesBuilder(copy: false);
    try {
      await for (final chunk in req.timeout(config.readTimeout)) {
        bytes.add(chunk);
        if (bytes.length > file.size) return await _drop(res, 400, 'Bad Request');
      }
    } on TimeoutException {
      return await _drop(res, 400, 'Bad Request');
    }
    final data = bytes.takeBytes();
    if (data.length != file.size) return _reply(res, 400, 'Size does not match the offer');
    final expected = file.sha256;
    if (expected != null && sha256.convert(data).toString() != expected) {
      return _reply(res, 422, 'Checksum mismatch');
    }
    LsIncoming incoming;
    if (file.kind == FileKind.torrent) {
      if (!looksLikeTorrent(data)) return _reply(res, 400, 'Not a torrent file');
      incoming = FileIncoming(file.name, data, s.alias, s.ownerIp);
    } else {
      try {
        incoming = TextIncoming(utf8.decode(data), s.alias, s.ownerIp);
      } on FormatException {
        return _reply(res, 400, 'Not UTF-8 text');
      }
    }
    file.uploaded = true;
    await _reply(res, 200);
    if (!_received.isClosed) _received.add(incoming);
    if (identical(_session, s) && s.finished) _endSession();
  }

  Future<void> _cancel(HttpRequest req, InternetAddress remote) async {
    final s = _session;
    if (s == null || req.uri.queryParameters['sessionId'] != s.id || s.ownerIp != remote.address) {
      return _reply(req.response, 403, 'Forbidden');
    }
    _endSession();
    await _reply(req.response, 200);
  }

  String _token() => [for (var i = 0; i < 16; i++) _rng.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
}
