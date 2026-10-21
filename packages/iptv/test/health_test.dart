import 'dart:async';
import 'dart:typed_data';

import 'package:iptv/iptv.dart';
import 'package:test/test.dart';

import 'fake_http.dart';

Uint8List ts(int packets, {int breakAt = -1}) {
  final b = Uint8List(188 * packets);
  for (var i = 0; i < packets; i++) {
    b[i * 188] = i == breakAt ? 0x00 : 0x47;
  }
  return b;
}

StoredChannel ch(int i) => StoredChannel(
    key: 'k$i', sourceId: 's', name: 'c$i', url: 'https://h.example.test/$i');

void main() {
  test('classify HLS / TS / junk', () {
    Uint8List s(String x) => Uint8List.fromList(x.codeUnits);
    expect(classifyProbeBytes(s('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nv.m3u8'), null).ok, isTrue);
    expect(classifyProbeBytes(s('#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\nx.ts'), null).ok, isTrue);
    expect(classifyProbeBytes(s('#EXTM3U\n'), null).ok, isFalse);
    expect(classifyProbeBytes(s('<html>nope'), 'text/html').ok, isFalse);
    expect(classifyProbeBytes(ts(3), null).kind, StreamKind.mpegTs);
    expect(classifyProbeBytes(ts(3), null).ok, isTrue);
    expect(classifyProbeBytes(ts(3, breakAt: 1), null).ok, isFalse);
    expect(classifyProbeBytes(Uint8List(0), null).ok, isFalse);
    expect(classifyProbeBytes(Uint8List.fromList([1, 2, 3]), 'video/mp4').ok, isTrue);
  });

  test('pool: 8 concurrent max, marks dead only after 2 failures, caches 24 h', () async {
    var now = DateTime.utc(2026, 1, 1);
    final http = FakeHttp({
      'https://h.example.test/': (uri, _) {
        final n = int.parse(uri.pathSegments.last);
        if (n % 2 == 0) return reply(200, ts(3));
        return reply(404, '');
      },
    });
    final pool = ProbePool(http);
    final store = InMemoryIptvStore();
    final chans = [for (var i = 0; i < 40; i++) ch(i)];

    var out = await pool.run(chans, store, now: now);
    expect(http.maxInFlight, lessThanOrEqualTo(8));
    expect(http.maxInFlight, greaterThan(1));
    expect(out.where((c) => c.dead), isEmpty, reason: 'one failure is not dead yet');
    expect(http.requests, hasLength(40));

    // Within TTL: no new requests.
    await pool.run(out, store, now: now.add(const Duration(hours: 23)));
    expect(http.requests, hasLength(40));

    // After TTL: re-probed, second failure marks dead; alive ones stay alive.
    now = now.add(const Duration(hours: 25));
    out = await pool.run(out, store, now: now);
    expect(http.requests, hasLength(80));
    expect(out.where((c) => c.dead), hasLength(20));
    expect(out, hasLength(40), reason: 'dead channels are kept');
    expect(out.firstWhere((c) => c.dead).deadSince, now.toUtc());
    expect(out.firstWhere((c) => !c.dead).ttfbMs, isNotNull);
  });

  test('timeout becomes a failed result, not an exception', () async {
    final http = _Hang();
    final r = await ProbePool(http, timeout: const Duration(milliseconds: 50))
        .probe(Uri.parse('https://h.example.test/x'));
    expect(r.ok, isFalse);
    expect(r.error, isNotNull);
  });
}

class _Hang implements IptvHttp {
  @override
  Future<IptvResponse> open(Uri uri,
      {Map<String, String> headers = const {},
      Duration timeout = const Duration(seconds: 15)}) async {
    return IptvResponse(
        status: 200,
        headers: {},
        body: Stream<List<int>>.fromFuture(Completer<List<int>>().future),
        ttfb: Duration.zero);
  }
}
