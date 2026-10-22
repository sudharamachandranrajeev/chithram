import 'package:drift/drift.dart';

import 'database.dart';
import 'tables.dart';

part 'torznab_dao.g.dart';

/// Empty in R0 (registered so code generation runs once); the owning work
/// package writes its queries here with the Dart API.
@DriftAccessor(tables: [TorznabEndpoints])
class TorznabDao extends DatabaseAccessor<AppDatabase> with _$TorznabDaoMixin {
  TorznabDao(super.attachedDatabase);
}
