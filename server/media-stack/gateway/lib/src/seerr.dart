import 'config.dart';
import 'net.dart';
import 'roles.dart';

/// Seerr access with the admin API key. Writes need the CSRF cookie + header pair
/// (Seerr runs with csrfProtection on). Requests are made AS a user via X-API-User.
class Seerr {
  Seerr(this.cfg);
  final Config cfg;
  final Map<String, String> _titleCache = {};

  Uri _u(String path, [Map<String, String>? q]) =>
      Uri.parse(cfg.seerrUrl).replace(path: '/api/v1$path', queryParameters: q);

  Future<Map<String, String>> _headers(bool write, int? asUser) async {
    final h = {'x-api-key': cfg.secret('seerr_api_key')};
    if (asUser != null) h['x-api-user'] = '$asUser';
    if (write) {
      final r = await jsonRequest('GET', _u('/status'));
      String? csrf, xsrf;
      for (final c in r.cookies) {
        if (c.name == '_csrf') csrf = c.value;
        if (c.name == 'XSRF-TOKEN') xsrf = c.value;
      }
      if (csrf != null && xsrf != null) {
        h['x-xsrf-token'] = xsrf;
        h['cookie'] = '_csrf=$csrf; XSRF-TOKEN=$xsrf';
      }
    }
    return h;
  }

  Future<HttpResult> call(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    int? asUser,
  }) async {
    final write = method != 'GET';
    return jsonRequest(
      method,
      _u(path, query),
      headers: await _headers(write, asUser),
      body: body,
    );
  }

  /// Seerr user id for a Jellyfin user: import when missing, then sync role permissions.
  /// The owner (id 1) keeps its own permissions.
  Future<int> ensureUser(String jellyfinId, Role role) async {
    var u = await _findByJellyfin(jellyfinId);
    if (u == null) {
      final r = await call(
        'POST',
        '/user/import-from-jellyfin',
        body: {
          'jellyfinUserIds': [jellyfinId],
        },
      );
      if (!r.ok) throw UpstreamException('seerr import');
      u = await _findByJellyfin(jellyfinId);
      if (u == null) throw UpstreamException('seerr import missing');
    }
    final id = u['id'] as int;
    if (id != 1 && u['permissions'] != role.seerrPermissions) {
      final r = await call(
        'POST',
        '/user/$id/settings/permissions',
        body: {'permissions': role.seerrPermissions},
      );
      if (!r.ok) throw UpstreamException('seerr permissions');
    }
    return id;
  }

  /// Takes all Seerr permissions from the Seerr user of a Jellyfin user (they could otherwise
  /// still sign in to Seerr directly). Returns false when nothing could be done because the
  /// Seerr owner (id 1) cannot be demoted; true when done or there is no Seerr user.
  Future<bool> revoke(String jellyfinId) async {
    final u = await _findByJellyfin(jellyfinId);
    if (u == null) return true;
    final id = u['id'] as int;
    if (id == 1) return false;
    if (u['permissions'] == 0) return true;
    final r = await call(
      'POST',
      '/user/$id/settings/permissions',
      body: {'permissions': 0},
    );
    if (!r.ok) throw UpstreamException('seerr permissions');
    return true;
  }

  Future<Map<dynamic, dynamic>?> _findByJellyfin(String jellyfinId) async {
    var skip = 0;
    while (true) {
      final r = await call(
        'GET',
        '/user',
        query: {'take': '100', 'skip': '$skip'},
      );
      if (!r.ok || r.body is! Map) throw UpstreamException('seerr users');
      final results = (r.body as Map)['results'];
      if (results is! List || results.isEmpty) return null;
      for (final u in results) {
        if (u is Map && _norm(u['jellyfinUserId']) == jellyfinId) return u;
      }
      if (results.length < 100) return null;
      skip += 100;
    }
  }

  static String? _norm(Object? v) =>
      v is String ? v.replaceAll('-', '').toLowerCase() : null;

  Future<List<Map<String, Object?>>> search(String q) async {
    // Seerr wants %20 (not +) for spaces, so build the query string by hand.
    final r = await jsonRequest(
      'GET',
      Uri.parse(cfg.seerrUrl).replace(
        path: '/api/v1/search',
        query: 'query=${Uri.encodeComponent(q)}&page=1',
      ),
      headers: await _headers(false, null),
    );
    if (!r.ok || r.body is! Map) throw UpstreamException('seerr search');
    final res = (r.body as Map)['results'];
    if (res is! List) return [];
    return [
      for (final e in res)
        if (e is Map && (e['mediaType'] == 'movie' || e['mediaType'] == 'tv'))
          e.cast<String, Object?>(),
    ];
  }

  /// Requests recorded on the media row for a TMDB id (null when none/unknown).
  Future<List<dynamic>?> requestsOf(String type, int tmdbId) async {
    final r = await call('GET', '/$type/$tmdbId');
    if (!r.ok || r.body is! Map) return null;
    final mi = (r.body as Map)['mediaInfo'];
    final reqs = mi is Map ? mi['requests'] : null;
    return reqs is List ? reqs : null;
  }

  /// Title for a TMDB id (cached).
  Future<String?> title(String type, int tmdbId) async {
    final key = '$type:$tmdbId';
    final hit = _titleCache[key];
    if (hit != null) return hit;
    final r = await call('GET', '/$type/$tmdbId');
    if (!r.ok || r.body is! Map) return null;
    final m = r.body as Map;
    final t = (m['title'] ?? m['name']);
    if (t is! String) return null;
    if (_titleCache.length > 500) _titleCache.clear();
    return _titleCache[key] = t;
  }
}
