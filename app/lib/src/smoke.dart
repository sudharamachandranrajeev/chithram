import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:torrent/torrent.dart';

/// Release smoke test (`chithram --smoke[=<result file>]`, or the Android
/// intent extra dart_entrypoint_args). Loads the bundled torrent library,
/// starts the engine on a dummy SOCKS5 proxy (so it opens no DHT, listener or
/// tracker connection) and checks that its loopback /health answers 200.
/// Prints `CHITHRAM_SMOKE torrent health=<status>`; with a file, writes it there
/// too (Windows GUI apps have no stdout).
const smokeFlag = '--smoke';

String? smokeTarget(List<String> args) {
  for (final a in args) {
    if (a == smokeFlag) return '';
    if (a.startsWith('$smokeFlag=')) return a.substring(smokeFlag.length + 1);
  }
  return null;
}

Future<void> runSmoke(String file) async {
  String line;
  TorrentEngine? engine;
  try {
    final dir = await Directory.systemTemp.createTemp('chithram_smoke');
    engine = await TorrentEngine.start(dir: dir.path, socks5: 'socks5://127.0.0.1:9');
    final client = HttpClient();
    final res = await (await client.getUrl(Uri.parse(engine.healthUrl))).close();
    await res.drain<void>();
    client.close();
    line = 'CHITHRAM_SMOKE torrent health=${res.statusCode}';
  } catch (error) {
    line = 'CHITHRAM_SMOKE torrent failed: $error';
  }
  debugPrint(line);
  if (file.isNotEmpty) File(file).writeAsStringSync('$line\n');
  try {
    await engine?.stop();
  } catch (_) {}
}
