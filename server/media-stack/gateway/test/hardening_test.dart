import 'dart:io';

import 'package:chithram_gateway/src/api.dart';
import 'package:chithram_gateway/src/cli.dart';
import 'package:chithram_gateway/src/config.dart';
import 'package:chithram_gateway/src/fsperm.dart';
import 'package:chithram_gateway/src/jellyfin.dart';
import 'package:chithram_gateway/src/net.dart';
import 'package:chithram_gateway/src/pairing.dart';
import 'package:chithram_gateway/src/roles.dart';
import 'package:chithram_gateway/src/seerr.dart';
import 'package:chithram_gateway/src/state.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class FakeJf extends Jellyfin {
  FakeJf(super.cfg);
  @override
  Future<JfUser?> findByName(String name) async =>
      JfUser('a' * 32, name, false);
}

class FakeSeerr extends Seerr {
  FakeSeerr(super.cfg);
  bool fail = false;
  bool owner = false;
  final calls = <String>[];
  List<Map<String, Object?>> searchResults = [];
  int detailCalls = 0;

  @override
  Future<int> ensureUser(String jellyfinId, Role role) async {
    calls.add('ensure:${role.name}');
    if (fail) throw UpstreamException('down');
    return 5;
  }

  @override
  Future<bool> revoke(String jellyfinId) async {
    calls.add('revoke:$jellyfinId');
    if (fail) throw UpstreamException('down');
    return !owner;
  }

  @override
  Future<List<Map<String, Object?>>> search(String q) async => searchResults;

  @override
  Future<List<dynamic>?> requestsOf(String type, int tmdbId) async {
    detailCalls++;
    return null;
  }
}

void main() {
  late Directory tmp;
  late StateStore store;
  late Config cfg;
  final uid = 'a' * 32;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gw-hard');
    store = StateStore(tmp.path);
    cfg = Config.fromEnv({'STATE_DIR': tmp.path, 'SECRETS_DIR': tmp.path});
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('admin CLI keeps gateway role and Seerr permissions in step', () {
    test('set-role success updates both', () async {
      final sr = FakeSeerr(cfg);
      final code = await runAdmin(
        ['users', 'set-role', '--user', 'bob', '--role', 'viewer'],
        cfg,
        jellyfin: FakeJf(cfg),
        seerr: sr,
      );
      expect(code, 0);
      expect(store.read().users[uid]!.role, Role.viewer);
      expect(sr.calls, ['ensure:viewer']);
    });

    test(
      'set-role with Seerr failure exits 1, restores the old role',
      () async {
        store.update((s) => s.users[uid] = UserRec('bob', Role.admin));
        final sr = FakeSeerr(cfg)..fail = true;
        final code = await runAdmin(
          ['users', 'set-role', '--user', 'bob', '--role', 'viewer'],
          cfg,
          jellyfin: FakeJf(cfg),
          seerr: sr,
        );
        expect(code, 1);
        expect(store.read().users[uid]!.role, Role.admin);
      },
    );

    test(
      'pair with Seerr failure exits 1, leaves no user and no code',
      () async {
        final sr = FakeSeerr(cfg)..fail = true;
        final code = await runAdmin(
          ['pair', '--user', 'bob', '--role', 'admin'],
          cfg,
          jellyfin: FakeJf(cfg),
          seerr: sr,
        );
        expect(code, 1);
        final s = store.read();
        expect(s.users, isEmpty);
        expect(s.codes, isEmpty);
      },
    );

    test('remove takes Seerr permissions first, then drops state', () async {
      store.update((s) {
        s.users[uid] = UserRec('bob', Role.admin);
        redeemCode(s, issueCode(s, uid, 0), 'phone', 1);
        issueCode(s, uid, 0);
      });
      final sr = FakeSeerr(cfg);
      expect(await runAdmin(['users', 'remove', 'BOB'], cfg, seerr: sr), 0);
      expect(sr.calls, ['revoke:$uid']);
      final s = store.read();
      expect(s.users, isEmpty);
      expect(s.devices, isEmpty);
      expect(s.codes, isEmpty);
    });

    test('remove with Seerr failure changes nothing and exits 1', () async {
      store.update((s) => s.users[uid] = UserRec('bob', Role.admin));
      final sr = FakeSeerr(cfg)..fail = true;
      expect(await runAdmin(['users', 'remove', 'bob'], cfg, seerr: sr), 1);
      expect(store.read().users, hasLength(1));
    });

    test('remove of the Seerr owner still drops gateway access', () async {
      store.update((s) => s.users[uid] = UserRec('bob', Role.admin));
      final sr = FakeSeerr(cfg)..owner = true;
      expect(await runAdmin(['users', 'remove', uid], cfg, seerr: sr), 0);
      expect(store.read().users, isEmpty);
    });
  });

  group('gateway hardening', () {
    Request req(String path, String token) => Request(
      'GET',
      Uri.parse('https://gw$path'),
      headers: {'authorization': 'Bearer $token'},
    );

    String pairDevice() => store.update((s) {
      s.users[uid] = UserRec('bob', Role.requester);
      return redeemCode(s, issueCode(s, uid, 0), 'phone', 1)!.token;
    });

    test('Jellyfin outage fails closed with 503, not open', () async {
      final h = Gateway(
        cfg,
        store,
        userActive: (_) async => throw UpstreamException('down'),
      ).handler;
      final res = await h(req('/v1/me', pairDevice()));
      expect(res.statusCode, 503);
    });

    test('search is limited per device, detail lookups are capped', () async {
      final sr = FakeSeerr(cfg)
        ..searchResults = [
          for (var i = 1; i <= 30; i++)
            {
              'id': i,
              'mediaType': 'movie',
              'title': 't$i',
              'mediaInfo': {'status': 2},
            },
        ];
      final h = Gateway(
        cfg,
        store,
        seerr: sr,
        userActive: (_) async => true,
      ).handler;
      final t = pairDevice();
      expect((await h(req('/v1/search?q=abc', t))).statusCode, 200);
      expect(sr.detailCalls, Gateway.maxDetailLookups);
      for (var i = 1; i < Gateway.searchesPerMinute; i++) {
        expect((await h(req('/v1/search?q=abc', t))).statusCode, 200);
      }
      final res = await h(req('/v1/search?q=abc', t));
      expect(res.statusCode, 429);
      expect(res.headers['retry-after'], '60');
    });
  });

  group('low level', () {
    test('chmod600 handles non-ASCII names and reports failure', () {
      if (Platform.isWindows) return;
      final f = File('${tmp.path}/dätä-☃.json')..createSync();
      expect(chmod600(f.path), isTrue);
      expect(f.statSync().mode & 0x1ff, 384);
      expect(chmod600('${tmp.path}/missing'), isFalse);
    });

    test('upstream redirects are not followed', () async {
      final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var hits = 0;
      srv.listen((r) {
        hits++;
        r.response
          ..statusCode = 302
          ..headers.set('location', '/second')
          ..close();
      });
      final url = Uri.parse('http://127.0.0.1:${srv.port}/');
      final res = await jsonRequest('GET', url, headers: {'x-api-key': 'k'});
      expect(res.status, 302);
      final raw = await rawRequest(url);
      expect(raw.statusCode, 302);
      await raw.drain<void>();
      expect(hits, 2);
      await srv.close(force: true);
    });
  });
}
