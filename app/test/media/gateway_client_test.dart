// The pinned gateway client against in-process HTTPS servers. The certificates
// are the committed throwaway files in test/media/fixtures (test-only; no
// openssl needed, nothing is skipped).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chithram/src/media/gateway_client.dart';
import 'package:chithram/src/media/media_config.dart';
import 'package:chithram/src/media/models.dart';
import 'package:chithram/src/media/stream_proxy.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCert implements X509Certificate {
  _FakeCert(this.der);

  @override
  final Uint8List der;
  @override
  String get pem => '';
  @override
  Uint8List get sha1 => Uint8List(20);
  @override
  String get subject => '';
  @override
  String get issuer => '';
  @override
  DateTime get startValidity => DateTime(2000);
  @override
  DateTime get endValidity => DateTime(2100);
}

String _fp(List<int> der) => certFingerprintOfDer(der);

const _fixtures = 'test/media/fixtures';

/// The pin (SHA-256 of the DER) of the first certificate in a PEM file.
String _pinOfFile(String path) {
  final pem = File(path).readAsStringSync();
  final b64 = RegExp(r'-----BEGIN CERTIFICATE-----([\s\S]+?)-----END CERTIFICATE-----').firstMatch(pem)!.group(1)!;
  return _fp(base64.decode(b64.replaceAll(RegExp(r'\s'), '')));
}

class _Req {
  _Req(this.method, this.uri, this.headers, this.body);
  final String method;
  final Uri uri;
  final HttpHeaders headers;
  final String body;
}

const _token = 'T0kenT0kenT0kenT0kenT0kenT0kenT0kenT0kenT0k';

void main() {
  group('pinning callback', () {
    final der = List<int>.generate(200, (i) => i);
    final pin = _fp(der);

    test('accepts the pinned certificate for the pinned host and port', () {
      final cb = pinnedCertificateCallback(host: 'media.local', port: 8443, fingerprint: pin);
      expect(cb(_FakeCert(Uint8List.fromList(der)), 'media.local', 8443), isTrue);
      expect(cb(_FakeCert(Uint8List.fromList(der)), 'MEDIA.local', 8443), isTrue);
    });

    test('rejects another certificate', () {
      final cb = pinnedCertificateCallback(host: 'media.local', port: 8443, fingerprint: pin);
      final other = List<int>.of(der)..[0] ^= 1;
      expect(cb(_FakeCert(Uint8List.fromList(other)), 'media.local', 8443), isFalse);
    });

    test('rejects the right certificate on another host or port', () {
      final cb = pinnedCertificateCallback(host: 'media.local', port: 8443, fingerprint: pin);
      expect(cb(_FakeCert(Uint8List.fromList(der)), 'evil.example', 8443), isFalse);
      expect(cb(_FakeCert(Uint8List.fromList(der)), 'media.local', 9999), isFalse);
    });

    test('a malformed pin never matches', () {
      final cb = pinnedCertificateCallback(host: 'h', port: 1, fingerprint: 'AA:BB');
      expect(cb(_FakeCert(Uint8List.fromList(der)), 'h', 1), isFalse);
      expect(certMatchesPin(_FakeCert(Uint8List.fromList(der)), ''), isFalse);
    });

    test('fingerprint format matches the gateway (AA:BB upper case)', () {
      expect(pin, matches(RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$')));
      expect(pin, sha256.convert(der).bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':'));
    });

    test('constantTimeBytesEqual', () {
      expect(constantTimeBytesEqual([1, 2, 3], [1, 2, 3]), isTrue);
      expect(constantTimeBytesEqual([1, 2, 3], [1, 2, 4]), isFalse);
      expect(constantTimeBytesEqual([1, 2], [1, 2, 3]), isFalse);
    });
  });

  group('against a TLS server', () {
    late HttpServer server;
    late String realPin;
    late int port;
    final seen = <_Req>[];
    // What the next request answers; set per test.
    late Future<void> Function(HttpRequest) answer;

    setUpAll(() async {
      const dir = 'test/media/fixtures';
      realPin = _pinOfFile('$dir/selfsigned.crt');
      final ctx = SecurityContext()
        ..useCertificateChain('$dir/selfsigned.crt')
        ..usePrivateKey('$dir/selfsigned.key');
      server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, ctx);
      port = server.port;
      server.listen((req) async {
        final body = await utf8.decodeStream(req);
        seen.add(_Req(req.method, req.uri, req.headers, body));
        await answer(req);
      });
    });

    tearDownAll(() async {
      await server.close(force: true);
    });

    setUp(seen.clear);

    GatewayClient client({String? pin, String? token = _token, Duration? timeout}) => GatewayClient(
      host: GatewayHost('127.0.0.1', port),
      fingerprint: pin ?? realPin,
      token: token,
      timeout: timeout ?? const Duration(seconds: 5),
    );

    Future<void> json(HttpRequest r, int status, Object body, {Map<String, String> headers = const {}}) async {
      r.response.statusCode = status;
      r.response.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
      for (final e in headers.entries) {
        r.response.headers.set(e.key, e.value);
      }
      r.response.write(jsonEncode(body));
      await r.response.close();
    }

    test('right pin: calls succeed, token only in the Authorization header', () async {
      answer = (r) => json(r, 200, {'user': 'sam', 'role': 'admin'});
      final me = await client().me();
      expect(me.role, MediaRole.admin);
      final req = seen.single;
      expect(req.headers.value('authorization'), 'Bearer $_token');
      expect(req.uri.toString().contains(_token), isFalse);
      expect(req.uri.query, isEmpty);
    });

    test('wrong pin: no request reaches the server, error is pinMismatch', () async {
      answer = (r) => json(r, 200, {'user': 'sam', 'role': 'admin'});
      final wrong = _fp(List<int>.filled(100, 7));
      await expectLater(
        client(pin: wrong).me(),
        throwsA(isA<GatewayException>().having((e) => e.kind, 'kind', GatewayErrorKind.pinMismatch)),
      );
      expect(seen, isEmpty, reason: 'the TLS handshake failed before any HTTP request');
    });

    test('pairing sends the code in the JSON body and no Authorization header', () async {
      answer = (r) => json(r, 200, {'token': _token, 'deviceId': 'abcd1234', 'user': 'sam', 'role': 'viewer'});
      final r = await client(token: null).pair('123456', 'Chithram on test');
      expect(r.role, MediaRole.viewer);
      final req = seen.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/v1/pair');
      expect(req.headers.value('authorization'), isNull);
      expect(jsonDecode(req.body), {'code': '123456', 'deviceName': 'Chithram on test'});
      expect(req.uri.query, isEmpty);
    });

    test('a bad code is refused locally, without a request', () async {
      await expectLater(
        client(token: null).pair('12ab56', 'x'),
        throwsA(isA<GatewayException>().having((e) => e.kind, 'kind', GatewayErrorKind.invalidInput)),
      );
      expect(seen, isEmpty);
    });

    test('status codes map to typed errors', () async {
      Future<GatewayException> failWith(int status, {Map<String, String> headers = const {}, Object? body}) async {
        answer = (r) => json(r, status, body ?? {'error': 'x'}, headers: headers);
        try {
          await client().me();
        } on GatewayException catch (e) {
          return e;
        }
        throw StateError('no error for $status');
      }

      expect((await failWith(401, body: {'error': 'unauthorized'})).kind, GatewayErrorKind.unauthorized);
      expect((await failWith(403)).kind, GatewayErrorKind.forbidden);
      expect((await failWith(404)).kind, GatewayErrorKind.notFound);
      expect((await failWith(409)).kind, GatewayErrorKind.conflict);
      final limited = await failWith(429, headers: {'retry-after': '42'}, body: {'error': 'too_many_searches'});
      expect(limited.kind, GatewayErrorKind.rateLimited);
      expect(limited.retryAfter, const Duration(seconds: 42));
      expect(limited.code, 'too_many_searches');
      final down = await failWith(503, body: {'error': 'upstream_unavailable'});
      expect(down.kind, GatewayErrorKind.unavailable);
      expect(down.message, contains('unavailable'));
      expect((await failWith(502)).kind, GatewayErrorKind.unavailable);
      expect((await failWith(500)).kind, GatewayErrorKind.server);
    });

    test('a hostile Retry-After is clamped', () async {
      answer = (r) => json(r, 429, {'error': 'x'}, headers: {'retry-after': '99999999'});
      try {
        await client().me();
        fail('should throw');
      } on GatewayException catch (e) {
        expect(e.retryAfter, const Duration(hours: 1));
      }
    });

    test('redirects are never followed', () async {
      answer = (r) async {
        r.response.statusCode = 302;
        r.response.headers.set('location', 'http://evil.example/steal');
        await r.response.close();
      };
      await expectLater(
        client().me(),
        throwsA(isA<GatewayException>().having((e) => e.kind, 'kind', GatewayErrorKind.badResponse)),
      );
      expect(seen, hasLength(1));
    });

    test('malformed, wrongly typed and oversized bodies are rejected', () async {
      Future<GatewayErrorKind> kindOf(Future<void> Function(HttpRequest) a) async {
        answer = a;
        try {
          await client().me();
        } on GatewayException catch (e) {
          return e.kind;
        }
        throw StateError('no error');
      }

      expect(await kindOf((r) => json(r, 200, {'user': 'sam', 'role': 'root'})), GatewayErrorKind.badResponse);
      expect(await kindOf((r) => json(r, 200, [1, 2])), GatewayErrorKind.badResponse);
      expect(await kindOf((r) async {
        r.response.headers.contentType = ContentType.text;
        r.response.write('hello');
        await r.response.close();
      }), GatewayErrorKind.badResponse);
      expect(await kindOf((r) async {
        r.response.headers.contentType = ContentType.json;
        r.response.write('{not json');
        await r.response.close();
      }), GatewayErrorKind.badResponse);
      expect(await kindOf((r) async {
        r.response.headers.contentType = ContentType.json;
        r.response.write('{"user":"${'a' * (maxJsonBytes + 10)}","role":"admin"}');
        await r.response.close();
      }), GatewayErrorKind.tooLarge);
    });

    test('a slow server times out', () async {
      answer = (r) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        try {
          await json(r, 200, {'user': 'a', 'role': 'admin'});
        } catch (_) {}
      };
      await expectLater(
        client(timeout: const Duration(milliseconds: 300)).me(),
        throwsA(isA<GatewayException>().having((e) => e.kind, 'kind', GatewayErrorKind.timeout)),
      );
    });

    test('search, request, decide, downloads and library hit the gateway routes', () async {
      final id = 'b' * 32;
      answer = (r) async {
        final route = '${r.method} ${r.uri.path}';
        switch (route) {
          case 'GET /v1/search':
            return json(r, 200, {
              'results': [
                {'tmdbId': 7, 'type': 'movie', 'title': 'Dune', 'year': 2021, 'overview': 'x', 'posterPath': null, 'mediaStatus': 'none'},
              ],
            });
          case 'POST /v1/requests':
            return json(r, 201, {'id': 5, 'tmdbId': 7, 'type': 'movie', 'title': 'Dune', 'status': 'awaitingApproval', 'createdAt': 't'});
          case 'GET /v1/requests':
            return json(r, 200, {'requests': [], 'nextCursor': null});
          case 'POST /v1/requests/5/approve':
            return json(r, 200, {'id': 5, 'tmdbId': 7, 'type': 'movie', 'title': 'Dune', 'status': 'approved', 'createdAt': 't'});
          case 'GET /v1/downloads':
            return json(r, 200, {'downloads': []});
          case 'GET /v1/library':
            return json(r, 200, {'items': [{'id': id, 'title': 'T', 'type': 'Movie', 'poster': '/v1/images/$id?w=342'}], 'nextCursor': '50'});
        }
        if (route == 'GET /v1/images/$id') {
          r.response.headers.contentType = ContentType('image', 'jpeg');
          r.response.add(List<int>.filled(100, 1));
          return r.response.close();
        }
        return json(r, 404, {'error': 'not_found'});
      };
      final c = client();
      final s = await c.search('  dune ');
      expect(s.single.status, MediaStatus.none);
      expect(seen.last.uri.queryParameters, {'q': 'dune'});
      final rq = await c.createRequest(7, 'movie');
      expect(rq.status, MediaStatus.awaitingApproval);
      expect(jsonDecode(seen.last.body), {'tmdbId': 7, 'type': 'movie'});
      expect((await c.requests(cursor: '50')).nextCursor, isNull);
      expect(seen.last.uri.queryParameters, {'cursor': '50'});
      expect((await c.decide(5, approve: true)).status, MediaStatus.approved);
      expect(await c.downloads(), isEmpty);
      final lib = await c.library(LibraryKind.movies);
      expect(lib.nextCursor, '50');
      expect(seen.last.uri.queryParameters, {'type': 'movies'});
      final img = await c.image(lib.items.single.poster!);
      expect(img.length, 100);
      expect(seen.last.headers.value('authorization'), 'Bearer $_token', reason: 'images carry the header too');
      expect(seen.last.uri.toString().contains(_token), isFalse);
      c.close();
    });

    test('image: only gateway paths, only images, size capped', () async {
      final id = 'c' * 32;
      await expectLater(client().image('https://evil.example/a.png'), throwsA(isA<GatewayException>()));
      expect(seen, isEmpty);
      answer = (r) async {
        r.response.headers.contentType = ContentType.html;
        r.response.write('<html>');
        await r.response.close();
      };
      await expectLater(client().image('/v1/images/$id'), throwsA(isA<GatewayException>()));
      answer = (r) async {
        r.response.headers.contentType = ContentType('image', 'png');
        r.response.add(Uint8List(maxImageBytes + 1));
        await r.response.close();
      };
      await expectLater(
        client().image('/v1/images/$id'),
        throwsA(isA<GatewayException>().having((e) => e.kind, 'kind', GatewayErrorKind.tooLarge)),
      );
    });

    test('stream proxy: loopback only, secret path, token header upstream, Range passed', () async {
      final id = 'd' * 32;
      answer = (r) async {
        r.response.statusCode = 206;
        r.response.headers.contentType = ContentType('video', 'mp4');
        r.response.headers.set('content-range', 'bytes 0-3/10');
        r.response.add([1, 2, 3, 4]);
        await r.response.close();
      };
      final proxy = await StreamProxy.start(client(), id);
      addTearDown(proxy.close);
      final u = Uri.parse(proxy.url);
      expect(u.scheme, 'http');
      expect(u.host, '127.0.0.1');
      expect(proxy.url.contains(_token), isFalse);
      expect(u.userInfo, isEmpty);
      final http = HttpClient();
      addTearDown(http.close);
      final req = await http.getUrl(u);
      req.headers.set('range', 'bytes=0-3');
      final res = await req.close();
      expect(res.statusCode, 206);
      expect(await res.fold<int>(0, (n, c) => n + c.length), 4);
      expect(seen.single.uri.path, '/v1/stream/$id');
      expect(seen.single.headers.value('authorization'), 'Bearer $_token');
      expect(seen.single.headers.value('range'), 'bytes=0-3');
      // Another path is refused without touching the gateway.
      final bad = await (await http.getUrl(u.replace(path: '/nope'))).close();
      expect(bad.statusCode, 404);
      await bad.drain<void>();
      expect(seen, hasLength(1));
    });

    test('without a token no authenticated request is sent', () async {
      await expectLater(
        client(token: null).me(),
        throwsA(isA<GatewayException>().having((e) => e.kind, 'kind', GatewayErrorKind.unauthorized)),
      );
      expect(seen, isEmpty);
    });

    group('stream proxy guards', () {
      final id = 'd' * 32;

      Future<StreamProxy> start({int max = 8, void Function()? onUnauthorized, void Function(StreamProxy)? onClosed}) async {
        final proxy = await StreamProxy.start(
          client(),
          id,
          maxConnections: max,
          onUnauthorized: onUnauthorized,
          onClosed: onClosed,
        );
        addTearDown(proxy.close);
        return proxy;
      }

      Future<String> rawStatus(int proxyPort, String request) async {
        final sock = await Socket.connect('127.0.0.1', proxyPort);
        try {
          sock.write(request);
          return await sock
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first
              .timeout(const Duration(seconds: 5));
        } finally {
          sock.destroy();
        }
      }

      test('a wrong Host header, a wrong Host port and a wrong method are refused', () async {
        answer = (r) => json(r, 200, {});
        final proxy = await start();
        final u = Uri.parse(proxy.url);
        final path = u.path;
        expect(await rawStatus(u.port, 'GET $path HTTP/1.1\r\nHost: evil.example\r\n\r\n'), contains('404'));
        expect(await rawStatus(u.port, 'GET $path HTTP/1.1\r\nHost: evil.example:${u.port}\r\n\r\n'), contains('404'));
        expect(await rawStatus(u.port, 'GET $path HTTP/1.1\r\nHost: 127.0.0.1:1\r\n\r\n'), contains('404'));
        expect(await rawStatus(u.port, 'GET $path HTTP/1.1\r\nHost: localhost:${u.port}\r\n\r\n'), contains('404'));
        for (final m in ['POST', 'PUT', 'DELETE']) {
          expect(
            await rawStatus(u.port, '$m $path HTTP/1.1\r\nHost: 127.0.0.1:${u.port}\r\nContent-Length: 0\r\n\r\n'),
            contains('404'),
            reason: m,
          );
        }
        // A path that differs only in its last character.
        final almost = '${path.substring(0, path.length - 1)}${path.endsWith('0') ? '1' : '0'}';
        expect(await rawStatus(u.port, 'GET $almost HTTP/1.1\r\nHost: 127.0.0.1:${u.port}\r\n\r\n'), contains('404'));
        expect(seen, isEmpty, reason: 'nothing reached the gateway');
        // The right request still works.
        answer = (r) async {
          r.response.headers.contentType = ContentType('video', 'mp4');
          r.response.add([1, 2]);
          await r.response.close();
        };
        expect(await rawStatus(u.port, 'GET $path HTTP/1.1\r\nHost: 127.0.0.1:${u.port}\r\n\r\n'), contains('200'));
      });

      test('HEAD returns the headers and drops the upstream body without reading it', () async {
        final upstreamGone = Completer<void>();
        answer = (r) async {
          r.response.headers.contentType = ContentType('video', 'mp4');
          r.response.contentLength = 1 << 30;
          // Keep sending: a drained body would keep succeeding, a dropped
          // connection makes a write fail.
          try {
            for (var i = 0; i < 250; i++) {
              r.response.add(Uint8List(1000));
              await r.response.flush();
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
          } catch (_) {
            upstreamGone.complete();
          }
        };
        final proxy = await start();
        final http = HttpClient();
        addTearDown(http.close);
        final res = await (await http.headUrl(Uri.parse(proxy.url))).close().timeout(const Duration(seconds: 5));
        expect(res.statusCode, 200);
        expect(res.headers.value('content-length'), '${1 << 30}');
        expect(await res.fold<int>(0, (n, c) => n + c.length), 0);
        await upstreamGone.future.timeout(const Duration(seconds: 5));
        expect(upstreamGone.isCompleted, isTrue, reason: 'the upstream connection was destroyed, not drained');
      });

      test('401 from the gateway runs onUnauthorized; 503 stays 503', () async {
        var unauthorized = 0;
        final proxy = await start(onUnauthorized: () => unauthorized++);
        final http = HttpClient();
        addTearDown(http.close);
        answer = (r) => json(r, 401, {'error': 'unauthorized'});
        var res = await (await http.getUrl(Uri.parse(proxy.url))).close();
        expect(res.statusCode, 401);
        await res.drain<void>();
        expect(unauthorized, 1);
        answer = (r) => json(r, 503, {'error': 'upstream_unavailable'});
        res = await (await http.getUrl(Uri.parse(proxy.url))).close();
        expect(res.statusCode, 503);
        await res.drain<void>();
        expect(unauthorized, 1, reason: 'a 503 does not unpair');
      });

      test('the number of requests served at once is capped', () async {
        final release = Completer<void>();
        final entered = Completer<void>();
        answer = (r) async {
          if (!entered.isCompleted) entered.complete();
          await release.future;
          r.response.headers.contentType = ContentType('video', 'mp4');
          r.response.add([1]);
          await r.response.close();
        };
        final proxy = await start(max: 1);
        final http = HttpClient();
        addTearDown(http.close);
        // The first request is held open at the gateway, so it counts as active.
        final first = http.getUrl(Uri.parse(proxy.url)).then((q) => q.close());
        await entered.future.timeout(const Duration(seconds: 5));
        final second = await (await http.getUrl(Uri.parse(proxy.url))).close();
        expect(second.statusCode, 503);
        await second.drain<void>();
        release.complete();
        final done = await first;
        expect(done.statusCode, 200);
        await done.drain<void>();
      });

      test('close is idempotent, reports once and stops the listener', () async {
        var closed = 0;
        answer = (r) => json(r, 200, {});
        final proxy = await start(onClosed: (_) => closed++);
        final port = Uri.parse(proxy.url).port;
        await proxy.close();
        await proxy.close();
        expect(closed, 1);
        await expectLater(Socket.connect('127.0.0.1', port), throwsA(isA<SocketException>()));
      });
    });
  });

  // A certificate that a trusted CA signed is NOT enough: the pin decides. The
  // client below trusts the test CA, so the TLS stack accepts the server
  // without ever asking the badCertificateCallback.
  group('a CA-signed server with the wrong pin', () {
    late HttpServer ca;
    late String caPin;
    final reached = <String?>[]; // Authorization header of each request that arrived

    setUpAll(() async {
      caPin = _pinOfFile('$_fixtures/server.crt');
      final ctx = SecurityContext()
        ..useCertificateChain('$_fixtures/server.crt')
        ..usePrivateKey('$_fixtures/server.key');
      ca = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, ctx);
      ca.listen((req) async {
        await req.drain<void>();
        reached.add(req.headers.value('authorization'));
        req.response.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
        req.response.write(jsonEncode({'user': 'sam', 'role': 'admin'}));
        await req.response.close();
      });
    });

    tearDownAll(() => ca.close(force: true));
    setUp(reached.clear);

    SecurityContext trustingCa() => SecurityContext(withTrustedRoots: false)..setTrustedCertificates('$_fixtures/ca.crt');

    GatewayClient client(String pin, {bool plain = false}) => GatewayClient(
      host: GatewayHost('127.0.0.1', ca.port),
      fingerprint: pin,
      token: _token,
      timeout: const Duration(seconds: 5),
      clientFactory: () => plain
          // No connection check: only the second guard (the answer's certificate) is left.
          ? (HttpClient(context: trustingCa())..badCertificateCallback = (_, _, _) => false)
          : createPinnedHttpClient(host: '127.0.0.1', port: ca.port, fingerprint: pin, context: trustingCa()),
    );

    test('control: the right pin works', () async {
      expect((await client(caPin).me()).role, MediaRole.admin);
      expect(reached, ['Bearer $_token']);
    });

    test('wrong pin: rejected, and the token never reaches the server', () async {
      await expectLater(
        client(_fp(List<int>.filled(64, 1))).me(),
        throwsA(isA<GatewayException>().having((e) => e.kind, 'kind', GatewayErrorKind.pinMismatch)),
      );
      expect(reached, isEmpty, reason: 'the connection was dropped before any HTTP byte');
    });

    test('wrong pin: pairing is rejected before the code is sent', () async {
      final c = GatewayClient(
        host: GatewayHost('127.0.0.1', ca.port),
        fingerprint: _fp(List<int>.filled(64, 1)),
        clientFactory: () => createPinnedHttpClient(
          host: '127.0.0.1',
          port: ca.port,
          fingerprint: _fp(List<int>.filled(64, 1)),
          context: trustingCa(),
        ),
      );
      await expectLater(
        c.pair('123456', 'x'),
        throwsA(isA<GatewayException>().having((e) => e.kind, 'kind', GatewayErrorKind.pinMismatch)),
      );
      expect(reached, isEmpty);
    });

    test('second guard: even a client that skipped the connection check refuses the answer', () async {
      await expectLater(
        client(_fp(List<int>.filled(64, 1)), plain: true).me(),
        throwsA(isA<GatewayException>().having((e) => e.kind, 'kind', GatewayErrorKind.pinMismatch)),
      );
    });

    test('a pinned client refuses a different host or port outright', () async {
      final h = createPinnedHttpClient(host: '127.0.0.1', port: ca.port, fingerprint: caPin, context: trustingCa());
      addTearDown(h.close);
      await expectLater(h.getUrl(Uri.parse('https://localhost:${ca.port}/v1/me')), throwsA(isA<GatewayException>()));
      await expectLater(h.getUrl(Uri.parse('https://127.0.0.1:${ca.port + 1}/v1/me')), throwsA(isA<GatewayException>()));
      expect(reached, isEmpty);
    });
  });
}
