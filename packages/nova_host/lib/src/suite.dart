import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'broker.dart';
import 'fixtures.g.dart';
import 'host.dart';
import 'session.dart';

/// A local HTTP server that plays the fake "example.test" site. It is the only
/// server any fixture engine may talk to; Chithram ships no real indexers.
class FixtureServer {
  FixtureServer._(this._server);
  final HttpServer _server;
  RawDatagramSocket? _udp;
  final List<String> hits = [];

  static Future<FixtureServer> start() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final f = FixtureServer._(s);
    s.listen(f._handle);
    try {
      // UDP echo on the same port number: an escaped UDP packet gets a "pong" back.
      final u = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, s.port);
      f._udp = u;
      u.listen((e) {
        final d = u.receive();
        if (d != null) {
          f.hits.add('udp /escaped');
          u.send(utf8.encode('pong'), d.address, d.port);
        }
      });
    } catch (_) {}
    return f;
  }

  int get port => _server.port;
  String get baseUrl => 'http://example.test:$port';

  Future<void> close() async {
    _udp?.close();
    await _server.close(force: true);
  }

  void _handle(HttpRequest r) async {
    hits.add('${r.headers.host} ${r.uri.path}');
    final res = r.response;
    try {
      switch (r.uri.path) {
        case '/search':
          res.headers.contentType = ContentType.html;
          res.write('<html><body>'
              '<a class="r" href="magnet:?xt=urn:btih:${'a' * 40}" data-size="1.5 GB" data-s="10" data-l="2">Fixture item 1</a>'
              '<a class="r" href="http://example.test/t2.torrent" data-size="700 MB" data-s="3" data-l="1">Fixture item 2</a>'
              '<a class="r" href="magnet:?xt=urn:btih:${'b' * 40}" data-size="42 MiB" data-s="0" data-l="0">Fixture item 3</a>'
              '</body></html>');
        case '/redirect-foreign':
          res.statusCode = 302;
          res.headers.set('location', 'http://other.test:$port/steal');
        case '/steal':
          res.write('STOLEN');
        default:
          res.write('hello\n');
      }
    } finally {
      await res.close();
    }
  }
}

class CheckResult {
  CheckResult(this.name, this.ok, this.detail);
  final String name;
  final bool ok;
  final String detail;
  @override
  String toString() => '${ok ? 'PASS' : 'FAIL'} $name: $detail';
}

/// The acceptance checks, platform-neutral: desktop CI runs them through
/// `flutter test`, the Android spike page runs the very same code.
class AcceptanceSuite {
  AcceptanceSuite({
    required this.start,
    required this.homeDir,
    required this.tmpDir,
    this.limits,
    this.log,
  });

  final SessionStarter start;

  /// Where "write $HOME" and the fake secret live (real HOME on desktop).
  final String homeDir;
  final String tmpDir;
  final NovaLimits? limits;
  final void Function(String)? log;

  static const checkNames = [
    'good-engine',
    'urllib-and-httpclient',
    'write-home',
    'raw-socket',
    'subprocess',
    'read-secret',
    'infinite-loop',
    'big-print-50mb',
    'foreign-host',
    'budgets-20-requests-500-results',
  ];

  late FixtureServer _server;
  late String _secretPath;
  static const _secretText = 'NOVA-FAKE-SECRET-4711';

  NovaHost _host() => NovaHost(
        start: start,
        limits: limits ?? const NovaLimits(),
        policy: BrokerPolicy(
          testMode: true,
          hostOverrides: {
            'example.test': InternetAddress.loopbackIPv4,
            'other.test': InternetAddress.loopbackIPv4,
          },
        ),
      );

  Future<SearchOutcome> _run(String id) {
    var src = novaFixtures[id]!;
    final sep = Platform.pathSeparator;
    for (final e in {
      '__BASE__': _server.baseUrl,
      '__PORT__': '${_server.port}',
      '__HOME__': homeDir.replaceAll('\\', '/'),
      '__TMP__': tmpDir.replaceAll('\\', '/'),
      '__SECRET__': _secretPath.replaceAll('\\', '/'),
    }.entries) {
      src = src.replaceAll(e.key, e.value);
    }
    assert(sep.isNotEmpty);
    return _host().search(NovaEngine(id: id, source: src), 'sintel');
  }

  Future<List<CheckResult>> run({Set<String>? only}) async {
    _server = await FixtureServer.start();
    _secretPath = '$homeDir${Platform.pathSeparator}.fake_secret';
    File(_secretPath).writeAsStringSync(_secretText);
    final out = <CheckResult>[];
    try {
      for (final name in checkNames) {
        if (only != null && !only.contains(name)) continue;
        _server.hits.clear();
        CheckResult r;
        try {
          r = await _check(name);
        } catch (e, st) {
          r = CheckResult(name, false, 'suite error: $e\n$st');
        }
        log?.call(r.toString());
        out.add(r);
      }
    } finally {
      try {
        File(_secretPath).deleteSync();
      } catch (_) {}
      await _server.close();
    }
    return out;
  }

  List<String> _names(SearchOutcome o) => [for (final r in o.results) '${r['name']}'];

  CheckResult _contained(String name, SearchOutcome o, {List<String> extraEscapes = const []}) {
    final names = _names(o);
    final escaped = names.where((n) => n.startsWith('ESCAPED')).toList();
    final blocked = names.where((n) => n.startsWith('BLOCKED')).length;
    final problems = [...escaped, ...extraEscapes];
    final detail = '${o.summary} blocked=$blocked escaped=$problems layers="${_layers(o)}"';
    // Done or killed are both fine; what matters is that nothing escaped.
    final ran = o.status != SearchStatus.error || o.results.isNotEmpty;
    return CheckResult(name, problems.isEmpty && ran, ran ? detail : '$detail err=${o.reason} stderr=${o.stderrHead}');
  }

  String _layers(SearchOutcome o) {
    final m = RegExp(r'nova-sandbox: layers ([^\n]*)').firstMatch(o.stderrHead);
    return m?.group(1) ?? 'none-reported';
  }

  Future<CheckResult> _check(String name) async {
    switch (name) {
      case 'good-engine':
        final o = await _run('fx_good');
        final ok = o.status == SearchStatus.ok &&
            o.results.length == 3 &&
            o.results.first['size'] == (1.5 * 1024 * 1024 * 1024).round() &&
            o.results.first['name'] == 'Fixture item 1';
        return CheckResult(name, ok, '${o.summary} layers="${_layers(o)}" err=${o.reason ?? ''} ${ok ? '' : 'broker=${o.brokerLog} results=${o.results.length} stderr=${o.stderrHead}'}');
      case 'urllib-and-httpclient':
        final o = await _run('fx_urllib');
        final n = _names(o);
        final ok = o.status == SearchStatus.ok && n.length == 2 && n[0] == 'urllib:hello' && n[1] == 'httpclient:200:hello';
        return CheckResult(name, ok, '${o.summary} $n ${ok ? '' : o.stderrHead}');
      case 'write-home':
        final o = await _run('fx_write_home');
        final sep = Platform.pathSeparator;
        final traces = <String>[
          for (final p in [
            '$homeDir${sep}nova_pwned.txt',
            '$homeDir${sep}nova_pwned.txt2',
            '$homeDir${sep}nova_pwned_dir',
            '$tmpDir${sep}nova_pwned_tmp.txt',
          ])
            if (FileSystemEntity.typeSync(p) != FileSystemEntityType.notFound) 'file exists: $p',
        ];
        for (final t in traces) {
          log?.call(t);
          try {
            final p = t.substring('file exists: '.length);
            FileSystemEntity.isDirectorySync(p) ? Directory(p).deleteSync() : File(p).deleteSync();
          } catch (_) {}
        }
        return _contained(name, o, extraEscapes: traces);
      case 'raw-socket':
        final o = await _run('fx_socket');
        final seen = _server.hits.where((h) => h.endsWith('/escaped')).toList();
        return _contained(name, o, extraEscapes: [for (final s in seen) 'server saw direct connection: $s']);
      case 'subprocess':
        return _contained(name, await _run('fx_subprocess'));
      case 'read-secret':
        final o = await _run('fx_read_secret');
        final leaked = o.results.any((r) => '${r['name']}'.contains(_secretText.substring(0, 10)));
        return _contained(name, o, extraEscapes: [if (leaked) 'secret content leaked']);
      case 'infinite-loop':
        final o = await _run('fx_loop');
        final lim = (limits ?? const NovaLimits()).wall + const Duration(seconds: 12);
        final ok = o.status == SearchStatus.killed && o.elapsed < lim;
        return CheckResult(name, ok, '${o.summary} layers="${_layers(o)}" exit=${o.exitCode}');
      case 'big-print-50mb':
        final o = await _run('fx_bigprint');
        final lim = (limits ?? const NovaLimits()).wall + const Duration(seconds: 12);
        final ok = o.results.isEmpty && o.elapsed < lim && (o.status == SearchStatus.killed || o.status == SearchStatus.ok);
        return CheckResult(name, ok, '${o.summary} exit=${o.exitCode}');
      case 'foreign-host':
        final o = await _run('fx_foreign');
        final stolen = _server.hits.where((h) => h.endsWith('/steal') || h.endsWith('/steal2')).toList();
        final denied = o.brokerLog.where((l) => l.startsWith('DENIED')).length;
        final r = _contained(name, o, extraEscapes: [for (final s in stolen) 'server saw foreign request: $s']);
        return CheckResult(name, r.ok && denied >= 3, '${r.detail} denied=$denied');
      case 'budgets-20-requests-500-results':
        final o = await _run('fx_flood');
        final first = o.results.isEmpty ? '' : '${o.results.first['name']}';
        final ok = o.status == SearchStatus.ok && o.results.length == 500 && o.truncated && first == 'ok=20';
        return CheckResult(name, ok, '${o.summary} first=$first truncated=${o.truncated} err=${o.reason ?? ''}');
    }
    return CheckResult(name, false, 'unknown check');
  }
}

/// Convenience for the JSON line that CI greps from logcat.
String suiteJson(List<CheckResult> rs) =>
    jsonEncode([for (final r in rs) {'name': r.name, 'ok': r.ok, 'detail': r.detail}]);
