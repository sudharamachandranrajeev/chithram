import 'package:iptv/iptv.dart';

/// A community catalogue offered as an opt-in suggestion. Offering one never
/// touches the network: it is fetched only after the user selects it and
/// confirms (see `add_playlist.dart`).
enum CatalogueSuggestion {
  iptvOrg(
    sourceId: 'cat-iptv-org',
    name: 'iptv-org',
    blurb: 'A large community channel database. The iptv-org blocklist is always applied. '
        'You can narrow it by country and language.',
    endpoint: CatalogueEndpoints.iptvOrgApi,
    filterable: true,
  ),
  freeTv(
    sourceId: 'cat-free-tv',
    name: 'Free-TV',
    blurb: 'A small community playlist of free-to-air channels.',
    endpoint: CatalogueEndpoints.freeTvPlaylist,
    filterable: false,
  );

  const CatalogueSuggestion({
    required this.sourceId,
    required this.name,
    required this.blurb,
    required this.endpoint,
    required this.filterable,
  });

  final String sourceId;
  final String name;
  final String blurb;
  final String endpoint;

  /// Offers country and language filters before adding.
  final bool filterable;

  /// The only host contacted once the user confirms.
  String get host => Uri.parse(endpoint).host;

  Source toSource({String? country, String? language}) => switch (this) {
        iptvOrg => Source.iptvOrg(
            id: sourceId,
            country: _clean(country),
            language: _clean(language),
          ),
        freeTv => Source.freeTv(sourceId),
      };

  static String? _clean(String? v) {
    final t = v?.trim();
    return t == null || t.isEmpty ? null : t;
  }
}
