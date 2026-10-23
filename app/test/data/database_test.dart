import 'package:chithram/src/data/database.dart';
import 'package:chithram/src/data/db_pin_store.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_host/nova_host.dart';

import 'generated/schema.dart';

void main() {
  // The schema test opens a second database next to setUp's.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('schema v1 matches the committed dump', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final connection = await verifier.startAt(1);
    final opened = AppDatabase(connection);
    addTearDown(opened.close);
    await verifier.migrateAndValidate(opened, 1);
  });

  test('DAOs are registered', () {
    expect(db.cacheDao, isNotNull);
    expect(db.pluginDao, isNotNull);
    expect(db.torznabDao, isNotNull);
    expect(db.runsDao, isNotNull);
  });

  test('http_cache round-trips and has the hard_expiry index', () async {
    final now = DateTime.utc(2026, 10, 22);
    await db.into(db.httpCache).insert(HttpCacheCompanion.insert(
          key: 'GET /3/movie/popular?page=1',
          parserVer: 1,
          fetchedAt: now,
          softExpiry: now.add(const Duration(hours: 24)),
          hardExpiry: now.add(const Duration(days: 180)),
          body: Uint8List.fromList([1, 2, 3]),
        ));
    final row = await db.select(db.httpCache).getSingle();
    expect(row.key, 'GET /3/movie/popular?page=1');
    expect(row.etag, isNull);
    expect(row.body, [1, 2, 3]);
    final idx = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'http_cache'").get();
    expect(idx.map((r) => r.read<String>('name')), contains('http_cache_hard_expiry'));
  });

  test('plugins keep JSON host lists; enabled defaults to true', () async {
    final now = DateTime.utc(2026, 10, 22);
    await db.into(db.plugins).insert(PluginsCompanion.insert(
          id: 'single:fixture',
          engineId: 'fixture',
          name: 'Fixture',
          sha256: 'ab' * 32,
          sourceUrl: 'http://127.0.0.1/fixture.py',
          declaredUrl: 'http://127.0.0.1',
          allowedHosts: const ['127.0.0.1', 'cdn.example.test'],
          signed: false,
          installedAt: now,
          updatedAt: now,
        ));
    final row = await db.select(db.plugins).getSingle();
    expect(row.allowedHosts, ['127.0.0.1', 'cdn.example.test']);
    expect(row.enabled, isTrue);
    expect(row.repoId, isNull);
  });

  test('torznab caps JSON and provider runs', () async {
    await db.into(db.torznabEndpoints).insert(TorznabEndpointsCompanion.insert(
          id: 'e1',
          name: 'Local',
          baseUrl: 'http://127.0.0.1:9117/api',
          caps: const Value({'search': true, 'cats': [2000, 5000]}),
        ));
    expect((await db.select(db.torznabEndpoints).getSingle()).caps, {'search': true, 'cats': [2000, 5000]});
    await db.into(db.providerRuns).insert(ProviderRunsCompanion.insert(
          providerId: 'e1',
          at: DateTime.utc(2026, 10, 22),
          status: 'ok',
          ms: 120,
          results: 3,
          requests: 1,
          blockedHosts: const ['x.example.test'],
        ));
    final run = await db.select(db.providerRuns).getSingle();
    expect(run.blockedHosts, ['x.example.test']);
    expect(run.reason, isNull);
  });

  test('DbPinStore pins a key, keeps it, and survives a repo row update', () async {
    final pins = DbPinStore(db, now: () => DateTime.utc(2026, 10, 22));
    expect(await pins.get('repo1'), isNull);
    await pins.set('repo1', PinnedKey('AABB', 'untrusted comment\nRWQ...'));
    final got = await pins.get('repo1');
    expect(got!.keyIdHex, 'AABB');
    expect(got.publicKeyText, 'untrusted comment\nRWQ...');
    await pins.set('repo1', PinnedKey('CCDD', 'other'));
    expect((await pins.get('repo1'))!.keyIdHex, 'CCDD');
    expect(await db.select(db.pluginRepos).get(), hasLength(1));
  });
}
