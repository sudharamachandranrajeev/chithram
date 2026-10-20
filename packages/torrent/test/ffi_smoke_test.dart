// Runs only when CHITHRAM_TORRENT_LIB points at a built libchithram_torrent
// (the spike-torrent workflow sets it); otherwise it is skipped.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:torrent/torrent.dart';

Future<int> _get(String url, {String? host}) async {
  final c = HttpClient();
  try {
    final req = await c.getUrl(Uri.parse(url));
    if (host != null) req.headers.host = host;
    final res = await req.close();
    await res.drain<void>();
    return res.statusCode;
  } finally {
    c.close(force: true);
  }
}

void main() {
  final lib = Platform.environment['CHITHRAM_TORRENT_LIB'] ?? '';
  test('start, /health, 403s, stop over dart:ffi', () async {
    final dir = await Directory.systemTemp.createTemp('torrent_ffi');
    final e = await TorrentEngine.start(dir: dir.path);
    try {
      expect(e.token.length, 32);
      expect(await _get(e.healthUrl), 200);
      expect(await _get('http://127.0.0.1:${e.port}/${'0' * 32}/health'), 403);
      expect(await _get(e.healthUrl, host: 'evil.example'), 403);
      await expectLater(
        e.add(magnet: 'not a magnet'),
        throwsA(isA<TorrentException>()),
      );
    } finally {
      await e.stop();
      await dir.delete(recursive: true);
    }
  }, skip: lib.isEmpty ? 'CHITHRAM_TORRENT_LIB not set' : false);
}
