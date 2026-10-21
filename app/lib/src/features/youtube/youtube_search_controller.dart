import 'package:flutter/foundation.dart';
import 'package:innertube/innertube.dart';

import 'youtube_service.dart';

/// Results of one YouTube search, paged by continuation. A newer search
/// replaces an older one that is still running.
class YouTubeSearchController extends ChangeNotifier {
  YouTubeSearchController(this.service);

  final YouTubeService service;

  String query = '';
  List<VideoItem> items = const [];
  String? continuation;
  bool loading = false;
  String? error;

  /// True once a search has finished (so "no results" can be told apart from
  /// "nothing searched yet").
  bool searched = false;

  int _generation = 0;

  Future<void> search(String q) async {
    final text = q.trim();
    final generation = ++_generation;
    query = text;
    items = const [];
    continuation = null;
    error = null;
    searched = false;
    if (text.isEmpty) {
      loading = false;
      notifyListeners();
      return;
    }
    loading = true;
    notifyListeners();
    try {
      final page = await service.search(text);
      if (generation != _generation) return;
      items = page.items;
      continuation = page.continuation;
    } catch (e) {
      if (generation != _generation) return;
      error = _describe(e);
    }
    loading = false;
    searched = true;
    notifyListeners();
  }

  /// The next page, if there is one and none is loading.
  Future<void> loadMore() async {
    final token = continuation;
    if (token == null || loading) return;
    final generation = _generation;
    loading = true;
    notifyListeners();
    try {
      final page = await service.search(query, continuation: token);
      if (generation != _generation) return;
      final known = {for (final v in items) v.videoId};
      items = [...items, ...page.items.where((v) => known.add(v.videoId))];
      continuation = page.continuation;
    } catch (e) {
      if (generation != _generation) return;
      // Keep what is on screen; stop paging.
      continuation = null;
    }
    loading = false;
    notifyListeners();
  }

  static String _describe(Object e) =>
      e is InnertubeException ? e.message : 'Search failed: ${e.runtimeType}';
}
