import 'dart:convert';

import 'package:iptv/iptv.dart';
import 'package:test/test.dart';

import 'fake_http.dart';

void main() {
  final acc = XtreamAccount(
      baseUrl: 'http://panel.example.test:8080/', username: 'u', password: 'p@ss');
  String b64(String s) => base64.encode(utf8.encode(s));

  final http = FakeHttp({
    'http://panel.example.test:8080/player_api.php': (uri, _) {
      final q = uri.queryParameters;
      expect(q['username'], 'u');
      switch (q['action']) {
        case null:
          return reply(200, jsonEncode({
            'user_info': {
              'auth': 1, 'status': 'Active', 'exp_date': '1900000000',
              'max_connections': '2', 'active_cons': '0', 'is_trial': '0',
              'allowed_output_formats': ['m3u8', 'ts'],
            },
            'server_info': {'url': 'panel.example.test', 'port': '8080'},
          }));
        case 'get_live_categories':
          return reply(200, jsonEncode([{'category_id': '5', 'category_name': 'Sports'}]));
        case 'get_live_streams':
          return reply(200, jsonEncode([
            {'stream_id': 11, 'name': 'Sport 1', 'category_id': '5',
             'epg_channel_id': 'sp1.test', 'tv_archive': 1, 'tv_archive_duration': '3'},
            {'stream_id': 12, 'name': 'Plain', 'tv_archive': 0},
          ]));
        case 'get_short_epg':
          return reply(200, jsonEncode({'epg_listings': [
            {'title': b64('Match'), 'description': b64('Live'),
             'start_timestamp': '1900000000', 'stop_timestamp': '1900003600'},
          ]}));
      }
      return reply(404, '');
    },
  });
  final x = XtreamClient(acc, http);

  test('auth, categories, streams, epg', () async {
    final a = await x.authenticate();
    expect(a.authenticated, isTrue);
    expect(a.maxConnections, 2);
    expect(a.allowedOutputFormats, ['m3u8', 'ts']);
    expect((await x.liveCategories()).single.name, 'Sports');
    final s = await x.liveStreams();
    expect(s.first.tvArchive, isTrue);
    expect(s.first.tvArchiveDuration, 3);
    expect(s.last.epgChannelId, isNull);
    final e = await x.shortEpg(11);
    expect(e.single.title, 'Match');
    expect(e.single.end.difference(e.single.start), const Duration(hours: 1));
  });

  test('url builders', () {
    expect(x.liveUrl(11).toString(),
        'http://panel.example.test:8080/live/u/p@ss/11.m3u8');
    expect(x.liveUrl(11, ext: 'ts').path, endsWith('/11.ts'));
    expect(x.vodUrl(7, ext: 'mkv').path, '/movie/u/p@ss/7.mkv');
    expect(x.seriesEpisodeUrl(9).path, '/series/u/p@ss/9.mp4');
    expect(
        x.timeshiftUrl(11,
                start: DateTime.utc(2026, 1, 2, 3, 4),
                duration: const Duration(minutes: 90))
            .path,
        '/timeshift/u/p@ss/90/2026-01-02:03-04/11.ts');
    expect(x.xmltvUrl.path, '/xmltv.php');
    expect(x.xmltvUrl.queryParameters['username'], 'u');
  });

  test('http warning flag and no credential leakage', () async {
    expect(acc.insecure, isTrue);
    expect(XtreamAccount(baseUrl: 'https://a.example.test', username: 'u', password: 'p').insecure, isFalse);
    expect(acc.toString(), isNot(contains('p@ss')));
    final bad = XtreamClient(
        XtreamAccount(baseUrl: 'http://nope.example.test', username: 'u', password: 'secret123'),
        http);
    await expectLater(
        bad.authenticate(),
        throwsA(predicate((e) => !e.toString().contains('secret123'))));
  });
}
