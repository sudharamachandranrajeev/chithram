import 'package:drift/drift.dart';

import 'database.dart';
import 'tables.dart';

part 'cache_dao.g.dart';

/// Empty in R0 (registered so code generation runs once); the owning work
/// package writes its queries here with the Dart API.
@DriftAccessor(tables: [HttpCache])
class CacheDao extends DatabaseAccessor<AppDatabase> with _$CacheDaoMixin {
  CacheDao(super.attachedDatabase);

  Future<HttpCacheRow?> lookup(String key, DateTime now) async {
    await purgeExpired(now);
    return (select(httpCache)
          ..where((t) => t.key.equals(key) & t.parserVer.equals(1)))
        .getSingleOrNull();
  }

  Future<void> store(HttpCacheCompanion row) =>
      into(httpCache).insertOnConflictUpdate(row);

  Future<int> purgeExpired(DateTime now) => (delete(
    httpCache,
  )..where((t) => t.hardExpiry.isSmallerOrEqualValue(now))).go();

  Future<int> purgeTmdb() =>
      (delete(httpCache)..where((t) => t.key.like('tmdb:%'))).go();
}
