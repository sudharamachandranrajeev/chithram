/// One file inside a torrent.
class TorrentFile {
  const TorrentFile({
    required this.index,
    required this.path,
    required this.length,
    required this.streamable,
  });

  factory TorrentFile.fromJson(Map<String, dynamic> j) => TorrentFile(
        index: j['index'] as int,
        path: j['path'] as String,
        length: j['length'] as int,
        streamable: j['streamable'] as bool,
      );

  final int index;
  final String path;
  final int length;

  /// False for non-media extensions: the server answers 415 for those.
  final bool streamable;
}

/// Result of adding a magnet / .torrent.
class TorrentInfo {
  const TorrentInfo({required this.id, required this.name, required this.files});

  factory TorrentInfo.fromJson(Map<String, dynamic> j) => TorrentInfo(
        id: j['id'] as int,
        name: j['name'] as String?,
        files: [
          for (final f in (j['files'] as List<dynamic>))
            TorrentFile.fromJson((f as Map).cast<String, dynamic>()),
        ],
      );

  final int id;
  final String? name;
  final List<TorrentFile> files;
}

/// Snapshot of a torrent; [raw] is the full JSON from librqbit.
class TorrentStats {
  const TorrentStats(this.raw);

  final Map<String, dynamic> raw;

  String get state => raw['state'] as String? ?? 'unknown';
  int get progressBytes => (raw['progress_bytes'] as num?)?.toInt() ?? 0;
  int get totalBytes => (raw['total_bytes'] as num?)?.toInt() ?? 0;
  bool get finished => raw['finished'] as bool? ?? false;
  String? get error => raw['error'] as String?;

  /// Download speed as librqbit reports it (MiB/s), or null when not live.
  double? get downloadMibPerSec {
    final live = raw['live'];
    if (live is! Map) return null;
    final s = live['download_speed'];
    if (s is Map && s['mbps'] is num) return (s['mbps'] as num).toDouble();
    return null;
  }
}

class TorrentException implements Exception {
  TorrentException(this.message);
  final String message;
  @override
  String toString() => 'TorrentException: $message';
}
