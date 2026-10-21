import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Stable item ids, prefixed by their source. Favourites, history, playlists
/// and the queue key on these, so the formats never change.
abstract final class ItemId {
  /// `yt:<videoId>`
  static String youtube(String id) => 'yt:$id';

  /// `iptv:<StoredChannel.key>`
  static String iptv(String channelKey) => 'iptv:$channelKey';

  /// `bt:<btih-hex-lowercase>/<fileIndex>`
  static String torrentFile(String btihHex, int file) => 'bt:${btihHex.toLowerCase()}/$file';

  /// `url:<first 16 hex of sha256(normalised url)>`
  static String url(String url) =>
      'url:${sha256.convert(utf8.encode(normaliseUrl(url))).toString().substring(0, 16)}';

  /// `src:<sourceId>`
  static String source(String sourceId) => 'src:$sourceId';

  /// Lower-cased scheme and host, no fragment, no default port, `/` for an
  /// empty path. The query is kept.
  static String normaliseUrl(String url) {
    final trimmed = url.trim();
    final u = Uri.tryParse(trimmed);
    if (u == null || !u.hasScheme) return trimmed;
    final defaultPort = u.scheme == 'http' ? 80 : (u.scheme == 'https' ? 443 : -1);
    return Uri(
      scheme: u.scheme.toLowerCase(),
      userInfo: u.userInfo,
      host: u.host.toLowerCase(),
      port: u.hasPort && u.port != defaultPort ? u.port : null,
      path: u.path.isEmpty ? '/' : u.path,
      query: u.hasQuery ? u.query : null,
    ).toString();
  }
}
