// describe, the pinned allowlist, url-changed, pub_date and downloadTorrent,
// through the real runner. Needs NOVA_PYTHON and NOVA_RUNNER_DIR; runs inside
// NOVA_SANDBOX when it is set, otherwise unsandboxed (local development only).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_host/nova_host.dart';

void main() {
  final env = Platform.environment;
  final python = env['NOVA_PYTHON'];
  final runner = env['NOVA_RUNNER_DIR'];
  final enabled = python != null && runner != null;
  final skip = enabled ? false : 'NOVA_PYTHON / NOVA_RUNNER_DIR not set';

  late FixtureServer server;
  late NovaHost host;

  setUpAll(() async {
    if (!enabled) return;
    server = await FixtureServer.start();
    final sandbox = env['NOVA_SANDBOX'];
    final cfg = LaunchConfig(
      python: python,
      runnerDir: runner,
      sandboxExe: sandbox,
      insecureNoSandbox: sandbox == null,
      readOnlyPaths: [if (env['NOVA_PY_PREFIX'] != null) env['NOVA_PY_PREFIX']!],
      allowNoLandlock: env['NOVA_ALLOW_NO_LANDLOCK'] == '1',
    );
    host = NovaHost(
      start: () => ProcessSession.start(cfg),
      policy: BrokerPolicy(testMode: true, hostOverrides: {
        'example.test': InternetAddress.loopbackIPv4,
        'other.test': InternetAddress.loopbackIPv4,
      }),
    );
  });
  tearDownAll(() async {
    if (enabled) await server.close();
  });

  NovaEngine engine(String id, {List<String>? pinned}) {
    final src = novaFixtures[id]!.replaceAll('__BASE__', server.baseUrl);
    return NovaEngine(id: id, source: src, pinnedHosts: pinned);
  }

  test('describe reports name, url and categories without any network', () async {
    final d = await host.describe(engine('fx_good'));
    expect(d.ok, isTrue, reason: '${d.reason} ${d.stderrHead}');
    expect(d.name, 'Fixture Good');
    expect(d.url, server.baseUrl);
    expect(d.categories, ['all', 'movies']);
    expect(server.hits, isEmpty);
  }, skip: skip);

  test('describe fails for a plugin that does not load', () async {
    final d = await host.describe(NovaEngine(id: 'fx_broken', source: 'class fx_broken(:\n'));
    expect(d.ok, isFalse);
    expect(d.reason, isNotEmpty);
  }, skip: skip);

  test('a pinned allowlist that matches lets the search run', () async {
    final o = await host.search(engine('fx_good', pinned: ['example.test']), 'sintel');
    expect(o.status, SearchStatus.ok, reason: '${o.reason} ${o.stderrHead}');
    expect(o.hits, hasLength(3));
    expect(o.hits.first.engineId, 'fx_good');
    expect(o.hits.first.seeders, 10);
    expect(o.hits.first.pubDate, isNull);
  }, skip: skip);

  test('a plugin that now declares another domain is refused as url-changed, with no request', () async {
    server.hits.clear();
    final o = await host.search(engine('fx_good', pinned: ['elsewhere.test']), 'sintel');
    expect(o.status, SearchStatus.error);
    expect(o.reason, urlChangedReason);
    expect(o.results, isEmpty);
    expect(server.hits, isEmpty);
  }, skip: skip);

  test('the pinned list, not the declared url, decides which hosts the broker allows', () async {
    // fx_foreign asks for other.test; pinning only example.test must deny it.
    final o = await host.search(engine('fx_foreign', pinned: ['example.test']), 'sintel');
    expect(o.brokerLog.where((l) => l.startsWith('DENIED')), isNotEmpty);
    expect(server.hits.where((h) => h.endsWith('/steal')), isEmpty);
  }, skip: skip);

  test('pub_date comes through as a UTC time; missing or implausible ones are null', () async {
    final o = await host.search(engine('fx_dated', pinned: ['example.test']), 'x');
    expect(o.status, SearchStatus.ok, reason: '${o.reason} ${o.stderrHead}');
    final by = {for (final h in o.hits) h.name: h};
    expect(by['Dated item']!.pubDate, DateTime.fromMillisecondsSinceEpoch(1760000000 * 1000, isUtc: true));
    expect(by['Dated item']!.descLink, '${server.baseUrl}/item/1');
    expect(by['Undated item']!.pubDate, isNull);
    expect(by['Bad date item']!.pubDate, isNull);
    expect(by['Negative date item']!.pubDate, isNull);
    expect(by['Dated item']!.infoHash, 'c' * 40);
  }, skip: skip);

  test('downloadTorrent returns the file bytes', () async {
    final bytes = await host.downloadTorrent(engine('fx_dl', pinned: ['example.test']), '${server.baseUrl}/a.torrent');
    expect(String.fromCharCodes(bytes), 'd4:infod4:name1:xee');
  }, skip: skip);

  test('downloadTorrent refuses a file over 2 MiB', () async {
    await expectLater(
      host.downloadTorrent(engine('fx_dl', pinned: ['example.test']), '${server.baseUrl}/big.torrent'),
      throwsA(isA<NovaDownloadError>().having((e) => e.reason, 'reason', 'torrent-too-large')),
    );
  }, skip: skip);

  test('downloadTorrent will not leave the pinned hosts', () async {
    await expectLater(
      host.downloadTorrent(engine('fx_dl', pinned: ['example.test']), 'http://other.test:${server.port}/steal'),
      throwsA(isA<NovaDownloadError>()),
    );
    expect(server.hits.where((h) => h.endsWith('/steal')), isEmpty);
  }, skip: skip);

  test('downloadTorrent with a changed domain is refused as url-changed', () async {
    await expectLater(
      host.downloadTorrent(engine('fx_dl', pinned: ['elsewhere.test']), '${server.baseUrl}/a.torrent'),
      throwsA(isA<NovaDownloadError>().having((e) => e.reason, 'reason', urlChangedReason)),
    );
  }, skip: skip);

  test('downloadTorrent rejects a non-http url before starting anything', () async {
    await expectLater(host.downloadTorrent(engine('fx_dl'), 'file:///etc/passwd'),
        throwsA(isA<NovaDownloadError>().having((e) => e.reason, 'reason', 'bad-url')));
  }, skip: skip);
}
