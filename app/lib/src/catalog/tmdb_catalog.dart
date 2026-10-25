import 'dart:async';

import 'package:drift/drift.dart';
import 'package:tmdb/tmdb.dart';

import '../core/secrets.dart';
import '../core/prefs.dart';
import '../data/cache_dao.dart';
import '../data/database.dart';
import 'catalog_repository.dart';
import 'catalog_worker.dart';

/// Database writes stay on the main isolate; HTTP and every parse use worker.
/// Creating the catalog performs no IO; its worker starts on first use.
class TmdbCatalog implements CatalogRepository {
  TmdbCatalog({
    this.worker,
    this.cache,
    this.secrets,
    this.language = 'en-US',
    this.region = 'US',
    this.clock,
    this.prefs,
  });
  final CatalogWorker? worker;
  final CacheDao? cache;
  final SecretStore? secrets;
  final String language, region;
  final Prefs? prefs;
  final DateTime Function()? clock;
  int _epoch = 0;
  bool _suspended = false;
  void _checkAvailable() {
    if (_suspended || (prefs != null && !prefs!.getBool('tmdb.configured'))) {
      throw const TmdbException('Metadata is not configured.');
    }
  }

  Future<void> suspend() async {
    _suspended = true;
    await invalidate();
  }

  void resume() {
    _suspended = false;
  }

  Future<void> _writes = Future.value();
  Future<void> invalidate() async {
    _epoch++;
    _searches.clear();
    final pending = _pending.values.toList();
    await Future.wait(
      pending.map((f) async {
        try {
          await f;
        } catch (_) {}
      }),
    );
    await _writes;
    await worker?.reset();
  }

  static const secretKey = 'tmdb.key';
  DateTime get _now => (clock ?? DateTime.now)().toUtc();
  final Map<String, Future<WorkerResult>> _pending = {};
  final Map<String, (DateTime, List<HomeTile>)> _searches = {};

  Map<String, String> get _query => {
    'language': prefs?.getString('tmdb.language') ?? language,
    'region': prefs?.getString('tmdb.region') ?? region,
  };
  Future<WorkerResult> request(
    String path, {
    String parser = 'raw',
    MediaKind? kind,
    Map<String, String> query = const {},
    bool list = false,
    String? etag,
    String? lastModified,
  }) async {
    _checkAvailable();
    final epoch = _epoch;
    final key = await secrets?.read(secretKey);
    if (epoch != _epoch) {
      throw const TmdbException('Metadata settings changed.');
    }
    if (key == null || worker == null) {
      throw const TmdbException('Add a metadata key in Settings.');
    }
    final parameters = {
      ..._query,
      ...query,
      if (parser == 'details')
        'append_to_response':
            '${kind == MediaKind.tv ? 'aggregate_credits' : 'credits'},videos,recommendations,external_ids',
      if (list) 'include_adult': 'false',
    };
    final id = TmdbClient.cacheKey(path, parameters);
    final pending = _pending;
    final existing = pending[id];
    if (existing != null) return existing;
    final work = worker!
        .fetch(
          key: key,
          path: path,
          query: parameters,
          parser: parser,
          kind: kind,
          list: list,
          etag: etag,
          lastModified: lastModified,
        )
        .then((result) {
          if (epoch != _epoch) {
            throw const TmdbException('Metadata settings changed.');
          }
          return result;
        });
    pending[id] = work;
    try {
      final result = await work;
      if (epoch != _epoch) {
        throw const TmdbException('Metadata settings changed.');
      }
      return result;
    } finally {
      pending.remove(id);
    }
  }

  Stream<Cached<T>> _cached<T>(
    String path,
    String parser,
    Duration ttl, {
    MediaKind? kind,
    Map<String, String> query = const {},
    bool list = false,
  }) async* {
    if (worker == null || cache == null) return;
    _checkAvailable();
    final epoch = _epoch;
    final parameters = {
      ..._query,
      ...query,
      if (list) 'include_adult': 'false',
      if (parser == 'details')
        'append_to_response':
            '${kind == MediaKind.tv ? 'aggregate_credits' : 'credits'},videos,recommendations,external_ids',
    };
    final id = TmdbClient.cacheKey(path, parameters);
    var row = await cache!.lookup(id, _now);
    if (row != null) {
      try {
        final value = await worker!.decode(row.body, parser, kind) as T;
        if (epoch != _epoch) return;
        final stale = !row.softExpiry.isAfter(_now);
        yield Cached(value, stale: stale);
        if (!stale) return;
      } catch (_) {
        row = null;
      }
    }
    final response = await request(
      path,
      query: query,
      list: list,
      parser: parser,
      kind: kind,
      etag: row?.etag,
      lastModified: row?.lastModified,
    );
    if (epoch != _epoch) return;
    final now = _now;
    if (response.status == 304 && row != null) {
      final write = cache!.store(
        row
            .toCompanion(true)
            .copyWith(fetchedAt: Value(now), softExpiry: Value(now.add(ttl))),
      );
      _writes = write.then<void>((_) {}, onError: (Object _) {});
      await write;
      final value = await worker!.decode(row.body, parser, kind) as T;
      if (epoch == _epoch) yield Cached(value);
    } else {
      final write = cache!.store(
        HttpCacheCompanion.insert(
          key: id,
          parserVer: 1,
          etag: Value(response.headers['etag']),
          lastModified: Value(response.headers['last-modified']),
          fetchedAt: now,
          softExpiry: now.add(ttl),
          hardExpiry: now.add(const Duration(days: 180)),
          body: response.body,
        ),
      );
      _writes = write.then<void>((_) {}, onError: (Object _) {});
      await write;
      if (epoch == _epoch) yield Cached(response.value as T);
    }
  }

  @override
  Stream<Cached<TitleDetails>> details(MediaKind k, int id) => _cached(
    '${k.name}/$id',
    'details',
    Duration(days: k == MediaKind.movie ? 7 : 1),
    kind: k,
  );

  @override
  Stream<Cached<SeasonDetails>> season(int showId, int season) =>
      _cached('tv/$showId/season/$season', 'season', const Duration(days: 1));

  @override
  Future<List<Genre>> genres(MediaKind k) async {
    if (worker == null) return const [];
    final values = await _cached<List<Genre>>(
      'genre/${k.name}/list',
      'genres',
      const Duration(days: 7),
    ).toList();
    return values.last.value;
  }

  @override
  Future<List<HomeTile>> discoverGenre(
    MediaKind k,
    int genreId, {
    int page = 1,
  }) async {
    if (worker == null) return const [];
    final values = await _cached<List<HomeTile>>(
      'discover/${k.name}',
      'tiles',
      const Duration(days: 1),
      kind: k,
      list: true,
      query: {'with_genres': '$genreId', 'page': '${page.clamp(1, 500)}'},
    ).toList();
    return values.last.value;
  }

  @override
  Future<List<HomeTile>> search(String q) async {
    if (worker == null || q.trim().isEmpty) return const [];
    _checkAvailable();
    final searches = _searches;
    searches.removeWhere((_, v) => !v.$1.isAfter(_now));
    final searchKey = TmdbClient.cacheKey('search/multi', {
      ..._query,
      'query': q.trim(),
    });
    final previous = searches[searchKey];
    if (previous != null) return previous.$2;
    final epoch = _epoch;
    final result =
        (await request(
              'search/multi',
              parser: 'tiles',
              list: true,
              query: {'query': q.trim()},
            )).value
            as List<HomeTile>;
    if (epoch != _epoch) {
      throw const TmdbException('Metadata settings changed.');
    }
    if (searches.length >= 100) searches.remove(searches.keys.first);
    searches[searchKey] = (_now.add(const Duration(minutes: 10)), result);
    return result;
  }

  @override
  void prefetchDetails(MediaKind k, int id) {
    unawaited(details(k, id).drain<void>().catchError((Object _) {}));
  }
}
