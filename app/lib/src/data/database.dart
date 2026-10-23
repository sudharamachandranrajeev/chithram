import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../core/paths.dart';
import 'cache_dao.dart';
import 'plugin_dao.dart';
import 'runs_dao.dart';
import 'tables.dart';
import 'torznab_dao.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [HttpCache, PluginRepos, Plugins, TorznabEndpoints, ProviderRuns],
  daos: [CacheDao, PluginDao, TorznabDao, RunsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// `chithram.sqlite` under the app support directory. Opens on the first
  /// query, on a background isolate: nothing before the first frame touches it.
  factory AppDatabase.open(AppPaths paths) => AppDatabase(
        driftDatabase(
          name: 'chithram',
          native: DriftNativeOptions(
            databasePath: () async => '${paths.support.path}/chithram.sqlite',
          ),
        ),
      );

  /// Opens (creates) the file at [path] on the calling isolate. For tests.
  factory AppDatabase.file(File path) => AppDatabase(NativeDatabase(path));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
