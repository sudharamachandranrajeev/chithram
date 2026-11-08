import 'dart:convert';

import '../../core/prefs.dart';
import 'channel_filter.dart';

/// Favourite and recently watched channels, and the Live TV view choices,
/// kept in [Prefs] as small JSON strings of channel keys.
class LiveTvLibrary {
  LiveTvLibrary(this.prefs);

  final Prefs prefs;

  static const favouritesKey = 'livetv.favourites';
  static const recentKey = 'livetv.recent';
  static const sortKey = 'livetv.sort';
  static const gridKey = 'livetv.grid';

  /// The recent list keeps this many channels, newest first.
  static const maxRecent = 50;

  // Decoding is cached per raw string: pages ask on every build.
  String? _favRaw;
  List<String> _fav = const [];
  String? _recentRaw;
  List<String> _recent = const [];

  static List<String> _decode(String? raw) {
    if (raw == null) return const [];
    try {
      final j = jsonDecode(raw);
      return j is List
          ? [
              for (final e in j)
                if (e is String) e,
            ]
          : const [];
    } on FormatException {
      return const [];
    }
  }

  /// Favourite channel keys, the latest added first.
  List<String> get favourites {
    final raw = prefs.getString(favouritesKey);
    if (raw != _favRaw) {
      _favRaw = raw;
      _fav = _decode(raw);
    }
    return _fav;
  }

  Set<String> get favouriteSet => favourites.toSet();

  bool isFavourite(String key) => favourites.contains(key);

  Future<void> toggleFavourite(String key) {
    final list = [...favourites];
    if (!list.remove(key)) list.insert(0, key);
    return prefs.set(favouritesKey, jsonEncode(list));
  }

  /// Recently played channel keys, newest first.
  List<String> get recent {
    final raw = prefs.getString(recentKey);
    if (raw != _recentRaw) {
      _recentRaw = raw;
      _recent = _decode(raw);
    }
    return _recent;
  }

  Future<void> markWatched(String key) {
    final list = [
      key,
      for (final k in recent)
        if (k != key) k,
    ];
    return prefs.set(recentKey, jsonEncode(list.take(maxRecent).toList()));
  }

  ChannelSort get sort => ChannelSort.byName(prefs.getString(sortKey));
  Future<void> setSort(ChannelSort s) => prefs.set(sortKey, s.name);

  /// Desktop shows a grid of cards unless the user picked the list.
  bool get grid => prefs.getBool(gridKey, fallback: true);
  Future<void> setGrid(bool v) => prefs.set(gridKey, v);
}
