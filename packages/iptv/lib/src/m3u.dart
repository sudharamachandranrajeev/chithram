import 'dart:async';
import 'dart:convert';

/// Limits applied while parsing untrusted playlists.
class M3uLimits {
  const M3uLimits({
    this.maxBytes = 64 * 1024 * 1024,
    this.maxEntries = 200000,
    this.maxLineLength = 16 * 1024,
  });
  final int maxBytes;
  final int maxEntries;
  final int maxLineLength;
}

class M3uLimitException implements Exception {
  M3uLimitException(this.message);
  final String message;
  @override
  String toString() => 'M3uLimitException: $message';
}

/// One playlist entry.
class M3uEntry {
  M3uEntry({
    required this.url,
    required this.name,
    this.tvgId,
    this.tvgName,
    this.logo,
    this.group,
    this.catchup,
    this.catchupDays,
    this.catchupSource,
    this.referrer,
    this.userAgent,
    this.attributes = const {},
  });

  final String url;
  final String name;
  final String? tvgId;
  final String? tvgName;
  final String? logo;
  final String? group;
  final String? catchup;
  final int? catchupDays;
  final String? catchupSource;

  /// From `#EXTVLCOPT:http-referrer=`.
  final String? referrer;

  /// From `#EXTVLCOPT:http-user-agent=`.
  final String? userAgent;
  final Map<String, String> attributes;

  bool get hasCatchup => catchup != null || catchupSource != null;

  /// Request headers a player must send for this stream.
  Map<String, String> get headers => {
        'Referer': ?referrer,
        'User-Agent': ?userAgent,
      };

  @override
  String toString() => 'M3uEntry($name)'; // never print the URL: may hold creds
}

final _attrRe = RegExp(r'([A-Za-z0-9_\-]+)="([^"]*)"');

/// Parses one `#EXTINF:` line body (after the colon) into attributes + title.
({Map<String, String> attrs, String title}) parseExtinf(String body) {
  final attrs = <String, String>{};
  for (final m in _attrRe.allMatches(body)) {
    attrs[m.group(1)!.toLowerCase()] = m.group(2)!;
  }
  // Title is after the last comma that is outside quotes.
  var inQuote = false;
  var comma = -1;
  for (var i = 0; i < body.length; i++) {
    final c = body.codeUnitAt(i);
    if (c == 0x22) inQuote = !inQuote;
    if (c == 0x2c && !inQuote) comma = i;
  }
  final title = comma >= 0 ? body.substring(comma + 1).trim() : '';
  return (attrs: attrs, title: title);
}

/// Incremental line-based parser. Feed lines, collect entries.
class M3uLineParser {
  M3uLineParser({this.limits = const M3uLimits()});
  final M3uLimits limits;

  int entryCount = 0;
  bool sawHeader = false;
  Map<String, String>? _attrs;
  String _title = '';
  String? _referrer;
  String? _userAgent;
  String? _groupOverride;

  /// Returns an entry when [line] completes one, else null.
  M3uEntry? addLine(String raw) {
    if (raw.length > limits.maxLineLength) {
      // Over-long lines are dropped (and reset pending state), not fatal.
      _reset();
      return null;
    }
    final line = raw.trim();
    if (line.isEmpty) return null;
    if (line.startsWith('#')) {
      final upper = line.toUpperCase();
      if (upper.startsWith('#EXTM3U')) {
        sawHeader = true;
      } else if (upper.startsWith('#EXTINF:')) {
        final p = parseExtinf(line.substring(8));
        _attrs = p.attrs;
        _title = p.title;
      } else if (upper.startsWith('#EXTVLCOPT:')) {
        final kv = line.substring(11);
        final eq = kv.indexOf('=');
        if (eq > 0) {
          final k = kv.substring(0, eq).trim().toLowerCase();
          final v = kv.substring(eq + 1).trim();
          if (k == 'http-referrer' || k == 'http-referer') _referrer = v;
          if (k == 'http-user-agent') _userAgent = v;
        }
      } else if (upper.startsWith('#EXTGRP:')) {
        _groupOverride = line.substring(8).trim();
      }
      // #KODIPROP and every other directive: ignored.
      return null;
    }
    // URL line.
    if (_attrs == null) {
      _reset();
      return null; // URL without EXTINF: skip
    }
    if (entryCount >= limits.maxEntries) {
      throw M3uLimitException('more than ${limits.maxEntries} entries');
    }
    final a = _attrs!;
    final entry = M3uEntry(
      url: line,
      name: _title.isNotEmpty ? _title : (a['tvg-name'] ?? line),
      tvgId: _nonEmpty(a['tvg-id']),
      tvgName: _nonEmpty(a['tvg-name']),
      logo: _nonEmpty(a['tvg-logo']),
      group: _nonEmpty(a['group-title']) ?? _nonEmpty(_groupOverride),
      catchup: _nonEmpty(a['catchup'] ?? a['catchup-type']),
      catchupDays: int.tryParse(a['catchup-days'] ?? ''),
      catchupSource: _nonEmpty(a['catchup-source']),
      referrer: _referrer,
      userAgent: _userAgent,
      attributes: a,
    );
    entryCount++;
    _reset();
    return entry;
  }

  void _reset() {
    _attrs = null;
    _title = '';
    _referrer = null;
    _userAgent = null;
    _groupOverride = null;
  }

  static String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;
}

/// Parses a whole in-memory string.
List<M3uEntry> parseM3u(String text, {M3uLimits limits = const M3uLimits()}) {
  if (text.length > limits.maxBytes) {
    throw M3uLimitException('playlist larger than ${limits.maxBytes} bytes');
  }
  final p = M3uLineParser(limits: limits);
  final out = <M3uEntry>[];
  for (final l in const LineSplitter().convert(text)) {
    final e = p.addLine(l);
    if (e != null) out.add(e);
  }
  return out;
}

/// Streams entries out of a byte stream without buffering the whole body.
Stream<M3uEntry> parseM3uStream(
  Stream<List<int>> bytes, {
  M3uLimits limits = const M3uLimits(),
}) async* {
  final p = M3uLineParser(limits: limits);
  var total = 0;
  final counted = bytes.map((c) {
    total += c.length;
    if (total > limits.maxBytes) {
      throw M3uLimitException('playlist larger than ${limits.maxBytes} bytes');
    }
    return c;
  });
  // allowMalformed: stray bytes in a playlist must not abort the parse.
  final lines = counted
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter());
  await for (final l in lines) {
    final e = p.addLine(l);
    if (e != null) yield e;
  }
}
