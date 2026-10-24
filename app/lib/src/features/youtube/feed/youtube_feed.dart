import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:innertube/innertube.dart';

import '../../../core/paths.dart';
import '../youtube_service.dart';
import 'taste.dart';

/// One row of videos on Home.
class FeedRail {
  const FeedRail(this.id, this.title, this.items);

  /// Stable: plays started from it teach the profile which rails to put first.
  final String id;
  final String title;
  final List<VideoItem> items;
}

class FeedState {
  const FeedState({this.hero = const [], this.rails = const [], this.loading = false, this.error});

  /// The billboard: the first suggestions, else the first popular videos.
  final List<VideoItem> hero;
  final List<FeedRail> rails;
  final bool loading;

  /// Set only when nothing could be fetched and nothing was cached.
  final String? error;
}

/// YouTube's own topic channels. Their home tabs list what is popular in the
/// region right now (YouTube has no trending list any more).
const popularTopics = [
  ('popular-music', 'Popular music', 'UC-9-kyTW8ZkZNDHQJ6FgpwQ'),
  ('popular-live', 'Live now', 'UC4R8DWoMoI7CAwX8_LjQHig'),
  ('popular-sports', 'Sports', 'UCEgdi0XIXXZ-qJOFPf4JSKw'),
  ('popular-news', 'News', 'UCYfdidRxbB8Qhf0Nx7ioOYw'),
  ('popular-gaming', 'Gaming', 'UCOpNcN46UbXVtpKMrmU4Abg'),
];

class _Cached {
  const _Cached(this.at, this.items);
  final DateTime at;
  final List<VideoItem> items;

  Map<String, Object?> toJson() => {'at': at.toUtc().toIso8601String(), 'items': [for (final v in items) v.toJson()]};

  static _Cached fromJson(Map<String, Object?> j) => _Cached(
        DateTime.parse(j['at'] as String),
        [for (final v in j['items'] as List) VideoItem.fromJson((v as Map).cast())],
      );
}

/// Home's YouTube rails: popular now, and, as the [TasteStore] learns,
/// Continue watching, Recommended for you and Because you watched.
///
/// Fetched lists are kept in `youtube_feed.json`, so Home shows the last ones
/// at once and only stale lists are fetched again. A new play re-ranks at
/// once from what is cached, then fetches the related list of a newly liked
/// video.
class YouTubeFeed {
  YouTubeFeed({required this.youtube, this.cacheFile, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final YouTubeService youtube;

  /// Null: nothing is read or written.
  final File? cacheFile;
  final DateTime Function() _clock;

  static const popularTtl = Duration(hours: 3);
  static const relatedTtl = Duration(days: 3);
  static const uploadsTtl = Duration(hours: 6);
  static const _minRail = 4;

  final _state = ValueNotifier(const FeedState(loading: true));
  ValueListenable<FeedState> get state => _state;

  final _popular = <String, _Cached>{};
  final _related = <String, _Cached>{};
  final _uploads = <String, _Cached>{};

  Future<void>? _opening;
  Future<void>? _refreshing;
  bool _again = false;

  TasteStore get _taste => youtube.taste;

  /// Home is on screen: shows the cache, then fetches what is stale. Only the
  /// first call does anything.
  Future<void> open() => _opening ??= () async {
        await (_taste.load(), _loadCache()).wait;
        _taste.addListener(_tasteChanged);
        _rebuild();
        await refresh();
      }();

  void _tasteChanged() {
    _rebuild();
    unawaited(refresh());
  }

  /// Fetches stale lists (all of them with [force]). A call while one runs
  /// makes it go round once more.
  Future<void> refresh({bool force = false}) {
    final running = _refreshing;
    if (running != null) {
      _again = true;
      return running;
    }
    return _refreshing = () async {
      try {
        do {
          _again = false;
          await _fetchStale(force);
          force = false;
        } while (_again);
      } finally {
        _refreshing = null;
      }
    }();
  }

  /// Seeds for related lists: the best liked plays plus the latest one.
  List<(VideoItem, double)> _seeds(TasteProfile taste) {
    final seeds = taste.seeds(4);
    final latest = _latestLiked(taste);
    if (latest != null && !seeds.any((s) => s.$1.videoId == latest.videoId)) seeds.add((latest, 0.5));
    return seeds;
  }

  static VideoItem? _latestLiked(TasteProfile taste) => taste.history.where((w) => w.reward > 0).firstOrNull?.item;

  Future<void> _fetchStale(bool force) async {
    final now = _clock();
    final taste = _taste.profile;
    final browse = youtube.browse;
    bool stale(_Cached? c, Duration ttl) => force || c == null || now.difference(c.at) > ttl;
    Future<bool> fetch(Future<List<VideoItem>> Function() get, Map<String, _Cached> into, String key) async {
      try {
        into[key] = _Cached(now, await get());
        return true;
      } catch (e) {
        debugPrint('youtube feed: $key: $e');
        return false;
      }
    }

    final seeds = _seeds(taste);
    final channels = taste.topChannels(3);
    final jobs = [
      for (final (id, _, channel) in popularTopics)
        if (stale(_popular[id], popularTtl)) fetch(() => browse.channelHome(channel), _popular, id),
      for (final (v, _) in seeds)
        if (stale(_related[v.videoId], relatedTtl)) fetch(() => browse.related(v.videoId), _related, v.videoId),
      for (final c in channels)
        if (stale(_uploads[c], uploadsTtl)) fetch(() async => (await browse.channelUploads(c)).items, _uploads, c),
    ];
    if (jobs.isEmpty) return;
    _state.value = FeedState(hero: _state.value.hero, rails: _state.value.rails, loading: true);
    final ok = await Future.wait(jobs);
    // Keep what the next rebuild can use, a little more so a small change in
    // the ranking does not refetch.
    final keepSeeds = {for (final (v, _) in taste.seeds(8)) v.videoId, for (final (v, _) in seeds) v.videoId};
    _related.removeWhere((id, _) => !keepSeeds.contains(id));
    final keepChannels = taste.topChannels(6).toSet();
    _uploads.removeWhere((id, _) => !keepChannels.contains(id));
    _rebuild(failed: !ok.contains(true));
    await _saveCache();
  }

  void _rebuild({bool failed = false}) {
    final taste = _taste.profile;
    final rails = <FeedRail>[];

    final unfinished = [for (final w in taste.unfinished.take(20)) w.item];
    if (unfinished.isNotEmpty) rails.add(FeedRail('continue', 'Continue watching', unfinished));

    // Popular rails, the ones the user plays from most first (stable order
    // otherwise).
    final popular = [
      for (final (i, (id, title, _)) in popularTopics.indexed)
        if ((_popular[id]?.items.length ?? 0) >= _minRail) (i, FeedRail(id, title, _popular[id]!.items.take(24).toList())),
    ]..sort((a, b) {
        final byTaste = (taste.sources[b.$2.id] ?? 0).compareTo(taste.sources[a.$2.id] ?? 0);
        return byTaste != 0 ? byTaste : a.$1.compareTo(b.$1);
      });

    final related = [
      for (final (v, weight) in _seeds(taste))
        if (_related[v.videoId] case final c?) (c.items, weight),
    ];
    final uploads = [
      for (final c in taste.topChannels(3))
        if (_uploads[c] case final cached?) cached.items,
    ];
    var forYou = const <VideoItem>[];
    if (related.isNotEmpty || uploads.isNotEmpty) {
      forYou = taste.recommend(
        related: related,
        uploads: uploads,
        popular: [for (final (_, r) in popular) ...r.items.take(8)],
      );
      if (forYou.length >= _minRail) rails.add(FeedRail('for-you', 'Recommended for you', forYou));
    }

    // The latest liked video's own list: shows what the suggestions follow.
    final latest = _latestLiked(taste);
    if (latest != null) {
      final seen = taste.seen;
      final top = forYou.take(6).map((v) => v.videoId).toSet();
      final because = [
        for (final v in _related[latest.videoId]?.items ?? const <VideoItem>[])
          if (!seen.contains(v.videoId) && !top.contains(v.videoId)) v,
      ];
      if (because.length >= _minRail) rails.add(FeedRail('because', 'Because you watched ${latest.title}', because));
    }

    rails.addAll([for (final (_, r) in popular) r]);
    final heroFrom = forYou.length >= _minRail ? forYou : popular.firstOrNull?.$2.items ?? const <VideoItem>[];
    _state.value = FeedState(
      hero: [for (final v in heroFrom) if (!v.isLive) v].take(5).toList(),
      rails: rails,
      error: failed && popular.isEmpty && forYou.isEmpty ? 'Could not reach YouTube.' : null,
    );
  }

  Future<void> _loadCache() async {
    final file = cacheFile;
    if (file == null) return;
    try {
      if (!await file.exists()) return;
      final j = jsonDecode(await file.readAsString());
      if (j is! Map || j['v'] != 1) return;
      void read(String name, Map<String, _Cached> into) {
        for (final MapEntry(:key, :value) in ((j[name] as Map?) ?? const {}).entries) {
          into[key as String] = _Cached.fromJson((value as Map).cast());
        }
      }

      read('popular', _popular);
      read('related', _related);
      read('uploads', _uploads);
    } catch (_) {
      // Corrupt: fetch again.
      _popular.clear();
      _related.clear();
      _uploads.clear();
    }
  }

  Future<void> _saveCache() async {
    final file = cacheFile;
    if (file == null) return;
    Map<String, Object?> dump(Map<String, _Cached> m) => {for (final e in m.entries) e.key: e.value.toJson()};
    try {
      await writeFileAtomic(
        file,
        jsonEncode({'v': 1, 'popular': dump(_popular), 'related': dump(_related), 'uploads': dump(_uploads)}),
      );
    } on FileSystemException catch (e) {
      debugPrint('youtube feed: cache not saved: $e');
    }
  }

  void dispose() {
    _taste.removeListener(_tasteChanged);
    _state.dispose();
  }
}
