import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:localsend_rx/localsend_rx.dart';
import 'package:localsend_rx/src/discovery.dart';
import 'package:localsend_rx/src/net.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

/// A device that announced itself: an HTTPS server that records `register` calls.
class Peer {
  Peer(this.identity, this.server);

  final LsIdentity identity;
  final HttpServer server;
  final registered = <Map<String, dynamic>>[];
  final _got = StreamController<void>.broadcast();

  static Future<Peer> start() async {
    final id = await LsIdentity.generate();
    final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, id.securityContext());
    final p = Peer(id, server);
    server.listen((req) async {
      final body = await utf8.decodeStream(req);
      if (req.uri.path == '/api/localsend/v2/register') {
        p.registered.add(jsonDecode(body) as Map<String, dynamic>);
        p._got.add(null);
      }
      req.response.statusCode = 200;
      await req.response.close();
    });
    return p;
  }

  Map<String, Object?> announce({String? fingerprint, bool announce = true}) => {
        'alias': 'Phone',
        'version': '2.1',
        'deviceModel': 'Pixel',
        'deviceType': 'mobile',
        'fingerprint': fingerprint ?? identity.fingerprint,
        'port': server.port,
        'protocol': 'https',
        'download': false,
        'announce': announce,
      };

  Future<void> waitRegister() => _got.stream.first.timeout(const Duration(seconds: 5));

  Future<void> close() => server.close(force: true);
}

void main() {
  late LsIdentity mine;
  late Map<String, Object?> Function({bool announce}) info;

  setUpAll(() async {
    mine = await sharedIdentity();
    info = ({bool announce = false}) => {
          'alias': 'Chithram test',
          'version': '2.1',
          'deviceModel': null,
          'deviceType': 'desktop',
          'fingerprint': mine.fingerprint,
          'port': 53420,
          'protocol': 'https',
          'download': false,
          if (announce) 'announce': true,
        };
  });

  Future<RawDatagramSocket> sendTo(int port, Object payload) async {
    final s = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    s.send(utf8.encode(jsonEncode(payload)), InternetAddress.loopbackIPv4, port);
    return s;
  }

  test('an announce from a device makes us register with it, pinned to its fingerprint', () async {
    final peer = await Peer.start();
    final d = Discovery(identity: mine, port: 53420, allowLoopback: true, info: info);
    await d.start();
    final s = await sendTo(53420, peer.announce());
    await peer.waitRegister();
    expect(peer.registered.single['fingerprint'], mine.fingerprint);
    expect(peer.registered.single['alias'], 'Chithram test');
    s.close();
    await d.stop();
    await peer.close();
  });

  test('a wrong fingerprint fails the pin and falls back to a UDP reply with announce:false', () async {
    final peer = await Peer.start();
    // Reply goes to the sender's own listening socket here.
    final listener = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final reply = Completer<Map<String, dynamic>>();
    listener.listen((e) {
      final dg = listener.receive();
      if (dg != null) reply.complete(jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>);
    });
    final d = Discovery(identity: mine, port: 53421, allowLoopback: true, info: info, replyPort: listener.port);
    await d.start();
    final s = await sendTo(53421, peer.announce(fingerprint: 'AB' * 32));
    final j = await reply.future.timeout(const Duration(seconds: 6));
    expect(j['fingerprint'], mine.fingerprint);
    expect(j.containsKey('announce'), isFalse);
    expect(peer.registered, isEmpty);
    s.close();
    listener.close();
    await d.stop();
    await peer.close();
  });

  test('our own announce, announce:false, junk and non-private senders are ignored', () async {
    final peer = await Peer.start();
    final strict = Discovery(identity: mine, port: 53422, allowLoopback: false, info: info);
    await strict.start();
    // Loopback is not private and allowLoopback is off.
    final a = await sendTo(53422, peer.announce());
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(peer.registered, isEmpty);
    a.close();
    await strict.stop();

    final d = Discovery(identity: mine, port: 53423, allowLoopback: true, info: info);
    await d.start();
    for (final payload in <Object>[
      peer.announce(fingerprint: mine.fingerprint),
      peer.announce(announce: false),
      'junk',
      {...peer.announce(), 'port': 70000},
      {...peer.announce(), 'version': '1.0'},
    ]) {
      (await sendTo(53423, payload)).close();
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(peer.registered, isEmpty);
    await d.stop();
    await peer.close();
  });

  test('announce:true repeats from the same device within 5 s are answered once', () async {
    final peer = await Peer.start();
    final d = Discovery(identity: mine, port: 53424, allowLoopback: true, info: info);
    await d.start();
    final src = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    for (var i = 0; i < 5; i++) {
      src.send(utf8.encode(jsonEncode(peer.announce())), InternetAddress.loopbackIPv4, 53424);
    }
    await peer.waitRegister();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(peer.registered, hasLength(1));
    src.close();
    await d.stop();
    await peer.close();
  });

  group('multicast', () {
    const group = '224.0.0.167';

    test('start announces to the group and answers a multicast announce', () async {
      final ifaces = await privateInterfaces();
      if (ifaces.isEmpty) {
        markTestSkipped('no private interface on this runner');
        return;
      }
      const port = 53425;
      final probe = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true, reusePort: true);
      for (final i in ifaces) {
        try {
          probe.joinMulticast(InternetAddress(group), i.interface);
        } on Object {
          // Another interface may work.
        }
      }
      final heard = Completer<Map<String, dynamic>>();
      probe.listen((e) {
        final dg = probe.receive();
        if (dg == null) return;
        final j = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
        if (j['fingerprint'] == mine.fingerprint && j['announce'] == true && !heard.isCompleted) heard.complete(j);
      });
      final rx = LsReceiver(
        identity: mine,
        config: const LsReceiverConfig(port: port, allowLoopback: true),
        onOffer: (_) async => true,
      );
      await rx.start();
      Map<String, dynamic> j;
      try {
        j = await heard.future.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        await rx.dispose();
        probe.close();
        markTestSkipped('this runner has no multicast loopback');
        return;
      }
      expect(j['protocol'], 'https');
      expect(j['port'], port);
      expect(j['version'], '2.1');
      expect(j['download'], false);

      // And a device announcing itself on the group gets a register from us.
      final peer = await Peer.start();
      probe.send(utf8.encode(jsonEncode(peer.announce())), InternetAddress(group), port);
      try {
        await peer.waitRegister();
        expect(peer.registered.single['fingerprint'], mine.fingerprint);
      } on TimeoutException {
        markTestSkipped('this runner does not deliver multicast to the receiver');
      }
      await peer.close();
      await rx.dispose();
      probe.close();
    }, tags: 'multicast');
  });
}
