import 'package:chithram/src/catalog/fake_catalog.dart';
import 'package:chithram/src/core/item_id.dart';
import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/find/fake_find.dart';
import 'package:chithram/src/find/find_api.dart';
import 'package:chithram/src/home/fake_home.dart';
import 'package:chithram/src/home/home_repository.dart';
import 'package:chithram/src/home/home_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmdb/tmdb.dart';

void main() {
  test('tmdb item ids', () {
    expect(ItemId.tmdbMovie(603), 'tmdb:movie:603');
    expect(ItemId.tmdbShow(1399), 'tmdb:tv:1399');
    expect(ItemId.tmdbEpisode(1399, 2, 5), 'tmdb:tv:1399/s2e5');
  });

  test('FakeFindProvider streams results and stops when cancelled', () async {
    const r = FindResult(providerId: 'fake', title: 'Fixture Film 1 1080p', kind: ResultKind.torrent, seeders: 9);
    final p = FakeFindProvider(results: [r, r, r], delay: const Duration(milliseconds: 20));
    final cancel = CancelToken();
    final got = <FindResult>[];
    await for (final x in p.search(const TextQuery('Fixture Film 1'), cancel)) {
      got.add(x);
      cancel.cancel();
    }
    expect(got, hasLength(1));
    expect(p.queries.single, isA<TextQuery>());
    expect(cancel.cancelled, isTrue);
    await cancel.whenCancelled;
  });

  test('FakeFindProviderSource notifies', () {
    final s = FakeFindProviderSource();
    var n = 0;
    s.providers.addListener(() => n++);
    s.value = [FakeFindProvider(id: 'a')];
    expect(n, 1);
    expect(s.providers.value.single.id, 'a');
  });

  test('FakeCatalog serves stale then fresh', () async {
    final c = FakeCatalog();
    final seen = await c.details(MediaKind.tv, 7).toList();
    expect(seen.map((e) => e.stale), [true, false]);
    expect(seen.last.value.seasons, hasLength(1));
    expect(seen.last.value.title, 'Fixture Show 7');
    expect((await c.search('fixture film')), isNotEmpty);
    expect((await c.search('zzz')), isEmpty);
  });

  test('FakeHomeSource: etag gives not-modified; failure and auth rejection', () async {
    final src = FakeHomeSource();
    const cfg = HomeConfig();
    final rails = src.rails(cfg);
    expect(rails.first.hero, isTrue);
    expect(await src.fetch(rails[1], cfg), isA<RailData>());
    expect(await src.fetch(rails[1], cfg, etag: 'fixture-etag'), isA<RailNotModified>());
    src.failWith = const RailFailed('401', authRejected: true);
    final f = await src.fetch(rails[1], cfg) as RailFailed;
    expect(f.authRejected, isTrue);
    expect(src.fetches, 3);
  });

  test('AppServices.memory wires the 0.3.0 services without opening anything', () {
    final s = AppServices.memory(home: FakeHomeRepository(HomeState(snapshot: fixtureSnapshot())));
    expect(s.home.state.value.snapshot!.rails, hasLength(3));
    expect(s.findSources, hasLength(1));
    expect(s.secrets.isFallback, isFalse);
  });

  test('the stub engine serves the snapshot and never refreshes', () async {
    final s = AppServices.memory();
    expect(s.home.state.value.snapshot, isNull);
    expect(s.home.state.value.configured, isFalse);
    await s.home.refresh(force: true);
    expect(s.home.state.value.snapshot, isNull);
  });

  test('the in-memory database opens on first use and has the v1 tables', () async {
    final s = AppServices.memory();
    final n = await s.db.select(s.db.plugins).get();
    expect(n, isEmpty);
    await s.db.close();
  });
}
