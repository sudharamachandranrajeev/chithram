import 'dart:typed_data';

import 'package:chithram/src/plugins/plugin_registry.dart';
import 'package:flutter/foundation.dart';
import 'package:nova_host/nova_host.dart';

/// A registry with no files or database: the UI tests drive the dialogs
/// against canned answers (the real logic is in registry_test.dart).
class FakeUiRegistry extends PluginRegistry {
  FakeUiRegistry() : super();

  final installed = ValueNotifier<List<InstalledPlugin>>([]);
  final repoViews = <PluginRepoView>[];
  final signal = ValueNotifier<int>(0);
  Object? previewError;
  Object? singleError;
  Object? inspectError;
  String? unavailable;
  final List<String> log = [];

  RepoPreview preview({bool firstUse = true}) => RepoPreview(
        repoId: 'r1',
        baseUrl: 'https://repo.example/plugins/',
        name: 'Test repo',
        keyId: '0102030405060708',
        firstUse: firstUse,
        publicKeyText: 'pub',
        entries: [
          PluginEntry(id: 'alpha', name: 'Alpha', file: 'alpha.py', sha256: 'a' * 64, version: '1.0', hosts: ['cdn.alpha.example'], adult: false),
          PluginEntry(id: 'beta', name: 'Beta', file: 'beta.py', sha256: 'b' * 64, version: '2.0', hosts: [], adult: false),
        ],
        hiddenAdult: 1,
        etag: null,
      );

  PluginCandidate candidate(String id, {String url = 'https://alpha.example', List<String>? hosts, bool signed = true, List<String> warnings = const []}) =>
      PluginCandidate(
        engineId: id,
        name: id[0].toUpperCase() + id.substring(1),
        version: signed ? '1.0' : null,
        source: Uint8List(0),
        sourceUrl: 'https://repo.example/plugins/$id.py',
        sha256: 'f' * 64,
        declaredUrl: url,
        categories: const ['all', 'movies'],
        allowedHosts: hosts ?? [registrableDomain(Uri.parse(url).host)],
        signed: signed,
        repoId: signed ? 'r1' : null,
        warnings: warnings,
      );

  InstalledPlugin make(String id,
          {bool signed = true,
          bool enabled = true,
          PluginHealth health = PluginHealth.untested,
          PendingUpdate? pending,
          DateTime? auto,
          bool canUndo = false,
          String version = '1.0'}) =>
      InstalledPlugin(
        id: '${signed ? 'r1' : 'single'}:$id',
        engineId: id,
        name: id[0].toUpperCase() + id.substring(1),
        sha256: 'f' * 64,
        sourceUrl: 'https://repo.example/plugins/$id.py',
        declaredUrl: 'https://$id.example',
        allowedHosts: ['$id.example'],
        signed: signed,
        enabled: enabled,
        installedAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 1),
        repoId: signed ? 'r1' : null,
        version: signed ? version : null,
        categories: const ['all', 'movies'],
        health: health,
        pending: pending,
        autoUpdatedAt: auto,
        canUndo: canUndo,
      );

  @override
  ValueListenable<List<InstalledPlugin>> get plugins => installed;
  @override
  ValueListenable<int> get repoChanges => signal;
  @override
  String? get unavailableReason => unavailable;
  @override
  bool get live => true;
  @override
  Future<void> ensureLoaded() async {}
  @override
  Future<void> start() async {}
  @override
  Future<List<PluginRepoView>> repos() async => repoViews;

  @override
  Future<RepoPreview> previewRepo(String input) async {
    log.add('preview $input');
    if (previewError != null) throw previewError!;
    return preview();
  }

  @override
  Future<PluginCandidate> inspectEntry(RepoPreview p, PluginEntry e) async {
    log.add('inspect ${e.id}');
    if (inspectError != null) throw inspectError!;
    return candidate(e.id, hosts: ['${e.id}.example', ...e.hosts]);
  }

  @override
  Future<void> installFromRepo(RepoPreview p, List<PluginCandidate> chosen) async {
    log.add('install ${chosen.map((c) => c.engineId).join(',')} firstUse=${p.firstUse}');
    installed.value = [...installed.value, for (final c in chosen) make(c.engineId)];
  }

  @override
  Future<PluginCandidate> inspectSingle(String input) async {
    log.add('single $input');
    if (singleError != null) throw singleError!;
    return candidate('solo', url: 'http://solo.example', hosts: ['img.solo.example', 'solo.example'], signed: false, warnings: [
      'Unsigned: this plugin is not from a verified repository. You are trusting its author.',
      'Its site uses plain http, so anyone on the network can read and change what it sends.',
    ]);
  }

  @override
  Future<void> installSingle(PluginCandidate c) async {
    log.add('install single ${c.engineId}');
    installed.value = [...installed.value, make(c.engineId, signed: false)];
  }

  void _replace(String id, InstalledPlugin Function(InstalledPlugin) f) =>
      installed.value = [for (final p in installed.value) p.id == id ? f(p) : p];

  @override
  Future<void> setEnabled(InstalledPlugin p, bool value) async => _replace(p.id, (x) => x.copyWith(enabled: value));

  @override
  Future<void> removePlugin(InstalledPlugin p) async => installed.value = [for (final x in installed.value) if (x.id != p.id) x];

  @override
  Future<void> removeRepo(String repoId) async {
    log.add('remove repo $repoId');
    repoViews.removeWhere((r) => r.id == repoId);
    installed.value = [for (final x in installed.value) if (x.repoId != repoId) x];
    signal.value++;
  }

  @override
  Future<PluginSearch> test(InstalledPlugin p, String query) async {
    log.add('test ${p.engineId} $query');
    _replace(p.id, (x) => x.copyWith(health: const PluginHealth(status: PluginHealthStatus.healthy, successRate: 1, medianMs: 40, runs: 1)));
    return PluginSearch(
      plugin: p,
      status: SearchStatus.ok,
      hits: [PluginHit(engineId: p.engineId, name: 'Fixture Film 1', link: 'magnet:?xt=urn:btih:${'a' * 40}', seeders: 9, sizeBytes: 1 << 30)],
      elapsed: const Duration(milliseconds: 40),
    );
  }

  @override
  Future<void> approveUpdate(InstalledPlugin p) async {
    log.add('approve ${p.engineId}');
    _replace(p.id, (x) => make(x.engineId, version: x.pending?.version ?? '1.1', canUndo: true));
  }

  @override
  Future<void> undoUpdate(InstalledPlugin p) async {
    log.add('undo ${p.engineId}');
    _replace(p.id, (x) => make(x.engineId));
  }

  @override
  Future<UpdateCheck> checkUnsigned(InstalledPlugin p) async {
    log.add('check ${p.engineId}');
    return UpdateCheck.upToDate;
  }
}
