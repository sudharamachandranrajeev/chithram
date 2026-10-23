// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'torznab_dao.dart';

// ignore_for_file: type=lint
mixin _$TorznabDaoMixin on DatabaseAccessor<AppDatabase> {
  $TorznabEndpointsTable get torznabEndpoints =>
      attachedDatabase.torznabEndpoints;
  TorznabDaoManager get managers => TorznabDaoManager(this);
}

class TorznabDaoManager {
  final _$TorznabDaoMixin _db;
  TorznabDaoManager(this._db);
  $$TorznabEndpointsTableTableManager get torznabEndpoints =>
      $$TorznabEndpointsTableTableManager(
        _db.attachedDatabase,
        _db.torznabEndpoints,
      );
}
