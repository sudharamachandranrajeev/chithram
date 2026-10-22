// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'runs_dao.dart';

// ignore_for_file: type=lint
mixin _$RunsDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProviderRunsTable get providerRuns => attachedDatabase.providerRuns;
  RunsDaoManager get managers => RunsDaoManager(this);
}

class RunsDaoManager {
  final _$RunsDaoMixin _db;
  RunsDaoManager(this._db);
  $$ProviderRunsTableTableManager get providerRuns =>
      $$ProviderRunsTableTableManager(_db.attachedDatabase, _db.providerRuns);
}
