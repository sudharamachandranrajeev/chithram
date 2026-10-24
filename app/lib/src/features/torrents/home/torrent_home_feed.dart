import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/paths.dart';
import '../../../core/redact.dart';
import '../torrent_logic.dart';
import 'popular_item.dart';
import 'popular_source.dart';

/// One row of torrents on Torrent Home.
class TorrentRail {
  const TorrentRail(this.id, this.title, this.items);
  final String id, title;
  final List<PopularItem> items;
}

class TorrentHomeState {
  const TorrentHomeState({
    this.rails = const [],
    this.loading = true,
    this.hasSources,
    this.error,
    this.sourceErrors = const {},
  });

  final List<TorrentRail> rails;
  final bool loading;

  /// Null until the sources are known (the first refresh).
  final bool? hasSources;

  /// Set only when nothing could be fetched and nothing was cached.
  final String? error;

  /// Source label to the reason its last fetch failed.
  final Map<String, String> sourceErrors;
}

/// The age windows of the rails.
enum PopularWindow {
  today('today', 'Popular today', Duration(hours: 24), Duration(hours: 3)),
  week('week', 'Popular this week', Duration(days: 7), Duration(hours: 12)),
  month('month', 'Popular this month', Duration(days: 30), Duration(hours: 24)),

  /// Items whose source gave no date.
  undated('undated', 'Most seeded', Duration.zero, Duration(hours: 24));

  const PopularWindow(this.id, this.title, this.maxAge, this.ttl);
  final String id, title;
  final Duration maxAge, ttl;
}

final _adultTitle = RegExp(r'\b(xxx|porn\w*|hentai|erotic\w*|nsfw|18\+)\b', caseSensitive: false);

/// Adult by category (Torznab 6000-6999) or by an obvious word in the name.
bool isAdultItem(PopularItem i) => i.categories.any((c) => c >= 6000 && c < 7000) || _adultTitle.hasMatch(i.title);

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

/// The infohash, else normalised title plus size.
String dedupeKey(PopularItem i) {
  final hash = i.infoHash ?? (i.magnet == null ? null : btihFromMagnet(i.magnet!));
  return hash != null ? 'h:${hash.toLowerCase()}' : 't:${_norm(i.title)}|${i.sizeBytes ?? ''}';
}

/// Drops adult items, merges duplicates (the most seeders win; the first
/// item's source stays the one that fetches the file; every source is listed).
List<PopularItem> mergeItems(Iterable<PopularItem> items) {
  final byKey = <String, PopularItem>{};
  for (final raw in items) {
    if (isAdultItem(raw)) continue;
    final key = dedupeKey(raw);
    final have = byKey[key];
    if (have == null) {
      byKey[key] = raw.copyWith(
        infoHash: raw.infoHash ?? (raw.magnet == null ? null : btihFromMagnet(raw.magnet!)),
        sources: raw.sources.isEmpty ? [raw.sourceLabel] : raw.sources,
      );
      continue;
    }
    final moreSeeded = (raw.seeders ?? 0) > (have.seeders ?? 0);
    final dates = [have.published, raw.published].whereType<DateTime>();
    byKey[key] = have.copyWith(
      seeders: moreSeeded ? raw.seeders : have.seeders,
      leechers: moreSeeded ? raw.leechers : have.leechers,
      sizeBytes: have.sizeBytes ?? raw.sizeBytes,
      infoHash: have.infoHash ?? raw.infoHash,
      magnet: have.magnet ?? raw.magnet,
      torrentUrl: have.torrentUrl ?? raw.torrentUrl,
      detailsUrl: have.detailsUrl ?? raw.detailsUrl,
      // The earliest date is the upload.
      published: dates.isEmpty ? null : dates.reduce((a, b) => a.isBefore(b) ? a : b),
      sources: {
        ...have.sources,
        ...(raw.sources.isEmpty ? [raw.sourceLabel] : raw.sources),
      }.toList(),
    );
  }
  return byKey.values.toList();
}

/// Most seeders first; ties go to the newer, then the title.
int bySeeders(PopularItem a, PopularItem b) {
  final s = (b.seeders ?? 0).compareTo(a.seeders ?? 0);
  if (s != 0) return s;
  final da = a.published, db = b.published;
  if (da != null && db != null && da != db) return db.compareTo(da);
  return a.title.compareTo(b.title);
}

/// The items of each window: merged, ranked by seeders, at most [perKind] of
/// each kind. Items with no seeders are not popular and are left out.
Map<PopularWindow, List<PopularItem>> buildWindows(
  Iterable<PopularItem> pool,
  DateTime now, {
  int perKind = TorrentHomeFeed.perKind,
}) {
  final items = [
    for (final i in mergeItems(pool))
      if ((i.seeders ?? 0) > 0) i,
  ]..sort(bySeeders);
  List<PopularItem> cap(Iterable<PopularItem> xs) {
    final out = <PopularItem>[];
    for (final kind in PopularKind.values) {
      out.addAll(xs.where((i) => i.kind == kind).take(perKind));
    }
    return out..sort(bySeeders);
  }

  Duration? age(PopularItem i) {
    final p = i.published;
    if (p == null) return null;
    final d = now.difference(p);
    return d.isNegative ? Duration.zero : d;
  }

  return {
    for (final w in PopularWindow.values)
      w: cap(
        items.where((i) {
          final a = age(i);
          return w == PopularWindow.undated ? a == null : a != null && a <= w.maxAge;
        }),
      ),
  };
}

class _Window {
  const _Window(this.at, this.items);
  final DateTime at;
  final List<PopularItem> items;
}

/// Torrent Home's rails: what is popular on the user's own sources (Torznab
/// feeds and search plugins), ranked by seeders and split by upload date.
///
/// Lists are kept in `torrent_home.json`; Home shows them at once and only
/// stale windows (today 3 h, week 12 h, month and undated 24 h) are fetched
/// again. Nothing runs on a timer: [open] when the tab opens, then [refresh]
/// from pull-to-refresh and Retry. Changing the set of sources makes
/// everything stale.
class TorrentHomeFeed {
  TorrentHomeFeed({
    required this.sources,
    this.cacheFile,
    DateTime Function()? clock,
    this.taskTimeout = const Duration(seconds: 25),
  }) : _clock = clock ?? DateTime.now;

  final PopularSources sources;

  /// Null: nothing is read or written.
  final File? cacheFile;
  final DateTime Function() _clock;
  final Duration taskTimeout;

  static const perKind = 30;

  final _state = ValueNotifier(const TorrentHomeState());
  ValueListenable<TorrentHomeState> get state => _state;

  final _windows = <PopularWindow, _Window>{};
  var _signature = '';
  final _byId = <String, PopularSource>{};

  Future<void>? _opening;
  Future<void>? _refreshing;
  bool _again = false, _againForce = false;

  /// The tab is on screen: shows the cache, then fetches what is stale. Only
  /// the first call does anything.
  Future<void> open() => _opening ??= () async {
    await _loadCache();
    _rebuild(loading: true);
    await refresh();
  }();

  /// Fetches stale windows (all of them with [force]). A call while one runs
  /// makes it go round once more.
  Future<void> refresh({bool force = false}) {
    final running = _refreshing;
    if (running != null) {
      _again = true;
      _againForce = _againForce || force;
      return running;
    }
    return _refreshing = () async {
      try {
        do {
          final f = force || _againForce;
          _again = false;
          _againForce = false;
          force = false;
          await _fetchStale(f);
        } while (_again);
      } finally {
        _refreshing = null;
      }
    }();
  }

  Future<void> _fetchStale(bool force) async {
    final groups = await sources.groups();
    final all = [for (final g in groups) ...g.sources];
    _byId
      ..clear()
      ..addEntries([for (final s in all) MapEntry(s.id, s)]);
    final signature = ([for (final s in all) s.id]..sort()).join(',');
    if (all.isEmpty) {
      _windows.clear();
      _signature = signature;
      _state.value = const TorrentHomeState(loading: false, hasSources: false);
      await _saveCache();
      return;
    }
    final now = _clock();
    final changed = signature != _signature;
    final stale = [
      for (final w in PopularWindow.values)
        if (force || changed || _windows[w] == null || now.difference(_windows[w]!.at) > w.ttl) w,
    ];
    if (stale.isEmpty) {
      _rebuild(loading: false, hasSources: true);
      return;
    }
    _rebuild(loading: true, hasSources: true);

    final pool = <PopularItem>[];
    final errors = <String, String>{};
    var ok = 0, tried = 0;
    Future<void> task(PopularSource s, PopularKind kind) async {
      tried++;
      try {
        pool.addAll(await s.fetch(kind).timeout(taskTimeout));
        ok++;
      } on TimeoutException {
        errors[s.label] = 'Did not answer in ${taskTimeout.inSeconds} s';
      } catch (e) {
        debugPrint('torrent home: ${s.id}: $e');
        errors[s.label] = redactText(e.toString());
      }
    }

    await Future.wait([
      for (final g in groups)
        _pool([
          for (final s in g.sources)
            for (final k in PopularKind.values) () => task(s, k),
        ], g.concurrency),
    ]);

    if (ok == 0) {
      // Keep what is cached, whatever its age.
      _rebuild(loading: false, hasSources: true, sourceErrors: errors, failed: tried > 0);
      return;
    }
    final built = buildWindows(pool, now);
    for (final w in stale) {
      _windows[w] = _Window(now, built[w]!);
    }
    _signature = signature;
    _rebuild(loading: false, hasSources: true, sourceErrors: errors);
    await _saveCache();
  }

  static Future<void> _pool(List<Future<void> Function()> jobs, int concurrency) async {
    var next = 0;
    Future<void> worker() async {
      while (next < jobs.length) {
        await jobs[next++]();
      }
    }

    await Future.wait([for (var i = 0; i < math.max(1, concurrency); i++) worker()]);
  }

  void _rebuild({
    required bool loading,
    bool? hasSources,
    Map<String, String> sourceErrors = const {},
    bool failed = false,
  }) {
    final rails = <TorrentRail>[];
    for (final w in PopularWindow.values) {
      final items = _windows[w]?.items ?? const <PopularItem>[];
      if (w == PopularWindow.undated) {
        if (items.isNotEmpty) rails.add(TorrentRail(w.id, w.title, items));
        continue;
      }
      for (final (kind, name) in [(PopularKind.film, 'Films'), (PopularKind.tv, 'TV')]) {
        final part = [
          for (final i in items)
            if (i.kind == kind) i,
        ];
        if (part.isNotEmpty) rails.add(TorrentRail('${w.id}-${kind.name}', '${w.title} · $name', part));
      }
    }
    _state.value = TorrentHomeState(
      rails: rails,
      loading: loading,
      hasSources: hasSources ?? _state.value.hasSources,
      error: failed && rails.isEmpty ? 'Could not reach any source.' : null,
      sourceErrors: sourceErrors,
    );
  }

  /// The .torrent for an item with no magnet and no infohash.
  Future<Uint8List> fetchTorrent(PopularItem item) async {
    var s = _byId[item.sourceId];
    if (s == null) {
      for (final g in await sources.groups()) {
        for (final x in g.sources) {
          if (x.id == item.sourceId) s = x;
        }
      }
    }
    if (s == null) throw StateError('That source is no longer available');
    return s.fetchTorrent(item);
  }

  Future<void> _loadCache() async {
    final file = cacheFile;
    if (file == null) return;
    try {
      if (!await file.exists()) return;
      final j = jsonDecode(await file.readAsString());
      if (j is! Map || j['v'] != 1) return;
      _signature = j['sources'] as String;
      for (final MapEntry(:key, :value) in (j['windows'] as Map).entries) {
        final w = PopularWindow.values.where((w) => w.id == key).firstOrNull;
        if (w == null) continue;
        final m = (value as Map).cast<String, Object?>();
        _windows[w] = _Window(DateTime.parse(m['at'] as String), [
          for (final i in m['items'] as List) PopularItem.fromJson((i as Map).cast()),
        ]);
      }
    } catch (_) {
      // Corrupt: fetch again.
      _windows.clear();
      _signature = '';
    }
  }

  Future<void> _saveCache() async {
    final file = cacheFile;
    if (file == null) return;
    try {
      await writeFileAtomic(
        file,
        jsonEncode({
          'v': 1,
          'sources': _signature,
          'windows': {
            for (final e in _windows.entries)
              e.key.id: {
                'at': e.value.at.toUtc().toIso8601String(),
                'items': [for (final i in e.value.items) i.toJson()],
              },
          },
        }),
      );
    } on FileSystemException catch (e) {
      debugPrint('torrent home: cache not saved: $e');
    }
  }

  void dispose() => _state.dispose();
}
