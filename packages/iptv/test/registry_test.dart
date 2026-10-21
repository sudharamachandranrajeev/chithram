import 'dart:io';
import 'dart:convert';

import 'package:iptv/iptv.dart';
import 'package:test/test.dart';

import 'fake_http.dart';

String pl(List<String> names) =>
    '#EXTM3U\n${[for (final n in names) '#EXTINF:-1 tvg-id="$n.test" group-title="G",$n\nhttps://s.example.test/$n.m3u8'].join('\n')}\n';

void main() {
  var clock = DateTime.utc(2026, 1, 1);
  late InMemoryIptvStore store;
  var body = pl(['a', 'b']);
  var fail = false;
  late FakeHttp http;
  late SourceRegistry reg;

  setUp(() {
    clock = DateTime.utc(2026, 1, 1);
    store = InMemoryIptvStore();
    body = pl(['a', 'b']);
    fail = false;
    http = FakeHttp({
      'https://list.example.test/p.m3u': (uri, h) {
        if (fail) return reply(503, '');
        if (h['If-None-Match'] == '"v1"' && body == pl(['a', 'b'])) {
          return reply(304, '');
        }
        return reply(200, body, headers: {'etag': '"v1"'});
      },
    });
    reg = SourceRegistry(store, http, maxFailures: 3, clock: () => clock);
  });

  Source m3u() => Source(
      id: 's1', kind: SourceKind.m3uUrl, name: 'T', location: 'https://list.example.test/p.m3u');

  test('first refresh adds channels; ETag makes next one a 304', () async {
    await reg.add(m3u());
    final r = await reg.refresh('s1');
    expect(r.status, RefreshStatus.updated);
    expect(r.added, 2);
    expect((await store.channels('s1')).map((c) => c.name), ['a', 'b']);
    clock = clock.add(const Duration(hours: 13));
    final r2 = await reg.refresh('s1');
    expect(r2.status, RefreshStatus.notModified);
    expect(http.headersSeen.last['If-None-Match'], '"v1"');
  });

  test('due respects 12 h default interval', () async {
    await reg.add(m3u());
    expect(await reg.due(), hasLength(1));
    await reg.refresh('s1');
    clock = clock.add(const Duration(hours: 11));
    expect(await reg.due(), isEmpty);
    clock = clock.add(const Duration(hours: 2));
    expect(await reg.due(), hasLength(1));
    expect((await reg.refreshDue()).single.sourceId, 's1');
  });

  test('new channels added, vanished ones marked missing not deleted, health kept', () async {
    await reg.add(m3u());
    await reg.refresh('s1');
    final cs = await store.channels('s1');
    await store.replaceChannels('s1', [
      cs[0].copyWith(dead: true, deadSince: clock),
      cs[1],
    ]);
    body = pl(['a', 'c']);
    clock = clock.add(const Duration(hours: 13));
    final r = await reg.refresh('s1');
    expect(r.added, 1);
    expect(r.removed, 1);
    final by = {for (final c in await store.channels('s1')) c.name: c};
    expect(by.keys, containsAll(['a', 'b', 'c']));
    expect(by['b']!.missing, isTrue);
    expect(by['b']!.playable, isFalse);
    expect(by['c']!.firstSeen, clock);
    expect(by['a']!.dead, isTrue, reason: 'health survives refresh');
  });

  test('N consecutive failures deprecate and auto-disable; success resets', () async {
    await reg.add(m3u());
    fail = true;
    expect((await reg.refresh('s1')).status, RefreshStatus.failed);
    expect((await reg.refresh('s1')).status, RefreshStatus.failed);
    fail = false;
    await reg.refresh('s1');
    expect((await store.sources()).single.failures, 0);
    fail = true;
    await reg.refresh('s1');
    await reg.refresh('s1');
    final r = await reg.refresh('s1');
    expect(r.status, RefreshStatus.deprecated);
    final s = (await store.sources()).single;
    expect(s.deprecated, isTrue);
    expect(s.enabled, isFalse);
    expect(await reg.due(), isEmpty);
    expect((await reg.refresh('s1')).status, RefreshStatus.skipped);
    // Channels from before are kept.
    await reg.enable('s1');
    expect((await store.sources()).single.active, isTrue);
  });

  test('empty playlist counts as failure', () async {
    await reg.add(m3u());
    body = '#EXTM3U\n';
    final r = await reg.refresh('s1');
    expect(r.status, RefreshStatus.failed);
  });

  test('xtream source: channels hold no password, URL resolved on demand', () async {
    final x = FakeHttp({
      'https://panel.example.test/player_api.php': (uri, _) {
        switch (uri.queryParameters['action']) {
          case null:
            return reply(200, jsonEncode({'user_info': {'auth': 1, 'status': 'Active'}}));
          case 'get_live_categories':
            return reply(200, jsonEncode([{'category_id': '1', 'category_name': 'Sports'}]));
          case 'get_live_streams':
            return reply(200, jsonEncode([{'stream_id': 5, 'name': 'X', 'category_id': '1'}]));
        }
        return reply(404, '');
      },
    });
    final r = SourceRegistry(store, x, clock: () => clock);
    await r.add(
        Source(id: 'x', kind: SourceKind.xtream, name: 'X', location: 'https://panel.example.test', username: 'u'),
        password: 'topsecret');
    expect((await r.refresh('x')).status, RefreshStatus.updated);
    final c = (await store.channels('x')).single;
    expect(jsonEncode(c.toJson()), isNot(contains('topsecret')));
    expect(jsonEncode((await store.sources()).single.toJson()), isNot(contains('topsecret')));
    expect(c.group, 'Sports');
    expect((await r.resolveUrl(c))!.toString(),
        'https://panel.example.test/live/u/topsecret/5.m3u8');
  });

  test('catalogue subscription: new channel appears on next refresh', () async {
    var channels = [
      {'id': 'A.in', 'name': 'A', 'country': 'IN', 'categories': ['sports']},
    ];
    final h = FakeHttp({
      'https://api.example.test/blocklist': (_, _) => reply(200, '[]'),
      'https://api.example.test/channels': (_, _) => reply(200, jsonEncode(channels)),
      'https://api.example.test/streams': (_, _) => reply(200, jsonEncode([
            for (final c in channels) {'channel': c['id'], 'url': 'https://s.example.test/${c['id']}.m3u8'}
          ])),
      'https://api.example.test/feeds': (_, _) => reply(200, jsonEncode([
            for (final c in channels) {'channel': c['id'], 'id': 'SD', 'languages': ['mal']}
          ])),
      'https://api.example.test/': (_, _) => reply(200, '[]'),
    });
    final r = SourceRegistry(store, h, clock: () => clock);
    await r.add(Source(
        id: 'c', kind: SourceKind.catalogue, name: 'iptv-org',
        location: 'https://api.example.test', filterCountry: 'IN', filterLanguage: 'mal'));
    expect((await r.refresh('c')).added, 1);
    channels = [...channels, {'id': 'B.in', 'name': 'B', 'country': 'IN', 'categories': ['news']}];
    clock = clock.add(const Duration(hours: 13));
    final res = await r.refresh('c');
    expect(res.added, 1);
    expect((await store.channels('c')).map((c) => c.name), ['A', 'B']);
  });

  test('json file store round trip', () async {
    final dir = Directory.systemTemp.createTempSync('iptvstore');
    final fs = JsonFileIptvStore(dir);
    final r = SourceRegistry(fs, http, clock: () => clock);
    await r.add(m3u());
    await r.refresh('s1');
    final again = JsonFileIptvStore(dir);
    expect((await again.sources()).single.etag, '"v1"');
    expect(await again.channels('s1'), hasLength(2));
    await again.saveProbes({'k': ProbeResult(ok: true, checkedAt: clock, kind: StreamKind.hls)});
    expect((await JsonFileIptvStore(dir).probes())['k']!.kind, StreamKind.hls);
    await again.deleteSource('s1');
    expect(await again.channels('s1'), isEmpty);
  });
}
