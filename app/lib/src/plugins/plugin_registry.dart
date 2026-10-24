import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:nova_host/nova_host.dart';

import '../core/paths.dart' show AppPaths;
import '../data/database.dart';
import '../data/db_pin_store.dart';
import '../data/plugin_dao.dart';
import '../data/runs_dao.dart';
import '../find/find_api.dart';
import 'backoff.dart';
import 'health.dart';
import 'plugin_fetch.dart';
import 'plugin_find_provider.dart';
import 'plugin_models.dart';
import 'plugin_runtime.dart';
import 'plugin_state.dart';

export 'plugin_models.dart';
export 'plugin_state.dart' show RepoOffer;

/// What a repository shows before the user trusts it.
class RepoPreview {
  RepoPreview({
    required this.repoId,
    required this.baseUrl,
    required this.name,
    required this.keyId,
    required this.firstUse,
    required this.publicKeyText,
    required this.entries,
    required this.hiddenAdult,
    required this.etag,
  });

  final String repoId;

  /// The folder holding `plugins.json`, with a trailing slash.
  final String baseUrl;
  final String name;

  /// The signing key's id; on [firstUse] the user is asked to trust it.
  final String keyId;
  final bool firstUse;
  final String publicKeyText;

  /// Adult entries are not listed.
  final List<PluginEntry> entries;
  final int hiddenAdult;
  final String? etag;

  Uri fileUrl(PluginEntry e) => Uri.parse('$baseUrl${e.file}');
}

/// A plugin that was downloaded, hash-checked and `describe`d, ready to install.
class PluginCandidate {
  PluginCandidate({
    required this.engineId,
    required this.name,
    required this.version,
    required this.source,
    required this.sourceUrl,
    required this.sha256,
    required this.declaredUrl,
    required this.categories,
    required this.allowedHosts,
    required this.signed,
    this.warnings = const [],
    this.repoId,
    this.differences = const [],
  });

  final String engineId, name, sourceUrl, sha256, declaredUrl;
  final String? version, repoId;
  final Uint8List source;
  final List<String> categories;

  /// The registrable domain of [declaredUrl] plus manifest or header hosts: what the user approves.
  final List<String> allowedHosts;
  final bool signed;

  /// Shown on the warning screen (unsigned, plain http).
  final List<String> warnings;

  /// For an update that needs approval: what differs.
  final List<String> differences;

  String get id => '${repoId ?? 'single'}:$engineId';

  /// The domain the user is asked about.
  String get declaredDomain => registrableDomain(Uri.tryParse(declaredUrl)?.host ?? '');
}

/// A repository as the settings page lists it.
class PluginRepoView {
  PluginRepoView({
    required this.id,
    required this.url,
    required this.name,
    required this.keyId,
    required this.lastCheckedAt,
    required this.keyChanged,
    required this.offers,
    required this.initialIds,
    this.lastError,
  });

  final String id, url, name, keyId;
  final DateTime? lastCheckedAt;
  final bool keyChanged;
  final List<RepoOffer> offers;
  final List<String> initialIds;
  final String? lastError;

  bool isNew(RepoOffer o) => !initialIds.contains(o.id);
}

enum UpdateCheck { upToDate, needsApproval, applied, failed }

/// Search plugins (nova3 format): install from signed repos or single `.py`
/// URLs, pinned domain allowlists, health, and automatic updates from signed
/// repos. Ships none; the user adds everything.
///
/// For Torrent Home and Find:
///  - [enabled] lists the plugins to query;
///  - [search] runs one (hash-checked, sandboxed, concurrency-limited, health
///    recorded) and returns typed [PluginHit]s;
///  - [fetchTorrent] downloads a result's .torrent through the plugin's own
///    allowlisted channel.
///
/// `PluginRegistry()` with no arguments is inert (no plugins, nothing to load).
class PluginRegistry implements FindProviderSource {
  PluginRegistry()
      : _db = null,
        _runner = null,
        _fetcher = null,
        _store = null,
        _now = DateTime.now,
        _backgroundDelay = Duration.zero,
        _backoff = Backoff(),
        concurrencyProbe = null,
        _gate = _Gate(1);

  PluginRegistry.open({
    required AppDatabase db,
    required AppPaths paths,
    required PluginRunner runner,
    PluginFetcher? fetcher,
    DateTime Function()? now,
    int concurrency = 2,
    this.concurrencyProbe,
    Duration backgroundDelay = const Duration(seconds: 30),
    Backoff? backoff,
  })  : _db = db,
        _runner = runner,
        _fetcher = fetcher ?? HttpPluginFetcher(),
        _store = PluginStore(Directory('${paths.support.path}/plugins')),
        _now = now ?? DateTime.now,
        _backgroundDelay = backgroundDelay,
        _backoff = backoff ?? Backoff(),
        _gate = _Gate(concurrency);

  /// Called by [start] (after the first frame) to size the plugin gate from
  /// the device's RAM; see [pluginConcurrency].
  final Future<int> Function()? concurrencyProbe;

  static const maxPluginBytes = 256 * 1024;
  static const _checkEvery = Duration(hours: 24);

  final AppDatabase? _db;
  final PluginRunner? _runner;
  final PluginFetcher? _fetcher;
  final PluginStore? _store;
  final DateTime Function() _now;
  final Duration _backgroundDelay;
  final Backoff _backoff;
  final _Gate _gate;

  final _plugins = ValueNotifier<List<InstalledPlugin>>(const []);
  final _providers = ValueNotifier<List<FindProvider>>(const []);
  final _repoSignal = ValueNotifier<int>(0);
  Future<void>? _loading;
  Timer? _timer;
  bool _disposed = false;

  /// Installed plugins, with health, for the settings page.
  ValueListenable<List<InstalledPlugin>> get plugins => _plugins;

  /// Changes whenever a repository's state does (checks, offers).
  ValueListenable<int> get repoChanges => _repoSignal;

  @override
  ValueListenable<List<FindProvider>> get providers => _providers;

  bool get live => _db != null;

  /// Why plugins cannot run on this device (null: they can, or not known yet).
  String? get unavailableReason => _runner?.unavailableReason;

  PluginDao get _plugDao => _db!.pluginDao;
  RunsDao get _runsDao => _db!.runsDao;

  // -- loading ---------------------------------------------------------------

  /// Loads the installed plugins, then arms the background repo check. Call
  /// after the first frame.
  Future<void> start() async {
    await ensureLoaded();
    if (!live || _disposed) return;
    final probe = concurrencyProbe;
    if (probe != null) {
      try {
        _gate.limit = await probe();
      } catch (_) {
        // Keep the default.
      }
    }
    _timer?.cancel();
    _timer = Timer(_backgroundDelay, () => unawaited(_background()));
  }

  Future<void> _background() async {
    if (_disposed) return;
    await checkDue();
    if (_disposed) return;
    // A long-running TV session still checks about once a day.
    _timer = Timer(const Duration(hours: 6), () => unawaited(_background()));
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    if (!live) return;
    await _store!.load();
    await _refresh();
  }

  Future<void> _refresh() async {
    final rows = await _plugDao.allPlugins();
    final out = <InstalledPlugin>[];
    for (final r in rows) {
      out.add(await _build(r));
    }
    if (_disposed) return;
    _plugins.value = out;
    final old = {for (final p in _providers.value.whereType<PluginFindProvider>()) p.plugin.id: p};
    _providers.value = [
      for (final p in out.where((p) => p.enabled)) old[p.id]?.withPlugin(p) ?? PluginFindProvider(this, p),
    ];
    _repoSignal.value++;
  }

  Future<InstalledPlugin> _build(PluginRow r) async {
    final x = _store!.plugin(r.id);
    final repoKeyChanged = r.repoId != null && _store.repo(r.repoId!).keyChanged;
    final runs = await _runsDao.recent(r.id);
    final health = classifyHealth(runs, unavailable: unavailableReason != null, keyChanged: repoKeyChanged);
    return InstalledPlugin(
      id: r.id,
      engineId: r.engineId,
      name: r.name,
      sha256: r.sha256,
      sourceUrl: r.sourceUrl,
      declaredUrl: r.declaredUrl,
      allowedHosts: r.allowedHosts,
      signed: r.signed,
      enabled: r.enabled,
      installedAt: r.installedAt,
      updatedAt: r.updatedAt,
      repoId: r.repoId,
      version: r.version,
      categories: x.categories,
      autoUpdatedAt: x.autoUpdatedAt,
      pending: x.pending?.view,
      canUndo: x.prev != null && _store.prevFile(r.id).existsSync(),
      health: health,
    );
  }

  /// The plugins to query: enabled, and not Blocked or Unavailable.
  Future<List<InstalledPlugin>> enabled() async {
    await ensureLoaded();
    return [
      for (final p in _plugins.value)
        if (p.enabled && p.health.status != PluginHealthStatus.blocked && p.health.status != PluginHealthStatus.unavailable) p,
    ];
  }

  Future<List<PluginRepoView>> repos() async {
    await ensureLoaded();
    if (!live) return const [];
    return [
      for (final r in await _plugDao.repos())
        if (r.url.isNotEmpty)
          PluginRepoView(
            id: r.id,
            url: r.url,
            name: r.name.isEmpty ? Uri.tryParse(r.url)?.host ?? r.url : r.name,
            keyId: r.keyId,
            lastCheckedAt: r.lastCheckedAt,
            keyChanged: _store!.repo(r.id).keyChanged,
            offers: _store.repo(r.id).offers,
            initialIds: _store.repo(r.id).initialIds,
            lastError: _store.repo(r.id).lastError,
          ),
    ];
  }

  // -- running ---------------------------------------------------------------

  /// The engine for [p]: its file, checked against the database hash, with the
  /// approved hosts pinned. Throws [StateError] `hash-mismatch` when the file
  /// is missing or changed.
  Future<NovaEngine> _engine(InstalledPlugin p) async {
    final f = _store!.file(p.id);
    final Uint8List bytes;
    try {
      bytes = await f.readAsBytes();
    } on FileSystemException {
      throw StateError('hash-mismatch');
    }
    if (crypto.sha256.convert(bytes).toString() != p.sha256) throw StateError('hash-mismatch');
    return NovaEngine(
      id: p.engineId,
      source: utf8.decode(bytes, allowMalformed: true),
      pinnedHosts: p.allowedHosts,
    );
  }

  /// Runs [p] for [what] in category [cat] (`all`, `movies`, `tv`, ...; pass
  /// `p.categoryFor('movies')`). Never throws: failures come back as a
  /// [PluginSearch] with `ok == false` and a short `reason`. Every run is
  /// recorded for health.
  Future<PluginSearch> search(InstalledPlugin p, String what, {String cat = 'all'}) async {
    if (!live) {
      return PluginSearch(plugin: p, status: SearchStatus.error, hits: const [], elapsed: Duration.zero, reason: 'unavailable');
    }
    return _gate.run(() async {
      final sw = Stopwatch()..start();
      SearchOutcome? o;
      String? reason;
      try {
        o = await _runner!.search(await _engine(p), what, cat: cat);
      } on StateError catch (e) {
        reason = e.message;
      } on PluginsUnavailable catch (e) {
        await _refresh();
        return PluginSearch(plugin: p, status: SearchStatus.error, hits: const [], elapsed: sw.elapsed, reason: 'unavailable: ${e.reason}');
      } catch (e) {
        reason = 'error: $e';
      }
      sw.stop();
      final blocked = o == null ? const <String>[] : _blockedHosts(o.brokerLog);
      final status = o?.status ?? SearchStatus.error;
      final why = o?.reason ?? reason;
      await _runsDao.record(ProviderRunsCompanion.insert(
        providerId: p.id,
        at: _now(),
        status: status.name,
        reason: Value(why),
        ms: sw.elapsedMilliseconds,
        results: o?.results.length ?? 0,
        requests: o?.requests ?? 0,
        blockedHosts: blocked,
      ));
      await _refreshOne(p.id);
      return PluginSearch(
        plugin: _plugins.value.firstWhere((x) => x.id == p.id, orElse: () => p),
        status: status,
        hits: o?.hits ?? const [],
        elapsed: sw.elapsed,
        reason: why,
        blockedHosts: blocked,
      );
    });
  }

  static List<String> _blockedHosts(List<String> log) {
    final out = <String>{};
    for (final l in log) {
      final m = RegExp(r'^DENIED host (\S+) not in allowlist').firstMatch(l);
      if (m != null) out.add(m.group(1)!.toLowerCase());
    }
    return out.toList()..sort();
  }

  Future<void> _refreshOne(String id) async {
    final row = await _plugDao.plugin(id);
    if (row == null || _disposed) return;
    final built = await _build(row);
    _plugins.value = [for (final p in _plugins.value) p.id == id ? built : p];
    _repoSignal.value++;
  }

  /// The .torrent bytes behind [url] (a result's `link`), at most 2 MiB.
  Future<Uint8List> fetchTorrent(InstalledPlugin p, String url) => _gate.run(() async {
        try {
          return await _runner!.downloadTorrent(await _engine(p), url);
        } on StateError catch (e) {
          throw NovaDownloadError(e.message);
        }
      });

  // -- install: repository ------------------------------------------------------

  Uri _manifestUri(String input) {
    var u = Uri.tryParse(input.trim());
    if (u == null || u.host.isEmpty) throw PluginInstallError(InstallErrorKind.malformed, 'That is not a web address');
    u = u.replace(fragment: '', query: '');
    final segs = [...u.pathSegments];
    if (segs.isNotEmpty && segs.last == 'plugins.json') segs.removeLast();
    if (segs.isNotEmpty && segs.last.isEmpty) segs.removeLast();
    return u.replace(pathSegments: [...segs, 'plugins.json']);
  }

  String _repoId(Uri manifest) => crypto.sha256.convert(utf8.encode(manifest.toString())).toString().substring(0, 16);

  static String _hash(List<int> bytes) => crypto.sha256.convert(bytes).toString();

  /// Fetches and verifies the repository at [input] (its folder, or the
  /// `plugins.json` URL) without trusting it yet: the key is pinned only when
  /// [installFromRepo] runs.
  Future<RepoPreview> previewRepo(String input) async {
    await ensureLoaded();
    final manifestUri = _manifestUri(input);
    final repoId = _repoId(manifestUri);
    final base = manifestUri.resolve('.').toString();
    final fetcher = _fetcher!;

    Future<Uint8List> need(String name, int cap) async {
      final r = await fetcher.get(manifestUri.resolve(name), maxBytes: cap);
      if (r.status == 404) {
        throw PluginInstallError(InstallErrorKind.malformed,
            name == 'plugins.json' ? 'There is no plugin list at this address' : 'The repository has no $name');
      }
      if (!r.ok) throw PluginInstallError(InstallErrorKind.fetch, 'The server answered ${r.status} for $name');
      return r.body;
    }

    final manifest = await need('plugins.json', 1024 * 1024);
    final sig = utf8.decode(await need('plugins.json.minisig', 4096), allowMalformed: true);
    final pinStore = DbPinStore(_db!);
    final pinned = await pinStore.get(repoId);
    String? pub;
    if (pinned == null) pub = utf8.decode(await need('repo.pub', 1024), allowMalformed: true);

    final client = PluginRepoClient(pinned == null ? MemoryPinStore() : pinStore);
    final VerifiedRepo v;
    try {
      v = await client.verify(repoId: repoId, manifestBytes: manifest, signatureText: sig, publicKeyText: pub);
    } on RepoError catch (e) {
      throw _fromRepoError(e);
    }
    return RepoPreview(
      repoId: repoId,
      baseUrl: base,
      name: v.manifest.name.isEmpty ? manifestUri.host : v.manifest.name,
      keyId: v.keyId,
      firstUse: pinned == null,
      publicKeyText: pub ?? pinned!.publicKeyText,
      entries: [for (final e in v.manifest.plugins) if (!e.adult) e],
      hiddenAdult: v.manifest.plugins.where((e) => e.adult).length,
      etag: null,
    );
  }

  PluginInstallError _fromRepoError(RepoError e) => switch (e.kind) {
        RepoErrorKind.badSignature =>
          PluginInstallError(InstallErrorKind.badSignature, 'The signature does not match this repository. It was not added.'),
        RepoErrorKind.keyChanged => PluginInstallError(InstallErrorKind.keyChanged,
            'This repository is now signed by a different key than the one you trusted. Nothing was changed.'),
        RepoErrorKind.hashMismatch =>
          PluginInstallError(InstallErrorKind.hashMismatch, 'A plugin file does not match the signed list. It was not installed.'),
        RepoErrorKind.malformed => PluginInstallError(InstallErrorKind.malformed, 'The repository list is not valid: ${e.message}'),
      };

  /// Downloads [entry], checks its sha256 against the signed list, and
  /// `describe`s it in the sandbox.
  Future<PluginCandidate> inspectEntry(RepoPreview preview, PluginEntry entry) async {
    final r = await _fetcher!.get(preview.fileUrl(entry), maxBytes: maxPluginBytes);
    if (!r.ok) throw PluginInstallError(InstallErrorKind.fetch, '${entry.file}: the server answered ${r.status}');
    final NovaEngine engine;
    try {
      engine = PluginRepoClient(MemoryPinStore()).engineFor(entry, r.body);
    } on RepoError catch (e) {
      throw _fromRepoError(e);
    } on FormatException {
      throw PluginInstallError(InstallErrorKind.malformed, '${entry.file} is not UTF-8 text');
    }
    final d = await _describe(engine);
    return PluginCandidate(
      engineId: entry.id,
      name: d.name?.isNotEmpty == true ? d.name! : entry.name,
      version: entry.version.isEmpty ? null : entry.version,
      source: r.body,
      sourceUrl: preview.fileUrl(entry).toString(),
      sha256: entry.sha256,
      declaredUrl: d.url!,
      categories: d.categories,
      allowedHosts: _allowed(d.url!, entry.hosts),
      signed: true,
      repoId: preview.repoId,
    );
  }

  Future<DescribeOutcome> _describe(NovaEngine engine) async {
    final DescribeOutcome d;
    try {
      d = await _runner!.describe(engine);
    } on PluginsUnavailable catch (e) {
      throw PluginInstallError(InstallErrorKind.unavailable, 'Plugins cannot run on this device: ${e.reason}');
    }
    if (!d.ok) {
      throw PluginInstallError(InstallErrorKind.describeFailed, '${engine.id} could not be loaded: ${d.reason ?? 'unknown error'}');
    }
    final host = Uri.tryParse(d.url!)?.host ?? '';
    if (host.isEmpty) {
      throw PluginInstallError(InstallErrorKind.describeFailed, '${engine.id} does not declare a web address');
    }
    return d;
  }

  List<String> _allowed(String declaredUrl, Iterable<String> extra) {
    final out = <String>{registrableDomain(Uri.parse(declaredUrl).host)};
    for (final h in extra) {
      final t = h.trim().toLowerCase();
      if (t.isNotEmpty) out.add(t);
    }
    return out.toList()..sort();
  }

  /// Pins the key (on first use), saves the repository, and installs [chosen].
  Future<void> installFromRepo(RepoPreview preview, List<PluginCandidate> chosen) async {
    await ensureLoaded();
    final dao = _plugDao;
    if (preview.firstUse) {
      await DbPinStore(_db!).set(preview.repoId, PinnedKey(preview.keyId, preview.publicKeyText));
    }
    final existing = await dao.repo(preview.repoId);
    await dao.saveRepo(
      id: preview.repoId,
      url: '${preview.baseUrl}plugins.json',
      name: preview.name,
      keyId: preview.keyId,
      pinnedPub: preview.publicKeyText,
      addedAt: existing?.addedAt ?? _now(),
    );
    final rx = _store!.repo(preview.repoId);
    if (existing == null || rx.initialIds.isEmpty) rx.initialIds = [for (final e in preview.entries) e.id];
    rx.keyChanged = false;
    for (final c in chosen) {
      await _install(c);
    }
    _setOffers(preview.repoId, preview.entries);
    await _store.save();
    await _refresh();
  }

  void _setOffers(String repoId, Iterable<PluginEntry> entries) {
    final installed = {for (final p in _plugins.value.where((p) => p.repoId == repoId)) p.engineId};
    _store!.repo(repoId).offers = [
      for (final e in entries)
        if (!e.adult && !installed.contains(e.id))
          RepoOffer(id: e.id, name: e.name, version: e.version, file: e.file, sha256: e.sha256, hosts: e.hosts),
    ];
  }

  Future<void> _install(PluginCandidate c) async {
    await _writeBytes(_store!.file(c.id), c.source);
    final now = _now();
    final prev = await _plugDao.plugin(c.id);
    await _plugDao.upsertPlugin(PluginsCompanion.insert(
      id: c.id,
      engineId: c.engineId,
      name: c.name,
      sha256: c.sha256,
      sourceUrl: c.sourceUrl,
      declaredUrl: c.declaredUrl,
      allowedHosts: c.allowedHosts,
      signed: c.signed,
      installedAt: prev?.installedAt ?? now,
      updatedAt: now,
      repoId: Value(c.repoId),
      version: Value(c.version),
      enabled: Value(prev?.enabled ?? true),
    ));
    _store.plugin(c.id)
      ..categories = c.categories
      ..prev = null
      ..pending = null
      ..autoUpdatedAt = null;
    await _store.deleteIfExists(_store.prevFile(c.id));
    await _store.deleteIfExists(_store.pendingFile(c.id));
  }

  static Future<void> _writeBytes(File f, Uint8List bytes) async {
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
  }

  /// Installs plugins the repo offers as "New" (or any not installed), after the user picked them.
  Future<List<PluginCandidate>> inspectOffers(String repoId, List<RepoOffer> offers) async {
    final row = await _plugDao.repo(repoId);
    if (row == null) throw PluginInstallError(InstallErrorKind.malformed, 'That repository is no longer added');
    final base = Uri.parse(row.url).resolve('.').toString();
    final preview = RepoPreview(
      repoId: repoId,
      baseUrl: base,
      name: row.name,
      keyId: row.keyId,
      firstUse: false,
      publicKeyText: row.pinnedPub,
      entries: const [],
      hiddenAdult: 0,
      etag: null,
    );
    return [
      for (final o in offers)
        await inspectEntry(
          preview,
          PluginEntry(id: o.id, name: o.name, file: o.file, sha256: o.sha256, version: o.version, hosts: o.hosts, adult: false),
        ),
    ];
  }

  Future<void> installOffers(String repoId, List<PluginCandidate> chosen) async {
    await ensureLoaded();
    for (final c in chosen) {
      await _install(c);
    }
    final x = _store!.repo(repoId);
    x.offers = [for (final o in x.offers) if (!chosen.any((c) => c.engineId == o.id)) o];
    await _store.save();
    await _refresh();
  }

  // -- install: single .py -------------------------------------------------------

  static bool _privateHost(String host) {
    final h = host.toLowerCase();
    if (isIpLiteral(h) || h == 'localhost' || !h.contains('.')) return true;
    return h.endsWith('.local') || h.endsWith('.internal') || h.endsWith('.lan') || h.endsWith('.home.arpa');
  }

  /// Downloads a single plugin file and `describe`s it. Nothing is installed.
  Future<PluginCandidate> inspectSingle(String input) async {
    await ensureLoaded();
    final uri = Uri.tryParse(input.trim());
    if (uri == null || uri.host.isEmpty || !uri.path.toLowerCase().endsWith('.py')) {
      throw PluginInstallError(InstallErrorKind.malformed, 'That is not a link to a .py plugin file');
    }
    final r = await _fetcher!.get(uri, maxBytes: maxPluginBytes);
    if (!r.ok) throw PluginInstallError(InstallErrorKind.fetch, 'The server answered ${r.status}');
    return _inspectSingleBytes(uri, r.body);
  }

  Future<PluginCandidate> _inspectSingleBytes(Uri uri, Uint8List bytes) async {
    final String source;
    try {
      source = utf8.decode(bytes);
    } on FormatException {
      throw PluginInstallError(InstallErrorKind.malformed, 'The file is not UTF-8 text');
    }
    final UnsignedPlugin u;
    try {
      u = UnsignedPlugin.fromSource(uri.pathSegments.last, source);
    } on RepoError {
      throw PluginInstallError(InstallErrorKind.malformed, '"${uri.pathSegments.last}" is not a valid plugin file name');
    }
    if (u.engine.adult) {
      throw PluginInstallError(InstallErrorKind.adult, 'Adult plugins are not supported in this version');
    }
    final d = await _describe(u.engine);
    final declared = Uri.parse(d.url!);
    if (_privateHost(declared.host)) {
      throw PluginInstallError(InstallErrorKind.privateOrIp,
          'The plugin names ${declared.host}, a private or numeric address. Chithram only allows public sites.');
    }
    return PluginCandidate(
      engineId: u.engine.id,
      name: d.name?.isNotEmpty == true ? d.name! : u.engine.id,
      version: null,
      source: bytes,
      sourceUrl: uri.toString(),
      sha256: _hash(bytes),
      declaredUrl: d.url!,
      categories: d.categories,
      allowedHosts: _allowed(d.url!, u.engine.hosts),
      signed: false,
      warnings: [
        'Unsigned: this plugin is not from a verified repository. You are trusting its author.',
        if (declared.scheme == 'http')
          'Its site uses plain http, so anyone on the network can read and change what it sends.',
      ],
    );
  }

  Future<void> installSingle(PluginCandidate c) async {
    await ensureLoaded();
    await _install(c);
    await _store!.save();
    await _refresh();
  }

  // -- enable, remove, test ------------------------------------------------------

  Future<void> setEnabled(InstalledPlugin p, bool value) async {
    await _plugDao.setEnabled(p.id, value);
    await _refresh();
  }

  Future<void> removePlugin(InstalledPlugin p) async {
    await _plugDao.deletePlugin(p.id);
    await _runsDao.clear(p.id);
    await _store!.forgetPlugin(p.id);
    await _refresh(); // a removed repo plugin shows as offered again after the next check
  }

  /// Removes the repository, its plugins and its key pin.
  Future<void> removeRepo(String repoId) async {
    final mine = _plugins.value.where((p) => p.repoId == repoId).toList();
    for (final p in mine) {
      await _runsDao.clear(p.id);
      await _store!.forgetPlugin(p.id);
    }
    await _plugDao.deleteRepo(repoId); // plugins, row and pin
    await _store!.forgetRepo(repoId);
    await _refresh();
  }

  // -- updates -------------------------------------------------------------------

  /// Checks every repository that is due: at most once per 24 h, one request
  /// at a time, with backoff after failures. Safe to call whenever.
  Future<void> checkDue() async {
    if (!live) return;
    await ensureLoaded();
    final gap = MinGap(const Duration(seconds: 1), now: _now);
    for (final r in await _plugDao.repos()) {
      if (r.url.isEmpty || _disposed) continue;
      final x = _store!.repo(r.id);
      final now = _now();
      final last = r.lastCheckedAt;
      if (last != null && now.difference(last) < _checkEvery) continue;
      if (x.nextAttemptAt != null && now.isBefore(x.nextAttemptAt!)) continue;
      final wait = gap.take();
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      await checkRepo(r.id);
    }
  }

  /// Checks one repository now (ETag aware). Applies updates that pass every
  /// automatic check; others wait for approval. Never throws.
  Future<void> checkRepo(String repoId, {bool force = false}) async {
    await ensureLoaded();
    final row = await _plugDao.repo(repoId);
    if (row == null || row.url.isEmpty) return;
    final x = _store!.repo(repoId);
    final manifestUri = Uri.parse(row.url);
    try {
      final r = await _fetcher!.get(manifestUri, maxBytes: 1024 * 1024, etag: force ? null : row.etag);
      if (r.notModified) {
        await _plugDao.markRepoChecked(repoId, _now());
        x
          ..failures = 0
          ..lastError = null
          ..nextAttemptAt = null;
        await _store.save();
        _repoSignal.value++;
        return;
      }
      if (!r.ok) {
        _failed(x, 'The server answered ${r.status}', retryAfter: r.retryAfter);
        await _store.save();
        _repoSignal.value++;
        return;
      }
      final sigRes = await _fetcher.get(manifestUri.resolve('plugins.json.minisig'), maxBytes: 4096);
      if (!sigRes.ok) {
        _failed(x, 'The signature file is missing (${sigRes.status})', retryAfter: sigRes.retryAfter);
        await _store.save();
        return;
      }
      final VerifiedRepo v;
      try {
        v = await PluginRepoClient(DbPinStore(_db!)).verify(
          repoId: repoId,
          manifestBytes: r.body,
          signatureText: utf8.decode(sigRes.body, allowMalformed: true),
        );
      } on RepoError catch (e) {
        if (e.kind == RepoErrorKind.keyChanged) {
          x
            ..keyChanged = true
            ..lastError = 'Signed by a different key than the one you trusted';
        } else {
          x.lastError = 'Update check refused: ${e.kind == RepoErrorKind.badSignature ? 'bad signature' : e.message}';
        }
        // A bad answer is not a network failure: look again tomorrow, not sooner.
        await _plugDao.markRepoChecked(repoId, _now());
        await _store.save();
        await _refresh();
        return;
      }
      x
        ..keyChanged = false
        ..failures = 0
        ..lastError = null
        ..nextAttemptAt = null;
      await _plugDao.markRepoChecked(repoId, _now(), etag: r.etag, clearEtag: r.etag == null);
      final base = manifestUri.resolve('.').toString();
      final byId = {for (final e in v.manifest.plugins) e.id: e};
      for (final p in _plugins.value.where((p) => p.repoId == repoId)) {
        final entry = byId[p.engineId];
        if (entry == null || entry.adult) continue;
        if (entry.sha256 == p.sha256) {
          if (p.pending != null) await _dropPending(p.id);
          continue;
        }
        if (p.pending?.sha256 == entry.sha256) continue;
        try {
          await _considerRepoUpdate(p, entry, Uri.parse('$base${entry.file}'));
        } catch (_) {
          // One bad plugin must not stop the others; it stays on its version.
        }
      }
      _setOffers(repoId, v.manifest.plugins);
      await _store.save();
      await _refresh();
    } on PluginInstallError catch (e) {
      _failed(x, e.message);
      await _store.save();
      _repoSignal.value++;
    } catch (e) {
      _failed(x, 'Check failed');
      await _store.save();
      _repoSignal.value++;
    }
  }

  void _failed(RepoExtra x, String why, {Duration? retryAfter}) {
    x
      ..failures += 1
      ..lastError = why
      ..nextAttemptAt = _now().add(_backoff.delay(x.failures, retryAfter: retryAfter));
  }

  Future<void> _dropPending(String id) async {
    _store!.plugin(id).pending = null;
    await _store.deleteIfExists(_store.pendingFile(id));
    await _plugDao.setUpdateSha(id, null);
  }

  /// Verifies a repo plugin's new version and applies it when every automatic
  /// condition holds; otherwise parks it for approval.
  Future<void> _considerRepoUpdate(InstalledPlugin p, PluginEntry entry, Uri file) async {
    final r = await _fetcher!.get(file, maxBytes: maxPluginBytes);
    if (!r.ok) return;
    final NovaEngine engine;
    try {
      engine = PluginRepoClient(MemoryPinStore()).engineFor(entry, r.body); // sha256 vs the signed list
    } on RepoError {
      return;
    }
    final DescribeOutcome d;
    try {
      d = await _describe(engine);
    } on PluginInstallError {
      return;
    }
    final newAllowed = _allowed(d.url!, entry.hosts);
    final cover = HostAllowlist(p.allowedHosts);
    final within = newAllowed.every((h) => p.allowedHosts.map((e) => e.toLowerCase()).contains(h) || cover.allows(h));
    final cand = PluginCandidate(
      engineId: p.engineId,
      name: d.name?.isNotEmpty == true ? d.name! : p.name,
      version: entry.version.isEmpty ? null : entry.version,
      source: r.body,
      sourceUrl: file.toString(),
      sha256: entry.sha256,
      declaredUrl: d.url!,
      categories: d.categories,
      allowedHosts: within ? p.allowedHosts : newAllowed,
      signed: true,
      repoId: p.repoId,
      differences: _differences(p, d.url!, newAllowed, entry.version),
    );
    if (within) {
      await _applyUpdate(p, cand, auto: true);
    } else {
      await _park(p, cand);
    }
  }

  List<String> _differences(InstalledPlugin p, String newUrl, List<String> newAllowed, String? newVersion) {
    final out = <String>[];
    if (newVersion != null && newVersion.isNotEmpty && newVersion != p.version) {
      out.add('Version: ${p.version ?? 'unknown'} to $newVersion');
    }
    final oldDomain = registrableDomain(Uri.tryParse(p.declaredUrl)?.host ?? '');
    final newDomain = registrableDomain(Uri.parse(newUrl).host);
    if (oldDomain != newDomain) out.add('Site changes from $oldDomain to $newDomain');
    final added = newAllowed.where((h) => !p.allowedHosts.map((e) => e.toLowerCase()).contains(h)).toList();
    if (added.isNotEmpty) out.add('Newly allowed: ${added.join(', ')}');
    final dropped = p.allowedHosts.where((h) => !newAllowed.contains(h.toLowerCase())).toList();
    if (dropped.isNotEmpty) out.add('No longer allowed: ${dropped.join(', ')}');
    if (out.isEmpty) out.add('The plugin file changed');
    return out;
  }

  Future<void> _park(InstalledPlugin p, PluginCandidate c) async {
    await _writeBytes(_store!.pendingFile(p.id), c.source);
    _store.plugin(p.id).pending = PendingRecord(
      version: c.version ?? '',
      sha256: c.sha256,
      name: c.name,
      declaredUrl: c.declaredUrl,
      allowedHosts: c.allowedHosts,
      categories: c.categories,
      differences: c.differences,
    );
    await _plugDao.setUpdateSha(p.id, c.sha256);
  }

  Future<void> _applyUpdate(InstalledPlugin p, PluginCandidate c, {required bool auto}) async {
    final st = _store!;
    final cur = st.file(p.id);
    // Keep the version being replaced, once.
    if (await cur.exists()) {
      await cur.copy(st.prevFile(p.id).path);
    }
    await _writeBytes(cur, c.source);
    st.plugin(p.id)
      ..prev = PrevVersion(
        version: p.version,
        sha256: p.sha256,
        name: p.name,
        declaredUrl: p.declaredUrl,
        allowedHosts: p.allowedHosts,
        categories: p.categories,
      )
      ..categories = c.categories
      ..pending = null
      ..autoUpdatedAt = auto ? _now() : null;
    await st.deleteIfExists(st.pendingFile(p.id));
    await _plugDao.upsertPlugin(PluginsCompanion(
      id: Value(p.id),
      engineId: Value(p.engineId),
      name: Value(c.name),
      sha256: Value(c.sha256),
      sourceUrl: Value(c.sourceUrl),
      declaredUrl: Value(c.declaredUrl),
      allowedHosts: Value(c.allowedHosts),
      signed: Value(p.signed),
      installedAt: Value(p.installedAt),
      updatedAt: Value(_now()),
      repoId: Value(p.repoId),
      version: Value(c.version),
      updateSha: const Value(null),
    ));
  }

  /// The user approved the update that waits for [p]: re-checks the parked
  /// file and applies it.
  Future<void> approveUpdate(InstalledPlugin p) async {
    await ensureLoaded();
    final rec = _store!.plugin(p.id).pending;
    if (rec == null) return;
    final Uint8List bytes;
    try {
      bytes = await _store.pendingFile(p.id).readAsBytes();
    } on FileSystemException {
      await _dropPending(p.id);
      throw PluginInstallError(InstallErrorKind.malformed, 'The downloaded update is gone; check for updates again');
    }
    if (_hash(bytes) != rec.sha256) {
      await _dropPending(p.id);
      await _store.save();
      await _refresh();
      throw PluginInstallError(InstallErrorKind.hashMismatch, 'The downloaded update changed on disk and was discarded');
    }
    final d = await _describe(NovaEngine(id: p.engineId, source: utf8.decode(bytes)));
    await _applyUpdate(
      p,
      PluginCandidate(
        engineId: p.engineId,
        name: rec.name,
        version: rec.version.isEmpty ? null : rec.version,
        source: bytes,
        sourceUrl: p.sourceUrl,
        sha256: rec.sha256,
        declaredUrl: d.url!,
        categories: d.categories,
        allowedHosts: rec.allowedHosts,
        signed: p.signed,
        repoId: p.repoId,
      ),
      auto: false,
    );
    await _runsDao.clear(p.id);
    await _store.save();
    await _refresh();
  }

  /// Declines the waiting update; it is offered again only if the repo changes.
  Future<void> dismissUpdate(InstalledPlugin p) async {
    await _dropPending(p.id);
    await _store!.save();
    await _refresh();
  }

  /// Brings back the version before the last update. Works once.
  Future<void> undoUpdate(InstalledPlugin p) async {
    await ensureLoaded();
    final st = _store!;
    final prev = st.plugin(p.id).prev;
    if (prev == null || !st.prevFile(p.id).existsSync()) return;
    final bytes = await st.prevFile(p.id).readAsBytes();
    if (_hash(bytes) != prev.sha256) return;
    await _writeBytes(st.file(p.id), bytes);
    await st.deleteIfExists(st.prevFile(p.id));
    st.plugin(p.id)
      ..prev = null
      ..autoUpdatedAt = null
      ..categories = prev.categories;
    await _dropPending(p.id);
    await _plugDao.upsertPlugin(PluginsCompanion(
      id: Value(p.id),
      engineId: Value(p.engineId),
      name: Value(prev.name),
      sha256: Value(prev.sha256),
      sourceUrl: Value(p.sourceUrl),
      declaredUrl: Value(prev.declaredUrl),
      allowedHosts: Value(prev.allowedHosts),
      signed: Value(p.signed),
      installedAt: Value(p.installedAt),
      updatedAt: Value(_now()),
      repoId: Value(p.repoId),
      version: Value(prev.version),
      updateSha: const Value(null),
    ));
    await st.save();
    await _refresh();
  }

  /// "Check for update" for an unsigned plugin: downloads its file again. A
  /// changed file or domain always needs approval, never applies by itself.
  Future<UpdateCheck> checkUnsigned(InstalledPlugin p) async {
    await ensureLoaded();
    if (p.signed) return UpdateCheck.failed;
    final uri = Uri.parse(p.sourceUrl);
    final r = await _fetcher!.get(uri, maxBytes: maxPluginBytes);
    if (!r.ok) throw PluginInstallError(InstallErrorKind.fetch, 'The server answered ${r.status}');
    if (_hash(r.body) == p.sha256) {
      await _dropPending(p.id);
      await _store!.save();
      await _refresh();
      return UpdateCheck.upToDate;
    }
    final c = await _inspectSingleBytes(uri, r.body);
    final diffs = _differences(p, c.declaredUrl, c.allowedHosts, null);
    final parked = PluginCandidate(
      engineId: p.engineId,
      name: c.name,
      version: null,
      source: c.source,
      sourceUrl: c.sourceUrl,
      sha256: c.sha256,
      declaredUrl: c.declaredUrl,
      categories: c.categories,
      allowedHosts: c.allowedHosts,
      signed: false,
      differences: diffs,
    );
    await _park(p, parked);
    await _store!.save();
    await _refresh();
    return UpdateCheck.needsApproval;
  }

  /// Runs the Test button: one search with the user's [query].
  Future<PluginSearch> test(InstalledPlugin p, String query) => search(p, query);
}

/// At most [limit] plugin processes at once.
class _Gate {
  _Gate(this.limit);
  int limit;
  int _running = 0;
  final _waiting = <Completer<void>>[];

  Future<T> run<T>(Future<T> Function() body) async {
    if (_running >= limit) {
      final c = Completer<void>();
      _waiting.add(c);
      await c.future;
    } else {
      _running++;
    }
    try {
      return await body();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeAt(0).complete();
      } else {
        _running--;
      }
    }
  }
}

/// Plugin processes at once: 1 on devices with 2 GB of RAM or less, 2 on
/// other phones and TVs, 4 on desktop (a CPython process uses 25 to 40 MB).
int pluginConcurrency({required bool desktop, required bool lowRam}) => desktop ? 4 : (lowRam ? 1 : 2);
