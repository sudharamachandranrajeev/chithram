import 'dart:convert';

import 'package:iptv/iptv.dart';
import 'package:test/test.dart';

const sample = '''#EXTM3U x-tvg-url="https://epg.example.test/guide.xml.gz"
#EXTINF:-1 tvg-id="news1.test" tvg-name="News One" tvg-logo="https://img.example.test/n1.png" group-title="News, India" catchup="default" catchup-days="3" catchup-source="https://cu.example.test/{utc}",News One HD
#EXTVLCOPT:http-referrer=https://ref.example.test/
#EXTVLCOPT:http-user-agent=TestAgent/1.0
#KODIPROP:inputstream.adaptive.license_type=clearkey
https://s1.example.test/news1.m3u8
#EXTINF:-1 group-title="Sports",Cricket Live
http://s2.example.test/cric.ts

https://orphan.example.test/no-extinf.ts
#EXTINF:-1,
https://s3.example.test/noname.m3u8
''';

void main() {
  test('parses attributes, vlcopt, ignores kodiprop and orphans', () {
    final e = parseM3u(sample);
    expect(e, hasLength(3));
    expect(e[0].name, 'News One HD');
    expect(e[0].tvgId, 'news1.test');
    expect(e[0].group, 'News, India'); // comma inside quotes
    expect(e[0].logo, 'https://img.example.test/n1.png');
    expect(e[0].catchup, 'default');
    expect(e[0].catchupDays, 3);
    expect(e[0].catchupSource, 'https://cu.example.test/{utc}');
    expect(e[0].referrer, 'https://ref.example.test/');
    expect(e[0].userAgent, 'TestAgent/1.0');
    expect(e[0].headers, {
      'Referer': 'https://ref.example.test/',
      'User-Agent': 'TestAgent/1.0'
    });
    expect(e[1].referrer, isNull, reason: 'options do not leak to next entry');
    expect(e[1].group, 'Sports');
    expect(e[2].name, 'https://s3.example.test/noname.m3u8');
    expect(e[0].toString(), isNot(contains('example.test')));
  });

  test('stream parser equals string parser, chunked at odd boundaries', () async {
    final bytes = utf8.encode(sample);
    Stream<List<int>> chunks() async* {
      for (var i = 0; i < bytes.length; i += 7) {
        yield bytes.sublist(i, i + 7 > bytes.length ? bytes.length : i + 7);
      }
    }

    final got = await parseM3uStream(chunks()).toList();
    expect(got.map((e) => e.name), parseM3u(sample).map((e) => e.name));
  });

  test('limits', () async {
    expect(() => parseM3u(sample, limits: const M3uLimits(maxEntries: 1)),
        throwsA(isA<M3uLimitException>()));
    expect(() => parseM3u(sample, limits: const M3uLimits(maxBytes: 10)),
        throwsA(isA<M3uLimitException>()));
    expect(
        parseM3uStream(Stream.value(utf8.encode(sample)),
            limits: const M3uLimits(maxBytes: 10)).toList(),
        throwsA(isA<M3uLimitException>()));
    // Over-long line is skipped, not fatal.
    final long = '#EXTM3U\n#EXTINF:-1,${'x' * 100}\nhttp://a.example.test/x\n'
        '#EXTINF:-1,ok\nhttp://b.example.test/y\n';
    final e = parseM3u(long, limits: const M3uLimits(maxLineLength: 80));
    expect(e.map((x) => x.name), ['ok']);
  });

  test('garbage in does not throw', () {
    expect(parseM3u('\u0000\u0001 not a playlist\n#EXTINF\nhttp://x'), isEmpty);
    expect(parseM3u(''), isEmpty);
  });
}
