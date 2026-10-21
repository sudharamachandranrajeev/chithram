import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:localsend_rx/localsend_rx.dart';
import 'package:localsend_rx/src/net.dart' show PinGuard;
import 'package:localsend_rx/testing.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

Uint8List torrentBytes([int pad = 0]) =>
    Uint8List.fromList(ascii.encode('d8:announce3:foo4:infod6:lengthi1e4:name1:aee') + List.filled(pad, 0x20));

void main() {
  late Harness h;
  late LsTestSender s;

  Future<void> setUpWith({String? pin, Future<bool> Function(LsOffer)? onOffer, Duration? promptTimeout, Duration? sessionIdle, DateTime Function()? clock}) async {
    h = await Harness.start(
      pin: pin,
      onOffer: onOffer,
      promptTimeout: promptTimeout ?? const Duration(seconds: 60),
      sessionIdle: sessionIdle ?? const Duration(minutes: 2),
      clock: clock,
    );
    s = h.sender();
  }

  tearDown(() => h.close());

  group('info and register', () {
    setUp(() => setUpWith());

    test('GET /info has the spec field names and our fingerprint', () async {
      final r = await s.info();
      expect(r.status, 200);
      final j = r.json! as Map<String, dynamic>;
      expect(j['alias'], 'Chithram test');
      expect(j['version'], '2.1');
      expect(j['deviceModel'], 'Test box');
      expect(j['deviceType'], 'desktop');
      expect(j['download'], false);
      expect(j['fingerprint'], matches(RegExp(r'^[0-9A-F]{64}$')));
      expect(j['fingerprint'], h.identity.fingerprint);
    });

    test('POST /register answers with our info', () async {
      final r = await s.register();
      expect(r.status, 200);
      expect((r.json! as Map)['fingerprint'], h.identity.fingerprint);
    });

    test('POST /register with a bad body is 400', () async {
      final r = await s.prepare([], rawBody: utf8.encode('{}'));
      expect(r.status, 400);
    });

    test('the certificate fingerprint is the SHA-256 of what the server presents', () async {
      final client = HttpClient(context: SecurityContext(withTrustedRoots: false));
      String? seen;
      client.badCertificateCallback = (cert, host, port) {
        seen = LsIdentity.fingerprintOf(cert.der);
        return true;
      };
      final req = await client.getUrl(Uri.parse('https://127.0.0.1:${h.rx.port}/api/localsend/v2/info'));
      await (await req.close()).drain<void>();
      client.close();
      expect(seen, h.identity.fingerprint);
    });

    test('unknown paths are 404 and wrong methods 405', () async {
      final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
      final a = await (await client.getUrl(Uri.parse('https://127.0.0.1:${h.rx.port}/api/localsend/v2/nope'))).close();
      expect(a.statusCode, 404);
      await a.drain<void>();
      final b = await (await client.postUrl(Uri.parse('https://127.0.0.1:${h.rx.port}/api/localsend/v2/info'))).close();
      expect(b.statusCode, 405);
      await b.drain<void>();
      client.close();
    });
  });

  group('prepare-upload', () {
    setUp(() => setUpWith());

    test('a text message is 204, offered with its preview, then delivered', () async {
      final r = await s.prepare([LsTestSender.textFile('magnet:?xt=urn:btih:abc')]);
      expect(r.status, 204);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(h.offers.single.senderAlias, 'Test phone');
      expect(h.offers.single.senderModel, 'Test model');
      expect(h.offers.single.senderAddress, '127.0.0.1');
      expect(h.offers.single.files.single.preview, 'magnet:?xt=urn:btih:abc');
      final t = h.incoming.single as TextIncoming;
      expect(t.text, 'magnet:?xt=urn:btih:abc');
      expect(t.fromAlias, 'Test phone');
    });

    test('a .torrent gets a session and per-file tokens (200), upload delivers it', () async {
      final bytes = torrentBytes();
      final r = await s.prepare([LsTestSender.binaryFile('t1', 'film.torrent', bytes)]);
      expect(r.status, 200);
      final j = r.json! as Map<String, dynamic>;
      expect(j.keys, containsAll(['sessionId', 'files']));
      final token = (j['files'] as Map)['t1'] as String;
      expect(token, isNotEmpty);
      final up = await s.upload(j['sessionId'] as String, 't1', token, bytes);
      expect(up.status, 200);
      final f = h.incoming.single as FileIncoming;
      expect(f.name, 'film.torrent');
      expect(f.bytes, bytes);
    });

    test('a .txt upload is delivered as text', () async {
      final bytes = Uint8List.fromList(utf8.encode('hello https://youtu.be/abc'));
      expect(await s.sendFile('note.txt', bytes, type: 'text/plain'), 200);
      expect((h.incoming.single as TextIncoming).text, 'hello https://youtu.be/abc');
    });

    test('partial acceptance lists only the accepted ids', () async {
      final bytes = torrentBytes();
      final r = await s.prepare([
        LsTestSender.binaryFile('t1', 'a.torrent', bytes),
        LsTestSender.binaryFile('p1', 'photo.png', Uint8List(10), type: 'image/png'),
      ]);
      expect(r.status, 200);
      expect(((r.json! as Map)['files'] as Map).keys, ['t1']);
      expect(h.offers.single.files.map((f) => f.id), ['t1']);
    });

    test('nothing acceptable is 403 and the user is never asked', () async {
      final r = await s.prepare([LsTestSender.binaryFile('p1', 'photo.png', Uint8List(10), type: 'image/png')]);
      expect(r.status, 403);
      expect(h.offers, isEmpty);
    });

    test('policy: size caps and name rules', () async {
      Future<int> status(Map<String, Object?> file) async => (await s.prepare([file])).status;
      Map<String, Object?> f(String name, int size, {String type = 'application/octet-stream', String? preview}) =>
          {'id': 'x', 'fileName': name, 'size': size, 'fileType': type, 'preview': ?preview};
      expect(await status(f('big.torrent', 2 * 1024 * 1024 + 1)), 403);
      expect(await status(f('empty.torrent', 0)), 403);
      expect(await status(f('big.txt', 64 * 1024 + 1, type: 'text/plain')), 403);
      expect(await status(f('x.txt', 5, type: 'text/plain', preview: 'a' * (64 * 1024 + 1))), 403);
      expect(await status(f('x.exe', 5)), 403);
      expect(await status(f('x.txt', 5, type: 'image/png', preview: 'hello')), 403);
      expect(await status(f('x.txt', -1, type: 'text/plain')), 403);
      expect(h.offers, isEmpty);
    });

    test('the user rejecting is 403', () async {
      await h.close();
      await setUpWith(onOffer: (_) async => false);
      expect(await s.sendText('hi'), 403);
      expect(h.incoming, isEmpty);
    });

    test('an unanswered prompt times out with 403', () async {
      await h.close();
      await setUpWith(promptTimeout: const Duration(milliseconds: 200), onOffer: (_) => Completer<bool>().future);
      expect(await s.sendText('hi'), 403);
      // And the receiver is free again.
      expect(await s.sendText('hi'), 403);
    });

    test('malformed bodies are 400', () async {
      expect((await s.prepare([], rawBody: utf8.encode('not json'))).status, 400);
      expect((await s.prepare([], rawBody: utf8.encode('[]'))).status, 400);
      expect((await s.prepare([], rawBody: utf8.encode('{"info":{},"files":{}}'))).status, 400);
      expect((await s.prepare([], rawBody: utf8.encode('{"info":{"alias":"a","version":"2.1","fingerprint":"F"}}'))).status, 400);
      expect((await s.prepare([], rawBody: utf8.encode('{"info":{"alias":"a","version":"1.0","fingerprint":"F"},"files":{"a":{}}}'))).status, 400);
    });

    test('a body over 256 KiB is 400 and the connection is dropped', () async {
      final big = utf8.encode('{"info":{},"files":{},"pad":"${'a' * (300 * 1024)}"}');
      try {
        expect((await s.prepare([], rawBody: big)).status, 400);
      } on SocketException {
        // The receiver hung up while the sender was still writing: also a drop.
      }
      expect(h.offers, isEmpty);
    });

    test('more than 16 files is 403', () async {
      final files = [for (var i = 0; i < 17; i++) LsTestSender.binaryFile('f$i', '$i.torrent', torrentBytes())];
      expect((await s.prepare(files)).status, 403);
      expect(h.offers, isEmpty);
    });

    test('control characters in names are stripped from the offer', () async {
      expect(await s.prepare([LsTestSender.textFile('x')]).then((r) => r.status), 204);
      final t = LsTestSender(host: '127.0.0.1', port: h.rx.port!, fingerprint: h.identity.fingerprint, alias: 'Evil\nAlias${String.fromCharCode(0x202e)}');
      await t.sendText('x');
      expect(h.offers.last.senderAlias, 'Evil Alias');
    });

    test('a second sender while a prompt is open is 409', () async {
      await h.close();
      final gate = Completer<bool>();
      await setUpWith(onOffer: (_) => gate.future);
      final first = s.sendText('one');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final second = LsTestSender(host: '127.0.0.1', port: h.rx.port!, fingerprint: h.identity.fingerprint, alias: 'Other');
      expect(await second.sendText('two'), 409);
      gate.complete(true);
      expect(await first, 204);
      // Free again once the first transfer is done.
      expect(await second.sendText('three'), 204);
    });

    test('a second sender while an accepted upload is pending is 409; cancel frees it', () async {
      final r = await s.prepare([LsTestSender.binaryFile('t1', 'a.torrent', torrentBytes())]);
      final id = (r.json! as Map)['sessionId'] as String;
      expect(await s.sendText('x'), 409);
      expect((await s.cancel('nope')).status, 403);
      expect((await s.cancel(id)).status, 200);
      expect(await s.sendText('x'), 204);
    });

    test('an idle accepted session expires', () async {
      await h.close();
      await setUpWith(sessionIdle: const Duration(milliseconds: 200));
      await s.prepare([LsTestSender.binaryFile('t1', 'a.torrent', torrentBytes())]);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(await s.sendText('x'), 204);
    });
  });

  group('upload', () {
    late String sid;
    late String tok;
    final bytes = torrentBytes(100);

    setUp(() async {
      await setUpWith();
      final r = await s.prepare([LsTestSender.binaryFile('t1', 'a.torrent', bytes)]);
      sid = (r.json! as Map)['sessionId'] as String;
      tok = ((r.json! as Map)['files'] as Map)['t1'] as String;
    });

    test('bad token, session, file id are 403', () async {
      expect((await s.upload(sid, 't1', 'bad', bytes)).status, 403);
      expect((await s.upload('bad', 't1', tok, bytes)).status, 403);
      expect((await s.upload(sid, 'zzz', tok, bytes)).status, 403);
      expect(h.incoming, isEmpty);
    });

    test('a body longer than declared is 400 and nothing is delivered', () async {
      expect((await s.upload(sid, 't1', tok, [...bytes, 1, 2, 3])).status, 400);
      expect(h.incoming, isEmpty);
    });

    test('a body shorter than declared is 400', () async {
      expect((await s.upload(sid, 't1', tok, bytes.sublist(0, 20))).status, 400);
    });

    test('content that is not a torrent is 400', () async {
      final fake = Uint8List(bytes.length)..fillRange(0, bytes.length, 0x41);
      final r = await s.prepare([LsTestSender.binaryFile('t2', 'b.torrent', fake)]);
      expect(r.status, 409); // first session still open
      await s.cancel(sid);
      final r2 = await s.prepare([LsTestSender.binaryFile('t2', 'b.torrent', fake)]);
      final id2 = (r2.json! as Map)['sessionId'] as String;
      final tok2 = ((r2.json! as Map)['files'] as Map)['t2'] as String;
      expect((await s.upload(id2, 't2', tok2, fake)).status, 400);
    });

    test('a wrong sha256 is 422', () async {
      await s.cancel(sid);
      final other = torrentBytes(5);
      final file = LsTestSender.binaryFile('t3', 'c.torrent', other)..['sha256'] = sha256.convert([1, 2, 3]).toString();
      final r = await s.prepare([file]);
      final id = (r.json! as Map)['sessionId'] as String;
      final t = ((r.json! as Map)['files'] as Map)['t3'] as String;
      expect((await s.upload(id, 't3', t, other)).status, 422);
      expect(h.incoming, isEmpty);
    });

    test('a file can be uploaded once, and the session ends after the last file', () async {
      expect((await s.upload(sid, 't1', tok, bytes)).status, 200);
      expect((await s.upload(sid, 't1', tok, bytes)).status, 403);
      expect(h.incoming, hasLength(1));
      expect(await s.sendText('free again'), 204);
    });

    test('oversized chunked upload is dropped without delivering', () async {
      final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
      final req = await client.postUrl(Uri.parse(
          'https://127.0.0.1:${h.rx.port}/api/localsend/v2/upload?sessionId=$sid&fileId=t1&token=$tok'));
      req.headers.chunkedTransferEncoding = true;
      req.add(Uint8List(bytes.length + 5000));
      try {
        final res = await req.close();
        expect(res.statusCode, 400);
      } on Object {
        // Dropped before the response was read: also fine.
      }
      client.close(force: true);
      expect(h.incoming, isEmpty);
    });
  });

  group('PIN', () {
    setUp(() => setUpWith(pin: '1234'));

    test('missing is 401, wrong is 401, right is accepted', () async {
      expect((await s.prepare([LsTestSender.textFile('x')])).status, 401);
      expect((await s.prepare([LsTestSender.textFile('x')], pin: '9999')).status, 401);
      expect((await s.prepare([LsTestSender.textFile('x')], pin: '1234')).status, 204);
    });

    test('five wrong PINs lock the address out with 429, even for the right PIN', () async {
      for (var i = 0; i < 4; i++) {
        expect((await s.prepare([LsTestSender.textFile('x')], pin: '000$i')).status, 401);
      }
      expect((await s.prepare([LsTestSender.textFile('x')], pin: '0004')).status, 429);
      expect((await s.prepare([LsTestSender.textFile('x')], pin: '1234')).status, 429);
      expect(h.offers, isEmpty);
    });
  });

  group('PinGuard', () {
    test('failures age out after the window', () {
      var now = DateTime(2026);
      final g = PinGuard(clock: () => now);
      for (var i = 0; i < 5; i++) {
        g.fail('10.0.0.2');
      }
      expect(g.limited('10.0.0.2'), isTrue);
      expect(g.limited('10.0.0.3'), isFalse);
      now = now.add(const Duration(minutes: 10, seconds: 1));
      expect(g.limited('10.0.0.2'), isFalse);
    });
  });

  group('remote address check', () {
    test('a non-private remote is 403 on every endpoint', () async {
      // Loopback is not private, and allowLoopback is off.
      h = await Harness.start(allowLoopback: false);
      s = h.sender();
      expect((await s.info()).status, 403);
      expect((await s.register()).status, 403);
      expect(await s.sendText('x'), 403);
      expect(h.offers, isEmpty);
    });

    test('isPrivateV4 follows the RFC 1918 ranges', () {
      bool p(String a) => isPrivateV4(InternetAddress(a));
      expect(p('10.1.2.3'), isTrue);
      expect(p('172.16.0.1'), isTrue);
      expect(p('172.31.255.255'), isTrue);
      expect(p('172.15.0.1'), isFalse);
      expect(p('172.32.0.1'), isFalse);
      expect(p('192.168.1.5'), isTrue);
      expect(p('192.169.1.5'), isFalse);
      expect(p('100.64.0.1'), isFalse); // CGNAT, e.g. Tailscale
      expect(p('8.8.8.8'), isFalse);
      expect(p('127.0.0.1'), isFalse);
      expect(p('169.254.1.1'), isFalse);
      expect(p('::1'), isFalse);
    });
  });

  group('start', () {
    test('port in use gives a clear error', () async {
      final blocker = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final id = await sharedIdentity();
      final rx = LsReceiver(
        identity: id,
        config: LsReceiverConfig(port: blocker.port, multicast: false, allowLoopback: true, bindAddresses: [InternetAddress.loopbackIPv4]),
        onOffer: (_) async => true,
      );
      await expectLater(rx.start(), throwsA(isA<LsBindException>().having((e) => e.message, 'message', contains('in use'))));
      expect(rx.running, isFalse);
      await blocker.close();
      await rx.dispose();
    });
  });
}
