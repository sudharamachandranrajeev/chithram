import 'package:tmdb/tmdb.dart';

import 'catalog_repository.dart';

/// R0 stub (WP-A replaces it): empty. Details never arrive, so a details page
/// built on it shows its loading state.
class TmdbCatalog implements CatalogRepository {
  const TmdbCatalog();

  @override
  Stream<Cached<TitleDetails>> details(MediaKind k, int id) => const Stream.empty();

  @override
  Stream<Cached<SeasonDetails>> season(int showId, int season) => const Stream.empty();

  @override
  Future<List<Genre>> genres(MediaKind k) async => const [];

  @override
  Future<List<HomeTile>> discoverGenre(MediaKind k, int genreId, {int page = 1}) async => const [];

  @override
  Future<List<HomeTile>> search(String q) async => const [];

  @override
  void prefetchDetails(MediaKind k, int id) {}
}
