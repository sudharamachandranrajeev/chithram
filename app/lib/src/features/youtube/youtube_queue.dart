import 'dart:async';

import 'package:innertube/innertube.dart';

import '../../player/play_request.dart';
import 'feed/taste.dart';

/// The best video to play after the one that ends.
///
/// [related] is YouTube's own order. Videos already played in this session,
/// videos the profile has [TasteProfile.seen], live streams and channels the
/// user turned away from are left out; the rest are ranked by the profile's
/// affinity plus a prior for YouTube's order. When everything was seen, the
/// first one not played this session wins, so a long session never stops.
VideoItem? pickNextVideo(
  List<VideoItem> related,
  TasteProfile taste, {
  Set<String> played = const {},
}) {
  final seen = taste.seen;
  final fresh = [
    for (final v in related)
      if (!v.isLive && !played.contains(v.videoId)) v,
  ];
  if (fresh.isEmpty) return null;
  final candidates = [
    for (final v in fresh)
      if (!seen.contains(v.videoId) &&
          (taste.channels[v.channelId] ?? 0) > -0.3)
        v,
  ];
  if (candidates.isEmpty) return fresh.first;
  VideoItem? best;
  var bestScore = double.negativeInfinity;
  for (var i = 0; i < candidates.length; i++) {
    final v = candidates[i];
    final score = 1 / (1 + 0.15 * i) + 0.6 * taste.affinity(v);
    if (score > bestScore) {
      best = v;
      bestScore = score;
    }
  }
  return best;
}

/// The queue of one YouTube viewing session: Up Next (autoplay) and Previous.
class YouTubeQueue implements PlayQueue {
  YouTubeQueue({
    required VideoItem first,
    required this.relatedOf,
    required this.profile,
    required this.build,
    required this.autoplayOn,
  }) {
    _items.add(first);
    _played.add(first.videoId);
  }

  /// YouTube's related list for a video id.
  final Future<List<VideoItem>> Function(String videoId) relatedOf;
  final TasteProfile Function() profile;

  /// The request for a video, tagged with the taste source and this queue.
  final PlayRequest Function(
    VideoItem v, {
    required String source,
    required PlayQueue queue,
  })
  build;
  final bool Function() autoplayOn;

  final _items = <VideoItem>[];
  final _played = <String>{};
  int _at = 0;
  VideoItem? _prepared;
  Future<VideoItem?>? _preparing;

  @override
  bool get autoplay => autoplayOn();

  /// The item playing now.
  VideoItem get current => _items[_at];

  @override
  Future<PlayRequest?> prepareNext() async {
    final v = await _next();
    return v == null ? null : build(v, source: 'autoplay', queue: this);
  }

  Future<VideoItem?> _next() {
    // Going forward again after Previous replays what was there.
    if (_at + 1 < _items.length) return Future.value(_items[_at + 1]);
    final ready = _prepared;
    if (ready != null) return Future.value(ready);
    return _preparing ??= () async {
      try {
        final related = await relatedOf(current.videoId);
        return _prepared = pickNextVideo(related, profile(), played: _played);
      } catch (_) {
        return null;
      } finally {
        _preparing = null;
      }
    }();
  }

  @override
  PlayRequest? takeNext() {
    VideoItem? v;
    if (_at + 1 < _items.length) {
      v = _items[++_at];
    } else {
      v = _prepared;
      if (v == null) return null;
      _prepared = null;
      _items.add(v);
      _played.add(v.videoId);
      _at = _items.length - 1;
    }
    return build(v, source: 'autoplay', queue: this);
  }

  @override
  bool get hasPrevious => _at > 0;

  @override
  PlayRequest? takePrevious() {
    if (_at == 0) return null;
    // A candidate picked for the old position no longer follows this one.
    if (_at + 1 >= _items.length) _prepared = null;
    return build(_items[--_at], source: 'autoplay', queue: this);
  }
}
