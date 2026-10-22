import 'package:drift/drift.dart';

import 'database.dart';
import 'tables.dart';

part 'cache_dao.g.dart';

/// Empty in R0 (registered so code generation runs once); the owning work
/// package writes its queries here with the Dart API.
@DriftAccessor(tables: [HttpCache])
class CacheDao extends DatabaseAccessor<AppDatabase> with _$CacheDaoMixin {
  CacheDao(super.attachedDatabase);
}
