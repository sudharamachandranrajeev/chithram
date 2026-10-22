import 'package:tmdb/tmdb.dart';

/// A value with a flag: true when it came from the cache and a fresh fetch is
/// on the way (stale-while-revalidate).
class Cached<T> {
  const Cached(this.value, {this.stale = false});
  final T value;
  final bool stale;
}

/// Details, seasons, genres, discover and search (WP-A implements over TMDB;
/// WP-C consumes). Models are in package:tmdb.
abstract interface class CatalogRepository {
  /// Cache first, then fresh.
  Stream<Cached<TitleDetails>> details(MediaKind k, int id);
  Stream<Cached<SeasonDetails>> season(int showId, int season);
  Future<List<Genre>> genres(MediaKind k);
  Future<List<HomeTile>> discoverGenre(MediaKind k, int genreId, {int page = 1});
  Future<List<HomeTile>> search(String q);
  void prefetchDetails(MediaKind k, int id);
}
