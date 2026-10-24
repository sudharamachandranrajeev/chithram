import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nova_host/nova_host.dart';
import 'package:torrent/torrent.dart';

import 'plugins/plugin_runtime.dart';

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
    Future<TorrentEngine> start() => TorrentEngine.start(dir: dir.path, socks5: 'socks5://127.0.0.1:9');
    try {
      engine = await start();
    } on TorrentException catch (e) {
      // The engine is process-global; a second main() (Android can run the
      // entrypoint again) finds it started. Restart it and check that one.
      debugPrint('CHITHRAM_SMOKE restarting: $e');
      await TorrentEngine.stopRunning();
      engine = await start();
    }
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

/// `--smoke-nova[=<result file>]`: the plugin runtime of this build runs the
/// good fixture engine and the raw-socket one inside the sandbox. Prints
/// `CHITHRAM_SMOKE nova good=ok socket=blocked` (or `failed: ...`).
/// `--smoke-nova-full` runs the whole acceptance suite (Android CI) and prints
/// `NOVA_SPIKE ...` lines instead.
const smokeNovaFlag = '--smoke-nova';
const smokeNovaFullFlag = '--smoke-nova-full';

class NovaSmokeTarget {
  const NovaSmokeTarget({required this.full, this.file = ''});
  final bool full;
  final String file;
}

NovaSmokeTarget? novaSmokeTarget(List<String> args) {
  for (final a in args) {
    if (a == smokeNovaFullFlag) return const NovaSmokeTarget(full: true);
    if (a == smokeNovaFlag) return const NovaSmokeTarget(full: false);
    if (a.startsWith('$smokeNovaFlag=')) return NovaSmokeTarget(full: false, file: a.substring(smokeNovaFlag.length + 1));
  }
  return null;
}

Future<void> runNovaSmoke(NovaSmokeTarget target) async {
  final lines = <String>[];
  void say(String s) {
    lines.add(s);
    debugPrint(target.full ? 'NOVA_SPIKE $s' : s);
  }

  var passed = 0, failed = 0;
  try {
    final home = Platform.isAndroid
        ? '${Directory.systemTemp.parent.path}/files'
        : (Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? Directory.systemTemp.path);
    final tmp = await Directory.systemTemp.createTemp('nova_smoke');
    DesktopNovaRuntime? desktop;
    if (!Platform.isAndroid) {
      desktop = DesktopNovaRuntime.locate();
      if (!desktop.available) throw PluginsUnavailable(desktop.reason ?? 'no plugin runtime');
    }
    // Android runs with and without the Python audit hook; the OS isolation alone must hold too.
    for (final audit in target.full && Platform.isAndroid ? [true, false] : [true]) {
      if (target.full) say('MODE audit=${audit ? 'on' : 'off'}');
      final suite = AcceptanceSuite(
        start: Platform.isAndroid ? () => AndroidNovaSession.start(audit: audit) : desktop!.start,
        homeDir: home,
        tmpDir: tmp.path,
        log: target.full ? say : null,
        expectIsolatedUid: Platform.isAndroid && target.full,
        spawnContained: Platform.isAndroid && !audit,
      );
      final rs = await suite.run(only: target.full ? null : {'good-engine', 'raw-socket'});
      for (final r in rs) {
        if (target.full) say('CHECK audit=${audit ? 'on' : 'off'} ${r.ok ? 'PASS' : 'FAIL'} ${r.name}');
        if (r.ok) {
          passed++;
        } else {
          failed++;
          say('FAIL ${r.name}: ${r.detail}');
        }
      }
      if (target.full) say('SUITE_JSON ${suiteJson(rs)}');
    }
    if (target.full) {
      if (Platform.isAndroid && AndroidNovaSession.lastReport != null) say(AndroidNovaSession.lastReport!.line);
      say('SUITE_DONE passed=$passed failed=$failed');
    } else {
      say(failed == 0 && passed == 2 ? 'CHITHRAM_SMOKE nova good=ok socket=blocked' : 'CHITHRAM_SMOKE nova failed: passed=$passed failed=$failed');
    }
    await tmp.delete(recursive: true);
  } on PluginsUnavailable catch (e) {
    if (target.full) {
      say('NOVA_PLUGINS=disabled reason="${e.reason}" (search falls back to Torznab only)');
      say('NOVA_ISOLATED=no detail="${e.reason}"');
      say('SUITE_DONE passed=0 failed=-1');
    } else {
      say('CHITHRAM_SMOKE nova failed: unavailable: ${e.reason}');
    }
  } catch (e, st) {
    say(target.full ? 'SUITE_ERROR $e\n$st' : 'CHITHRAM_SMOKE nova failed: $e');
    if (target.full) say('SUITE_DONE passed=0 failed=-1');
  }
  if (target.file.isNotEmpty) File(target.file).writeAsStringSync('${lines.join('\n')}\n');
}
