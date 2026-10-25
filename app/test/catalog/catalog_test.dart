import 'dart:async';
import 'dart:io';

import 'package:chithram/src/catalog/catalog_worker.dart';
import 'package:chithram/src/catalog/tmdb_catalog.dart';
import 'package:chithram/src/catalog/tmdb_home_source.dart';
import 'package:chithram/src/core/prefs.dart';
import 'package:chithram/src/core/secrets.dart';
import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/data/database.dart';
import 'package:chithram/src/features/metadata/metadata_setup.dart';
import 'package:chithram/src/features/metadata/metadata_settings.dart';
import 'package:chithram/src/features/metadata/attribution.dart';
import 'package:chithram/src/home/home_source.dart';
import 'package:chithram/src/home/snapshot.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmdb/tmdb.dart';

const key = '0123456789abcdef0123456789abcdef';
class FailingDeleteStore extends MemorySecretStore {
  FailingDeleteStore() : super({TmdbCatalog.secretKey: key});
  @override
  Future<void> delete(String key) async => throw StateError('keyring unavailable');
}
class SlowWriteStore extends MemorySecretStore {
  SlowWriteStore() : super({TmdbCatalog.secretKey: key});
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> write(String key, String value) async {
    entered.complete(); await release.future; await super.write(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late CatalogWorker worker;
  late AppDatabase db;
  late TmdbCatalog catalog;
  late Prefs prefs;
  late MemorySecretStore secrets;
  late DateTime now;
  late List<Uri> hits;
  late int revision;
  late bool conditional;
  Completer<void>? gate;
  String fixture(String name) =>
      File('../.github/fixtures/tmdb/$name.json').readAsStringSync();

  setUp(() async {
    now = DateTime.utc(2026, 10, 1);
    hits = [];
    revision = 0;
    conditional = false;
    gate = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      hits.add(request.uri);
      if (gate != null) await gate!.future;
      if (request.uri.queryParameters['api_key'] ==
          'ffffffffffffffffffffffffffffffff') {
        request.response.statusCode = 401;
        await request.response.close();
        return;
      }
      if (conditional &&
          request.headers.value('if-none-match') == 'fixture-etag') {
        request.response.statusCode = 304;
        await request.response.close();
        return;
      }
      request.response.headers.set('etag', 'fixture-etag');
      final path = request.uri.path;
      final name = path.endsWith('configuration')
          ? 'configuration'
          : path.contains('/season/')
          ? 'season'
          : path.contains('genre/')
          ? 'genres'
          : path.endsWith('/1')
          ? 'movie-details'
          : path.endsWith('/2')
          ? 'tv-details'
          : path.contains('search') || path.contains('/all/')
          ? 'mixed-list'
          : path.contains('/tv/')
          ? 'tv-list'
          : 'movie-list';
      request.response.write(
        fixture(name)
            .replaceAll('Fixture Film 1', 'Fixture Film ${1 + revision}'),
      );
      await request.response.close();
    });
    worker = CatalogWorker(
      base: Uri.parse('http://127.0.0.1:${server.port}/3/'),
    );
    db = AppDatabase(NativeDatabase.memory());
    secrets = MemorySecretStore({TmdbCatalog.secretKey: key});
    prefs = Prefs.memory({'tmdb.configured': true});
    catalog = TmdbCatalog(
      worker: worker,
      cache: db.cacheDao,
      secrets: secrets,
      prefs: prefs,
      clock: () => now,
    );
  });
  tearDown(() async {
    gate?.complete();
    gate = null;
    await worker.close();
    await server.close(force: true);
    await db.close();
  });

  test(
    'SWR emits stale cache followed by fresh worker parsed details',
    () async {
      expect(
        (await catalog.details(MediaKind.movie, 1).first).value.title,
        'Fixture Film 1',
      );
      now = now.add(const Duration(days: 8));
      revision = 1;
      final values = await catalog.details(MediaKind.movie, 1).toList();
      expect(values.map((v) => v.value.title), [
        'Fixture Film 1',
        'Fixture Film 2',
      ]);
      expect(values.map((v) => v.stale), [true, false]);
      expect(
        hits.last.queryParameters['append_to_response'],
        'credits,videos,recommendations,external_ids',
      );
    },
  );
  test(
    'fresh cache avoids HTTP; 304 renews soft TTL but preserves hard expiry',
    () async {
      await catalog.details(MediaKind.movie, 1).drain<void>();
      final row = (await db.select(db.httpCache).get()).single;
      await catalog.details(MediaKind.movie, 1).drain<void>();
      expect(hits.length, 1);
      now = now.add(const Duration(days: 8));
      conditional = true;
      expect((await catalog.details(MediaKind.movie, 1).toList()).length, 2);
      final updated = (await db.select(db.httpCache).get()).single;
      expect(updated.hardExpiry, row.hardExpiry);
      expect(updated.softExpiry.isAfter(now), true);
    },
  );
  test('180 day hard expiry purges without serving expired content', () async {
    await catalog.details(MediaKind.movie, 1).drain<void>();
    now = now.add(const Duration(days: 180));
    revision = 1;
    final values = await catalog.details(MediaKind.movie, 1).toList();
    expect(values.length, 1);
    expect(values.single.value.title, 'Fixture Film 2');
  });
  test('every rail, search and discover excludes adult and parses endpoint responses', () async {
    final source = TmdbHomeSource(catalog: catalog, prefs: prefs);
    final config = HomeConfig(
      originalLanguages: ['ta', 'hi', 'ml', 'en', 'fr'],
    );
    final rails = source.rails(config);
    expect(rails.length, 16);
    for (final rail in rails) {
      expect(await source.fetch(rail, config), isA<RailData>());
    }
    expect(
      await source.fetch(rails.first, config, etag: 'fixture-etag'),
      isA<RailData>(),
    );
    expect((await catalog.search('fixture')).length, 2);
    expect((await catalog.discoverGenre(MediaKind.movie, 12)).length, 1);
    expect(
      hits.every((u) => u.queryParameters['include_adult'] == 'false'),
      true,
    );
    expect((await catalog.genres(MediaKind.tv)).single.id, 12);
    expect((await catalog.season(2, 1).first).value.episodes.single.number, 1);
    expect((await catalog.details(MediaKind.tv, 2).first).value.tvdbId, 22);
  });
  test(
    'search stays memory only and honors locale changes and ten minute expiry',
    () async {
      await catalog.search('fixture');
      await catalog.search('fixture');
      expect(hits.length, 1);
      expect(await db.select(db.httpCache).get(), isEmpty);
      await prefs.set('tmdb.language', 'ta-IN');
      await catalog.search('fixture');
      expect(hits.length, 2);
      expect(hits.last.queryParameters['language'], 'ta-IN');
      now = now.add(const Duration(minutes: 11));
      await catalog.search('fixture');
      expect(hits.length, 3);
    },
  );
  test('invalidating in-flight work prevents cache repopulation', () async {
    gate = Completer<void>();
    final request = catalog.details(MediaKind.movie, 1).toList();
    final expected = expectLater(request, throwsA(isA<TmdbException>()));
    while (hits.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final invalidation = catalog.invalidate();
    gate!.complete();
    gate = null;
    await invalidation;
    await expected;
    expect(await db.select(db.httpCache).get(), isEmpty);
  });
  test(
    'setup validates good and bad keys; rejection preserves stored key',
    () async {
      final s = AppServices.memory(
        db: db,
        secrets: secrets,
        prefs: prefs,
        catalog: catalog,
      );
      await saveMetadataKey(s, key, worker: worker);
      expect(prefs.getBool('tmdb.configured'), true);
      await expectLater(
        saveMetadataKey(s, 'ffffffffffffffffffffffffffffffff', worker: worker),
        throwsA(isA<TmdbException>()),
      );
      expect(await secrets.read(TmdbCatalog.secretKey), key);
    },
  );
  test(
    'removal purges cache, snapshot, image files and configured flag',
    () async {
      final s = AppServices.memory(
        db: db,
        secrets: secrets,
        prefs: prefs,
        catalog: catalog,
      );
      await catalog.details(MediaKind.movie, 1).drain<void>();
      await s.snapshots.save(
        HomeSnapshot(
          generatedAt: now,
          language: 'en-US',
          region: 'US',
          hero: const [],
          rails: const [],
        ),
      );
      final image = File('${s.paths.cacheDir('img').path}/fixture');
      await image.parent.create(recursive: true);
      await image.writeAsString('fixture');
      await removeMetadataKey(s);
      expect(await secrets.read(TmdbCatalog.secretKey), isNull);
      expect(prefs.getBool('tmdb.configured'), false);
      expect(await db.select(db.httpCache).get(), isEmpty);
      expect(await s.snapshots.load(), isNull);
      expect(await image.exists(), false);
    },
  );
  test('replacement suspends catalog access and rejects concurrent removal', () async {
    final store = SlowWriteStore();
    final s = AppServices.memory(db:db,secrets:store,prefs:prefs,catalog:catalog);
    final saving = saveMetadataKey(s,key,worker:worker);
    await store.entered.future;
    await expectLater(catalog.details(MediaKind.movie,1).first, throwsA(isA<TmdbException>()));
    await expectLater(catalog.search('fixture'), throwsA(isA<TmdbException>()));
    await expectLater(removeMetadataKey(s), throwsA(isA<TmdbException>()));
    store.release.complete(); await saving;
    expect(metadataBusy(s).value,false);
    expect((await catalog.details(MediaKind.movie,1).first).value.title,'Fixture Film 1');
  });
  test('removal purges content even when deleting the keyring secret fails', () async {
    final s = AppServices.memory(db:db,secrets:FailingDeleteStore(),prefs:prefs,catalog:catalog);
    await catalog.details(MediaKind.movie,1).drain<void>();
    await s.snapshots.save(HomeSnapshot(generatedAt:now,language:'en-US',region:'US',hero:const [],rails:const []));
    await expectLater(removeMetadataKey(s),throwsStateError);
    expect(await db.select(db.httpCache).get(),isEmpty);
    expect(await s.snapshots.load(),isNull);
    expect(prefs.getBool('tmdb.configured'),false);
    await expectLater(catalog.details(MediaKind.movie,1).first,throwsA(isA<TmdbException>()));
  });
  test('worker close promptly rejects active and subsequent calls', () async {
    gate=Completer<void>();
    final active=worker.fetch(key:key,path:'configuration');
    final rejected=expectLater(active,throwsA(isA<TmdbException>()));
    while(hits.isEmpty) {await Future<void>.delayed(const Duration(milliseconds:5));}
    await worker.close(); await rejected;
    await expectLater(worker.fetch(key:key,path:'configuration'),throwsA(isA<TmdbException>()));
    gate!.complete();gate=null;
  });
  test('search invalidation cannot restore an old in-memory result', () async {
    gate=Completer<void>();
    final first=catalog.search('fixture');
    final duplicate=catalog.search('fixture');
    final errors=Future.wait([expectLater(first,throwsA(isA<TmdbException>())),expectLater(duplicate,throwsA(isA<TmdbException>()))]);
    while(hits.isEmpty) {await Future<void>.delayed(const Duration(milliseconds:5));}
    final invalidation=catalog.invalidate();gate!.complete();gate=null;
    await invalidation;await errors;
    await catalog.search('fixture');expect(hits.length,2);
  });

  testWidgets(
    'metadata settings shows logo, exact attribution and setup actions',
    (tester) async {
      final s = AppServices.memory(
        db: db,
        secrets: secrets,
        prefs: prefs,
        catalog: catalog,
      );
      await tester.pumpWidget(
        AppServicesScope(
          services: s,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: MetadataSettings()),
            ),
          ),
        ),
      );
      expect(find.text(tmdbNotice), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Replace key'), findsOneWidget);
    },
  );
}
