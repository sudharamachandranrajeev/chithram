import 'package:drift/drift.dart';

import 'database.dart';
import 'tables.dart';

part 'plugin_dao.g.dart';

/// Plugin repositories and installed plugins. Queries use the Dart API only,
/// so no code generation is needed when one is added.
@DriftAccessor(tables: [PluginRepos, Plugins])
class PluginDao extends DatabaseAccessor<AppDatabase> with _$PluginDaoMixin {
  PluginDao(super.attachedDatabase);

  Future<List<PluginRepoRow>> repos() =>
      (select(pluginRepos)..orderBy([(r) => OrderingTerm.asc(r.addedAt)])).get();

  Future<PluginRepoRow?> repo(String id) =>
      (select(pluginRepos)..where((r) => r.id.equals(id))).getSingleOrNull();

  /// Fills in what [DbPinStore] left empty when it pinned the key, or inserts the row.
  Future<void> saveRepo({
    required String id,
    required String url,
    required String name,
    required String keyId,
    required String pinnedPub,
    required DateTime addedAt,
  }) =>
      into(pluginRepos).insert(
        PluginReposCompanion.insert(
          id: id,
          url: url,
          name: name,
          keyId: keyId,
          pinnedPub: pinnedPub,
          addedAt: addedAt,
        ),
        onConflict: DoUpdate((_) => PluginReposCompanion(url: Value(url), name: Value(name))),
      );

  /// After a check: the ETag the server sent (kept when null) and when we looked.
  Future<void> markRepoChecked(String id, DateTime at, {String? etag, bool clearEtag = false}) =>
      (update(pluginRepos)..where((r) => r.id.equals(id))).write(
        PluginReposCompanion(
          lastCheckedAt: Value(at),
          etag: clearEtag ? const Value(null) : (etag == null ? const Value.absent() : Value(etag)),
        ),
      );

  Future<void> setRepoName(String id, String name) =>
      (update(pluginRepos)..where((r) => r.id.equals(id))).write(PluginReposCompanion(name: Value(name)));

  /// The repo, its plugins and its key pin.
  Future<void> deleteRepo(String id) => transaction(() async {
        await (delete(plugins)..where((p) => p.repoId.equals(id))).go();
        await (delete(pluginRepos)..where((r) => r.id.equals(id))).go();
      });

  Future<List<PluginRow>> allPlugins() =>
      (select(plugins)..orderBy([(p) => OrderingTerm.asc(p.name)])).get();

  Future<PluginRow?> plugin(String id) =>
      (select(plugins)..where((p) => p.id.equals(id))).getSingleOrNull();

  Future<void> upsertPlugin(PluginsCompanion row) => into(plugins).insertOnConflictUpdate(row);

  Future<void> setEnabled(String id, bool enabled) =>
      (update(plugins)..where((p) => p.id.equals(id))).write(PluginsCompanion(enabled: Value(enabled)));

  /// The sha256 of an update that waits for approval (null: none).
  Future<void> setUpdateSha(String id, String? sha) =>
      (update(plugins)..where((p) => p.id.equals(id))).write(PluginsCompanion(updateSha: Value(sha)));

  Future<void> deletePlugin(String id) => (delete(plugins)..where((p) => p.id.equals(id))).go();
}
