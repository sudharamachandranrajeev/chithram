import 'dart:convert';

import 'package:iptv/iptv.dart';
import 'package:test/test.dart';

import 'fake_http.dart';

/// Synthetic API: ids and hosts are made up.
FakeHttp api({bool blocklistFails = false}) {
  Handler json(Object o) => (_, _) => reply(200, jsonEncode(o));
  return FakeHttp({
    'https://api.example.test/blocklist.json': blocklistFails
        ? (_, _) => reply(500, '')
        : json([{'channel': 'Blocked.in', 'ref': 'https://ref.example.test'}]),
    'https://api.example.test/channels.json': json([
      {'id': 'MalSports.in', 'name': 'Mal Sports', 'country': 'IN', 'categories': ['sports']},
      {'id': 'TamNews.in', 'name': 'Tam News', 'country': 'IN', 'categories': ['news']},
      {'id': 'Blocked.in', 'name': 'Blocked', 'country': 'IN', 'categories': ['sports']},
      {'id': 'Adult.us', 'name': 'Adult', 'country': 'US', 'categories': ['xxx'], 'is_nsfw': true},
      {'id': 'Gone.in', 'name': 'Gone', 'country': 'IN', 'categories': ['sports'], 'closed': '2020-01-01'},
      {'id': 'UsSports.us', 'name': 'US Sports', 'country': 'US', 'categories': ['sports']},
    ]),
    'https://api.example.test/streams.json': json([
      {'channel': 'MalSports.in', 'url': 'https://s.example.test/a.m3u8', 'referrer': 'https://r.example.test/', 'user_agent': 'UA'},
      {'channel': 'MalSports.in', 'url': 'rtmp://s.example.test/skip'},
      {'channel': 'TamNews.in', 'url': 'https://s.example.test/b.m3u8'},
      {'channel': 'Blocked.in', 'url': 'https://s.example.test/c.m3u8'},
      {'channel': 'Adult.us', 'url': 'https://s.example.test/d.m3u8'},
      {'channel': 'Gone.in', 'url': 'https://s.example.test/e.m3u8'},
      {'channel': 'UsSports.us', 'url': 'https://s.example.test/f.m3u8'},
    ]),
    'https://api.example.test/feeds.json': json([
      {'channel': 'MalSports.in', 'id': 'SD', 'languages': ['mal']},
      {'channel': 'TamNews.in', 'id': 'SD', 'languages': ['tam']},
      {'channel': 'UsSports.us', 'id': 'SD', 'languages': ['eng']},
    ]),
    'https://api.example.test/categories.json': json([{'id': 'sports', 'name': 'Sports'}]),
    'https://api.example.test/countries.json': json([{'code': 'IN', 'name': 'India'}]),
    'https://api.example.test/languages.json': json([{'code': 'mal', 'name': 'Malayalam'}]),
    'https://api.example.test/guides.json': json([{'channel': 'MalSports.in', 'site': 'g.example.test', 'site_id': '1', 'lang': 'ml'}]),
  });
}

void main() {
  Future<Catalogue> load() =>
      IptvOrgClient(api(), baseUrl: 'https://api.example.test').load(withGuides: true);

  test('endpoints are the two allowed ones', () {
    expect(CatalogueEndpoints.iptvOrgApi, 'https://iptv-org.github.io/api');
    expect(CatalogueEndpoints.freeTvPlaylist,
        startsWith('https://raw.githubusercontent.com/Free-TV/IPTV/'));
  });

  test('blocklist, nsfw, closed and non-http are excluded by default', () async {
    final c = await load();
    final ids = c.select().map((e) => e.channel.id).toList();
    expect(ids, ['MalSports.in', 'TamNews.in', 'UsSports.us']);
    expect(c.select().first.streams, hasLength(1)); // rtmp dropped
    expect(c.select().first.streams.single.headers,
        {'Referer': 'https://r.example.test/', 'User-Agent': 'UA'});
    expect(c.guides, hasLength(1));
  });

  test('filters: country / language / category', () async {
    final c = await load();
    expect(c.select(country: 'in').length, 2);
    expect(c.select(country: 'IN', language: 'MAL').single.channel.id, 'MalSports.in');
    expect(c.select(language: 'tam').single.channel.id, 'TamNews.in');
    expect(c.select(category: 'Sports').map((e) => e.channel.id),
        ['MalSports.in', 'UsSports.us']);
    expect(c.select(country: 'IN', category: 'sports', language: 'mal'), hasLength(1));
    expect(c.select(allowNsfw: true).map((e) => e.channel.id), contains('Adult.us'));
    // Blocklist wins even with every opt-in.
    expect(c.select(allowNsfw: true, includeClosed: true).map((e) => e.channel.id),
        isNot(contains('Blocked.in')));
  });

  test('blocklist fetch failure fails the load', () async {
    await expectLater(
        IptvOrgClient(api(blocklistFails: true), baseUrl: 'https://api.example.test').load(),
        throwsA(isA<HttpStatusException>()));
  });
}
