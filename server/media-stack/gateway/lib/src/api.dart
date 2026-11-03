import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'arr.dart';
import 'config.dart';
import 'jellyfin.dart';
import 'net.dart';
import 'pairing.dart';
import 'roles.dart';
import 'seerr.dart';
import 'state.dart';
import 'status_map.dart';
import 'util.dart';
import 'validate.dart';

const _jsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
  'cache-control': 'no-store',
  'x-content-type-options': 'nosniff',
};

Response jsonResp(int status, Object? body, {Map<String, String>? headers}) =>
    Response(
      status,
      body: jsonEncode(body),
      headers: {..._jsonHeaders, ...?headers},
    );

Response _err(int status, String code) => jsonResp(status, {'error': code});

/// Authenticated caller, attached to the request context by the auth wrapper.
class Caller {
  Caller(this.device, this.userId, this.user, this.role);
  final DeviceRec device;
  final String userId;
  final String user;
  final Role role;
}

typedef UserActive = Future<bool> Function(String userId);

class Gateway {
  Gateway(
    this.cfg,
    this.store, {
    Jellyfin? jellyfin,
    Seerr? seerr,
    ArrClient? radarr,
    ArrClient? sonarr,
    UserActive? userActive,
    int Function()? clock,
  }) : jf = jellyfin ?? Jellyfin(cfg),
       seerr = seerr ?? Seerr(cfg),
       radarr =
           radarr ?? ArrClient(cfg, cfg.radarrUrl, 'radarr_api_key', 'movie'),
       sonarr =
           sonarr ?? ArrClient(cfg, cfg.sonarrUrl, 'sonarr_api_key', 'series'),
       _clock = clock ?? nowMs {
    _userActive = userActive ?? _jellyfinActive;
  }

  final Config cfg;
  final StateStore store;
  final Jellyfin jf;
  final Seerr seerr;
  final ArrClient radarr;
  final ArrClient sonarr;
  final int Function() _clock;
  late final UserActive _userActive;
  final Throttle _pairThrottle = Throttle(20, 60 * 1000);
  final Map<String, int> _activeCache =
      {}; // userId -> expiry ms (positive results only)
  final Map<String, Throttle> _searchThrottle = {}; // deviceId -> limiter
  final Map<String, int> _visCache = {}; // userId|itemId -> expiry ms

  static const _cacheMs =
      10 * 1000; // upper bound for how stale an allow decision may be
  static const searchesPerMinute = 30;
  static const maxDetailLookups = 8;

  Future<bool> _jellyfinActive(String userId) async {
    final now = _clock();
    final exp = _activeCache[userId];
    if (exp != null && exp > now) return true;
    // Jellyfin errors propagate: _authed answers 503 (fail closed) instead of trusting the token.
    final u = await jf.user(userId);
    if (u == null || u.disabled) return false;
    if (_activeCache.length > 200) _activeCache.clear();
    _activeCache[userId] = now + _cacheMs;
    return true;
  }

  // ------------------------------------------------------------------ plumbing

  Handler get handler {
    final r = Router(notFoundHandler: (_) => _err(404, 'not_found'))
      ..get('/healthz', (Request _) => jsonResp(200, {'ok': true}))
      ..post('/v1/pair', _pair)
      ..get('/v1/me', _authed(null, _me))
      ..get('/v1/search', _authed(null, _search))
      ..post('/v1/requests', _authed(null, _createRequest))
      ..get('/v1/requests', _authed(null, _listRequests))
      ..post(
        '/v1/requests/<id>/approve',
        _authed(Role.admin, (c, req) => _decide(c, req, true)),
      )
      ..post(
        '/v1/requests/<id>/decline',
        _authed(Role.admin, (c, req) => _decide(c, req, false)),
      )
      ..get('/v1/downloads', _authed(Role.admin, _downloads))
      ..get('/v1/library', _authed(null, _library))
      ..get('/v1/images/<id>', _authed(null, _image))
      ..get('/v1/stream/<id>', _authed(null, _stream));
    return const Pipeline()
        .addMiddleware(_logging)
        .addMiddleware(_safety)
        .addHandler(r.call);
  }

  /// Logs method, route template, status, latency and a hash prefix of the device id. Nothing else.
  Middleware get _logging =>
      (inner) => (req) async {
        final sw = Stopwatch()..start();
        final holder = <String, String>{};
        var status = 500;
        try {
          final res = await inner(req.change(context: {'log': holder}));
          status = res.statusCode;
          return res;
        } finally {
          stdout.writeln(
            jsonEncode({
              't': DateTime.now().toUtc().toIso8601String(),
              'm': req.method,
              'p': routeTemplate(
                req.url.path.isEmpty ? '/' : '/${req.url.path}',
              ),
              's': status,
              'ms': sw.elapsedMilliseconds,
              'd': holder['d'] ?? '-',
            }),
          );
        }
      };

  Middleware get _safety =>
      (inner) => (req) async {
        try {
          return await inner(req);
        } on UpstreamException {
          return _err(502, 'upstream_unavailable');
        } on _BadRequest catch (e) {
          return _err(e.status, e.code);
        } catch (_) {
          return _err(500, 'internal');
        }
      };

  Handler _authed(Role? need, FutureOr<Response> Function(Caller, Request) h) =>
      (req) async {
        final hdr = req.headers['authorization'];
        if (hdr == null || !hdr.startsWith('Bearer '))
          return _err(401, 'unauthorized');
        final token = hdr.substring(7).trim();
        if (token.length < 20 || token.length > 128)
          return _err(401, 'unauthorized');
        final st = store.read();
        final dev = authenticate(st, token);
        if (dev == null) return _err(401, 'unauthorized');
        final u = st.users[dev.userId];
        if (u == null) return _err(401, 'unauthorized');
        final bool active;
        try {
          active = await _userActive(dev.userId);
        } on UpstreamException {
          return _err(503, 'upstream_unavailable');
        }
        if (!active) return _err(401, 'unauthorized');
        (req.context['log'] as Map<String, String>?)?['d'] = sha256Hex(
          dev.id,
        ).substring(0, 8);
        if (need != null && u.role != need) return _err(403, 'forbidden');
        return h(Caller(dev, dev.userId, u.name, u.role), req);
      };

  static Future<Map<String, Object?>> _readJson(Request req) async {
    final ct = req.headers['content-type'] ?? '';
    if (!ct.toLowerCase().startsWith('application/json'))
      throw _BadRequest(415, 'unsupported_media_type');
    final len = req.contentLength;
    if (len != null && len > maxBodyBytes) throw _BadRequest(413, 'too_large');
    final bytes = BytesBuilder(copy: false);
    await for (final c in req.read()) {
      bytes.add(c);
      if (bytes.length > maxBodyBytes) throw _BadRequest(413, 'too_large');
    }
    try {
      final j = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (j is Map<String, dynamic>) return j;
    } on FormatException {
      // fall through
    }
    throw _BadRequest(400, 'bad_json');
  }

  // ------------------------------------------------------------------ pairing

  Future<Response> _pair(Request req) async {
    final now = _clock();
    if (!_pairThrottle.allow(now)) {
      return jsonResp(
        429,
        {'error': 'too_many_attempts'},
        headers: {'retry-after': '60'},
      );
    }
    final body = await _readJson(req);
    final code = body['code'];
    final name = validDeviceName(body['deviceName']);
    if (!validCode(code) || name == null) return _err(400, 'bad_request');
    final out = store.update((s) {
      final r = redeemCode(s, code as String, name, now);
      if (r == null) return null;
      final u = s.users[r.device.userId];
      return u == null ? null : (r, u);
    });
    if (out == null) return _err(401, 'invalid_code');
    return jsonResp(200, {
      'token': out.$1.token,
      'deviceId': out.$1.device.id,
      'user': out.$2.name,
      'role': out.$2.role.name,
    });
  }

  // ------------------------------------------------------------------ handlers

  Response _me(Caller c, Request _) =>
      jsonResp(200, {'user': c.user, 'role': c.role.name});

  Future<Response> _search(Caller c, Request req) async {
    final q = validQuery(req.url.queryParameters['q']);
    if (q == null) return _err(400, 'bad_query');
    final th = _searchThrottle.putIfAbsent(
      c.device.id,
      () => Throttle(searchesPerMinute, 60 * 1000),
    );
    if (_searchThrottle.length > 200)
      _searchThrottle.removeWhere((_, t) => t.idle(_clock()));
    if (!th.allow(_clock())) {
      return jsonResp(
        429,
        {'error': 'too_many_searches'},
        headers: {'retry-after': '60'},
      );
    }
    final results = await seerr.search(q);
    var detailLookups = 0;
    ArrSnapshot? snap;
    final items = <Map<String, Object?>>[];
    for (final e in results.take(40)) {
      final tmdbId = e['id'];
      final type = e['mediaType'] as String;
      if (tmdbId is! int) continue;
      final mi = e['mediaInfo'];
      int? mediaStatus;
      int? reqStatus;
      if (mi is Map) {
        mediaStatus = mi['status'] as int?;
        var reqs = mi['requests'];
        if (reqs is! List &&
            (mediaStatus == 2 || mediaStatus == 3) &&
            detailLookups < maxDetailLookups) {
          detailLookups++;
          // search results omit the request list; the detail endpoint has it
          reqs = await seerr.requestsOf(type, tmdbId);
        }
        reqStatus = _latestRequestStatus(reqs);
      }
      ArrActivity? act;
      if (reqStatus == 2 || mediaStatus == 3) {
        snap ??= await ArrSnapshot.load(radarr, sonarr);
        act = snap.activity(type, tmdbId);
      }
      final date = (e['releaseDate'] ?? e['firstAirDate']) as String?;
      final overview = e['overview'];
      items.add({
        'tmdbId': tmdbId,
        'type': type,
        'title': e['title'] ?? e['name'],
        'year': (date != null && date.length >= 4)
            ? int.tryParse(date.substring(0, 4))
            : null,
        'overview': overview is String && overview.length > 500
            ? overview.substring(0, 500)
            : overview,
        'posterPath': e['posterPath'],
        'mediaStatus': mapStatus(
          requestStatus: reqStatus,
          mediaStatus: mediaStatus,
          arr: act,
        ),
      });
    }
    return jsonResp(200, {'results': items});
  }

  static int? _latestRequestStatus(Object? requests) {
    if (requests is! List || requests.isEmpty) return null;
    Map<dynamic, dynamic>? best;
    for (final r in requests) {
      if (r is Map &&
          r['id'] is int &&
          (best == null || (r['id'] as int) > (best['id'] as int)))
        best = r;
    }
    return best?['status'] as int?;
  }

  Future<Response> _createRequest(Caller c, Request req) async {
    if (!c.role.canRequest) return _err(403, 'forbidden');
    final body = await _readJson(req);
    final tmdbId = validTmdbId(body['tmdbId']);
    final type = validMediaType(body['type']);
    if (tmdbId == null || type == null) return _err(400, 'bad_request');
    final sid = await seerr.ensureUser(c.userId, c.role);
    final r = await seerr.call(
      'POST',
      '/request',
      asUser: sid,
      body: {
        'mediaType': type,
        'mediaId': tmdbId,
        if (type == 'tv') 'seasons': 'all',
      },
    );
    if (r.status == 409) return _err(409, 'already_requested');
    if (r.status == 403) return _err(403, 'forbidden');
    if (r.status == 404) return _err(404, 'not_found');
    if (!r.ok || r.body is! Map) throw UpstreamException('seerr request');
    return jsonResp(
      201,
      await _requestView(r.body as Map, null, withUser: false),
    );
  }

  Future<Response> _listRequests(Caller c, Request req) async {
    final skip = validCursor(req.url.queryParameters['cursor']);
    if (skip == null) return _err(400, 'bad_cursor');
    final sid = await seerr.ensureUser(c.userId, c.role);
    final r = await seerr.call(
      'GET',
      '/request',
      asUser: sid,
      query: {
        'take': '50',
        'skip': '$skip',
        'sort': 'added',
        'filter': 'all',
        if (!c.role.isAdmin) 'requestedBy': '$sid',
      },
    );
    if (!r.ok || r.body is! Map) throw UpstreamException('seerr requests');
    final results = (r.body as Map)['results'];
    final snap = await ArrSnapshot.load(radarr, sonarr);
    final out = <Map<String, Object?>>[];
    if (results is List) {
      for (final e in results) {
        if (e is! Map) continue;
        final rb = e['requestedBy'];
        if (!c.role.isAdmin && !(rb is Map && rb['id'] == sid)) continue;
        out.add(await _requestView(e, snap, withUser: c.role.isAdmin));
      }
    }
    return jsonResp(200, {
      'requests': out,
      'nextCursor': (results is List && results.length == 50)
          ? '${skip + 50}'
          : null,
    });
  }

  Future<Map<String, Object?>> _requestView(
    Map<dynamic, dynamic> e,
    ArrSnapshot? snap, {
    required bool withUser,
  }) async {
    final media = e['media'];
    final type =
        (e['type'] ?? (media is Map ? media['mediaType'] : null)) as String?;
    final tmdbId = media is Map ? media['tmdbId'] as int? : null;
    final mediaStatus = media is Map ? media['status'] as int? : null;
    ArrActivity? act;
    if (snap != null && type != null && tmdbId != null)
      act = snap.activity(type, tmdbId);
    final rb = e['requestedBy'];
    return {
      'id': e['id'],
      'tmdbId': tmdbId,
      'type': type,
      'title': (type != null && tmdbId != null)
          ? await seerr.title(type, tmdbId)
          : null,
      'status': mapStatus(
        requestStatus: e['status'] as int?,
        mediaStatus: mediaStatus,
        arr: act,
      ),
      'createdAt': e['createdAt'],
      if (withUser && rb is Map)
        'requestedBy': rb['jellyfinUsername'] ?? rb['displayName'],
    };
  }

  Future<Response> _decide(Caller c, Request req, bool approve) async {
    final id = validNumericId(req.params['id']);
    if (id == null) return _err(400, 'bad_id');
    final sid = await seerr.ensureUser(c.userId, c.role);
    final r = await seerr.call(
      'POST',
      '/request/$id/${approve ? 'approve' : 'decline'}',
      asUser: sid,
    );
    if (r.status == 404) return _err(404, 'not_found');
    if (!r.ok || r.body is! Map) throw UpstreamException('seerr decide');
    return jsonResp(
      200,
      await _requestView(r.body as Map, null, withUser: false),
    );
  }

  Future<Response> _downloads(Caller c, Request req) async {
    final items = <Map<String, Object?>>[];
    for (final (client, type, key) in [
      (radarr, 'movie', 'movie'),
      (sonarr, 'tv', 'series'),
    ]) {
      try {
        for (final r in await client.queue()) {
          final inner = r[key];
          final size = r['size'], left = r['sizeleft'];
          items.add({
            'id': r['id'],
            'type': type,
            'title': (inner is Map ? inner['title'] : null) ?? r['title'],
            'status': mapStatusOfQueue(r),
            'progress': (size is num && left is num && size > 0)
                ? ((size - left) / size)
                : null,
            'timeLeft': r['timeleft'],
          });
        }
      } on UpstreamException {
        // one arr down: list what we can
      }
    }
    return jsonResp(200, {'downloads': items});
  }

  static String mapStatusOfQueue(Map<dynamic, dynamic> r) {
    final s = r['trackedDownloadState'];
    return (s == 'importPending' || s == 'importing' || s == 'imported')
        ? 'importing'
        : 'downloading';
  }

  Future<Response> _library(Caller c, Request req) async {
    final itemType = libraryItemType(req.url.queryParameters['type']);
    final start = validCursor(req.url.queryParameters['cursor']);
    if (itemType == null || start == null) return _err(400, 'bad_request');
    final page = await jf.libraryPage(c.userId, itemType, start, 50);
    final raw = page['Items'];
    final total = page['TotalRecordCount'];
    final items = <Map<String, Object?>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        final id = normalizeItemId(e['Id'] as String?);
        if (id == null) continue;
        final tags = e['ImageTags'];
        items.add({
          'id': id,
          'title': e['Name'],
          'year': e['ProductionYear'],
          'type': e['Type'],
          'poster': (tags is Map && tags['Primary'] != null)
              ? '/v1/images/$id?w=342'
              : null,
        });
      }
    }
    final next = start + items.length;
    return jsonResp(200, {
      'items': items,
      'nextCursor': (total is int && items.isNotEmpty && next < total)
          ? '$next'
          : null,
    });
  }

  /// True when the user may see the item (checked through Jellyfin's per-user endpoint).
  Future<Map<String, Object?>?> _visible(Caller c, String itemId) async {
    final item = await jf.itemFor(c.userId, itemId);
    if (item != null) {
      final now = _clock();
      if (_visCache.length > 500) _visCache.clear();
      _visCache['${c.userId}|$itemId'] = now + _cacheMs;
    }
    return item;
  }

  Future<Response> _image(Caller c, Request req) async {
    final id = normalizeItemId(req.params['id']);
    final w = validWidth(req.url.queryParameters['w']);
    if (id == null || w == null) return _err(400, 'bad_request');
    final exp = _visCache['${c.userId}|$id'];
    if ((exp == null || exp <= _clock()) && await _visible(c, id) == null)
      return _err(404, 'not_found');
    final res = await jf.image(id, w);
    final ct = res.headers.contentType;
    if (res.statusCode != 200 || ct == null || ct.primaryType != 'image') {
      await res.drain<void>();
      return _err(404, 'not_found');
    }
    return Response.ok(
      res,
      headers: {
        'content-type': '${ct.primaryType}/${ct.subType}',
        if (res.contentLength >= 0) 'content-length': '${res.contentLength}',
        'cache-control': 'private, max-age=3600',
        'x-content-type-options': 'nosniff',
      },
    );
  }

  Future<Response> _stream(Caller c, Request req) async {
    final id = normalizeItemId(req.params['id']);
    if (id == null) return _err(400, 'bad_request');
    final item = await _visible(c, id);
    if (item == null) return _err(404, 'not_found');
    final type = item['Type'];
    const video = {'Movie', 'Episode', 'Video', 'MusicVideo'};
    if (type != 'Audio' && !video.contains(type))
      return _err(400, 'not_streamable');
    var range = req.headers['range'];
    if (range != null &&
        !RegExp(r'^bytes=[0-9]{0,15}-[0-9]{0,15}$').hasMatch(range))
      range = null;
    final res = await jf.stream(id, type == 'Audio', range);
    if (res.statusCode != 200 &&
        res.statusCode != 206 &&
        res.statusCode != 416) {
      await res.drain<void>();
      return _err(404, 'not_found');
    }
    final ct = res.headers.contentType;
    String? h(String n) => res.headers.value(n);
    return Response(
      res.statusCode,
      body: res,
      headers: {
        'content-type': ct == null
            ? 'application/octet-stream'
            : '${ct.primaryType}/${ct.subType}',
        if (res.contentLength >= 0) 'content-length': '${res.contentLength}',
        'accept-ranges': 'bytes',
        'content-range': ?h('content-range'),
        'cache-control': 'private, no-store',
        'x-content-type-options': 'nosniff',
      },
    );
  }
}

class _BadRequest implements Exception {
  _BadRequest(this.status, this.code);
  final int status;
  final String code;
}
