import 'snapshot.dart';

/// User choices that shape the rails.
class HomeConfig {
  const HomeConfig({this.language = 'en-US', this.region = 'US', this.originalLanguages = const []});
  final String language, region;

  /// Up to 4 "Popular in (language)" rails (ISO 639-1 codes).
  final List<String> originalLanguages;
}

class RailSpec {
  const RailSpec({required this.id, required this.title, required this.softTtl, this.hero = false});
  final String id, title;
  final Duration softTtl;

  /// Feeds the Featured hero instead of a rail.
  final bool hero;
}

sealed class RailFetch {
  const RailFetch();
}

final class RailData extends RailFetch {
  const RailData(this.tiles, {this.etag});
  final List<HomeTile> tiles;
  final String? etag;
}

final class RailNotModified extends RailFetch {
  const RailNotModified();
}

final class RailFailed extends RailFetch {
  const RailFailed(this.error, {this.retryAfter, this.authRejected = false});
  final Duration? retryAfter;
  final bool authRejected;
  final Object error;
}

/// Where rails come from (WP-A implements over TMDB; WP-B consumes).
abstract interface class HomeSource {
  /// A prefs flag: the user entered a key. Reads no secret.
  bool get configured;
  List<RailSpec> rails(HomeConfig c);
  Future<RailFetch> fetch(RailSpec r, HomeConfig c, {String? etag});
}

/// No key, no rails. The R0 stand-in.
class UnconfiguredHomeSource implements HomeSource {
  const UnconfiguredHomeSource();

  @override
  bool get configured => false;

  @override
  List<RailSpec> rails(HomeConfig c) => const [];

  @override
  Future<RailFetch> fetch(RailSpec r, HomeConfig c, {String? etag}) async =>
      const RailFailed('no TMDB key');
}
