import 'package:drift/drift.dart';

import 'database.dart';
import 'tables.dart';

part 'torznab_dao.g.dart';

/// The user's Torznab endpoints. The API key is not here (SecretStore).
@DriftAccessor(tables: [TorznabEndpoints])
class TorznabDao extends DatabaseAccessor<AppDatabase> with _$TorznabDaoMixin {
  TorznabDao(super.attachedDatabase);

  Future<List<TorznabEndpointRow>> all() =>
      (select(torznabEndpoints)..orderBy([(t) => OrderingTerm.asc(t.name), (t) => OrderingTerm.asc(t.id)])).get();

  Future<void> upsert(TorznabEndpointRow row) => into(torznabEndpoints).insertOnConflictUpdate(row);

  Future<void> setEnabled(String id, bool enabled) => (update(
    torznabEndpoints,
  )..where((t) => t.id.equals(id))).write(TorznabEndpointsCompanion(enabled: Value(enabled)));

  Future<void> setCaps(String id, Map<String, Object?> caps, DateTime at) => (update(
    torznabEndpoints,
  )..where((t) => t.id.equals(id))).write(TorznabEndpointsCompanion(caps: Value(caps), capsAt: Value(at)));

  Future<void> remove(String id) => (delete(torznabEndpoints)..where((t) => t.id.equals(id))).go();
}
