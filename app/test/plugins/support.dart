import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chithram/src/core/paths.dart';
import 'package:chithram/src/data/database.dart';
import 'package:chithram/src/plugins/backoff.dart';
import 'package:chithram/src/plugins/plugin_fetch.dart';
import 'package:chithram/src/plugins/plugin_registry.dart';
import 'package:chithram/src/plugins/plugin_runtime.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:drift/native.dart';
import 'package:nova_host/nova_host.dart';

/// Files of a fixture repo directory (see fixtures/make_fixtures.py), by name.
Map<String, Uint8List> repoFiles(String dir) => {
      for (final f in Directory('test/plugins/fixtures/$dir').listSync().whereType<File>())
        f.uri.pathSegments.last: f.readAsBytesSync(),
    };

const repoBase = 'https://repo.example/plugins/';

/// Serves [files] under [base]; everything else is 404. Counts requests.
class FakeFetcher implements PluginFetcher {
  FakeFetcher();

  final Map<String, Uint8List> files = {};
  final List<String> calls = [];
  Object? failWith;
  int failStatus = 0;
  Duration? retryAfter;

  void serve(Map<String, Uint8List> repo, {String base = repoBase}) {
    files.removeWhere((k, _) => k.startsWith(base));
    for (final e in repo.entries) {
      files['$base${e.key}'] = e.value;
    }
  }

  static String etagOf(List<int> b) => '"${crypto.sha1.convert(b)}"';

  @override
  Future<FetchResult> get(Uri url, {required int maxBytes, String? etag}) async {
    calls.add(url.toString());
    final err = failWith;
    if (err != null) throw err;
    if (failStatus != 0) return FetchResult(failStatus, Uint8List(0), retryAfter: retryAfter);
    final body = files[url.toString()];
    if (body == null) return FetchResult(404, Uint8List(0));
    if (body.length > maxBytes) throw PluginInstallError(InstallErrorKind.tooLarge, 'too large');
    final tag = etagOf(body);
    if (etag != null && etag == tag) return FetchResult(304, Uint8List(0), etag: tag);
    return FetchResult(200, body, etag: tag);
  }
}

/// A runner that reads `url`, `name` and `supported_categories` from the plugin
/// source with regexes, and returns canned search outcomes.
class FakeRunner implements PluginRunner {
  FakeRunner();

  String? unavailable;
  final List<String> describes = [];
  final Set<String> failDescribe = {};

  /// Per engine id: what a search returns.
  final Map<String, SearchOutcome Function(NovaEngine)> searches = {};
  int running = 0, maxRunning = 0;
  Duration searchTime = Duration.zero;
  final List<NovaEngine> engines = [];

  @override
  String? get unavailableReason => unavailable;

  @override
  Future<DescribeOutcome> describe(NovaEngine engine) async {
    if (unavailable != null) throw PluginsUnavailable(unavailable!);
    describes.add(engine.id);
    if (failDescribe.contains(engine.id)) return DescribeOutcome(ok: false, reason: 'SyntaxError');
    final src = engine.source;
    final url = RegExp(r"url = '([^']*)'").firstMatch(src)?.group(1);
    final name = RegExp(r"name = '([^']*)'").firstMatch(src)?.group(1);
    final cats = RegExp(r"supported_categories = \{([^}]*)\}").firstMatch(src)?.group(1) ?? '';
    return DescribeOutcome(
      ok: url != null,
      name: name,
      url: url,
      categories: [for (final m in RegExp(r"'(\w+)':").allMatches(cats)) m.group(1)!],
      reason: url == null ? 'no url' : null,
    );
  }

  @override
  Future<SearchOutcome> search(NovaEngine engine, String what, {String cat = 'all'}) async {
    if (unavailable != null) throw PluginsUnavailable(unavailable!);
    engines.add(engine);
    running++;
    if (running > maxRunning) maxRunning = running;
    try {
      if (searchTime > Duration.zero) await Future<void>.delayed(searchTime);
      return (searches[engine.id] ?? (e) => outcome(e.id))(engine);
    } finally {
      running--;
    }
  }

  @override
  Future<Uint8List> downloadTorrent(NovaEngine engine, String url) async => Uint8List.fromList(utf8.encode('d4:infod4:name1:xee'));
}

SearchOutcome outcome(
  String engineId, {
  SearchStatus status = SearchStatus.ok,
  String? reason,
  List<Map<String, Object?>>? results,
  List<String> brokerLog = const [],
}) =>
    SearchOutcome(
      status: status,
      results: results ??
          [
            {'name': 'Fixture Film 1', 'link': 'magnet:?xt=urn:btih:${'a' * 40}', 'size': 1000, 'seeds': 9, 'leech': 1, 'pub_date': 1760000000},
          ],
      elapsed: const Duration(milliseconds: 40),
      brokerLog: brokerLog,
      requests: 1,
      reason: reason,
      engineId: engineId,
    );

class Harness {
  Harness._(this.db, this.dir, this.fetcher, this.runner, this.registry, this.clock);

  final AppDatabase db;
  final Directory dir;
  final FakeFetcher fetcher;
  final FakeRunner runner;
  final PluginRegistry registry;
  final TestClock clock;

  static Future<Harness> create({int concurrency = 2, Backoff? backoff}) async {
    final db = AppDatabase(NativeDatabase.memory());
    final dir = await Directory.systemTemp.createTemp('plugin_test');
    final fetcher = FakeFetcher();
    final runner = FakeRunner();
    final clock = TestClock(DateTime.utc(2026, 10, 24, 12));
    final registry = PluginRegistry.open(
      db: db,
      paths: AppPaths.under(dir.path),
      runner: runner,
      fetcher: fetcher,
      now: clock.call,
      concurrency: concurrency,
      backoff: backoff,
    );
    return Harness._(db, dir, fetcher, runner, registry, clock);
  }

  /// Adds the v1 repo with all non-adult plugins installed.
  Future<RepoPreview> addRepo({String dirName = 'v1', List<String>? only}) async {
    fetcher.serve(repoFiles(dirName));
    final preview = await registry.previewRepo('${repoBase}plugins.json');
    final cands = [
      for (final e in preview.entries)
        if (only == null || only.contains(e.id)) await registry.inspectEntry(preview, e),
    ];
    await registry.installFromRepo(preview, cands);
    return preview;
  }

  InstalledPlugin plugin(String engineId) => registry.plugins.value.firstWhere((p) => p.engineId == engineId);

  Future<void> close() async {
    registry.dispose();
    await db.close();
    await dir.delete(recursive: true);
  }
}

class TestClock {
  TestClock(this.now);
  DateTime now;
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}
