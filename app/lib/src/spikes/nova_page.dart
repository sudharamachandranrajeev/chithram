import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nova_host/nova_host.dart';

/// Spike page for spike/nova (debug only, see registry.dart).
///
/// Android: starts the acceptance suite by itself and logs `NOVA_SPIKE ...`
/// lines to logcat (CI greps them). Desktop: set NOVA_PYTHON, NOVA_SANDBOX,
/// NOVA_RUNNER_DIR (and optionally NOVA_PY_PREFIX) or press the buttons.
class NovaSpikePage extends StatefulWidget {
  const NovaSpikePage({super.key});

  @override
  State<NovaSpikePage> createState() => _NovaSpikePageState();
}

class _NovaSpikePageState extends State<NovaSpikePage> {
  final _log = StringBuffer();
  final _path = TextEditingController();
  final _query = TextEditingController(text: 'sintel');
  final _pins = FilePinStore('${Directory.systemTemp.path}${Platform.pathSeparator}nova_pins.json');
  final List<NovaEngine> _engines = [];
  final Map<String, String> _warnings = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final auto = Platform.isAndroid || const bool.fromEnvironment('NOVA_AUTORUN');
    if (auto) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runSuite());
    }
  }

  void _say(String s) {
    debugPrint('NOVA_SPIKE $s');
    if (mounted) setState(() => _log.writeln(s));
  }

  Future<NovaSession> Function() _starter() {
    if (Platform.isAndroid) {
      return () => AndroidNovaSession.start();
    }
    final env = Platform.environment;
    final python = env['NOVA_PYTHON'] ?? (Platform.isWindows ? 'python.exe' : 'python3');
    final runnerDir = env['NOVA_RUNNER_DIR'] ?? 'python/nova/runtime';
    final sandbox = env['NOVA_SANDBOX'];
    final cfg = LaunchConfig(
      python: python,
      runnerDir: runnerDir,
      sandboxExe: sandbox,
      insecureNoSandbox: sandbox == null,
      readOnlyPaths: [if (env['NOVA_PY_PREFIX'] != null) env['NOVA_PY_PREFIX']!],
      auditHook: env['NOVA_AUDIT'] != '0',
    );
    if (sandbox == null) _say('WARNING: NOVA_SANDBOX not set, running WITHOUT the native sandbox');
    return () => ProcessSession.start(cfg);
  }

  Future<void> _runSuite() async {
    if (_busy) return;
    setState(() => _busy = true);
    _say('suite start platform=${Platform.operatingSystem}');
    var passed = 0, failed = 0;
    try {
      // Android: the app's filesDir holds the fake secret and is the "$HOME" the
      // plugin tries to write to; it is the parent of the cache dir.
      final home = Platform.isAndroid
          ? '${Directory.systemTemp.parent.path}/files'
          : (Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? Directory.systemTemp.path);
      // Android runs the suite twice: with the Python audit hook, and with only the
      // OS isolation (isolated uid) in force.
      for (final audit in Platform.isAndroid ? [true, false] : [true]) {
        _say('MODE audit=${audit ? 'on' : 'off'}');
        final suite = AcceptanceSuite(
          start: Platform.isAndroid ? () => AndroidNovaSession.start(audit: audit) : _starter(),
          homeDir: home,
          tmpDir: Directory.systemTemp.path,
          log: _say,
          expectIsolatedUid: Platform.isAndroid,
          spawnContained: Platform.isAndroid && !audit,
        );
        final rs = await suite.run();
        for (final r in rs) {
          _say('CHECK audit=${audit ? 'on' : 'off'} ${r.ok ? 'PASS' : 'FAIL'} ${r.name}');
        }
        _say('SUITE_JSON ${suiteJson(rs)}');
        passed += rs.where((r) => r.ok).length;
        failed += rs.where((r) => !r.ok).length;
      }
      if (Platform.isAndroid && AndroidNovaSession.lastReport != null) {
        _say(AndroidNovaSession.lastReport!.line);
      }
      _say('SUITE_DONE passed=$passed failed=$failed');
    } on PluginsUnavailable catch (e) {
      _say('NOVA_PLUGINS=disabled reason="${e.reason}" (search falls back to Torznab only)');
      _say('NOVA_ISOLATED=no detail="${e.reason}"');
      _say('SUITE_DONE passed=0 failed=-1');
    } catch (e, st) {
      _say('SUITE_ERROR $e\n$st');
      _say('SUITE_DONE passed=0 failed=-1');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPlugin() async {
    try {
      final f = File(_path.text.trim());
      final u = UnsignedPlugin.fromSource(f.uri.pathSegments.last, await f.readAsString());
      setState(() {
        _engines.add(u.engine);
        _warnings[u.engine.id] = u.warning;
      });
      _say('added ${u.engine.id} (${u.warning})${u.engine.adult ? ' [ADULT]' : ''}');
    } catch (e) {
      _say('add plugin failed: $e');
    }
  }

  Future<List<int>> _read(String base, String name) async {
    if (base.startsWith('http://') || base.startsWith('https://')) {
      final c = HttpClient();
      try {
        final r = await (await c.getUrl(Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}/$name'))).close();
        if (r.statusCode != 200) throw HttpException('HTTP ${r.statusCode} for $name');
        return await r.fold<List<int>>([], (a, b) => a..addAll(b));
      } finally {
        c.close();
      }
    }
    return File('$base${Platform.pathSeparator}$name').readAsBytes();
  }

  Future<void> _addRepo() async {
    final base = _path.text.trim();
    try {
      final client = PluginRepoClient(_pins);
      String? pub;
      try {
        pub = utf8.decode(await _read(base, 'repo.pub'));
      } catch (_) {}
      final v = await client.verify(
        repoId: base,
        manifestBytes: await _read(base, 'plugins.json'),
        signatureText: utf8.decode(await _read(base, 'plugins.json.minisig')),
        publicKeyText: pub,
      );
      _say('repo verified, key ${v.keyId}${v.firstUse ? ' (pinned now: trust on first use)' : ''}');
      for (final p in v.manifest.plugins) {
        final e = client.engineFor(p, await _read(base, p.file));
        setState(() => _engines.add(e));
        _say('plugin ${p.id} ${p.version} sha256 ok hosts=${p.hosts}${p.adult ? ' [ADULT]' : ''}');
      }
    } on RepoError catch (e) {
      _say('REFUSED: ${e.message} (${e.kind.name})');
    } catch (e) {
      _say('add repo failed: $e');
    }
  }

  Future<void> _search(NovaEngine e) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final host = NovaHost(start: _starter());
      final o = await host.search(e, _query.text);
      _say('search ${e.id}: ${o.summary}');
      for (final r in o.results.take(20)) {
        _say('  ${r['name']}  seeds=${r['seeds']} size=${r['size']}');
      }
      for (final l in o.brokerLog) {
        _say('  broker: $l');
      }
      if (o.stderrHead.isNotEmpty) _say('  sandbox log: ${o.stderrHead.trim()}');
    } catch (err) {
      _say('search failed: $err');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('spike: nova plugin host')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _path,
                  decoration: const InputDecoration(labelText: 'plugin .py file, or repo directory / URL'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _busy ? null : _addPlugin, child: const Text('Add .py')),
              const SizedBox(width: 8),
              FilledButton(onPressed: _busy ? null : _addRepo, child: const Text('Add repo')),
              const SizedBox(width: 8),
              FilledButton(onPressed: _busy ? null : _runSuite, child: const Text('Run suite')),
            ]),
            Row(children: [
              SizedBox(width: 200, child: TextField(controller: _query, decoration: const InputDecoration(labelText: 'query'))),
              const SizedBox(width: 16),
              Expanded(
                child: Wrap(spacing: 8, children: [
                  for (final e in _engines)
                    Tooltip(
                      message: _warnings[e.id] ?? 'verified repo plugin',
                      child: ActionChip(
                        label: Text('${e.id}${e.adult ? ' (18+)' : ''}'),
                        onPressed: _busy ? null : () => _search(e),
                      ),
                    ),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(_log.toString(), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
