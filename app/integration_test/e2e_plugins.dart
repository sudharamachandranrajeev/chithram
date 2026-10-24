// End-to-end: search plugins. Run through e2e_all_test.dart.
//
// Real sandbox (the desktop runtime from NOVA_* on Linux, the isolated service
// on Android) against synthetic plugins served by the fixture server
// (.github/fixtures/plugins): the plugin site is "fixture.test:8000", which the
// end-to-end broker policy resolves to the local fixture server.
import 'dart:io';

import 'package:chithram/src/core/paths.dart';
import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/data/database.dart';
import 'package:chithram/src/plugins/plugin_registry.dart';
import 'package:chithram/src/plugins/plugin_wiring.dart';
import 'package:chithram/src/plugins/ui/plugin_keys.dart';
import 'package:chithram/src/plugins/ui/plugins_settings.dart';
import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/common/keys.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Real time until [finder] matches (the sandbox and the broker are real work).
Future<void> _waitFor(WidgetTester t, Finder finder, {Duration timeout = const Duration(seconds: 90)}) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < timeout) {
    if (finder.evaluate().isNotEmpty) return;
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await t.pump(const Duration(milliseconds: 100));
  }
  fail('timed out waiting for $finder');
}

Future<void> _ask(WidgetTester t, String text) async {
  await t.enterText(find.byKey(Keys.textEntryField), text);
  await t.tap(find.byKey(Keys.textEntryOk));
  await t.pump();
}

void pluginsE2e() {
  group('plugins', () {
    testWidgets('a fresh install has no plugins and no repo', (t) async {
      expect(PluginRegistry().providers.value, isEmpty);
      // The fixture repo URL is only a define; nothing is added by default.
      expect(e2ePluginRepo.isEmpty || e2ePluginRepo.startsWith('http'), isTrue);
    });

    testWidgets('install from a signed repo and a single link, test, health, url-changed', (t) async {
      expect(e2ePluginRepo, isNotEmpty, reason: 'E2E_PLUGIN_REPO is not set');
      t.view.physicalSize = const Size(1920, 1080);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final dir = await t.runAsync(() => Directory.systemTemp.createTemp('e2e_plugins')) as Directory;
      final db = AppDatabase(NativeDatabase.memory());
      final registry = openPluginRegistry(db: db, paths: AppPaths.under(dir.path));
      addTearDown(() async {
        registry.dispose();
        await db.close();
      });
      await t.pumpWidget(AppServicesScope(
        services: AppServices.memory(db: db, plugins: registry),
        child: FormScope(
          form: FormFactor.tv,
          child: MaterialApp(theme: buildChithramTheme(form: FormFactor.tv), home: const PluginsPage()),
        ),
      ));
      await t.pump();
      await t.runAsync(registry.ensureLoaded);
      expect(registry.plugins.value, isEmpty);

      // 1-2. Add the repo; the key is shown for confirmation.
      await t.tap(find.byKey(PluginKeys.addRepo));
      await t.pump();
      await t.pumpAndSettle();
      await _ask(t, e2ePluginRepo);
      await _waitFor(t, find.text('Trust this repository?'));
      expect(find.byKey(const ValueKey('plugins-key-id')), findsOneWidget);
      await t.tap(find.byKey(PluginKeys.trustContinue));
      await t.pumpAndSettle();

      // 3. Install fx_fixture and fx_urlswap; the domains screen lists fixture.test.
      await _waitFor(t, find.byKey(PluginKeys.pick('fx_fixture')));
      await t.tap(find.byKey(PluginKeys.pick('fx_fixture')));
      await t.tap(find.byKey(PluginKeys.pick('fx_urlswap')));
      await t.pump();
      await t.tap(find.byKey(PluginKeys.pickNext));
      await t.pump();
      await _waitFor(t, find.text('Allow these sites?'));
      expect(find.textContaining('fixture.test'), findsWidgets);
      expect(find.textContaining('cdn.fixture.test'), findsOneWidget);
      await t.tap(find.byKey(PluginKeys.installConfirm));
      await _waitFor(t, find.byKey(PluginKeys.plugin('fx_fixture')));
      expect(registry.plugins.value.map((p) => p.engineId), containsAll(['fx_fixture', 'fx_urlswap']));

      // Test returns the fixture row; health shows Healthy.
      await t.tap(find.byKey(PluginKeys.plugin('fx_fixture')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(PluginKeys.testRun));
      await t.pumpAndSettle();
      await _ask(t, 'Fixture Film 1');
      await _waitFor(t, find.byKey(const ValueKey('plugins-test-result')));
      expect(find.textContaining('Fixture Film 1 2024 1080p'), findsOneWidget);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      await _waitFor(t, find.byWidgetPredicate((w) => w is Text && w.key == PluginKeys.status('fx_fixture') && w.data == 'Healthy'));

      // What Torrent Home gets: typed hits with date, seeders and engine id, and a .torrent through the plugin.
      final fixture = registry.plugins.value.firstWhere((p) => p.engineId == 'fx_fixture');
      expect((await t.runAsync(registry.enabled))!.map((p) => p.engineId), contains('fx_fixture'));
      final r = (await t.runAsync(() => registry.search(fixture, 'Fixture Film', cat: fixture.categoryFor('movies'))))!;
      expect(r.ok, isTrue, reason: r.reason);
      final film = r.hits.firstWhere((h) => h.name == 'Fixture Film 1 2024 1080p');
      expect(film.engineId, 'fx_fixture');
      expect(film.seeders, 42);
      expect(film.pubDate, DateTime.fromMillisecondsSinceEpoch(1760000000 * 1000, isUtc: true));
      expect(film.infoHash, '1' * 40);
      final torrentHit = r.hits.firstWhere((h) => !h.isMagnet);
      final bytes = (await t.runAsync(() => registry.fetchTorrent(fixture, torrentHit.link)))!;
      expect(String.fromCharCodes(bytes), startsWith('d4:info'));

      // 4. A single .py: the warning lists fixture.test; confirm; Test works.
      await t.tap(find.byKey(PluginKeys.addSingle));
      await t.pumpAndSettle();
      await _ask(t, '$e2eBase/plugins/single/fx_single.py');
      await _waitFor(t, find.text('Install Fixture Single?'));
      expect(find.text('Unsigned'), findsOneWidget);
      expect(find.byKey(const ValueKey('plugins-warning-domains')), findsOneWidget);
      expect(t.widget<SelectableText>(find.byKey(const ValueKey('plugins-warning-domains'))).data, contains('fixture.test'));
      expect(find.textContaining('plain http'), findsOneWidget);
      await t.tap(find.byKey(PluginKeys.installAnyway));
      await _waitFor(t, find.byKey(PluginKeys.plugin('fx_single')));
      final single = registry.plugins.value.firstWhere((p) => p.engineId == 'fx_single');
      final sr = (await t.runAsync(() => registry.test(single, 'Fixture Film 1')))!;
      expect(sr.ok, isTrue, reason: sr.reason);
      expect(sr.hits.map((h) => h.name), contains('Fixture Film 1 2024 1080p'));

      // 5. A plugin whose declared domain is no longer the approved one ends Blocked (url-changed).
      final swap = registry.plugins.value.firstWhere((p) => p.engineId == 'fx_urlswap');
      expect((await t.runAsync(registry.enabled))!.map((p) => p.engineId), contains('fx_urlswap'));
      final approvedElsewhere = swap.copyWith(allowedHosts: ['elsewhere.test']);
      final res = (await t.runAsync(() => registry.search(approvedElsewhere, 'x')))!;
      expect(res.reason, 'url-changed');
      expect(res.hits, isEmpty);
      await t.pump(const Duration(milliseconds: 100));
      expect(t.widget<Text>(find.byKey(PluginKeys.status('fx_urlswap'))).data, 'Blocked');
      expect((await t.runAsync(registry.enabled))!.map((p) => p.engineId), isNot(contains('fx_urlswap')));
    });
  });
}
