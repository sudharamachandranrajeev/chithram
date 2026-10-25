import 'dart:io';

import 'package:tmdb/tmdb.dart';

Future<void> main() async {
  final key = Platform.environment['TMDB_TEST_KEY'];
  if (key == null || key.isEmpty) {
    stdout.writeln('api.themoviedb.org: skipped (no test key)');
    return;
  }
  final client = TmdbClient(key: key);
  try {
    final list = await client.get('trending/movie/week', list: true);
    final tiles = parseTiles(list.body!, MediaKind.movie);
    if (tiles.isEmpty) throw const TmdbException('Empty trending response.');
    final detail = await client.get(
      'movie/${tiles.first.tmdbId}',
      query: {
        'append_to_response': 'credits,videos,recommendations,external_ids',
      },
    );
    parseDetails(detail.body!, MediaKind.movie);
    stdout.writeln('api.themoviedb.org: catalog live check passed');
  } catch (_) {
    stderr.writeln('api.themoviedb.org: catalog live check failed');
    exitCode = 1;
  } finally {
    client.close();
  }
}
