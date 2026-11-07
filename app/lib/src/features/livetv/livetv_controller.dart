import 'package:flutter/widgets.dart';

import '../../core/prefs.dart';
import '../../core/services.dart';
import '../../player/play_request.dart';
import 'channel_filter.dart';
import 'iptv_service.dart';
import 'livetv_library.dart';

/// The state every Live TV form shares: the snapshot, its index, the filter
/// and its result, favourites and recents. Pages own one and listen to it.
class LiveTvController extends ChangeNotifier {
  LiveTvController({required this.service, required Prefs prefs})
    : library = LiveTvLibrary(prefs) {
    _filter = ChannelFilter(sort: library.sort);
    service.addListener(reload);
    prefs.addListener(_onPrefs);
    _favKeys = library.favourites;
    _recentKeys = library.recent;
    _grid = library.grid;
  }

  final IptvService service;
  final LiveTvLibrary library;

  LiveTvSnapshot? _snap;
  ChannelIndex _index = ChannelIndex.empty;
  late ChannelFilter _filter;
  FilterResult _result = FilterResult.empty;
  List<String> _favKeys = const [];
  List<String> _recentKeys = const [];
  var _grid = true;
  var _generation = 0;
  var _disposed = false;

  /// Null until the first load finishes.
  LiveTvSnapshot? get snapshot => _snap;
  ChannelIndex get index => _index;
  ChannelFilter get filter => _filter;
  FilterResult get result => _result;
  List<IndexedChannel> get visible => _result.visible;
  Set<String> get refreshing => service.refreshing;

  bool isFavourite(String key) => _favKeys.contains(key);

  /// Favourite channels that still exist, latest added first.
  List<IndexedChannel> get favourites => [
    for (final k in _favKeys) ?_index.byKey[k],
  ];

  /// Recently watched channels that still exist, newest first.
  List<IndexedChannel> get recent => [
    for (final k in _recentKeys) ?_index.byKey[k],
  ];

  Future<void> reload() async {
    final gen = ++_generation;
    final snap = await service.snapshot();
    if (_disposed || gen != _generation) return;
    _snap = snap;
    _index = ChannelIndex.build(snap.sources, snap.channels);
    // A removed source cannot stay selected.
    final src = _filter.selected(ChannelFacet.source);
    if (src.any((id) => !snap.sources.any((s) => s.id == id))) {
      _filter = _filter.withFacet(ChannelFacet.source, {
        for (final id in src)
          if (snap.sources.any((s) => s.id == id)) id,
      });
    }
    _apply();
  }

  void setFilter(ChannelFilter f) {
    if (f.sort != _filter.sort) library.setSort(f.sort);
    _filter = f;
    _apply();
  }

  void setQuery(String q) => setFilter(_filter.copyWith(query: q));
  void toggleFacet(ChannelFacet f, String key) =>
      setFilter(_filter.toggle(f, key));
  void clearFacet(ChannelFacet f) => setFilter(_filter.withFacet(f, const {}));
  void clearFilters() => setFilter(_filter.cleared());

  Future<void> toggleFavourite(String key) => library.toggleFavourite(key);

  void _onPrefs() {
    final fav = library.favourites;
    final recent = library.recent;
    final grid = library.grid;
    // Prefs also carries the rest of the app's settings; only ours rebuild.
    if (identical(fav, _favKeys) &&
        identical(recent, _recentKeys) &&
        grid == _grid) {
      return;
    }
    _grid = grid;
    final refilter =
        (!identical(fav, _favKeys) && _filter.favouritesOnly) ||
        (!identical(recent, _recentKeys) && _filter.sort == ChannelSort.recent);
    _favKeys = fav;
    _recentKeys = recent;
    if (refilter) {
      _apply();
    } else {
      notifyListeners();
    }
  }

  void _apply() {
    _result = applyChannelFilter(
      _index,
      _filter,
      favourites: _favKeys.toSet(),
      recent: _recentKeys,
    );
    notifyListeners();
  }

  /// Plays [picked]; Up and Down then step through the playable channels of
  /// [list] in its order (the visible list, or a row).
  void play(
    BuildContext context,
    IndexedChannel picked,
    List<IndexedChannel> list,
  ) {
    final zap = zapList(list, picked);
    openPlayer(
      context,
      service.playRequest(
        zap,
        zap.indexOf(picked.channel),
        onWatch: (c) => library.markWatched(c.key),
      ),
    );
  }

  Future<void> refreshAll() async {
    final snap = _snap;
    if (snap == null) return;
    await Future.wait([for (final s in snap.sources) service.refresh(s.id)]);
  }

  @override
  void dispose() {
    _disposed = true;
    service.removeListener(reload);
    library.prefs.removeListener(_onPrefs);
    super.dispose();
  }
}

/// Owns a [LiveTvController] for the nearest [AppServices]; the state
/// rebuilds on every change.
mixin LiveTvControllerHost<T extends StatefulWidget> on State<T> {
  LiveTvController? _controller;
  LiveTvController get controller => _controller!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppServices.of(context);
    final s = services.iptv;
    final p = services.prefs;
    final old = _controller;
    if (old == null ||
        !identical(old.service, s) ||
        !identical(old.library.prefs, p)) {
      old?.removeListener(_changed);
      old?.dispose();
      _controller = LiveTvController(service: s, prefs: p)
        ..addListener(_changed);
      _controller!.reload();
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_changed);
    _controller?.dispose();
    super.dispose();
  }
}
