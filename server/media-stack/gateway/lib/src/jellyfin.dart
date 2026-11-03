import 'dart:io';

import 'config.dart';
import 'net.dart';
import 'validate.dart';

class JfUser {
  JfUser(this.id, this.name, this.disabled);
  final String id; // 32 lowercase hex
  final String name;
  final bool disabled;
}

/// Jellyfin access. The admin API key stays inside this process; every per-user call is
/// scoped by the paired user's Jellyfin userId (/Users/{id}/...).
class Jellyfin {
  Jellyfin(this.cfg);
  final Config cfg;

  Map<String, String> get _h => {
    'authorization': 'MediaBrowser Token="${cfg.secret('jellyfin_api_key')}"',
  };
  Uri _u(String path, [Map<String, String>? q]) =>
      Uri.parse(cfg.jellyfinUrl).replace(path: path, queryParameters: q);

  static JfUser? _user(Object? j) {
    if (j is! Map) return null;
    final id = normalizeItemId(j['Id'] as String?);
    final name = j['Name'];
    if (id == null || name is! String) return null;
    final pol = j['Policy'];
    final dis = pol is Map && pol['IsDisabled'] == true;
    return JfUser(id, name, dis);
  }

  Future<List<JfUser>> users() async {
    final r = await jsonRequest('GET', _u('/Users'), headers: _h);
    if (!r.ok || r.body is! List) throw UpstreamException('jellyfin users');
    return [for (final j in r.body as List) ?_user(j)];
  }

  Future<JfUser?> findByName(String name) async {
    final lower = name.toLowerCase();
    for (final u in await users()) {
      if (u.name.toLowerCase() == lower) return u;
    }
    return null;
  }

  /// null when the user does not exist.
  Future<JfUser?> user(String id) async {
    final r = await jsonRequest('GET', _u('/Users/$id'), headers: _h);
    if (r.status == 404 || r.status == 400) return null;
    if (!r.ok) throw UpstreamException('jellyfin user');
    return _user(r.body);
  }

  /// One page of the user's own library view. Returns the raw Jellyfin JSON map.
  Future<Map<String, Object?>> libraryPage(
    String userId,
    String itemType,
    int start,
    int limit,
  ) async {
    final r = await jsonRequest(
      'GET',
      _u('/Users/$userId/Items', {
        'IncludeItemTypes': itemType,
        'Recursive': 'true',
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'StartIndex': '$start',
        'Limit': '$limit',
        'Fields': 'ProductionYear',
        'EnableImageTypes': 'Primary',
        'EnableTotalRecordCount': 'true',
      }),
      headers: _h,
    );
    if (!r.ok || r.body is! Map) throw UpstreamException('jellyfin library');
    return (r.body as Map).cast<String, Object?>();
  }

  /// The item as that user sees it, or null when hidden/missing (library access check).
  Future<Map<String, Object?>?> itemFor(String userId, String itemId) async {
    final r = await jsonRequest(
      'GET',
      _u('/Users/$userId/Items/$itemId'),
      headers: _h,
    );
    if (r.status == 404 || r.status == 400 || r.status == 403) return null;
    if (!r.ok || r.body is! Map) throw UpstreamException('jellyfin item');
    return (r.body as Map).cast<String, Object?>();
  }

  Future<HttpClientResponse> image(String itemId, int width) => rawRequest(
    _u('/Items/$itemId/Images/Primary', {
      'maxWidth': '$width',
      'quality': '85',
    }),
    headers: _h,
  );

  /// Direct-play byte stream (no transcoding). [range] is forwarded as-is after validation.
  Future<HttpClientResponse> stream(String itemId, bool audio, String? range) =>
      rawRequest(
        _u('/${audio ? 'Audio' : 'Videos'}/$itemId/stream', {'static': 'true'}),
        headers: {..._h, 'range': ?range},
        timeout: const Duration(seconds: 30),
      );
}
