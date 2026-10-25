import 'dart:io';

import 'package:test/test.dart';
import 'package:web_media/src/unpack.dart';
import 'package:web_media/web_media.dart';

final _page = Uri.parse('https://videos.example/watch/42');

void main() {
  group('isAdUrl', () {
    test('ad hosts, paths and files', () {
      for (final u in [
        'https://ads.example.net/v.mp4',
        'https://cdn.adserver.example/x.m3u8',
        'https://cdn.example/vast/tag.xml',
        'https://cdn.example/media/preroll/clip.mp4',
        'https://cdn.example/media/preroll_15s.mp4',
        'https://cdn.example/a/vmap.xml',
      ]) {
        expect(isAdUrl(Uri.parse(u)), isTrue, reason: u);
      }
    });

    test('ordinary media is not an ad', () {
      for (final u in [
        'https://cdn.example/hls/master.m3u8',
        'https://downloads.example/adventure-time.mp4',
        'https://road.example/video/720/movie.mp4',
        'https://cdn.example/shadows.mkv',
      ]) {
        expect(isAdUrl(Uri.parse(u)), isFalse, reason: u);
      }
    });
  });

  group('scanPage', () {
    test('finds video tags, sources and player configs; skips ads', () {
      const html = '''
<html><head><title>Episode 1 &amp; more</title>
<meta property="og:video" content="https://cdn.example/og.mp4"></head>
<body>
<video src="/media/main.mp4"></video>
<video><source src="https://cdn.example/hd.mp4" type="video/mp4" label="1080p"></video>
<script>
jwplayer("p").setup({sources:[{file:"https:\\/\\/cdn.example\\/hls\\/index.m3u8",label:"720p"}],
  advertising:{tag:"https://ads.example.net/vast.xml", schedule:"https://cdn.example/preroll/ad.mp4"}});
</script>
<iframe src="//player.example/embed/9"></iframe>
<iframe src="https://ads.example.net/banner.html"></iframe>
<a href="/watch/43"><img src="/t/43.jpg" alt="Episode 2">Episode 2</a>
<a href="/watch/43">Episode 2 again</a>
<a href="#top">Top</a>
<a href="https://ads.example.net/click">Win</a>
<a href="javascript:void(0)">Menu</a>
</body></html>''';
      final scan = scanPage(html, _page);
      expect(scan.title, 'Episode 1 & more');
      final urls = scan.media.map((m) => m.url.toString()).toList();
      expect(urls, containsAll([
        'https://cdn.example/og.mp4',
        'https://videos.example/media/main.mp4',
        'https://cdn.example/hd.mp4',
        'https://cdn.example/hls/index.m3u8',
      ]));
      expect(urls.any((u) => u.contains('ads.') || u.contains('preroll')), isFalse);
      // 1080p first, then 720p.
      expect(scan.media.first.url.toString(), 'https://cdn.example/hd.mp4');
      expect(scan.media[1].kind, MediaKind.hls);
      expect(scan.media.first.headers['Referer'], _page.toString());
      expect(scan.frames, [Uri.parse('https://player.example/embed/9')]);
      expect(scan.links.map((l) => l.text), ['Episode 2']);
      expect(scan.links.single.url.toString(), 'https://videos.example/watch/43');
      expect(scan.links.single.image.toString(), 'https://videos.example/t/43.jpg');
    });

    test('reads packed player scripts', () {
      // eval(function(p,a,c,k,e,d){...}('0 1="2://3.4/5.6"',10,7,'var|src|https|cdn|example|hls|m3u8'.split('|'),0,{}))
      const packed = "eval(function(p,a,c,k,e,d){while(c--)if(k[c])p=p.replace(new RegExp('\\\\b'+c.toString(a)+'\\\\b','g'),k[c]);return p}"
          "('0 1=\"2://3.4/5/a.6\"',10,7,'var|src|https|cdn|example|hls|m3u8'.split('|'),0,{}))";
      expect(unpackAll(packed), ['var src="https://cdn.example/hls/a.m3u8"']);
      final scan = scanPage('<script>$packed</script>', _page);
      expect(scan.media.single.url.toString(), 'https://cdn.example/hls/a.m3u8');
    });
  });

  group('rewritePlaylist', () {
    final base = Uri.parse('https://cdn.example/hls/v/index.m3u8');

    test('drops cue-out breaks and ad segments, keeps keys and discontinuities right', () {
      const text = '''#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:6
#EXT-X-MEDIA-SEQUENCE:0
#EXT-X-KEY:METHOD=AES-128,URI="key1"
#EXTINF:6,
s0.ts
#EXT-X-CUE-OUT:12
#EXTINF:6,
ad0.ts
#EXT-X-CUE-OUT-CONT
#EXTINF:6,
ad1.ts
#EXT-X-CUE-IN
#EXTINF:6,
s1.ts
#EXTINF:6,
https://ads.example.net/x.ts
#EXTINF:6,
s2.ts
#EXT-X-ENDLIST
''';
      final out = rewritePlaylist(text, base);
      expect(out, isNot(contains('ad0')));
      expect(out, isNot(contains('ad1')));
      expect(out, isNot(contains('ads.example')));
      expect(out, isNot(contains('CUE')));
      expect(out.split('\n'), [
        '#EXTM3U',
        '#EXT-X-VERSION:3',
        '#EXT-X-TARGETDURATION:6',
        '#EXT-X-MEDIA-SEQUENCE:0',
        '#EXT-X-KEY:METHOD=AES-128,URI="https://cdn.example/hls/v/key1"',
        '#EXTINF:6,',
        'https://cdn.example/hls/v/s0.ts',
        '#EXT-X-DISCONTINUITY',
        '#EXTINF:6,',
        'https://cdn.example/hls/v/s1.ts',
        '#EXT-X-DISCONTINUITY',
        '#EXTINF:6,',
        'https://cdn.example/hls/v/s2.ts',
        '#EXT-X-ENDLIST',
        '',
      ]);
    });

    test('drops a short stitched-in run from another host', () {
      final main = [for (var i = 0; i < 20; i++) '#EXTINF:6,\ns$i.ts'];
      final text = [
        '#EXTM3U', '#EXT-X-TARGETDURATION:6', ...main.take(10), //
        '#EXT-X-DISCONTINUITY', '#EXTINF:15,', 'https://stitch.example/p/1.ts', '#EXTINF:15,', 'https://stitch.example/p/2.ts',
        '#EXT-X-DISCONTINUITY', ...main.skip(10), '#EXT-X-ENDLIST',
      ].join('\n');
      final out = rewritePlaylist(text, base);
      expect(out, isNot(contains('stitch.example')));
      expect('#EXT-X-DISCONTINUITY'.allMatches(out).length, 1);
      expect(out, contains('s19.ts'));
    });

    test('routes variants and renditions of a multivariant playlist', () {
      const text = '''#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="en",URI="audio/en.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=1280x720,AUDIO="a"
720/index.m3u8
''';
      final routed = <Uri>[];
      final out = rewritePlaylist(text, base, route: (u) {
        routed.add(u);
        return Uri.parse('http://127.0.0.1:1/t/${routed.length}.m3u8');
      });
      expect(routed.map((u) => u.toString()), [
        'https://cdn.example/hls/v/audio/en.m3u8',
        'https://cdn.example/hls/v/720/index.m3u8',
      ]);
      expect(out, contains('URI="http://127.0.0.1:1/t/1.m3u8"'));
      expect(out, contains('\nhttp://127.0.0.1:1/t/2.m3u8\n'));
    });
  });

  group('WebMediaResolver', () {
    test('follows frames with the parent as Referer and skips local frames', () async {
      final asked = <String, String?>{};
      Future<FetchedPage?> fetch(Uri url, {Map<String, String> headers = const {}}) async {
        asked[url.toString()] = headers['Referer'];
        return switch (url.toString()) {
          'https://videos.example/watch/42' => FetchedPage(
              url: url,
              contentType: 'text/html',
              body: '<iframe src="https://player.example/e/1"></iframe><iframe src="http://192.168.1.1/"></iframe>'),
          'https://player.example/e/1' =>
            FetchedPage(url: url, contentType: 'text/html', body: '<script>var f="https://cdn.example/s.m3u8";</script>'),
          _ => null,
        };
      }

      final scan = await WebMediaResolver(fetch: fetch).scan(_page);
      expect(scan!.media.single.url.toString(), 'https://cdn.example/s.m3u8');
      expect(scan.media.single.referer.toString(), 'https://player.example/e/1');
      expect(asked['https://player.example/e/1'], _page.toString());
      expect(asked.containsKey('http://192.168.1.1/'), isFalse);
    });

    test('isLocalHost', () {
      for (final h in ['localhost', '127.0.0.1', '10.0.0.2', '192.168.0.9', '172.20.1.1', 'tv.local', '[::1]', 'fd00::1']) {
        expect(isLocalHost(h), isTrue, reason: h);
      }
      for (final h in ['example.org', '8.8.8.8', '172.32.0.1']) {
        expect(isLocalHost(h), isFalse, reason: h);
      }
    });
  });

  test('HlsAdProxy serves only registered playlists, filtered', () async {
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin.listen((req) {
      req.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl');
      req.response.write(req.uri.path == '/v.m3u8'
          ? '#EXTM3U\n#EXTINF:6,\na.ts\n#EXT-X-CUE-OUT:6\n#EXTINF:6,\nad.ts\n#EXT-X-CUE-IN\n#EXTINF:6,\nb.ts\n#EXT-X-ENDLIST\n'
          : 'nope');
      req.response.close();
    });
    final proxy = HlsAdProxy();
    addTearDown(() async {
      await proxy.close();
      await origin.close(force: true);
    });
    final local = await proxy.wrap(Uri.parse('http://127.0.0.1:${origin.port}/v.m3u8'), {'Referer': 'https://x/'});
    final client = HttpClient();
    addTearDown(client.close);
    Future<(int, String)> get(Uri u) async {
      final res = await (await client.getUrl(u)).close();
      return (res.statusCode, await res.transform(const SystemEncoding().decoder).join());
    }

    final (status, body) = await get(local);
    expect(status, 200);
    expect(body, contains('/a.ts'));
    expect(body, contains('/b.ts'));
    expect(body, isNot(contains('ad.ts')));
    final other = local.replace(path: local.path.replaceFirst(RegExp(r'\d+\.m3u8$'), '999.m3u8'));
    expect((await get(other)).$1, 404);
    expect((await get(local.replace(path: '/wrongtoken/0.m3u8'))).$1, 403);
  });
}
