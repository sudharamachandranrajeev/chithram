import 'package:tmdb/tmdb.dart';

import '../core/prefs.dart';
import '../home/home_source.dart';
import 'tmdb_catalog.dart';

class TmdbHomeSource implements HomeSource {
  TmdbHomeSource({required this.catalog, required this.prefs});
  final TmdbCatalog catalog;
  final Prefs prefs;
  @override
  bool get configured => prefs.getBool('tmdb.configured');

  static const _definitions = [
    ('featured', 'Featured', 'trending/all/week', 12, true),
    ('trending', 'Trending today', 'trending/movie/day', 3, false),
    ('movie-popular', 'Popular films', 'movie/popular', 24, false),
    ('now-playing', 'Now playing', 'movie/now_playing', 12, false),
    ('upcoming', 'Upcoming', 'movie/upcoming', 12, false),
    ('movie-top', 'Top rated films', 'movie/top_rated', 24, false),
    ('tv-popular', 'Popular series', 'tv/popular', 24, false),
    ('on-air', 'On the air', 'tv/on_the_air', 12, false),
    ('airing-today', 'Airing today', 'tv/airing_today', 12, false),
    ('tv-top', 'Top rated series', 'tv/top_rated', 24, false),
    ('documentaries', 'Documentaries', 'discover/movie', 24, false),
    ('animation', 'Animation', 'discover/movie', 24, false),
  ];
  @override
  List<RailSpec> rails(HomeConfig c) => [
    for (final d in _definitions)
      RailSpec(
        id: d.$1,
        title: d.$2,
        softTtl: Duration(hours: d.$4),
        hero: d.$5,
      ),
    for (final language
        in c.originalLanguages
            .where((l) => RegExp(r'^[a-z]{2}$').hasMatch(l))
            .toSet()
            .take(4))
      RailSpec(
        id: 'language-$language',
        title: 'Popular in $language',
        softTtl: const Duration(days: 1),
      ),
  ];

  @override
  Future<RailFetch> fetch(RailSpec r, HomeConfig c, {String? etag}) async {
    if (!configured) return const RailFailed('Add a metadata key in Settings.');
    try {
      final languageRail = r.id.startsWith('language-');
      final definition = _definitions.where((d) => d.$1 == r.id).firstOrNull;
      if (!languageRail && definition == null) {
        return const RailFailed('Unknown metadata rail.');
      }
      final path = languageRail ? 'discover/movie' : definition!.$3;
      final kind = path.contains('/all/')
          ? null
          : path.startsWith('tv/')
          ? MediaKind.tv
          : MediaKind.movie;
      final response = await catalog.request(
        path,
        parser: 'tiles',
        kind: kind,
        list: true,
        etag: etag,
        query: {
          'language': c.language,
          'region': c.region,
          if (r.id == 'documentaries') 'with_genres': '99',
          if (r.id == 'animation') 'with_genres': '16',
          if (languageRail) 'with_original_language': r.id.substring(9),
        },
      );
      return response.status == 304
          ? const RailNotModified()
          : RailData(
              r.hero
                  ? (response.value as List<HomeTile>).take(5).toList()
                  : response.value as List<HomeTile>,
              etag: response.headers['etag'],
            );
    } on TmdbException catch (e) {
      return RailFailed(
        e,
        retryAfter: e.retryAfter,
        authRejected: e.status == 401 || e.status == 403,
      );
    } catch (_) {
      return const RailFailed('Could not load metadata.');
    }
  }
}
