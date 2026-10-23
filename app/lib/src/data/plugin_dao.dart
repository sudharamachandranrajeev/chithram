import 'package:drift/drift.dart';

import 'database.dart';
import 'tables.dart';

part 'plugin_dao.g.dart';

/// Empty in R0 (registered so code generation runs once); the owning work
/// package writes its queries here with the Dart API.
@DriftAccessor(tables: [PluginRepos, Plugins])
class PluginDao extends DatabaseAccessor<AppDatabase> with _$PluginDaoMixin {
  PluginDao(super.attachedDatabase);
}
