// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cache_dao.dart';

// ignore_for_file: type=lint
mixin _$CacheDaoMixin on DatabaseAccessor<AppDatabase> {
  $HttpCacheTable get httpCache => attachedDatabase.httpCache;
  CacheDaoManager get managers => CacheDaoManager(this);
}

class CacheDaoManager {
  final _$CacheDaoMixin _db;
  CacheDaoManager(this._db);
  $$HttpCacheTableTableManager get httpCache =>
      $$HttpCacheTableTableManager(_db.attachedDatabase, _db.httpCache);
}
