import 'dart:math' as math;

import 'models.dart';
import 'util.dart';

/// One size of a video's preview sprites ("storyboard"): sheets of
/// [cols] x [rows] frames of [width] x [height], one frame every [interval].
class StoryboardLevel {
  const StoryboardLevel({
    required this.index,
    required this.width,
    required this.height,
    required this.count,
    required this.cols,
    required this.rows,
    required this.interval,
    required this.urlTemplate,
    required this.name,
    required this.sigh,
  });

  final int index;
  final int width;
  final int height;

  /// Frames in all sheets.
  final int count;
  final int cols;
  final int rows;
  final Duration interval;
  final String urlTemplate;
  final String name;
  final String sigh;

  int get framesPerSheet => cols * rows;
  int get sheets => (count / framesPerSheet).ceil();

  /// The image of sheet [i] (0-based).
  Uri sheetUrl(int i) {
    final file = name.replaceAll(r'$M', '$i');
    final base = urlTemplate
        .replaceAll(r'$L', '$index')
        .replaceAll(r'$N', file);
    return Uri.parse('$base&sigh=$sigh');
  }

  /// Where the frame for [t] is.
  StoryboardFrame frameAt(Duration t) {
    final step = interval.inMilliseconds;
    var i = step > 0 ? t.inMilliseconds ~/ step : 0;
    i = math.max(0, math.min(count - 1, i));
    final sheet = i ~/ framesPerSheet;
    final within = i % framesPerSheet;
    return StoryboardFrame(
      sheet: sheet,
      url: sheetUrl(sheet),
      col: within % cols,
      row: within ~/ cols,
    );
  }
}

class StoryboardFrame {
  const StoryboardFrame({
    required this.sheet,
    required this.url,
    required this.col,
    required this.row,
  });
  final int sheet;
  final Uri url;
  final int col;
  final int row;
}

/// The levels in a player response's `storyboards.playerStoryboardSpecRenderer
/// .spec`: `base|w#h#count#cols#rows#intervalMs#name#sigh|...`. [duration]
/// fills the interval of levels that give none (the first one does not).
/// Malformed levels are skipped; no spec gives an empty list.
List<StoryboardLevel> parseStoryboardSpec(String? spec, {Duration? duration}) {
  if (spec == null || spec.isEmpty) return const [];
  final parts = spec.split('|');
  if (parts.length < 2) return const [];
  final base = parts.first;
  final out = <StoryboardLevel>[];
  for (var i = 1; i < parts.length; i++) {
    final f = parts[i].split('#');
    if (f.length < 8) continue;
    final w = int.tryParse(f[0]),
        h = int.tryParse(f[1]),
        count = int.tryParse(f[2]);
    final cols = int.tryParse(f[3]),
        rows = int.tryParse(f[4]),
        ms = int.tryParse(f[5]);
    if (w == null ||
        h == null ||
        count == null ||
        cols == null ||
        rows == null ||
        ms == null)
      continue;
    if (w <= 0 || h <= 0 || count <= 0 || cols <= 0 || rows <= 0) continue;
    var interval = Duration(milliseconds: ms);
    if (ms <= 0 && duration != null && duration > Duration.zero) {
      interval = Duration(milliseconds: duration.inMilliseconds ~/ count);
    }
    out.add(
      StoryboardLevel(
        index: i - 1,
        width: w,
        height: h,
        count: count,
        cols: cols,
        rows: rows,
        interval: interval,
        urlTemplate: base,
        name: f[6],
        sigh: f.sublist(7).join('#'),
      ),
    );
  }
  return out;
}

/// The level to show at [targetWidth] logical pixels: the smallest that is at
/// least that wide (sharp, cheap to decode), else the largest. Level 0 is
/// skipped when the sheets are tiny and a better one exists.
StoryboardLevel? pickStoryboardLevel(
  List<StoryboardLevel> levels, {
  int targetWidth = 240,
}) {
  final usable = levels.where((l) => l.interval > Duration.zero).toList();
  if (usable.isEmpty) return null;
  usable.sort((a, b) => a.width.compareTo(b.width));
  for (final l in usable) {
    if (l.width >= targetWidth) return l;
  }
  return usable.last;
}

/// A chapter: from [start] until the next one.
class Chapter {
  const Chapter(this.start, this.title);
  final Duration start;
  final String title;
}

/// Chapters in a `/next` response (the player bar's chapter markers, else the
/// chapters panel), or the timestamps in its description.
List<Chapter> parseChapters(
  Object? next, {
  String description = '',
  Duration? duration,
}) {
  final fromMarkers = <Chapter>[];
  for (final c in findAll(next, 'chapterRenderer')) {
    final ms = toInt(c['timeRangeStartMillis']);
    final title = textOf(c['title']);
    if (ms != null && title.isNotEmpty)
      fromMarkers.add(Chapter(Duration(milliseconds: ms), title));
  }
  if (fromMarkers.length < 2) {
    fromMarkers.clear();
    for (final c in findAll(next, 'macroMarkersListItemRenderer')) {
      final tap = asJson(asJson(c['onTap'])['watchEndpoint']);
      final secs =
          toInt(tap['startTimeSeconds']) ??
          parseClockSeconds(textOf(c['timeDescription']));
      final title = textOf(c['title']);
      if (secs != null && title.isNotEmpty)
        fromMarkers.add(Chapter(Duration(seconds: secs), title));
    }
  }
  final clean = _cleanChapters(fromMarkers, duration, minCount: 2);
  if (clean.isNotEmpty) return clean;
  return chaptersFromDescription(description, duration: duration);
}

int? parseClockSeconds(String text) {
  final m = RegExp(r'^(?:(\d{1,2}):)?(\d{1,2}):(\d{2})$')
      .firstMatch(text.trim());
  if (m == null) return null;
  return (int.tryParse(m[1] ?? '0') ?? 0) * 3600 +
      int.parse(m[2]!) * 60 +
      int.parse(m[3]!);
}

final _stampLine = RegExp(
  r'^\W{0,3}((?:\d{1,2}:)?\d{1,2}:\d{2})\W{0,3}\s*(.*?)\s*$',
);
final _stampTrailing = RegExp(
  r'^(.*?)[\s\-–—:|(\[]+((?:\d{1,2}:)?\d{1,2}:\d{2})[)\]]?\s*$',
);

/// Chapters from a description, by YouTube's rule: the list starts at 0:00,
/// has at least three entries in order, each at least ten seconds long.
List<Chapter> chaptersFromDescription(
  String description, {
  Duration? duration,
}) {
  final found = <Chapter>[];
  for (final raw in description.split('\n')) {
    final line = raw.trim();
    var m = _stampLine.firstMatch(line);
    String? stamp, title;
    if (m != null && m[2]!.isNotEmpty) {
      stamp = m[1];
      title = m[2];
    } else {
      m = _stampTrailing.firstMatch(line);
      if (m != null && m[1]!.isNotEmpty) {
        stamp = m[2];
        title = m[1];
      }
    }
    if (stamp == null || title == null) continue;
    final secs = parseClockSeconds(stamp);
    if (secs != null)
      found.add(
        Chapter(
          Duration(seconds: secs),
          title.replaceAll(RegExp(r'^[\s\-–—:|]+'), ''),
        ),
      );
  }
  if (found.isEmpty || found.first.start != Duration.zero) return const [];
  for (var i = 1; i < found.length; i++) {
    if (found[i].start - found[i - 1].start < const Duration(seconds: 10))
      return const [];
  }
  return _cleanChapters(found, duration, minCount: 3);
}

List<Chapter> _cleanChapters(
  List<Chapter> list,
  Duration? duration, {
  required int minCount,
}) {
  final sorted = [...list]..sort((a, b) => a.start.compareTo(b.start));
  final out = <Chapter>[];
  for (final c in sorted) {
    if (duration != null && duration > Duration.zero && c.start >= duration)
      continue;
    if (out.isNotEmpty && out.last.start == c.start) continue;
    out.add(c);
  }
  if (out.length < minCount) return const [];
  // The bar starts at zero: the first chapter covers it.
  if (out.first.start != Duration.zero)
    out[0] = Chapter(Duration.zero, out.first.title);
  return out;
}

/// One slice of the "most replayed" graph.
class HeatBin {
  const HeatBin(this.start, this.length, this.intensity);
  final Duration start;
  final Duration length;

  /// 0..1, 1 = the most replayed part.
  final double intensity;
}

/// The "most replayed" bins in a `/next` response: the player bar's heat
/// markers, or the heatmap markers in `frameworkUpdates`.
List<HeatBin> parseHeatmap(Object? next) {
  final out = <HeatBin>[];
  for (final m in findAll(next, 'heatMarkerRenderer')) {
    final start = toInt(m['timeRangeStartMillis']);
    final len = toInt(m['markerDurationMillis']);
    final v = m['heatMarkerIntensityScoreNormalized'];
    if (start != null && len != null && len > 0 && v is num) {
      out.add(
        HeatBin(
          Duration(milliseconds: start),
          Duration(milliseconds: len),
          v.toDouble().clamp(0.0, 1.0),
        ),
      );
    }
  }
  if (out.isEmpty) {
    for (final list in findAll(next, 'markersList')) {
      if (!asString(list['markerType']).contains('HEATMAP')) continue;
      for (final raw in asList(list['markers'])) {
        final m = asJson(raw);
        final start = toInt(m['startMillis']);
        final len = toInt(m['durationMillis']);
        final v = m['intensityScoreNormalized'];
        if (start != null && len != null && len > 0 && v is num) {
          out.add(
            HeatBin(
              Duration(milliseconds: start),
              Duration(milliseconds: len),
              v.toDouble().clamp(0.0, 1.0),
            ),
          );
        }
      }
    }
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// The description text in a `/next` response.
String descriptionOf(Object? next) {
  for (final s in findAll(next, 'videoSecondaryInfoRenderer')) {
    final attributed = asString(asJson(s['attributedDescription'])['content']);
    if (attributed.isNotEmpty) return attributed;
    final text = textOf(s['description']);
    if (text.isNotEmpty) return text;
  }
  return '';
}

/// What one `/next` call tells about a video besides its related list.
class WatchInfo {
  const WatchInfo({
    this.related = const [],
    this.chapters = const [],
    this.heatmap = const [],
  });
  final List<VideoItem> related;
  final List<Chapter> chapters;
  final List<HeatBin> heatmap;
}
