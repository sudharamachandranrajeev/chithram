import 'dart:convert';
import 'dart:io';

import 'package:tmdb/tmdb.dart';

import '../core/paths.dart';

// The tile models live in package:tmdb (its details model holds tiles too).
export 'package:tmdb/tmdb.dart' show HomeTile, MediaKind;

Map<String, Object?> tileToJson(HomeTile t) => {
      'id': t.id,
      'k': t.kind.name,
      'tmdb': t.tmdbId,
      'title': t.title,
      if (t.subtitle != null) 'sub': t.subtitle,
      if (t.poster != null) 'poster': t.poster,
      if (t.backdrop != null) 'backdrop': t.backdrop,
      if (t.rating != null) 'rating': t.rating,
    };

HomeTile tileFromJson(Map<String, Object?> j) => HomeTile(
      id: j['id'] as String,
      kind: MediaKind.values.byName(j['k'] as String),
      tmdbId: j['tmdb'] as int,
      title: j['title'] as String,
      subtitle: j['sub'] as String?,
      poster: j['poster'] as String?,
      backdrop: j['backdrop'] as String?,
      rating: (j['rating'] as num?)?.toDouble(),
    );

class HomeRail {
  const HomeRail({
    required this.id,
    required this.title,
    required this.fetchedAt,
    this.etag,
    required this.tiles,
  });

  final String id, title;
  final DateTime fetchedAt;
  final String? etag;
  final List<HomeTile> tiles;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'fetchedAt': fetchedAt.toUtc().toIso8601String(),
        if (etag != null) 'etag': etag,
        'tiles': [for (final t in tiles) tileToJson(t)],
      };

  static HomeRail fromJson(Map<String, Object?> j) => HomeRail(
        id: j['id'] as String,
        title: j['title'] as String,
        fetchedAt: DateTime.parse(j['fetchedAt'] as String),
        etag: j['etag'] as String?,
        tiles: [for (final t in j['tiles'] as List) tileFromJson((t as Map).cast())],
      );
}

/// What Home shows on the first frame: the hero and the rails as last
/// fetched. About 50 KB of JSON; read once at launch, before anything else.
class HomeSnapshot {
  const HomeSnapshot({
    required this.generatedAt,
    required this.language,
    required this.region,
    required this.hero,
    required this.rails,
  });

  static const version = 1;

  final DateTime generatedAt;
  final String language, region;
  final List<HomeTile> hero;
  final List<HomeRail> rails;

  Map<String, Object?> toJson() => {
        'v': version,
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'language': language,
        'region': region,
        'hero': [for (final t in hero) tileToJson(t)],
        'rails': [for (final r in rails) r.toJson()],
      };

  /// Null when the bytes are not a version-1 snapshot or are corrupt.
  static HomeSnapshot? tryParse(List<int> bytes) {
    try {
      final j = jsonDecode(utf8.decode(bytes));
      if (j is! Map || j['v'] != version) return null;
      return HomeSnapshot(
        generatedAt: DateTime.parse(j['generatedAt'] as String),
        language: j['language'] as String,
        region: j['region'] as String,
        hero: [for (final t in j['hero'] as List) tileFromJson((t as Map).cast())],
        rails: [for (final r in j['rails'] as List) HomeRail.fromJson((r as Map).cast())],
      );
    } catch (_) {
      return null;
    }
  }
}

/// `home_snapshot.json` under the support directory.
class SnapshotStore {
  SnapshotStore(this.file);
  final File file;

  Future<HomeSnapshot?> load() async {
    try {
      if (!await file.exists()) return null;
      return HomeSnapshot.tryParse(await file.readAsBytes());
    } on FileSystemException {
      return null;
    }
  }

  /// Through a temporary file and a rename: a crash never leaves half a file.
  Future<void> save(HomeSnapshot s) => writeFileAtomic(file, jsonEncode(s.toJson()));

  Future<void> delete() async {
    try {
      await file.delete();
    } on FileSystemException {
      // Already gone.
    }
  }
}
