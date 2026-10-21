import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:innertube/innertube.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('parseVideoPage: videos, live flag, duration, channel and next token', () {
    final page = parseVideoPage(fixture('search_page1.json'));
    expect(page.items.map((v) => v.videoId), ['aaaaaaaaaa1', 'aaaaaaaaaa2', 'aaaaaaaaaa3']);
    expect(page.items[0].title, 'First');
    expect(page.items[0].duration, const Duration(minutes: 3, seconds: 45));
    expect(page.items[1].duration, const Duration(hours: 1, minutes: 2, seconds: 3));
    expect(page.items[0].author, 'Chan One');
    expect(page.items[0].channelId, 'UC${'a' * 22}');
    expect(page.items[0].thumbnails.single.url, contains('aaaaaaaaaa1'));
    expect(page.items[2].isLive, isTrue);
    expect(page.items[2].duration, isNull);
    expect(page.items[0].isLive, isFalse);
    expect(page.continuation, 'TOKEN_PAGE_2');
  });

  test('continuation page: dedupes within the page, no further token', () {
    final page = parseVideoPage(fixture('search_page2.json'));
    expect(page.items.map((v) => v.videoId), ['aaaaaaaaaa4', 'aaaaaaaaaa1']);
    expect(page.continuation, isNull);
  });

  test('uploads: playlistVideoRenderer with lengthSeconds', () {
    final page = parseVideoPage(fixture('uploads_page1.json'));
    expect(page.items.map((v) => v.videoId), ['bbbbbbbbbb1', 'bbbbbbbbbb2']);
    expect(page.items[1].duration, const Duration(minutes: 1, seconds: 5));
    expect(page.continuation, 'UP_TOKEN');
  });

  test('parseClock', () {
    expect(parseClock('0:59'), const Duration(seconds: 59));
    expect(parseClock('LIVE'), isNull);
    expect(parseClock(''), isNull);
  });

  test('search pages through the continuation token', () async {
    final bodies = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      bodies.add(body);
      expect(request.url.path, '/youtubei/v1/search');
      final name = body.containsKey('continuation') ? 'search_page2.json' : 'search_page1.json';
      return http.Response(fixtureText(name), 200);
    });
    final browse = InnertubeBrowse(client: client);
    final first = await browse.search('kolaveri');
    final second = await browse.search('kolaveri', continuation: first.continuation);
    expect(bodies[0]['query'], 'kolaveri');
    expect(bodies[0]['params'], isNotNull);
    expect(bodies[1]['continuation'], 'TOKEN_PAGE_2');
    expect(bodies[1].containsKey('query'), isFalse);
    expect(second.continuation, isNull);
    expect(second.items, hasLength(2));
  });

  test('channelUploads browses the UU playlist; rejects a bad id', () async {
    late Map<String, dynamic> sent;
    final client = MockClient((request) async {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(fixtureText('uploads_page1.json'), 200);
    });
    final browse = InnertubeBrowse(client: client);
    final page = await browse.channelUploads('UC${'a' * 22}');
    expect(sent['browseId'], 'VLUU${'a' * 22}');
    expect(page.items, hasLength(2));
    expect(() => browse.channelUploads('nope'), throwsA(isA<InnertubeException>()));
  });

  test('videoDetails reads the player response', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/sw.js_data') return http.Response(swBody('V'), 200);
      return http.Response(fixtureText('player_vod.json'), 200);
    });
    final d = await InnertubeBrowse(client: client).videoDetails('FIXTUREVOD1');
    expect(d.title, 'Fixture Video');
    expect(d.duration, const Duration(seconds: 212));
  });
}
