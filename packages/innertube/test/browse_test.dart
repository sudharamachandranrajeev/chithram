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

  test('related: lockup videos from /next, no playlists, not the video itself', () async {
    late http.Request sent;
    final client = MockClient((request) async {
      sent = request;
      return http.Response(fixtureText('next_related.json'), 200);
    });
    final items = await InnertubeBrowse(client: client, region: 'GB').related('seedseed001');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(sent.url.path, '/youtubei/v1/next');
    expect(body['videoId'], 'seedseed001');
    expect(body['context']['client']['gl'], 'GB');
    expect(items.map((v) => v.videoId), ['ccccccccc01', 'ccccccccc02']);
    final first = items.first;
    expect(first.title, 'Related One');
    expect(first.author, 'Chan C');
    expect(first.channelId, 'UC${'c' * 22}');
    expect(first.duration, const Duration(minutes: 3, seconds: 24));
    expect(first.viewsText, '208M views');
    expect(first.isLive, isFalse);
    expect(first.thumbnails.single.width, 336);
    expect(items[1].isLive, isTrue);
    expect(items[1].duration, isNull);
    expect(items[1].viewsText, '1.2K watching');
  });

  test('channelHome: every shelf, lockups and video renderers; rejects a bad id', () async {
    late Map<String, dynamic> sent;
    final client = MockClient((request) async {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(fixtureText('channel_home.json'), 200);
    });
    final browse = InnertubeBrowse(client: client);
    final items = await browse.channelHome('UC${'d' * 22}');
    expect(sent['browseId'], 'UC${'d' * 22}');
    expect(items.map((v) => v.title), ['Topic Lockup', 'Topic Video']);
    expect(items.first.viewsText, '5K views');
    expect(() => browse.channelHome('nope'), throwsA(isA<InnertubeException>()));
  });

  test('VideoItem survives JSON', () {
    const v = VideoItem(
      videoId: 'aaaaaaaaaa1',
      title: 'T',
      author: 'A',
      channelId: 'UCx',
      duration: Duration(seconds: 61),
      viewsText: '3 views',
      isLive: true,
      thumbnails: [ThumbnailInfo('u', width: 1, height: 2)],
    );
    final back = VideoItem.fromJson(jsonDecode(jsonEncode(v.toJson())) as Map<String, Object?>);
    expect(back.toJson(), v.toJson());
    expect(VideoItem.fromJson({'id': 'b', 'title': 'B'}).thumbnails, isEmpty);
  });
}
