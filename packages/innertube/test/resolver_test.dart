import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:innertube/innertube.dart';
import 'package:test/test.dart';

import 'helpers.dart';

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// Routes sw.js_data and /player by client name.
class FakeYouTube {
  FakeYouTube(this.onPlayer);
  final FutureOr<http.Response> Function(String clientName, String visitorHeader, int swCalls) onPlayer;
  int swCalls = 0;
  final playerCalls = <String>[];

  late final http.Client client = MockClient((request) async {
    if (request.url.path == '/sw.js_data') {
      swCalls++;
      return http.Response(swBody('VISITOR_$swCalls'), 200);
    }
    if (request.url.path == '/youtubei/v1/player') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final name = (body['context'] as Map)['client']['clientName'] as String;
      playerCalls.add(name);
      return onPlayer(name, request.headers['X-Goog-Visitor-Id'] ?? '', swCalls);
    }
    return http.Response('not found', 404);
  });
}

VideoStreams explodeStub(String id) => VideoStreams(
      videoId: id,
      tier: Tier.explode,
      userAgent: browserAgent,
      muxed: [StreamFormat(itag: 18, url: Uri.parse('https://x/18'), videoCodec: VideoCodec.h264, audioCodec: AudioCodec.aac, height: 360, width: 640)],
    );

void main() {
  test('VISIONOS wins; visitor data is cached across videos', () async {
    final fake = FakeYouTube((name, visitor, _) => json(fixture('player_vod.json')));
    final resolver = YouTubeResolver(client: fake.client, explode: (id) async => explodeStub(id));
    final a = await resolver.resolve('FIXTUREVOD1');
    await resolver.resolve('FIXTUREVOD1');
    expect(a.tier, Tier.visionos);
    expect(a.attempts.single.ok, isTrue);
    expect(fake.swCalls, 1);
    expect(fake.playerCalls, ['VISIONOS', 'VISIONOS']);
  });

  test('LOGIN_REQUIRED refreshes visitor data and retries on VISIONOS', () async {
    final fake = FakeYouTube((name, visitor, sw) =>
        visitor == 'VISITOR_1' ? json(fixture('player_login_required.json')) : json(fixture('player_vod.json')));
    final resolver = YouTubeResolver(client: fake.client, explode: (id) async => explodeStub(id));
    final r = await resolver.resolve('FIXTUREVOD1');
    expect(r.tier, Tier.visionos);
    expect(fake.swCalls, 2);
    expect(fake.playerCalls, ['VISIONOS', 'VISIONOS']);
    // The new id is cached for the next video.
    await resolver.resolve('FIXTUREVOD1');
    expect(fake.swCalls, 2);
  });

  test('falls through VISIONOS (403), android_vr (login) to tv', () async {
    final fake = FakeYouTube((name, visitor, _) {
      switch (name) {
        case 'VISIONOS':
          return http.Response('no', 403);
        case 'ANDROID_VR':
          return json(fixture('player_login_required.json'));
        default:
          return json(fixture('player_vod.json'));
      }
    });
    final resolver = YouTubeResolver(client: fake.client, explode: (id) async => explodeStub(id));
    final r = await resolver.resolve('FIXTUREVOD1');
    expect(r.tier, Tier.tv);
    expect(r.userAgent, tvClient.userAgent);
    expect(r.attempts.map((a) => a.tier), [Tier.visionos, Tier.androidVr, Tier.tv]);
    expect(r.attempts.map((a) => a.ok), [false, false, true]);
    expect(r.attempts.first.error, contains('403'));
    expect(r.attempts[1].error, contains('LOGIN_REQUIRED'));
    // android_vr does not refresh visitor data: only the VISIONOS tier does.
    expect(fake.swCalls, 1);
  });

  test('a hanging tier times out and the next one answers', () async {
    final fake = FakeYouTube((name, visitor, _) =>
        name == 'VISIONOS' ? Completer<http.Response>().future : json(fixture('player_vod.json')));
    final resolver = YouTubeResolver(
      client: fake.client,
      timeouts: const {
        Tier.visionos: Duration(milliseconds: 50),
        Tier.androidVr: Duration(seconds: 2),
        Tier.tv: Duration(seconds: 2),
        Tier.explode: Duration(seconds: 2),
      },
    );
    final r = await resolver.resolve('FIXTUREVOD1');
    expect(r.tier, Tier.androidVr);
    expect(r.attempts.first.ok, isFalse);
  });

  test('all InnerTube tiers fail: youtube_explode answers', () async {
    final fake = FakeYouTube((name, visitor, _) => json(fixture('player_unplayable.json')));
    final resolver = YouTubeResolver(client: fake.client, explode: (id) async => explodeStub(id));
    final r = await resolver.resolve('FIXTUREVOD1');
    expect(r.tier, Tier.explode);
    expect(r.attempts, hasLength(4));
    expect(r.attempts.take(3).every((a) => !a.ok), isTrue);
  });

  test('live video resolves to an HLS manifest', () async {
    final fake = FakeYouTube((name, visitor, _) => json(fixture('player_live.json')));
    final resolver = YouTubeResolver(client: fake.client);
    final r = await resolver.resolve('FIXTURELIVE1');
    expect(r.isLive, isTrue);
    expect(r.hlsManifestUrl, isNotNull);
  });

  test('everything fails: AllTiersFailed lists each tier', () async {
    final fake = FakeYouTube((name, visitor, _) => json(fixture('player_unplayable.json')));
    final resolver = YouTubeResolver(client: fake.client, explode: (id) async => throw InnertubeException('boom'));
    await expectLater(
      resolver.resolve('FIXTUREVOD1'),
      throwsA(isA<AllTiersFailed>()
          .having((e) => e.attempts, 'attempts', hasLength(4))
          .having((e) => e.message, 'message', allOf(contains('visionos'), contains('explode: boom')))),
    );
  });

  test('the player request carries the VISIONOS identity and visitor data', () async {
    late http.Request seen;
    final client = MockClient((request) async {
      if (request.url.path == '/sw.js_data') return http.Response(swBody('V'), 200);
      seen = request;
      return json(fixture('player_vod.json'));
    });
    await YouTubeResolver(client: client).resolve('FIXTUREVOD1');
    final body = jsonDecode(seen.body) as Map<String, dynamic>;
    final c = (body['context'] as Map)['client'] as Map;
    expect(c['clientName'], 'VISIONOS');
    expect(c['visitorData'], 'V');
    expect(body['videoId'], 'FIXTUREVOD1');
    expect(seen.headers['X-YouTube-Client-Name'], '101');
    expect(seen.headers['X-Goog-Visitor-Id'], 'V');
  });
}
