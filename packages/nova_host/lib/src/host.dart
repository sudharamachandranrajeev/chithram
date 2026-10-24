import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'broker.dart';
import 'domains.dart';
import 'session.dart';

class NovaEngine {
  NovaEngine({
    required this.id,
    required this.source,
    this.hosts = const [],
    this.adult = false,
    this.pinnedHosts,
  });

  /// Module/class name (nova convention: file `<id>.py` defines `class <id>`).
  final String id;
  final String source;

  /// From the signed manifest: extra hosts the engine may contact.
  final List<String> hosts;
  final bool adult;

  /// The allowlist the user confirmed at install: the registrable domain of the
  /// plugin's declared `url` plus its manifest or header hosts. When set, the
  /// broker allows exactly these hosts, and a plugin whose `url` now names any
  /// other registrable domain is refused with reason `url-changed`. Null (tests,
  /// spikes) falls back to deriving the list from the url the plugin reports.
  final List<String>? pinnedHosts;
}

/// Reason a search or download is refused when the plugin's declared domain is
/// no longer one the user approved.
const urlChangedReason = 'url-changed';

/// One search result, typed. [pubDate] is null when the plugin omits it (or
/// gives a value that is not a plausible unix time); [sizeBytes], [seeders] and
/// [leechers] are null when the plugin reports -1.
class PluginHit {
  PluginHit({
    required this.engineId,
    required this.name,
    required this.link,
    this.sizeBytes,
    this.seeders,
    this.leechers,
    this.descLink,
    this.pubDate,
    this.engineUrl,
  });

  /// The plugin that found it (`NovaEngine.id`).
  final String engineId;
  final String name;

  /// `magnet:`, or an http(s) link to a .torrent file or a page.
  final String link;
  final int? sizeBytes;
  final int? seeders;
  final int? leechers;
  final String? descLink;
  final DateTime? pubDate;
  final String? engineUrl;

  bool get isMagnet => link.toLowerCase().startsWith('magnet:');

  /// 40 hex (or base32) characters of `xt=urn:btih:`, lower-cased hex; null for non-magnets.
  String? get infoHash {
    final m = RegExp(r'xt=urn:btih:([0-9a-fA-F]{40})(&|$)').firstMatch(link);
    return m?.group(1)?.toLowerCase();
  }

  factory PluginHit.fromResult(String engineId, Map<String, Object?> r) {
    int? nonNeg(Object? v) => v is int && v >= 0 ? v : null;
    final pd = r['pub_date'];
    return PluginHit(
      engineId: engineId,
      name: '${r['name']}',
      link: '${r['link']}',
      sizeBytes: nonNeg(r['size']),
      seeders: nonNeg(r['seeds']),
      leechers: nonNeg(r['leech']),
      descLink: r['desc_link'] as String?,
      pubDate: pd is int ? DateTime.fromMillisecondsSinceEpoch(pd * 1000, isUtc: true) : null,
      engineUrl: r['engine_url'] as String?,
    );
  }
}

/// What `describe` found out about a plugin, without any network.
class DescribeOutcome {
  DescribeOutcome({required this.ok, this.name, this.url, this.categories = const [], this.reason, this.stderrHead = ''});

  final bool ok;
  final String? name;

  /// The plugin's declared `url` (its site).
  final String? url;
  final List<String> categories;
  final String? reason;
  final String stderrHead;
}

class NovaDownloadError implements Exception {
  NovaDownloadError(this.reason);
  final String reason;
  @override
  String toString() => 'NovaDownloadError: $reason';
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
    this.engineId = '',
  });

  final SearchStatus status;

  /// `NovaEngine.id` of the plugin that ran.
  final String engineId;

  /// [results] as typed hits (same order).
  List<PluginHit> get hits => [for (final r in results) PluginHit.fromResult(engineId, r)];

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
    var refused = false;

    session.send({
      'op': 'search',
      'module': engine.id,
      'src': source ?? engine.source,
      'query': query,
      'cat': cat,
    });
    try {
      await for (final m in session.messages) {
        if (refused) continue;
        switch (m['op']) {
          case 'meta':
            name = m['name'] as String?;
            url = m['url'] as String?;
            uid = (m['uid'] as num?)?.toInt();
            if (!_urlStillApproved(engine, url)) {
              status = SearchStatus.error;
              reason = urlChangedReason;
              refused = true;
              await session.kill('cleanup');
              break;
            }
            broker = HttpBroker(allowlist: _allowlist(engine, url), policy: policy);
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
    } else if (!refused && status == SearchStatus.error && code != null && (code == 124 || code > 128 || code < 0)) {
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
      engineId: engine.id,
    );
  }

  /// Loads the plugin in a sandboxed runner and reports its name, `url` and
  /// categories. The plugin gets no network (every request is refused).
  Future<DescribeOutcome> describe(NovaEngine engine) async {
    final session = await start();
    String? name, url, reason = 'runner ended without a result';
    var categories = <String>[];
    var ok = false;
    session.send({'op': 'describe', 'module': engine.id, 'src': engine.source});
    try {
      await for (final m in session.messages) {
        switch (m['op']) {
          case 'meta':
            name = m['name'] as String?;
            url = m['url'] as String?;
            categories = [for (final c in (m['categories'] as List? ?? const [])) '$c'];
          case 'http':
            session.send({'op': 'http_resp', 'id': m['id'], 'error': 'no network while describing'});
          case 'done':
            ok = true;
            reason = null;
            session.send({'op': 'quit'});
          case 'error':
            reason = m['msg'] as String?;
            session.send({'op': 'quit'});
        }
      }
    } finally {
      await _reap(session);
    }
    if (session.killedReason != null && session.killedReason != 'cleanup') {
      ok = false;
      reason = session.killedReason;
    }
    return DescribeOutcome(
      ok: ok && url != null,
      name: name,
      url: url,
      categories: categories,
      reason: ok && url == null ? 'plugin has no url' : reason,
      stderrHead: session.stderrHead,
    );
  }

  /// Downloads the file at [url] through [engine]'s own `download_torrent`,
  /// on its allowlisted channel, and returns its bytes (at most [maxBytes],
  /// 2 MiB). Throws [NovaDownloadError] with a short reason.
  Future<Uint8List> downloadTorrent(NovaEngine engine, String url, {int maxBytes = 2 * 1024 * 1024}) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
      throw NovaDownloadError('bad-url');
    }
    final session = await start();
    HttpBroker? broker;
    final out = BytesBuilder(copy: false);
    String? reason = 'runner ended without a result';
    var done = false;
    var refused = false;
    var expectChunk = 0;
    session.send({'op': 'download', 'module': engine.id, 'src': engine.source, 'url': url});
    try {
      await for (final m in session.messages) {
        if (refused) continue;
        switch (m['op']) {
          case 'meta':
            final declared = m['url'] as String?;
            if (!_urlStillApproved(engine, declared)) {
              reason = urlChangedReason;
              refused = true;
              await session.kill('cleanup');
              break;
            }
            broker = HttpBroker(allowlist: _allowlist(engine, declared), policy: policy);
          case 'http':
            final b = broker;
            session.send(b == null
                ? {'op': 'http_resp', 'id': m['id'], 'error': 'no engine metadata yet'}
                : await _serve(b, m));
          case 'dl':
            if ((m['i'] as num?)?.toInt() != expectChunk++ || m['b64'] is! String) {
              reason = 'protocol-violation';
              refused = true;
              await session.kill('cleanup');
              break;
            }
            out.add(base64.decode(m['b64'] as String));
            if (out.length > maxBytes) {
              reason = 'torrent-too-large';
              refused = true;
              await session.kill('cleanup');
            }
          case 'downloaded':
            done = (m['size'] as num?)?.toInt() == out.length;
            reason = done ? null : 'protocol-violation';
            session.send({'op': 'quit'});
          case 'error':
            final msg = '${m['msg']}';
            reason = msg.contains('torrent-too-large') ? 'torrent-too-large' : msg;
            session.send({'op': 'quit'});
        }
      }
    } finally {
      await _reap(session);
    }
    if (session.killedReason != null && session.killedReason != 'cleanup') reason = session.killedReason;
    if (!done || reason != null) throw NovaDownloadError(reason ?? 'download failed');
    return out.takeBytes();
  }

  bool _urlStillApproved(NovaEngine engine, String? declared) {
    final pinned = engine.pinnedHosts;
    if (pinned == null) return true;
    final host = Uri.tryParse(declared ?? '')?.host ?? '';
    if (host.isEmpty) return false;
    return pinned.map((e) => e.toLowerCase()).contains(registrableDomain(host));
  }

  HostAllowlist _allowlist(NovaEngine engine, String? declared) {
    final pinned = engine.pinnedHosts;
    return pinned != null ? HostAllowlist(pinned) : HostAllowlist.forEngine(declared ?? '', engine.hosts);
  }

  /// Gives a clean exit a moment, then makes sure the process is gone.
  Future<void> _reap(NovaSession session) async {
    if (session.killedReason == null) {
      await session.exitCode.timeout(const Duration(seconds: 2), onTimeout: () async {
        await session.kill('cleanup');
        return null;
      });
    }
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
