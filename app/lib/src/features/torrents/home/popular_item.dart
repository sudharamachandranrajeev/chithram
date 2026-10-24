/// Films or TV: how a source was asked and how a rail is split.
enum PopularKind { film, tv }

/// One torrent on Torrent Home, from a Torznab feed or a search plugin.
class PopularItem {
  const PopularItem({
    required this.title,
    required this.kind,
    required this.sourceId,
    required this.sourceLabel,
    this.sizeBytes,
    this.seeders,
    this.leechers,
    this.infoHash,
    this.magnet,
    this.torrentUrl,
    this.detailsUrl,
    this.published,
    this.categories = const [],
    this.sources = const [],
  });

  final String title;
  final PopularKind kind;

  /// The source that first reported it (the one that can fetch its file).
  final String sourceId, sourceLabel;
  final int? sizeBytes, seeders, leechers;

  /// 40 lower-case hex characters.
  final String? infoHash;
  final String? magnet, torrentUrl, detailsUrl;
  final DateTime? published;

  /// Torznab categories; used to drop adult ones.
  final List<int> categories;

  /// Labels of every source that reported it.
  final List<String> sources;

  PopularItem copyWith({
    PopularKind? kind,
    int? seeders,
    int? leechers,
    int? sizeBytes,
    String? infoHash,
    String? magnet,
    String? torrentUrl,
    String? detailsUrl,
    DateTime? published,
    List<String>? sources,
  }) => PopularItem(
    title: title,
    kind: kind ?? this.kind,
    sourceId: sourceId,
    sourceLabel: sourceLabel,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    seeders: seeders ?? this.seeders,
    leechers: leechers ?? this.leechers,
    infoHash: infoHash ?? this.infoHash,
    magnet: magnet ?? this.magnet,
    torrentUrl: torrentUrl ?? this.torrentUrl,
    detailsUrl: detailsUrl ?? this.detailsUrl,
    published: published ?? this.published,
    categories: categories,
    sources: sources ?? this.sources,
  );

  Map<String, Object?> toJson() => {
    'title': title,
    'kind': kind.name,
    'sourceId': sourceId,
    'sourceLabel': sourceLabel,
    'size': sizeBytes,
    'seeders': seeders,
    'leechers': leechers,
    'hash': infoHash,
    'magnet': magnet,
    'torrent': torrentUrl,
    'details': detailsUrl,
    'published': published?.toUtc().toIso8601String(),
    'cats': categories,
    'sources': sources,
  };

  factory PopularItem.fromJson(Map<String, Object?> j) => PopularItem(
    title: j['title'] as String,
    kind: PopularKind.values.byName(j['kind'] as String),
    sourceId: j['sourceId'] as String,
    sourceLabel: j['sourceLabel'] as String,
    sizeBytes: j['size'] as int?,
    seeders: j['seeders'] as int?,
    leechers: j['leechers'] as int?,
    infoHash: j['hash'] as String?,
    magnet: j['magnet'] as String?,
    torrentUrl: j['torrent'] as String?,
    detailsUrl: j['details'] as String?,
    published: j['published'] == null ? null : DateTime.parse(j['published'] as String),
    categories: [for (final c in (j['cats'] as List? ?? const [])) c as int],
    sources: [for (final s in (j['sources'] as List? ?? const [])) s as String],
  );
}
