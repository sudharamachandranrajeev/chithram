import 'dart:convert';

import 'package:drift/drift.dart';

/// Schema v1 (0.3.0): HTTP cache, plugins, Torznab, provider health. Later
/// versions add tables through migrations (v2 Library, v3 IPTV and EPG, v4
/// YouTube subscriptions).

/// A JSON list of strings in a text column.
class StringListConverter extends TypeConverter<List<String>, String> {
  const StringListConverter();

  @override
  List<String> fromSql(String fromDb) =>
      [for (final e in jsonDecode(fromDb) as List) '$e'];

  @override
  String toSql(List<String> value) => jsonEncode(value);
}

/// A JSON object in a text column.
class JsonMapConverter extends TypeConverter<Map<String, Object?>, String> {
  const JsonMapConverter();

  @override
  Map<String, Object?> fromSql(String fromDb) =>
      (jsonDecode(fromDb) as Map).cast<String, Object?>();

  @override
  String toSql(Map<String, Object?> value) => jsonEncode(value);
}

/// Cached HTTP bodies (TMDB, gzip). The key never contains the API key.
/// Everything hard-expires after 180 days (the TMDB terms).
@DataClassName('HttpCacheRow')
@TableIndex(name: 'http_cache_hard_expiry', columns: {#hardExpiry})
class HttpCache extends Table {
  TextColumn get key => text()();
  IntColumn get parserVer => integer()();
  TextColumn get etag => text().nullable()();
  TextColumn get lastModified => text().nullable()();
  DateTimeColumn get fetchedAt => dateTime()();
  DateTimeColumn get softExpiry => dateTime()();
  DateTimeColumn get hardExpiry => dateTime()();

  /// gzip.
  BlobColumn get body => blob()();

  @override
  Set<Column> get primaryKey => {key};
}

@DataClassName('PluginRepoRow')
class PluginRepos extends Table {
  /// First 16 hex of sha256(url).
  TextColumn get id => text()();
  TextColumn get url => text()();
  TextColumn get name => text()();
  TextColumn get keyId => text()();
  TextColumn get pinnedPub => text()();
  TextColumn get etag => text().nullable()();
  DateTimeColumn get lastCheckedAt => dateTime().nullable()();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PluginRow')
class Plugins extends Table {
  /// `<repoId|single>:<engineId>`
  TextColumn get id => text()();
  TextColumn get repoId => text().nullable()();
  TextColumn get engineId => text()();
  TextColumn get name => text()();
  TextColumn get version => text().nullable()();
  TextColumn get sha256 => text()();
  TextColumn get sourceUrl => text()();
  TextColumn get declaredUrl => text()();
  TextColumn get allowedHosts => text().map(const StringListConverter())();
  BoolColumn get signed => boolean()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get installedAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get updateSha => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The API key lives in SecretStore, never here.
@DataClassName('TorznabEndpointRow')
class TorznabEndpoints extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get baseUrl => text()();
  TextColumn get caps => text().map(const JsonMapConverter()).nullable()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get capsAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The last 20 runs per provider (RunsDao trims).
@DataClassName('ProviderRunRow')
@TableIndex(name: 'provider_runs_by_provider', columns: {#providerId, #at})
class ProviderRuns extends Table {
  TextColumn get providerId => text()();
  DateTimeColumn get at => dateTime()();
  TextColumn get status => text()();
  TextColumn get reason => text().nullable()();
  IntColumn get ms => integer()();
  IntColumn get results => integer()();
  IntColumn get requests => integer()();
  TextColumn get blockedHosts => text().map(const StringListConverter())();
}
