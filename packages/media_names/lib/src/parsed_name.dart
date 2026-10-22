class ParsedName {
  const ParsedName({
    required this.title,
    this.year,
    this.season,
    this.episode,
    this.episodeEnd,
    this.resolution,
    this.source,
    this.codec,
    this.hdr,
    this.group,
    this.isPack = false,
  });

  /// The name with the release tags removed.
  final String title;
  final int? year;
  final int? season, episode, episodeEnd;

  /// Vertical lines: 480, 720, 1080, 2160.
  final int? resolution;
  final String? source, codec, hdr, group;

  /// A whole season or series (no single episode).
  final bool isPack;
}

/// Stub: returns the input as the title, nothing else. Replaced in R1.
ParsedName parse(String name) => ParsedName(title: name.trim());
