/// TMDB models: fields only (parsing arrives with the client in R1 WP-A).
/// Image fields hold size-free TMDB paths (`/abc.jpg`).
library;

enum MediaKind { movie, tv }

class HomeTile {
  const HomeTile({
    required this.id,
    required this.kind,
    required this.tmdbId,
    required this.title,
    this.subtitle,
    this.poster,
    this.backdrop,
    this.rating,
  });

  /// `tmdb:movie:<id>` or `tmdb:tv:<id>`.
  final String id;
  final MediaKind kind;
  final int tmdbId;
  final String title;
  final String? subtitle, poster, backdrop;
  final double? rating;
}

class Genre {
  const Genre({required this.id, required this.name});
  final int id;
  final String name;
}

class CastMember {
  const CastMember({required this.name, this.character, this.profile});
  final String name;
  final String? character, profile;
}

class SeasonSummary {
  const SeasonSummary({
    required this.number,
    required this.name,
    required this.episodeCount,
    this.poster,
  });
  final int number;
  final String name;
  final int episodeCount;
  final String? poster;
}

class Trailer {
  const Trailer({
    required this.youtubeKey,
    required this.name,
    required this.official,
    this.lang,
  });

  /// TMDB videos with `site == "YouTube"` only.
  final String youtubeKey;
  final String name;
  final bool official;
  final String? lang;
}

class TitleDetails {
  const TitleDetails({
    required this.kind,
    required this.id,
    required this.title,
    this.originalTitle,
    this.year,
    this.runtimeMin,
    this.overview,
    this.genres = const [],
    this.rating,
    this.poster,
    this.backdrop,
    this.cast = const [],
    this.seasons = const [],
    this.trailers = const [],
    this.imdbId,
    this.tvdbId,
    this.similar = const [],
  });

  final MediaKind kind;
  final int id;
  final String title;
  final String? originalTitle;
  final int? year, runtimeMin;
  final String? overview;
  final List<Genre> genres;
  final double? rating;
  final String? poster, backdrop;
  final List<CastMember> cast;
  final List<SeasonSummary> seasons;
  final List<Trailer> trailers;
  final String? imdbId;
  final int? tvdbId;
  final List<HomeTile> similar;
}

class Episode {
  const Episode({
    required this.number,
    required this.title,
    this.overview,
    this.still,
    this.airDate,
    this.runtimeMin,
  });
  final int number;
  final String title;
  final String? overview, still;
  final DateTime? airDate;
  final int? runtimeMin;
}

class SeasonDetails {
  const SeasonDetails({required this.number, this.episodes = const []});
  final int number;
  final List<Episode> episodes;
}
