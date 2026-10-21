import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'identity.dart';
import 'net.dart';
import 'protocol.dart';

final _group = InternetAddress('224.0.0.167');

/// Multicast announce and the answer to other devices' announcements.
///
/// The only outbound traffic is: our announcement to the multicast group, a
/// `POST /register` to a device that announced itself (pinned to the
/// fingerprint it announced), and a unicast UDP reply when that fails.
class Discovery {
  Discovery({
    required this.identity,
    required this.port,
    required this.allowLoopback,
    required this.info,
    int? replyPort,
  }) : replyPort = replyPort ?? port;

  final LsIdentity identity;
  final int port;
  final bool allowLoopback;

  /// Where fallback replies go: the multicast port, the same for every device.
  final int replyPort;

  /// Our description, with `announce` set for multicast.
  final Map<String, Object?> Function({bool announce}) info;

  RawDatagramSocket? _listener;
  final _senders = <RawDatagramSocket>[];
  final _timers = <Timer>[];
  final _lastHeard = <String, DateTime>{};
  int _registering = 0;
  String? error;

  Future<void> start() async {
    try {
      try {
        _listener = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true, reusePort: true);
      } on SocketException {
        // Windows has no SO_REUSEPORT.
        _listener = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true);
      } on UnsupportedError {
        _listener = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true);
      }
    } on SocketException catch (e) {
      error = 'Discovery is off: ${e.message}';
      return;
    }
    final l = _listener!;
    l.readEventsEnabled = true;
    l.listen((event) {
      if (event != RawSocketEvent.read) return;
      final d = l.receive();
      if (d != null) _onDatagram(d);
    });
    for (final p in await privateInterfaces()) {
      try {
        l.joinMulticast(_group, p.interface);
      } on OSError {
        // That interface cannot do multicast; the others may.
      } on SocketException {
        // Same.
      }
      try {
        final s = await RawDatagramSocket.bind(p.address, 0);
        s.multicastHops = 1;
        _pickOutgoing(s, p.address);
        _senders.add(s);
      } on SocketException {
        // Skip this interface.
      }
    }
  }

  /// IP_MULTICAST_IF, so the announcement leaves on this interface (Dart has
  /// no working setter for it). Best effort: the default route is the fallback.
  void _pickOutgoing(RawDatagramSocket s, InternetAddress local) {
    try {
      final option = (Platform.isLinux || Platform.isAndroid) ? 32 : 9;
      s.setRawOption(RawSocketOption(RawSocketOption.levelIPv4, option, local.rawAddress));
    } on Object {
      // Unsupported here.
    }
  }

  void announceBurst() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    for (final ms in const [0, 500, 2000]) {
      _timers.add(Timer(Duration(milliseconds: ms), _sendAnnounce));
    }
  }

  void _sendAnnounce() {
    final data = utf8.encode(jsonEncode(info(announce: true)));
    for (final s in _senders) {
      try {
        s.send(data, _group, port);
      } catch (_) {
        // Interface went away.
      }
    }
  }

  void _onDatagram(Datagram d) {
    if (d.data.length > 4096) return;
    final from = d.address;
    if (!(isPrivateV4(from) || (allowLoopback && from.isLoopback))) return;
    final Object? j;
    try {
      j = jsonDecode(utf8.decode(d.data));
    } on FormatException {
      return;
    }
    if (j is! Map || j['announce'] != true) return;
    final fingerprint = j['fingerprint'];
    final peerPort = j['port'];
    if (fingerprint is! String || fingerprint == identity.fingerprint || PeerInfo.parse(j) == null) return;
    if (peerPort is! int || peerPort < 1 || peerPort > 65535) return;
    // One answer per device every few seconds: a flood costs us nothing.
    final now = DateTime.now();
    final last = _lastHeard[from.address];
    if (last != null && now.difference(last) < const Duration(seconds: 5)) return;
    if (_lastHeard.length > 256) _lastHeard.clear();
    _lastHeard[from.address] = now;
    unawaited(_answer(from, peerPort, fingerprint, j['protocol'] == 'https'));
  }

  Future<void> _answer(InternetAddress from, int peerPort, String fingerprint, bool https) async {
    if (_registering >= 8) return;
    _registering++;
    try {
      if (https && await _register(from, peerPort, fingerprint)) return;
      _listener?.send(utf8.encode(jsonEncode(info())), from, replyPort);
    } catch (_) {
      // The device is gone; nothing to do.
    } finally {
      _registering--;
    }
  }

  /// `POST /register` over HTTPS to a device that announced itself, accepting
  /// only the certificate whose fingerprint it announced.
  Future<bool> _register(InternetAddress to, int peerPort, String fingerprint) async {
    final client = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..connectionTimeout = const Duration(seconds: 3)
      ..badCertificateCallback = (cert, host, p) => LsIdentity.fingerprintOf(cert.der) == fingerprint.toUpperCase();
    try {
      final req = await client.postUrl(Uri(scheme: 'https', host: to.address, port: peerPort, path: '$apiBase/register'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(info()));
      final res = await req.close().timeout(const Duration(seconds: 3));
      await res.drain<void>();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> stop() async {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _listener?.close();
    _listener = null;
    for (final s in _senders) {
      s.close();
    }
    _senders.clear();
  }
}
