import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_host/nova_host.dart';

void main() {
  test('registrableDomain', () {
    expect(registrableDomain('www.example.com'), 'example.com');
    expect(registrableDomain('a.b.example.co.uk'), 'example.co.uk');
    expect(registrableDomain('example.test'), 'example.test');
    expect(registrableDomain('127.0.0.1'), '127.0.0.1');
  });

  test('allowlist matches the domain and its subdomains only', () {
    final a = HostAllowlist.forEngine('https://cdn.example.com/x', ['static.other.org']);
    expect(a.allows('example.com'), isTrue);
    expect(a.allows('api.example.com'), isTrue);
    expect(a.allows('static.other.org'), isTrue);
    expect(a.allows('evilexample.com'), isFalse);
    expect(a.allows('example.com.evil.net'), isFalse);
    expect(a.allows('other.org'), isFalse);
  });

  test('isPublicAddress', () {
    bool p(String s) => isPublicAddress(InternetAddress(s));
    for (final s in ['127.0.0.1', '10.1.2.3', '172.16.0.1', '172.31.255.1', '192.168.1.1', '169.254.1.1', '100.64.0.1',
      '0.0.0.0', '224.0.0.1', '::1', '::', 'fe80::1', 'fc00::1', 'fd12::1', 'ff02::1', '::ffff:10.0.0.1']) {
      expect(p(s), isFalse, reason: s);
    }
    for (final s in ['8.8.8.8', '93.184.216.34', '172.32.0.1', '2606:4700:4700::1111']) {
      expect(p(s), isTrue, reason: s);
    }
  });

  group('with a local server', () {
    late HttpServer server;
    late int port;
    final big = Uint8List(2 * 1024 * 1024);
    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;
      server.listen((r) async {
        switch (r.uri.path) {
          case '/ok':
            r.response.write('hello');
          case '/chunked':
            r.response.headers.chunkedTransferEncoding = true;
            r.response.write('part1-');
            await r.response.flush();
            r.response.write('part2');
          case '/big':
            r.response.add(big);
          case '/redir':
            r.response.statusCode = 302;
            r.response.headers.set('location', 'http://foreign.test:$port/ok');
          case '/slow':
            await Future<void>.delayed(const Duration(seconds: 5));
            r.response.write('late');
          default:
            r.response.statusCode = 404;
        }
        await r.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    HttpBroker broker({bool testMode = true, int budget = 20, int maxBody = 5 * 1024 * 1024, Duration? timeout}) =>
        HttpBroker(
          allowlist: HostAllowlist(['example.test', '127.0.0.1']),
          policy: BrokerPolicy(
            testMode: testMode,
            maxRequests: budget,
            maxBodyBytes: maxBody,
            requestTimeout: timeout ?? const Duration(seconds: 15),
            hostOverrides: {
              'example.test': InternetAddress.loopbackIPv4,
              'foreign.test': InternetAddress.loopbackIPv4,
            },
          ),
        );

    test('fetches, including chunked bodies', () async {
      final b = broker();
      expect(String.fromCharCodes((await b.fetch('GET', 'http://example.test:$port/ok', {}, null)).body), 'hello');
      expect(String.fromCharCodes((await b.fetch('GET', 'http://example.test:$port/chunked', {}, null)).body), 'part1-part2');
    });

    test('loopback is blocked outside test mode', () async {
      final b = broker(testMode: false);
      await expectLater(b.fetch('GET', 'http://127.0.0.1:$port/ok', {}, null), throwsA(isA<BrokerDenied>()));
    });

    test('non-http schemes, credentials and header injection are refused', () async {
      final b = broker();
      for (final u in ['file:///etc/passwd', 'ftp://example.test/x', 'http://u:p@example.test:$port/ok']) {
        await expectLater(b.fetch('GET', u, {}, null), throwsA(isA<BrokerDenied>()), reason: u);
      }
      await expectLater(b.fetch('GET', 'http://example.test:$port/ok', {'X': 'a\r\nEvil: 1'}, null), throwsA(isA<BrokerDenied>()));
    });

    test('a redirect to a foreign host is refused at the hop', () async {
      final b = broker();
      await expectLater(b.fetch('GET', 'http://example.test:$port/redir', {}, null), throwsA(isA<BrokerDenied>()));
      expect(b.log.last, contains('not in allowlist'));
    });

    test('request budget', () async {
      final b = broker(budget: 3);
      for (var i = 0; i < 3; i++) {
        await b.fetch('GET', 'http://example.test:$port/ok', {}, null);
      }
      await expectLater(b.fetch('GET', 'http://example.test:$port/ok', {}, null), throwsA(isA<BrokerDenied>()));
    });

    test('body cap', () async {
      final b = broker(maxBody: 1024 * 1024);
      await expectLater(b.fetch('GET', 'http://example.test:$port/big', {}, null), throwsA(isA<BrokerDenied>()));
    });

    test('per-request timeout', () async {
      final b = broker(timeout: const Duration(milliseconds: 600));
      await expectLater(b.fetch('GET', 'http://example.test:$port/slow', {}, null), throwsA(isA<BrokerDenied>()));
    });

    test('SOCKS5 proxy (VPN guard): traffic goes through the proxy with remote DNS', () async {
      final seen = <String>[];
      final proxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      proxy.listen((c) {
        final it = StreamIterator<Uint8List>(c);
        () async {
          Future<Uint8List> take(int n) async {
            final out = BytesBuilder();
            while (out.length < n) {
              await it.moveNext();
              out.add(it.current);
            }
            return out.toBytes();
          }

          await take(3); // 5 1 0
          c.add([5, 0]);
          final h = await take(5); // 5 1 0 3 len
          final rest = await take(h[4] + 2);
          final host = String.fromCharCodes(rest.sublist(0, h[4]));
          final p = (rest[h[4]] << 8) | rest[h[4] + 1];
          seen.add('$host:$p');
          final up = await Socket.connect(InternetAddress.loopbackIPv4, p);
          c.add([5, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
          up.listen(c.add, onDone: c.destroy);
          // pump the rest of the client's bytes upstream
          () async {
            while (await it.moveNext()) {
              up.add(it.current);
            }
            up.destroy();
          }();
        }();
      });
      final b = HttpBroker(
        allowlist: HostAllowlist(['example.test']),
        policy: BrokerPolicy(testMode: true, socks5: Socks5Config('127.0.0.1', proxy.port)),
      );
      final r = await b.fetch('GET', 'http://example.test:$port/ok', {}, null);
      expect(String.fromCharCodes(r.body), 'hello');
      expect(seen, ['example.test:$port']);
      await proxy.close();
    });
  });
}
