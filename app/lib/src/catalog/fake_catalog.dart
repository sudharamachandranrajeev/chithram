import 'package:tmdb/tmdb.dart';

import '../home/fake_home.dart';
import 'catalog_repository.dart';

/// A [CatalogRepository] that answers from memory with synthetic titles.
/// `details` emits a stale copy first, then the fresh one, like the real SWR.
class FakeCatalog implements CatalogRepository {
  final prefetched = <String>[];

  static TitleDetails titleFor(MediaKind k, int id) => TitleDetails(
        kind: k,
        id: id,
        title: k == MediaKind.movie ? 'Fixture Film $id' : 'Fixture Show $id',
        year: 2020,
        runtimeMin: 100,
        overview: 'A synthetic title for tests.',
        genres: const [Genre(id: 1, name: 'Fixture')],
        rating: 7.5,
        poster: '/fixture_poster_$id.jpg',
        backdrop: '/fixture_backdrop_$id.jpg',
        cast: const [CastMember(name: 'Fixture Actor', character: 'Lead')],
        seasons: k == MediaKind.tv
            ? const [SeasonSummary(number: 1, name: 'Season 1', episodeCount: 3)]
            : const [],
        trailers: const [Trailer(youtubeKey: 'fixture00000', name: 'Trailer', official: true, lang: 'en')],
        similar: fixtureTiles(5, firstId: id + 100, kind: k),
      );

  @override
  Stream<Cached<TitleDetails>> details(MediaKind k, int id) async* {
    yield Cached(titleFor(k, id), stale: true);
    yield Cached(titleFor(k, id));
  }

  @override
  Stream<Cached<SeasonDetails>> season(int showId, int season) async* {
    yield Cached(SeasonDetails(
      number: season,
      episodes: [
        for (var e = 1; e <= 3; e++) Episode(number: e, title: 'Fixture Episode $e', runtimeMin: 45),
      ],
    ));
  }

  @override
  Future<List<Genre>> genres(MediaKind k) async => const [Genre(id: 1, name: 'Fixture')];

  @override
  Future<List<HomeTile>> discoverGenre(MediaKind k, int genreId, {int page = 1}) async =>
      fixtureTiles(10, kind: k, firstId: 1 + (page - 1) * 10);

  @override
  Future<List<HomeTile>> search(String q) async =>
      q.toLowerCase().contains('fixture') ? fixtureTiles(3) : const [];

  @override
  void prefetchDetails(MediaKind k, int id) => prefetched.add('$k:$id');
}
