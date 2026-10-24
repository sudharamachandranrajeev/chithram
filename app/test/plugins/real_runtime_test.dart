// The registry against the real sandbox, a real HTTP server and the synthetic
// plugins in .github/fixtures/plugins. Needs NOVA_PYTHON, NOVA_RUNNER_DIR and
// NOVA_SANDBOX (nova.yml sets them) and port 8000; skipped otherwise.
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:chithram/src/core/paths.dart';
import 'package:chithram/src/data/database.dart';
import 'package:chithram/src/plugins/plugin_fetch.dart';
import 'package:chithram/src/plugins/plugin_registry.dart';
import 'package:chithram/src/plugins/plugin_runtime.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_host/nova_host.dart';

void main() {
  final env = Platform.environment;
  final enabled = env['NOVA_PYTHON'] != null && env['NOVA_RUNNER_DIR'] != null && env['NOVA_SANDBOX'] != null;
  final fixtures = Directory('../.github/fixtures/plugins');

  late HttpServer server;
  late Directory tmp;
  late AppDatabase db;
  late PluginRegistry registry;

  setUpAll(() async {
    if (!enabled) return;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8000);
    server.listen((r) async {
      final p = r.uri.path;
      File? f;
      if (p.startsWith('/plugins/single/')) {
        f = File('${fixtures.path}/single/${p.substring('/plugins/single/'.length)}');
      } else if (p.startsWith('/plugins/site/')) {
        f = File('${fixtures.path}/site/${p.substring('/plugins/site/'.length).split('?').first}');
      } else if (p.startsWith('/plugins/')) {
        f = File('${fixtures.path}/repo/${p.substring('/plugins/'.length)}');
      }
      if (f != null && f.existsSync() && f.statSync().type == FileSystemEntityType.file) {
        r.response.add(f.readAsBytesSync());
      } else {
        r.response.statusCode = 404;
      }
      await r.response.close();
    });
    tmp = await Directory.systemTemp.createTemp('real_plugins');
    db = AppDatabase(NativeDatabase.memory());
    registry = PluginRegistry.open(
      db: db,
      paths: AppPaths.under(tmp.path),
      runner: NovaPluginRunner.forPlatform(
        broker: BrokerPolicy(testMode: true, hostOverrides: {
          'fixture.test': InternetAddress.loopbackIPv4,
          'other.test': InternetAddress.loopbackIPv4,
        }),
      ),
      fetcher: HttpPluginFetcher(allowInsecure: true),
    );
  });

  tearDownAll(() async {
    if (!enabled) return;
    registry.dispose();
    await db.close();
    await server.close(force: true);
    await tmp.delete(recursive: true);
  });

  final skip = enabled ? false : 'NOVA_* not set';

  test('repo install, search with pub_date, torrent download, single file, url-changed, hash check', () async {
    const repoUrl = 'http://127.0.0.1:8000/plugins/plugins.json';
    final preview = await registry.previewRepo(repoUrl);
    expect(preview.firstUse, isTrue);
    expect(preview.entries.map((e) => e.id), ['fx_fixture', 'fx_urlswap']);
    final cands = [for (final e in preview.entries) await registry.inspectEntry(preview, e)];
    expect(cands.first.declaredDomain, 'fixture.test');
    expect(cands.first.allowedHosts, ['cdn.fixture.test', 'fixture.test']);
    await registry.installFromRepo(preview, cands);

    final fixture = registry.plugins.value.firstWhere((p) => p.engineId == 'fx_fixture');
    final r = await registry.search(fixture, 'Fixture Film', cat: fixture.categoryFor('movies'));
    expect(r.ok, isTrue, reason: '${r.reason}');
    final film = r.hits.firstWhere((h) => h.name == 'Fixture Film 1 2024 1080p');
    expect(film.seeders, 42);
    expect(film.leechers, 7);
    expect(film.sizeBytes, (1.5 * 1024 * 1024 * 1024).round());
    expect(film.pubDate, DateTime.fromMillisecondsSinceEpoch(1760000000 * 1000, isUtc: true));
    expect(film.infoHash, '1' * 40);
    expect(film.descLink, 'http://fixture.test:8000/plugins/site/item/42');
    expect(film.engineId, 'fx_fixture');
    expect(registry.plugins.value.firstWhere((p) => p.engineId == 'fx_fixture').health.status, PluginHealthStatus.healthy);

    final torrent = r.hits.firstWhere((h) => !h.isMagnet);
    final bytes = await registry.fetchTorrent(fixture, torrent.link);
    expect(String.fromCharCodes(bytes), 'd4:infod4:name1:xee');

    // The plugin cannot be sent anywhere its approved list does not name.
    final swap = registry.plugins.value.firstWhere((p) => p.engineId == 'fx_urlswap');
    final blocked = await registry.search(swap.copyWith(allowedHosts: ['elsewhere.test']), 'x');
    expect(blocked.reason, 'url-changed');
    expect(registry.plugins.value.firstWhere((p) => p.engineId == 'fx_urlswap').health.status, PluginHealthStatus.blocked);

    // A single .py.
    final c = await registry.inspectSingle('http://127.0.0.1:8000/plugins/single/fx_single.py');
    expect(c.signed, isFalse);
    expect(c.allowedHosts, ['fixture.test']);
    expect(c.warnings.last, contains('plain http'));
    await registry.installSingle(c);
    final t = await registry.test(registry.plugins.value.firstWhere((p) => p.engineId == 'fx_single'), 'Fixture Film');
    expect(t.ok, isTrue, reason: '${t.reason}');

    // A changed file is refused before it runs.
    final file = File('${tmp.path}/support/plugins/${fixture.id.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_')}.py');
    file.writeAsStringSync('${file.readAsStringSync()}\n# changed\n');
    final changed = await registry.search(fixture, 'x');
    expect(changed.reason, 'hash-mismatch');
  }, skip: skip);
}
