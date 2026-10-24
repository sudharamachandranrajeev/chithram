import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:chithram/src/core/secrets.dart';
import 'package:chithram/src/data/database.dart';
import 'package:chithram/src/features/torrents/home/popular_item.dart';
import 'package:chithram/src/features/torrents/home/popular_source.dart';
import 'package:chithram/src/features/torrents/home/torrent_home_feed.dart';
import 'package:chithram/src/features/torrents/torrent_logic.dart';
import 'package:chithram/src/find/find_api.dart';
import 'package:chithram/src/find/torznab/torznab_provider.dart';
import 'package:chithram/src/find/torznab/torznab_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:torznab/torznab.dart';

String fixture(String name) => File('../.github/fixtures/torznab/$name').readAsStringSync();

TorznabResponse ok(String body) => TorznabResponse(200, Uint8List.fromList(utf8.encode(body)));

/// Answers like an indexer: caps, movies (2000), TV (5000); records the URLs.
class FakeIndexer {
  final urls = <Uri>[];
  int status = 200;
  Duration? retryAfter;

  Future<TorznabResponse> call(Uri u) async {
    urls.add(u);
    if (status != 200) return TorznabResponse(status, Uint8List(0), retryAfter: retryAfter);
    final p = u.queryParameters;
    if (p['apikey'] != 'sekrit') return ok(fixture('error.xml'));
    return switch (p['t']) {
      'caps' => ok(fixture('caps.xml')),
      _ => ok(fixture(p['cat'] == '5000' ? 'latest_tv.xml' : 'latest_movies.xml')),
    };
  }
}

void main() {
  late AppDatabase db;
  late MemorySecretStore secrets;
  late FakeIndexer indexer;
  late DateTime clock;
  late NetworkChoice choice;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    secrets = MemorySecretStore();
    indexer = FakeIndexer();
    clock = DateTime.utc(2026, 10, 24, 12);
    choice = NetworkChoice.unset;
  });
  tearDown(() => db.close());

  TorznabService make({TorznabFetch? fetch}) => TorznabService(
    db: db,
    secrets: secrets,
    network: () => choice,
    fetch: fetch ?? indexer.call,
    clock: () => clock,
    random: _Mid(),
    minGap: Duration.zero,
  );

  const url = 'http://192.168.1.5:9117/api/v2.0/indexers/all/results/torznab/';

  group('endpoints', () {
    test('add checks caps, keeps the key in the secret store only', () async {
      final s = make();
      final e = await s.add(name: ' Home ', url: url, apiKey: 'sekrit');
      expect(e.name, 'Home');
      expect(e.caps!.movieSearch, isTrue);
      expect(indexer.urls.single.queryParameters, containsPair('t', 'caps'));
      expect(await secrets.read(e.secretKey), 'sekrit');
      final row = (await db.torznabDao.all()).single;
      expect(jsonEncode([row.baseUrl, row.name, row.caps]), isNot(contains('sekrit')));
      expect(row.enabled, isTrue);
      expect(row.capsAt!.toUtc(), clock);
    });

    test('name defaults to the host; reload from the database', () async {
      await make().add(name: '', url: url, apiKey: 'sekrit');
      final again = make();
      await again.load();
      expect(again.endpoints.single.name, '192.168.1.5');
      expect(again.endpoints.single.caps!.tvSearch, isTrue);
      expect(again.enabled, hasLength(1));
    });

    test('a wrong key or address adds nothing', () async {
      final s = make();
      await expectLater(
        s.add(name: 'x', url: url, apiKey: 'wrong'),
        throwsA(isA<TorznabException>().having((e) => e.message, 'm', contains('refused the API key'))),
      );
      await expectLater(
        s.add(name: 'x', url: 'http://indexer.example/api', apiKey: 'sekrit'),
        throwsA(isA<TorznabException>().having((e) => e.message, 'm', contains('https'))),
      );
      await expectLater(s.add(name: 'x', url: 'nonsense', apiKey: 'sekrit'), throwsA(isA<TorznabException>()));
      expect(s.endpoints, isEmpty);
      expect(await db.torznabDao.all(), isEmpty);
      expect(secrets.isFallback, isFalse);
    });

    test('disable, enable and remove (the key goes too)', () async {
      final s = make();
      final e = await s.add(name: 'Home', url: url, apiKey: 'sekrit');
      await s.setEnabled(e.id, false);
      expect(s.enabled, isEmpty);
      expect((await db.torznabDao.all()).single.enabled, isFalse);
      await s.setEnabled(e.id, true);
      expect(s.enabled, hasLength(1));
      await s.remove(e.id);
      expect(s.endpoints, isEmpty);
      expect(await db.torznabDao.all(), isEmpty);
      expect(await secrets.read(e.secretKey), isNull);
    });

    test('test refreshes caps and health', () async {
      final s = make();
      final e = await s.add(name: 'Home', url: url, apiKey: 'sekrit');
      clock = clock.add(const Duration(hours: 1));
      final caps = await s.test(e.id);
      expect(caps.categories, contains(2000));
      expect(s.health(e.id).lastOk, clock);
      expect(s.endpoints.single.capsAt, clock);
    });
  });

  group('etiquette', () {
    test('failure backs off with jitter; backoff holds calls; test overrides it', () async {
      final s = make();
      final e = await s.add(name: 'Home', url: url, apiKey: 'sekrit');
      indexer.status = 500;
      await expectLater(s.search(e, cats: [2000]), throwsA(isA<TorznabException>()));
      expect(s.health(e.id).failures, 1);
      // Mid jitter: exactly 30 s.
      expect(s.health(e.id).retryAt, clock.add(const Duration(seconds: 30)));
      final before = indexer.urls.length;
      await expectLater(
        s.search(e, cats: [2000]),
        throwsA(isA<TorznabException>().having((x) => x.message, 'm', contains('backing off'))),
      );
      expect(indexer.urls.length, before, reason: 'no request while backing off');

      clock = clock.add(const Duration(seconds: 31));
      await expectLater(s.search(e, cats: [2000]), throwsA(isA<TorznabException>()));
      expect(s.health(e.id).retryAt, clock.add(const Duration(seconds: 60)));

      indexer.status = 200;
      await s.test(e.id); // not held back by the backoff
      expect(s.health(e.id).failures, 0);
      expect(s.health(e.id).retryAt, isNull);
    });

    test('backoff is capped at 6 h and honours Retry-After', () async {
      final s = make();
      final e = await s.add(name: 'Home', url: url, apiKey: 'sekrit');
      indexer.status = 429;
      indexer.retryAfter = const Duration(minutes: 20);
      await expectLater(s.search(e), throwsA(isA<TorznabException>()));
      expect(s.health(e.id).retryAt, clock.add(const Duration(minutes: 20)));
      indexer.retryAfter = null;
      indexer.status = 500;
      for (var i = 0; i < 20; i++) {
        clock = s.health(e.id).retryAt!.add(const Duration(seconds: 1));
        await expectLater(s.search(e), throwsA(isA<TorznabException>()));
      }
      expect(s.health(e.id).retryAt!.difference(clock), TorznabService.maxBackoff);
    });

    test('calls to one endpoint are spaced by minGap', () async {
      final times = <DateTime>[];
      final s = TorznabService(
        db: db,
        secrets: secrets,
        network: () => choice,
        fetch: (u) {
          times.add(DateTime.now());
          return indexer.call(u);
        },
        minGap: const Duration(milliseconds: 80),
      );
      final e = await s.add(name: 'Home', url: url, apiKey: 'sekrit');
      times.clear();
      await Future.wait([
        s.search(e, cats: [2000]),
        s.search(e, cats: [5000]),
        s.search(e, cats: [2000]),
      ]);
      expect(times, hasLength(3));
      // Slots are 80 ms apart; allow scheduler jitter.
      expect(times[2].difference(times[0]), greaterThanOrEqualTo(const Duration(milliseconds: 100)));
    });

    test('the key is never in an error message', () async {
      final s = make(fetch: (u) async => throw SocketException('failed for $u'));
      await expectLater(
        s.add(name: 'x', url: url, apiKey: 'sekrit'),
        throwsA(
          isA<TorznabException>().having(
            (e) => e.message,
            'm',
            allOf(isNot(contains('sekrit')), isNot(contains('192.168'))),
          ),
        ),
      );
    });
  });

  group('traffic route', () {
    test('a public host goes through SOCKS5 when chosen, never directly', () async {
      choice = NetworkChoice(NetworkMode.socks5, Socks5Address.tryParse('socks5://127.0.0.1:1'));
      final s = TorznabService(db: db, secrets: secrets, network: () => choice, minGap: Duration.zero);
      await expectLater(
        s.add(name: 'x', url: 'https://indexer.example/api', apiKey: 'sekrit'),
        throwsA(
          isA<TorznabException>().having((e) => e.message, 'm', allOf(contains('SOCKS5'), isNot(contains('sekrit')))),
        ),
      );
    });

    test('a private host is reached directly even with SOCKS5 chosen', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final seen = <Uri>[];
      server.listen((r) {
        seen.add(r.uri);
        r.response.write(fixture('caps.xml'));
        r.response.close();
      });
      choice = NetworkChoice(NetworkMode.socks5, Socks5Address.tryParse('socks5://127.0.0.1:1'));
      final s = TorznabService(db: db, secrets: secrets, network: () => choice, minGap: Duration.zero);
      final e = await s.add(name: 'lan', url: 'http://127.0.0.1:${server.port}/api', apiKey: 'k');
      expect(e.caps!.search, isTrue);
      expect(seen.single.queryParameters, containsPair('apikey', 'k'));
    });
  });

  group('from endpoint to rails', () {
    test('fixture indexer feeds the popular rails; adult dropped, duplicate merged', () async {
      final s = make();
      await s.add(name: 'Home', url: url, apiKey: 'sekrit');
      final feed = TorrentHomeFeed(sources: TorznabPopularSources(s), clock: () => DateTime.utc(2026, 10, 24, 12));
      await feed.open();
      final asked = indexer.urls
          .where((u) => u.queryParameters['t'] == 'search')
          .map((u) => u.queryParameters)
          .toList();
      expect(asked, hasLength(2));
      expect(asked.map((q) => q['cat']), unorderedEquals(['2000', '5000']));
      expect(asked.every((q) => q['limit'] == '100' && !q.containsKey('q')), isTrue);

      final rails = {for (final r in feed.state.value.rails) r.id: r.items.map((i) => i.title).toList()};
      expect(rails['today-film'], ['Fixture Film 1 2026 1080p WEB-DL', 'Fixture Film 2 2026 2160p HDR']);
      expect(rails['today-tv'], ['Fixture Show S02E05 1080p WEB']);
      expect(rails['week-film']!.first, 'Fixture Film 3 2026 720p');
      expect(rails['month-film'], [
        'Fixture Film 3 2026 720p',
        'Fixture Film 1 2026 1080p WEB-DL',
        'Fixture Film 4 2026 1080p',
        'Fixture Film 2 2026 2160p HDR',
      ]);
      expect(rails['undated'], ['Fixture Film 6 2026 1080p']);
      final all = feed.state.value.rails.expand((r) => r.items).toList();
      expect(all.any((i) => i.title.contains('Adult')), isFalse);
      // Film 1 also appears in the TV list with fewer seeders: one entry, 900 seeders.
      final film1 = feed.state.value.rails.first.items.first;
      expect(film1.seeders, 900);
      expect(rails['today-tv']!.any((t) => t.contains('Film 1')), isFalse);
      expect(film1.sources, ['Home']);
      expect(film1.kind, PopularKind.film);
      // Month window excludes the 2025-09 film (> 30 d) and "Another Show" (16 d) is in it.
      expect(rails.values.expand((x) => x).any((t) => t.contains('Film 5')), isFalse);
      expect(rails['month-tv'], contains('Another Show S01 Complete 720p'));
    });

    test('fetchTorrent uses the indexer link', () async {
      final fetched = <Uri>[];
      final s = make(
        fetch: (u) async {
          if (u.path.endsWith('.torrent')) {
            fetched.add(u);
            return TorznabResponse(200, Uint8List.fromList([7, 7]));
          }
          return indexer.call(u);
        },
      );
      final e = await s.add(name: 'Home', url: url, apiKey: 'sekrit');
      final src = TorznabPopularSource(s, e);
      final items = await src.fetch(PopularKind.film);
      expect(await src.fetchTorrent(items.first), [7, 7]);
      expect(fetched.single.path, '/dl/m1.torrent');
    });
  });

  group('Find provider', () {
    test('one provider per enabled endpoint; results carry hash, date and seeders', () async {
      final s = make();
      final e = await s.add(name: 'Home', url: url, apiKey: 'sekrit');
      final providers = TorznabProviders(s);
      expect(providers.providers.value.single.id, 'torznab:${e.id}');
      final p = providers.providers.value.single;
      final results = await p.search(const TextQuery('fixture'), CancelToken()).toList();
      expect(results, hasLength(6));
      final first = results.first;
      expect(first.kind, ResultKind.torrent);
      expect(first.seeders, 900);
      expect(first.infoHash, hasLength(40));
      expect(first.hasTorrentFile, isTrue);
      await s.setEnabled(e.id, false);
      expect(providers.providers.value, isEmpty);
    });
  });
}

class _Mid implements Random {
  @override
  double nextDouble() => 0.5;
  @override
  bool nextBool() => false;
  @override
  int nextInt(int max) => 0;
}
