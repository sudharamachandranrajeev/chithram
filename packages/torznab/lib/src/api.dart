import 'fetch.dart';
import 'parse.dart';

/// What an endpoint advertises (`t=caps`).
class TorznabCaps {
  const TorznabCaps({this.search = false, this.tvSearch = false, this.movieSearch = false, this.categories = const []});
  final bool search, tvSearch, movieSearch;
  final List<int> categories;

  Map<String, Object?> toJson() => {'search': search, 'tv': tvSearch, 'movie': movieSearch, 'categories': categories};

  factory TorznabCaps.fromJson(Map<String, Object?> j) => TorznabCaps(
    search: j['search'] == true,
    tvSearch: j['tv'] == true,
    movieSearch: j['movie'] == true,
    categories: [for (final c in (j['categories'] as List? ?? const [])) c as int],
  );
}

class TorznabItem {
  const TorznabItem({
    required this.title,
    this.guid,
    this.infoHash,
    this.magnet,
    this.torrentUrl,
    this.detailsUrl,
    this.sizeBytes,
    this.seeders,
    this.leechers,
    this.published,
    this.categories = const [],
  });
  final String title;
  final String? guid;

  /// 40 lower-case hex characters when the indexer sent one.
  final String? infoHash;
  final String? magnet, torrentUrl, detailsUrl;
  final int? sizeBytes, seeders, leechers;
  final DateTime? published;

  /// Numeric Torznab categories (2000 movies, 5000 TV, ...).
  final List<int> categories;
}

/// One configured endpoint. The API key is passed per call and never stored here.
abstract interface class TorznabClient {
  Future<TorznabCaps> caps(Uri baseUrl, {String? apiKey});

  /// Searches [baseUrl]. With no [query] the indexer returns its latest
  /// releases. Categories 6000-6999 are never requested and never returned.
  Future<List<TorznabItem>> search(
    Uri baseUrl, {
    String? apiKey,
    String? query,
    List<int> cats = const [],
    int limit = 100,
    int? season,
    int? episode,
    String? imdbId,
    int? tvdbId,
  });
}

/// Stub: reports no capabilities and finds nothing.
class NullTorznabClient implements TorznabClient {
  const NullTorznabClient();

  @override
  Future<TorznabCaps> caps(Uri baseUrl, {String? apiKey}) async => const TorznabCaps();

  @override
  Future<List<TorznabItem>> search(
    Uri baseUrl, {
    String? apiKey,
    String? query,
    List<int> cats = const [],
    int limit = 100,
    int? season,
    int? episode,
    String? imdbId,
    int? tvdbId,
  }) async => const [];
}

/// The real client over a [TorznabFetch] (HTTP is injected so tests and the
/// app's SOCKS5 path share it).
class HttpTorznabClient implements TorznabClient {
  HttpTorznabClient({TorznabFetch? fetch}) : _fetch = fetch ?? fetchDirect;

  final TorznabFetch _fetch;

  /// Items kept from one response.
  static const maxItems = 500;

  /// `base` plus the Torznab parameters. Existing query parameters of [base]
  /// are kept.
  static Uri buildUrl(Uri base, Map<String, String?> params) {
    final q = {...base.queryParameters};
    for (final e in params.entries) {
      final v = e.value;
      if (v != null && v.isNotEmpty) q[e.key] = v;
    }
    return base.replace(queryParameters: q);
  }

  Future<String> _get(Uri url) async {
    final r = await _fetch(url);
    if (r.status == 429) throw TorznabException('The indexer is rate limiting (429)', retryAfter: r.retryAfter);
    if (r.status == 401 || r.status == 403) throw TorznabException('The indexer refused the API key (${r.status})');
    if (r.status < 200 || r.status >= 300) throw TorznabException('The indexer answered ${r.status}');
    return decodeBody(r.body);
  }

  @override
  Future<TorznabCaps> caps(Uri baseUrl, {String? apiKey}) async =>
      parseCaps(await _get(buildUrl(baseUrl, {'t': 'caps', 'apikey': apiKey})));

  @override
  Future<List<TorznabItem>> search(
    Uri baseUrl, {
    String? apiKey,
    String? query,
    List<int> cats = const [],
    int limit = 100,
    int? season,
    int? episode,
    String? imdbId,
    int? tvdbId,
  }) async {
    final mode = season != null || episode != null
        ? 'tvsearch'
        : (imdbId != null && (query == null || query.isEmpty))
        ? 'movie'
        : 'search';
    final allowed = [
      for (final c in cats)
        if (!isAdultCategory(c)) c,
    ];
    final xml = await _get(
      buildUrl(baseUrl, {
        't': mode,
        'q': query?.trim(),
        'cat': allowed.join(','),
        'limit': '${limit.clamp(1, maxItems)}',
        'season': season?.toString(),
        'ep': episode?.toString(),
        'imdbid': imdbId?.replaceFirst(RegExp('^tt'), ''),
        'tvdbid': tvdbId?.toString(),
        'apikey': apiKey,
      }),
    );
    return parseItems(xml).take(maxItems).toList();
  }
}
