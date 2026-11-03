import 'config.dart';
import 'net.dart';
import 'status_map.dart';

/// Read-only snapshot of Radarr/Sonarr queue + running search commands.
class ArrSnapshot {
  ArrSnapshot._(
    this._movieQueue,
    this._tvQueue,
    this._movieSearch,
    this._tvSearch,
  );

  final Map<int, String> _movieQueue; // tmdbId -> 'downloading'|'importing'
  final Map<int, String> _tvQueue;
  final Set<int> _movieSearch; // tmdbIds with an active search command
  final Set<int> _tvSearch;

  static final ArrSnapshot empty = ArrSnapshot._({}, {}, {}, {});

  ArrActivity? activity(String type, int tmdbId) {
    final q = type == 'movie' ? _movieQueue : _tvQueue;
    final s = type == 'movie' ? _movieSearch : _tvSearch;
    final st = q[tmdbId];
    return ArrActivity(
      downloading: st == 'downloading',
      importing: st == 'importing',
      searching: s.contains(tmdbId),
    );
  }

  static Future<ArrSnapshot> load(ArrClient radarr, ArrClient sonarr) async {
    final mq = <int, String>{}, tq = <int, String>{};
    final ms = <int>{}, ts = <int>{};
    try {
      for (final r in await radarr.queue()) {
        final m = r['movie'];
        if (m is Map && m['tmdbId'] is int) mq[m['tmdbId'] as int] = _qstate(r);
      }
      ms.addAll(await radarr.searchingTmdbIds('movie'));
    } on UpstreamException {
      // unreachable arr: status falls back to "approved"
    }
    try {
      for (final r in await sonarr.queue()) {
        final m = r['series'];
        if (m is Map && m['tmdbId'] is int) tq[m['tmdbId'] as int] = _qstate(r);
      }
      ts.addAll(await sonarr.searchingTmdbIds('series'));
    } on UpstreamException {
      // as above
    }
    return ArrSnapshot._(mq, tq, ms, ts);
  }

  static String _qstate(Map<dynamic, dynamic> r) {
    final s = r['trackedDownloadState'];
    return (s == 'importPending' || s == 'importing' || s == 'imported')
        ? 'importing'
        : 'downloading';
  }
}

class ArrClient {
  ArrClient(this.cfg, this.baseUrl, this.keyName, this.kind);
  final Config cfg;
  final String baseUrl;
  final String keyName;
  final String kind; // 'movie' | 'series'

  Uri _u(String path, [Map<String, String>? q]) =>
      Uri.parse(baseUrl).replace(path: '/api/v3$path', queryParameters: q);
  Map<String, String> get _h => {'x-api-key': cfg.secret(keyName)};

  Future<List<Map<dynamic, dynamic>>> queue() async {
    final r = await jsonRequest(
      'GET',
      _u('/queue', {
        'page': '1',
        'pageSize': '200',
        if (kind == 'movie')
          'includeMovie': 'true'
        else
          'includeSeries': 'true',
      }),
      headers: _h,
    );
    if (!r.ok || r.body is! Map) throw UpstreamException('arr queue');
    final rec = (r.body as Map)['records'];
    return rec is List
        ? [
            for (final e in rec)
              if (e is Map) e,
          ]
        : [];
  }

  /// TMDB ids of titles with a queued/started search command.
  Future<Set<int>> searchingTmdbIds(String idKind) async {
    final r = await jsonRequest('GET', _u('/command'), headers: _h);
    if (!r.ok || r.body is! List) throw UpstreamException('arr command');
    final ids = <int>{};
    for (final c in r.body as List) {
      if (c is! Map) continue;
      final name = c['name'];
      final st = c['status'];
      if (st != 'queued' && st != 'started') continue;
      final body = c['body'];
      if (body is! Map) continue;
      if (kind == 'movie' &&
          name == 'MoviesSearch' &&
          body['movieIds'] is List) {
        for (final i in body['movieIds'] as List) {
          if (i is int) ids.addAll(await _tmdb('/movie/$i'));
        }
      } else if (kind == 'series' &&
          (name == 'SeriesSearch' || name == 'SeasonSearch') &&
          body['seriesId'] is int) {
        ids.addAll(await _tmdb('/series/${body['seriesId']}'));
      }
    }
    return ids;
  }

  Future<Set<int>> _tmdb(String path) async {
    final r = await jsonRequest('GET', _u(path), headers: _h);
    if (r.ok && r.body is Map && (r.body as Map)['tmdbId'] is int) {
      return {(r.body as Map)['tmdbId'] as int};
    }
    return {};
  }
}
