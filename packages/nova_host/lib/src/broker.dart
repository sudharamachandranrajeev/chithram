import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'domains.dart';

class BrokerDenied implements Exception {
  BrokerDenied(this.reason);
  final String reason;
  @override
  String toString() => 'BrokerDenied: $reason';
}

class Socks5Config {
  const Socks5Config(this.host, this.port, {this.user, this.password});
  final String host;
  final int port;
  final String? user;
  final String? password;
}

class BrokerPolicy {
  const BrokerPolicy({
    this.requestTimeout = const Duration(seconds: 15),
    this.maxRequests = 20,
    this.maxBodyBytes = 5 * 1024 * 1024,
    this.maxRedirects = 5,
    this.testMode = false,
    this.hostOverrides = const {},
    this.socks5,
  });

  final Duration requestTimeout;
  final int maxRequests;
  final int maxBodyBytes;
  final int maxRedirects;

  /// Tests only: allows loopback/private destinations and honours [hostOverrides].
  final bool testMode;

  /// Tests only: fake DNS (`example.test` -> 127.0.0.1).
  final Map<String, InternetAddress> hostOverrides;

  /// VPN guard on: every connection goes through this SOCKS5 proxy (remote DNS).
  final Socks5Config? socks5;
}

class BrokerResponse {
  BrokerResponse(this.status, this.reason, this.headers, this.body, this.url);
  final int status;
  final String reason;
  final Map<String, String> headers;
  final Uint8List body;
  final String url;
}

/// Performs the HTTP requests a sandboxed plugin asks for. One broker per search:
/// it carries the per-search request budget.
class HttpBroker {
  HttpBroker({required this.allowlist, this.policy = const BrokerPolicy()});

  final HostAllowlist allowlist;
  final BrokerPolicy policy;
  int requests = 0;
  final List<String> log = [];

  Future<BrokerResponse> fetch(String method, String url, Map<String, String> headers, List<int>? body) async {
    requests++;
    if (requests > policy.maxRequests) {
      throw _deny('request budget (${policy.maxRequests}) exhausted', url);
    }
    var current = url;
    var m = method.toUpperCase();
    var payload = body;
    for (var hop = 0; hop <= policy.maxRedirects; hop++) {
      final r = await _one(m, current, headers, payload).timeout(policy.requestTimeout,
          onTimeout: () => throw _deny('timeout (${policy.requestTimeout.inSeconds}s)', current));
      if (const {301, 302, 303, 307, 308}.contains(r.status) && r.headers['location'] != null) {
        current = Uri.parse(current).resolve(r.headers['location']!).toString();
        if (r.status != 307 && r.status != 308) {
          m = 'GET';
          payload = null;
        }
        // The next hop is re-checked against the allowlist in _one.
        continue;
      }
      log.add('ok ${r.status} ${r.body.length}B $current');
      return r;
    }
    throw _deny('too many redirects', url);
  }

  BrokerDenied _deny(String why, String url) {
    log.add('DENIED $why: $url');
    return BrokerDenied(why);
  }

  Future<BrokerResponse> _one(String method, String url, Map<String, String> headers, List<int>? body) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) throw _deny('bad url', url);
    if (uri.scheme != 'http' && uri.scheme != 'https') throw _deny('scheme ${uri.scheme} not allowed', url);
    if (uri.userInfo.isNotEmpty) throw _deny('credentials in url', url);
    if (!allowlist.allows(uri.host)) throw _deny('host ${uri.host} not in allowlist', url);
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    for (final e in headers.entries) {
      if (e.key.contains(RegExp(r'[\r\n:]')) || e.value.contains(RegExp(r'[\r\n]'))) {
        throw _deny('bad header', url);
      }
    }
    if (body != null && body.length > policy.maxBodyBytes) throw _deny('request body too large', url);

    _Conn conn;
    final socks = policy.socks5;
    if (socks != null) {
      conn = await _socks5Connect(socks, uri.host, port);
    } else {
      final ip = await _pick(uri.host);
      conn = await _Conn.connect(ip, port);
    }
    try {
      if (uri.scheme == 'https') conn = await conn.secure(uri.host);
      return await _exchange(conn, method, uri, headers, body);
    } finally {
      conn.close();
    }
  }

  Future<InternetAddress> _pick(String host) async {
    final lit = InternetAddress.tryParse(host);
    List<InternetAddress> addrs;
    if (lit != null) {
      addrs = [lit];
    } else if (policy.testMode && policy.hostOverrides.containsKey(host.toLowerCase())) {
      addrs = [policy.hostOverrides[host.toLowerCase()]!];
    } else {
      try {
        addrs = await InternetAddress.lookup(host);
      } on SocketException {
        throw _deny('dns failure', host);
      }
    }
    if (addrs.isEmpty) throw _deny('no address', host);
    if (!policy.testMode) {
      // Every address must be public, so one private A record cannot sneak through.
      for (final a in addrs) {
        if (!isPublicAddress(a)) throw _deny('address ${a.address} is not public', host);
      }
    }
    return addrs.first;
  }

  Future<BrokerResponse> _exchange(_Conn c, String method, Uri uri, Map<String, String> headers, List<int>? body) async {
    final skip = {'host', 'connection', 'content-length', 'transfer-encoding'};
    final sb = StringBuffer();
    final path = (uri.path.isEmpty ? '/' : uri.path) + (uri.hasQuery ? '?${uri.query}' : '');
    sb.write('$method $path HTTP/1.1\r\n');
    sb.write('Host: ${uri.host}${uri.hasPort ? ':${uri.port}' : ''}\r\n');
    sb.write('Connection: close\r\n');
    final lower = headers.keys.map((k) => k.toLowerCase()).toSet();
    if (!lower.contains('accept-encoding')) sb.write('Accept-Encoding: identity\r\n');
    for (final e in headers.entries) {
      if (!skip.contains(e.key.toLowerCase())) sb.write('${e.key}: ${e.value}\r\n');
    }
    if (body != null) sb.write('Content-Length: ${body.length}\r\n');
    sb.write('\r\n');
    await c.write([...latin1.encode(sb.toString()), ...?body]);

    final buf = BytesBuilder(copy: false);
    int? headEnd;
    int status = 0;
    var reason = '';
    final respHeaders = <String, String>{};
    int? contentLength;
    var chunked = false;
    final cap = policy.maxBodyBytes + 70 * 1024;
    var nChunks = 0;
    while (true) {
      final chunk = await c.next();
      if (chunk == null) break;
      nChunks++;
      buf.add(chunk);
      if (buf.length > cap) throw _deny('response too large', uri.toString());
      final bytes = buf.toBytes();
      buf.clear();
      buf.add(bytes);
      if (headEnd == null) {
        final i = _find(bytes, const [13, 10, 13, 10]);
        if (i < 0) {
          if (bytes.length > 64 * 1024) throw _deny('response headers too large', uri.toString());
          continue;
        }
        headEnd = i + 4;
        final lines = latin1.decode(bytes.sublist(0, i)).split('\r\n');
        final m = RegExp(r'^HTTP/1\.[01] (\d{3})\s?(.*)$').firstMatch(lines.first);
        if (m == null) throw _deny('bad status line', uri.toString());
        status = int.parse(m.group(1)!);
        reason = m.group(2)!;
        for (final l in lines.skip(1)) {
          final k = l.indexOf(':');
          if (k > 0) respHeaders[l.substring(0, k).trim().toLowerCase()] = l.substring(k + 1).trim();
        }
        contentLength = int.tryParse(respHeaders['content-length'] ?? '');
        chunked = (respHeaders['transfer-encoding'] ?? '').toLowerCase().contains('chunked');
        if (contentLength != null && contentLength > policy.maxBodyBytes) {
          throw _deny('body larger than ${policy.maxBodyBytes} bytes', uri.toString());
        }
      }
      final have = bytes.length - headEnd;
      if (!chunked && contentLength != null && have >= contentLength) break;
      if (chunked && have >= 5 && _endsWithTerminator(bytes)) break;
      if (have > policy.maxBodyBytes + (chunked ? 64 * 1024 : 0)) throw _deny('body too large', uri.toString());
    }
    if (headEnd == null) throw _deny('connection closed before headers', uri.toString());
    final all = buf.toBytes();
    if (all.length == headEnd && status == 200) {
      log.add('DEBUG empty body: total=${all.length} headEnd=$headEnd cl=$contentLength chunked=$chunked chunks=$nChunks headers=$respHeaders');
    }
    var payload = Uint8List.sublistView(all, headEnd);
    if (method == 'HEAD' || status == 204 || status == 304) {
      payload = Uint8List(0);
    } else if (chunked) {
      payload = _dechunk(payload, uri.toString());
    } else if (contentLength != null && payload.length > contentLength) {
      payload = Uint8List.sublistView(payload, 0, contentLength);
    }
    if (payload.length > policy.maxBodyBytes) throw _deny('body larger than ${policy.maxBodyBytes} bytes', uri.toString());
    return BrokerResponse(status, reason, respHeaders, payload, uri.toString());
  }

  Uint8List _dechunk(Uint8List d, String url) {
    final out = BytesBuilder(copy: false);
    var i = 0;
    while (true) {
      final e = _find(d, const [13, 10], i);
      if (e < 0) break;
      final size = int.tryParse(latin1.decode(d.sublist(i, e)).split(';').first.trim(), radix: 16);
      if (size == null) throw _deny('bad chunk', url);
      i = e + 2;
      if (size == 0) break;
      if (i + size > d.length) break;
      out.add(d.sublist(i, i + size));
      if (out.length > policy.maxBodyBytes) throw _deny('body too large', url);
      i += size + 2;
    }
    return out.toBytes();
  }

  bool _endsWithTerminator(Uint8List b) {
    final n = b.length;
    return n >= 5 && b[n - 5] == 48 && b[n - 4] == 13 && b[n - 3] == 10 && b[n - 2] == 13 && b[n - 1] == 10;
  }

  int _find(List<int> hay, List<int> needle, [int from = 0]) {
    for (var i = from; i <= hay.length - needle.length; i++) {
      var ok = true;
      for (var j = 0; j < needle.length; j++) {
        if (hay[i + j] != needle[j]) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }

  Future<_Conn> _socks5Connect(Socks5Config s, String host, int port) async {
    final c = await _Conn.connect((await InternetAddress.lookup(s.host)).first, s.port);
    try {
      final auth = s.user != null;
      log.add('socks5: connected to proxy, greeting');
      await c.write(auth ? [5, 2, 0, 2] : [5, 1, 0]);
      final m = await c.readExact(2);
      if (m[0] != 5) throw _deny('socks5: bad proxy reply', host);
      if (m[1] == 2 && auth) {
        final u = utf8.encode(s.user!), p = utf8.encode(s.password ?? '');
        await c.write([1, u.length, ...u, p.length, ...p]);
        final r = await c.readExact(2);
        if (r[1] != 0) throw _deny('socks5: authentication refused', host);
      } else if (m[1] != 0) {
        throw _deny('socks5: no acceptable auth method', host);
      }
      final lit = InternetAddress.tryParse(host);
      final addr = lit != null
          ? [lit.type == InternetAddressType.IPv4 ? 1 : 4, ...lit.rawAddress]
          : [3, utf8.encode(host).length, ...utf8.encode(host)];
      await c.write([5, 1, 0, ...addr, port >> 8, port & 0xff]);
      log.add('socks5: method ok, requesting $host:$port');
      final h = await c.readExact(4);
      if (h[1] != 0) throw _deny('socks5: connect refused (code ${h[1]})', host);
      final skip = h[3] == 1 ? 4 : h[3] == 4 ? 16 : (await c.readExact(1))[0];
      await c.readExact(skip + 2);
      return c;
    } catch (_) {
      c.close();
      rethrow;
    }
  }
}

/// True for globally routable unicast addresses only.
bool isPublicAddress(InternetAddress a) {
  final b = a.rawAddress;
  if (a.type == InternetAddressType.IPv4) {
    final x = b[0], y = b[1];
    if (x == 0 || x == 10 || x == 127 || x >= 224) return false;
    if (x == 100 && y >= 64 && y <= 127) return false;
    if (x == 169 && y == 254) return false;
    if (x == 172 && y >= 16 && y <= 31) return false;
    if (x == 192 && y == 168) return false;
    if (x == 192 && y == 0 && b[2] == 0) return false;
    if (x == 198 && (y == 18 || y == 19)) return false;
    return true;
  }
  if (b.length != 16) return false;
  if (b.sublist(0, 15).every((v) => v == 0) && (b[15] == 0 || b[15] == 1)) return false;
  if (b[0] == 0xfe && (b[1] & 0xc0) == 0x80) return false;
  if ((b[0] & 0xfe) == 0xfc) return false;
  if (b[0] == 0xff) return false;
  if (b.sublist(0, 10).every((v) => v == 0) && b[10] == 0xff && b[11] == 0xff) {
    return isPublicAddress(InternetAddress.fromRawAddress(Uint8List.fromList(b.sublist(12))));
  }
  return true;
}

/// Event-driven reader/writer over [RawSocket] (plain or TLS), so a SOCKS5
/// handshake can hand the very same connection to TLS.
class _Conn {
  _Conn(this._raw) {
    _sub = _raw.listen(_onEvent, onError: (_) => _closed = true, onDone: () => _closed = true);
  }

  final RawSocket _raw;
  late StreamSubscription<RawSocketEvent> _sub;
  final Queue<Uint8List> _chunks = Queue();
  Completer<void>? _wake;
  bool _closed = false;

  static Future<_Conn> connect(InternetAddress ip, int port) async {
    final raw = await RawSocket.connect(ip, port, timeout: const Duration(seconds: 10));
    raw.setOption(SocketOption.tcpNoDelay, true);
    return _Conn(raw);
  }

  void _onEvent(RawSocketEvent e) {
    // Also drain on readClosed: data can still be pending when it arrives (seen on Windows).
    if (e == RawSocketEvent.read || e == RawSocketEvent.readClosed) {
      var d = _raw.read();
      while (d != null && d.isNotEmpty) {
        _chunks.add(d);
        d = _raw.read();
      }
    }
    if (e == RawSocketEvent.readClosed || e == RawSocketEvent.closed) {
      _closed = true;
    }
    final w = _wake;
    _wake = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<Uint8List?> next() async {
    while (_chunks.isEmpty) {
      if (_closed) return null;
      _wake = Completer<void>();
      await _wake!.future;
    }
    return _chunks.removeFirst();
  }

  Future<Uint8List> readExact(int n) async {
    final out = BytesBuilder();
    while (out.length < n) {
      final c = await next();
      if (c == null) throw BrokerDenied('connection closed during handshake');
      final need = n - out.length;
      if (c.length > need) {
        out.add(c.sublist(0, need));
        _chunks.addFirst(Uint8List.sublistView(c, need));
      } else {
        out.add(c);
      }
    }
    return out.toBytes();
  }

  Future<void> write(List<int> data) async {
    var off = 0;
    while (off < data.length) {
      final n = _raw.write(data, off, data.length - off);
      off += n;
      if (n == 0) {
        _raw.writeEventsEnabled = true;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }
  }

  Future<_Conn> secure(String host) async {
    final s = await RawSecureSocket.secure(_raw, subscription: _sub, host: host);
    return _Conn(s);
  }

  void close() {
    _sub.cancel();
    _raw.close();
  }
}
