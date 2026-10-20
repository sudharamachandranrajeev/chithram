import 'package:innertube/innertube.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final now = DateTime.utc(2026, 10, 20);

  group('parsePlayerResponse', () {
    final streams = parsePlayerResponse(fixture('player_vod.json'),
        tier: Tier.visionos, userAgent: visionAgent, now: now);

    test('details', () {
      expect(streams.title, 'Fixture Video');
      expect(streams.author, 'Fixture Channel');
      expect(streams.duration, const Duration(seconds: 212));
      expect(streams.isLive, isFalse);
      expect(streams.hlsManifestUrl, isNull);
      expect(streams.tier, Tier.visionos);
      expect(streams.thumbnails, hasLength(2));
      expect(streams.thumbnails.last.url, 'https://i.ytimg.com/vi/FIXTUREVOD1/maxresdefault.jpg');
    });

    test('splits muxed, video and audio; drops cipher-only formats', () {
      expect(streams.muxed.map((f) => f.itag), [18, 22]);
      expect(streams.video.map((f) => f.itag), [137, 248, 399, 271, 313, 315, 160]);
      expect(streams.audio, hasLength(5));
      expect(streams.video.any((f) => f.itag == 299), isFalse);
    });

    test('codecs, size, fps, length', () {
      final h264 = streams.video.firstWhere((f) => f.itag == 137);
      expect(h264.videoCodec, VideoCodec.h264);
      expect(h264.container, 'mp4');
      expect(h264.width, 1920);
      expect(h264.height, 1080);
      expect(h264.fps, 30);
      expect(h264.bitrate, 4000000);
      expect(h264.contentLength, 50000000);
      expect(streams.video.firstWhere((f) => f.itag == 248).videoCodec, VideoCodec.vp9);
      expect(streams.video.firstWhere((f) => f.itag == 248).container, 'webm');
      expect(streams.video.firstWhere((f) => f.itag == 399).videoCodec, VideoCodec.av1);
      expect(streams.audio.firstWhere((f) => f.itag == 140).audioCodec, AudioCodec.aac);
      expect(streams.audio.firstWhere((f) => f.itag == 250).audioCodec, AudioCodec.opus);
      expect(streams.muxed.first.hasAudio && streams.muxed.first.hasVideo, isTrue);
    });

    test('hdr, drc and dubbed flags', () {
      expect(streams.video.firstWhere((f) => f.itag == 315).hdr, isTrue);
      expect(streams.video.firstWhere((f) => f.itag == 313).hdr, isFalse);
      expect(streams.audio.where((f) => f.isDrc), hasLength(1));
      expect(streams.audio.where((f) => !f.isDefaultTrack), hasLength(1));
    });

    test('expiry comes from the url', () {
      expect(streams.expires, DateTime.fromMillisecondsSinceEpoch(1790000000 * 1000, isUtc: true));
    });

    test('live response keeps the HLS manifest', () {
      final live = parsePlayerResponse(fixture('player_live.json'),
          tier: Tier.visionos, userAgent: visionAgent, now: now);
      expect(live.isLive, isTrue);
      expect(live.hlsManifestUrl.toString(), contains('index.m3u8'));
      expect(live.duration, isNull);
      expect(live.hasFormats, isFalse);
    });

    test('LOGIN_REQUIRED throws loginRequired', () {
      expect(
          () => parsePlayerResponse(fixture('player_login_required.json'), tier: Tier.visionos, userAgent: ''),
          throwsA(isA<PlayabilityException>().having((e) => e.loginRequired, 'loginRequired', isTrue)));
    });

    test('unplayable reason is whitespace-squashed', () {
      expect(
          () => parsePlayerResponse(fixture('player_unplayable.json'), tier: Tier.tv, userAgent: ''),
          throwsA(isA<PlayabilityException>()
              .having((e) => e.reason, 'reason', 'Video unavailable in your country')
              .having((e) => e.loginRequired, 'loginRequired', isFalse)));
    });

    test('video details', () {
      final d = parseVideoDetails(fixture('player_vod.json'));
      expect(d.title, 'Fixture Video');
      expect(d.channelId, 'UCfixture0000000000000000');
      expect(d.viewCount, 12345);
      expect(d.description, 'A fixture.');
    });
  });

  group('rangedHeaders', () {
    test('always sends Range', () {
      expect(rangedHeaders('UA'), {'User-Agent': 'UA', 'Range': 'bytes=0-'});
      expect(rangedHeaders('UA', from: 10, to: 19)['Range'], 'bytes=10-19');
    });
  });
}
