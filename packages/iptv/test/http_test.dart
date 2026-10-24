import 'dart:io';

import 'package:iptv/src/http.dart';
import 'package:test/test.dart';

void main() {
  test('DartIoHttp decodes a gzip Content-Encoding (GitHub serves playlists so)', () async {
    const m3u = '#EXTM3U\n#EXTINF:-1,One\nhttp://example.test/1.m3u8\n';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) {
      final gz = req.headers.value(HttpHeaders.acceptEncodingHeader)?.contains('gzip') ?? false;
      if (gz) req.response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
      req.response.add(gz ? gzip.encode(m3u.codeUnits) : m3u.codeUnits);
      req.response.close();
    });
    final http = DartIoHttp();
    addTearDown(http.close);
    final r = await http.open(Uri.parse('http://127.0.0.1:${server.port}/playlist.m3u8'));
    expect(await readText(r), m3u);
  });
}
