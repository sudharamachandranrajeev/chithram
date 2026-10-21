import 'dart:convert';

import 'http.dart';

/// Credentials never appear in toString / logs.
class XtreamAccount {
  XtreamAccount({
    required String baseUrl,
    required this.username,
    required this.password,
  }) : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');

  final String baseUrl;
  final String username;
  final String password;

  Uri get _base => Uri.parse(baseUrl);

  /// True when credentials would travel in clear text; UI must warn.
  bool get insecure => _base.scheme == 'http';

  /// Redacted form for logs.
  String get redacted => '${_base.scheme}://${_base.host}';

  @override
  String toString() => 'XtreamAccount($redacted)';
}

class XtreamAuth {
  XtreamAuth({
    required this.authenticated,
    this.status,
    this.expiry,
    this.maxConnections,
    this.activeConnections,
    this.isTrial = false,
    this.serverUrl,
    this.serverPort,
    this.allowedOutputFormats = const [],
  });
  final bool authenticated;
  final String? status;
  final DateTime? expiry;
  final int? maxConnections;
  final int? activeConnections;
  final bool isTrial;
  final String? serverUrl;
  final String? serverPort;
  final List<String> allowedOutputFormats;
}

class XtreamCategory {
  XtreamCategory(this.id, this.name);
  final String id;
  final String name;
}

class XtreamStream {
  XtreamStream({
    required this.id,
    required this.name,
    this.categoryId,
    this.icon,
    this.epgChannelId,
    this.tvArchive = false,
    this.tvArchiveDuration = 0,
    this.containerExtension,
    this.rating,
  });
  final int id;
  final String name;
  final String? categoryId;
  final String? icon;
  final String? epgChannelId;

  /// Server supports timeshift catch-up for this channel.
  final bool tvArchive;
  final int tvArchiveDuration; // days
  final String? containerExtension;
  final String? rating;
}

class XtreamEpgEntry {
  XtreamEpgEntry({
    required this.title,
    required this.description,
    required this.start,
    required this.end,
  });
  final String title;
  final String description;
  final DateTime start;
  final DateTime end;
}

class XtreamClient {
  XtreamClient(this.account, this._http,
      {this.timeout = const Duration(seconds: 20)});
  final XtreamAccount account;
  final IptvHttp _http;
  final Duration timeout;

  Uri _api([Map<String, String> extra = const {}]) {
    final b = Uri.parse(account.baseUrl);
    return b.replace(
      path: '${b.path}/player_api.php',
      queryParameters: {
        'username': account.username,
        'password': account.password,
        ...extra,
      },
    );
  }

  Future<dynamic> _json(Map<String, String> extra) async {
    final r = await _http.open(_api(extra), timeout: timeout);
    if (!r.ok) {
      r.close();
      // Message omits the URL, which carries the credentials.
      throw HttpStatusException(r.status, 'xtream ${account.redacted}');
    }
    return jsonDecode(await readText(r));
  }

  Future<XtreamAuth> authenticate() async {
    final j = await _json(const {});
    final ui = (j is Map ? j['user_info'] : null) as Map?;
    final si = (j is Map ? j['server_info'] : null) as Map?;
    if (ui == null) return XtreamAuth(authenticated: false);
    return XtreamAuth(
      authenticated: _int(ui['auth']) == 1 && ui['status'] != 'Disabled',
      status: ui['status']?.toString(),
      expiry: _epoch(ui['exp_date']),
      maxConnections: _int(ui['max_connections']),
      activeConnections: _int(ui['active_cons']),
      isTrial: _int(ui['is_trial']) == 1,
      serverUrl: si?['url']?.toString(),
      serverPort: si?['port']?.toString(),
      allowedOutputFormats: [
        for (final f in (ui['allowed_output_formats'] as List? ?? const []))
          f.toString(),
      ],
    );
  }

  Future<List<XtreamCategory>> _cats(String action) async {
    final j = await _json({'action': action});
    return [
      if (j is List)
        for (final c in j)
          if (c is Map)
            XtreamCategory(
                c['category_id'].toString(), c['category_name'].toString()),
    ];
  }

  Future<List<XtreamCategory>> liveCategories() => _cats('get_live_categories');
  Future<List<XtreamCategory>> vodCategories() => _cats('get_vod_categories');
  Future<List<XtreamCategory>> seriesCategories() =>
      _cats('get_series_categories');

  Future<List<XtreamStream>> _streams(String action, String? cat,
      {String idKey = 'stream_id'}) async {
    final j = await _json({
      'action': action,
      'category_id': ?cat,
    });
    return [
      if (j is List)
        for (final s in j)
          if (s is Map && _int(s[idKey]) != null)
            XtreamStream(
              id: _int(s[idKey])!,
              name: s['name']?.toString() ?? '',
              categoryId: s['category_id']?.toString(),
              icon: (s['stream_icon'] ?? s['cover'])?.toString(),
              epgChannelId: _str(s['epg_channel_id']),
              tvArchive: _int(s['tv_archive']) == 1,
              tvArchiveDuration: _int(s['tv_archive_duration']) ?? 0,
              containerExtension: _str(s['container_extension']),
              rating: _str(s['rating']),
            ),
    ];
  }

  Future<List<XtreamStream>> liveStreams({String? categoryId}) =>
      _streams('get_live_streams', categoryId);
  Future<List<XtreamStream>> vodStreams({String? categoryId}) =>
      _streams('get_vod_streams', categoryId);
  Future<List<XtreamStream>> series({String? categoryId}) =>
      _streams('get_series', categoryId, idKey: 'series_id');

  /// Short EPG for one stream (titles/descriptions are base64 in the API).
  Future<List<XtreamEpgEntry>> shortEpg(int streamId, {int limit = 4}) async {
    final j = await _json({
      'action': 'get_short_epg',
      'stream_id': '$streamId',
      'limit': '$limit',
    });
    final list = (j is Map ? j['epg_listings'] : null) as List? ?? const [];
    final out = <XtreamEpgEntry>[];
    for (final e in list) {
      if (e is! Map) continue;
      final s = _epoch(e['start_timestamp']);
      final en = _epoch(e['stop_timestamp']);
      if (s == null || en == null) continue;
      out.add(XtreamEpgEntry(
        title: _b64(e['title']),
        description: _b64(e['description']),
        start: s,
        end: en,
      ));
    }
    return out;
  }

  /// URL of the full XMLTV guide (feed to the XMLTV parser).
  Uri get xmltvUrl {
    final b = Uri.parse(account.baseUrl);
    return b.replace(path: '${b.path}/xmltv.php', queryParameters: {
      'username': account.username,
      'password': account.password,
    });
  }

  // ---- stream URL builders ------------------------------------------------

  Uri _path(List<String> segs) {
    final b = Uri.parse(account.baseUrl);
    return b.replace(pathSegments: [
      ...b.pathSegments.where((s) => s.isNotEmpty),
      ...segs,
    ]);
  }

  /// Live: `/live/user/pass/id.m3u8` or `.ts`.
  Uri liveUrl(int streamId, {String ext = 'm3u8'}) =>
      _path(['live', account.username, account.password, '$streamId.$ext']);

  Uri vodUrl(int streamId, {String ext = 'mp4'}) =>
      _path(['movie', account.username, account.password, '$streamId.$ext']);

  Uri seriesEpisodeUrl(int episodeId, {String ext = 'mp4'}) =>
      _path(['series', account.username, account.password, '$episodeId.$ext']);

  /// Timeshift catch-up: `/timeshift/user/pass/<minutes>/<yyyy-MM-dd:HH-mm>/id.ts`
  /// ([start] is converted to UTC; panels differ, this is the common form).
  Uri timeshiftUrl(int streamId,
      {required DateTime start, required Duration duration, String ext = 'ts'}) {
    final u = start.toUtc();
    String p(int n) => n.toString().padLeft(2, '0');
    final stamp = '${u.year}-${p(u.month)}-${p(u.day)}:${p(u.hour)}-${p(u.minute)}';
    return _path([
      'timeshift',
      account.username,
      account.password,
      '${duration.inMinutes}',
      stamp,
      '$streamId.$ext',
    ]);
  }

  static int? _int(Object? v) => v is int ? v : int.tryParse('${v ?? ''}');
  static String? _str(Object? v) {
    final s = v?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }

  static DateTime? _epoch(Object? v) {
    final n = _int(v);
    if (n == null || n <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
  }

  static String _b64(Object? v) {
    try {
      return utf8.decode(base64.decode(base64.normalize('${v ?? ''}')),
          allowMalformed: true);
    } catch (_) {
      return '${v ?? ''}';
    }
  }
}
