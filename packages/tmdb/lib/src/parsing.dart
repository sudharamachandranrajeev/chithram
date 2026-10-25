import 'models.dart';
import 'client.dart';

typedef Json = Map<String, dynamic>;
List<Json> objects(dynamic value) =>
    value is List ? value.whereType<Json>().toList() : const [];
String? imagePath(dynamic value) =>
    value is String && RegExp(r'^/[A-Za-z0-9_.-]+$').hasMatch(value)
    ? value
    : null;
String text(dynamic value, [String fallback = '']) =>
    value is String ? value : fallback;
int? integer(dynamic value) => value is num ? value.toInt() : null;
double? decimal(dynamic value) => value is num ? value.toDouble() : null;

List<HomeTile> parseTiles(Json json, [MediaKind? kind]) => [
  for (final j in objects(json['results']))
    if (j['adult'] != true &&
        j['id'] is int &&
        (kind != null || j['media_type'] == 'movie' || j['media_type'] == 'tv'))
      parseTile(
        j,
        kind ?? (j['media_type'] == 'tv' ? MediaKind.tv : MediaKind.movie),
      ),
];
HomeTile parseTile(Json j, MediaKind k) => HomeTile(
  id: 'tmdb:${k.name}:${j['id']}',
  kind: k,
  tmdbId: j['id'] as int,
  title: text(j[k == MediaKind.movie ? 'title' : 'name']),
  subtitle: text(j[k == MediaKind.movie ? 'release_date' : 'first_air_date']),
  poster: imagePath(j['poster_path']),
  backdrop: imagePath(j['backdrop_path']),
  rating: decimal(j['vote_average']),
);
List<Genre> parseGenres(Json j) => [
  for (final g in objects(j['genres']))
    if (g['id'] is int) Genre(id: g['id'], name: text(g['name'])),
];
TitleDetails parseDetails(Json j, MediaKind k) {
  if (j['adult'] == true) {
    throw const TmdbException('This title is unavailable.');
  }
  final date = text(
    j[k == MediaKind.movie ? 'release_date' : 'first_air_date'],
  );
  final credits =
      j[k == MediaKind.tv ? 'aggregate_credits' : 'credits'] as Json? ?? {};
  final external = j['external_ids'] as Json? ?? {};
  return TitleDetails(
    kind: k,
    id: j['id'] as int,
    title: text(j[k == MediaKind.movie ? 'title' : 'name']),
    originalTitle:
        j[k == MediaKind.movie ? 'original_title' : 'original_name'] as String?,
    year: date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null,
    runtimeMin:
        integer(j['runtime']) ??
        (j['episode_run_time'] is List &&
                (j['episode_run_time'] as List).isNotEmpty
            ? integer(j['episode_run_time'][0])
            : null),
    overview: j['overview'] as String?,
    genres: parseGenres(j),
    rating: decimal(j['vote_average']),
    poster: imagePath(j['poster_path']),
    backdrop: imagePath(j['backdrop_path']),
    cast: [
      for (final c in objects(credits['cast']).take(30))
        CastMember(
          name: text(c['name']),
          character:
              c['character'] as String? ??
              (objects(c['roles']).isNotEmpty
                  ? text(objects(c['roles']).first['character'])
                  : null),
          profile: imagePath(c['profile_path']),
        ),
    ],
    seasons: [
      for (final s in objects(j['seasons']))
        SeasonSummary(
          number: integer(s['season_number']) ?? 0,
          name: text(s['name']),
          episodeCount: integer(s['episode_count']) ?? 0,
          poster: imagePath(s['poster_path']),
        ),
    ],
    trailers: [
      for (final v in objects((j['videos'] as Json? ?? {})['results']))
        if (v['site'] == 'YouTube' &&
            v['type'] == 'Trailer' &&
            RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(text(v['key'])))
          Trailer(
            youtubeKey: v['key'],
            name: text(v['name']),
            official: v['official'] == true,
            lang: v['iso_639_1'] as String?,
          ),
    ],
    imdbId: external['imdb_id'] as String? ?? j['imdb_id'] as String?,
    tvdbId: integer(external['tvdb_id']),
    similar: parseTiles(j['recommendations'] as Json? ?? {}, k),
  );
}

SeasonDetails parseSeason(Json j) => SeasonDetails(
  number: integer(j['season_number']) ?? 0,
  episodes: [
    for (final e in objects(j['episodes']))
      Episode(
        number: integer(e['episode_number']) ?? 0,
        title: text(e['name']),
        overview: e['overview'] as String?,
        still: imagePath(e['still_path']),
        airDate: DateTime.tryParse(text(e['air_date'])),
        runtimeMin: integer(e['runtime']),
      ),
  ],
);
