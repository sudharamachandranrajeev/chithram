import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:torznab/torznab.dart';

String fixture(String name) => File('../../.github/fixtures/torznab/$name').readAsStringSync();

TorznabResponse ok(String body) => TorznabResponse(200, Uint8List.fromList(utf8.encode(body)));

void main() {
  final base = Uri.parse('http://192.168.1.5:9117/api?x=1');

  test('stub client finds nothing', () async {
    const c = NullTorznabClient();
    expect((await c.caps(base)).search, isFalse);
    expect(await c.search(base, query: 'Fixture Film 1'), isEmpty);
  });

  group('caps', () {
    test('modes and categories, adult dropped', () {
      final caps = parseCaps(fixture('caps.xml'));
      expect([caps.search, caps.tvSearch, caps.movieSearch], [true, true, true]);
      expect(caps.categories, [2000, 2040, 5000, 5040, 7000]);
    });

    test('json round trip', () {
      final caps = parseCaps(fixture('caps.xml'));
      final back = TorznabCaps.fromJson(caps.toJson());
      expect(back.categories, caps.categories);
      expect(back.movieSearch, isTrue);
    });
  });

  group('items', () {
    test('attributes parsed, adult category dropped', () {
      final items = parseItems(fixture('latest_movies.xml'));
      expect(items, hasLength(6));
      expect(items.any((i) => i.title.contains('Adult')), isFalse);
      final first = items.first;
      expect(first.title, 'Fixture Film 1 2026 1080p WEB-DL');
      expect(first.seeders, 900);
      expect(first.leechers, 100);
      expect(first.sizeBytes, 2147483648);
      expect(first.infoHash, hasLength(40));
      expect(first.torrentUrl, 'https://indexer.example/dl/m1.torrent');
      expect(first.detailsUrl, 'https://indexer.example/details/m1');
      expect(first.published, DateTime.utc(2026, 10, 24, 7));
      expect(first.categories, [2040]);
    });

    test('missing date stays null', () {
      final items = parseItems(fixture('latest_movies.xml'));
      expect(items.last.published, isNull);
    });

    test('magnet in link, ISO date, repeated category, untitled item skipped', () {
      final items = parseItems(fixture('magnet_only.xml'));
      expect(items, hasLength(1));
      final i = items.single;
      expect(i.magnet, startsWith('magnet:?xt=urn:btih:0123'));
      expect(i.torrentUrl, isNull);
      expect(i.published, DateTime.utc(2026, 10, 24, 10));
      expect(i.categories, [2000, 100002]);
      expect(i.leechers, 3);
    });

    test('error xml becomes a readable message', () {
      expect(
        () => parseItems(fixture('error.xml')),
        throwsA(
          isA<TorznabException>()
              .having((e) => e.message, 'message', 'The indexer refused the API key: Incorrect user credentials')
              .having((e) => e.code, 'code', '100'),
        ),
      );
    });

    test('not xml', () {
      expect(() => parseItems('<html'), throwsA(isA<TorznabException>()));
    });
  });

  group('dates', () {
    test('rfc 822 with offsets and names', () {
      expect(parseDate('Sat, 24 Oct 2026 08:00:00 +0200'), DateTime.utc(2026, 10, 24, 6));
      expect(parseDate('24 Oct 2026 08:00 GMT'), DateTime.utc(2026, 10, 24, 8));
      expect(parseDate('nonsense'), isNull);
      expect(parseDate(null), isNull);
    });
  });

  group('client', () {
    test('no query is latest: t=search, cats, limit, key, base query kept', () async {
      Uri? seen;
      final c = HttpTorznabClient(
        fetch: (u) async {
          seen = u;
          return ok(fixture('latest_movies.xml'));
        },
      );
      final items = await c.search(base, apiKey: 'sekrit', cats: [2000, 6000, 6040], limit: 100);
      expect(items, hasLength(6));
      expect(seen!.queryParameters, {'x': '1', 't': 'search', 'cat': '2000', 'limit': '100', 'apikey': 'sekrit'});
    });

    test('mode follows the arguments', () async {
      final seen = <Uri>[];
      final c = HttpTorznabClient(
        fetch: (u) async {
          seen.add(u);
          return ok(fixture('magnet_only.xml'));
        },
      );
      await c.search(base, query: 'Show', season: 1, episode: 2, tvdbId: 7);
      await c.search(base, imdbId: 'tt123');
      expect(seen[0].queryParameters, containsPair('t', 'tvsearch'));
      expect(seen[0].queryParameters, containsPair('ep', '2'));
      expect(seen[1].queryParameters, containsPair('t', 'movie'));
      expect(seen[1].queryParameters, containsPair('imdbid', '123'));
    });

    test('http statuses become messages that never hold the url or key', () async {
      for (final (status, text) in [(401, 'refused the API key'), (500, 'answered 500'), (429, 'rate limiting')]) {
        final c = HttpTorznabClient(
          fetch: (_) async => TorznabResponse(status, Uint8List(0), retryAfter: const Duration(seconds: 9)),
        );
        await expectLater(
          c.caps(base, apiKey: 'sekrit'),
          throwsA(
            isA<TorznabException>().having(
              (e) => e.message,
              'message',
              allOf(contains(text), isNot(contains('sekrit')), isNot(contains('192.168'))),
            ),
          ),
        );
      }
    });

    test('429 carries Retry-After', () async {
      final c = HttpTorznabClient(
        fetch: (_) async => TorznabResponse(429, Uint8List(0), retryAfter: const Duration(seconds: 9)),
      );
      await expectLater(
        c.caps(base),
        throwsA(isA<TorznabException>().having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 9))),
      );
    });

    test('caps over the client', () async {
      final c = HttpTorznabClient(
        fetch: (u) async {
          expect(u.queryParameters['t'], 'caps');
          return ok(fixture('caps.xml'));
        },
      );
      expect((await c.caps(base)).movieSearch, isTrue);
    });
  });

  group('endpoint rules', () {
    test('https anywhere, http only on the user network', () {
      for (final ok in [
        'https://indexer.example/api',
        'http://192.168.1.5:9117/api',
        'http://localhost:9117/',
        'http://jackett:9117/api',
        'http://10.0.0.2/api',
        'http://172.16.4.1/api',
        'http://nas.local/api',
      ]) {
        expect(endpointProblem(Uri.parse(ok)), isNull, reason: ok);
      }
      for (final bad in [
        'http://indexer.example/api',
        'http://172.32.0.1/api',
        'http://8.8.8.8/api',
        'ftp://192.168.1.5/',
        'https://user:pw@indexer.example/',
        'indexer.example/api',
      ]) {
        expect(endpointProblem(Uri.parse(bad)), isNotNull, reason: bad);
      }
    });
  });

  group('fetchDirect', () {
    late HttpServer server;
    setUp(() async => server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    tearDown(() => server.close(force: true));

    Uri url([String path = '/']) => Uri.parse('http://127.0.0.1:${server.port}$path');

    test('reads a body and Retry-After', () async {
      server.listen((r) {
        r.response
          ..statusCode = 429
          ..headers.set('retry-after', '30')
          ..write('slow down');
        r.response.close();
      });
      final r = await fetchDirect(url());
      expect(r.status, 429);
      expect(r.retryAfter, const Duration(seconds: 30));
      expect(utf8.decode(r.body), 'slow down');
    });

    test('follows a redirect that is still allowed', () async {
      server.listen((r) {
        if (r.uri.path == '/a') {
          r.response
            ..statusCode = 302
            ..headers.set('location', '/b');
        } else {
          r.response.write('done');
        }
        r.response.close();
      });
      expect(utf8.decode((await fetchDirect(url('/a'))).body), 'done');
    });

    test('refuses a redirect to a public http host', () async {
      server.listen((r) {
        r.response
          ..statusCode = 302
          ..headers.set('location', 'http://indexer.example/x?apikey=sekrit');
        r.response.close();
      });
      await expectLater(
        fetchDirect(url()),
        throwsA(isA<TorznabException>().having((e) => e.message, 'message', isNot(contains('sekrit')))),
      );
    });

    test('size cap', () async {
      server.listen((r) async {
        r.response.headers.chunkedTransferEncoding = true;
        final chunk = Uint8List(1024 * 1024);
        try {
          for (var i = 0; i < 7; i++) {
            r.response.add(chunk);
            await r.response.flush();
          }
          await r.response.close();
        } catch (_) {}
      });
      await expectLater(
        fetchDirect(url()),
        throwsA(isA<TorznabException>().having((e) => e.message, 'm', contains('5 MiB'))),
      );
    });

    test('connection refused hides the address', () async {
      final u = url('/?apikey=sekrit');
      await server.close(force: true);
      await expectLater(
        fetchDirect(u),
        throwsA(
          isA<TorznabException>().having((e) => e.message, 'm', allOf(contains('connect'), isNot(contains('sekrit')))),
        ),
      );
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    });
  });
}
