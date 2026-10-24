import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:innertube/innertube.dart';

import '../../../core/paths.dart';

/// One video the user played, and how much of it.
class Watch {
  const Watch({
    required this.item,
    required this.at,
    required this.position,
    required this.fraction,
    required this.reward,
    this.source,
  });

  final VideoItem item;
  final DateTime at;
  final Duration position;

  /// 0..1 of the length; 0 for live.
  final double fraction;

  /// What this play said about the user's taste (see [TasteProfile.rewardFor]).
  final double reward;

  /// The Home rail it was started from, if any.
  final String? source;

  Map<String, Object?> toJson() => {
        'item': item.toJson(),
        'at': at.toUtc().toIso8601String(),
        'pos': position.inSeconds,
        'f': fraction,
        'r': reward,
        if (source != null) 'src': source,
      };

  static Watch fromJson(Map<String, Object?> j) => Watch(
        item: VideoItem.fromJson((j['item'] as Map).cast()),
        at: DateTime.parse(j['at'] as String),
        position: Duration(seconds: j['pos'] as int),
        fraction: (j['f'] as num).toDouble(),
        reward: (j['r'] as num).toDouble(),
        source: j['src'] as String?,
      );
}

/// What the user likes on YouTube, learnt on the device from what they watch
/// and search. Nothing leaves the device.
///
/// Every play adds a reward (positive when most of a video was watched,
/// negative when it was abandoned at once) to the video's channel, the words of
/// its title and the Home rail it came from. Old scores fade with a 30-day
/// half-life, so the profile follows the user as their taste moves.
class TasteProfile {
  TasteProfile();

  static const halfLife = Duration(days: 30);
  static const _maxHistory = 300, _maxTerms = 400, _maxChannels = 150;

  /// Channel id -> score, and the channel's name for display.
  final channels = <String, double>{};
  final channelNames = <String, String>{};

  /// Title word -> score.
  final terms = <String, double>{};

  /// Home rail id -> score: orders the popular rails.
  final sources = <String, double>{};

  /// Newest first, one entry per video.
  final history = <Watch>[];
  DateTime? updatedAt;

  bool get isEmpty => history.isEmpty && terms.isEmpty;

  /// How much a play of [position] out of [duration] says the user liked it.
  /// A zero [duration] is live: only the time spent counts.
  static double rewardFor(Duration position, Duration duration) {
    final seconds = position.inSeconds;
    if (duration <= Duration.zero) {
      if (seconds >= 600) return 1;
      if (seconds >= 120) return 0.5;
      return seconds < 30 ? -0.3 : 0.15;
    }
    final f = position.inMilliseconds / duration.inMilliseconds;
    if (f >= 0.7) return 1;
    if (f >= 0.3) return 0.5;
    // Left within half a minute: not what they wanted.
    if (seconds < 30 && f < 0.2) return -0.5;
    return 0.15;
  }

  /// Learns from one play. [source] is the Home rail it was started from.
  void watched(VideoItem v, {required Duration position, required Duration duration, String? source, DateTime? now}) {
    final at = now ?? DateTime.now();
    _decayTo(at);
    final reward = rewardFor(position, duration);
    if (v.channelId.isNotEmpty) {
      _add(channels, v.channelId, reward);
      if (v.author.isNotEmpty) channelNames[v.channelId] = v.author;
    }
    final words = titleTerms(v.title);
    for (final t in words) {
      // A long title spreads the same reward over more words.
      _add(terms, t, reward * 0.6 / math.sqrt(words.length));
    }
    if (source != null) _add(sources, source, reward);
    final previous = history.indexWhere((w) => w.item.videoId == v.videoId);
    final fraction = duration > Duration.zero
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    if (previous >= 0) history.removeAt(previous);
    history.insert(0, Watch(item: v, at: at, position: position, fraction: fraction, reward: reward, source: source));
    _prune();
  }

  /// A search is a hint of interest, weaker than a watch.
  void searched(String query, {DateTime? now}) {
    final words = titleTerms(query);
    if (words.isEmpty) return;
    _decayTo(now ?? DateTime.now());
    for (final t in words) {
      _add(terms, t, 0.3);
    }
    _prune();
  }

  /// How well [v] matches the profile: its channel plus its title words.
  double affinity(VideoItem v) {
    final words = titleTerms(v.title);
    final wordScore = words.isEmpty ? 0.0 : words.fold<double>(0, (s, t) => s + (terms[t] ?? 0)) / math.sqrt(words.length);
    return (channels[v.channelId] ?? 0) + wordScore;
  }

  /// Videos to find more like: liked plays, the recent ones first (two-week
  /// half-life on top of the reward). Pairs of video and weight.
  List<(VideoItem, double)> seeds(int n, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final scored = [
      for (final w in history)
        if (w.reward > 0) (w.item, w.reward * _fade(at.difference(w.at), const Duration(days: 14))),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(n).toList();
  }

  /// Channels the user keeps coming back to, best first.
  List<String> topChannels(int n) {
    final liked = channels.entries.where((e) => e.value >= 0.8).toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in liked.take(n)) e.key];
  }

  /// Videos not to suggest again: watched past a third, or abandoned.
  Set<String> get seen => {
        for (final w in history)
          if (w.fraction >= 0.3 || w.reward < 0) w.item.videoId,
      };

  /// Started, not finished: between 5% and 90% and over half a minute in.
  List<Watch> get unfinished => [
        for (final w in history)
          if (!w.item.isLive && w.fraction >= 0.05 && w.fraction < 0.9 && w.position.inSeconds >= 30) w,
      ];

  /// Ranks candidates for "Recommended for you".
  ///
  /// - [related]: each seed's related list with the seed's weight; a video
  ///   high in a heavy seed's list scores most, and one related to several
  ///   seeds adds up.
  /// - [uploads]: new videos from the user's top channels.
  /// - [popular]: what is popular now, a weak prior so the list is never empty.
  ///
  /// Then the profile's own [affinity] is added, seen videos and disliked
  /// channels are dropped, and no channel gets more than two places.
  List<VideoItem> recommend({
    required List<(List<VideoItem>, double)> related,
    List<List<VideoItem>> uploads = const [],
    List<VideoItem> popular = const [],
    int limit = 30,
  }) {
    final score = <String, double>{};
    final byId = <String, VideoItem>{};
    void add(VideoItem v, double s) {
      byId.putIfAbsent(v.videoId, () => v);
      score[v.videoId] = (score[v.videoId] ?? 0) + s;
    }

    for (final (list, weight) in related) {
      for (var i = 0; i < list.length; i++) {
        add(list[i], weight / (1 + 0.15 * i));
      }
    }
    for (final list in uploads) {
      for (var i = 0; i < list.length; i++) {
        add(list[i], 0.5 * (channels[list[i].channelId] ?? 0).clamp(0, 2) / (1 + 0.2 * i));
      }
    }
    for (var i = 0; i < popular.length; i++) {
      add(popular[i], 0.1 / (1 + 0.05 * i));
    }
    final skip = seen;
    final ranked = [
      for (final MapEntry(key: id, value: s) in score.entries)
        if (!skip.contains(id) && (channels[byId[id]!.channelId] ?? 0) > -0.3) (byId[id]!, s + 0.6 * affinity(byId[id]!)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final perChannel = <String, int>{};
    final out = <VideoItem>[];
    for (final (v, _) in ranked) {
      final channel = v.channelId.isEmpty ? v.author : v.channelId;
      final count = perChannel[channel] ?? 0;
      if (channel.isNotEmpty && count >= 2) continue;
      perChannel[channel] = count + 1;
      out.add(v);
      if (out.length == limit) break;
    }
    return out;
  }

  static const _stopWords = {
    'the', 'and', 'for', 'with', 'from', 'you', 'your', 'this', 'that', 'are', 'was', 'what', 'how', 'why',
    'official', 'video', 'videos', 'full', 'new', 'latest', 'episode', 'part', 'live', 'watch', 'channel',
    'subscribe', 'shorts', 'feat', 'ft', 'hd', 'uhd', '4k', '1080p', '720p', 'lyrics', 'lyric', 'audio', 'version',
  };

  /// Lower-case words of [text], any script, without short or common ones.
  static List<String> titleTerms(String text) {
    final words = RegExp(r'[\p{L}\p{M}\p{N}]+', unicode: true)
        .allMatches(text.toLowerCase())
        .map((m) => m[0]!)
        .where((w) => w.runes.length >= 3 && !_stopWords.contains(w) && int.tryParse(w) == null);
    return words.toSet().take(16).toList();
  }

  static double _fade(Duration age, Duration halfLife) =>
      math.pow(0.5, age.inSeconds / halfLife.inSeconds).toDouble();

  void _decayTo(DateTime now) {
    final last = updatedAt;
    updatedAt = now;
    if (last == null || !now.isAfter(last)) return;
    final k = _fade(now.difference(last), halfLife);
    for (final map in [channels, terms, sources]) {
      map.updateAll((_, v) => v * k);
    }
  }

  static void _add(Map<String, double> map, String key, double v) => map[key] = (map[key] ?? 0) + v;

  void _prune() {
    void cap(Map<String, double> map, int max) {
      map.removeWhere((_, v) => v.abs() < 0.02);
      if (map.length <= max) return;
      final keep = (map.entries.toList()..sort((a, b) => b.value.abs().compareTo(a.value.abs()))).take(max).toList();
      map
        ..clear()
        ..addEntries(keep);
    }

    cap(channels, _maxChannels);
    cap(terms, _maxTerms);
    cap(sources, 50);
    channelNames.removeWhere((id, _) => !channels.containsKey(id));
    if (history.length > _maxHistory) history.removeRange(_maxHistory, history.length);
  }

  Map<String, Object?> toJson() => {
        'v': 1,
        if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
        'channels': channels,
        'channelNames': channelNames,
        'terms': terms,
        'sources': sources,
        'history': [for (final w in history) w.toJson()],
      };

  static TasteProfile fromJson(Map<String, Object?> j) {
    Map<String, double> scores(Object? m) => {
          for (final MapEntry(:key, :value) in ((m as Map?) ?? const {}).entries) key as String: (value as num).toDouble(),
        };
    return TasteProfile()
      ..updatedAt = j['updatedAt'] == null ? null : DateTime.parse(j['updatedAt'] as String)
      ..channels.addAll(scores(j['channels']))
      ..channelNames.addAll(((j['channelNames'] as Map?) ?? const {}).cast<String, String>())
      ..terms.addAll(scores(j['terms']))
      ..sources.addAll(scores(j['sources']))
      ..history.addAll([for (final w in (j['history'] as List?) ?? const []) Watch.fromJson((w as Map).cast())]);
  }
}

/// The [TasteProfile], kept in `youtube_taste.json` (or only in memory).
/// Loaded on first use, never before the first frame; written after each
/// change, one write at a time.
class TasteStore extends ChangeNotifier {
  TasteStore(this._file);

  /// Nothing is read or written. For tests and previews.
  TasteStore.memory() : _file = null;

  final File? _file;
  TasteProfile _profile = TasteProfile();
  Future<void>? _loading;
  Future<void> _writing = Future.value();

  TasteProfile get profile => _profile;

  Future<void> load() => _loading ??= () async {
        final file = _file;
        if (file == null) return;
        try {
          if (!await file.exists()) return;
          final j = jsonDecode(await file.readAsString());
          if (j is Map && j['v'] == 1) {
            _profile = TasteProfile.fromJson(j.cast());
            notifyListeners();
          }
        } catch (_) {
          // Corrupt: start learning again rather than fail.
        }
      }();

  Future<void> watched(VideoItem v, {required Duration position, required Duration duration, String? source}) async {
    await load();
    _profile.watched(v, position: position, duration: duration, source: source);
    await _changed();
  }

  Future<void> searched(String query) async {
    await load();
    _profile.searched(query);
    await _changed();
  }

  /// Forgets everything learnt.
  Future<void> clear() async {
    await load();
    _profile = TasteProfile();
    await _changed();
  }

  Future<void> _changed() {
    notifyListeners();
    final file = _file;
    if (file == null) return Future.value();
    final json = jsonEncode(_profile.toJson());
    return _writing = _writing.then((_) => writeFileAtomic(file, json)).catchError((Object _) {});
  }
}
