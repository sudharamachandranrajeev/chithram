import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chithram/src/features/torrents/home/popular_item.dart';
import 'package:chithram/src/features/torrents/home/popular_source.dart';
import 'package:chithram/src/features/torrents/home/torrent_home_feed.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 10, 24, 12);

PopularItem item(
  String title, {
  int seeders = 10,
  Duration? age = const Duration(hours: 1),
  PopularKind kind = PopularKind.film,
  String? hash,
  String? magnet,
  int? size,
  List<int> cats = const [],
  String source = 'a',
}) => PopularItem(
  title: title,
  kind: kind,
  sourceId: 'fixture:$source',
  sourceLabel: source.toUpperCase(),
  seeders: seeders,
  infoHash: hash,
  magnet: magnet,
  sizeBytes: size,
  published: age == null ? null : now.subtract(age),
  categories: cats,
);

String hex(int n) => n.toRadixString(16).padLeft(40, '0');

Iterable<String> titles(TorrentRail r) => r.items.map((i) => i.title);

TorrentRail rail(TorrentHomeFeed f, String id) => f.state.value.rails.firstWhere((r) => r.id == id);

void main() {
  group('ranking and windows', () {
    test('ranked by seeders, split by upload date, cumulative windows', () {
      final w = buildWindows([
        item('hour', seeders: 5, age: const Duration(hours: 1), hash: hex(1)),
        item('day edge', seeders: 50, age: const Duration(hours: 24), hash: hex(2)),
        item('3 days', seeders: 500, age: const Duration(days: 3), hash: hex(3)),
        item('20 days', seeders: 80, age: const Duration(days: 20), hash: hex(4)),
        item('40 days', seeders: 9999, age: const Duration(days: 40), hash: hex(5)),
        item('no date', seeders: 70, age: null, hash: hex(6)),
        item('future', seeders: 1, age: const Duration(hours: -3), hash: hex(7)),
      ], now);
      expect(w[PopularWindow.today]!.map((i) => i.title), ['day edge', 'hour', 'future']);
      expect(w[PopularWindow.week]!.map((i) => i.title), ['3 days', 'day edge', 'hour', 'future']);
      expect(w[PopularWindow.month]!.map((i) => i.title), ['3 days', '20 days', 'day edge', 'hour', 'future']);
      expect(w[PopularWindow.undated]!.map((i) => i.title), ['no date']);
    });

    test('items without seeders are not popular; ties go to the newer', () {
      final w = buildWindows([
        item('dead', seeders: 0, hash: hex(1)),
        item('old', seeders: 10, age: const Duration(hours: 5), hash: hex(2)),
        item('new', seeders: 10, age: const Duration(hours: 1), hash: hex(3)),
      ], now);
      expect(w[PopularWindow.today]!.map((i) => i.title), ['new', 'old']);
    });

    test('each kind is capped', () {
      final w = buildWindows([
        for (var i = 0; i < 40; i++) item('f$i', seeders: 100 + i, hash: hex(i)),
        for (var i = 0; i < 5; i++) item('t$i', seeders: 1 + i, hash: hex(100 + i), kind: PopularKind.tv),
      ], now);
      final today = w[PopularWindow.today]!;
      expect(today.where((i) => i.kind == PopularKind.film), hasLength(TorrentHomeFeed.perKind));
      expect(today.where((i) => i.kind == PopularKind.tv), hasLength(5));
      expect(today.first.title, 'f39');
    });
  });

  group('merge', () {
    test('same infohash merges across sources and kinds, most seeders win', () {
      final merged = mergeItems([
        item('Fixture Film 1 2026', seeders: 900, hash: hex(1), source: 'a'),
        item('Fixture.Film.1.2026', seeders: 1200, hash: hex(1).toUpperCase(), kind: PopularKind.tv, source: 'b'),
      ]);
      expect(merged, hasLength(1));
      expect(merged.single.seeders, 1200);
      expect(merged.single.sourceId, 'fixture:a');
      expect(merged.single.kind, PopularKind.film);
      expect(merged.single.sources, ['A', 'B']);
    });

    test('hash from the magnet link', () {
      final h = hex(0xabc);
      final merged = mergeItems([item('One', hash: h), item('Two', magnet: 'magnet:?xt=urn:btih:$h&dn=x')]);
      expect(merged, hasLength(1));
    });

    test('no hash: normalised title plus size', () {
      final merged = mergeItems([
        item('Fixture Film (2026) 1080p', size: 100),
        item('fixture.film.2026.1080p', size: 100, source: 'b'),
        item('fixture.film.2026.1080p', size: 101, source: 'c'),
      ]);
      expect(merged, hasLength(2));
    });

    test('earliest date kept', () {
      final merged = mergeItems([
        item('x', hash: hex(1), age: const Duration(hours: 2)),
        item('x', hash: hex(1), age: const Duration(hours: 9), source: 'b'),
      ]);
      expect(merged.single.published, now.subtract(const Duration(hours: 9)));
    });

    test('adult dropped by category and by name', () {
      final merged = mergeItems([
        item('Fine', hash: hex(1)),
        item('Hidden', hash: hex(2), cats: [2000, 6040]),
        item('Some XXX thing', hash: hex(3)),
        item('Class Xxxavier is fine', hash: hex(4)),
      ]);
      expect(merged.map((i) => i.title), ['Fine', 'Class Xxxavier is fine']);
    });
  });

  group('feed', () {
    late DateTime clock;
    late File cache;
    late Directory tmp;

    setUp(() {
      clock = now;
      tmp = Directory.systemTemp.createTempSync('torrent-home');
      cache = File('${tmp.path}/torrent_home.json');
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    TorrentHomeFeed make(FixturePopularSources s, {File? file}) =>
        TorrentHomeFeed(sources: s, cacheFile: file ?? cache, clock: () => clock);

    FixturePopularSource fixture({String id = 'a', Object? error}) => FixturePopularSource(
      id: 'fixture:$id',
      label: id.toUpperCase(),
      error: error,
      films: [
        item('Film A', seeders: 100, hash: hex(1), age: const Duration(hours: 2), source: id),
        item('Film B', seeders: 300, hash: hex(2), age: const Duration(days: 3), source: id),
        item('Film C', seeders: 20, hash: hex(3), age: null, source: id),
      ],
      tv: [item('Show A', seeders: 60, hash: hex(4), kind: PopularKind.tv, age: const Duration(hours: 5), source: id)],
    );

    test('rails: windows split into Films and TV, then Most seeded', () async {
      final f = make(FixturePopularSources([fixture()]));
      await f.open();
      final s = f.state.value;
      expect(s.loading, isFalse);
      expect(s.hasSources, isTrue);
      expect(
        [for (final r in s.rails) r.id],
        ['today-film', 'today-tv', 'week-film', 'week-tv', 'month-film', 'month-tv', 'undated'],
      );
      expect(s.rails.first.title, 'Popular today · Films');
      expect(titles(rail(f, 'week-film')), ['Film B', 'Film A']);
      expect(titles(rail(f, 'undated')), ['Film C']);
      expect(s.rails.map((r) => r.title), contains('Popular this month · TV'));
    });

    test('no sources: empty state, nothing fetched', () async {
      final f = make(FixturePopularSources([]));
      await f.open();
      expect(f.state.value.hasSources, isFalse);
      expect(f.state.value.rails, isEmpty);
      expect(f.state.value.loading, isFalse);
      expect(f.state.value.error, isNull);
    });

    test('cache TTLs: today 3 h, week 12 h, month 24 h', () async {
      final a = fixture();
      final f = make(FixturePopularSources([a]));
      await f.open();
      expect(a.calls, hasLength(2));

      // Reopen from the cache 2 h later: nothing is stale.
      clock = now.add(const Duration(hours: 2));
      final b = fixture();
      var g = make(FixturePopularSources([b]));
      await g.open();
      expect(b.calls, isEmpty);
      expect(g.state.value.rails, isNotEmpty);

      // 4 h: today is stale, so a fetch happens; week and month keep their time.
      clock = now.add(const Duration(hours: 4));
      await g.refresh();
      expect(b.calls, hasLength(2));
      final cached = jsonOf(cache);
      expect(cached['windows']['today']['at'], clock.toIso8601String());
      expect(cached['windows']['week']['at'], now.toIso8601String());
      expect(cached['windows']['month']['at'], now.toIso8601String());

      // 13 h later: today and week are stale, month is not (but is rebuilt too: same fetch).
      clock = now.add(const Duration(hours: 13));
      g = make(FixturePopularSources([fixture()]));
      await g.open();
      final c = jsonOf(cache);
      expect(c['windows']['today']['at'], clock.toIso8601String());
      expect(c['windows']['week']['at'], clock.toIso8601String());
      expect(c['windows']['month']['at'], now.toIso8601String());

      // 25 h after the first fetch the month is stale too.
      clock = now.add(const Duration(hours: 40));
      await make(FixturePopularSources([fixture()])).open();
      expect(jsonOf(cache)['windows']['month']['at'], clock.toIso8601String());
    });

    test('cache shows at once, before the fetch ends', () async {
      await make(FixturePopularSources([fixture()])).open();
      clock = now.add(const Duration(hours: 5));
      final slow = FixturePopularSource(id: 'fixture:a', label: 'A', delay: const Duration(milliseconds: 50));
      final f = make(FixturePopularSources([slow]));
      final opening = f.open();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(f.state.value.rails, isNotEmpty);
      expect(f.state.value.loading, isTrue);
      await opening;
    });

    test('force refetches everything', () async {
      final a = fixture();
      final f = make(FixturePopularSources([a]));
      await f.open();
      await f.refresh();
      expect(a.calls, hasLength(2));
      await f.refresh(force: true);
      expect(a.calls, hasLength(4));
    });

    test('changing the sources makes everything stale and drops removed ones', () async {
      final a = fixture();
      final s = FixturePopularSources([a]);
      await make(s).open();
      final b = fixture(id: 'b');
      final f = make(FixturePopularSources([b]));
      await f.open();
      expect(b.calls, hasLength(2));
      expect(f.state.value.rails.expand((r) => r.items).every((i) => i.sourceId == 'fixture:b'), isTrue);
    });

    test('removing every source clears the rails', () async {
      final s = FixturePopularSources([fixture()]);
      final f = make(s);
      await f.open();
      s.sources = [];
      await f.refresh();
      expect(f.state.value.hasSources, isFalse);
      expect(f.state.value.rails, isEmpty);
    });

    test('all sources fail and nothing is cached: error and Retry', () async {
      final bad = fixture(error: const SocketException('down'));
      final f = make(FixturePopularSources([bad]));
      await f.open();
      expect(f.state.value.rails, isEmpty);
      expect(f.state.value.error, 'Could not reach any source.');
      expect(f.state.value.sourceErrors.keys, ['A']);
      expect(f.state.value.loading, isFalse);
      // The user taps Retry once the network is back.
      final ok = fixture();
      final g = make(FixturePopularSources([ok]));
      await g.refresh(force: true);
      expect(g.state.value.rails, isNotEmpty);
      expect(g.state.value.error, isNull);
    });

    test('offline with a cache keeps the cached rails', () async {
      await make(FixturePopularSources([fixture()])).open();
      clock = now.add(const Duration(days: 2));
      final f = make(FixturePopularSources([fixture(error: const SocketException('down'))]));
      await f.open();
      expect(f.state.value.rails, isNotEmpty);
      expect(f.state.value.error, isNull);
      expect(f.state.value.sourceErrors, isNotEmpty);
    });

    test('one source failing does not hide the other', () async {
      final f = make(FixturePopularSources([fixture(error: StateError('boom')), fixture(id: 'b')]));
      await f.open();
      expect(f.state.value.rails, isNotEmpty);
      expect(f.state.value.sourceErrors.keys, ['A']);
    });

    test('a hung source times out', () async {
      final slow = FixturePopularSource(delay: const Duration(seconds: 5));
      final f = TorrentHomeFeed(
        sources: FixturePopularSources([slow]),
        clock: () => now,
        taskTimeout: const Duration(milliseconds: 20),
      );
      await f.open();
      expect(f.state.value.sourceErrors['Fixture'], contains('Did not answer'));
    });

    test('corrupt cache is ignored', () async {
      cache.writeAsStringSync('{not json');
      final a = fixture();
      await make(FixturePopularSources([a])).open();
      expect(a.calls, isNotEmpty);
      cache.writeAsStringSync('{"v":2}');
      final b = fixture();
      await make(FixturePopularSources([b])).open();
      expect(b.calls, isNotEmpty);
    });

    test('open does the work once', () async {
      final a = fixture();
      final f = make(FixturePopularSources([a]));
      await Future.wait([f.open(), f.open()]);
      expect(a.calls, hasLength(2));
    });

    test('concurrency limit per group', () async {
      var running = 0, peak = 0;
      final sources = [
        for (var i = 0; i < 5; i++)
          _Counting('s$i', () => ++running, () => --running, (n) => peak = n > peak ? n : peak),
      ];
      final f = TorrentHomeFeed(sources: FixturePopularSources(sources, concurrency: 2), clock: () => now);
      await f.open();
      expect(peak, 2);
      final g = TorrentHomeFeed(sources: FixturePopularSources(sources, concurrency: 1), clock: () => now);
      peak = 0;
      await g.open();
      expect(peak, 1);
    });

    test('fetchTorrent goes to the item\'s own source', () async {
      final a = FixturePopularSource(
        id: 'fixture:a',
        torrentBytes: Uint8List.fromList([1, 2, 3]),
        films: [item('Only link', hash: null)],
      );
      final f = make(FixturePopularSources([a]));
      await f.open();
      expect(await f.fetchTorrent(item('x', source: 'a')), [1, 2, 3]);
      await expectLater(f.fetchTorrent(item('x', source: 'gone')), throwsStateError);
    });
  });

  test('plugin concurrency: 1 on low RAM, 2 on phones and TVs, 4 on desktop', () {
    expect(pluginConcurrency(desktop: false, ramMb: 1536), 1);
    expect(pluginConcurrency(desktop: false, ramMb: 2048), 1);
    expect(pluginConcurrency(desktop: false, ramMb: 4096), 2);
    expect(pluginConcurrency(desktop: false), 2);
    expect(pluginConcurrency(desktop: true, ramMb: 1024), 4);
  });

  test('plugin adapter: current year, movies and tv, unknown values dropped', () async {
    final asked = <(String, String, String)>[];
    final sources = PluginPopularSources(
      enabled: () async => const [PluginEngineRef('e1', 'Engine One')],
      search: (id, what, cat) async {
        asked.add((id, what, cat));
        return [
          PluginHit(name: 'Hit', link: 'magnet:?xt=urn:btih:${hex(9)}', size: -1, seeds: -1, leech: 4, pubDate: now),
          const PluginHit(name: 'File', link: 'https://engine.example/dl/1', seeds: 7),
        ];
      },
      download: (id, link) async => Uint8List.fromList([9]),
      concurrency: 2,
      clock: () => now,
    );
    final groups = await sources.groups();
    expect(groups.single.concurrency, 2);
    final s = groups.single.sources.single;
    final films = await s.fetch(PopularKind.film);
    await s.fetch(PopularKind.tv);
    expect(asked, [('e1', '2026', 'movies'), ('e1', '2026', 'tv')]);
    expect(films[0].infoHash, hex(9));
    expect(films[0].seeders, isNull);
    expect(films[0].sizeBytes, isNull);
    expect(films[0].published, now);
    expect(films[1].torrentUrl, 'https://engine.example/dl/1');
    expect(await s.fetchTorrent(films[1]), [9]);
    expect(
      await PluginPopularSources(
        enabled: () async => [],
        search: (_, _, _) async => [],
        download: (_, _) async => Uint8List(0),
        concurrency: 1,
      ).groups(),
      isEmpty,
    );
  });
}

class _Counting implements PopularSource {
  _Counting(this.id, this.up, this.down, this.peak);
  @override
  final String id;
  final int Function() up;
  final int Function() down;
  final void Function(int) peak;
  @override
  String get label => id;
  @override
  Future<List<PopularItem>> fetch(PopularKind kind) async {
    peak(up());
    await Future<void>.delayed(const Duration(milliseconds: 5));
    down();
    return [];
  }

  @override
  Future<Uint8List> fetchTorrent(PopularItem item) async => Uint8List(0);
}

Map<String, dynamic> jsonOf(File f) => jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
