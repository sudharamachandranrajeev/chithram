import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where the app keeps its files.
class AppPaths {
  const AppPaths({required this.support, required this.cache});

  /// Resolves the platform directories (Android, Windows, Linux).
  static Future<AppPaths> resolve() async {
    final support = await getApplicationSupportDirectory();
    final cache = await getApplicationCacheDirectory();
    return AppPaths(support: support, cache: cache);
  }

  /// Directories under [root], not created until something writes there.
  /// For tests.
  factory AppPaths.under(String root) =>
      AppPaths(support: Directory('$root/support'), cache: Directory('$root/cache'));

  /// JSON stores, prefs, resume positions, the LocalSend certificate.
  final Directory support;

  /// Torrent cache and other data that may be deleted at any time.
  final Directory cache;

  File supportFile(String name) => File('${support.path}/$name');
  Directory cacheDir(String name) => Directory('${cache.path}/$name');
}

/// Writes [contents] to [file] through a temporary file and a rename, so a
/// crash never leaves half a file behind.
Future<void> writeFileAtomic(File file, String contents) async {
  await file.parent.create(recursive: true);
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString(contents, flush: true);
  await tmp.rename(file.path);
}
