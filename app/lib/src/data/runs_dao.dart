import 'package:drift/drift.dart';

import 'database.dart';
import 'tables.dart';

part 'runs_dao.g.dart';

/// How many runs per provider are kept.
const providerRunsKept = 20;

/// Provider health history. Queries use the Dart API only.
@DriftAccessor(tables: [ProviderRuns])
class RunsDao extends DatabaseAccessor<AppDatabase> with _$RunsDaoMixin {
  RunsDao(super.attachedDatabase);

  /// Adds a run and trims the provider to its newest [providerRunsKept].
  Future<void> record(ProviderRunsCompanion run) => transaction(() async {
        await into(providerRuns).insert(run);
        final id = run.providerId.value;
        final keep = await (select(providerRuns)
              ..where((r) => r.providerId.equals(id))
              ..orderBy([(r) => OrderingTerm.desc(r.at)])
              ..limit(providerRunsKept))
            .get();
        if (keep.length < providerRunsKept) return;
        final oldest = keep.last.at;
        await (delete(providerRuns)..where((r) => r.providerId.equals(id) & r.at.isSmallerThanValue(oldest))).go();
      });

  /// Newest first.
  Future<List<ProviderRunRow>> recent(String providerId, {int limit = providerRunsKept}) => (select(providerRuns)
        ..where((r) => r.providerId.equals(providerId))
        ..orderBy([(r) => OrderingTerm.desc(r.at)])
        ..limit(limit))
      .get();

  Future<void> clear(String providerId) => (delete(providerRuns)..where((r) => r.providerId.equals(providerId))).go();
}
