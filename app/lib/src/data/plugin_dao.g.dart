// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'plugin_dao.dart';

// ignore_for_file: type=lint
mixin _$PluginDaoMixin on DatabaseAccessor<AppDatabase> {
  $PluginReposTable get pluginRepos => attachedDatabase.pluginRepos;
  $PluginsTable get plugins => attachedDatabase.plugins;
  PluginDaoManager get managers => PluginDaoManager(this);
}

class PluginDaoManager {
  final _$PluginDaoMixin _db;
  PluginDaoManager(this._db);
  $$PluginReposTableTableManager get pluginRepos =>
      $$PluginReposTableTableManager(_db.attachedDatabase, _db.pluginRepos);
  $$PluginsTableTableManager get plugins =>
      $$PluginsTableTableManager(_db.attachedDatabase, _db.plugins);
}
