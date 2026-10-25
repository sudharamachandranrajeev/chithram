import 'ads.dart';

/// Playlist-level tags: kept as they are, before the first segment.
const _headerTags = {
  '#EXTM3U', '#EXT-X-VERSION', '#EXT-X-TARGETDURATION', '#EXT-X-MEDIA-SEQUENCE', //
  '#EXT-X-DISCONTINUITY-SEQUENCE', '#EXT-X-PLAYLIST-TYPE', '#EXT-X-INDEPENDENT-SEGMENTS',
  '#EXT-X-START', '#EXT-X-ALLOW-CACHE', '#EXT-X-I-FRAMES-ONLY',
};

/// Low-latency tags. Dropped: the player falls back to whole segments, and
/// blocking reloads would bypass the filter.
const _lowLatencyTags = {
  '#EXT-X-SERVER-CONTROL', '#EXT-X-PART-INF', '#EXT-X-PART', '#EXT-X-PRELOAD-HINT', //
  '#EXT-X-RENDITION-REPORT', '#EXT-X-SKIP',
};

/// A stitched-in break on another host longer than this is kept: it is more
/// likely a second part of the programme than an ad.
const _maxForeignBreak = Duration(seconds: 150);

final _uriAttr = RegExp(r'URI="([^"]*)"');

/// Rewrites an HLS playlist fetched from [base] so that no ad plays:
///
/// * ad breaks marked with `#EXT-X-CUE-OUT` / `#EXT-X-CUE-IN` or SCTE-35
///   date ranges are removed, and so are interstitials;
/// * segments whose URL looks like an ad ([isAdUrl]) are removed;
/// * a short run between discontinuities served from another host than the
///   rest of the stream (a stitched-in ad) is removed.
///
/// Every URI becomes absolute. In a multivariant playlist, [route] maps each
/// variant and rendition playlist (so they are filtered too).
String rewritePlaylist(String text, Uri base, {Uri Function(Uri playlist)? route}) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  if (lines.any((l) => l.startsWith('#EXT-X-STREAM-INF'))) {
    return _rewriteMultivariant(lines, base, route ?? (u) => u);
  }
  return _rewriteMedia(lines, base);
}

String _rewriteMultivariant(List<String> lines, Uri base, Uri Function(Uri) route) {
  final out = <String>[];
  var nextIsVariant = false;
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#')) {
      if (line.startsWith('#EXT-X-STREAM-INF')) nextIsVariant = true;
      final playlist = line.startsWith('#EXT-X-MEDIA') || line.startsWith('#EXT-X-I-FRAME-STREAM-INF');
      out.add(_absUris(line, base, playlist ? route : null));
      continue;
    }
    final url = _abs(base, line);
    if (url == null) continue;
    out.add((nextIsVariant ? route(url) : url).toString());
    nextIsVariant = false;
  }
  return '${out.join('\n')}\n';
}

class _Segment {
  _Segment(this.tags, this.url, this.duration, {required this.key, required this.map, required this.discontinuity, required this.ad, required this.group});

  final List<String> tags;
  final Uri url;
  final double duration;
  final String? key;
  final String? map;
  final bool discontinuity;
  final bool ad;
  final int group;
  bool drop = false;
}

String _rewriteMedia(List<String> lines, Uri base) {
  final header = <String>[];
  final segments = <_Segment>[];
  var tags = <String>[];
  String? key;
  String? map;
  var discontinuity = false;
  var inBreak = false;
  var group = 0;
  var ended = false;
  var duration = 0.0;
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final name = line.split(':').first;
    if (!line.startsWith('#')) {
      final url = _abs(base, line);
      if (url != null) {
        segments.add(_Segment(tags, url, duration,
            key: key, map: map, discontinuity: discontinuity, ad: inBreak || isAdUrl(url), group: group));
      }
      tags = [];
      discontinuity = false;
      duration = 0;
    } else if (_headerTags.contains(name) && segments.isEmpty) {
      header.add(line);
    } else if (_lowLatencyTags.contains(name)) {
      continue;
    } else if (name == '#EXT-X-ENDLIST') {
      ended = true;
    } else if (name == '#EXT-X-KEY') {
      key = _absUris(line, base, null);
    } else if (name == '#EXT-X-MAP') {
      map = _absUris(line, base, null);
    } else if (name == '#EXT-X-DISCONTINUITY') {
      discontinuity = true;
      group++;
    } else if (name == '#EXT-X-CUE-OUT' || name == '#EXT-X-CUE-OUT-CONT') {
      inBreak = true;
    } else if (name == '#EXT-X-CUE-IN') {
      inBreak = false;
    } else if (name == '#EXT-X-DATERANGE') {
      if (line.contains('SCTE35-OUT')) inBreak = true;
      if (line.contains('SCTE35-IN')) inBreak = false;
      if (!line.contains('SCTE35') && !line.contains('com.apple.hls.interstitial')) tags.add(_absUris(line, base, null));
    } else {
      if (name == '#EXTINF') duration = double.tryParse(line.substring(8).split(',').first.trim()) ?? 0;
      tags.add(_absUris(line, base, null));
    }
  }

  for (final s in segments) {
    s.drop = s.ad;
  }
  _dropForeignBreaks(segments);

  final out = [...header];
  String? lastKey;
  String? lastMap;
  var cut = false;
  var first = true;
  for (final s in segments) {
    if (s.drop) {
      cut = true;
      continue;
    }
    if (!first && (cut || s.discontinuity)) out.add('#EXT-X-DISCONTINUITY');
    if (s.key != lastKey && s.key != null) out.add(s.key!);
    if (s.map != lastMap && s.map != null) out.add(s.map!);
    lastKey = s.key;
    lastMap = s.map;
    out.addAll(s.tags);
    out.add(s.url.toString());
    cut = false;
    first = false;
  }
  if (ended) out.add('#EXT-X-ENDLIST');
  return '${out.join('\n')}\n';
}

/// Marks short discontinuity groups served entirely from a host other than
/// the stream's main one.
void _dropForeignBreaks(List<_Segment> segments) {
  final byHost = <String, double>{};
  for (final s in segments) {
    byHost.update(s.url.host, (d) => d + s.duration, ifAbsent: () => s.duration);
  }
  if (byHost.length < 2) return;
  final main = byHost.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  final groups = <int, List<_Segment>>{};
  for (final s in segments) {
    groups.putIfAbsent(s.group, () => []).add(s);
  }
  if (groups.length < 2) return;
  for (final g in groups.values) {
    final seconds = g.fold<double>(0, (n, s) => n + s.duration);
    if (g.every((s) => s.url.host != main) && seconds * 1000 <= _maxForeignBreak.inMilliseconds) {
      for (final s in g) {
        s.drop = true;
      }
    }
  }
}

/// [line] with each `URI="..."` made absolute, and passed through [route]
/// when given.
String _absUris(String line, Uri base, Uri Function(Uri)? route) => line.replaceAllMapped(_uriAttr, (m) {
      final url = _abs(base, m.group(1)!);
      if (url == null) return m.group(0)!;
      return 'URI="${route == null ? url : route(url)}"';
    });

Uri? _abs(Uri base, String ref) {
  try {
    return base.resolve(ref.trim());
  } on FormatException {
    return null;
  }
}
