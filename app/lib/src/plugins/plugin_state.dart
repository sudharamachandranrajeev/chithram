import 'dart:convert';
import 'dart:io';

import '../core/paths.dart';
import 'plugin_models.dart';

/// What the database tables have no column for: categories, the previous
/// version (for "Undo update"), an update waiting for approval, and per-repo
/// check state. One small JSON file next to the plugin files; losing it only
/// loses those extras.
class PluginExtra {
  PluginExtra({
    this.categories = const [],
    this.autoUpdatedAt,
    this.prev,
    this.pending,
  });

  List<String> categories;
  DateTime? autoUpdatedAt;
  PrevVersion? prev;
  PendingRecord? pending;

  factory PluginExtra.fromJson(Map<String, Object?> j) => PluginExtra(
        categories: [for (final c in (j['categories'] as List? ?? const [])) '$c'],
        autoUpdatedAt: DateTime.tryParse('${j['autoUpdatedAt']}'),
        prev: j['prev'] is Map ? PrevVersion.fromJson((j['prev'] as Map).cast()) : null,
        pending: j['pending'] is Map ? PendingRecord.fromJson((j['pending'] as Map).cast()) : null,
      );

  Map<String, Object?> toJson() => {
        'categories': categories,
        if (autoUpdatedAt != null) 'autoUpdatedAt': autoUpdatedAt!.toIso8601String(),
        if (prev != null) 'prev': prev!.toJson(),
        if (pending != null) 'pending': pending!.toJson(),
      };
}

/// The installed version that "Undo update" brings back (its file is `<id>.py.prev`).
class PrevVersion {
  PrevVersion({required this.version, required this.sha256, required this.name, required this.declaredUrl, required this.allowedHosts, required this.categories});

  final String? version;
  final String sha256, name, declaredUrl;
  final List<String> allowedHosts, categories;

  factory PrevVersion.fromJson(Map<String, Object?> j) => PrevVersion(
        version: j['version'] as String?,
        sha256: '${j['sha256']}',
        name: '${j['name']}',
        declaredUrl: '${j['declaredUrl']}',
        allowedHosts: [for (final h in (j['allowedHosts'] as List? ?? const [])) '$h'],
        categories: [for (final h in (j['categories'] as List? ?? const [])) '$h'],
      );

  Map<String, Object?> toJson() => {
        'version': version,
        'sha256': sha256,
        'name': name,
        'declaredUrl': declaredUrl,
        'allowedHosts': allowedHosts,
        'categories': categories,
      };
}

/// A verified update that needs the user's approval (its file is `<id>.py.pending`).
class PendingRecord {
  PendingRecord({
    required this.version,
    required this.sha256,
    required this.name,
    required this.declaredUrl,
    required this.allowedHosts,
    required this.categories,
    required this.differences,
  });

  final String version, sha256, name, declaredUrl;
  final List<String> allowedHosts, categories, differences;

  factory PendingRecord.fromJson(Map<String, Object?> j) => PendingRecord(
        version: '${j['version']}',
        sha256: '${j['sha256']}',
        name: '${j['name']}',
        declaredUrl: '${j['declaredUrl']}',
        allowedHosts: [for (final h in (j['allowedHosts'] as List? ?? const [])) '$h'],
        categories: [for (final h in (j['categories'] as List? ?? const [])) '$h'],
        differences: [for (final h in (j['differences'] as List? ?? const [])) '$h'],
      );

  Map<String, Object?> toJson() => {
        'version': version,
        'sha256': sha256,
        'name': name,
        'declaredUrl': declaredUrl,
        'allowedHosts': allowedHosts,
        'categories': categories,
        'differences': differences,
      };

  PendingUpdate get view => PendingUpdate(version: version, sha256: sha256, differences: differences);
}

/// A plugin a trusted repo lists that is not installed.
class RepoOffer {
  RepoOffer({required this.id, required this.name, required this.version, required this.file, required this.sha256, required this.hosts});

  final String id, name, version, file, sha256;
  final List<String> hosts;

  factory RepoOffer.fromJson(Map<String, Object?> j) => RepoOffer(
        id: '${j['id']}',
        name: '${j['name']}',
        version: '${j['version']}',
        file: '${j['file']}',
        sha256: '${j['sha256']}',
        hosts: [for (final h in (j['hosts'] as List? ?? const [])) '$h'],
      );

  Map<String, Object?> toJson() =>
      {'id': id, 'name': name, 'version': version, 'file': file, 'sha256': sha256, 'hosts': hosts};
}

class RepoExtra {
  RepoExtra({
    this.failures = 0,
    this.nextAttemptAt,
    this.keyChanged = false,
    this.lastError,
    this.offers = const [],
    this.initialIds = const [],
  });

  /// Failed checks in a row (drives the backoff).
  int failures;
  DateTime? nextAttemptAt;

  /// The repo is now signed by another key than the pinned one.
  bool keyChanged;
  String? lastError;

  /// "New" plugins: in the repo, not installed.
  List<RepoOffer> offers;

  /// Plugin ids the manifest listed when the repo was added. An offer that is
  /// not among them appeared later: it is "New".
  List<String> initialIds;

  factory RepoExtra.fromJson(Map<String, Object?> j) => RepoExtra(
        failures: (j['failures'] as num?)?.toInt() ?? 0,
        nextAttemptAt: DateTime.tryParse('${j['nextAttemptAt']}'),
        keyChanged: j['keyChanged'] == true,
        lastError: j['lastError'] as String?,
        offers: [for (final o in (j['offers'] as List? ?? const [])) RepoOffer.fromJson((o as Map).cast())],
        initialIds: [for (final i in (j['initialIds'] as List? ?? const [])) '$i'],
      );

  Map<String, Object?> toJson() => {
        'failures': failures,
        if (nextAttemptAt != null) 'nextAttemptAt': nextAttemptAt!.toIso8601String(),
        'keyChanged': keyChanged,
        if (lastError != null) 'lastError': lastError,
        'offers': [for (final o in offers) o.toJson()],
        'initialIds': initialIds,
      };
}

/// `plugins/state.json` and the plugin files beside it.
class PluginStore {
  PluginStore(this.dir);

  final Directory dir;
  final _plugins = <String, PluginExtra>{};
  final _repos = <String, RepoExtra>{};
  bool _loaded = false;

  File get _stateFile => File('${dir.path}/state.json');

  /// File names must stay inside [dir]: ids are `<hex>:<name>` / `single:<name>`.
  String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
  File file(String id) => File('${dir.path}/${_safe(id)}.py');
  File prevFile(String id) => File('${dir.path}/${_safe(id)}.py.prev');
  File pendingFile(String id) => File('${dir.path}/${_safe(id)}.py.pending');

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final j = jsonDecode(await _stateFile.readAsString()) as Map;
      for (final e in ((j['plugins'] as Map?) ?? const {}).entries) {
        _plugins['${e.key}'] = PluginExtra.fromJson((e.value as Map).cast());
      }
      for (final e in ((j['repos'] as Map?) ?? const {}).entries) {
        _repos['${e.key}'] = RepoExtra.fromJson((e.value as Map).cast());
      }
    } catch (_) {
      // Missing or damaged: start empty.
    }
  }

  PluginExtra plugin(String id) => _plugins.putIfAbsent(id, PluginExtra.new);
  RepoExtra repo(String id) => _repos.putIfAbsent(id, RepoExtra.new);

  Future<void> save() => writeFileAtomic(_stateFile, jsonEncode({
        'v': 1,
        'plugins': {for (final e in _plugins.entries) e.key: e.value.toJson()},
        'repos': {for (final e in _repos.entries) e.key: e.value.toJson()},
      }));

  Future<void> forgetPlugin(String id) async {
    _plugins.remove(id);
    for (final f in [file(id), prevFile(id), pendingFile(id)]) {
      try {
        await f.delete();
      } on FileSystemException {
        // Already gone.
      }
    }
    await save();
  }

  Future<void> forgetRepo(String id) async {
    _repos.remove(id);
    await save();
  }

  Future<void> deleteIfExists(File f) async {
    try {
      await f.delete();
    } on FileSystemException {
      // Already gone.
    }
  }
}
