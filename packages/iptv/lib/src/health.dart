import 'dart:async';
import 'dart:typed_data';

import 'http.dart';
import 'sources.dart';
import 'store.dart';

enum StreamKind { hls, mpegTs, other, unknown }

class ProbeResult {
  ProbeResult({
    required this.ok,
    required this.checkedAt,
    this.kind = StreamKind.unknown,
    this.ttfbMs,
    this.status,
    this.error,
    this.failStreak = 0,
  });
  final bool ok;
  final DateTime checkedAt;
  final StreamKind kind;
  final int? ttfbMs;
  final int? status;
  final String? error;

  /// Consecutive failed probes.
  final int failStreak;

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'at': checkedAt.toUtc().millisecondsSinceEpoch,
        'kind': kind.name,
        'ttfb': ttfbMs,
        'status': status,
        'error': error,
        'streak': failStreak,
      };
  factory ProbeResult.fromJson(Map<String, dynamic> j) => ProbeResult(
        ok: j['ok'] == true,
        checkedAt: DateTime.fromMillisecondsSinceEpoch(j['at'] as int, isUtc: true),
        kind: StreamKind.values.firstWhere((k) => k.name == j['kind'],
            orElse: () => StreamKind.unknown),
        ttfbMs: j['ttfb'] as int?,
        status: j['status'] as int?,
        error: j['error'] as String?,
        failStreak: (j['streak'] as int?) ?? 0,
      );
}

/// Classifies the first bytes of a stream. Pure, unit-testable.
({bool ok, StreamKind kind, String? error}) classifyProbeBytes(
    Uint8List head, String? contentType) {
  final ct = (contentType ?? '').toLowerCase();
  if (head.isEmpty) return (ok: false, kind: StreamKind.unknown, error: 'empty');
  // HLS playlist.
  final isText = head[0] == 0x23; // '#'
  if (isText || ct.contains('mpegurl')) {
    final s = String.fromCharCodes(head.take(8192));
    if (!s.trimLeft().startsWith('#EXTM3U')) {
      return (ok: false, kind: StreamKind.hls, error: 'not an HLS playlist');
    }
    final valid = s.contains('#EXT-X-STREAM-INF') ||
        s.contains('#EXTINF') ||
        s.contains('#EXT-X-TARGETDURATION');
    return valid
        ? (ok: true, kind: StreamKind.hls, error: null)
        : (ok: false, kind: StreamKind.hls, error: 'playlist has no segments');
  }
  // MPEG-TS: 0x47 sync byte, repeating every 188 bytes when we have them.
  if (head[0] == 0x47) {
    if (head.length > 188 && head[188] != 0x47) {
      return (ok: false, kind: StreamKind.mpegTs, error: 'TS sync lost');
    }
    return (ok: true, kind: StreamKind.mpegTs, error: null);
  }
  // HTML/JSON error pages are the usual dead-stream answer.
  if (ct.contains('text/html') || ct.contains('json') || head[0] == 0x3c) {
    return (ok: false, kind: StreamKind.other, error: 'not a media stream');
  }
  if (ct.startsWith('video/') || ct.startsWith('audio/') ||
      ct.contains('octet-stream')) {
    return (ok: true, kind: StreamKind.other, error: null);
  }
  return (ok: false, kind: StreamKind.unknown, error: 'unrecognised content');
}

class ProbePool {
  ProbePool(
    this._http, {
    this.concurrency = 8,
    this.timeout = const Duration(seconds: 8),
    this.probeBytes = 2048,
  });
  final IptvHttp _http;
  final int concurrency;
  final Duration timeout;
  final int probeBytes;

  Future<ProbeResult> probe(Uri url,
      {Map<String, String> headers = const {}, DateTime? now}) async {
    final at = (now ?? DateTime.now()).toUtc();
    IptvResponse? r;
    try {
      r = await _http.open(url, headers: headers, timeout: timeout);
      if (!r.ok) {
        return ProbeResult(
            ok: false, checkedAt: at, status: r.status,
            ttfbMs: r.ttfb.inMilliseconds, error: 'HTTP ${r.status}');
      }
      final b = BytesBuilder(copy: false);
      // Read enough for a TS double-sync check, but never wait past [timeout].
      await for (final c in r.body.timeout(timeout)) {
        b.add(c);
        if (b.length >= probeBytes) break;
      }
      final c = classifyProbeBytes(b.takeBytes(), r.headers['content-type']);
      return ProbeResult(
        ok: c.ok,
        checkedAt: at,
        kind: c.kind,
        status: r.status,
        ttfbMs: r.ttfb.inMilliseconds,
        error: c.error,
      );
    } on TimeoutException {
      return ProbeResult(ok: false, checkedAt: at, error: 'timeout');
    } catch (e) {
      // Error text only carries the exception type: URLs may hold credentials.
      return ProbeResult(ok: false, checkedAt: at, error: e.runtimeType.toString());
    } finally {
      r?.close();
    }
  }

  /// Probes [channels] with at most [concurrency] in flight. Results fresher
  /// than [ttl] in the store are reused. Dead = [deadAfter] consecutive
  /// failures; channels are marked, never deleted. Returns channels updated.
  Future<List<StoredChannel>> run(
    List<StoredChannel> channels,
    IptvStore store, {
    Uri Function(StoredChannel)? urlOf,
    Duration ttl = const Duration(hours: 24),
    int deadAfter = 2,
    DateTime? now,
  }) async {
    final t = (now ?? DateTime.now()).toUtc();
    final cache = await store.probes();
    final out = List<StoredChannel>.of(channels);
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= out.length) return;
        final ch = out[i];
        final key = ch.key;
        var res = cache[key];
        if (res == null || t.difference(res.checkedAt) >= ttl) {
          final u = urlOf != null ? urlOf(ch) : Uri.tryParse(ch.url ?? '');
          if (u == null) continue;
          final fresh = await probe(u, headers: ch.headers, now: t);
          res = ProbeResult(
            ok: fresh.ok,
            checkedAt: fresh.checkedAt,
            kind: fresh.kind,
            ttfbMs: fresh.ttfbMs,
            status: fresh.status,
            error: fresh.error,
            failStreak: fresh.ok ? 0 : (res?.failStreak ?? 0) + 1,
          );
          cache[key] = res;
        }
        out[i] = ch.copyWith(
          dead: !res.ok && res.failStreak >= deadAfter,
          deadSince: !res.ok && res.failStreak >= deadAfter
              ? (ch.deadSince ?? t)
              : null,
          ttfbMs: res.ttfbMs,
          clearDeadSince: res.ok || res.failStreak < deadAfter,
        );
      }
    }

    await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
    await store.saveProbes(cache);
    return out;
  }
}
