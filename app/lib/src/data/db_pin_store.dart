import 'package:drift/drift.dart';
import 'package:nova_host/nova_host.dart';

import 'database.dart';

/// Plugin repo key pins (Trust On First Use) in `plugin_repos`, so they live
/// with the repo rows. A pin made before the repo row is complete creates the
/// row with an empty url and name; the plugin registry fills those in when it
/// saves the repo.
class DbPinStore implements KeyPinStore {
  DbPinStore(this._db, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _now;

  @override
  Future<PinnedKey?> get(String repoId) async {
    final row = await (_db.select(_db.pluginRepos)..where((r) => r.id.equals(repoId))).getSingleOrNull();
    if (row == null || row.keyId.isEmpty || row.pinnedPub.isEmpty) return null;
    return PinnedKey(row.keyId, row.pinnedPub);
  }

  @override
  Future<void> set(String repoId, PinnedKey key) async {
    await _db.into(_db.pluginRepos).insert(
          PluginReposCompanion.insert(
            id: repoId,
            url: '',
            name: '',
            keyId: key.keyIdHex,
            pinnedPub: key.publicKeyText,
            addedAt: _now(),
          ),
          onConflict: DoUpdate(
            (_) => PluginReposCompanion(keyId: Value(key.keyIdHex), pinnedPub: Value(key.publicKeyText)),
          ),
        );
  }
}
