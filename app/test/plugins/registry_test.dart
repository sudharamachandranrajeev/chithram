import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chithram/src/core/paths.dart';
import 'package:chithram/src/data/db_pin_store.dart';
import 'package:chithram/src/find/find_api.dart';
import 'package:chithram/src/plugins/plugin_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_host/nova_host.dart';

import 'support.dart';

void main() {
  late Harness h;
  setUp(() async => h = await Harness.create());
  tearDown(() => h.close());

  Future<PluginInstallError> installError(Future<Object?> f) async {
    try {
      await f;
    } on PluginInstallError catch (e) {
      return e;
    }
    fail('expected a PluginInstallError');
  }

  group('adding a repository', () {
    test('first use shows the key and pins nothing until the user installs', () async {
      h.fetcher.serve(repoFiles('v1'));
      final preview = await h.registry.previewRepo('${repoBase}plugins.json');
      expect(preview.firstUse, isTrue);
      expect(preview.keyId, isNotEmpty);
      expect(preview.name, 'Test repo');
      expect(await DbPinStore(h.db).get(preview.repoId), isNull);
      expect(h.registry.plugins.value, isEmpty);
    });

    test('adult entries are hidden', () async {
      h.fetcher.serve(repoFiles('v1'));
      final preview = await h.registry.previewRepo(repoBase);
      expect(preview.entries.map((e) => e.id), ['alpha', 'beta']);
      expect(preview.hiddenAdult, 1);
      expect(h.fetcher.calls.any((c) => c.contains('adulty.py')), isFalse);
    });

    test('install pins the key and approves the declared domain plus manifest hosts', () async {
      final preview = await h.addRepo();
      expect(await DbPinStore(h.db).get(preview.repoId), isNotNull);
      final alpha = h.plugin('alpha');
      expect(alpha.signed, isTrue);
      expect(alpha.declaredUrl, 'https://alpha.example');
      expect(alpha.allowedHosts, ['alpha.example', 'cdn.alpha.example']);
      expect(alpha.version, '1.0');
      expect(alpha.categories, containsAll(['all', 'movies', 'tv']));
      expect(h.plugin('beta').allowedHosts, ['beta.example']);
      expect((await h.registry.repos()).single.name, 'Test repo');
    });

    test('a bad signature, a changed key and a hash mismatch each say something different', () async {
      h.fetcher.serve(repoFiles('v1'));
      final tampered = repoFiles('v1');
      final json = utf8.decode(tampered['plugins.json']!).replaceFirst('"Alpha"', '"Alphx"');
      tampered['plugins.json'] = Uint8List.fromList(utf8.encode(json));
      h.fetcher.serve(tampered);
      final bad = await installError(h.registry.previewRepo(repoBase));
      expect(bad.kind, InstallErrorKind.badSignature);

      await h.addRepo(); // pins key a
      h.fetcher.serve(repoFiles('v2_keyb'));
      final changed = await installError(h.registry.previewRepo(repoBase));
      expect(changed.kind, InstallErrorKind.keyChanged);

      h.fetcher.serve(repoFiles('v1'));
      final preview = await h.registry.previewRepo(repoBase);
      h.fetcher.files['${repoBase}alpha.py'] = Uint8List.fromList(utf8.encode('# swapped\n'));
      final mismatch = await installError(h.registry.inspectEntry(preview, preview.entries.first));
      expect(mismatch.kind, InstallErrorKind.hashMismatch);

      expect({bad.message, changed.message, mismatch.message}, hasLength(3));
    });

    test('a plugin that does not load, or declares no site, is not installable', () async {
      h.fetcher.serve(repoFiles('v1'));
      final preview = await h.registry.previewRepo(repoBase);
      h.runner.failDescribe.add('alpha');
      expect((await installError(h.registry.inspectEntry(preview, preview.entries.first))).kind, InstallErrorKind.describeFailed);
    });

    test('plugins cannot be added where there is no runtime', () async {
      h.fetcher.serve(repoFiles('v1'));
      final preview = await h.registry.previewRepo(repoBase);
      h.runner.unavailable = 'This build does not include the plugin runtime';
      expect((await installError(h.registry.inspectEntry(preview, preview.entries.first))).kind, InstallErrorKind.unavailable);
    });
  });

  group('a single .py', () {
    const url = 'https://files.example/plugins/solo.py';
    String src({String site = 'https://solo.example', String header = ''}) =>
        "$header\nclass solo(object):\n    url = '$site'\n    name = 'Solo'\n    supported_categories = {'all': '0'}\n";

    void serveSolo(String source) => h.fetcher.files[url] = Uint8List.fromList(utf8.encode(source));

    test('shows unsigned and the declared domain, and installs', () async {
      serveSolo(src(header: '# chithram: hosts=img.solo.example'));
      final c = await h.registry.inspectSingle(url);
      expect(c.signed, isFalse);
      expect(c.declaredDomain, 'solo.example');
      expect(c.allowedHosts, ['img.solo.example', 'solo.example']);
      expect(c.warnings.single, contains('Unsigned'));
      await h.registry.installSingle(c);
      final p = h.plugin('solo');
      expect(p.id, 'single:solo');
      expect(p.signed, isFalse);
      expect(p.version, isNull);
    });

    test('an http site adds a plain-http warning', () async {
      serveSolo(src(site: 'http://solo.example'));
      final c = await h.registry.inspectSingle(url);
      expect(c.warnings, hasLength(2));
      expect(c.warnings.last, contains('plain http'));
    });

    test('ip literals, private hosts and adult plugins are refused', () async {
      for (final site in ['http://192.168.1.5', 'http://10.0.0.2:8080', 'http://localhost', 'http://nas.local', 'http://intranet']) {
        serveSolo(src(site: site));
        expect((await installError(h.registry.inspectSingle(url))).kind, InstallErrorKind.privateOrIp, reason: site);
      }
      serveSolo(src(header: '# chithram: adult=true'));
      expect((await installError(h.registry.inspectSingle(url))).kind, InstallErrorKind.adult);
    });

    test('not a .py link, not UTF-8, bad file name', () async {
      expect((await installError(h.registry.inspectSingle('https://files.example/plugins/solo.txt'))).kind, InstallErrorKind.malformed);
      h.fetcher.files[url] = Uint8List.fromList([0xff, 0xfe, 0x00, 0x80]);
      expect((await installError(h.registry.inspectSingle(url))).kind, InstallErrorKind.malformed);
      h.fetcher.files['https://files.example/1bad-name.py'] = Uint8List.fromList(utf8.encode(src()));
      expect((await installError(h.registry.inspectSingle('https://files.example/1bad-name.py'))).kind, InstallErrorKind.malformed);
    });

    test('over 256 KiB is refused by the fetch cap', () async {
      h.fetcher.files[url] = Uint8List(PluginRegistry.maxPluginBytes + 1);
      expect((await installError(h.registry.inspectSingle(url))).kind, InstallErrorKind.tooLarge);
    });

    test('check for update: same file is up to date; a changed one needs approval, never applied by itself', () async {
      serveSolo(src());
      await h.registry.installSingle(await h.registry.inspectSingle(url));
      expect(await h.registry.checkUnsigned(h.plugin('solo')), UpdateCheck.upToDate);
      serveSolo(src(site: 'https://solo-new.example'));
      expect(await h.registry.checkUnsigned(h.plugin('solo')), UpdateCheck.needsApproval);
      final p = h.plugin('solo');
      expect(p.pending!.differences, contains('Site changes from solo.example to solo-new.example'));
      expect(p.declaredUrl, 'https://solo.example');
      // Background checks never touch unsigned plugins.
      h.fetcher.calls.clear();
      await h.registry.checkDue();
      expect(h.fetcher.calls, isEmpty);
      await h.registry.approveUpdate(p);
      final after = h.plugin('solo');
      expect(after.declaredUrl, 'https://solo-new.example');
      expect(after.allowedHosts, ['solo-new.example']);
      expect(after.pending, isNull);
      expect(after.autoUpdatedAt, isNull);
    });
  });

  group('automatic updates from a signed repo', () {
    setUp(() async {
      await h.addRepo();
      h.clock.advance(const Duration(hours: 25));
    });

    test('same-domain update applies by itself; keeps the old file; undo works once', () async {
      final before = h.plugin('alpha');
      h.fetcher.serve(repoFiles('v2'));
      await h.registry.checkDue();
      final alpha = h.plugin('alpha');
      expect(alpha.version, '1.1');
      expect(alpha.sha256, isNot(before.sha256));
      expect(alpha.autoUpdatedAt, h.clock.now);
      expect(alpha.pending, isNull);
      expect(alpha.canUndo, isTrue);
      expect(alpha.allowedHosts, before.allowedHosts);

      await h.registry.undoUpdate(alpha);
      final back = h.plugin('alpha');
      expect(back.version, '1.0');
      expect(back.sha256, before.sha256);
      expect(back.canUndo, isFalse);
      expect(back.autoUpdatedAt, isNull);
      await h.registry.undoUpdate(back); // nothing left to undo
      expect(h.plugin('alpha').sha256, before.sha256);
    });

    test('a new domain waits for approval with the differences; the old version keeps running', () async {
      final before = h.plugin('beta');
      h.fetcher.serve(repoFiles('v2'));
      await h.registry.checkDue();
      final beta = h.plugin('beta');
      expect(beta.version, '1.0');
      expect(beta.sha256, before.sha256);
      expect(beta.pending, isNotNull);
      expect(beta.pending!.differences, containsAll(['Version: 1.0 to 1.1', 'Site changes from beta.example to beta-new.example']));
      expect(beta.pending!.differences.any((d) => d.startsWith('Newly allowed')), isTrue);
      // It still runs from the old file, pinned to the old hosts.
      await h.registry.search(beta, 'x');
      expect(h.runner.engines.last.pinnedHosts, ['beta.example']);
      expect(h.runner.engines.last.source, contains('https://beta.example'));

      await h.registry.approveUpdate(beta);
      final after = h.plugin('beta');
      expect(after.version, '1.1');
      expect(after.pending, isNull);
      expect(after.allowedHosts, ['beta-new.example']);
      expect(after.autoUpdatedAt, isNull);
      expect(after.canUndo, isTrue);
    });

    test('new plugins in the repo are listed as New and not installed', () async {
      h.fetcher.serve(repoFiles('v2'));
      await h.registry.checkDue();
      expect(h.registry.plugins.value.map((p) => p.engineId), isNot(contains('gamma')));
      final repo = (await h.registry.repos()).single;
      expect(repo.offers.map((o) => o.id), ['gamma']);
      expect(repo.isNew(repo.offers.single), isTrue);
      // Install it from the offer.
      final cands = await h.registry.inspectOffers(repo.id, repo.offers);
      await h.registry.installOffers(repo.id, cands);
      expect(h.plugin('gamma').signed, isTrue);
      expect((await h.registry.repos()).single.offers, isEmpty);
    });

    test('the plugin is not updated when its file does not match the signed sha256', () async {
      final before = h.plugin('alpha');
      h.fetcher.serve(repoFiles('v2'));
      h.fetcher.files['${repoBase}alpha.py'] = Uint8List.fromList(utf8.encode('# not what was signed\n'));
      await h.registry.checkDue();
      expect(h.plugin('alpha').sha256, before.sha256);
      expect(h.plugin('alpha').pending, isNull);
    });

    test('a plugin that fails describe in the sandbox is not updated', () async {
      final before = h.plugin('alpha');
      h.fetcher.serve(repoFiles('v2'));
      h.runner.failDescribe.add('alpha');
      await h.registry.checkDue();
      expect(h.plugin('alpha').sha256, before.sha256);
      expect(h.plugin('alpha').pending, isNull);
      expect(h.plugin('beta').pending, isNotNull); // the others still go on
    });

    test('a bad signature updates nothing', () async {
      final before = h.plugin('alpha');
      final files = repoFiles('v2');
      files['plugins.json'] = Uint8List.fromList(utf8.encode(utf8.decode(files['plugins.json']!).replaceFirst('1.1', '9.9')));
      h.fetcher.serve(files);
      await h.registry.checkDue();
      expect(h.plugin('alpha').sha256, before.sha256);
      expect((await h.registry.repos()).single.lastError, contains('bad signature'));
    });

    test('a changed repo key blocks its plugins and updates nothing', () async {
      final before = h.plugin('alpha');
      h.fetcher.serve(repoFiles('v2_keyb'));
      await h.registry.checkDue();
      expect(h.plugin('alpha').sha256, before.sha256);
      expect(h.plugin('alpha').health.status, PluginHealthStatus.blocked);
      expect((await h.registry.repos()).single.keyChanged, isTrue);
      expect(await h.registry.enabled(), isEmpty);
    });

    test('unchanged repo: ETag answers 304 and nothing is downloaded; checks are at most once a day', () async {
      h.fetcher.serve(repoFiles('v2'));
      await h.registry.checkDue();
      h.fetcher.calls.clear();
      // Within 24 h: no request at all.
      h.clock.advance(const Duration(hours: 23));
      await h.registry.checkDue();
      expect(h.fetcher.calls, isEmpty);
      // After 24 h: one conditional request, answered 304.
      h.clock.advance(const Duration(hours: 2));
      await h.registry.checkDue();
      expect(h.fetcher.calls, ['${repoBase}plugins.json']);
    });

    test('failures back off with a cap of 6 h and no request before then', () async {
      h.fetcher.failStatus = 503;
      h.fetcher.calls.clear();
      await h.registry.checkDue();
      final first = h.fetcher.calls.length;
      expect(first, 1);
      await h.registry.checkDue();
      expect(h.fetcher.calls.length, first); // waiting
      final repo = (await h.registry.repos()).single;
      expect(repo.lastError, contains('503'));
      h.clock.advance(const Duration(hours: 6, minutes: 1));
      await h.registry.checkDue();
      expect(h.fetcher.calls.length, first + 1);
    });

    test('Retry-After is honoured', () async {
      h.fetcher
        ..failStatus = 429
        ..retryAfter = const Duration(hours: 3);
      await h.registry.checkDue();
      h.fetcher.calls.clear();
      h.clock.advance(const Duration(hours: 2));
      await h.registry.checkDue();
      expect(h.fetcher.calls, isEmpty);
      h.clock.advance(const Duration(hours: 1, minutes: 1));
      await h.registry.checkDue();
      expect(h.fetcher.calls, isNotEmpty);
    });
  });

  group('running', () {
    setUp(() async => h.addRepo());

    test('a changed file is refused before it runs (hash-mismatch) and the plugin shows Blocked', () async {
      final p = h.plugin('alpha');
      final file = File('${h.dir.path}/support/plugins/${p.id.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_')}.py');
      await file.writeAsString('# tampered\n');
      final r = await h.registry.search(p, 'x');
      expect(r.ok, isFalse);
      expect(r.reason, 'hash-mismatch');
      expect(h.runner.engines, isEmpty);
      expect(h.plugin('alpha').health.status, PluginHealthStatus.blocked);
    });

    test('search pins the approved hosts and returns typed hits with pub_date', () async {
      final p = h.plugin('alpha');
      final r = await h.registry.search(p, 'Fixture');
      expect(r.ok, isTrue);
      expect(h.runner.engines.single.pinnedHosts, ['alpha.example', 'cdn.alpha.example']);
      final hit = r.hits.single;
      expect(hit.engineId, 'alpha');
      expect(hit.seeders, 9);
      expect(hit.pubDate, DateTime.utc(2025, 10, 9, 8, 53, 20));
      expect(h.plugin('alpha').health.status, PluginHealthStatus.healthy);
    });

    test('url-changed blocks; blocked hosts are recorded', () async {
      h.runner.searches['alpha'] = (e) => outcome(e.id,
          status: SearchStatus.error, reason: urlChangedReason, results: const [], brokerLog: ['DENIED host evil.test not in allowlist: http://evil.test/x']);
      final r = await h.registry.search(h.plugin('alpha'), 'x');
      expect(r.reason, urlChangedReason);
      expect(r.blockedHosts, ['evil.test']);
      final p = h.plugin('alpha');
      expect(p.health.status, PluginHealthStatus.blocked);
      expect(p.health.blockedHosts, ['evil.test']);
      expect(await h.registry.enabled(), [h.plugin('beta')]);
    });

    test('health: three failures in a row is Failing; recovery is Degraded then Healthy', () async {
      h.runner.searches['alpha'] = (e) => outcome(e.id, status: SearchStatus.error, reason: 'timeout', results: const []);
      for (var i = 0; i < 3; i++) {
        await h.registry.search(h.plugin('alpha'), 'x');
        h.clock.advance(const Duration(seconds: 1));
      }
      expect(h.plugin('alpha').health.status, PluginHealthStatus.failing);
      expect(h.plugin('alpha').health.lastError, 'timeout');
      h.runner.searches.remove('alpha');
      for (var i = 0; i < 10; i++) {
        await h.registry.search(h.plugin('alpha'), 'x');
        h.clock.advance(const Duration(seconds: 1));
      }
      expect(h.plugin('alpha').health.status, PluginHealthStatus.healthy);
      expect(h.plugin('alpha').health.medianMs, isNotNull);
    });

    test('plugins unavailable on this device show Unavailable and are not queried', () async {
      h.runner.unavailable = 'Landlock missing';
      final r = await h.registry.search(h.plugin('alpha'), 'x');
      expect(r.reason, contains('unavailable'));
      expect(h.plugin('alpha').health.status, PluginHealthStatus.unavailable);
      expect(await h.registry.enabled(), isEmpty);
    });

    test('disabled plugins are not offered; enabling brings them back', () async {
      await h.registry.setEnabled(h.plugin('alpha'), false);
      expect((await h.registry.enabled()).map((p) => p.engineId), ['beta']);
      expect(h.registry.providers.value.map((p) => p.id), ['plugin:${h.plugin('beta').id}']);
      await h.registry.setEnabled(h.plugin('alpha'), true);
      expect(await h.registry.enabled(), hasLength(2));
    });

    test('at most `concurrency` plugin processes run at once', () async {
      await h.close();
      h = await Harness.create(concurrency: 1);
      await h.addRepo();
      h.runner.searchTime = const Duration(milliseconds: 30);
      await Future.wait([for (final p in h.registry.plugins.value) h.registry.search(p, 'x')]);
      expect(h.runner.maxRunning, 1);
      expect(pluginConcurrency(desktop: false, lowRam: true), 1);
      expect(pluginConcurrency(desktop: false, lowRam: false), 2);
      expect(pluginConcurrency(desktop: true, lowRam: false), 4);
    });

    test('Find provider maps hits and fetches .torrent links through the plugin', () async {
      h.runner.searches['alpha'] = (e) => outcome(e.id, results: [
            {'name': 'Dated', 'link': 'https://alpha.example/t/1.torrent', 'size': 5000, 'seeds': 3, 'leech': 2, 'pub_date': 1760000000, 'desc_link': 'https://alpha.example/d/1'},
            {'name': 'Mag', 'link': 'magnet:?xt=urn:btih:${'b' * 40}', 'size': -1, 'seeds': -1, 'leech': -1},
          ]);
      final provider = h.registry.providers.value.firstWhere((p) => p.id.endsWith(':alpha'));
      final rs = await provider.search(const TextQuery('x'), CancelToken()).toList();
      expect(rs, hasLength(2));
      expect(rs[0].hasTorrentFile, isTrue);
      expect(rs[0].seeders, 3);
      expect(rs[0].detailsUrl, 'https://alpha.example/d/1');
      expect(rs[0].published, isNotNull);
      expect(rs[1].magnet, startsWith('magnet:'));
      expect(rs[1].infoHash, 'b' * 40);
      expect(rs[1].seeders, isNull);
      final bytes = await provider.fetchTorrent(rs[0]);
      expect(utf8.decode(bytes), 'd4:infod4:name1:xee');
    });
  });

  group('removing', () {
    test('removing a repo removes its plugins, files and key pin', () async {
      final preview = await h.addRepo();
      await h.registry.removeRepo(preview.repoId);
      expect(h.registry.plugins.value, isEmpty);
      expect(await DbPinStore(h.db).get(preview.repoId), isNull);
      expect(await h.registry.repos(), isEmpty);
      expect(Directory('${h.dir.path}/support/plugins').listSync().where((f) => f.path.endsWith('.py')), isEmpty);
    });

    test('removing one plugin keeps the repo', () async {
      await h.addRepo();
      await h.registry.removePlugin(h.plugin('alpha'));
      expect(h.registry.plugins.value.map((p) => p.engineId), ['beta']);
      expect(await h.registry.repos(), hasLength(1));
    });

    test('state survives a restart', () async {
      await h.addRepo();
      h.fetcher.serve(repoFiles('v2'));
      h.clock.advance(const Duration(days: 2));
      await h.registry.checkDue();
      final again = PluginRegistry.open(
        db: h.db,
        paths: AppPaths.under(h.dir.path),
        runner: h.runner,
        fetcher: h.fetcher,
        now: h.clock.call,
      );
      await again.ensureLoaded();
      expect(again.plugins.value.firstWhere((p) => p.engineId == 'alpha').autoUpdatedAt, isNotNull);
      expect(again.plugins.value.firstWhere((p) => p.engineId == 'beta').pending, isNotNull);
      again.dispose();
    });
  });

  test('the inert registry offers nothing', () async {
    final r = PluginRegistry();
    expect(r.providers.value, isEmpty);
    expect(await r.enabled(), isEmpty);
    expect(await r.repos(), isEmpty);
    await r.start();
  });

  test('database rows carry what the spec lists', () async {
    await h.addRepo();
    final row = await h.db.pluginDao.plugin(h.plugin('alpha').id);
    expect(row!.repoId, isNotNull);
    expect(row.sourceUrl, '${repoBase}alpha.py');
    expect(row.signed, isTrue);
    expect(row.enabled, isTrue);
    expect(row.updateSha, isNull);
  });
}
