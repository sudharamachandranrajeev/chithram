import 'package:innertube/innertube.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final streams = parsePlayerResponse(fixture('player_vod.json'),
      tier: Tier.visionos, userAgent: visionAgent, now: DateTime.utc(2026, 10, 20));

  test('4K-capable device with AV1: best height wins, AV1 preferred at equal height', () {
    final p = pickFormats(streams, const DeviceCaps());
    expect(p.isAdaptive, isTrue);
    expect(p.video!.itag, 313); // 2160p VP9 SDR (no AV1 2160 in the fixture)
    expect(p.audio!.itag, 251); // opus 150k, original track, not DRC, not dubbed
    expect(p.audio!.isDrc, isFalse);
    expect(p.audio!.isDefaultTrack, isTrue);
  });

  test('cap at 1080 picks AV1 over VP9 over H.264', () {
    expect(pickFormats(streams, const DeviceCaps(maxHeight: 1080)).video!.itag, 399);
    expect(
        pickFormats(streams, const DeviceCaps(maxHeight: 1080, videoCodecs: [VideoCodec.vp9, VideoCodec.h264]))
            .video!
            .itag,
        248);
    expect(pickFormats(streams, const DeviceCaps(maxHeight: 1080, videoCodecs: [VideoCodec.h264])).video!.itag, 137);
  });

  test('H.264-only device never gets a VP9/AV1 stream', () {
    final p = pickFormats(streams, const DeviceCaps(videoCodecs: [VideoCodec.h264]));
    expect(p.video!.videoCodec, VideoCodec.h264);
    expect(p.video!.itag, 137);
  });

  test('HDR only when preferred', () {
    expect(pickFormats(streams, const DeviceCaps()).video!.hdr, isFalse);
    final hdr = pickFormats(streams, const DeviceCaps(preferHdr: true));
    expect(hdr.video!.itag, 315);
    expect(hdr.video!.hdr, isTrue);
    // HDR preferred but capped below any HDR format: SDR.
    expect(pickFormats(streams, const DeviceCaps(preferHdr: true, maxHeight: 1080)).video!.hdr, isFalse);
  });

  test('audio codec order: prefers AAC when the device lists it first and bitrates are close', () {
    final p = pickFormats(streams, const DeviceCaps(audioCodecs: [AudioCodec.aac, AudioCodec.opus]));
    expect(p.audio!.itag, 140);
  });

  test('portrait Short counts by its short side', () {
    final short = VideoStreams(
      videoId: 's',
      tier: Tier.visionos,
      userAgent: '',
      video: [
        StreamFormat(itag: 1, url: Uri.parse('https://x/1'), videoCodec: VideoCodec.h264, width: 1080, height: 1920, bitrate: 1),
        StreamFormat(itag: 2, url: Uri.parse('https://x/2'), videoCodec: VideoCodec.h264, width: 720, height: 1280, bitrate: 1),
      ],
      audio: [StreamFormat(itag: 3, url: Uri.parse('https://x/3'), audioCodec: AudioCodec.aac, bitrate: 1)],
    );
    expect(pickFormats(short, const DeviceCaps(maxHeight: 1080)).video!.itag, 1);
    expect(pickFormats(short, const DeviceCaps(maxHeight: 720)).video!.itag, 2);
  });

  test('falls back to muxed when there is no adaptive video', () {
    final muxedOnly = VideoStreams(
        videoId: 'm', tier: Tier.explode, userAgent: '', muxed: streams.muxed, audio: streams.audio);
    final p = pickFormats(muxedOnly, const DeviceCaps());
    expect(p.isAdaptive, isFalse);
    expect(p.muxed!.itag, 22);
  });

  test('everything over the cap: smallest one over it', () {
    final p = pickFormats(streams, const DeviceCaps(maxHeight: 100));
    expect(p.video!.itag, 160);
  });

  test('live with no formats picks nothing', () {
    final live = parsePlayerResponse(fixture('player_live.json'),
        tier: Tier.visionos, userAgent: visionAgent, now: DateTime.utc(2026, 10, 20));
    expect(pickFormats(live, const DeviceCaps()).isEmpty, isTrue);
  });
}
