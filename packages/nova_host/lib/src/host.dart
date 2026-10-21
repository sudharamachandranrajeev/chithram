import 'dart:async';
import 'dart:convert';

import 'broker.dart';
import 'domains.dart';
import 'session.dart';

class NovaEngine {
  NovaEngine({required this.id, required this.source, this.hosts = const [], this.adult = false});

  /// Module/class name (nova convention: file `<id>.py` defines `class <id>`).
  final String id;
  final String source;

  /// From the signed manifest: extra hosts the engine may contact.
  final List<String> hosts;
  final bool adult;
}

enum SearchStatus { ok, error, killed }

class SearchOutcome {
  SearchOutcome({
    required this.status,
    required this.results,
    required this.elapsed,
    required this.brokerLog,
    required this.requests,
    this.reason,
    this.engineName,
    this.engineUrl,
    this.rejected = 0,
    this.truncated = false,
    this.stderrHead = '',
    this.exitCode,
    this.adult = false,
    this.uid,
  });

  final SearchStatus status;

  /// uid the plugin process runs as (Android isolated range is 99000-99999).
  final int? uid;
  final List<Map<String, Object?>> results;
  final Duration elapsed;
  final List<String> brokerLog;
  final int requests;
  final String? reason;
  final String? engineName;
  final String? engineUrl;
  final int rejected;
  final bool truncated;
  final String stderrHead;
  final int? exitCode;
  final bool adult;

  String get summary =>
      '${status.name}${reason != null ? '($reason)' : ''} results=${results.length} requests=$requests '
      '${elapsed.inMilliseconds}ms';
}

typedef SessionStarter = Future<NovaSession> Function();

/// Runs one search per sandboxed runner process and brokers its HTTP.
class NovaHost {
  NovaHost({required this.start, this.policy = const BrokerPolicy(), this.limits = const NovaLimits()});

  final SessionStarter start;
  final BrokerPolicy policy;
  final NovaLimits limits;

  Future<SearchOutcome> search(NovaEngine engine, String query, {String cat = 'all', String? source}) async {
    final sw = Stopwatch()..start();
    final session = await start();
    HttpBroker? broker;
    final results = <Map<String, Object?>>[];
    String? name, url;
    int? uid;
    var status = SearchStatus.error;
    String? reason = 'runner ended without a result';
    var rejected = 0;
    var truncated = false;

    session.send({
      'op': 'search',
      'module': engine.id,
      'src': source ?? engine.source,
      'query': query,
      'cat': cat,
    });
    try {
      await for (final m in session.messages) {
        switch (m['op']) {
          case 'meta':
            name = m['name'] as String?;
            url = m['url'] as String?;
            uid = (m['uid'] as num?)?.toInt();
            broker = HttpBroker(allowlist: HostAllowlist.forEngine(url ?? '', engine.hosts), policy: policy);
          case 'http':
            final b = broker;
            if (b == null) {
              session.send({'op': 'http_resp', 'id': m['id'], 'error': 'no engine metadata yet'});
              break;
            }
            session.send(await _serve(b, m));
          case 'result':
            final r = m['r'];
            if (r is Map<String, Object?>) {
              if (results.length < limits.maxResults) {
                results.add(r);
              } else {
                truncated = true;
              }
            }
          case 'done':
            status = SearchStatus.ok;
            reason = null;
            rejected = (m['rejected'] as num?)?.toInt() ?? 0;
            truncated = truncated || m['truncated'] == true;
            session.send({'op': 'quit'});
          case 'error':
            status = SearchStatus.error;
            reason = m['msg'] as String?;
            session.send({'op': 'quit'});
        }
      }
    } finally {
      if (session.killedReason == null) {
        // Give a clean exit a moment, then make sure the process is gone.
        await session.exitCode.timeout(const Duration(seconds: 2), onTimeout: () async {
          await session.kill('cleanup');
          return null;
        });
      }
    }
    final code = await session.exitCode.timeout(const Duration(seconds: 3), onTimeout: () => null);
    if (session.killedReason != null && session.killedReason != 'cleanup') {
      status = SearchStatus.killed;
      reason = session.killedReason;
    } else if (status == SearchStatus.error && code != null && (code == 124 || code > 128 || code < 0)) {
      // The launcher / Job Object killed it (wall time, CPU limit, signal, NTSTATUS).
      status = SearchStatus.killed;
      reason = code == 124
          ? 'sandbox-wall-timeout'
          : code > 128 && code < 256
              ? 'sandbox-signal-${code - 128}'
              : 'sandbox-exit-0x${(code & 0xffffffff).toRadixString(16)}';
    }
    sw.stop();
    return SearchOutcome(
      status: status,
      results: results,
      elapsed: sw.elapsed,
      brokerLog: broker?.log ?? const [],
      requests: broker?.requests ?? 0,
      reason: reason,
      engineName: name,
      engineUrl: url,
      rejected: rejected,
      truncated: truncated,
      stderrHead: session.stderrHead,
      exitCode: code,
      adult: engine.adult,
      uid: uid,
    );
  }

  Future<Map<String, Object?>> _serve(HttpBroker b, Map<String, Object?> m) async {
    final id = m['id'];
    try {
      final hdr = <String, String>{
        for (final e in ((m['headers'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}',
      };
      final body = m['body_b64'] is String ? base64.decode(m['body_b64'] as String) : null;
      final r = await b.fetch('${m['method'] ?? 'GET'}', '${m['url']}', hdr, body);
      return {
        'op': 'http_resp',
        'id': id,
        'status': r.status,
        'reason': r.reason,
        'headers': r.headers,
        'url': r.url,
        'body_b64': base64.encode(r.body),
      };
    } on BrokerDenied catch (e) {
      return {'op': 'http_resp', 'id': id, 'error': e.reason};
    } catch (e) {
      b.log.add('ERROR $e');
      return {'op': 'http_resp', 'id': id, 'error': 'broker error'};
    }
  }
}
