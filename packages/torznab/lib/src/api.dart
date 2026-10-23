/// What an endpoint advertises (`t=caps`).
class TorznabCaps {
  const TorznabCaps({this.search = false, this.tvSearch = false, this.movieSearch = false, this.categories = const []});
  final bool search, tvSearch, movieSearch;
  final List<int> categories;
}

class TorznabItem {
  const TorznabItem({
    required this.title,
    this.infoHash,
    this.magnet,
    this.torrentUrl,
    this.detailsUrl,
    this.sizeBytes,
    this.seeders,
    this.leechers,
    this.published,
  });
  final String title;
  final String? infoHash, magnet, torrentUrl, detailsUrl;
  final int? sizeBytes, seeders, leechers;
  final DateTime? published;
}

/// One configured endpoint. The API key is passed per call and never stored here.
abstract interface class TorznabClient {
  Future<TorznabCaps> caps(Uri baseUrl, {String? apiKey});
  Future<List<TorznabItem>> search(
    Uri baseUrl, {
    String? apiKey,
    required String query,
    int? season,
    int? episode,
    String? imdbId,
    int? tvdbId,
  });
}

/// Stub: reports no capabilities and finds nothing. Replaced in R1.
class NullTorznabClient implements TorznabClient {
  const NullTorznabClient();

  @override
  Future<TorznabCaps> caps(Uri baseUrl, {String? apiKey}) async => const TorznabCaps();

  @override
  Future<List<TorznabItem>> search(
    Uri baseUrl, {
    String? apiKey,
    required String query,
    int? season,
    int? episode,
    String? imdbId,
    int? tvdbId,
  }) async => const [];
}
